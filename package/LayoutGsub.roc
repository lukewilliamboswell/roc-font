import Sfnt
import LayoutCommon
import LayoutGdef
import LayoutVar
import ShaperUnicode

## Glyph substitution from a font's `GSUB` table, applied as HarfBuzz
## 14.6.0 applies it (`hb-ot-layout-gsubgpos.hh`, `hb-ot-layout-gsub-table.hh`,
## `hb-buffer.cc`): single, multiple, alternate and ligature substitutions,
## contextual and chained contextual rules, and reverse chaining single
## substitutions (lookup types 1 to 8), honouring lookup flags (ignore base
## glyphs, ligatures or marks, a mark attachment type or a mark filtering
## set) with glyph classes from `GDEF`. Which lookups apply (the features
## chosen for a script, language and direction) is the plan's business
## (`Shaper`); this module reads every lookup a feature can reach and
## applies a list of them.
##
## The value also carries the font's `GDEF` glyph classes, mark attachment
## classes and mark glyph sets (`LayoutGdef`, read once by `Face` and shared
## with `GPOS`), which lookup flags consult; `Face` attaches them with
## `with_gdef`.
##
## The prepared data is flat: every subtable, coverage range, glyph value
## and contextual rule of the font lives in one of five lists, and nested
## structure is expressed by offsets and lengths into them. Reading
## allocates per list, not per ligature or rule, and applying reads only
## scalar records, so looking at a subtable costs no reference counting.
##
## A glyph of a run (`Item`) carries its cluster (the text offset it came
## from), a mask (one bit field per feature of the plan, as HarfBuzz
## allocates them, and `unsafe`, the unsafe-to-break flag) and its
## properties: HarfBuzz's Unicode property word (bits 0-15, see
## `ShaperUnicode.props`), its glyph properties (bits 16-31: class flags,
## substitution flags, mark attachment type) and its ligature properties
## (bits 32-39: ligature id and component). Applying follows HarfBuzz's
## buffer model, an input and an output list with a cursor, so clusters
## merge and flags are set exactly where HarfBuzz merges and sets them at
## its monotone cluster levels.
LayoutGsub := {
	common : LayoutCommon,
	lookups : List({ start : U64, count : U64, mode : U64, d0 : U64, d1 : U64, d2 : U64, props : U64, reverse : Bool }),
	subtables : List(
		{
			kind : U64,
			coverage : U64,
			coverage_len : U64,
			delta : I64,
			data : U64,
			data_len : U64,
			match_kind : U64,
			back : U64,
			back_len : U64,
			input : U64,
			input_len : U64,
			ahead : U64,
			ahead_len : U64,
		},
	),
	ranges : List({ first : U64, last : U64, index : U64 }),
	values : List(U64),
	rules : List({ back : U64, back_len : U64, input : U64, input_len : U64, ahead : U64, ahead_len : U64, records : U64, records_len : U64 }),
	gdef : LayoutGdef,
}.{

	Range : { first : U64, last : U64, index : U64 }

	Ranges : List(Range)

	## One lookup: its subtables are `subtables[start ..< start + count]`.
	## `mode` is 0 when every subtable is a single substitution (applied in
	## place), 2 otherwise. `d0`, `d1` and `d2` are a digest of every glyph
	## its subtables cover (see `may_start`). `props` are HarfBuzz's lookup
	## properties: the lookup flag, plus the mark filtering set times 65536
	## when the flag uses one. `reverse` for a reverse chaining lookup. A
	## lookup no feature reaches is not read and has no subtables.
	Lookup : { start : U64, count : U64, mode : U64, d0 : U64, d1 : U64, d2 : U64, props : U64, reverse : Bool }

	## One subtable. `coverage` and `coverage_len` select its coverage in
	## `ranges`. By `kind`:
	##
	## - 1 (single): `delta` when `data_len` is 0, else the substitutes are
	##   `values[data ..< data + data_len]`.
	## - 2 (multiple) and 3 (alternate): `data_len` glyph sequences;
	##   `values[data + s]` and `values[data + s + 1]` bound sequence `s` in
	##   `values`.
	## - 4 (ligature): `data_len` ligature sets bounded likewise in `values`;
	##   a set holds ligatures as `glyph, n, component 2, ..., component n+1`.
	## - 5 (context and chained context): `data_len` rule sets bounded
	##   likewise in `rules`. `match_kind` is 0 for glyphs, 1 for classes
	##   (`back`, `input` and `ahead` select the class definitions in
	##   `ranges`), 2 for coverages (each match is a start and length in
	##   `ranges`, two values). `delta` is 1 for a chained subtable.
	## - 8 (reverse chaining single): backtrack and lookahead coverages at
	##   `back` and `ahead` in `values` (`back_len` and `ahead_len` of them,
	##   two values each), the substitutes `values[data ..< data + data_len]`.
	Sub : {
		kind : U64,
		coverage : U64,
		coverage_len : U64,
		delta : I64,
		data : U64,
		data_len : U64,
		match_kind : U64,
		back : U64,
		back_len : U64,
		input : U64,
		input_len : U64,
		ahead : U64,
		ahead_len : U64,
	}

	## A contextual rule: spans of matches in `values` (the input after its
	## first glyph, backtrack nearest first, lookahead), and its nested
	## lookup records as `at, lookup` pairs.
	Rule : { back : U64, back_len : U64, input : U64, input_len : U64, ahead : U64, ahead_len : U64, records : U64, records_len : U64 }

	## The lists being filled while reading, and the reading work spent.
	Built : { subtables : List(Sub), ranges : Ranges, values : List(U64), rules : List(Rule), steps : U64 }

	## One glyph of a run (see the module notes).
	Item : { glyph : U64, cluster : U64, mask : U64, props : U64 }

	## One lookup of a plan: its index, its feature mask, whether ZWJ and
	## ZWNJ are skipped automatically, and whether it is the `rand` feature's.
	Step : { index : U64, mask : U64, auto_zwnj : Bool, auto_zwj : Bool, random : Bool }

	## The bounds of one application: a run never grows past `limit`
	## glyphs, lookups called from contextual rules are applied at most
	## `budget` times in all, and at most `depth` deep.
	Limits : { limit : U64, budget : U64, depth : U64 }

	## What applying a plan gives: the run, and which bounds stopped work
	## (`stopped_growth`, `stopped_operations` and `stopped_depth` bits; 0
	## when none did, so the run is complete).
	Applied : { items : List(Item), stopped : U64 }

	## What a lookup is applied with: its mask and properties, the joiner
	## rules, `rand`, and the index in the plan of the step being applied
	## (recorded in the origin of every glyph it substitutes, also through
	## nested lookups).
	Ctx : { mask : U64, props : U64, auto_zwnj : Bool, auto_zwj : Bool, random : Bool, step : U64 }

	## HarfBuzz's buffer while a lookup applies: the input `info` read from
	## `idx`, and, when `output`, the output written so far. `serial`
	## numbers ligatures, `random` is the `rand` feature's state, `ops`
	## the nested lookups applied so far and `stopped` the bounds that
	## stopped work so far (see `Applied`).
	Buf : { info : List(Item), out : List(Item), idx : U64, output : Bool, serial : U64, random : U64, ops : U64, stopped : U64 }

	## A contextual rule being applied (HarfBuzz's `apply_lookup`): its
	## nested lookup records, the next one, how many matched positions it
	## has (in `positions` from `base`), where its match ends, and the
	## position and length saved around a nested lookup.
	Frame : { records : U64, records_len : U64, next : U64, count : U64, end : U64, base : U64, saved_at : U64, saved_len : U64 }

	## Reusable lists for applying: matched positions of the subtable being
	## tried, the frames of contextual rules and their positions.
	Work : { scratch : List(U64), frames : List(Frame), positions : List(U64) }

	## What applying a subtable did.
	Outcome : [Applied, NotApplied, Context({ count : U64, records : U64, records_len : U64, end : U64 })]

	## No substitutions.
	none : LayoutGsub
	none = { common: LayoutCommon.none, lookups: [], subtables: [], ranges: [], values: [], rules: [], gdef: LayoutGdef.none }

	## The unsafe-to-break flag in an item's mask. Lookup masks never hold it.
	unsafe : U64
	unsafe = 0x8000000000000000

	## The bounds that can stop work, as bits of `stopped`: a substitution
	## not made because the run would outgrow `Limits.limit`, a rule's
	## lookups not called because `Limits.budget` was spent, and a rule's
	## lookups not called because they were deeper than `Limits.depth`.
	stopped_growth : U64
	stopped_growth = 1

	stopped_operations : U64
	stopped_operations = 2

	stopped_depth : U64
	stopped_depth = 4

	## The longest input a contextual rule may match (HarfBuzz's
	## `HB_MAX_CONTEXT_LENGTH`); longer rules never match.
	max_context : U64
	max_context = 64

	no_item : Item
	no_item = { glyph: 0, cluster: 0, mask: 0, props: 0 }

	no_lookup : Lookup
	no_lookup = { start: 0, count: 0, mode: 0, d0: 0, d1: 0, d2: 0, props: 0, reverse: False }

	no_sub : Sub
	no_sub = { kind: 0, coverage: 0, coverage_len: 0, delta: 0, data: 0, data_len: 0, match_kind: 0, back: 0, back_len: 0, input: 0, input_len: 0, ahead: 0, ahead_len: 0 }

	no_rule : Rule
	no_rule = { back: 0, back_len: 0, input: 0, input_len: 0, ahead: 0, ahead_len: 0, records: 0, records_len: 0 }

	no_frame : Frame
	no_frame = { records: 0, records_len: 0, next: 0, count: 0, end: 0, base: 0, saved_at: 0, saved_len: 0 }

	## The script and feature lists, for choosing lookups.
	common_of : LayoutGsub -> LayoutCommon
	common_of = |shape| shape.common

	## The substitutions with the font's `GDEF` glyph classes, which lookup
	## flags and the glyph properties of substituted glyphs use.
	with_gdef : LayoutGsub, LayoutGdef -> LayoutGsub
	with_gdef = |shape, gdef| { ..shape, gdef }

	# ------------------------------------------------------------ glyph properties

	## HarfBuzz's glyph property flags (the low byte of `glyph_props`). The
	## class flags equal the lookup flags that ignore them.
	base_glyph : U64
	base_glyph = 0x02

	ligature : U64
	ligature = 0x04

	mark : U64
	mark = 0x08

	substituted : U64
	substituted = 0x10

	ligated : U64
	ligated = 0x20

	multiplied : U64
	multiplied = 0x40

	preserve : U64
	preserve = 0x70

	## Whether the font has `GDEF` glyph classes.
	has_glyph_classes : LayoutGsub -> Bool
	has_glyph_classes = |shape| LayoutGdef.has_glyph_classes(shape.gdef)

	## A glyph's properties from `GDEF` (see `LayoutGdef.glyph_props`).
	glyph_props : LayoutGsub, U64 -> U64
	glyph_props = |shape, glyph| LayoutGdef.glyph_props(shape.gdef, glyph)

	## Lookup properties with a mark filtering set the font does not have
	## turned off, as HarfBuzz's `sanitize_lookup_props`.
	sanitize_props : LayoutGsub, U64 -> U64
	sanitize_props = |shape, props| LayoutGdef.sanitize_props(shape.gdef, props)

	## Whether lookup properties let a lookup see a glyph (HarfBuzz's
	## `check_glyph_property`).
	check_glyph_property : LayoutGsub, Item, U64 -> Bool
	check_glyph_property = |shape, item, match_props| LayoutGdef.check_glyph_property(shape.gdef, item.glyph, LayoutGsub.gprops(item), match_props)

	gprops : Item -> U64
	gprops = |item| item.props.shr_zf_wrap(16).bitwise_and(0xFFFF)

	with_gprops : Item, U64 -> Item
	with_gprops = |item, g| { ..item, props: item.props.bitwise_and(0xFFFFFFFF0000FFFF).bitwise_or(g.bitwise_and(0xFFFF).shl_wrap(16)) }

	lprops : Item -> U64
	lprops = |item| item.props.shr_zf_wrap(32).bitwise_and(0xFF)

	with_lprops : Item, U64 -> Item
	with_lprops = |item, l| { ..item, props: item.props.bitwise_and(0xFFFFFF00FFFFFFFF).bitwise_or(l.bitwise_and(0xFF).shl_wrap(32)) }

	lig_id : Item -> U64
	lig_id = |item| LayoutGsub.lprops(item).shr_zf_wrap(5)

	lig_comp : Item -> U64
	lig_comp = |item| {
		l = LayoutGsub.lprops(item)
		if (l.bitwise_and(0x10) != 0) 0 else l.bitwise_and(0x0F)
	}

	num_comps : Item -> U64
	num_comps = |item| {
		l = LayoutGsub.lprops(item)
		if (LayoutGsub.gprops(item).bitwise_and(LayoutGsub.ligature) != 0 and l.bitwise_and(0x10) != 0) l.bitwise_and(0x0F) else 1
	}

	num_comps_in_ligation : Item -> U64
	num_comps_in_ligation = |item|
		if (LayoutGsub.gprops(item).bitwise_and(LayoutGsub.multiplied) != 0 and LayoutGsub.lig_comp(item) != 0) 0 else LayoutGsub.num_comps(item)

	is_mark_item : Item -> Bool
	is_mark_item = |item| LayoutGsub.gprops(item).bitwise_and(LayoutGsub.mark) != 0

	## Default ignorable and not yet substituted (HarfBuzz's
	## `_hb_glyph_info_is_default_ignorable`).
	is_default_ignorable : Item -> Bool
	is_default_ignorable = |item| item.props.bitwise_and(ShaperUnicode.ignorable) != 0 and LayoutGsub.gprops(item).bitwise_and(LayoutGsub.substituted) == 0

	## An item's glyph properties after substituting `glyph`, as HarfBuzz's
	## `_set_glyph_class`.
	set_glyph_class : LayoutGsub, Item, U64, U64, Bool, Bool -> Item
	set_glyph_class = |shape, item, glyph, class_guess, as_ligature, component| {
		base = LayoutGsub.gprops(item).bitwise_or(LayoutGsub.substituted)
		with_ligature = if (as_ligature) base.bitwise_or(LayoutGsub.ligated).bitwise_and(0xFFFF - LayoutGsub.multiplied) else base
		flags = if (component) with_ligature.bitwise_or(LayoutGsub.multiplied) else with_ligature
		props =
			if LayoutGdef.has_glyph_classes(shape.gdef) {
				flags.bitwise_and(LayoutGsub.preserve).bitwise_or(LayoutGsub.glyph_props(shape, glyph))
			} else if class_guess != 0 {
				flags.bitwise_and(LayoutGsub.preserve).bitwise_or(class_guess)
			} else {
				flags
			}
		LayoutGsub.with_gprops(item, props)
	}

	# ------------------------------------------------------------ origins

	## Which substitution produced a glyph, for `Font.shape_traced`. Kept
	## in bits no other part of an item uses: the kind in props bits 41-43,
	## the plan step that made the substitution in props bits 44-60, and a
	## ligature's component count in mask bits 32-38. A plan has fewer
	## than 2^17 steps (two stages of at most 65535 lookups, the format's
	## count), and a ligature at most `max_context` (64) components.
	## Writing the bits costs no allocation, so untraced shaping pays
	## nothing measurable for them.
	##
	## Kinds: `origin_mapped` (0, from the character map, never
	## substituted), `origin_substituted` (one glyph for one), and the
	## structural kinds `origin_ligature` (several glyphs joined into one),
	## `origin_multiple` (the first glyph a multiple substitution wrote)
	## and `origin_inserted` (the further glyphs it wrote). A one-for-one
	## substitution of a glyph of a structural kind keeps the kind (and a
	## ligature's component count), because it does not change how many
	## characters the glyph draws; the step is always the last one.
	origin_mapped : U64
	origin_mapped = 0

	origin_substituted : U64
	origin_substituted = 1

	origin_ligature : U64
	origin_ligature = 2

	origin_multiple : U64
	origin_multiple = 3

	origin_inserted : U64
	origin_inserted = 4

	origin_kind : Item -> U64
	origin_kind = |item| item.props.shr_zf_wrap(41).bitwise_and(0x7)

	origin_step : Item -> U64
	origin_step = |item| item.props.shr_zf_wrap(44).bitwise_and(0x1FFFF)

	origin_components : Item -> U64
	origin_components = |item| item.mask.shr_zf_wrap(32).bitwise_and(0x7F)

	## An item with its origin set.
	with_origin : Item, U64, U64, U64 -> Item
	with_origin = |item, kind, step, components| {
		props = item.props.bitwise_and(0xE00001FFFFFFFFFF).bitwise_or(kind.bitwise_and(0x7).shl_wrap(41)).bitwise_or(step.bitwise_and(0x1FFFF).shl_wrap(44))
		mask = item.mask.bitwise_and(0xFFFFFF80FFFFFFFF).bitwise_or(components.bitwise_and(0x7F).shl_wrap(32))
		{ ..item, props, mask }
	}

	## An item after a one-for-one substitution made by step `step`.
	resubstituted : Item, U64 -> Item
	resubstituted = |item, step| {
		kind = LayoutGsub.origin_kind(item)
		if kind == LayoutGsub.origin_mapped or kind == LayoutGsub.origin_substituted {
			LayoutGsub.with_origin(item, LayoutGsub.origin_substituted, step, 0)
		} else {
			LayoutGsub.with_origin(item, kind, step, LayoutGsub.origin_components(item))
		}
	}

	# ------------------------------------------------------------ applying

	## Apply lookups to a run, in the order given; each applies where a
	## glyph's mask shares a bit with the lookup's `mask`. Each lookup passes
	## over the run once, left to right (a reverse chaining lookup right to
	## left). Past `limits`, a substitution that would grow the run past its
	## limit is not made, and contextual rules match but call no more
	## lookups; the run stays total and finite.
	apply : LayoutGsub, List(Step), List(Item), Limits -> Applied
	apply = |shape, plan, items, limits| {
		var $run = items
		# The previous run of a general lookup, whose allocation the next one
		# writes into.
		var $spare = []
		var $serial = 0
		var $random = 1
		var $ops = 0
		var $stopped = 0
		var $work = { scratch: [], frames: [], positions: [] }
		for step_index in 0..<plan.len() {
			step = plan.get(step_index) ?? { index: 0, mask: 0, auto_zwnj: False, auto_zwj: False, random: False }
			lookup = shape.lookups.get(step.index) ?? LayoutGsub.no_lookup
			if lookup.count > 0 and LayoutGsub.any_start(lookup, $run, step.mask) {
				ctx = { mask: step.mask, props: LayoutGsub.sanitize_props(shape, lookup.props), auto_zwnj: step.auto_zwnj, auto_zwj: step.auto_zwj, random: step.random, step: step_index }
				if lookup.reverse {
					{ buf, work } = LayoutGsub.apply_backward(shape, lookup, ctx, { info: $run, out: [], idx: 0, output: False, serial: $serial, random: $random, ops: $ops, stopped: $stopped }, limits, $work)
					{ info, out: _, idx: _, output: _, serial, random, ops, stopped } = buf
					$run = info
					$serial = serial
					$random = random
					$ops = ops
					$stopped = stopped
					$work = work
				} else if lookup.mode == 0 {
					$run = LayoutGsub.apply_singles(shape, lookup, ctx, $run)
				} else {
					{ buf, work } = LayoutGsub.apply_forward(shape, lookup, ctx, { info: $run, out: $spare.clear().reserve($run.len()), idx: 0, output: True, serial: $serial, random: $random, ops: $ops, stopped: $stopped }, limits, $work)
					{ info, out, idx, output: _, serial, random, ops, stopped } = buf
					# Sync: the rest of the input follows the output.
					$run = if (idx < info.len()) out.concat(info.drop_first(idx)) else out
					$spare = info
					$serial = serial
					$random = random
					$ops = ops
					$stopped = stopped
					$work = work
				}
			}
		}
		{ items: $run, stopped: $stopped }
	}

	applies : U64, U64 -> Bool
	applies = |item_mask, lookup_mask| item_mask.bitwise_and(lookup_mask) != 0

	## Whether a lookup may start at an item: its glyph may be covered, the
	## masks share a bit, and the lookup flags let the lookup see it.
	candidate : LayoutGsub, Lookup, Ctx, Item -> Bool
	candidate = |shape, lookup, ctx, item| LayoutGsub.may_start(lookup, item.glyph) and LayoutGsub.applies(item.mask, ctx.mask) and LayoutGsub.check_glyph_property(shape, item, ctx.props)

	# A lookup of single substitutions only: each glyph is replaced in place,
	# which is what HarfBuzz's out-of-place replacement amounts to.
	apply_singles : LayoutGsub, Lookup, Ctx, List(Item) -> List(Item)
	apply_singles = |shape, lookup, ctx, items| {
		var $run = items
		n = $run.len()
		var $i = 0
		while $i < n {
			item = $run.get($i) ?? LayoutGsub.no_item
			if LayoutGsub.candidate(shape, lookup, ctx, item) {
				end = lookup.start + lookup.count
				var $k = lookup.start
				while $k < end {
					sub = shape.subtables.get($k) ?? LayoutGsub.no_sub
					match LayoutGsub.covered_in(shape.ranges, sub.coverage, sub.coverage_len, item.glyph) {
						Err(_) => {
							$k = $k + 1
						}
						Ok(at) =>
							match LayoutGsub.single(shape.values, sub, at, item.glyph) {
								Ok(glyph) => {
									# `$i < n`, the run's length.
									$run = $run.set($i, LayoutGsub.resubstituted({ ..LayoutGsub.set_glyph_class(shape, item, glyph, 0, False, False), glyph }, ctx.step)) ?? []
									$k = end
								}
								Err(_) => {
									$k = $k + 1
								}
							}
					}
				}
			}
			$i = $i + 1
		}
		$run
	}

	## The substitute of a covered glyph (coverage index `at`) in a single
	## substitution, or `Err` when format 2 has no substitute at that index.
	single : List(U64), Sub, U64, U64 -> Try(U64, [NoSubstitute])
	single = |values, sub, at, glyph|
		if sub.data_len == 0 {
			Ok((glyph.to_i64_wrap() + sub.delta).bitwise_and(0xFFFF).to_u64_wrap())
		} else if at < sub.data_len {
			Ok(values.get(sub.data + at) ?? glyph)
		} else {
			Err(NoSubstitute)
		}

	# HarfBuzz's `apply_forward`: past glyphs no subtable can start at, try
	# the lookup's subtables in order at each glyph; one that applies moves
	# the cursor itself, otherwise the glyph is copied.
	apply_forward : LayoutGsub, Lookup, Ctx, Buf, Limits, Work -> { buf : Buf, work : Work }
	apply_forward = |shape, lookup, ctx, start, limits, work_in| {
		var $buf = start
		var $work = work_in
		var $going = True
		while $going {
			n = $buf.info.len()
			var $j = $buf.idx
			while $j < n and !LayoutGsub.candidate(shape, lookup, ctx, $buf.info.get($j) ?? LayoutGsub.no_item) {
				$j = $j + 1
			}
			if $j > $buf.idx {
				$buf = LayoutGsub.next_glyphs($buf, $j - $buf.idx)
			}
			if $buf.idx >= n {
				$going = False
			} else {
				{ buf: after, work: used, outcome } = LayoutGsub.apply_once(shape, lookup, ctx, $buf, limits, $work, False)
				$work = used
				match outcome {
					Applied => {
						$buf = after
					}
					NotApplied => {
						$buf = LayoutGsub.next_glyph(after)
					}
					Context(found) => {
						{ buf: done, work: frames_done } = LayoutGsub.run_frames(shape, ctx, after, found, limits, $work)
						$buf = done
						$work = frames_done
					}
				}
			}
		}
		{ buf: $buf, work: $work }
	}

	# HarfBuzz's `apply_backward`, for reverse chaining lookups: in place,
	# from the last glyph to the first.
	apply_backward : LayoutGsub, Lookup, Ctx, Buf, Limits, Work -> { buf : Buf, work : Work }
	apply_backward = |shape, lookup, ctx, start, limits, work_in| {
		var $buf = start
		var $work = work_in
		var $k = $buf.info.len()
		while $k > 0 {
			$buf = { ..$buf, idx: $k - 1 }
			item = $buf.info.get($k - 1) ?? LayoutGsub.no_item
			if LayoutGsub.candidate(shape, lookup, ctx, item) {
				{ buf: after, work: used, outcome: _ } = LayoutGsub.apply_once(shape, lookup, ctx, $buf, limits, $work, False)
				$buf = after
				$work = used
			}
			$k = $k - 1
		}
		{ buf: $buf, work: $work }
	}

	## The first subtable of a lookup that applies at the cursor.
	apply_once : LayoutGsub, Lookup, Ctx, Buf, Limits, Work, Bool -> { buf : Buf, work : Work, outcome : Outcome }
	apply_once = |shape, lookup, ctx, start, limits, work_in, nested| {
		var $buf = start
		var $work = work_in
		var $outcome = NotApplied
		end = lookup.start + lookup.count
		var $k = lookup.start
		while $k < end {
			sub = shape.subtables.get($k) ?? LayoutGsub.no_sub
			{ buf: after, work: used, outcome } = LayoutGsub.apply_subtable(shape, sub, ctx, $buf, limits, $work, nested)
			$buf = after
			$work = used
			match outcome {
				NotApplied => {
					$k = $k + 1
				}
				_ => {
					$outcome = outcome
					$k = end
				}
			}
		}
		{ buf: $buf, work: $work, outcome: $outcome }
	}

	# One subtable at the cursor (HarfBuzz's subtable `apply`).
	apply_subtable : LayoutGsub, Sub, Ctx, Buf, Limits, Work, Bool -> { buf : Buf, work : Work, outcome : Outcome }
	apply_subtable = |shape, sub, ctx, buf, limits, work, nested| {
		cur = buf.info.get(buf.idx) ?? LayoutGsub.no_item
		# Built only where it is the answer, so `buf` stays unique.
		if buf.idx >= buf.info.len() {
			{ buf, work, outcome: NotApplied }
		} else if sub.kind == 5 {
			LayoutGsub.apply_context(shape, sub, ctx, buf, work)
		} else {
			match LayoutGsub.covered_in(shape.ranges, sub.coverage, sub.coverage_len, cur.glyph) {
				Err(_) => { buf, work, outcome: NotApplied }
				Ok(at) =>
					if sub.kind == 1 {
						match LayoutGsub.single(shape.values, sub, at, cur.glyph) {
							Ok(glyph) => { buf: LayoutGsub.replace_glyph(shape, buf, glyph, ctx.step), work, outcome: Applied }
							Err(_) => { buf, work, outcome: NotApplied }
						}
					} else if sub.kind == 2 {
						LayoutGsub.apply_multiple(shape, sub, ctx, at, buf, limits, work)
					} else if sub.kind == 3 {
						LayoutGsub.apply_alternate(shape, sub, ctx, at, buf, work)
					} else if sub.kind == 4 {
						LayoutGsub.apply_ligatures(shape, sub, ctx, at, buf, work)
					} else if sub.kind == 8 and !nested {
						LayoutGsub.apply_reverse(shape, sub, ctx, at, buf, work)
					} else {
						{ buf, work, outcome: NotApplied }
					}
			}
		}
	}

	## Replace the glyph at the cursor and move on (HarfBuzz's
	## `replace_glyph`; in place without an output).
	replace_glyph : LayoutGsub, Buf, U64, U64 -> Buf
	replace_glyph = |shape, buf, glyph, step| {
		# Destructured, so the lists are not also held by `buf`.
		{ info, out, idx, output, serial, random, ops, stopped } = buf
		cur = info.get(idx) ?? LayoutGsub.no_item
		item = LayoutGsub.resubstituted({ ..LayoutGsub.set_glyph_class(shape, cur, glyph, 0, False, False), glyph }, step)
		if output {
			{ info, out: out.append(item), idx: idx + 1, output, serial, random, ops, stopped }
		} else {
			# The cursor is inside the input.
			{ info: info.set(idx, item) ?? [], out, idx: idx + 1, output, serial, random, ops, stopped }
		}
	}

	# Multiple substitution (HarfBuzz's `Sequence::apply`). A sequence of
	# one glyph is a plain replacement and of none a deletion; a longer one
	# is not made when it would grow the run past its limit.
	apply_multiple : LayoutGsub, Sub, Ctx, U64, Buf, Limits, Work -> { buf : Buf, work : Work, outcome : Outcome }
	apply_multiple = |shape, sub, ctx, at, buf, limits, work| {
		if at >= sub.data_len {
			{ buf, work, outcome: NotApplied }
		} else {
			start = shape.values.get(sub.data + at) ?? 0
			stop = (shape.values.get(sub.data + at + 1) ?? 0).max(start)
			count = stop - start
			if count == 1 {
				{ buf: LayoutGsub.replace_glyph(shape, buf, shape.values.get(start) ?? 0, ctx.step), work, outcome: Applied }
			} else if count == 0 {
				{ buf: LayoutGsub.delete_glyph(buf), work, outcome: Applied }
			} else if buf.out.len() + count + (buf.info.len() - buf.idx) > limits.limit + 1 {
				# Over the growth bound: not made, and said so.
				{ buf: { ..buf, stopped: buf.stopped.bitwise_or(LayoutGsub.stopped_growth) }, work, outcome: NotApplied }
			} else {
				{ info, out, idx, output, serial, random, ops, stopped } = buf
				cur = info.get(idx) ?? LayoutGsub.no_item
				klass = if (LayoutGsub.gprops(cur).bitwise_and(LayoutGsub.ligature) != 0) LayoutGsub.base_glyph else 0
				attached = LayoutGsub.lig_id(cur) != 0
				var $cur = cur
				var $out = out
				for i in 0..<count {
					glyph = shape.values.get(start + i) ?? 0
					component = if (attached) $cur else LayoutGsub.with_lprops($cur, i.bitwise_and(0x0F))
					$cur = LayoutGsub.set_glyph_class(shape, component, glyph, klass, False, True)
					kind = if (i == 0) LayoutGsub.origin_multiple else LayoutGsub.origin_inserted
					$out = $out.append(LayoutGsub.with_origin({ ..$cur, glyph }, kind, ctx.step, 0))
				}
				{ buf: { info, out: $out, idx: idx + 1, output, serial, random, ops, stopped }, work, outcome: Applied }
			}
		}
	}

	# Alternate substitution (HarfBuzz's `AlternateSet::apply`): the
	# alternate is the glyph's value of the lookup's feature; `rand` at its
	# largest value picks one with HarfBuzz's generator (the minimal
	# standard generator on a 32-bit state, seeded with 1 for each run), so
	# the choice is deterministic.
	apply_alternate : LayoutGsub, Sub, Ctx, U64, Buf, Work -> { buf : Buf, work : Work, outcome : Outcome }
	apply_alternate = |shape, sub, ctx, at, buf, work| {
		if at >= sub.data_len {
			{ buf, work, outcome: NotApplied }
		} else {
			start = shape.values.get(sub.data + at) ?? 0
			stop = (shape.values.get(sub.data + at + 1) ?? 0).max(start)
			count = stop - start
			cur = buf.info.get(buf.idx) ?? LayoutGsub.no_item
			shift = LayoutGsub.trailing_zeros(ctx.mask)
			chosen = ctx.mask.bitwise_and(cur.mask).shr_zf_wrap(shift.to_u8_wrap())
			{ index, after } =
				if chosen == 255 and ctx.random and count > 0 {
					# HarfBuzz's state is 32 bits: the product wraps before the
					# remainder.
					next = (buf.random * 48271).bitwise_and(0xFFFFFFFF) % 2147483647
					n = buf.info.len()
					{ info, out, idx, output, serial, random: _, ops, stopped } = LayoutGsub.unsafe_to_break(buf, 0, n)
					{ index: next % count + 1, after: { info, out, idx, output, serial, random: next, ops, stopped } }
				} else {
					{ index: chosen, after: buf }
				}
			if index > count or index == 0 {
				{ buf: after, work, outcome: NotApplied }
			} else {
				{ buf: LayoutGsub.replace_glyph(shape, after, shape.values.get(start + index - 1) ?? 0, ctx.step), work, outcome: Applied }
			}
		}
	}

	trailing_zeros : U64 -> U64
	trailing_zeros = |mask|
		if mask == 0 {
			0
		} else {
			var $n = 0
			var $m = mask
			while $m.bitwise_and(1) == 0 {
				$m = $m.shr_zf_wrap(1)
				$n = $n + 1
			}
			$n
		}

	# Ligature substitution (HarfBuzz's `LigatureSet::apply`): the first
	# ligature of the set whose components match, skipping what the lookup
	# flags skip.
	apply_ligatures : LayoutGsub, Sub, Ctx, U64, Buf, Work -> { buf : Buf, work : Work, outcome : Outcome }
	apply_ligatures = |shape, sub, ctx, at, buf, work_in| {
		if at >= sub.data_len {
			{ buf, work: work_in, outcome: NotApplied }
		} else {
			end = shape.values.get(sub.data + at + 1) ?? 0
			{ scratch: scratch_in, frames, positions } = work_in
			var $scratch = scratch_in
			var $found = NoLigature
			var $p = shape.values.get(sub.data + at) ?? 0
			while $p < end {
				glyph = shape.values.get($p) ?? 0
				components = shape.values.get($p + 1) ?? 0
				if components == 0 {
					$found = Single(glyph)
					$p = end
				} else {
					seq = { kind: 0, classes: 0, classes_len: 0, at: $p + 2, stride: 1 }
					{ ok, end: match_end, scratch, total } = LayoutGsub.match_input(shape, ctx, buf, seq, components + 1, $scratch)
					$scratch = scratch
					if ok {
						$found = Ligature({ glyph, count: components + 1, match_end, total })
						$p = end
					} else {
						$p = $p + 2 + components
					}
				}
			}
			match $found {
				Single(glyph) => { buf: LayoutGsub.replace_glyph(shape, buf, glyph, ctx.step), work: { scratch: $scratch, frames, positions }, outcome: Applied }
				Ligature(l) => { buf: LayoutGsub.ligate_input(shape, buf, $scratch, { count: l.count, match_end: l.match_end, glyph: l.glyph, total: l.total, step: ctx.step }), work: { scratch: $scratch, frames, positions }, outcome: Applied }
				NoLigature => { buf, work: { scratch: $scratch, frames, positions }, outcome: NotApplied }
			}
		}
	}

	# Reverse chaining single substitution (HarfBuzz's
	# `ReverseChainSingleSubstFormat1::apply`), never called from a rule.
	apply_reverse : LayoutGsub, Sub, Ctx, U64, Buf, Work -> { buf : Buf, work : Work, outcome : Outcome }
	apply_reverse = |shape, sub, ctx, at, buf, work| {
		if at >= sub.data_len {
			{ buf, work, outcome: NotApplied }
		} else {
			back = { kind: 2, classes: 0, classes_len: 0, at: sub.back, stride: 2 }
			ahead = { kind: 2, classes: 0, classes_len: 0, at: sub.ahead, stride: 2 }
			before = LayoutGsub.match_backtrack(shape, ctx, buf, back, sub.back_len)
			after = LayoutGsub.match_lookahead(shape, ctx, buf, ahead, sub.ahead_len, buf.idx + 1)
			if before.ok and after.ok {
				{ info, out, idx, output, serial, random, ops, stopped } = LayoutGsub.unsafe_to_break_from_outbuffer(buf, before.start, after.end)
				cur = info.get(idx) ?? LayoutGsub.no_item
				glyph = shape.values.get(sub.data + at) ?? 0
				item = LayoutGsub.resubstituted({ ..LayoutGsub.set_glyph_class(shape, cur, glyph, 0, False, False), glyph }, ctx.step)
				# The cursor is inside the input.
				{ buf: { info: info.set(idx, item) ?? [], out, idx, output, serial, random, ops, stopped }, work, outcome: Applied }
			} else {
				{ buf, work, outcome: NotApplied }
			}
		}
	}

	# Contextual and chained contextual substitution: the first rule of the
	# glyph's rule set that matches. A match is marked unsafe to break and
	# returned for the caller to run its nested lookups (`run_frames`).
	apply_context : LayoutGsub, Sub, Ctx, Buf, Work -> { buf : Buf, work : Work, outcome : Outcome }
	apply_context = |shape, sub, ctx, buf, work_in| {
		cur = buf.info.get(buf.idx) ?? LayoutGsub.no_item
		match LayoutGsub.covered_in(shape.ranges, sub.coverage, sub.coverage_len, cur.glyph) {
			Err(_) => { buf, work: work_in, outcome: NotApplied }
			Ok(at) => {
				slot = if (sub.match_kind == 1) LayoutGsub.class_in(shape.ranges, sub.input, sub.input_len, cur.glyph) else if (sub.match_kind == 2) 0 else at
				if slot >= sub.data_len {
					{ buf, work: work_in, outcome: NotApplied }
				} else {
					last = shape.values.get(sub.data + slot + 1) ?? 0
					stride = if (sub.match_kind == 2) 2 else 1
					{ scratch: scratch_in, frames, positions } = work_in
					var $scratch = scratch_in
					var $found = NoRule
					var $r = shape.values.get(sub.data + slot) ?? 0
					while $r < last {
						rule = shape.rules.get($r) ?? LayoutGsub.no_rule
						input = { kind: sub.match_kind, classes: sub.input, classes_len: sub.input_len, at: rule.input, stride }
						count = rule.input_len + 1
						{ ok, end: match_end, scratch, total: _ } = LayoutGsub.match_input(shape, ctx, buf, input, count, $scratch)
						$scratch = scratch
						found = { count, records: rule.records, records_len: rule.records_len, end: match_end }
						if !ok or count > LayoutGsub.max_context {
							$r = $r + 1
						} else if sub.delta == 0 {
							# A context rule: unsafe to break across its input.
							$found = Plain({ found, start: buf.idx, end: match_end })
							$r = last
						} else {
							ahead = { kind: sub.match_kind, classes: sub.ahead, classes_len: sub.ahead_len, at: rule.ahead, stride }
							back = { kind: sub.match_kind, classes: sub.back, classes_len: sub.back_len, at: rule.back, stride }
							after = LayoutGsub.match_lookahead(shape, ctx, buf, ahead, rule.ahead_len, match_end)
							before = if (after.ok) LayoutGsub.match_backtrack(shape, ctx, buf, back, rule.back_len) else { ok: False, start: 0 }
							if after.ok and before.ok {
								$found = Chained({ found, start: before.start, end: after.end })
								$r = last
							} else {
								$r = $r + 1
							}
						}
					}
					work = { scratch: $scratch, frames, positions }
					match $found {
						Plain(m) => { buf: LayoutGsub.unsafe_to_break(buf, m.start, m.end), work, outcome: Context(m.found) }
						Chained(m) => { buf: LayoutGsub.unsafe_to_break_from_outbuffer(buf, m.start, m.end), work, outcome: Context(m.found) }
						NoRule => { buf, work, outcome: NotApplied }
					}
				}
			}
		}
	}

	# Run the nested lookups of a matched rule (HarfBuzz's `apply_lookup`)
	# whose positions are `work.scratch`, and of the rules they match in
	# turn, through an explicit stack of frames: at most `limits.depth`
	# rules deep (deeper rules match but call nothing), and at most
	# `limits.budget` nested lookups in all. Positions are kept relative to
	# the output, and adjusted after a nested lookup changes the run's
	# length exactly as HarfBuzz adjusts them.
	run_frames : LayoutGsub, Ctx, Buf, { count : U64, records : U64, records_len : U64, end : U64 }, Limits, Work -> { buf : Buf, work : Work }
	run_frames = |shape, ctx, start, found, limits, work_in| {
		{ scratch: scratch_in, frames: frames_in, positions: positions_in } = work_in
		var $buf = start
		var $scratch = scratch_in
		var $positions = positions_in.clear()
		var $frames = frames_in.clear()
		{ frame: first, positions: placed } = LayoutGsub.push_frame($buf, found, $scratch, $positions, 0)
		$positions = placed
		$frames = $frames.append(first)
		while !$frames.is_empty() {
			depth = $frames.len()
			top = $frames.last() ?? LayoutGsub.no_frame
			if top.next >= top.records_len {
				# The rule is done: continue after its input.
				$buf = LayoutGsub.move_to($buf, top.end)
				$frames = $frames.drop_last(1)
				match $frames.last() {
					Ok(parent) => {
						{ frame: adjusted, positions: moved } = LayoutGsub.after_nested($buf, parent, $positions)
						$positions = moved
						# The list is not empty: it holds `parent`.
						$frames = $frames.set($frames.len() - 1, adjusted) ?? []
					}
					Err(_) => {}
				}
			} else {
				r = top.next
				at = shape.values.get(top.records + 2 * r) ?? 0
				index = shape.values.get(top.records + 2 * r + 1) ?? 0
				orig_len = $buf.out.len() + ($buf.info.len() - $buf.idx)
				position = $positions.get(top.base + at) ?? 0
				# The list is not empty: it holds `top`.
				$frames = $frames.set(depth - 1, { ..top, next: r + 1 }) ?? []
				if at < top.count and position < orig_len {
					$buf = LayoutGsub.move_to($buf, position)
					if $buf.ops >= limits.budget {
						# Out of budget: the rule stops here, and says so.
						$frames = $frames.set(depth - 1, { ..top, next: top.records_len }) ?? []
						$buf = { ..$buf, stopped: $buf.stopped.bitwise_or(LayoutGsub.stopped_operations) }
					} else if depth > limits.depth {
						# Too deep: the record calls nothing, and says so.
						$buf = { ..$buf, stopped: $buf.stopped.bitwise_or(LayoutGsub.stopped_depth) }
					} else {
						$buf = { ..$buf, ops: $buf.ops + 1 }
						lookup = shape.lookups.get(index) ?? LayoutGsub.no_lookup
						nested_ctx = { ..ctx, props: LayoutGsub.sanitize_props(shape, lookup.props) }
						saved = { ..top, next: r + 1, saved_at: at, saved_len: orig_len }
						$frames = $frames.set(depth - 1, saved) ?? []
						# Destructured, so the scratch list is not also held by a record.
						{ buf: after, work: { scratch: used, frames: _, positions: _ }, outcome } = LayoutGsub.apply_once(shape, lookup, nested_ctx, $buf, limits, { scratch: $scratch, frames: [], positions: [] }, True)
						$buf = after
						$scratch = used
						match outcome {
							Applied => {
								{ frame: adjusted, positions: moved } = LayoutGsub.after_nested($buf, saved, $positions)
								$positions = moved
								$frames = $frames.set(depth - 1, adjusted) ?? []
							}
							NotApplied => {}
							Context(inner) => {
								{ frame: pushed, positions: placed_inner } = LayoutGsub.push_frame($buf, inner, $scratch, $positions, depth * LayoutGsub.max_context)
								$positions = placed_inner
								$frames = $frames.append(pushed)
							}
						}
					}
				}
			}
		}
		{ buf: $buf, work: { scratch: $scratch, frames: $frames, positions: $positions } }
	}

	## A new frame for a matched rule: its positions (`scratch`, input
	## indices) converted to output indices and stored from `base`.
	push_frame : Buf, { count : U64, records : U64, records_len : U64, end : U64 }, List(U64), List(U64), U64 -> { frame : Frame, positions : List(U64) }
	push_frame = |buf, found, scratch, positions_in, base| {
		bl = buf.out.len()
		var $positions = positions_in
		while $positions.len() < base + LayoutGsub.max_context {
			$positions = $positions.append(0)
		}
		for j in 0..<found.count.min(LayoutGsub.max_context) {
			p = scratch.get(j) ?? buf.idx
			# Matched positions are at or after the cursor; `base + j` is
			# within the slots added above.
			$positions = $positions.set(base + j, p + bl - buf.idx) ?? []
		}
		{ frame: { records: found.records, records_len: found.records_len, next: 0, count: found.count, end: bl + found.end - buf.idx, base, saved_at: 0, saved_len: 0 }, positions: $positions }
	}

	## A frame's positions and end after a nested lookup applied at its
	## position `saved_at` and changed the run's length from `saved_len`
	## (HarfBuzz's adjustment in `apply_lookup`, including its limit of
	## `max_context` positions).
	after_nested : Buf, Frame, List(U64) -> { frame : Frame, positions : List(U64) }
	after_nested = |buf, frame, positions_in| {
		new_len = buf.out.len() + (buf.info.len() - buf.idx)
		delta0 = new_len.to_i64_wrap() - frame.saved_len.to_i64_wrap()
		if delta0 == 0 {
			{ frame, positions: positions_in }
		} else {
			base = frame.base
			at = frame.saved_at
			count = frame.count.to_i64_wrap()
			p_at = (positions_in.get(base + at) ?? 0).to_i64_wrap()
			end0 = frame.end.to_i64_wrap() + delta0
			{ end, delta } = if (end0 < p_at) { end: p_at, delta: delta0 + (p_at - end0) } else { end: end0, delta: delta0 }
			next0 = (at + 1).to_i64_wrap()
			if delta > 0 and delta + count > LayoutGsub.max_context.to_i64_wrap() {
				# HarfBuzz stops applying the rule's records.
				{ frame: { ..frame, end: end.to_u64_wrap(), next: frame.records_len }, positions: positions_in }
			} else {
				{ d, next } = if (delta > 0) { d: delta, next: next0 } else { d: delta.max(next0 - count), next: next0 - delta.max(next0 - count) }
				var $positions = positions_in
				# Shift positions `next ..< count` by `d` places.
				moved = count - next
				if d > 0 {
					var $k = moved - 1
					while $k >= 0 {
						v = $positions.get(base + (next + $k).to_u64_wrap()) ?? 0
						# Within the frame's slots: `count + d <= max_context`.
						$positions = $positions.set(base + (next + d + $k).to_u64_wrap(), v) ?? []
						$k = $k - 1
					}
				} else if d < 0 {
					for k in 0..<moved.max(0).to_u64_wrap() {
						v = $positions.get(base + (next + k.to_i64_wrap()).to_u64_wrap()) ?? 0
						# Within the frame's slots.
						$positions = $positions.set(base + (next + d + k.to_i64_wrap()).to_u64_wrap(), v) ?? []
					}
				}
				next2 = next + d
				count2 = count + d
				# New entries follow the nested lookup's position.
				var $j = at + 1
				while $j.to_i64_wrap() < next2 {
					v = $positions.get(base + $j - 1) ?? 0
					# Within the frame's slots.
					$positions = $positions.set(base + $j, v + 1) ?? []
					$j = $j + 1
				}
				var $m = next2
				while $m < count2 {
					v = ($positions.get(base + $m.to_u64_wrap()) ?? 0).to_i64_wrap()
					# Within the frame's slots.
					$positions = $positions.set(base + $m.to_u64_wrap(), (v + d).max(0).to_u64_wrap()) ?? []
					$m = $m + 1
				}
				{ frame: { ..frame, end: end.max(0).to_u64_wrap(), count: count2.max(0).to_u64_wrap() }, positions: $positions }
			}
		}
	}

	# ------------------------------------------------------------ matching

	## A sequence of values to match: glyphs (`kind` 0), classes of the
	## class definition `classes` (1) or coverages (2), from `values[at]`
	## with `stride` values per entry.
	Seq : { kind : U64, classes : U64, classes_len : U64, at : U64, stride : U64 }

	## Whether a glyph matches entry `k` of a sequence.
	seq_matches : LayoutGsub, Seq, U64, U64 -> Bool
	seq_matches = |shape, seq, k, glyph| LayoutGsub.match_one(shape, seq.kind, seq.classes, seq.classes_len, seq.at + seq.stride * k, glyph)

	## HarfBuzz's skipping iterator deciding about one item: `Skip` it,
	## it is a `Match`, or `NoMatch` (stop). `context` for backtrack and
	## lookahead, which ignore masks and skip ZWJ always.
	step_item : LayoutGsub, Ctx, Item, Bool, Bool -> [Match, NoMatch, Skip]
	step_item = |shape, ctx, item, context, matched| {
		skip =
			if !LayoutGsub.check_glyph_property(shape, item, ctx.props) {
				SkipYes
			} else if LayoutGsub.is_default_ignorable(item) and ((context and ctx.auto_zwnj) or !ShaperUnicode.is_zwnj(item.props)) and (context or ctx.auto_zwj or !ShaperUnicode.is_zwj(item.props)) and item.props.bitwise_and(ShaperUnicode.hidden) == 0 {
				SkipMaybe
			} else {
				SkipNo
			}
		match skip {
			SkipYes => Skip
			_ => {
				masked = context or LayoutGsub.applies(item.mask, ctx.mask)
				if masked and matched {
					Match
				} else {
					match skip {
						SkipNo => NoMatch
						_ => Skip
					}
				}
			}
		}
	}

	## Whether the skipping iterator would skip an item outright (HarfBuzz's
	## `may_skip` giving `SKIP_YES`), for input matching.
	skips : LayoutGsub, Ctx, Item -> Bool
	skips = |shape, ctx, item| !LayoutGsub.check_glyph_property(shape, item, ctx.props)

	# HarfBuzz's `match_input`: the input after the cursor's glyph, `count`
	# glyphs in all, skipping what the lookup flags and joiner rules skip,
	# and not across glyphs attached to different components of earlier
	# ligatures. Gives where the match ends, the matched positions in
	# `scratch` and the ligature components they carry.
	match_input : LayoutGsub, Ctx, Buf, Seq, U64, List(U64) -> { ok : Bool, end : U64, scratch : List(U64), total : U64 }
	match_input = |shape, ctx, buf, seq, count, scratch_in| {
		# The positions are written only for a match, walking it again, so
		# the many failed attempts never touch the scratch list.
		trial = LayoutGsub.match_walk(shape, ctx, buf, seq, count, [], False)
		if trial.ok {
			LayoutGsub.match_walk(shape, ctx, buf, seq, count, scratch_in, True)
		} else {
			{ ok: False, end: trial.end, scratch: scratch_in, total: 0 }
		}
	}

	match_walk : LayoutGsub, Ctx, Buf, Seq, U64, List(U64), Bool -> { ok : Bool, end : U64, scratch : List(U64), total : U64 }
	match_walk = |shape, ctx, buf, seq, count, scratch_in, record| {
		info = buf.info
		idx = buf.idx
		cur = info.get(idx) ?? LayoutGsub.no_item
		var $scratch = if (record) scratch_in.clear().append(idx) else scratch_in
		if count == 1 {
			{ ok: True, end: idx + 1, scratch: $scratch, total: LayoutGsub.num_comps(cur) }
		} else if count > LayoutGsub.max_context {
			{ ok: False, end: idx, scratch: $scratch, total: 0 }
		} else {
			first_id = LayoutGsub.lig_id(cur)
			first_comp = LayoutGsub.lig_comp(cur)
			n = info.len()
			var $total = 0
			var $at = idx
			var $ok = True
			var $end = idx
			# 0 not checked, 1 may not skip, 2 may skip.
			var $ligbase = 0
			var $i = 1
			while $ok and $i < count {
				# Find the next item that matches entry `$i - 1`.
				var $searching = True
				while $searching {
					if $at + 1 >= n {
						$ok = False
						$end = n
						$searching = False
					} else {
						$at = $at + 1
						item = info.get($at) ?? LayoutGsub.no_item
						match LayoutGsub.step_item(shape, ctx, item, False, LayoutGsub.seq_matches(shape, seq, $i - 1, item.glyph)) {
							Match => {
								$searching = False
							}
							NoMatch => {
								$ok = False
								$end = $at + 1
								$searching = False
							}
							Skip => {}
						}
					}
				}
				if $ok {
					if record {
						$scratch = $scratch.append($at)
					}
					this = info.get($at) ?? LayoutGsub.no_item
					this_id = LayoutGsub.lig_id(this)
					this_comp = LayoutGsub.lig_comp(this)
					if first_id != 0 and first_comp != 0 {
						if first_id != this_id or first_comp != this_comp {
							if $ligbase == 0 {
								# Is the ligature the first glyph belongs to one the
								# lookup skips?
								var $j = buf.out.len()
								var $found = False
								var $looking = True
								while $looking and $j > 0 and LayoutGsub.lig_id(buf.out.get($j - 1) ?? LayoutGsub.no_item) == first_id {
									if LayoutGsub.lig_comp(buf.out.get($j - 1) ?? LayoutGsub.no_item) == 0 {
										$found = True
										$looking = False
									}
									$j = $j - 1
								}
								$ligbase = if ($found and LayoutGsub.skips(shape, ctx, buf.out.get($j) ?? LayoutGsub.no_item)) 2 else 1
							}
							if $ligbase == 1 {
								$ok = False
							}
						}
					} else if this_id != 0 and this_comp != 0 and this_id != first_id {
						$ok = False
					}
					$total = $total + LayoutGsub.num_comps_in_ligation(this)
				}
				$i = $i + 1
			}
			if $ok {
				{ ok: True, end: $at + 1, scratch: $scratch, total: $total + LayoutGsub.num_comps(cur) }
			} else {
				{ ok: False, end: $end, scratch: $scratch, total: 0 }
			}
		}
	}

	# HarfBuzz's `match_backtrack`: `count` entries backwards from the
	# output's end (the input's cursor without an output). Gives where the
	# match starts.
	match_backtrack : LayoutGsub, Ctx, Buf, Seq, U64 -> { ok : Bool, start : U64 }
	match_backtrack = |shape, ctx, buf, seq, count| {
		before = if (buf.output) buf.out else buf.info
		len = if (buf.output) buf.out.len() else buf.idx
		if count == 0 {
			{ ok: True, start: len }
		} else {
			var $at = len
			var $ok = True
			var $start = len
			var $i = 0
			while $ok and $i < count {
				var $searching = True
				while $searching {
					if $at == 0 {
						$ok = False
						$start = 0
						$searching = False
					} else {
						$at = $at - 1
						item = before.get($at) ?? LayoutGsub.no_item
						match LayoutGsub.step_item(shape, ctx, item, True, LayoutGsub.seq_matches(shape, seq, $i, item.glyph)) {
							Match => {
								$searching = False
							}
							NoMatch => {
								$ok = False
								$start = $at.max(1) - 1
								$searching = False
							}
							Skip => {}
						}
					}
				}
				$i = $i + 1
			}
			if ($ok) { ok: True, start: $at } else { ok: False, start: $start }
		}
	}

	# HarfBuzz's `match_lookahead`: `count` entries forwards from input
	# index `start`. Gives where the match ends.
	match_lookahead : LayoutGsub, Ctx, Buf, Seq, U64, U64 -> { ok : Bool, end : U64 }
	match_lookahead = |shape, ctx, buf, seq, count, start| {
		if count == 0 {
			{ ok: True, end: start }
		} else {
			info = buf.info
			n = info.len()
			var $at = start - 1
			var $ok = True
			var $end = start
			var $i = 0
			while $ok and $i < count {
				var $searching = True
				while $searching {
					if $at + 1 >= n {
						$ok = False
						$end = n
						$searching = False
					} else {
						$at = $at + 1
						item = info.get($at) ?? LayoutGsub.no_item
						match LayoutGsub.step_item(shape, ctx, item, True, LayoutGsub.seq_matches(shape, seq, $i, item.glyph)) {
							Match => {
								$searching = False
							}
							NoMatch => {
								$ok = False
								$end = $at + 1
								$searching = False
							}
							Skip => {}
						}
					}
				}
				$i = $i + 1
			}
			if ($ok) { ok: True, end: $at + 1 } else { ok: False, end: $end }
		}
	}

	# HarfBuzz's `ligate_input`: merge the clusters of the match, write the
	# ligature glyph, keep the glyphs skipped between components (with the
	# ligature's id and their component), drop the components, and move
	# marks that followed an earlier ligature to the new one's components.
	ligate_input : LayoutGsub, Buf, List(U64), { count : U64, match_end : U64, glyph : U64, total : U64, step : U64 } -> Buf
	ligate_input = |shape, start, positions, made| {
		count = made.count
		match_end = made.match_end
		lig_glyph = made.glyph
		total = made.total
		merged = LayoutGsub.merge_clusters(start, start.idx, match_end)
		{ info: info_in, out: out_in, idx: idx_in, output, serial: serial_in, random, ops, stopped } = merged
		first = info_in.get(positions.get(0) ?? 0) ?? LayoutGsub.no_item
		var $is_base = LayoutGsub.gprops(first).bitwise_and(LayoutGsub.base_glyph) != 0
		var $is_mark = LayoutGsub.is_mark_item(first)
		for i in 1..<count {
			if !LayoutGsub.is_mark_item(info_in.get(positions.get(i) ?? 0) ?? LayoutGsub.no_item) {
				$is_base = False
				$is_mark = False
			}
		}
		is_ligature = !$is_base and !$is_mark
		var $info = info_in
		var $out = out_in
		var $idx = idx_in
		klass = if (is_ligature) LayoutGsub.ligature else 0
		{ id: new_id, serial } = if (is_ligature) LayoutGsub.allocate_lig_id(serial_in) else { id: 0, serial: serial_in }
		cur = $info.get($idx) ?? LayoutGsub.no_item
		var $last_id = LayoutGsub.lig_id(cur)
		var $last_count = LayoutGsub.num_comps(cur)
		var $so_far = $last_count
		with_lig =
			if is_ligature {
				lig = LayoutGsub.with_lprops(cur, new_id.shl_wrap(5).bitwise_or(0x10).bitwise_or(total.bitwise_and(0x0F)))
				if (ShaperUnicode.general_category_of(lig.props) == ShaperUnicode.non_spacing_mark) { ..lig, props: ShaperUnicode.with_category(lig.props, ShaperUnicode.other_letter) } else lig
			} else {
				cur
			}
		$out = $out.append(LayoutGsub.with_origin({ ..LayoutGsub.set_glyph_class(shape, with_lig, lig_glyph, klass, True, False), glyph: lig_glyph }, LayoutGsub.origin_ligature, made.step, count))
		$idx = $idx + 1
		for i in 1..<count {
			target = positions.get(i) ?? $idx
			while $idx < target {
				item = $info.get($idx) ?? LayoutGsub.no_item
				moved =
					if is_ligature {
						this_comp = LayoutGsub.lig_comp(item)
						comp = if (this_comp == 0) $last_count else this_comp
						new_comp = $so_far - $last_count + comp.min($last_count)
						LayoutGsub.with_lprops(item, new_id.shl_wrap(5).bitwise_or(new_comp.bitwise_and(0x0F)))
					} else {
						item
					}
				$out = $out.append(moved)
				$idx = $idx + 1
			}
			component = $info.get($idx) ?? LayoutGsub.no_item
			$last_id = LayoutGsub.lig_id(component)
			$last_count = LayoutGsub.num_comps_in_ligation(component)
			$so_far = $so_far + $last_count
			# The component is dropped.
			$idx = $idx + 1
		}
		if !$is_mark and $last_id != 0 {
			var $k = $idx
			var $going = True
			while $going and $k < $info.len() {
				item = $info.get($k) ?? LayoutGsub.no_item
				this_comp = LayoutGsub.lig_comp(item)
				if LayoutGsub.lig_id(item) != $last_id or this_comp == 0 {
					$going = False
				} else {
					new_comp = $so_far - $last_count + this_comp.min($last_count)
					# `$k` is below the input's length.
					$info = $info.set($k, LayoutGsub.with_lprops(item, new_id.shl_wrap(5).bitwise_or(new_comp.bitwise_and(0x0F)))) ?? []
					$k = $k + 1
				}
			}
		}
		{ info: $info, out: $out, idx: $idx, output, serial, random, ops, stopped }
	}

	## The next ligature id (HarfBuzz's `_hb_allocate_lig_id`: an 8-bit
	## serial that skips 0, taken modulo 8 and never 0).
	allocate_lig_id : U64 -> { id : U64, serial : U64 }
	allocate_lig_id = |serial| {
		var $s = serial
		var $id = 0
		while $id == 0 {
			$s = ($s + 1) % 256
			if $s == 0 {
				$s = 1
			}
			$id = $s.bitwise_and(7)
		}
		{ id: $id, serial: $s }
	}

	# ------------------------------------------------------------ buffer

	## Copy the item at the cursor to the output and move on.
	next_glyph : Buf -> Buf
	next_glyph = |buf| {
		{ info, out, idx, output, serial, random, ops, stopped } = buf
		if output {
			item = info.get(idx) ?? LayoutGsub.no_item
			{ info, out: out.append(item), idx: idx + 1, output, serial, random, ops, stopped }
		} else {
			{ info, out, idx: idx + 1, output, serial, random, ops, stopped }
		}
	}

	next_glyphs : Buf, U64 -> Buf
	next_glyphs = |buf, n| {
		{ info, out, idx, output, serial, random, ops, stopped } = buf
		if output {
			var $out = out
			for k in idx..<(idx + n) {
				$out = $out.append(info.get(k) ?? LayoutGsub.no_item)
			}
			{ info, out: $out, idx: idx + n, output, serial, random, ops, stopped }
		} else {
			{ info, out, idx: idx + n, output, serial, random, ops, stopped }
		}
	}

	## Move the cursor so that the output holds `i` items (HarfBuzz's
	## `move_to`): forward copies input to the output, backward returns
	## output to the input.
	move_to : Buf, U64 -> Buf
	move_to = |buf, i| {
		{ info, out, idx, output, serial, random, ops, stopped } = buf
		written = out.len()
		if !output {
			{ info, out, idx: i, output, serial, random, ops, stopped }
		} else if written < i {
			count = (i - written).min(info.len() - idx.min(info.len()))
			var $out = out
			for k in idx..<(idx + count) {
				$out = $out.append(info.get(k) ?? LayoutGsub.no_item)
			}
			{ info, out: $out, idx: idx + count, output, serial, random, ops, stopped }
		} else if written > i {
			count = written - i
			if idx < count {
				{ info: out.sublist({ start: i, len: count }).concat(info.drop_first(idx)), out: out.take_first(i), idx: 0, output, serial, random, ops, stopped }
			} else {
				var $info = info
				for k in 0..<count {
					# `idx - count + k < idx <= len`.
					$info = $info.set(idx - count + k, out.get(i + k) ?? LayoutGsub.no_item) ?? []
				}
				{ info: $info, out: out.take_first(i), idx: idx - count, output, serial, random, ops, stopped }
			}
		} else {
			{ info, out, idx, output, serial, random, ops, stopped }
		}
	}

	## An item with another cluster, its unsafe-to-break flag cleared when
	## the cluster changes (HarfBuzz's `set_cluster`).
	set_cluster : Item, U64 -> Item
	set_cluster = |item, cluster|
		if (item.cluster == cluster) item else { ..item, cluster, mask: item.mask.bitwise_and(0x7FFFFFFFFFFFFFFF) }

	## Merge the clusters of input items `start ..< end` (HarfBuzz's
	## `merge_clusters` at a monotone level): they and their neighbours with
	## the same clusters take the smallest, continuing into the output when
	## the range starts at the cursor.
	merge_clusters : Buf, U64, U64 -> Buf
	merge_clusters = |buf, start, end_in|
		if end_in <= start + 1 {
			buf
		} else {
			{ info, out, idx, output, serial, random, ops, stopped } = buf
			n = info.len()
			end0 = end_in.min(n)
			cluster = LayoutGsub.min_cluster(info, start, end0, (info.get(start) ?? LayoutGsub.no_item).cluster)
			var $end = end0
			if cluster != (info.get($end - 1) ?? LayoutGsub.no_item).cluster {
				while $end < n and (info.get($end - 1) ?? LayoutGsub.no_item).cluster == (info.get($end) ?? LayoutGsub.no_item).cluster {
					$end = $end + 1
				}
			}
			var $start = start
			if cluster != (info.get($start) ?? LayoutGsub.no_item).cluster {
				while idx < $start and (info.get($start - 1) ?? LayoutGsub.no_item).cluster == (info.get($start) ?? LayoutGsub.no_item).cluster {
					$start = $start - 1
				}
			}
			var $out = out
			first = (info.get($start) ?? LayoutGsub.no_item).cluster
			if output and idx == $start and first != cluster {
				var $i = $out.len()
				while $i > 0 and ($out.get($i - 1) ?? LayoutGsub.no_item).cluster == first {
					# `$i - 1` is below the output's length.
					$out = $out.set($i - 1, LayoutGsub.set_cluster($out.get($i - 1) ?? LayoutGsub.no_item, cluster)) ?? []
					$i = $i - 1
				}
			}
			var $info = info
			for i in $start..<$end {
				# `i < $end <= n`.
				$info = $info.set(i, LayoutGsub.set_cluster($info.get(i) ?? LayoutGsub.no_item, cluster)) ?? []
			}
			{ info: $info, out: $out, idx, output, serial, random, ops, stopped }
		}

	## Delete the item at the cursor, merging its cluster as HarfBuzz's
	## `delete_glyph` does: nothing when a neighbour shares it; else into the
	## output's last cluster when smaller; else, with nothing written, into
	## the next item.
	delete_glyph : Buf -> Buf
	delete_glyph = |buf| {
		cur = buf.info.get(buf.idx) ?? LayoutGsub.no_item
		c = cur.cluster
		next_shares = buf.idx + 1 < buf.info.len() and (buf.info.get(buf.idx + 1) ?? LayoutGsub.no_item).cluster == c
		last = buf.out.last()
		{ shares, smaller, has_last } = match last {
			Ok(p) => { shares: p.cluster == c, smaller: c < p.cluster, has_last: True }
			Err(_) => { shares: False, smaller: False, has_last: False }
		}
		merged =
			if next_shares or shares {
				buf
			} else if has_last and smaller {
				old = (last ?? LayoutGsub.no_item).cluster
				# Destructured, so the output is not also held by `buf`.
				{ info, out, idx, output, serial, random, ops, stopped } = buf
				var $out = out
				var $i = $out.len()
				while $i > 0 and ($out.get($i - 1) ?? LayoutGsub.no_item).cluster == old {
					item = $out.get($i - 1) ?? LayoutGsub.no_item
					# `$i - 1` is below the output's length.
					$out = $out.set($i - 1, { ..item, cluster: c, mask: item.mask.bitwise_and(0x7FFFFFFFFFFFFFFF).bitwise_or(cur.mask.bitwise_and(LayoutGsub.unsafe)) }) ?? []
					$i = $i - 1
				}
				{ info, out: $out, idx, output, serial, random, ops, stopped }
			} else if !has_last and buf.idx + 1 < buf.info.len() {
				LayoutGsub.merge_clusters(buf, buf.idx, buf.idx + 2)
			} else {
				buf
			}
		{ info, out, idx, output, serial, random, ops, stopped } = merged
		{ info, out, idx: idx + 1, output, serial, random, ops, stopped }
	}

	## The smallest cluster of `run[start ..< end]` and `init`.
	min_cluster : List(Item), U64, U64, U64 -> U64
	min_cluster = |run, start, end, init| {
		var $c = init
		var $p = start
		while $p < end {
			$c = $c.min((run.get($p) ?? LayoutGsub.no_item).cluster)
			$p = $p + 1
		}
		$c
	}

	## Set the unsafe-to-break flag on `run[start ..< end]` as HarfBuzz's
	## `_infos_set_glyph_flags` does at monotone cluster levels, for a range
	## whose smallest cluster is `cluster`: the glyphs after the first
	## cluster's, or before the last cluster's.
	flag_range : List(Item), U64, U64, U64 -> List(Item)
	flag_range = |run, start, end_raw, cluster| {
		end = end_raw.min(run.len())
		if start >= end {
			run
		} else {
			first = (run.get(start) ?? LayoutGsub.no_item).cluster
			last = (run.get(end - 1) ?? LayoutGsub.no_item).cluster
			var $run = run
			if cluster != first and cluster != last {
				for p in start..<end {
					item = $run.get(p) ?? LayoutGsub.no_item
					if item.cluster != cluster {
						# `p < end <= len`.
						$run = $run.set(p, { ..item, mask: item.mask.bitwise_or(LayoutGsub.unsafe) }) ?? []
					}
				}
			} else if cluster == first {
				var $p = end
				while $p > start and ($run.get($p - 1) ?? LayoutGsub.no_item).cluster != first {
					item = $run.get($p - 1) ?? LayoutGsub.no_item
					# `start < $p <= end <= len`.
					$run = $run.set($p - 1, { ..item, mask: item.mask.bitwise_or(LayoutGsub.unsafe) }) ?? []
					$p = $p - 1
				}
			} else {
				var $p = start
				while $p < end and ($run.get($p) ?? LayoutGsub.no_item).cluster != last {
					item = $run.get($p) ?? LayoutGsub.no_item
					# `$p < end <= len`.
					$run = $run.set($p, { ..item, mask: item.mask.bitwise_or(LayoutGsub.unsafe) }) ?? []
					$p = $p + 1
				}
			}
			$run
		}
	}

	## The smallest of the first and last clusters of `run[start ..< end]`
	## and `init` (HarfBuzz's `_infos_find_min_cluster`, monotone levels).
	end_cluster : List(Item), U64, U64, U64 -> U64
	end_cluster = |run, start, end, init|
		if start >= end {
			init
		} else {
			init.min((run.get(start) ?? LayoutGsub.no_item).cluster).min((run.get(end - 1) ?? LayoutGsub.no_item).cluster)
		}

	## HarfBuzz's `unsafe_to_break` over input items `start ..< end`.
	unsafe_to_break : Buf, U64, U64 -> Buf
	unsafe_to_break = |buf, start, end_in| {
		end = end_in.min(buf.info.len())
		if end_in < start or end_in - start > 255 or end < start + 2 {
			buf
		} else {
			{ info, out, idx, output, serial, random, ops, stopped } = buf
			cluster = LayoutGsub.end_cluster(info, start, end, 0xFFFFFFFFFFFFFFFF)
			{ info: LayoutGsub.flag_range(info, start, end, cluster), out, idx, output, serial, random, ops, stopped }
		}
	}

	## HarfBuzz's `unsafe_to_break_from_outbuffer`: output items from `start`
	## and input items from the cursor to `end`. Like HarfBuzz it compares
	## the two indices directly for its 255-glyph limit.
	unsafe_to_break_from_outbuffer : Buf, U64, U64 -> Buf
	unsafe_to_break_from_outbuffer = |buf, start, end_in| {
		if end_in < start or end_in - start > 255 {
			buf
		} else {
			{ info, out, idx, output, serial, random, ops, stopped } = buf
			end = end_in.min(info.len())
			if !output {
				cluster = LayoutGsub.end_cluster(info, start, end, 0xFFFFFFFFFFFFFFFF)
				{ info: LayoutGsub.flag_range(info, start, end, cluster), out, idx, output, serial, random, ops, stopped }
			} else {
				written = out.len()
				c1 = LayoutGsub.end_cluster(info, idx, end, 0xFFFFFFFFFFFFFFFF)
				cluster = LayoutGsub.end_cluster(out, start, written, c1)
				# `written` is taken first: reading the list's length in the
				# call that consumes it would keep it shared and force a copy.
				flagged_info = LayoutGsub.flag_range(info, idx, end, cluster)
				flagged_out = LayoutGsub.flag_range(out, start, written, cluster)
				{ info: flagged_info, out: flagged_out, idx, output, serial, random, ops, stopped }
			}
		}
	}

	## Whether a lookup could apply anywhere in a run.
	any_start : Lookup, List(Item), U64 -> Bool
	any_start = |lookup, run, mask| {
		var $found = False
		var $i = 0
		n = run.len()
		while $i < n {
			item = run.get($i) ?? LayoutGsub.no_item
			if LayoutGsub.may_start(lookup, item.glyph) and LayoutGsub.applies(item.mask, mask) {
				$found = True
				$i = n
			} else {
				$i = $i + 1
			}
		}
		$found
	}

	## Whether a lookup may apply at a glyph. Every subtable needs the glyph
	## at the current position to be in its coverage, so a lookup keeps a
	## digest of every covered glyph: three 64-bit masks indexed by glyph
	## bits 0–5, 4–9 and 9–14. A glyph whose bit is clear in any mask is
	## covered by no subtable; the converse need not hold.
	may_start : Lookup, U64 -> Bool
	may_start = |lookup, glyph|
		lookup.d0.shr_wrap(glyph.bitwise_and(63).to_u8_wrap()).bitwise_and(1) == 1
			and lookup.d1.shr_wrap(glyph.shr_wrap(4).bitwise_and(63).to_u8_wrap()).bitwise_and(1) == 1
			and lookup.d2.shr_wrap(glyph.shr_wrap(9).bitwise_and(63).to_u8_wrap()).bitwise_and(1) == 1

	# Add the glyphs `first` to `last` to one mask of a digest.
	digest_range : U64, U8, U64, U64 -> U64
	digest_range = |mask, shift, first, last|
		if first > last {
			mask
		} else {
			low = first.shr_wrap(shift)
			high = last.shr_wrap(shift)
			if high - low >= 63 {
				0xFFFFFFFFFFFFFFFF
			} else {
				var $mask = mask
				var $k = low
				while $k <= high {
					$mask = $mask.bitwise_or((1.U64).shl_wrap($k.bitwise_and(63).to_u8_wrap()))
					$k = $k + 1
				}
				$mask
			}
		}

	# Whether a glyph matches the match stored at `values[at]`: the glyph
	# itself, a class in the class definition `classes`, or a coverage.
	match_one : LayoutGsub, U64, U64, U64, U64, U64 -> Bool
	match_one = |shape, kind, classes, classes_len, at, glyph| {
		value = shape.values.get(at) ?? 0
		if kind == 0 {
			value == glyph
		} else if kind == 1 {
			LayoutGsub.class_in(shape.ranges, classes, classes_len, glyph) == value
		} else {
			LayoutGsub.covered_in(shape.ranges, value, shape.values.get(at + 1) ?? 0, glyph).is_ok()
		}
	}

	## The coverage index of a glyph.
	covered : Ranges, U64 -> Try(U64, [NotCovered])
	covered = |ranges, glyph| LayoutGsub.covered_in(ranges, 0, ranges.len(), glyph)

	## The coverage index of a glyph in the coverage `ranges[start ..< start
	## + len]`.
	covered_in : Ranges, U64, U64, U64 -> Try(U64, [NotCovered])
	covered_in = |ranges, start, len, glyph| {
		var $low = 0
		var $high = len
		var $result = Err(NotCovered)
		while $low < $high {
			mid = ($low + $high) // 2
			range = ranges.get(start + mid) ?? { first: 1, last: 0, index: 0 }
			if glyph < range.first {
				$high = mid
			} else if glyph > range.last {
				$low = mid + 1
			} else {
				$result = Ok(range.index + glyph - range.first)
				$low = $high
			}
		}
		$result
	}

	## A glyph's class; classes are stored as ranges whose `index` is the
	## class.
	class_of : Ranges, U64 -> U64
	class_of = |ranges, glyph| LayoutGsub.class_in(ranges, 0, ranges.len(), glyph)

	## A glyph's class in the class definition `ranges[start ..< start +
	## len]`.
	class_in : Ranges, U64, U64, U64 -> U64
	class_in = |ranges, start, len, glyph| {
		var $low = 0
		var $high = len
		var $result = 0
		while $low < $high {
			mid = ($low + $high) // 2
			range = ranges.get(start + mid) ?? { first: 1, last: 0, index: 0 }
			if glyph < range.first {
				$high = mid
			} else if glyph > range.last {
				$low = mid + 1
			} else {
				$result = range.index
				$low = $high
			}
		}
		$result
	}

	# ------------------------------------------------------------ reading

	u16 : List(U8), U64 -> U64
	u16 = |bytes, at| (bytes.get(at) ?? 0).to_u64() * 256 + (bytes.get(at + 1) ?? 0).to_u64()

	u32 : List(U8), U64 -> U64
	u32 = |bytes, at| LayoutGsub.u16(bytes, at) * 65536 + LayoutGsub.u16(bytes, at + 2)

	fits : U64, U64, U64 -> Bool
	fits = |start, len, size| start <= size and len <= size - start

	tag : Str -> U64
	tag = |name| name.to_utf8().fold(0, |acc, b| acc * 256 + b.to_u64())

	## Reading work is counted in steps: one per table visited and one per
	## entry read. Offsets may point many times at the same data, so a few
	## bytes could otherwise describe billions of entries; a table that takes
	## more than eight steps per byte (plus a fixed allowance) is refused.
	## `spend` adds a visit costing `cost` entries to `steps`, failing when
	## the table's allowance is exceeded. Checking happens before the entries
	## are read, so refusing is cheap.
	spend : List(U8), U64, U64 -> Try(U64, [Bad(U64)])
	spend = |data, steps, cost| {
		total = steps + cost + 1
		if (total > 8 * data.len() + 16384) Err(Bad(0)) else Ok(total)
	}

	## The lookups of a font file's `GSUB` that features reach (none for a
	## font without `GSUB`). A table listing more than `max_lookups` lookups
	## is over the limit. The result has no `GDEF` glyph classes until
	## `with_gdef` gives it the font's.
	from_tables : List(U8), List(Sfnt.Table), U64 -> Try(LayoutGsub, [BadTable({ table : Str, offset : U32 }), OverLimit(Str)])
	from_tables = |bytes, tables, max_lookups|
		match Sfnt.located(bytes, tables, "GSUB", 10) {
			Missing => Ok(LayoutGsub.none)
			Bad(at) => Err(Sfnt.bad("GSUB", at))
			Found({ data: gsub, offset }) =>
				if LayoutGsub.u16(gsub, LayoutGsub.u16(gsub, 8)) > max_lookups {
					Err(OverLimit("max_lookups"))
				} else {
					LayoutGsub.read(gsub).map_err(|Bad(at)| Sfnt.bad("GSUB", offset + at))
				}
		}

	## Read a `GSUB` table: its script and feature lists, every lookup a
	## feature lists, and every lookup their rules call. Problems give their
	## offset in the table.
	read : List(U8) -> Try(LayoutGsub, [Bad(U64)])
	read = |gsub| {
		read_common = LayoutCommon.read(gsub)?
		common = read_common.common
		lookups = LayoutGsub.u16(gsub, 8)
		lookup_count = common.lookup_count
		# Lookups feature variations can swap in at some location are read
		# too (alternate feature tables and lookup variation records).
		used = LayoutVar.variation_lookups(gsub, LayoutCommon.all_feature_lookups(common))
		start = LayoutGsub.indices(0, lookup_count).keep_if(|index| used.get(index) ?? False)
		# Read the chosen lookups and those their rules call.
		var $lookups = List.repeat(LayoutGsub.no_lookup, lookup_count)
		var $built = { subtables: [], ranges: [], values: [], rules: [], steps: read_common.steps }
		var $seen = List.repeat(False, lookup_count)
		var $pending = start
		while !$pending.is_empty() {
			index = $pending.last() ?? 0
			$pending = $pending.drop_last(1)
			if !($seen.get(index) ?? True) {
				# Every pending index is below `lookup_count`.
				$seen = $seen.set(index, True) ?? []
				lookup = lookups + LayoutGsub.u16(gsub, lookups + 2 + 2 * index)
				first = $built.subtables.len()
				{ built: read_built, props, reverse } = LayoutGsub.read_lookup(gsub, lookup, $built)?
				$built = read_built
				end = $built.subtables.len()
				var $mode = 0
				var $d0 = 0
				var $d1 = 0
				var $d2 = 0
				for k in first..<end {
					sub = $built.subtables.get(k) ?? LayoutGsub.no_sub
					$mode = if (sub.kind == 1) $mode else 2
					for r in sub.coverage..<(sub.coverage + sub.coverage_len) {
						range = $built.ranges.get(r) ?? { first: 1, last: 0, index: 0 }
						$d0 = LayoutGsub.digest_range($d0, 0, range.first, range.last)
						$d1 = LayoutGsub.digest_range($d1, 4, range.first, range.last)
						$d2 = LayoutGsub.digest_range($d2, 9, range.first, range.last)
					}
					if sub.kind == 5 {
						# The lookups this subtable's rules call, in rule order.
						rules_end = $built.values.get(sub.data + sub.data_len) ?? 0
						for r in ($built.values.get(sub.data) ?? 0)..<rules_end {
							rule = $built.rules.get(r) ?? LayoutGsub.no_rule
							for j in 0..<rule.records_len {
								called = $built.values.get(rule.records + 2 * j + 1) ?? 0
								if called >= lookup_count {
									return Err(Bad(lookup))
								}
								$pending = $pending.append(called)
							}
						}
					}
				}
				# `index < lookup_count`, the length of `$lookups`.
				$lookups = $lookups.set(index, { start: first, count: end - first, mode: $mode, d0: $d0, d1: $d1, d2: $d2, props, reverse }) ?? []
			}
		}
		{ subtables, ranges, values, rules, steps: _ } = $built
		Ok({ common, lookups: $lookups, subtables, ranges, values, rules, gdef: LayoutGdef.none })
	}

	## A lookup's subtables, its properties (the lookup flag, plus the mark
	## filtering set times 65536 when the flag uses one) and whether it is a
	## reverse chaining lookup (type 8, or an extension whose first subtable
	## is, as HarfBuzz decides).
	read_lookup : List(U8), U64, Built -> Try({ built : Built, props : U64, reverse : Bool }, [Bad(U64)])
	read_lookup = |data, lookup, built| {
		kind = LayoutGsub.u16(data, lookup)
		flag = LayoutGsub.u16(data, lookup + 2)
		count = LayoutGsub.u16(data, lookup + 4)
		filtering = flag.bitwise_and(0x10) != 0
		if !LayoutGsub.fits(lookup, 6 + 2 * count + (if (filtering) 2 else 0), data.len()) {
			Err(Bad(lookup))
		} else {
			props = if (filtering) flag + LayoutGsub.u16(data, lookup + 6 + 2 * count) * 65536 else flag
			steps = LayoutGsub.spend(data, built.steps, count)?
			var $built = { ..built, steps }
			var $reverse = kind == 8
			for s in 0..<count {
				at = lookup + LayoutGsub.u16(data, lookup + 6 + 2 * s)
				real = if kind == 7 {
					if !LayoutGsub.fits(at, 8, data.len()) {
						return Err(Bad(lookup))
					}
					{ kind: LayoutGsub.u16(data, at + 2), at: at + LayoutGsub.u32(data, at + 4) }
				} else {
					{ kind, at }
				}
				if kind == 7 and s == 0 {
					$reverse = real.kind == 8
				}
				$built = LayoutGsub.read_subtable(data, real.kind, real.at, $built)?
			}
			Ok({ built: $built, props, reverse: $reverse })
		}
	}

	read_subtable : List(U8), U64, U64, Built -> Try(Built, [Bad(U64)])
	read_subtable = |data, kind, at, { subtables, ranges, values, rules, steps }| {
		if !LayoutGsub.fits(at, 6, data.len()) {
			Err(Bad(at))
		} else {
			format = LayoutGsub.u16(data, at)
			if kind == 1 {
				cov = LayoutGsub.append_coverage(data, at + LayoutGsub.u16(data, at + 2), steps, ranges)?
				base = { ..LayoutGsub.no_sub, kind: 1, coverage: cov.start, coverage_len: cov.len }
				if format == 1 {
					raw = LayoutGsub.u16(data, at + 4).to_i64_wrap()
					delta = if (raw >= 32768) raw - 65536 else raw
					Ok({ subtables: subtables.append({ ..base, delta }), ranges: cov.ranges, values, rules, steps: cov.steps })
				} else if format == 2 {
					glyphs = LayoutGsub.count_u16s(data, at + 4, cov.steps)?
					first = values.len()
					var $values = values
					for k in 0..<glyphs.count {
						$values = $values.append(LayoutGsub.u16(data, at + 6 + 2 * k))
					}
					Ok({ subtables: subtables.append({ ..base, data: first, data_len: glyphs.count }), ranges: cov.ranges, values: $values, rules, steps: glyphs.steps })
				} else {
					Err(Bad(at))
				}
			} else if (kind == 2 or kind == 3) and format == 1 {
				cov = LayoutGsub.append_coverage(data, at + LayoutGsub.u16(data, at + 2), steps, ranges)?
				offsets = LayoutGsub.count_u16s(data, at + 4, cov.steps)?
				var $steps = offsets.steps
				# Bounds of each sequence, filled in as the sequences are read.
				bounds = values.len()
				var $values = values.concat(List.repeat(0, offsets.count + 1))
				for s in 0..<offsets.count {
					sequence_at = at + LayoutGsub.u16(data, at + 6 + 2 * s)
					seq = LayoutGsub.count_u16s(data, sequence_at, $steps)?
					$steps = seq.steps
					# `bounds + s` is within the slots added above.
					$values = $values.set(bounds + s, $values.len()) ?? []
					for k in 0..<seq.count {
						$values = $values.append(LayoutGsub.u16(data, sequence_at + 2 + 2 * k))
					}
				}
				$values = $values.set(bounds + offsets.count, $values.len()) ?? []
				sub = { ..LayoutGsub.no_sub, kind, coverage: cov.start, coverage_len: cov.len, data: bounds, data_len: offsets.count }
				Ok({ subtables: subtables.append(sub), ranges: cov.ranges, values: $values, rules, steps: $steps })
			} else if kind == 4 and format == 1 {
				cov = LayoutGsub.append_coverage(data, at + LayoutGsub.u16(data, at + 2), steps, ranges)?
				offsets = LayoutGsub.count_u16s(data, at + 4, cov.steps)?
				var $steps = offsets.steps
				# Bounds of each ligature set, filled in as the sets are read.
				bounds = values.len()
				var $values = values.concat(List.repeat(0, offsets.count + 1))
				for s in 0..<offsets.count {
					set = at + LayoutGsub.u16(data, at + 6 + 2 * s)
					ligatures = LayoutGsub.count_u16s(data, set, $steps)?
					$steps = ligatures.steps
					# `bounds + s` is within the slots added above.
					$values = $values.set(bounds + s, $values.len()) ?? []
					for l in 0..<ligatures.count {
						lig = set + LayoutGsub.u16(data, set + 2 + 2 * l)
						count = LayoutGsub.u16(data, lig + 2)
						if count == 0 or !LayoutGsub.fits(lig, 2 + 2 * count, data.len()) {
							return Err(Bad(at))
						}
						$steps = LayoutGsub.spend(data, $steps, count)?
						$values = $values.append(LayoutGsub.u16(data, lig)).append(count - 1)
						for k in 1..<count {
							$values = $values.append(LayoutGsub.u16(data, lig + 2 + 2 * k))
						}
					}
				}
				$values = $values.set(bounds + offsets.count, $values.len()) ?? []
				sub = { ..LayoutGsub.no_sub, kind: 4, coverage: cov.start, coverage_len: cov.len, data: bounds, data_len: offsets.count }
				Ok({ subtables: subtables.append(sub), ranges: cov.ranges, values: $values, rules, steps: $steps })
			} else if kind == 5 or kind == 6 {
				LayoutGsub.read_context(data, kind == 6, format, at, { subtables, ranges, values, rules, steps })
			} else if kind == 8 and format == 1 {
				cov = LayoutGsub.append_coverage(data, at + LayoutGsub.u16(data, at + 2), steps, ranges)?
				back = LayoutGsub.append_coverages(data, at, at + 4, cov.steps, cov.ranges, values)?
				ahead_at = at + 6 + 2 * back.count
				ahead = LayoutGsub.append_coverages(data, at, ahead_at, back.steps, back.ranges, back.values)?
				glyphs_at = ahead_at + 2 + 2 * ahead.count
				glyphs = LayoutGsub.count_u16s(data, glyphs_at, ahead.steps)?
				first = ahead.values.len()
				var $values = ahead.values
				for k in 0..<glyphs.count {
					$values = $values.append(LayoutGsub.u16(data, glyphs_at + 2 + 2 * k))
				}
				sub = { ..LayoutGsub.no_sub, kind: 8, coverage: cov.start, coverage_len: cov.len, data: first, data_len: glyphs.count, match_kind: 2, back: back.start, back_len: back.count, ahead: ahead.start, ahead_len: ahead.count }
				Ok({ subtables: subtables.append(sub), ranges: ahead.ranges, values: $values, rules, steps: glyphs.steps })
			} else {
				Err(Bad(at))
			}
		}
	}

	read_context : List(U8), Bool, U64, U64, Built -> Try(Built, [Bad(U64)])
	read_context = |data, chained, format, at, { subtables, ranges, values, rules, steps }| {
		if format == 3 {
			if chained {
				back = LayoutGsub.append_coverages(data, at, at + 2, steps, ranges, values)?
				input_at = at + 4 + 2 * back.count
				input = LayoutGsub.append_coverages(data, at, input_at, back.steps, back.ranges, back.values)?
				ahead_at = input_at + 2 + 2 * input.count
				ahead = LayoutGsub.append_coverages(data, at, ahead_at, input.steps, input.ranges, input.values)?
				records = LayoutGsub.append_records(data, ahead_at + 2 + 2 * ahead.count, ahead.steps, ahead.values)?
				if input.count == 0 {
					Err(Bad(at))
				} else {
					rule = { back: back.start, back_len: back.count, input: input.start + 2, input_len: input.count - 1, ahead: ahead.start, ahead_len: ahead.count, records: records.start, records_len: records.count }
					LayoutGsub.context3_of(input.start, rule, 1, { subtables, ranges: ahead.ranges, values: records.values, rules, steps: records.steps })
				}
			} else {
				count = LayoutGsub.u16(data, at + 2)
				record_count = LayoutGsub.u16(data, at + 4)
				if count == 0 or !LayoutGsub.fits(at, 6 + 2 * count, data.len()) {
					Err(Bad(at))
				} else {
					var $steps = steps
					var $ranges = ranges
					var $values = values
					first = $values.len()
					for k in 0..<count {
						coverage = LayoutGsub.append_coverage(data, at + LayoutGsub.u16(data, at + 6 + 2 * k), $steps, $ranges)?
						$steps = coverage.steps
						$ranges = coverage.ranges
						$values = $values.append(coverage.start).append(coverage.len)
					}
					records = LayoutGsub.append_record_list(data, at + 6 + 2 * count, record_count, $steps, $values)?
					rule = { ..LayoutGsub.no_rule, input: first + 2, input_len: count - 1, records: records.start, records_len: records.count }
					LayoutGsub.context3_of(first, rule, 0, { subtables, ranges: $ranges, values: records.values, rules, steps: records.steps })
				}
			}
		} else if format == 1 or format == 2 {
			cov = LayoutGsub.append_coverage(data, at + LayoutGsub.u16(data, at + 2), steps, ranges)?
			var $steps = cov.steps
			var $ranges = cov.ranges
			by_class = format == 2
			# Offsets to class definitions, then to the rule sets. A null
			# offset (allowed for backtrack and lookahead classes) puts every
			# glyph in class 0.
			class_offsets = if (!by_class) [] else if (chained) [4, 6, 8] else [4]
			var $classes = []
			for o in class_offsets {
				offset = LayoutGsub.u16(data, at + o)
				if offset == 0 {
					$classes = $classes.append({ start: $ranges.len(), len: 0 })
				} else {
					classes = LayoutGsub.append_classes(data, at + offset, $steps, $ranges)?
					$steps = classes.steps
					$ranges = classes.ranges
					$classes = $classes.append({ start: classes.start, len: classes.len })
				}
			}
			sets_at = at + 4 + 2 * class_offsets.len()
			offsets = LayoutGsub.count_u16s(data, sets_at, $steps)?
			$steps = offsets.steps
			# Bounds of each rule set in `rules`, filled in as the sets are
			# read.
			bounds = values.len()
			var $values = values.concat(List.repeat(0, offsets.count + 1))
			var $rules = rules
			for s in 0..<offsets.count {
				o = LayoutGsub.u16(data, sets_at + 2 + 2 * s)
				# `bounds + s` is within the slots added above.
				$values = $values.set(bounds + s, $rules.len()) ?? []
				if o != 0 {
					set = at + o
					count = LayoutGsub.count_u16s(data, set, $steps)?
					$steps = count.steps
					for r in 0..<count.count {
						done = LayoutGsub.read_rule(data, chained, set + LayoutGsub.u16(data, set + 2 + 2 * r), $steps, $values, $rules)?
						$steps = done.steps
						$values = done.values
						$rules = done.rules
					}
				}
			}
			$values = $values.set(bounds + offsets.count, $rules.len()) ?? []
			absent = { start: 0, len: 0 }
			back_classes = $classes.get(0) ?? absent
			input_classes = if (chained) ($classes.get(1) ?? absent) else ($classes.get(0) ?? absent)
			ahead_classes = $classes.get(2) ?? absent
			sub = {
				kind: 5,
				coverage: cov.start,
				coverage_len: cov.len,
				delta: if (chained) 1 else 0,
				data: bounds,
				data_len: offsets.count,
				match_kind: if (by_class) 1 else 0,
				back: back_classes.start,
				back_len: back_classes.len,
				input: input_classes.start,
				input_len: input_classes.len,
				ahead: ahead_classes.start,
				ahead_len: ahead_classes.len,
			}
			Ok({ subtables: subtables.append(sub), ranges: $ranges, values: $values, rules: $rules, steps: $steps })
		} else {
			Err(Bad(at))
		}
	}

	# A context subtable of format 3: one rule set holding one rule, whose
	# coverage is the first input coverage (a start and length at
	# `values[first]`). `chained` is 1 for a chained subtable.
	context3_of : U64, Rule, I64, Built -> Try(Built, [Bad(U64)])
	context3_of = |first, rule, chained, { subtables, ranges, values, rules, steps }| {
		coverage = values.get(first) ?? 0
		coverage_len = values.get(first + 1) ?? 0
		bounds = values.len()
		sub = { ..LayoutGsub.no_sub, kind: 5, coverage, coverage_len, delta: chained, data: bounds, data_len: 1, match_kind: 2 }
		Ok({ subtables: subtables.append(sub), ranges, values: values.append(rules.len()).append(rules.len() + 1), rules: rules.append(rule), steps })
	}

	read_rule : List(U8), Bool, U64, U64, List(U64), List(Rule) -> Try({ values : List(U64), rules : List(Rule), steps : U64 }, [Bad(U64)])
	read_rule = |data, chained, at, steps, values, rules| {
		if chained {
			back = LayoutGsub.count_u16s(data, at, steps)?
			back_start = values.len()
			var $values = values
			for k in 0..<back.count {
				$values = $values.append(LayoutGsub.u16(data, at + 2 + 2 * k))
			}
			input_at = at + 2 + 2 * back.count
			input_count = LayoutGsub.u16(data, input_at)
			if input_count == 0 or !LayoutGsub.fits(input_at, 2 + 2 * (input_count - 1), data.len()) {
				Err(Bad(at))
			} else {
				counted = LayoutGsub.spend(data, back.steps, input_count)?
				input_start = $values.len()
				for k in 1..<input_count {
					$values = $values.append(LayoutGsub.u16(data, input_at + 2 * k))
				}
				ahead_at = input_at + 2 * input_count
				ahead = LayoutGsub.count_u16s(data, ahead_at, counted)?
				ahead_start = $values.len()
				for k in 0..<ahead.count {
					$values = $values.append(LayoutGsub.u16(data, ahead_at + 2 + 2 * k))
				}
				records = LayoutGsub.append_records(data, ahead_at + 2 + 2 * ahead.count, ahead.steps, $values)?
				rule = { back: back_start, back_len: back.count, input: input_start, input_len: input_count - 1, ahead: ahead_start, ahead_len: ahead.count, records: records.start, records_len: records.count }
				Ok({ values: records.values, rules: rules.append(rule), steps: records.steps })
			}
		} else {
			input_count = LayoutGsub.u16(data, at)
			record_count = LayoutGsub.u16(data, at + 2)
			if input_count == 0 or !LayoutGsub.fits(at, 4 + 2 * (input_count - 1), data.len()) {
				Err(Bad(at))
			} else {
				counted = LayoutGsub.spend(data, steps, input_count)?
				input_start = values.len()
				var $values = values
				for k in 1..<input_count {
					$values = $values.append(LayoutGsub.u16(data, at + 2 + 2 * k))
				}
				records = LayoutGsub.append_record_list(data, at + 2 + 2 * input_count, record_count, counted, $values)?
				rule = { ..LayoutGsub.no_rule, input: input_start, input_len: input_count - 1, records: records.start, records_len: records.count }
				Ok({ values: records.values, rules: rules.append(rule), steps: records.steps })
			}
		}
	}

	indices : U64, U64 -> List(U64)
	indices = |start, end| {
		var $out = List.with_capacity(if (end > start) end - start else 0)
		var $k = start
		while $k < end {
			$out = $out.append($k)
			$k = $k + 1
		}
		$out
	}

	# A count followed by that many 16-bit values: checks they fit and
	# spends the work of reading them, returning the count.
	count_u16s : List(U8), U64, U64 -> Try({ count : U64, steps : U64 }, [Bad(U64)])
	count_u16s = |data, at, steps| {
		count = LayoutGsub.u16(data, at)
		if !LayoutGsub.fits(at, 2 + 2 * count, data.len()) {
			Err(Bad(at))
		} else {
			after = LayoutGsub.spend(data, steps, count)?
			Ok({ count, steps: after })
		}
	}

	# A count at `at` followed by offsets (from `base`) to coverage tables.
	# Each coverage is added to `ranges`, and its start and length to
	# `values` from `start`.
	append_coverages : List(U8), U64, U64, U64, Ranges, List(U64) -> Try({ start : U64, count : U64, ranges : Ranges, values : List(U64), steps : U64 }, [Bad(U64)])
	append_coverages = |data, base, at, steps, ranges, values| {
		offsets = LayoutGsub.count_u16s(data, at, steps)?
		var $steps = offsets.steps
		var $ranges = ranges
		var $values = values
		start = $values.len()
		for k in 0..<offsets.count {
			coverage = LayoutGsub.append_coverage(data, base + LayoutGsub.u16(data, at + 2 + 2 * k), $steps, $ranges)?
			$steps = coverage.steps
			$ranges = coverage.ranges
			$values = $values.append(coverage.start).append(coverage.len)
		}
		Ok({ start, count: offsets.count, ranges: $ranges, values: $values, steps: $steps })
	}

	append_records : List(U8), U64, U64, List(U64) -> Try({ start : U64, count : U64, values : List(U64), steps : U64 }, [Bad(U64)])
	append_records = |data, at, steps, values| LayoutGsub.append_record_list(data, at + 2, LayoutGsub.u16(data, at), steps, values)

	# Nested lookup records, added to `values` as `at, lookup` pairs.
	append_record_list : List(U8), U64, U64, U64, List(U64) -> Try({ start : U64, count : U64, values : List(U64), steps : U64 }, [Bad(U64)])
	append_record_list = |data, at, count, steps, values|
		if !LayoutGsub.fits(at, 4 * count, data.len()) {
			Err(Bad(at))
		} else {
			after = LayoutGsub.spend(data, steps, count)?
			start = values.len()
			var $values = values
			for k in 0..<count {
				$values = $values.append(LayoutGsub.u16(data, at + 4 * k)).append(LayoutGsub.u16(data, at + 4 * k + 2))
			}
			Ok({ start, count, values: $values, steps: after })
		}

	## A coverage table as ranges of glyphs with their first coverage index.
	read_coverage : List(U8), U64, U64 -> Try({ value : Ranges, steps : U64 }, [Bad(U64)])
	read_coverage = |data, at, steps| {
		done = LayoutGsub.append_coverage(data, at, steps, [])?
		Ok({ value: done.ranges, steps: done.steps })
	}

	# A coverage table, added to `ranges` from `start` (`len` ranges).
	# Consecutive glyphs of a format 1 table are merged into one range.
	append_coverage : List(U8), U64, U64, Ranges -> Try({ start : U64, len : U64, ranges : Ranges, steps : U64 }, [Bad(U64)])
	append_coverage = |data, at, steps, ranges| {
		format = LayoutGsub.u16(data, at)
		count = LayoutGsub.u16(data, at + 2)
		start = ranges.len()
		if format == 1 and LayoutGsub.fits(at, 4 + 2 * count, data.len()) {
			after = LayoutGsub.spend(data, steps, count)?
			var $out = ranges
			for i in 0..<count {
				g = LayoutGsub.u16(data, at + 4 + 2 * i)
				merged = if $out.len() > start {
					match $out.last() {
						Ok(last) if last.last + 1 == g and last.index + (last.last - last.first) + 1 == i => Ok({ first: last.first, last: g, index: last.index })
						_ => Err(NotMerged)
					}
				} else {
					Err(NotMerged)
				}
				$out = match merged {
					# The list is not empty: it holds the range being merged.
					Ok(range) => $out.set($out.len() - 1, range) ?? []
					Err(_) => $out.append({ first: g, last: g, index: i })
				}
			}
			Ok({ start, len: $out.len() - start, ranges: $out, steps: after })
		} else if format == 2 and LayoutGsub.fits(at, 4 + 6 * count, data.len()) {
			after = LayoutGsub.spend(data, steps, count)?
			Ok({ start, len: count, ranges: LayoutGsub.append_range_records(data, at + 4, count, ranges), steps: after })
		} else {
			Err(Bad(at))
		}
	}

	## A class definition as ranges whose `index` is the class.
	read_classes : List(U8), U64, U64 -> Try({ value : Ranges, steps : U64 }, [Bad(U64)])
	read_classes = |data, at, steps| {
		done = LayoutGsub.append_classes(data, at, steps, [])?
		Ok({ value: done.ranges, steps: done.steps })
	}

	# A class definition, added to `ranges` from `start` (`len` ranges).
	append_classes : List(U8), U64, U64, Ranges -> Try({ start : U64, len : U64, ranges : Ranges, steps : U64 }, [Bad(U64)])
	append_classes = |data, at, steps, ranges| {
		format = LayoutGsub.u16(data, at)
		start = ranges.len()
		if format == 1 and LayoutGsub.fits(at, 6, data.len()) {
			first = LayoutGsub.u16(data, at + 2)
			count = LayoutGsub.u16(data, at + 4)
			if LayoutGsub.fits(at + 6, 2 * count, data.len()) {
				after = LayoutGsub.spend(data, steps, count)?
				var $out = ranges
				for k in 0..<count {
					$out = $out.append({ first: first + k, last: first + k, index: LayoutGsub.u16(data, at + 6 + 2 * k) })
				}
				Ok({ start, len: count, ranges: $out, steps: after })
			} else {
				Err(Bad(at))
			}
		} else if format == 2 and LayoutGsub.fits(at, 4, data.len()) {
			count = LayoutGsub.u16(data, at + 2)
			if LayoutGsub.fits(at + 4, 6 * count, data.len()) {
				after = LayoutGsub.spend(data, steps, count)?
				Ok({ start, len: count, ranges: LayoutGsub.append_range_records(data, at + 4, count, ranges), steps: after })
			} else {
				Err(Bad(at))
			}
		} else {
			Err(Bad(at))
		}
	}

	# Range records (first, last, value). They should be in increasing order
	# without overlaps, and lookups by binary search assume so, but they are
	# not checked: some fonts in use break the rule, and browsers read them
	# anyway. A range whose last glyph comes before its first matches no
	# glyph.
	append_range_records : List(U8), U64, U64, Ranges -> Ranges
	append_range_records = |data, at, count, ranges| {
		var $out = ranges
		for i in 0..<count {
			r = at + 6 * i
			$out = $out.append({ first: LayoutGsub.u16(data, r), last: LayoutGsub.u16(data, r + 2), index: LayoutGsub.u16(data, r + 4) })
		}
		$out
	}
}
