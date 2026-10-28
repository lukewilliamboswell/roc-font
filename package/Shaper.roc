import Bytes
import Face
import LayoutCommon
import LayoutGdef
import LayoutGsub
import LayoutKerning
import LayoutVar
import ShaperUse
import ShaperMyanmar
import ShaperKhmer
import ShaperIndicVowels
import ShaperIndic
import ShaperHangul
import ShaperThai
import ShaperArabic
import ShaperArabicFallback
import ShaperArabicStretch
import ShaperNormalize
import ShaperTags
import ShaperUnicode
import Sorted
import TablePost
import TableCmap

## Horizontal OpenType shaping with default, Hebrew, Arabic/Syriac,
## Thai/Lao, Hangul, Indic, Khmer, Myanmar and USE models: choosing
## lookups for a script, language, direction and features (a plan, as
## `hb-ot-map.cc` and `hb-ot-shape.cc` build one), then preparing the text
## (Unicode properties, grapheme clusters, the script's own direction,
## mirroring, normalisation by what the font maps, automatic fractions),
## substituting, positioning (with HarfBuzz's fallbacks for spaces and
## for marks in fonts without `GPOS`) and finishing the run (hiding
## default-ignorable characters, unsafe-to-break flags).
##
## Internal. Horizontal OpenType shaping; vertical text and extra cluster
## levels remain separate work. Features beyond the 27 feature-mask bits
## are dropped as HarfBuzz drops them.
Shaper :: {}.{

	Options : {
		script : Str,
		language : Str,
		direction : [FromScript, LeftToRight, RightToLeft, TopToBottom, BottomToTop],
		features : List({ tag : Str, value : U32, start : U64, end : U64 }),
		growth : U64,
		operations : U64,
	}

	## A plan: the lookups to apply in order with their masks, the mask
	## every glyph starts with and the ranges of text where features that
	## vary are set, the masks the shaper sets itself, the direction, and
	## which of HarfBuzz's fallbacks apply. `mapped`, `gsub_required`,
	## `gsub_required_stage` and `gsub_subs` are what chose the `GSUB`
	## lookups, kept (they are already built) so that `step_features` can
	## name the features of each step for traced shaping.
	Plan : {
		backward : Bool,
		vertical : Bool,
		has_vert : Bool,
		script : U64,
		native : [Ltr, Rtl, Either],
		gsub : List(LayoutGsub.Step),
		gsub_stage_count : U64,
		staged : Staged,
		model : [Indic(ShaperIndic), Khmer(ShaperKhmer), Myanmar(ShaperMyanmar), Use(ShaperUse), Simple],
		zero_marks : [Early, Late, Keep],
		fallback_position : Bool,
		gpos : List({ index : U64, mask : U64 }),
		gpos_auto_zwj : List(Bool),
		kern : [Kern(U64), NoKern],
		global_mask : U64,
		ranges : List({ mask : U64, value : U64, start : U64, end : U64 }),
		frac_mask : U64,
		numr_mask : U64,
		dnom_mask : U64,
		rtlm_mask : U64,
		hebrew : Bool,
		arabic : Bool,
		thai : Bool,
		hangul : Bool,
		hangul_masks : ShaperHangul.Masks,
		thai_legacy : Bool,
		arabic_masks : ShaperArabic.Masks,
		arabic_fallback : ShaperArabicFallback,
		arabic_stch : Bool,
		characters : Bool,
		has_gpos_mark : Bool,
		fallback_marks : Bool,
		growth : U64,
		operations : U64,
		mapped : List(Mapped),
		gsub_required : U64,
		gsub_required_stage : U64,
		gsub_subs : List({ feature : U64, table : U64 }),
		gsub_lookup_vars : List({ feature : U64, defaults : Bool, lookups : List(U64) }),
	}

	Run : { glyphs : List(U32), advances : List({ x : I32, y : I32 }), offsets : List({ x : I32, y : I32 }), clusters : List(U64), flags : List(U8) }

	## A shaped run with the finished items it was made from (in output
	## order, for origins) and the bounds that stopped substitution
	## (`LayoutGsub.Applied`; 0 when none did).
	Shaped : { run : Run, items : List(LayoutGsub.Item), stopped : U64, aborted : Bool }

	## The end of a feature range that runs to the end of the text (every
	## offset is below it): with start 0, a feature over the whole text.
	text_end : U64
	text_end = 0xFFFFFFFFFFFFFFFF

	## A requested feature (HarfBuzz's `feature_info_t`): its largest and
	## default values, whether it is global, falls back to `kern`, joins
	## manually (mark positioning) or is `rand`, and its `GSUB` stage.
	Request : { tag : U64, max : U64, default : U64, global : Bool, fallback : Bool, manual : Bool, random : Bool, stage : U64 }

	## A feature given mask bits (HarfBuzz's `feature_map_t`).
	Mapped : { tag : U64, gsub : U64, gpos : U64, stage : U64, mask : U64, shift : U64, manual : Bool, random : Bool }

	## HarfBuzz's global mask bit, and the bits feature values may use
	## (bits 0 to 3 hold glyph flags in HarfBuzz).
	global_bit : U64
	global_bit = 0x80000000

	first_bit : U64
	first_bit = 4

	global_shift : U64
	global_shift = 31

	empty_run : Run
	empty_run = { glyphs: [], advances: [], offsets: [], clusters: [], flags: [] }

	tag : Str -> U64
	tag = |name| ShaperTags.tag_of(name)

	# ------------------------------------------------------------ planning

	## A feature tag from a string: up to four bytes, padded with spaces.
	feature_tag : Str -> U64
	feature_tag = |name| ShaperTags.tag_from_bytes(name.to_utf8())

	request : Str, U64, Bool -> Request
	request = |name, value, global| { tag: Shaper.tag(name), max: value, default: if (global) value else 0, global, fallback: False, manual: False, random: False, stage: 1 }

	## The features HarfBuzz's default shaper asks for, in the order it adds
	## them, for left-to-right and right-to-left text. Made once, when the
	## program is compiled, as is everything below that only depends on
	## them, so planning with the default features builds no requests.
	default_requests : [Ltr, Rtl] -> List(Request)
	default_requests = |direction| {
		direction_features = match direction {
			Ltr => [Shaper.request("ltra", 1, True), Shaper.request("ltrm", 1, True)]
			Rtl => [Shaper.request("rtla", 1, True), Shaper.request("rtlm", 1, False)]
		}
		fractions = [Shaper.request("frac", 1, False), Shaper.request("numr", 1, False), Shaper.request("dnom", 1, False)]
		random = [{ ..Shaper.request("rand", 255, True), random: True }]
		markers = ["Harf", "HARF", "Buzz", "BUZZ"].map(|t| Shaper.request(t, 1, True))
		common = ["abvm", "blwm", "ccmp", "locl"].map(|t| Shaper.request(t, 1, True)).concat(["mark", "mkmk"].map(|t| { ..Shaper.request(t, 1, True), manual: True })).append(Shaper.request("rlig", 1, True))
		horizontal = ["calt", "clig", "curs", "dist"].map(|t| Shaper.request(t, 1, True)).append({ ..Shaper.request("kern", 1, True), fallback: True }).concat(["liga", "rclt"].map(|t| Shaper.request(t, 1, True)))
		[{ ..Shaper.request("rvrn", 1, True), stage: 0 }].concat(direction_features).concat(fractions).concat(random).concat(markers).concat(common).concat(horizontal)
	}

	hangul_requests : [Ltr, Rtl] -> List(Request)
	hangul_requests = |direction| Shaper.default_requests(direction).map(|r| if (r.tag == Shaper.tag("calt")) { ..r, global: False, default: 1 } else r).concat(["ljmo", "vjmo", "tjmo"].map(|name| Shaper.request(name, 1, False)))

	hangul_ltr_merged : List(Request)
	hangul_ltr_merged = Shaper.merge(Shaper.sort_by_tag(Shaper.hangul_requests(Ltr)))
	hangul_rtl_merged : List(Request)
	hangul_rtl_merged = Shaper.merge(Shaper.sort_by_tag(Shaper.hangul_requests(Rtl)))
	hangul_ltr_keys : List(U64)
	hangul_ltr_keys = LayoutCommon.feature_keys(Shaper.hangul_ltr_merged.map(|f| f.tag))
	hangul_rtl_keys : List(U64)
	hangul_rtl_keys = LayoutCommon.feature_keys(Shaper.hangul_rtl_merged.map(|f| f.tag))

	indic_scripts : List(U64)
	indic_scripts = ["Deva", "Beng", "Gujr", "Guru", "Knda", "Mlym", "Orya", "Taml", "Telu"].map(Shaper.tag)

	indic_requests : [Ltr, Rtl] -> List(Request)
	indic_requests = |direction| Shaper.default_requests(direction).map(|r| { ..r, stage: ShaperIndic.stage(r.tag) }).concat(ShaperIndic.features.map(|f| { tag: f.tag, max: f.default, default: if (f.global) f.default else 0, global: f.global, fallback: False, manual: f.manual_zwj, random: False, stage: f.stage })).append({ ..Shaper.request("liga", 0, True), stage: 14 })
	indic_ltr_merged : List(Request)
	indic_ltr_merged = Shaper.merge(Shaper.sort_by_tag(Shaper.indic_requests(Ltr)))
	indic_rtl_merged : List(Request)
	indic_rtl_merged = Shaper.merge(Shaper.sort_by_tag(Shaper.indic_requests(Rtl)))
	indic_ltr_keys : List(U64)
	indic_ltr_keys = LayoutCommon.feature_keys(Shaper.indic_ltr_merged.map(|f| f.tag))
	indic_rtl_keys : List(U64)
	indic_rtl_keys = LayoutCommon.feature_keys(Shaper.indic_rtl_merged.map(|f| f.tag))

	khmer_requests : [Ltr, Rtl] -> List(Request)
	khmer_requests = |direction| Shaper.default_requests(direction).map(|r| { ..r, stage: ShaperKhmer.stage(r.tag) }).concat(ShaperKhmer.features.map(|f| { tag: f.tag, max: f.default, default: if (f.global) f.default else 0, global: f.global, fallback: False, manual: f.manual_zwj, random: False, stage: f.stage })).append({ ..Shaper.request("liga", 0, True), stage: 3 }).append({ ..Shaper.request("clig", 1, True), stage: 3 })
	khmer_ltr_merged : List(Request)
	khmer_ltr_merged = Shaper.merge(Shaper.sort_by_tag(Shaper.khmer_requests(Ltr)))
	khmer_rtl_merged : List(Request)
	khmer_rtl_merged = Shaper.merge(Shaper.sort_by_tag(Shaper.khmer_requests(Rtl)))
	khmer_ltr_keys : List(U64)
	khmer_ltr_keys = LayoutCommon.feature_keys(Shaper.khmer_ltr_merged.map(|f| f.tag))
	khmer_rtl_keys : List(U64)
	khmer_rtl_keys = LayoutCommon.feature_keys(Shaper.khmer_rtl_merged.map(|f| f.tag))

	myanmar_requests : [Ltr, Rtl] -> List(Request)
	myanmar_requests = |direction| Shaper.default_requests(direction).map(|r| { ..r, stage: ShaperMyanmar.stage(r.tag) }).concat(ShaperMyanmar.features.map(|f| { tag: f.tag, max: f.default, default: if (f.global) f.default else 0, global: f.global, fallback: False, manual: f.manual_zwj, random: False, stage: f.stage }))
	myanmar_ltr_merged : List(Request)
	myanmar_ltr_merged = Shaper.merge(Shaper.sort_by_tag(Shaper.myanmar_requests(Ltr)))
	myanmar_rtl_merged : List(Request)
	myanmar_rtl_merged = Shaper.merge(Shaper.sort_by_tag(Shaper.myanmar_requests(Rtl)))
	myanmar_ltr_keys : List(U64)
	myanmar_ltr_keys = LayoutCommon.feature_keys(Shaper.myanmar_ltr_merged.map(|f| f.tag))
	myanmar_rtl_keys : List(U64)
	myanmar_rtl_keys = LayoutCommon.feature_keys(Shaper.myanmar_rtl_merged.map(|f| f.tag))

	use_requests : [Ltr, Rtl] -> List(Request)
	use_requests = |direction| Shaper.default_requests(direction).map(|r| { ..r, stage: ShaperUse.stage(r.tag) }).concat(ShaperUse.features.map(|f| { tag: f.tag, max: f.default, default: if (f.global) f.default else 0, global: f.global, fallback: False, manual: f.manual_zwj, random: False, stage: f.stage }))
	use_ltr_merged : List(Request)
	use_ltr_merged = Shaper.merge(Shaper.sort_by_tag(Shaper.use_requests(Ltr)))
	use_rtl_merged : List(Request)
	use_rtl_merged = Shaper.merge(Shaper.sort_by_tag(Shaper.use_requests(Rtl)))
	use_ltr_keys : List(U64)
	use_ltr_keys = LayoutCommon.feature_keys(Shaper.use_ltr_merged.map(|f| f.tag))
	use_rtl_keys : List(U64)
	use_rtl_keys = LayoutCommon.feature_keys(Shaper.use_rtl_merged.map(|f| f.tag))

	ltr_requests : List(Request)
	ltr_requests = Shaper.default_requests(Ltr)

	rtl_requests : List(Request)
	rtl_requests = Shaper.default_requests(Rtl)

	## The default requests merged, for a plan without features of the
	## caller's (HarfBuzz merges them unsorted then: their tags differ).
	ltr_merged : List(Request)
	ltr_merged = Shaper.merge(Shaper.ltr_requests)

	rtl_merged : List(Request)
	rtl_merged = Shaper.merge(Shaper.rtl_requests)

	## Each default merged request's tag as a key for
	## `LayoutCommon.find_features`.
	ltr_keys : List(U64)
	ltr_keys = LayoutCommon.feature_keys(Shaper.ltr_merged.map(|f| f.tag))

	rtl_keys : List(U64)
	rtl_keys = LayoutCommon.feature_keys(Shaper.rtl_merged.map(|f| f.tag))

	arabic_requests : [Ltr, Rtl] -> List(Request)
	arabic_requests = |direction| {
		base = Shaper.default_requests(direction).map(|r| { ..r, stage: ShaperArabic.stage(r.tag), manual: r.manual or ShaperArabic.manual_zwj(r.tag), fallback: r.fallback or r.tag == Shaper.tag("rlig") })
		forms = ShaperArabic.form_names.map(
			|name| {
				r = Shaper.request(name, 1, False)
				{ ..r, stage: ShaperArabic.stage(r.tag), manual: True, fallback: name == "init" or name == "medi" or name == "fina" or name == "isol" }
			},
		)
		base.concat(forms).append({ ..Shaper.request("mset", 1, True), stage: 12, manual: True }).append({ ..Shaper.request("stch", 1, True), stage: 1 })
	}
	syriac_requests : [Ltr, Rtl] -> List(Request)
	syriac_requests = |direction| Shaper.arabic_requests(direction).map(|r| if (ShaperArabic.form_names.any(|name| r.tag == Shaper.tag(name))) { ..r, fallback: False } else r)
	syriac_ltr_merged : List(Request)
	syriac_ltr_merged = Shaper.merge(Shaper.sort_by_tag(Shaper.syriac_requests(Ltr)))
	syriac_rtl_merged : List(Request)
	syriac_rtl_merged = Shaper.merge(Shaper.sort_by_tag(Shaper.syriac_requests(Rtl)))

	arabic_ltr_merged : List(Request)
	arabic_ltr_merged = Shaper.merge(Shaper.sort_by_tag(Shaper.arabic_requests(Ltr)))
	arabic_rtl_merged : List(Request)
	arabic_rtl_merged = Shaper.merge(Shaper.sort_by_tag(Shaper.arabic_requests(Rtl)))
	arabic_ltr_keys : List(U64)
	arabic_ltr_keys = LayoutCommon.feature_keys(Shaper.arabic_ltr_merged.map(|f| f.tag))
	arabic_rtl_keys : List(U64)
	arabic_rtl_keys = LayoutCommon.feature_keys(Shaper.arabic_rtl_merged.map(|f| f.tag))

	hebrew_script : U64
	hebrew_script = Shaper.tag("Hebr")

	hebrew_tag : U64
	hebrew_tag = Shaper.tag("hebr")

	kern_tag : U64
	kern_tag = Shaper.tag("kern")

	frac_tag : U64
	frac_tag = Shaper.tag("frac")

	numr_tag : U64
	numr_tag = Shaper.tag("numr")

	dnom_tag : U64
	dnom_tag = Shaper.tag("dnom")

	rtlm_tag : U64
	rtlm_tag = Shaper.tag("rtlm")

	mark_tag : U64
	mark_tag = Shaper.tag("mark")

	plan : Face, Options -> Plan
	plan = |face, options| Shaper.plan_with_clusters(face, options, Graphemes)

	## A plan at a cluster level: `Graphemes` (HarfBuzz's level 0, monotone
	## graphemes: a grapheme's characters share its first character's
	## cluster) or `Characters` (level 1, monotone characters: each
	## character keeps its own cluster, and only substitutions merge them).
	plan_with_clusters : Face, Options, [Graphemes, Characters] -> Plan
	plan_with_clusters = |face, options, clusters| {
		vertical = options.direction == TopToBottom or options.direction == BottomToTop
		native = ShaperTags.script_direction(options.script)
		requested = match options.direction {
			LeftToRight | TopToBottom => Ltr
			RightToLeft | BottomToTop => Rtl
			FromScript =>
				match native {
					Rtl => Rtl
					_ => Ltr
				}
		}
		lang = ShaperTags.language_tags(options.language)
		script_tags = match lang.scripts {
			Given(t) => [t]
			NotGiven => ShaperTags.script_tags(options.script)
		}
		gsub_table = Face.gsub(face)
		gsub_common = LayoutGsub.common_of(gsub_table)
		kerning = Face.kerning(face)
		gpos_common = LayoutKerning.common_of(kerning)
		hebrew = !options.script.is_empty() and ShaperTags.script_of(options.script) == Shaper.hebrew_script
		chosen_script = LayoutCommon.select_script_tag(gsub_common, script_tags)
		indic = Shaper.indic_scripts.contains(ShaperTags.script_of(options.script)) and chosen_script != Shaper.tag("DFLT") and chosen_script != Shaper.tag("latn") and chosen_script.bitwise_and(0xFF) != '3'
		use_model = ShaperUse.selected(ShaperTags.script_of(options.script), chosen_script)
		myanmar = ShaperTags.script_of(options.script) == Shaper.tag("Mymr") and chosen_script != Shaper.tag("DFLT") and chosen_script != Shaper.tag("latn") and chosen_script != Shaper.tag("mymr")
		khmer = ShaperTags.script_of(options.script) == Shaper.tag("Khmr")
		hangul = ShaperTags.script_of(options.script) == Shaper.tag("Hang")
		syriac = ShaperTags.script_of(options.script) == Shaper.tag("Syrc")
		arabic = ShaperTags.script_of(options.script) == Shaper.tag("Arab") or (ShaperTags.script_of(options.script) == Shaper.tag("Syrc") and chosen_script != Shaper.tag("DFLT"))
		# The features HarfBuzz's default shaper asks for, then the caller's.
		merged =
			if vertical {
				model_defaults = if (use_model) Shaper.use_requests(Ltr) else if (myanmar) Shaper.myanmar_requests(Ltr) else if (khmer) Shaper.khmer_requests(Ltr) else if (indic) Shaper.indic_requests(Ltr) else if (arabic) Shaper.arabic_requests(Ltr) else if (hangul) Shaper.hangul_requests(Ltr) else Shaper.ltr_requests
				removed = ["ltra", "ltrm", "rtla", "rtlm", "calt", "clig", "curs", "dist", "kern", "liga", "rclt"].map(Shaper.tag)
				stage = if (use_model) 7 else if (myanmar) 7 else if (indic) 14 else if (khmer) 3 else if (arabic) 12 else 1
				var $requests = model_defaults.keep_if(|r| !removed.contains(r.tag)).append({ ..Shaper.request("vert", 1, True), stage })
				for f in options.features {
					global = f.start == 0 and f.end == Shaper.text_end
					$requests = $requests.append({ ..Shaper.request(f.tag, f.value.to_u64(), global), stage })
				}
				Shaper.merge(Shaper.sort_by_tag($requests))
			} else if options.features.is_empty() and !vertical {
				match requested {
					Ltr => if (use_model) Shaper.use_ltr_merged else if (myanmar) Shaper.myanmar_ltr_merged else if (khmer) Shaper.khmer_ltr_merged else if (indic) Shaper.indic_ltr_merged else if (arabic) if (syriac) Shaper.syriac_ltr_merged else Shaper.arabic_ltr_merged else if (hangul) Shaper.hangul_ltr_merged else Shaper.ltr_merged
					Rtl => if (use_model) Shaper.use_rtl_merged else if (myanmar) Shaper.myanmar_rtl_merged else if (khmer) Shaper.khmer_rtl_merged else if (indic) Shaper.indic_rtl_merged else if (arabic) if (syriac) Shaper.syriac_rtl_merged else Shaper.arabic_rtl_merged else if (hangul) Shaper.hangul_rtl_merged else Shaper.rtl_merged
				}
			} else {
				defaults = match requested {
					Ltr => if (use_model) Shaper.use_requests(Ltr) else if (myanmar) Shaper.myanmar_requests(Ltr) else if (khmer) Shaper.khmer_requests(Ltr) else if (indic) Shaper.indic_requests(Ltr) else if (arabic) if (syriac) Shaper.syriac_requests(Ltr) else Shaper.arabic_requests(Ltr) else if (hangul) Shaper.hangul_requests(Ltr) else Shaper.ltr_requests
					Rtl => if (use_model) Shaper.use_requests(Rtl) else if (myanmar) Shaper.myanmar_requests(Rtl) else if (khmer) Shaper.khmer_requests(Rtl) else if (indic) Shaper.indic_requests(Rtl) else if (arabic) if (syriac) Shaper.syriac_requests(Rtl) else Shaper.arabic_requests(Rtl) else if (hangul) Shaper.hangul_requests(Rtl) else Shaper.rtl_requests
				}
				var $requests = List.with_capacity(defaults.len() + options.features.len())
				$requests = $requests.concat(defaults)
				for f in options.features {
					global = f.start == 0 and f.end == Shaper.text_end
					v = f.value.to_u64()
					$requests = $requests.append({ tag: Shaper.feature_tag(f.tag), max: v, default: if (global) v else 0, global, fallback: False, manual: False, random: False, stage: if (use_model) ShaperUse.stage(Shaper.feature_tag(f.tag)) else if (myanmar) ShaperMyanmar.stage(Shaper.feature_tag(f.tag)) else if (khmer) ShaperKhmer.stage(Shaper.feature_tag(f.tag)) else if (indic) ShaperIndic.stage(Shaper.feature_tag(f.tag)) else if (arabic) ShaperArabic.stage(Shaper.feature_tag(f.tag)) else 1 })
				}
				# Hangul keeps calt in its own bit even after a global user setting.
				if hangul {
					$requests = $requests.append(Shaper.request("calt", 1, False))
				}
				Shaper.merge(Shaper.sort_by_tag($requests))
			}
		keys =
			if options.features.is_empty() and !vertical {
				match requested {
					Ltr => if (use_model) Shaper.use_ltr_keys else if (myanmar) Shaper.myanmar_ltr_keys else if (khmer) Shaper.khmer_ltr_keys else if (indic) Shaper.indic_ltr_keys else if (arabic) Shaper.arabic_ltr_keys else if (hangul) Shaper.hangul_ltr_keys else Shaper.ltr_keys
					Rtl => if (use_model) Shaper.use_rtl_keys else if (myanmar) Shaper.myanmar_rtl_keys else if (khmer) Shaper.khmer_rtl_keys else if (indic) Shaper.indic_rtl_keys else if (arabic) Shaper.arabic_rtl_keys else if (hangul) Shaper.hangul_rtl_keys else Shaper.rtl_keys
				}
			} else {
				LayoutCommon.feature_keys(merged.map(|f| f.tag))
			}
		gsub_langsys = LayoutCommon.select_langsys(gsub_common, LayoutCommon.select_script(gsub_common, script_tags), lang.languages)
		gpos_langsys = LayoutCommon.select_langsys(gpos_common, LayoutCommon.select_script(gpos_common, script_tags), lang.languages)
		gsub_required = LayoutCommon.required_feature(gsub_common, gsub_langsys)
		gpos_required = LayoutCommon.required_feature(gpos_common, gpos_langsys)
		gsub_required_tag = if (gsub_required == LayoutCommon.no_feature) 0 else LayoutCommon.feature_tag(gsub_common, gsub_required)
		# Each request's feature in each table, found in one pass over each
		# language system.
		gsub_found = LayoutCommon.find_features(gsub_common, gsub_langsys, keys)
		gpos_found = LayoutCommon.find_features(gpos_common, gpos_langsys, keys)
		# Allocate mask bits as HarfBuzz's map builder does.
		var $mapped = List.with_capacity(merged.len())
		var $next_bit = Shaper.first_bit
		var $global_mask = Shaper.global_bit
		var $gsub_required_stage = 0
		for k in 0..<merged.len() {
			f = merged.get(k) ?? Shaper.request("", 0, False)
			bits = if (f.global and f.max == 1) 0 else Shaper.bit_storage(f.max).min(8)
			if f.max != 0 and $next_bit + bits < Shaper.global_shift {
				if gsub_required_tag == f.tag {
					$gsub_required_stage = f.stage
				}
				selected_sub = gsub_found.get(k) ?? LayoutCommon.no_feature
				selected_pos = gpos_found.get(k) ?? LayoutCommon.no_feature
				global_search = vertical and f.tag == Shaper.tag("vert") and selected_sub == LayoutCommon.no_feature and selected_pos == LayoutCommon.no_feature
				gsub_index = if (global_search) Shaper.global_feature(gsub_common, f.tag) else selected_sub
				gpos_index = if (global_search) Shaper.global_feature(gpos_common, f.tag) else selected_pos
				found = gsub_index != LayoutCommon.no_feature or gpos_index != LayoutCommon.no_feature
				if found or f.fallback {
					{ shift, mask } =
						if f.global and f.max == 1 {
							{ shift: Shaper.global_shift, mask: Shaper.global_bit }
						} else {
							s = $next_bit
							m = (1.U64).shl_wrap((s + bits).to_u8_wrap()) - (1.U64).shl_wrap(s.to_u8_wrap())
							$next_bit = $next_bit + bits
							$global_mask = $global_mask.bitwise_or(f.default.shl_wrap(s.to_u8_wrap()).bitwise_and(m))
							{ shift: s, mask: m }
						}
					$mapped = $mapped.append({ tag: f.tag, gsub: gsub_index, gpos: gpos_index, stage: f.stage, mask, shift, manual: f.manual, random: f.random })
				}
			}
		}
		# The Arabic shaper merges calt and the final group when rclt exists.
		if arabic and $mapped.any(|m| m.tag == Shaper.tag("rclt") and m.gsub != LayoutCommon.no_feature) {
			for i in 0..<$mapped.len() {
				m = $mapped.get(i) ?? { tag: 0, gsub: LayoutCommon.no_feature, gpos: LayoutCommon.no_feature, stage: 0, mask: 0, shift: 0, manual: False, random: False }
				if m.stage == 12 {
					$mapped = $mapped.set(i, { ..m, stage: 11 }) ?? []
				}
			}
			if $gsub_required_stage == 12 {
				$gsub_required_stage = 11
			}
		}
		mapped = $mapped
		mask_of = |wanted|
			match mapped.find_first(|m| m.tag == wanted) {
				Ok(m) => m.mask
				Err(_) => 0
			}
		one_mask_of = |wanted|
			match mapped.find_first(|m| m.tag == wanted) {
				Ok(m) => (1.U64).shl_wrap(m.shift.to_u8_wrap()).bitwise_and(m.mask)
				Err(_) => 0
			}
		# Feature variations at the face's location replace the lookups of
		# the features they name (HarfBuzz's `variations_index`).
		variations = Face.feature_variations(face)
		gsub_varied = { subs: LayoutVar.substitutions_at(variations.gsub, variations.lv, variations.coords), fv: variations.gsub, lookup_vars: LayoutVar.lookup_variations_at(variations.gsub, variations.lv, variations.coords) }
		gpos_varied = { subs: LayoutVar.substitutions_at(variations.gpos, variations.lv, variations.coords), fv: variations.gpos, lookup_vars: LayoutVar.lookup_variations_at(variations.gpos, variations.lv, variations.coords) }
		arabic_masks = if (arabic) { isol: one_mask_of(Shaper.tag("isol")), fina: one_mask_of(Shaper.tag("fina")), fin2: one_mask_of(Shaper.tag("fin2")), fin3: one_mask_of(Shaper.tag("fin3")), medi: one_mask_of(Shaper.tag("medi")), med2: one_mask_of(Shaper.tag("med2")), init: one_mask_of(Shaper.tag("init")) } else ShaperArabic.no_masks
		fallback = arabic and ShaperTags.script_of(options.script) == Shaper.tag("Arab") and ["isol", "fina", "medi", "init"].all(|name| mapped.any(|m| m.tag == Shaper.tag(name) and m.gsub == LayoutCommon.no_feature))
		arabic_fallback = if (fallback) ShaperArabicFallback.make(face, arabic_masks, one_mask_of(Shaper.tag("rlig"))) else ShaperArabicFallback.none
		stage_count = if (use_model) 8 else if (myanmar) 8 else if (khmer) 4 else if (indic) 16 else if (arabic) 13 else 2
		staged = if (indic or khmer or myanmar or use_model or !ShaperArabicFallback.credits(arabic_fallback).is_empty() or (arabic and one_mask_of(Shaper.tag("stch")) != 0)) Shaper.staged_lookups(gsub_common, gsub_required, $gsub_required_stage, mapped, stage_count, gsub_varied, if (use_model) ShaperUse.features else if (myanmar) ShaperMyanmar.features else if (khmer) ShaperKhmer.features else if (indic) ShaperIndic.features else []) else { steps: [], spans: [] }
		gsub = if (indic or khmer or myanmar or use_model) staged.steps.map(|step| step.step) else Shaper.lookups(gsub_common, gsub_required, $gsub_required_stage, mapped, stage_count, Gsub, gsub_varied, arabic)
		model = if use_model {
			Use(ShaperUse.make({ script: ShaperTags.script_of(options.script), rphf_mask: one_mask_of(Shaper.tag("rphf")), joining_masks: { isol: one_mask_of(Shaper.tag("isol")), fina: one_mask_of(Shaper.tag("fina")), fin2: one_mask_of(Shaper.tag("fin2")), fin3: one_mask_of(Shaper.tag("fin3")), medi: one_mask_of(Shaper.tag("medi")), med2: one_mask_of(Shaper.tag("med2")), init: one_mask_of(Shaper.tag("init")) }, arabic_joining: ShaperUse.has_arabic_joining(ShaperTags.script_of(options.script)), global_mask: $global_mask }))
		} else if myanmar {
			Myanmar(ShaperMyanmar.make({}))
		} else if khmer {
			Khmer(ShaperKhmer.make({ masks: { pref: one_mask_of(Shaper.tag("pref")), blwf: one_mask_of(Shaper.tag("blwf")), abvf: one_mask_of(Shaper.tag("abvf")), pstf: one_mask_of(Shaper.tag("pstf")), cfar: one_mask_of(Shaper.tag("cfar")) } }))
		} else if indic {
			var $probe_lookups = []
			var $probe_spans = []
			for name in ["rphf", "pref", "blwf", "pstf", "vatu"] {
				start = $probe_lookups.len()
				match mapped.find_first(|m| m.tag == Shaper.tag(name)) {
					Ok(m) if m.gsub != LayoutCommon.no_feature => {
						$probe_lookups = $probe_lookups.concat(Shaper.varied_feature_lookups(gsub_common, gsub_varied, m.gsub))
					}
					_ => {}
				}
				$probe_spans = $probe_spans.append({ start, end: $probe_lookups.len() })
			}
			chosen = LayoutCommon.select_script_tag(gsub_common, script_tags)
			script = ShaperTags.script_of(options.script)
			Indic(ShaperIndic.make({ script, old_spec: chosen.bitwise_and(0xFF) != '2' and chosen.bitwise_and(0xFF) != '3', virama_glyph: Face.glyph(face, ShaperIndic.virama(script).to_u32_wrap()) ?? 0, masks: { rphf: one_mask_of(Shaper.tag("rphf")), pref: one_mask_of(Shaper.tag("pref")), blwf: one_mask_of(Shaper.tag("blwf")), abvf: one_mask_of(Shaper.tag("abvf")), half: one_mask_of(Shaper.tag("half")), pstf: one_mask_of(Shaper.tag("pstf")), init: one_mask_of(Shaper.tag("init")) }, probe_lookups: $probe_lookups, probe_spans: $probe_spans }))
		} else Simple
		# HarfBuzz's Hebrew shaper uses `GPOS` only when it has the `hebr`
		# script.
		disable_gpos = hebrew and LayoutCommon.select_script_tag(gpos_common, script_tags) != Shaper.hebrew_tag
		apply_gpos = LayoutKerning.has_gpos(kerning) and !disable_gpos
		gpos_steps =
			if apply_gpos {
				Shaper.lookups(gpos_common, gpos_required, 0, mapped, 1, Gpos, gpos_varied, arabic)
			} else {
				[]
			}
		gpos_auto_zwj = if (gpos_steps.any(|s| !s.auto_zwj)) gpos_steps.map(|s| s.auto_zwj) else []
		# Consume the temporary steps last so map can reuse their allocation.
		gpos = gpos_steps.map(|s| { index: s.index, mask: s.mask })
		kern_mask = mask_of(Shaper.kern_tag)
		has_gpos_kern = match mapped.find_first(|m| m.tag == Shaper.kern_tag) {
			Ok(m) => m.gpos != LayoutCommon.no_feature
			Err(_) => False
		}
		fallback_position = !use_model and !myanmar and !indic and !khmer and ShaperTags.script_of(options.script) != Shaper.tag("Thai") and ShaperTags.script_of(options.script) != Shaper.tag("Laoo")
		# Legacy kern follows the shaper's fallback positioning policy;
		# prepared GPOS lookups above remain independent of this fallback.
		apply_kern = !vertical and fallback_position and (!has_gpos_kern or !apply_gpos) and LayoutKerning.has_kern(kerning)
		kern = if (apply_kern and kern_mask != 0) Kern(kern_mask) else NoKern
		# Ranges, in the caller's order: a later one wins where they overlap.
		var $ranges = []
		for f in options.features {
			if !(f.start == 0 and f.end == Shaper.text_end) {
				t = Shaper.feature_tag(f.tag)
				match mapped.find_first(|m| m.tag == t) {
					Ok(m) => {
						$ranges = $ranges.append({ mask: m.mask, value: f.value.to_u64().shl_wrap(m.shift.to_u8_wrap()).bitwise_and(m.mask), start: f.start, end: f.end })
					}
					Err(_) => {}
				}
			}
		}
		{
			backward: requested == Rtl,
			vertical,
			has_vert: mapped.any(|m| m.tag == Shaper.tag("vert") and m.mask != 0),
			script: ShaperTags.script_of(options.script),
			native,
			gsub,
			gsub_stage_count: stage_count,
			staged,
			model,
			zero_marks: if (myanmar or use_model) Early else if (indic or khmer or hangul) Keep else Late,
			fallback_position,
			gpos,
			gpos_auto_zwj,
			kern,
			global_mask: $global_mask,
			ranges: $ranges,
			frac_mask: one_mask_of(Shaper.frac_tag),
			numr_mask: one_mask_of(Shaper.numr_tag),
			dnom_mask: one_mask_of(Shaper.dnom_tag),
			rtlm_mask: one_mask_of(Shaper.rtlm_tag),
			hebrew,
			arabic,
			hangul,
			hangul_masks: if (hangul) { ljmo: one_mask_of(Shaper.tag("ljmo")), vjmo: one_mask_of(Shaper.tag("vjmo")), tjmo: one_mask_of(Shaper.tag("tjmo")), calt: one_mask_of(Shaper.tag("calt")) } else ShaperHangul.no_masks,
			thai: ShaperTags.script_of(options.script) == Shaper.tag("Thai") or ShaperTags.script_of(options.script) == Shaper.tag("Laoo"),
			thai_legacy: ShaperTags.script_of(options.script) == Shaper.tag("Thai") and LayoutCommon.select_script_tag(gsub_common, script_tags) != Shaper.tag("thai"),
			arabic_masks,
			arabic_fallback,
			arabic_stch: arabic and one_mask_of(Shaper.tag("stch")) != 0,
			characters: clusters == Characters,
			has_gpos_mark: one_mask_of(Shaper.mark_tag) != 0,
			# HarfBuzz positions marks itself when nothing else does: no
			# `GPOS` and no `kern` with cross-stream kerning (which
			# roc-font does not read).
			fallback_marks: !apply_gpos,
			growth: options.growth,
			operations: options.operations,
			mapped,
			gsub_required,
			gsub_required_stage: $gsub_required_stage,
			gsub_subs: gsub_varied.subs,
			gsub_lookup_vars: gsub_varied.lookup_vars,
		}
	}

	## The bits a value needs.
	bit_storage : U64 -> U64
	bit_storage = |v| {
		var $n = 0
		var $x = v
		while $x != 0 {
			$x = $x.shr_zf_wrap(1)
			$n = $n + 1
		}
		$n
	}

	## Requests sorted by tag, keeping the order of requests for one tag
	## (HarfBuzz sorts by tag, then by the order of adding): sorted as
	## `tag << 32 | position` keys (a tag is four bytes), then gathered.
	sort_by_tag : List(Request) -> List(Request)
	sort_by_tag = |requests| {
		keys = Sorted.sort(requests.map_with_index(|r, i| r.tag.shl_wrap(32).bitwise_or(i.bitwise_and(0xFFFFFFFF))))
		var $out = List.with_capacity(requests.len())
		for key in keys {
			match requests.get(key.bitwise_and(0xFFFFFFFF)) {
				Ok(r) => {
					$out = $out.append(r)
				}
				Err(_) => {}
			}
		}
		$out
	}

	## Merge adjacent requests for one tag, as HarfBuzz's map builder merges
	## them: a global request sets the value everywhere, a ranged one makes
	## the feature vary and raises its largest value; the earliest stage
	## wins.
	merge : List(Request) -> List(Request)
	merge = |requests| {
		var $out = []
		for r in requests {
			match $out.last() {
				Ok(m) if m.tag == r.tag => {
					updated =
						if r.global {
							{ ..m, global: True, max: r.max, default: r.default, fallback: m.fallback or r.fallback, stage: m.stage.min(r.stage) }
						} else {
							{ ..m, global: False, max: m.max.max(r.max), fallback: m.fallback or r.fallback, stage: m.stage.min(r.stage) }
						}
					# The list is not empty: it holds `m`.
					$out = $out.set($out.len() - 1, updated) ?? []
				}
				_ => {
					$out = $out.append(r)
				}
			}
		}
		$out
	}

	## What feature variations do at the face's location to one layout
	## table's features: the feature table substitutions in force (`subs`,
	## alternate tables in `fv`) and the lookup variation records in force
	## (`lookup_vars`).
	Varied : { subs : List({ feature : U64, table : U64 }), fv : LayoutVar.FeatureVariations, lookup_vars : List({ feature : U64, defaults : Bool, lookups : List(U64) }) }

	## The lookups of feature `index` at the face's location: its own, or
	## its alternate feature table's when a substitution is in force, then
	## as the first lookup variation record in force for it has them
	## (replaced, or extended when the record keeps them). Only indices
	## below the table's lookup count are kept.
	varied_feature_lookups : LayoutCommon, Varied, U64 -> List(U64)
	varied_feature_lookups = |common, varied, index| {
		own = match varied.subs.find_first(|v| v.feature == index) {
			Ok(v) => LayoutVar.lookups_of(varied.fv, v.table)
			Err(_) => LayoutCommon.feature_lookups(common, index)
		}
		if varied.lookup_vars.is_empty() {
			own.keep_if(|l| l < common.lookup_count)
		} else {
			LayoutVar.varied_lookups(varied.lookup_vars, index, own).keep_if(|l| l < common.lookup_count)
		}
	}

	## The lookups of a table for the mapped features, stage by stage, each
	## stage in lookup index order with the masks of every feature that
	## lists the lookup (a lookup two features list skips joiners only when
	## both do). The language system's required feature applies everywhere,
	## in `required_stage`. A feature's lookups are as feature variations
	## have them at the face's location (`varied_feature_lookups`).
	lookups : LayoutCommon, U64, U64, List(Mapped), U64, [Gsub, Gpos], Varied, Bool -> List(LayoutGsub.Step)
	lookups = |common, required, required_stage, mapped, stages, table, varied, arabic| {
		count = common.lookup_count
		# Every stage's lookups in one list: stage `s`, lookup `l` at
		# `s * count + l` (a feature's stage is below `stages`), each entry
		# the lookup's mask (bits 0 to 31) and its kind (bits 32 to 34). Bit
		# 32: some feature asks; bit 33: some feature joins manually; bit 34:
		# the first feature to list it is `rand`.
		asks = 0x100000000.U64
		joins = 0x200000000
		random_first = 0x400000000
		var $entries = List.repeat(0.U64, stages * count)
		# Lookups are read where the font lists them unless feature
		# variations are in force.
		in_place = varied.subs.is_empty() and varied.lookup_vars.is_empty()
		if required != LayoutCommon.no_feature and required_stage < stages {
			base = required_stage * count
			feature_lookups = if (in_place) LayoutCommon.feature_lookups(common, required) else Shaper.varied_feature_lookups(common, varied, required)
			for lookup in feature_lookups {
				# Feature lookups are below the lookup count.
				$entries = $entries.set(base + lookup, ($entries.get(base + lookup) ?? 0).bitwise_or(Shaper.global_bit).bitwise_or(asks)) ?? []
			}
		}
		for m in mapped {
			index = match table {
				Gsub => m.gsub
				Gpos => m.gpos
			}
			feature_stage = match table {
				Gsub => m.stage.min(stages - 1)
				Gpos => 0
			}
			if index != LayoutCommon.no_feature and feature_stage < stages {
				base = feature_stage * count
				added = m.mask.bitwise_and(0xFFFFFFFF).bitwise_or(asks).bitwise_or(if (m.manual) joins else 0)
				if in_place {
					# `LayoutCommon.feature_lookups` without making the list.
					data = common.data
					offset = if (index >= common.feature_count) 0 else Bytes.u16(data, common.feature_list + 2 + 6 * index + 4)
					if offset != 0 {
						at = common.feature_list + offset
						for k in 0..<Bytes.u16(data, at + 2) {
							lookup = Bytes.u16(data, at + 4 + 2 * k)
							if lookup < count {
								entry = $entries.get(base + lookup) ?? 0
								first = if (entry.bitwise_and(asks) == 0 and m.random) random_first else 0
								# `lookup` is below the lookup count.
								$entries = $entries.set(base + lookup, entry.bitwise_or(added).bitwise_or(first)) ?? []
							}
						}
					}
				} else {
					for lookup in Shaper.varied_feature_lookups(common, varied, index) {
						entry = $entries.get(base + lookup) ?? 0
						first = if (entry.bitwise_and(asks) == 0 and m.random) random_first else 0
						# Feature lookups are below the lookup count.
						$entries = $entries.set(base + lookup, entry.bitwise_or(added).bitwise_or(first)) ?? []
					}
				}
			}
		}
		var $steps = 0
		for entry in $entries {
			if entry.bitwise_and(0xFFFFFFFF) != 0 {
				$steps = $steps + 1
			}
		}
		var $out = List.with_capacity($steps)
		for at in 0..<(stages * count) {
			entry = $entries.get(at) ?? 0
			mask = entry.bitwise_and(0xFFFFFFFF)
			if mask != 0 {
				automatic = entry.bitwise_and(joins) == 0
				$out = $out.append({ index: at % count, mask, auto_zwnj: arabic or automatic, auto_zwj: automatic, random: entry.bitwise_and(random_first) != 0 })
			}
		}
		$out
	}

	ModelFeature : { tag : U64, stage : U64, default : U64, global : Bool, manual_zwj : Bool, manual_zwnj : Bool, per_syllable : Bool }
	Staged : { steps : List(LayoutGsub.StageStep), spans : List({ start : U64, end : U64 }) }
	staged_lookups : LayoutCommon, U64, U64, List(Mapped), U64, Varied, List(ModelFeature) -> Staged
	staged_lookups = |common, required, required_stage, mapped, stages, varied, model_features| {
		count = common.lookup_count
		# Every stage's lookups in one list: stage `s`, lookup `l` at
		# `s * count + l` (a feature's stage is below `stages`), each entry
		# the lookup's mask (bits 0 to 31) and its kind (bits 32 to 34). Bit
		# 32: some feature asks; bit 33: some feature joins manually; bit 34:
		# the first feature to list it is `rand`.
		asks = 0x100000000.U64
		joins = 0x200000000
		zwnj = 0x800000000
		syllable = 0x1000000000
		random_first = 0x400000000
		var $entries = List.repeat(0.U64, stages * count)
		# Lookups are read where the font lists them unless feature
		# variations are in force.
		in_place = varied.subs.is_empty() and varied.lookup_vars.is_empty()
		if required != LayoutCommon.no_feature and required_stage < stages {
			base = required_stage * count
			feature_lookups = if (in_place) LayoutCommon.feature_lookups(common, required) else Shaper.varied_feature_lookups(common, varied, required)
			for lookup in feature_lookups {
				# Feature lookups are below the lookup count.
				$entries = $entries.set(base + lookup, ($entries.get(base + lookup) ?? 0).bitwise_or(Shaper.global_bit).bitwise_or(asks)) ?? []
			}
		}
		for m in mapped {
			index = m.gsub
			feature_stage = m.stage.min(stages - 1)
			if index != LayoutCommon.no_feature and feature_stage < stages {
				base = feature_stage * count
				flags = match model_features.find_first(|f| f.tag == m.tag) {
					Ok(f) => { manual_zwnj: f.manual_zwnj, per_syllable: f.per_syllable }
					Err(_) => { manual_zwnj: False, per_syllable: m.tag == Shaper.tag("locl") or m.tag == Shaper.tag("ccmp") }
				}
				added = m.mask.bitwise_and(0xFFFFFFFF).bitwise_or(asks).bitwise_or(if (m.manual) joins else 0).bitwise_or(if (flags.manual_zwnj) zwnj else 0).bitwise_or(if (flags.per_syllable) syllable else 0)
				if in_place {
					# `LayoutCommon.feature_lookups` without making the list.
					data = common.data
					offset = if (index >= common.feature_count) 0 else Bytes.u16(data, common.feature_list + 2 + 6 * index + 4)
					if offset != 0 {
						at = common.feature_list + offset
						for k in 0..<Bytes.u16(data, at + 2) {
							lookup = Bytes.u16(data, at + 4 + 2 * k)
							if lookup < count {
								entry = $entries.get(base + lookup) ?? 0
								first = if (entry.bitwise_and(asks) == 0 and m.random) random_first else 0
								# `lookup` is below the lookup count.
								$entries = $entries.set(base + lookup, entry.bitwise_or(added).bitwise_or(first)) ?? []
							}
						}
					}
				} else {
					for lookup in Shaper.varied_feature_lookups(common, varied, index) {
						entry = $entries.get(base + lookup) ?? 0
						first = if (entry.bitwise_and(asks) == 0 and m.random) random_first else 0
						# Feature lookups are below the lookup count.
						$entries = $entries.set(base + lookup, entry.bitwise_or(added).bitwise_or(first)) ?? []
					}
				}
			}
		}
		var $steps = 0
		for entry in $entries {
			if entry.bitwise_and(0xFFFFFFFF) != 0 {
				$steps = $steps + 1
			}
		}
		var $out = List.with_capacity($steps)
		var $spans = List.with_capacity(stages)
		for stage in 0..<stages {
			start = $out.len()
			for index in 0..<count {
				entry = $entries.get(stage * count + index) ?? 0
				mask = entry.bitwise_and(0xFFFFFFFF)
				if mask != 0 {
					step = { index, mask, auto_zwnj: entry.bitwise_and(zwnj) == 0, auto_zwj: entry.bitwise_and(joins) == 0, random: entry.bitwise_and(random_first) != 0 }
					$out = $out.append({ step, per_syllable: entry.bitwise_and(syllable) != 0 })
				}
			}
			$spans = $spans.append({ start, end: $out.len() })
		}
		{ steps: $out, spans: $spans }
	}

	apply_arabic : Plan, LayoutGsub, List(LayoutGsub.Item), LayoutGsub.Limits -> LayoutGsub.Applied
	apply_arabic = |p, shape, items, limits| {
		var $session = LayoutGsub.begin(items)
		for stage in 0..<p.staged.spans.len() {
			if stage == 2 and p.arabic_stch {
				{ items: current, serial, random, operations, stopped, step_offset, spare, work } = $session
				if current.len() > limits.budget - operations {
					$session = { items: current, serial, random, operations, stopped: stopped.bitwise_or(2), step_offset, spare, work }
				} else {
					count = current.len()
					$session = { items: ShaperArabicStretch.record(current), serial, random, operations: operations + count, stopped, step_offset, spare, work }
				}
			}
			if stage == 11 {
				$session = ShaperArabicFallback.apply(p.arabic_fallback, $session, limits)
			}
			span = p.staged.spans.get(stage) ?? { start: 0, end: 0 }
			steps = p.staged.steps.sublist({ start: span.start, len: span.end - span.start })
			$session = LayoutGsub.resume(shape, steps, $session, limits)
		}
		{ items: $session.items, stopped: $session.stopped, operations: $session.operations }
	}

	pause_indic : ShaperIndic, ShaperIndic.Event, LayoutGsub, LayoutGsub.Session, ShaperIndic.Dotted, LayoutGsub.Limits -> LayoutGsub.Session
	pause_indic = |model, event, shape, session, dotted_circle, limits| {
		{ items, serial, random, operations, stopped, step_offset, spare, work } = session
		paused = ShaperIndic.pause(model, event, shape, items, { dotted_circle, limit: limits.limit, budget: limits.budget - operations })
		{ items: paused.items, serial, random, operations: operations + paused.operations, stopped: stopped.bitwise_or(paused.stopped), step_offset, spare, work }
	}

	apply_indic : Face, ShaperIndic, Staged, LayoutGsub, List(LayoutGsub.Item), LayoutGsub.Limits -> LayoutGsub.Applied
	apply_indic = |face, model, staged, shape, items, limits| {
		gdef = Face.gdef(face)
		dotted_circle = match Face.glyph(face, 0x25CC) {
			Ok(glyph) => {
				gprops = if (LayoutGdef.has_glyph_classes(gdef)) LayoutGdef.glyph_props(gdef, glyph) else LayoutGsub.base_glyph
				Present({ glyph, props: ShaperUnicode.props(0x25CC).bitwise_and(0xFFFF).bitwise_or(gprops.shl_wrap(16)) })
			}
			Err(_) => Absent
		}
		var $session = LayoutGsub.begin(items)
		for stage in 0..<staged.spans.len() {
			for pause in ShaperIndic.pauses {
				if pause.stage == stage {
					$session = Shaper.pause_indic(model, pause.event, shape, $session, dotted_circle, limits)
				}
			}
			span = staged.spans.get(stage) ?? { start: 0, end: 0 }
			steps = staged.steps.sublist({ start: span.start, len: span.end - span.start })
			$session = LayoutGsub.resume(shape, steps, $session, limits)
		}
		{ items: $session.items, stopped: $session.stopped, operations: $session.operations }
	}

	pause_khmer : ShaperKhmer, ShaperKhmer.Event, LayoutGsub, LayoutGsub.Session, ShaperIndic.Dotted, LayoutGsub.Limits -> LayoutGsub.Session
	pause_khmer = |model, event, shape, session, dotted_circle, limits| {
		{ items, serial, random, operations, stopped, step_offset, spare, work } = session
		paused = ShaperKhmer.pause(model, event, shape, items, { dotted_circle, limit: limits.limit, budget: limits.budget - operations })
		{ items: paused.items, serial, random, operations: operations + paused.operations, stopped: stopped.bitwise_or(paused.stopped), step_offset, spare, work }
	}

	apply_khmer : Face, ShaperKhmer, Staged, LayoutGsub, List(LayoutGsub.Item), LayoutGsub.Limits -> LayoutGsub.Applied
	apply_khmer = |face, model, staged, shape, items, limits| {
		gdef = Face.gdef(face)
		dotted_circle = match Face.glyph(face, 0x25CC) {
			Ok(glyph) => {
				gprops = if (LayoutGdef.has_glyph_classes(gdef)) LayoutGdef.glyph_props(gdef, glyph) else LayoutGsub.base_glyph
				Present({ glyph, props: ShaperUnicode.props(0x25CC).bitwise_and(0xFFFF).bitwise_or(gprops.shl_wrap(16)) })
			}
			Err(_) => Absent
		}
		var $session = LayoutGsub.begin(items)
		for stage in 0..<staged.spans.len() {
			for pause in ShaperKhmer.pauses {
				if pause.stage == stage {
					$session = Shaper.pause_khmer(model, pause.event, shape, $session, dotted_circle, limits)
				}
			}
			span = staged.spans.get(stage) ?? { start: 0, end: 0 }
			steps = staged.steps.sublist({ start: span.start, len: span.end - span.start })
			$session = LayoutGsub.resume(shape, steps, $session, limits)
		}
		{ items: $session.items, stopped: $session.stopped, operations: $session.operations }
	}

	pause_myanmar : ShaperMyanmar, ShaperMyanmar.Event, LayoutGsub, LayoutGsub.Session, ShaperIndic.Dotted, LayoutGsub.Limits -> LayoutGsub.Session
	pause_myanmar = |model, event, shape, session, dotted_circle, limits| {
		{ items, serial, random, operations, stopped, step_offset, spare, work } = session
		paused = ShaperMyanmar.pause(model, event, shape, items, { dotted_circle, limit: limits.limit, budget: limits.budget - operations })
		{ items: paused.items, serial, random, operations: operations + paused.operations, stopped: stopped.bitwise_or(paused.stopped), step_offset, spare, work }
	}

	apply_myanmar : Face, ShaperMyanmar, Staged, LayoutGsub, List(LayoutGsub.Item), LayoutGsub.Limits -> LayoutGsub.Applied
	apply_myanmar = |face, model, staged, shape, items, limits| {
		gdef = Face.gdef(face)
		dotted_circle = match Face.glyph(face, 0x25CC) {
			Ok(glyph) => {
				gprops = if (LayoutGdef.has_glyph_classes(gdef)) LayoutGdef.glyph_props(gdef, glyph) else LayoutGsub.base_glyph
				Present({ glyph, props: ShaperUnicode.props(0x25CC).bitwise_and(0xFFFF).bitwise_or(gprops.shl_wrap(16)) })
			}
			Err(_) => Absent
		}
		var $session = LayoutGsub.begin(items)
		for stage in 0..<staged.spans.len() {
			for pause in ShaperMyanmar.pauses {
				if pause.stage == stage {
					$session = Shaper.pause_myanmar(model, pause.event, shape, $session, dotted_circle, limits)
				}
			}
			span = staged.spans.get(stage) ?? { start: 0, end: 0 }
			steps = staged.steps.sublist({ start: span.start, len: span.end - span.start })
			$session = LayoutGsub.resume(shape, steps, $session, limits)
		}
		{ items: $session.items, stopped: $session.stopped, operations: $session.operations }
	}

	pause_use : ShaperUse, ShaperUse.Event, LayoutGsub, LayoutGsub.Session, ShaperIndic.Dotted, LayoutGsub.Limits -> LayoutGsub.Session
	pause_use = |model, event, shape, session, dotted_circle, limits| {
		{ items, serial, random, operations, stopped, step_offset, spare, work } = session
		paused = ShaperUse.pause(model, event, shape, items, { dotted_circle, limit: limits.limit, budget: limits.budget - operations })
		{ items: paused.items, serial, random, operations: operations + paused.operations, stopped: stopped.bitwise_or(paused.stopped), step_offset, spare, work }
	}

	apply_use : Face, ShaperUse, Staged, LayoutGsub, List(LayoutGsub.Item), LayoutGsub.Limits -> LayoutGsub.Applied
	apply_use = |face, model, staged, shape, items, limits| {
		gdef = Face.gdef(face)
		dotted_circle = match Face.glyph(face, 0x25CC) {
			Ok(glyph) => {
				gprops = if (LayoutGdef.has_glyph_classes(gdef)) LayoutGdef.glyph_props(gdef, glyph) else LayoutGsub.base_glyph
				Present({ glyph, props: ShaperUnicode.props(0x25CC).bitwise_and(0xFFFF).bitwise_or(gprops.shl_wrap(16)) })
			}
			Err(_) => Absent
		}
		var $session = LayoutGsub.begin(items)
		for stage in 0..<staged.spans.len() {
			for pause in ShaperUse.pauses {
				if pause.stage == stage {
					$session = Shaper.pause_use(model, pause.event, shape, $session, dotted_circle, limits)
				}
			}
			span = staged.spans.get(stage) ?? { start: 0, end: 0 }
			steps = staged.steps.sublist({ start: span.start, len: span.end - span.start })
			$session = LayoutGsub.resume(shape, steps, $session, limits)
		}
		{ items: $session.items, stopped: $session.stopped, operations: $session.operations }
	}

	# ------------------------------------------------------------ shaping

	## Text as scalars with the UTF-8 byte offset each starts at.
	decode : Str -> List({ scalar : U32, offset : U64 })
	decode = |text| {
		bytes = text.to_utf8()
		count = bytes.len()
		var $out = List.with_capacity(count)
		var $i = 0
		while $i < count {
			b0 = (bytes.get($i) ?? 0).to_u32()
			width = if (b0 < 0x80) 1 else if (b0 < 0xE0) 2 else if (b0 < 0xF0) 3 else 4
			var $cp = if (width == 1) b0 else if (width == 2) b0.bitwise_and(0x1F) else if (width == 3) b0.bitwise_and(0x0F) else b0.bitwise_and(0x07)
			for k in 1..<width {
				$cp = $cp.shl_wrap(6).bitwise_or((bytes.get($i + k) ?? 0).to_u32().bitwise_and(0x3F))
			}
			$out = $out.append({ scalar: $cp, offset: $i })
			$i = $i + width
		}
		$out
	}

	clamp : I64 -> I32
	clamp = |v| v.max(-2147483648).min(2147483647).to_i32_wrap()

	## Set the masks HarfBuzz sets before substituting
	## (`hb_ot_shape_setup_masks`): automatic fractions around U+2044
	## FRACTION SLASH between decimal digits (numerators, the slash,
	## denominators; mirrored for backward text), then the caller's ranged
	## features over the clusters they cover, in order.
	setup_masks : Plan, List(ShaperNormalize.Char), Bool, Bool -> List(ShaperNormalize.Char)
	setup_masks = |p, chars, fraction_slash, forward| {
		count = chars.len()
		var $chars = chars
		if fraction_slash and (p.frac_mask != 0 or (p.numr_mask != 0 and p.dnom_mask != 0)) {
			pre = if (forward) p.numr_mask.bitwise_or(p.frac_mask) else p.frac_mask.bitwise_or(p.dnom_mask)
			post = if (forward) p.frac_mask.bitwise_or(p.dnom_mask) else p.numr_mask.bitwise_or(p.frac_mask)
			digit = |c| ShaperUnicode.general_category_of(c.props) == ShaperUnicode.decimal_number
			var $i = 0
			while $i < count {
				c = $chars.get($i) ?? ShaperNormalize.no_char
				if c.cp == 0x2044 {
					var $start = $i
					while $start > 0 and digit($chars.get($start - 1) ?? ShaperNormalize.no_char) {
						$start = $start - 1
					}
					var $end = $i + 1
					while $end < count and digit($chars.get($end) ?? ShaperNormalize.no_char) {
						$end = $end + 1
					}
					if $start == $i or $end == $i + 1 {
						$i = $i + 1
					} else {
						$chars = Shaper.flag_chars($chars, $start, $end)
						for j in $start..<$end {
							d = $chars.get(j) ?? ShaperNormalize.no_char
							extra = if (j < $i) pre else if (j == $i) p.frac_mask else post
							# `j < $end <= count`.
							$chars = $chars.set(j, { ..d, mask: d.mask.bitwise_or(extra) }) ?? []
						}
						$i = $end
					}
				} else {
					$i = $i + 1
				}
			}
		}
		for r in p.ranges {
			$chars = $chars.map(|c| if (c.cluster >= r.start and c.cluster < r.end) { ..c, mask: c.mask.bitwise_and(r.mask.bitwise_xor(0xFFFFFFFFFFFFFFFF)).bitwise_or(r.value) } else c)
		}
		$chars
	}

	## HarfBuzz's `unsafe_to_break` over characters `start ..< end`.
	flag_chars : List(ShaperNormalize.Char), U64, U64 -> List(ShaperNormalize.Char)
	flag_chars = |chars, start, end|
		if end - start < 2 or end - start > 255 {
			chars
		} else {
			first = (chars.get(start) ?? ShaperNormalize.no_char).cluster
			last = (chars.get(end - 1) ?? ShaperNormalize.no_char).cluster
			cluster = first.min(last)
			var $chars = chars
			for i in start..<end {
				c = $chars.get(i) ?? ShaperNormalize.no_char
				flagged = if (cluster != first and cluster != last) c.cluster != cluster else if (cluster == first) c.cluster != first else c.cluster != last
				if flagged {
					# `i < end <= len`.
					$chars = $chars.set(i, { ..c, mask: c.mask.bitwise_or(LayoutGsub.unsafe) }) ?? []
				}
			}
			$chars
		}

	## Combining classes HarfBuzz uses for positioning marks itself
	## (`recategorize_combining_class`): Hebrew, Arabic, Syriac, Thai, Lao
	## and Tibetan classes become the positional classes they draw at.
	# hb-ot-shape-fallback.cc switches on modified CCC aliases, not on
	# canonical CCC numbers. This constant pool also avoids per-mark work.
	fallback_classes : List(U64)
	fallback_classes = [0, 1, 2, 222, 4, 5, 6, 7, 8, 9, 232, 228, 12, 214, 228, 220, 220, 220, 220, 220, 220, 220, 220, 220, 220, 220, 230, 230, 230, 230, 220, 230, 230, 220, 230, 230, 230, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 232, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 220, 119, 120, 121, 230, 123, 124, 125, 126, 127, 128, 220, 130, 220, 230, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255]

	recategorize : U64, U64 -> U64
	recategorize = |u, klass_in|
		if klass_in >= 200 {
			klass_in
		} else {
			klass =
				if u.bitwise_and(0xFFFFFF00) == 0x0E00 {
					if klass_in == 0 {
						if u == 0x0E31 or (u >= 0x0E34 and u <= 0x0E37) or u == 0x0E47 or (u >= 0x0E4C and u <= 0x0E4E) {
							232
						} else if u == 0x0EB1 or (u >= 0x0EB4 and u <= 0x0EB7) or u == 0x0EBB or u == 0x0ECC or u == 0x0ECD {
							230
						} else if u == 0x0EBC {
							220
						} else {
							klass_in
						}
					} else if u == 0x0E3A {
						222
					} else {
						klass_in
					}
				} else {
					klass_in
				}
			Shaper.fallback_classes.get(klass) ?? klass
		}

	shape : Face, Face.Location, Plan, List({ scalar : U32, offset : U64 }) -> Run
	shape = |face, location, p, scalars| Shaper.shape_items(face, location, p, scalars).run

	## Shape, keeping the finished items and the bounds that stopped
	## substitution (see `Shaped`).
	shape_items : Face, Face.Location, Plan, List({ scalar : U32, offset : U64 }) -> Shaped
	shape_items = |face, location, p, scalars| Shaper.shape_items_with_context(face, location, p, scalars, { before: [], after: [] })

	shape_items_with_context : Face, Face.Location, Plan, List({ scalar : U32, offset : U64 }), { before : List(U32), after : List(U32) } -> Shaped
	shape_items_with_context = |face, location, p, scalars, context| {
		n = scalars.len()
		if n == 0 {
			return { run: Shaper.empty_run, items: [], stopped: 0, aborted: False }
		}
		limit = (p.growth * n).max(65536)
		budget = (p.operations * n).max(65536)
		gsub = Face.gsub(face)
		{ chars: prepared, found } = ShaperNormalize.prepare(scalars, p.global_mask)
		clustered =
			if !found.continuations {
				prepared
			} else if p.characters {
				# HarfBuzz marks graphemes unsafe to break instead of merging.
				ShaperNormalize.flag_graphemes(prepared)
			} else {
				ShaperNormalize.form_clusters(prepared)
			}
		# Shape in the script's own direction (HarfBuzz's
		# `hb_ensure_native_direction`).
		reverse = if (p.vertical) p.backward else match p.native {
			Rtl => !p.backward and !ShaperNormalize.numeric(clustered)
			Ltr => p.backward
			Either => False
		}
		ordered = if (reverse) ShaperNormalize.reverse_graphemes(clustered, p.characters) else clustered
		backward = if (reverse) !p.backward else p.backward
		mirrored_base = if (p.backward) ShaperNormalize.mirror(face, ordered, p.rtlm_mask) else ordered
		mirrored = if (p.vertical and !p.has_vert) Shaper.vertical_chars(face, mirrored_base) else mirrored_base
		preprocessed = if (p.thai) ShaperThai.preprocess(mirrored, p.characters) else if (p.hangul) ShaperHangul.preprocess(face, location, mirrored, p.characters, p.hangul_masks) else mirrored
		legacy = if (p.thai_legacy) ShaperThai.legacy(face, preprocessed) else preprocessed
		{ chars: vowels, operations: pre_operations, stopped: pre_stopped } = match p.model {
			Indic(_) | Use(_) => ShaperIndicVowels.preprocess(p.script, legacy, limit, budget)
			_ => { chars: legacy, operations: 0, stopped: 0 }
		}
		ctx = { face, variants: TableCmap.variants_of(Face.cmap(face)), hebrew: p.hebrew, hebrew_forms: p.hebrew and !p.has_gpos_mark }
		{ chars: normalized, space_fallback } = match p.model {
			Indic(_) => ShaperNormalize.normalize_script(ctx, vowels, Indic)
			Khmer(_) => ShaperNormalize.normalize_script(ctx, vowels, Khmer)
			Myanmar(_) => ShaperNormalize.normalize_script(ctx, vowels, Unicode)
			Use(_) => ShaperNormalize.normalize_script(ctx, vowels, Use)
			Simple => if (p.arabic) ShaperNormalize.normalize_with_marks(ctx, vowels, ShaperArabic.reorder) else if (p.hangul) ShaperNormalize.normalize_short_circuit(ctx, vowels) else ShaperNormalize.normalize(ctx, vowels)
		}
		joined = match p.model {
			Indic(_) => ShaperIndic.setup(normalized)
			Khmer(_) => ShaperKhmer.setup(normalized)
			Myanmar(_) => ShaperMyanmar.setup(normalized)
			Use(model) => ShaperUse.setup(model, normalized, context)
			Simple => if (p.arabic) ShaperArabic.setup(normalized, p.arabic_masks, context) else if (p.hangul) ShaperHangul.setup(normalized, p.hangul_masks) else normalized
		}
		masked = Shaper.setup_masks(p, joined, found.fraction_slash, !backward)
		gdef = Face.gdef(face)
		classes = LayoutGdef.has_glyph_classes(gdef)
		count0 = masked.len()
		var $items = List.with_capacity(count0)
		for c in masked {
			props =
				if p.fallback_marks and p.fallback_position and ShaperUnicode.general_category_of(c.props) == ShaperUnicode.non_spacing_mark {
					ShaperUnicode.with_high(c.props, Shaper.recategorize(c.cp, ShaperUnicode.class_of(c.props)))
				} else {
					c.props
				}
			glyph_props =
				if classes {
					LayoutGdef.glyph_props(gdef, c.glyph)
				} else if ShaperUnicode.general_category_of(props) == ShaperUnicode.non_spacing_mark and props.bitwise_and(ShaperUnicode.ignorable) == 0 {
					LayoutGsub.mark
				} else {
					LayoutGsub.base_glyph
				}
			$items = $items.append({ glyph: c.glyph, cluster: c.cluster, mask: c.mask, props: props.bitwise_and(0xFFFF).bitwise_or(glyph_props.shl_wrap(16)).bitwise_or(props.bitwise_and(ShaperNormalize.missing)) })
		}
		applied = match p.model {
			Simple => if (p.arabic and !p.staged.spans.is_empty()) Shaper.apply_arabic(p, gsub, $items, { limit, budget: budget - pre_operations, depth: Face.max_depth(face) }) else LayoutGsub.apply(gsub, p.gsub, $items, { limit, budget: budget - pre_operations, depth: Face.max_depth(face) })
			Indic(model) => Shaper.apply_indic(face, model, p.staged, gsub, $items, { limit, budget: budget - pre_operations, depth: Face.max_depth(face) })
			Khmer(model) => Shaper.apply_khmer(face, model, p.staged, gsub, $items, { limit, budget: budget - pre_operations, depth: Face.max_depth(face) })
			Myanmar(model) => Shaper.apply_myanmar(face, model, p.staged, gsub, $items, { limit, budget: budget - pre_operations, depth: Face.max_depth(face) })
			Use(model) => Shaper.apply_use(face, model, p.staged, gsub, $items, { limit, budget: budget - pre_operations, depth: Face.max_depth(face) })
		}
		positioned = Shaper.position_checked(face, location, p, applied.items, backward, space_fallback, found.ignorables, budget - pre_operations - applied.operations, limit)
		placed = positioned.placed
		{ run: Shaper.finish_axis(placed, p.vertical), items: placed.items, stopped: pre_stopped.bitwise_or(applied.stopped).bitwise_or(positioned.stopped), aborted: False }
	}

	# Unicode presentation-form fallback used only without a vert feature.
	vertical_form : U64 -> U64
	vertical_form = |cp|
		match cp {
			0x2013 => 0xfe32
			0x2014 => 0xfe31
			0x2025 => 0xfe30
			0x2026 => 0xfe19
			0x3001 => 0xfe11
			0x3002 => 0xfe12
			0x3008 => 0xfe3f
			0x3009 => 0xfe40
			0x300a => 0xfe3d
			0x300b => 0xfe3e
			0x300c => 0xfe41
			0x300d => 0xfe42
			0x300e => 0xfe43
			0x300f => 0xfe44
			0x3010 => 0xfe3b
			0x3011 => 0xfe3c
			0x3014 => 0xfe39
			0x3015 => 0xfe3a
			0x3016 => 0xfe17
			0x3017 => 0xfe18
			0xfe4f => 0xfe34
			0xff01 => 0xfe15
			0xff08 => 0xfe35
			0xff09 => 0xfe36
			0xff0c => 0xfe10
			0xff1a => 0xfe13
			0xff1b => 0xfe14
			0xff1f => 0xfe16
			0xff3b => 0xfe47
			0xff3d => 0xfe48
			0xff3f => 0xfe33
			0xff5b => 0xfe37
			0xff5d => 0xfe38
			_ => cp
		}

	vertical_chars : Face, List(ShaperNormalize.Char) -> List(ShaperNormalize.Char)
	vertical_chars = |face, chars| chars.map(
		|c| {
			vertical_cp = Shaper.vertical_form(c.cp)
			if (vertical_cp != c.cp and Face.glyph(face, vertical_cp.to_u32_wrap()).is_ok()) { ..c, cp: vertical_cp } else c
		},
	)

	global_feature : LayoutCommon, U64 -> U64
	global_feature = |common, wanted_tag| {
		for index in 0..<common.feature_count {
			if LayoutCommon.feature_tag(common, index) == wanted_tag {
				return index
			}
		}
		LayoutCommon.no_feature
	}

	position_vertical : Face, Face.Location, Plan, List(LayoutGsub.Item), Bool, Bool, Bool, U64 -> { placed : Placed, stopped : U64 }
	position_vertical = |face, location, p, items, backward, space_fallback, ignorables, budget| {
		count = items.len()
		var $base = List.with_capacity(count)
		var $major = List.with_capacity(count)
		var $cross = List.with_capacity(count)
		for item in items {
			origin = Face.vertical_origin(face, location, item.glyph)
			$base = $base.append(-(Face.vertical_advance(face, location, item.glyph).to_i64()))
			$major = $major.append((-(origin.y.to_i64())).to_i32_wrap().to_i64())
			$cross = $cross.append((-(origin.x.to_i64())).to_i32_wrap().to_i64())
		}
		if space_fallback {
			$base = Shaper.space_widths(face, items, $base, -(Face.units_per_em(face).to_i64()), |glyph| -(Face.vertical_advance(face, location, glyph).to_i64()))
		}
		if p.zero_marks == Early {
			for i in 0..<count {
				if LayoutGsub.is_mark_item(items.get(i) ?? LayoutGsub.no_item) {
					if p.fallback_marks and !backward {
						$major = $major.set(i, LayoutVar.position_sub($major.get(i) ?? 0, $base.get(i) ?? 0)) ?? []
					}
					$base = $base.set(i, 0) ?? []
				}
			}
		}
		full = LayoutKerning.position_vertical(Face.kerning(face), p.gpos, p.gpos_auto_zwj, p.zero_marks == Late, items, Face.glyph_count(face), $base, $major, $cross, backward, { budget, depth: Face.max_depth(face) })
		{ items: positioned_items, ax, dx, dy } = full.positions
		var $ax = ax
		var $dx = dx
		var $dy = dy
		for i in 0..<count {
			item = positioned_items.get(i) ?? LayoutGsub.no_item
			if p.zero_marks == Late and LayoutGsub.is_mark_item(item) {
				if p.fallback_marks and !backward {
					$dx = $dx.set(i, LayoutVar.position_sub($dx.get(i) ?? 0, $ax.get(i) ?? 0)) ?? []
				}
				$ax = $ax.set(i, 0) ?? []
			}
			if ignorables and LayoutGsub.is_default_ignorable(item) {
				$ax = $ax.set(i, 0) ?? []
				$dx = $dx.set(i, 0) ?? []
			}
		}
		fallback = if (p.fallback_marks and p.fallback_position) Shaper.position_marks_axis(face, location, { items: positioned_items, ax: $ax, dx: $dx, dy: $dy }, backward, p.native == Rtl, Face.units_per_em(face).to_i64(), p.fallback_marks and !backward, True) else { items: positioned_items, ax: $ax, dx: $dx, dy: $dy }
		placed = if (backward) { items: Shaper.reversed(fallback.items), ax: Shaper.reversed(fallback.ax), dx: Shaper.reversed(fallback.dx), dy: Shaper.reversed(fallback.dy) } else fallback
		{ placed: if (ignorables) Shaper.hide_ignorables(face, placed) else placed, stopped: full.stopped }
	}

	## Position a substituted run and finish it (HarfBuzz's `hb_ot_position`
	## and `hb_ot_substitute_post`).
	position : Face, Face.Location, Plan, List(LayoutGsub.Item), Bool, Bool, Bool -> Placed
	position = |face, location, p, substituted, backward, space_fallback, ignorables| Shaper.position_checked(face, location, p, substituted, backward, space_fallback, ignorables, (p.operations * substituted.len()).max(65536), (p.growth * substituted.len()).max(65536)).placed

	position_checked : Face, Face.Location, Plan, List(LayoutGsub.Item), Bool, Bool, Bool, U64, U64 -> { placed : Placed, stopped : U64 }
	position_checked = |face, location, p, substituted, backward, space_fallback, ignorables, remaining_budget, growth_limit| {
		if p.vertical {
			return Shaper.position_vertical(face, location, p, substituted, backward, space_fallback, ignorables, remaining_budget)
		}
		upem = Face.units_per_em(face).to_i64()
		advance_of = |glyph| Face.advance(face, location, glyph).to_i64()
		count = substituted.len()
		var $base = List.with_capacity(count)
		for item in substituted {
			$base = $base.append(advance_of(item.glyph))
		}
		if space_fallback {
			$base = Shaper.space_widths(face, substituted, $base, upem, advance_of)
		}
		adjust_early = p.zero_marks == Early and p.fallback_marks and !backward
		original = if (adjust_early) $base else []
		if p.zero_marks == Early {
			for i in 0..<count {
				if LayoutGsub.is_mark_item(substituted.get(i) ?? LayoutGsub.no_item) {
					$base = $base.set(i, 0) ?? []
				}
			}
		}
		full = LayoutKerning.position_full_with_policy(Face.kerning(face), p.gpos, p.gpos_auto_zwj, p.zero_marks == Late, p.kern, substituted, Face.glyph_count(face), $base, backward, { budget: remaining_budget, depth: Face.max_depth(face) })
		positioned = full.positions
		var $items = positioned.items
		var $ax = List.with_capacity(count)
		var $dx = positioned.dx
		var $dy = positioned.dy
		for i in 0..<count {
			$ax = $ax.append(($base.get(i) ?? 0) + (positioned.ax.get(i) ?? 0))
		}
		if adjust_early {
			for i in 0..<count {
				if LayoutGsub.is_mark_item($items.get(i) ?? LayoutGsub.no_item) {
					$dx = $dx.set(i, ($dx.get(i) ?? 0) - (original.get(i) ?? 0)) ?? []
				}
			}
		}
		# Marks take no advance (HarfBuzz zeroes them after `GPOS`); without
		# `GPOS`, in forward text a mark keeps hanging over the glyph before.
		adjust = p.fallback_marks and !backward
		for i in 0..<count {
			item = $items.get(i) ?? LayoutGsub.no_item
			if LayoutGsub.is_mark_item(item) and p.zero_marks == Late {
				if adjust {
					# `i < count`, the lists' length.
					$dx = $dx.set(i, ($dx.get(i) ?? 0) - ($ax.get(i) ?? 0)) ?? []
				}
				$ax = $ax.set(i, 0) ?? []
			}
		}
		if ignorables {
			for i in 0..<count {
				if LayoutGsub.is_default_ignorable($items.get(i) ?? LayoutGsub.no_item) {
					$ax = $ax.set(i, 0) ?? []
					$dx = $dx.set(i, 0) ?? []
				}
			}
		}
		if p.fallback_marks and p.fallback_position {
			{ items: fallback_items, ax: fallback_ax, dx: fallback_dx, dy: fallback_dy } = Shaper.position_marks(face, location, { items: $items, ax: $ax, dx: $dx, dy: $dy }, backward, p.backward, upem, adjust)
			$items = fallback_items
			$ax = fallback_ax
			$dx = fallback_dx
			$dy = fallback_dy
		}
		ordered = if (backward) { items: Shaper.reversed($items), ax: Shaper.reversed($ax), dx: Shaper.reversed($dx), dy: Shaper.reversed($dy) } else { items: $items, ax: $ax, dx: $dx, dy: $dy }
		finished = if (ignorables) Shaper.hide_ignorables(face, ordered) else ordered
		if p.arabic_stch {
			stretched = ShaperArabicStretch.apply(face, location, finished, backward, growth_limit, remaining_budget - full.operations)
			{ placed: stretched.placed, stopped: full.stopped.bitwise_or(stretched.stopped) }
		} else { placed: finished, stopped: full.stopped }
	}

	## The widths HarfBuzz gives spaces the font lacks, drawn with the space
	## glyph (`_hb_ot_shape_fallback_spaces`): fractions of an em, the width
	## of a digit or of a full stop, or half the space.
	space_widths : Face, List(LayoutGsub.Item), List(I64), I64, (U64 -> I64) -> List(I64)
	space_widths = |face, items, widths, upem, advance_of| {
		var $widths = widths
		for i in 0..<items.len() {
			item = items.get(i) ?? LayoutGsub.no_item
			if ShaperUnicode.is_space(item.props) and LayoutGsub.gprops(item).bitwise_and(LayoutGsub.ligated) == 0 {
				kind = item.props.shr_zf_wrap(8).bitwise_and(0xFF)
				current = $widths.get(i) ?? 0
				glyph_of = |cp| Face.glyph(face, cp)
				width =
					if (kind >= 1 and kind <= 6) or kind == 16 {
						d = kind.to_i64_wrap()
						(upem + d // 2) // d
					} else if kind == 17 {
						upem * 4 // 18
					} else if kind == 19 {
						match ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'].find_first(|c| glyph_of(c).is_ok()) {
							Ok(c) => advance_of(glyph_of(c) ?? 0)
							Err(_) => current
						}
					} else if kind == 20 {
						match glyph_of('.') {
							Ok(g) => advance_of(g)
							Err(_) =>
								match glyph_of(',') {
									Ok(g) => advance_of(g)
									Err(_) => current
								}
						}
					} else if kind == 21 {
						current // 2
					} else {
						current
					}
				# `i` is below the run's length.
				$widths = $widths.set(i, width) ?? []
			}
		}
		$widths
	}

	Placed : { items : List(LayoutGsub.Item), ax : List(I64), dx : List(I64), dy : List(I64) }

	## HarfBuzz's fallback mark positioning (`_hb_ot_shape_fallback_mark_position`)
	## for fonts that do not position marks: each cluster's marks are placed
	## around its base glyph's ink by their combining classes.
	position_marks : Face, Face.Location, Placed, Bool, Bool, I64, Bool -> Placed
	position_marks = |face, location, placed, backward, target_backward, upem, adjust| Shaper.position_marks_axis(face, location, placed, backward, target_backward, upem, adjust, False)

	position_marks_axis : Face, Face.Location, Placed, Bool, Bool, I64, Bool, Bool -> Placed
	position_marks_axis = |face, location, placed, backward, target_backward, upem, adjust, vertical| {
		items = placed.items
		count = items.len()
		var $placed = placed
		var $start = 0
		for i in 1..<count {
			item = items.get(i) ?? LayoutGsub.no_item
			if !ShaperUnicode.is_mark(item.props) and item.props.bitwise_and(ShaperUnicode.hidden) == 0 and !LayoutGsub.is_default_ignorable(item) {
				$placed = Shaper.position_cluster_axis(face, location, $placed, $start, i, backward, target_backward, upem, adjust, vertical)
				$start = i
			}
		}
		Shaper.position_cluster_axis(face, location, $placed, $start, count, backward, target_backward, upem, adjust, vertical)
	}

	position_cluster : Face, Face.Location, Placed, U64, U64, Bool, Bool, I64, Bool -> Placed
	position_cluster = |face, location, placed, start, end, backward, target_backward, upem, adjust| Shaper.position_cluster_axis(face, location, placed, start, end, backward, target_backward, upem, adjust, False)

	position_cluster_axis : Face, Face.Location, Placed, U64, U64, Bool, Bool, I64, Bool, Bool -> Placed
	position_cluster_axis = |face, location, placed, start, end, backward, target_backward, upem, adjust, vertical|
		if end - start < 2 {
			placed
		} else {
			var $placed = placed
			var $i = start
			while $i < end {
				item = $placed.items.get($i) ?? LayoutGsub.no_item
				if ShaperUnicode.is_mark(item.props) {
					$i = $i + 1
				} else {
					var $j = $i + 1
					var $going = True
					while $going and $j < end {
						next = $placed.items.get($j) ?? LayoutGsub.no_item
						if next.props.bitwise_and(ShaperUnicode.hidden) != 0 or LayoutGsub.is_default_ignorable(next) {
							$j = $j + 1
						} else if !ShaperUnicode.is_mark(next.props) {
							$going = False
						} else {
							$j = $j + 1
						}
					}
					$placed = Shaper.position_around_base_axis(face, location, $placed, $i, $j, backward, target_backward, upem, adjust, vertical)
					$i = $j
				}
			}
			$placed
		}

	## A glyph's ink box as HarfBuzz's extents (x and y bearings, width and
	## a negative height); a glyph without outline has a zero box.
	Extents : { x_bearing : I64, y_bearing : I64, width : I64, height : I64 }

	extents_of : Face, U64 -> Extents
	extents_of = |face, glyph|
		match Face.extents(face, glyph) {
			Extents(b) => { x_bearing: b.x_min.to_i64(), y_bearing: b.y_max.to_i64(), width: b.x_max.to_i64() - b.x_min.to_i64(), height: b.y_min.to_i64() - b.y_max.to_i64() }
			Empty | Unknown => { x_bearing: 0, y_bearing: 0, width: 0, height: 0 }
		}

	## HarfBuzz's `position_around_base`.
	position_around_base : Face, Face.Location, Placed, U64, U64, Bool, Bool, I64, Bool -> Placed
	position_around_base = |face, location, placed, base, end, backward, target_backward, upem, adjust| Shaper.position_around_base_axis(face, location, placed, base, end, backward, target_backward, upem, adjust, False)

	position_around_base_axis : Face, Face.Location, Placed, U64, U64, Bool, Bool, I64, Bool, Bool -> Placed
	position_around_base_axis = |face, location, placed, base, end, backward, target_backward, upem, adjust, vertical| {
		{ items: items0, ax: ax0, dx: dx0, dy: dy0 } = placed
		items = if (end - base <= 255) LayoutGsub.flag_range(items0, base, end, LayoutGsub.end_cluster(items0, base, end, 0xFFFFFFFFFFFFFFFF)) else items0
		base_item = items.get(base) ?? LayoutGsub.no_item
		raw = Shaper.extents_of(face, base_item.glyph)
		base_extents = { ..raw, x_bearing: 0, width: Face.advance(face, location, base_item.glyph).to_i64(), y_bearing: raw.y_bearing + (if (vertical) dx0.get(base) ?? 0 else dy0.get(base) ?? 0) }
		lig_id = LayoutGsub.lig_id(base_item)
		num_components = LayoutGsub.num_comps(base_item).to_i64_wrap()
		var $ax = ax0
		var $dx = dx0
		var $dy = dy0
		var $x_offset = if (!backward) -($ax.get(base) ?? 0) else 0
		var $component = base_extents
		var $last_component = -1
		var $last_class = 255
		var $cluster = base_extents
		for i in (base + 1)..<end {
			item = items.get(i) ?? LayoutGsub.no_item
			this_class = ShaperUnicode.class_of(item.props)
			if this_class != 0 {
				if num_components > 1 {
					this_id = LayoutGsub.lig_id(item)
					comp = LayoutGsub.lig_comp(item).to_i64_wrap() - 1
					this_component = if (lig_id == 0 or lig_id != this_id or comp >= num_components) num_components - 1 else comp
					if $last_component != this_component {
						$last_component = this_component
						$last_class = 255
						x = if (!target_backward) base_extents.x_bearing + this_component * base_extents.width // num_components else base_extents.x_bearing + (num_components - 1 - this_component) * base_extents.width // num_components
						$component = { ..base_extents, x_bearing: x, width: base_extents.width // num_components }
					}
				}
				if $last_class != this_class {
					$last_class = this_class
					$cluster = $component
				}
				{ extents, x, y } = Shaper.position_mark_axis(face, $cluster, item.glyph, this_class, backward, upem, vertical)
				$cluster = extents
				# `i < end <= count`.
				$ax = $ax.set(i, 0) ?? []
				$dx = $dx.set(i, if (vertical) y + $x_offset else x + $x_offset) ?? []
				$dy = $dy.set(i, if (vertical) x else y) ?? []
			} else {
				$x_offset = if (!backward) $x_offset - ($ax.get(i) ?? 0) else $x_offset + ($ax.get(i) ?? 0)
			}
		}
		_ = adjust
		{ items, ax: $ax, dx: $dx, dy: $dy }
	}

	## HarfBuzz's `position_mark`: a mark's offset from the cluster's ink
	## by its class, and the cluster's ink after stacking the mark.
	position_mark : Face, Extents, U64, U64, Bool, I64 -> { extents : Extents, x : I64, y : I64 }
	position_mark = |face, base_in, glyph, klass, backward, upem| Shaper.position_mark_axis(face, base_in, glyph, klass, backward, upem, False)

	position_mark_axis : Face, Extents, U64, U64, Bool, I64, Bool -> { extents : Extents, x : I64, y : I64 }
	position_mark_axis = |face, base_in, glyph, klass, backward, upem, vertical| {
		mark = Shaper.extents_of(face, glyph)
		y_gap = upem // 16
		x =
			if !vertical and (klass == 233 or klass == 234) and !backward {
				base_in.x_bearing + base_in.width - mark.width // 2 - mark.x_bearing
			} else if !vertical and (klass == 233 or klass == 234) {
				base_in.x_bearing - mark.width // 2 - mark.x_bearing
			} else if klass == 200 or klass == 218 or klass == 228 {
				# Left aligned.
				base_in.x_bearing - mark.x_bearing
			} else if klass == 216 or klass == 222 or klass == 232 {
				# Right aligned.
				base_in.x_bearing + base_in.width - mark.width - mark.x_bearing
			} else {
				# Centred.
				base_in.x_bearing + (base_in.width - mark.width) // 2 - mark.x_bearing
			}
		below = klass == 233 or klass == 218 or klass == 220 or klass == 222
		attached_below = klass == 200 or klass == 202
		above = klass == 234 or klass == 228 or klass == 230 or klass == 232
		attached_above = klass == 214 or klass == 216
		if below or attached_below {
			b0 = if (below) { ..base_in, height: base_in.height - y_gap } else base_in
			y0 = b0.y_bearing + b0.height - mark.y_bearing
			{ height, y } = if ((y_gap > 0) == (y0 > 0)) { height: b0.height - y0, y: 0 } else { height: b0.height, y: y0 }
			{ extents: { ..b0, height: height + mark.height }, x, y }
		} else if above or attached_above {
			b0 = if (above) { ..base_in, y_bearing: base_in.y_bearing + y_gap, height: base_in.height - y_gap } else base_in
			y0 = b0.y_bearing - mark.y_bearing - mark.height
			{ b1, y } =
				if (y_gap > 0) != (y0 > 0) {
					correction = -(y0 // 2)
					{ b1: { ..b0, y_bearing: b0.y_bearing + correction, height: b0.height - correction }, y: y0 + correction }
				} else {
					{ b1: b0, y: y0 }
				}
			{ extents: { ..b1, y_bearing: b1.y_bearing - mark.height, height: b1.height + mark.height }, x, y }
		} else {
			{ extents: base_in, x, y: 0 }
		}
	}

	## Default-ignorable characters drawn with the space glyph, or removed
	## (their clusters merged) when the font has none (HarfBuzz's
	## `hb_ot_hide_default_ignorables`).
	hide_ignorables : Face, Placed -> Placed
	hide_ignorables = |face, placed|
		match Face.glyph(face, ' ') {
			Ok(space) => { ..placed, items: placed.items.map(|item| if (LayoutGsub.is_default_ignorable(item)) { ..item, glyph: space } else item) }
			Err(_) => {
				items = placed.items
				count = items.len()
				var $items = List.with_capacity(count)
				var $ax = List.with_capacity(count)
				var $dx = List.with_capacity(count)
				var $dy = List.with_capacity(count)
				var $merged = items
				for i in 0..<count {
					item = $merged.get(i) ?? LayoutGsub.no_item
					if LayoutGsub.is_default_ignorable(item) {
						cluster = item.cluster
						shares_next = i + 1 < count and ($merged.get(i + 1) ?? LayoutGsub.no_item).cluster == cluster
						if !shares_next {
							match $items.last() {
								Ok(last) =>
									if cluster < last.cluster {
										old = last.cluster
										var $k = $items.len()
										while $k > 0 and ($items.get($k - 1) ?? LayoutGsub.no_item).cluster == old {
											kept = $items.get($k - 1) ?? LayoutGsub.no_item
											# `$k - 1` is below the kept list's length.
											$items = $items.set($k - 1, { ..kept, cluster, mask: kept.mask.bitwise_and(0x7FFFFFFFFFFFFFFF).bitwise_or(item.mask.bitwise_and(LayoutGsub.unsafe)) }) ?? []
											$k = $k - 1
										}
									}
								Err(_) =>
									if i + 1 < count {
										$merged = Shaper.merge_items($merged, i, i + 2)
									}
							}
						}
					} else {
						$items = $items.append(item)
						$ax = $ax.append(placed.ax.get(i) ?? 0)
						$dx = $dx.append(placed.dx.get(i) ?? 0)
						$dy = $dy.append(placed.dy.get(i) ?? 0)
					}
				}
				{ items: $items, ax: $ax, dx: $dx, dy: $dy }
			}
		}

	## HarfBuzz's `merge_clusters` on a finished run (no output list).
	merge_items : List(LayoutGsub.Item), U64, U64 -> List(LayoutGsub.Item)
	merge_items = |items, start, end_in|
		if end_in <= start + 1 {
			items
		} else {
			n = items.len()
			at = |i| (items.get(i) ?? LayoutGsub.no_item).cluster
			cluster = LayoutGsub.min_cluster(items, start, end_in.min(n), at(start))
			var $end = end_in.min(n)
			if cluster != at($end - 1) {
				while $end < n and at($end - 1) == at($end) {
					$end = $end + 1
				}
			}
			var $start = start
			if cluster != at($start) {
				while $start > 0 and at($start - 1) == at($start) {
					$start = $start - 1
				}
			}
			var $items = items
			for i in $start..<$end {
				# `i < $end <= n`.
				$items = $items.set(i, LayoutGsub.set_cluster($items.get(i) ?? LayoutGsub.no_item, cluster)) ?? []
			}
			$items
		}

	## The run in output order, with unsafe-to-break flags the same on every
	## glyph of a cluster.
	finish : Placed -> Run
	finish = |placed| Shaper.finish_axis(placed, False)

	finish_axis : Placed, Bool -> Run
	finish_axis = |placed, vertical| {
		items = placed.items
		count = items.len()
		var $glyphs = List.with_capacity(count)
		var $advances = List.with_capacity(count)
		var $offsets = List.with_capacity(count)
		var $clusters = List.with_capacity(count)
		for k in 0..<count {
			item = items.get(k) ?? LayoutGsub.no_item
			$glyphs = $glyphs.append(item.glyph.min(0xFFFFFFFF).to_u32_wrap())
			$advances = $advances.append(if (vertical) { x: 0, y: Shaper.clamp(placed.ax.get(k) ?? 0) } else { x: Shaper.clamp(placed.ax.get(k) ?? 0), y: 0 })
			$offsets = $offsets.append(if (vertical) { x: Shaper.clamp(placed.dy.get(k) ?? 0), y: Shaper.clamp(placed.dx.get(k) ?? 0) } else { x: Shaper.clamp(placed.dx.get(k) ?? 0), y: Shaper.clamp(placed.dy.get(k) ?? 0) })
			$clusters = $clusters.append(item.cluster)
		}
		{ glyphs: $glyphs, advances: $advances, offsets: $offsets, clusters: $clusters, flags: Shaper.flags(items) }
	}

	reversed : List(a) -> List(a)
	reversed = |list| {
		n = list.len()
		var $out = List.with_capacity(n)
		var $k = n
		while $k > 0 {
			match list.get($k - 1) {
				Ok(x) => {
					$out = $out.append(x)
				}
				Err(_) => {}
			}
			$k = $k - 1
		}
		$out
	}

	## Glyph flags: bit 0 unsafe to break, the same on every glyph of a
	## cluster (consecutive glyphs with one cluster), as HarfBuzz's
	## `hb_propagate_flags` makes it; bit 1 missing, on a glyph 0 drawn for
	## a character the font does not map.
	flags : List(LayoutGsub.Item) -> List(U8)
	flags = |items| {
		count = items.len()
		var $out = List.with_capacity(count)
		var $k = 0
		while $k < count {
			cluster = (items.get($k) ?? LayoutGsub.no_item).cluster
			var $end = $k
			var $unsafe = False
			while $end < count and (items.get($end) ?? LayoutGsub.no_item).cluster == cluster {
				if (items.get($end) ?? LayoutGsub.no_item).mask.bitwise_and(LayoutGsub.unsafe) != 0 {
					$unsafe = True
				}
				$end = $end + 1
			}
			for j in $k..<$end {
				item = items.get(j) ?? LayoutGsub.no_item
				missing = if (item.glyph == 0 and item.props.bitwise_and(ShaperNormalize.missing) != 0) 2 else 0
				$out = $out.append((if ($unsafe) 1.U8 else 0).bitwise_or(missing))
			}
			$k = $end
		}
		$out
	}

	## The text range each glyph draws (`Font.cluster_ranges`): from its
	## cluster to the next larger cluster of the run, or `length` when none
	## is larger; empty at the cluster when the cluster is at or past
	## `length`. The larger clusters come from the run's distinct clusters
	## in increasing order (one pass and one list for the monotone runs
	## shaping gives), searched by bisection, so any order of clusters has
	## a defined result.
	cluster_ranges : List(U64), U64 -> List({ start : U64, end : U64 })
	cluster_ranges = |clusters, length| {
		distinct = Sorted.unique(clusters)
		n = distinct.len()
		var $out = List.with_capacity(clusters.len())
		for c in clusters {
			if c >= length {
				$out = $out.append({ start: c, end: c })
			} else {
				# The first distinct cluster above `c`.
				var $low = 0
				var $high = n
				while $low < $high {
					mid = ($low + $high) // 2
					if (distinct.get(mid) ?? 0) <= c {
						$low = mid + 1
					} else {
						$high = mid
					}
				}
				next = if ($low < n) distinct.get($low) ?? length else length
				$out = $out.append({ start: c, end: next.min(length) })
			}
		}
		$out
	}

	# ------------------------------------------------------------ origins

	## Which substitution produced each glyph of a traced run, by the
	## public `GlyphOrigin` kinds.
	Origin : [Mapped, Substituted({ feature : Str }), Ligature({ feature : Str, components : U32 }), Multiple({ feature : Str }), Inserted({ feature : Str })]

	## Which of several features listing one lookup an origin credits
	## first: `liga` (0), then the features shaping applies by default
	## (1), then the others (2); ties go by tag.
	credit_rank : U64 -> U64
	credit_rank = |t|
		if t == Shaper.liga_tag {
			0
		} else if Shaper.default_tags.contains(t) {
			1
		} else {
			2
		}

	liga_tag : U64
	liga_tag = Shaper.tag("liga")

	## The tags of every default request, in either direction.
	default_tags : List(U64)
	default_tags = Shaper.ltr_requests.concat(Shaper.rtl_requests).map(|r| r.tag)

	## The features that list each `GSUB` step's lookup, in the plan's step
	## order, each step's features in the order origins credit them
	## (`credit_rank`, then tag), with each tag's
	## text made once here (not once per glyph). Built as
	## `lookups` builds the steps (stage by stage, each stage in lookup
	## order, from the required feature and the mapped features of the
	## stage, their lookups replaced by feature variations), so the lists
	## align with `p.gsub`. Only traced shaping calls it.
	step_features : Face, Plan -> List(List({ rank : U64, tag : U64, mask : U64, text : Str }))
	step_features = |face, p| {
		common = LayoutGsub.common_of(Face.gsub(face))
		varied = { subs: p.gsub_subs, fv: Face.feature_variations(face).gsub, lookup_vars: p.gsub_lookup_vars }
		feature_lookups = |index| Shaper.varied_feature_lookups(common, varied, index)
		stages = p.gsub_stage_count
		var $out = []
		for stage in 0..<stages {
			if p.arabic and stage == 11 {
				for credit in ShaperArabicFallback.credits(p.arabic_fallback) {
					$out = $out.append([{ rank: Shaper.credit_rank(credit.tag), tag: credit.tag, mask: credit.mask, text: Shaper.tag_text(credit.tag) }])
				}
			}
			var $found = List.repeat([], common.lookup_count)
			add = |found, lookup, wanted, rank, mask| {
				entry = { rank, tag: wanted, mask, text: Shaper.tag_text(wanted) }
				list = found.get(lookup) ?? []
				var $at = list.len()
				while $at > 0 and Shaper.credited_after(list.get($at - 1) ?? entry, entry) {
					$at = $at - 1
				}
				# Feature lookups are below the lookup count, the list's length.
				found.set(lookup, list.take_first($at).append(entry).concat(list.drop_first($at))) ?? []
			}
			if p.gsub_required != LayoutCommon.no_feature and p.gsub_required_stage == stage {
				required_tag = LayoutCommon.feature_tag(common, p.gsub_required)
				for lookup in feature_lookups(p.gsub_required) {
					# The required feature always applies, as defaults do.
					$found = add($found, lookup, required_tag, Shaper.credit_rank(required_tag).min(1), Shaper.global_bit)
				}
			}
			for m in p.mapped {
				if m.gsub != LayoutCommon.no_feature and m.stage.min(stages - 1) == stage {
					for lookup in feature_lookups(m.gsub) {
						$found = add($found, lookup, m.tag, Shaper.credit_rank(m.tag), m.mask)
					}
				}
			}
			for features in $found {
				if !features.is_empty() {
					$out = $out.append(features)
				}
			}
		}
		$out
	}

	## Whether origins credit feature `a` after feature `b`.
	credited_after : { rank : U64, tag : U64, mask : U64, text : Str }, { rank : U64, tag : U64, mask : U64, text : Str } -> Bool
	credited_after = |a, b| a.rank > b.rank or (a.rank == b.rank and a.tag > b.tag)

	## A four-byte tag as text, as the font stores it (bytes that are not
	## UTF-8 become U+FFFD).
	# A tag's four bytes as ISO 8859-1, so every tag is four characters and
	# distinct tags stay distinct (OTS does not limit tags to ASCII).
	tag_text : U64 -> Str
	tag_text = |t| TablePost.latin1([24, 16, 8, 0].map(|s| t.shr_zf_wrap(s).bitwise_and(0xFF).to_u8_wrap()), 0, 4)

	## The origin of every glyph of a finished run (`Shaped.items`): what
	## made it, and the feature of the plan step that made it. A step's
	## lookup that several features list is credited to the first of them,
	## in `step_features` order, that is on for the glyph (to the first of them when
	## none is: a lookup a contextual rule called may change a glyph the
	## rule's feature is not on for).
	origins : Face, Plan, List(LayoutGsub.Item) -> List(Origin)
	origins = |face, p, items| {
		features = Shaper.step_features(face, p)
		items.map(
			|item| {
				kind = LayoutGsub.origin_kind(item)
				if kind == LayoutGsub.origin_mapped {
					Mapped
				} else {
					candidates = features.get(LayoutGsub.origin_step(item)) ?? []
					# Every step has a feature that lists its lookup, so a
					# candidate exists; "" is never seen.
					feature = match candidates.find_first(|c| c.mask.bitwise_and(item.mask) != 0) {
						Ok(c) => c.text
						Err(_) =>
							match candidates.first() {
								Ok(c) => c.text
								Err(_) => ""
							}
					}
					if kind == LayoutGsub.origin_ligature {
						Ligature({ feature, components: LayoutGsub.origin_components(item).to_u32_wrap() })
					} else if kind == LayoutGsub.origin_multiple {
						Multiple({ feature: feature })
					} else if kind == LayoutGsub.origin_inserted {
						Inserted({ feature: feature })
					} else {
						Substituted({ feature: feature })
					}
				}
			},
		)
	}

	## The bounds a `Shaped.stopped` names, in the order growth,
	## operations, depth.
	budgets : U64 -> List([Growth, Operations, Depth])
	budgets = |stopped| {
		var $out = []
		if stopped.bitwise_and(LayoutGsub.stopped_growth) != 0 {
			$out = $out.append(Growth)
		}
		if stopped.bitwise_and(LayoutGsub.stopped_operations) != 0 {
			$out = $out.append(Operations)
		}
		if stopped.bitwise_and(LayoutGsub.stopped_depth) != 0 {
			$out = $out.append(Depth)
		}
		$out
	}
}

# The complete default Indic selection fits below the global bit and
# leaves metadata bits 32..63 untouched, even when rand needs eight bits.
expect {
	[Shaper.indic_ltr_merged, Shaper.indic_rtl_merged, Shaper.khmer_ltr_merged, Shaper.khmer_rtl_merged, Shaper.myanmar_ltr_merged, Shaper.myanmar_rtl_merged, Shaper.use_ltr_merged, Shaper.use_rtl_merged].all(
		|requests| {
			bits = requests.fold(0.U64, |total, r| total + (if (r.global and r.max == 1) 0 else Shaper.bit_storage(r.max).min(8)))
			Shaper.first_bit + bits < Shaper.global_shift
		},
	)
}

# Fallback placement consumes the same modified classes as normalization.
expect Shaper.recategorize(0x064F, ShaperUnicode.modified_combining_class(0x064F)) == 230 and Shaper.recategorize(0x0650, ShaperUnicode.modified_combining_class(0x0650)) == 220
expect Shaper.recategorize(0x05B4, ShaperUnicode.modified_combining_class(0x05B4)) == 220 and Shaper.recategorize(0x05BF, ShaperUnicode.modified_combining_class(0x05BF)) == 214
expect Shaper.recategorize(0x05C1, ShaperUnicode.modified_combining_class(0x05C1)) == 232 and Shaper.recategorize(0x05C2, ShaperUnicode.modified_combining_class(0x05C2)) == 228
expect Shaper.recategorize(0x0F72, ShaperUnicode.modified_combining_class(0x0F72)) == 230 and Shaper.recategorize(0x0F74, ShaperUnicode.modified_combining_class(0x0F74)) == 220
