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

	CoverageRange : { first : U64, last : U64, index : U64 }

	Ranges : List(CoverageRange)

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
	Applied : { items : List(Item), stopped : U64, operations : U64 }

	## What a lookup is applied with: its mask and properties, the joiner
	## rules, `rand`, and the index in the plan of the step being applied
	## (recorded in the origin of every glyph it substitutes, also through
	## nested lookups).
	Ctx : { mask : U64, props : U64, auto_zwnj : Bool, auto_zwj : Bool, random : Bool, step : U64, per_syllable : Bool, positioning : Bool }

	## HarfBuzz's buffer while a lookup applies: the input `info` read from
	## `idx`, and, when `output`, the output written so far. `serial`
	## numbers ligatures, `random` is the `rand` feature's state, `ops`
	## the nested lookups applied so far and `stopped` the bounds that
	## stopped work so far (see `Applied`). HarfBuzz writes its output over
	## its input until a multiple substitution needs room, and only then
	## copies it apart; `aliased` says the output still shares the input's
	## storage, so the input's first `out.len()` items are the output's.
	## Only `rand`'s unsafe-to-break range reads that region, which
	## otherwise holds consumed input.
	Buf : { info : List(Item), out : List(Item), idx : U64, output : Bool, serial : U64, random : U64, ops : U64, stopped : U64, aliased : Bool }

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

	## Contextual positioning uses the same checked matching grammar as
	## substitutions. Keep the flat match pools without substitution lookups.
	from_contexts : Built -> LayoutGsub
	from_contexts = |built| { ..LayoutGsub.none, subtables: built.subtables, ranges: built.ranges, values: built.values, rules: built.rules }

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
	## the plan step that made the substitution in props bits 44-63, and a
	## ligature's component count in mask bits 32-38. A plan has fewer
	## than 2^20 steps (at most sixteen stages of 65535 lookups,
	## the format's count), and a ligature at most `max_context` (64) components.
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
	origin_step = |item| item.props.shr_zf_wrap(44).bitwise_and(0xFFFFF)

	origin_components : Item -> U64
	origin_components = |item| item.mask.shr_zf_wrap(32).bitwise_and(0x7F)

	## An item with its origin set.
	with_origin : Item, U64, U64, U64 -> Item
	with_origin = |item, kind, step, components| {
		props = item.props.bitwise_and(0x000001FFFFFFFFFF).bitwise_or(kind.bitwise_and(0x7).shl_wrap(41)).bitwise_or(step.bitwise_and(0xFFFFF).shl_wrap(44))
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
		# A digest of the run's glyphs, made again after each lookup that
		# runs: a lookup whose digest misses it cannot start anywhere, so
		# it is passed over without visiting the run.
		var $digest = LayoutGsub.run_digest($run)
		for step_index in 0..<plan.len() {
			step = plan.get(step_index) ?? { index: 0, mask: 0, auto_zwnj: False, auto_zwj: False, random: False }
			lookup = shape.lookups.get(step.index) ?? LayoutGsub.no_lookup
			if lookup.count > 0 and LayoutGsub.digests_meet(lookup, $digest) and LayoutGsub.any_start(lookup, $run, step.mask) {
				ctx = { mask: step.mask, props: LayoutGsub.sanitize_props(shape, lookup.props), auto_zwnj: step.auto_zwnj, auto_zwj: step.auto_zwj, random: step.random, step: step_index, per_syllable: False, positioning: False }
				if lookup.reverse {
					{ buf, work } = LayoutGsub.apply_backward(shape, lookup, ctx, { info: $run, out: [], idx: 0, output: False, serial: $serial, random: $random, ops: $ops, stopped: $stopped, aliased: False }, limits, $work)
					{ info, out: _, idx: _, output: _, serial, random, ops, stopped, aliased: _ } = buf
					$run = info
					$serial = serial
					$random = random
					$ops = ops
					$stopped = stopped
					$work = work
				} else if lookup.mode == 0 {
					$run = LayoutGsub.apply_singles(shape, lookup, ctx, $run)
				} else {
					{ buf, work } = LayoutGsub.apply_forward(shape, lookup, ctx, { info: $run, out: $spare.clear().reserve($run.len()), idx: 0, output: True, serial: $serial, random: $random, ops: $ops, stopped: $stopped, aliased: True }, limits, $work)
					{ info, out, idx, output: _, serial, random, ops, stopped, aliased: _ } = buf
					# Sync: the rest of the input follows the output.
					$run = if (idx < info.len()) out.concat(info.drop_first(idx)) else out
					$spare = info
					$serial = serial
					$random = random
					$ops = ops
					$stopped = stopped
					$work = work
				}
				$digest = LayoutGsub.run_digest($run)
			}
		}
		{ items: $run, stopped: $stopped, operations: $ops }
	}

	## State retained across script-specific pauses. Origin step numbers,
	## ligature serials, random state, work lists and budgets never reset.
	Session : { items : List(Item), serial : U64, random : U64, operations : U64, stopped : U64, step_offset : U64, spare : List(Item), work : Work }
	StageStep : { step : Step, per_syllable : Bool }

	begin : List(Item) -> Session
	begin = |items| { items, serial: 0, random: 1, operations: 0, stopped: 0, step_offset: 0, spare: [], work: { scratch: [], frames: [], positions: [] } }

	with_items : Session, List(Item) -> Session
	with_items = |session, items| { ..session, items }

	clear_substitution_flags : List(Item) -> List(Item)
	clear_substitution_flags = |items| items.map(|item| LayoutGsub.with_gprops(item, LayoutGsub.gprops(item).bitwise_and(0xFF8F)))

	resume : LayoutGsub, List(StageStep), Session, Limits -> Session
	resume = |shape, plan, session, limits| {
		{ items, serial: serial_in, random: random_in, operations, stopped: stopped_in, step_offset, spare, work: work_in } = session
		var $run = items
		# The previous run of a general lookup, whose allocation the next one
		# writes into.
		var $spare = spare
		var $serial = serial_in
		var $random = random_in
		var $ops = operations
		var $stopped = stopped_in
		var $work = work_in
		# A digest of the run's glyphs, made again after each lookup that
		# runs: a lookup whose digest misses it cannot start anywhere, so
		# it is passed over without visiting the run.
		var $digest = LayoutGsub.run_digest($run)
		for step_index in 0..<plan.len() {
			entry = plan.get(step_index) ?? { step: { index: 0, mask: 0, auto_zwnj: False, auto_zwj: False, random: False }, per_syllable: False }
			step = entry.step
			lookup = shape.lookups.get(step.index) ?? LayoutGsub.no_lookup
			if lookup.count > 0 and LayoutGsub.digests_meet(lookup, $digest) and LayoutGsub.any_start(lookup, $run, step.mask) {
				ctx = { mask: step.mask, props: LayoutGsub.sanitize_props(shape, lookup.props), auto_zwnj: step.auto_zwnj, auto_zwj: step.auto_zwj, random: step.random, step: step_offset + step_index, per_syllable: entry.per_syllable, positioning: False }
				if lookup.reverse {
					{ buf, work } = LayoutGsub.apply_backward(shape, lookup, ctx, { info: $run, out: [], idx: 0, output: False, serial: $serial, random: $random, ops: $ops, stopped: $stopped, aliased: False }, limits, $work)
					{ info, out: _, idx: _, output: _, serial, random, ops, stopped, aliased: _ } = buf
					$run = info
					$serial = serial
					$random = random
					$ops = ops
					$stopped = stopped
					$work = work
				} else if lookup.mode == 0 {
					$run = LayoutGsub.apply_singles(shape, lookup, ctx, $run)
				} else {
					{ buf, work } = LayoutGsub.apply_forward(shape, lookup, ctx, { info: $run, out: $spare.clear().reserve($run.len()), idx: 0, output: True, serial: $serial, random: $random, ops: $ops, stopped: $stopped, aliased: True }, limits, $work)
					{ info, out, idx, output: _, serial, random, ops, stopped, aliased: _ } = buf
					# Sync: the rest of the input follows the output.
					$run = if (idx < info.len()) out.concat(info.drop_first(idx)) else out
					$spare = info
					$serial = serial
					$random = random
					$ops = ops
					$stopped = stopped
					$work = work
				}
				$digest = LayoutGsub.run_digest($run)
			}
		}
		{ items: $run, serial: $serial, random: $random, operations: $ops, stopped: $stopped, step_offset: step_offset + plan.len(), spare: $spare, work: $work }
	}

	## HarfBuzz's structural would-apply probe. Context rules test their
	## input only; chained rules with zero_context additionally require
	## empty backtrack/lookahead. No glyphs, flags or trace state change.
	would_substitute : LayoutGsub, List(U64), List(U64), Bool, U64 -> { matches : Bool, operations : U64, stopped : U64 }
	would_substitute = |shape, indices, glyphs, zero_context, budget| {
		if glyphs.is_empty() {
			return { matches: False, operations: 0, stopped: 0 }
		}
		var $operations = 0
		for index in indices {
			if $operations >= budget {
				return { matches: False, operations: $operations, stopped: LayoutGsub.stopped_operations }
			}
			$operations = $operations + 1
			lookup = shape.lookups.get(index) ?? LayoutGsub.no_lookup
			for at in lookup.start..<(lookup.start + lookup.count) {
				sub = shape.subtables.get(at) ?? LayoutGsub.no_sub
				if LayoutGsub.probe_subtable(shape, sub, glyphs, zero_context) {
					return { matches: True, operations: $operations, stopped: 0 }
				}
			}
		}
		{ matches: False, operations: $operations, stopped: 0 }
	}

	probe_sequence : LayoutGsub, Seq, List(U64) -> Bool
	probe_sequence = |shape, seq, glyphs| {
		var $matches = True
		for i in 1..<glyphs.len() {
			if !LayoutGsub.seq_matches(shape, seq, i - 1, glyphs.get(i) ?? 0) {
				$matches = False
			}
		}
		$matches
	}

	probe_subtable : LayoutGsub, Sub, List(U64), Bool -> Bool
	probe_subtable = |shape, sub, glyphs, zero_context| {
		first = glyphs.first() ?? 0
		coverage = LayoutGsub.covered_in(shape.ranges, sub.coverage, sub.coverage_len, first) ?? return False
		if sub.kind == 1 or sub.kind == 2 or sub.kind == 3 or sub.kind == 8 {
			return glyphs.len() == 1
		}
		if sub.kind == 4 {
			if coverage >= sub.data_len {
				return False
			}
			end = shape.values.get(sub.data + coverage + 1) ?? 0
			var $at = shape.values.get(sub.data + coverage) ?? 0
			while $at < end {
				components = shape.values.get($at + 1) ?? 0
				if components + 1 == glyphs.len() and LayoutGsub.probe_sequence(shape, { kind: 0, classes: 0, classes_len: 0, at: $at + 2, stride: 1 }, glyphs) {
					return True
				}
				$at = $at + 2 + components
			}
		} else if sub.kind == 5 {
			slot = if (sub.match_kind == 1) LayoutGsub.class_in(shape.ranges, sub.input, sub.input_len, first) else if (sub.match_kind == 2) 0 else coverage
			if slot >= sub.data_len {
				return False
			}
			start = shape.values.get(sub.data + slot) ?? 0
			end = shape.values.get(sub.data + slot + 1) ?? 0
			for at in start..<end {
				rule = shape.rules.get(at) ?? LayoutGsub.no_rule
				if rule.input_len + 1 == glyphs.len() and (!zero_context or sub.delta == 0 or (rule.back_len == 0 and rule.ahead_len == 0)) {
					seq = { kind: sub.match_kind, classes: sub.input, classes_len: sub.input_len, at: rule.input, stride: if (sub.match_kind == 2) 2 else 1 }
					if LayoutGsub.probe_sequence(shape, seq, glyphs) {
						return True
					}
				}
			}
		}
		False
	}

	## The digest of every glyph of a run, in the form of a lookup's (see
	## `may_start`).
	run_digest : List(Item) -> { d0 : U64, d1 : U64, d2 : U64 }
	run_digest = |run| {
		var $d0 = 0
		var $d1 = 0
		var $d2 = 0
		for item in run {
			g = item.glyph
			$d0 = $d0.bitwise_or((1.U64).shl_wrap(g.bitwise_and(63).to_u8_wrap()))
			$d1 = $d1.bitwise_or((1.U64).shl_wrap(g.shr_wrap(4).bitwise_and(63).to_u8_wrap()))
			$d2 = $d2.bitwise_or((1.U64).shl_wrap(g.shr_wrap(9).bitwise_and(63).to_u8_wrap()))
		}
		{ d0: $d0, d1: $d1, d2: $d2 }
	}

	## Whether a lookup's digest and a run's share a glyph's bits in every
	## mask: needed for any glyph of the run to pass `may_start`.
	digests_meet : Lookup, { d0 : U64, d1 : U64, d2 : U64 } -> Bool
	digests_meet = |lookup, digest|
		lookup.d0.bitwise_and(digest.d0) != 0 and lookup.d1.bitwise_and(digest.d1) != 0 and lookup.d2.bitwise_and(digest.d2) != 0

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
		{ info, out, idx, output, serial, random, ops, stopped, aliased } = buf
		cur = info.get(idx) ?? LayoutGsub.no_item
		item = LayoutGsub.resubstituted({ ..LayoutGsub.set_glyph_class(shape, cur, glyph, 0, False, False), glyph }, step)
		if output {
			{ info, out: out.append(item), idx: idx + 1, output, serial, random, ops, stopped, aliased }
		} else {
			# The cursor is inside the input.
			{ info: info.set(idx, item) ?? [], out, idx: idx + 1, output, serial, random, ops, stopped, aliased }
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
				{ info, out, idx, output, serial, random, ops, stopped, aliased } = buf
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
				# HarfBuzz copies its output apart once it would overtake
				# the input: before the cursor moves past the replaced glyph.
				{ buf: { info, out: $out, idx: idx + 1, output, serial, random, ops, stopped, aliased: aliased and $out.len() <= idx }, work, outcome: Applied }
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
					{ info, out, idx, output, serial, random: _, ops, stopped, aliased } = LayoutGsub.unsafe_to_break_all(buf)
					{ index: next % count + 1, after: { info, out, idx, output, serial, random: next, ops, stopped, aliased } }
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
			# Ligatures whose second component is not the next input glyph
			# cannot match; they are passed without matching, as HarfBuzz does.
			{ target, any } = match LayoutGsub.next_input(shape, ctx, buf) {
				Next(g) => { target: g, any: False }
				# No glyph has this value: every ligature of two or more
				# components is passed.
				End => { target: 0xFFFFFFFFFFFFFFFF, any: False }
				Unknown => { target: 0, any: True }
			}
			var $p = LayoutGsub.scan_ligatures(shape.values, shape.values.get(sub.data + at) ?? 0, end, target, any)
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
						$p = LayoutGsub.scan_ligatures(shape.values, $p + 2 + components, end, target, any)
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

	## The first ligature of a set, from `values[p]` up to `end`, that may
	## match: a single glyph, or one whose second component is `target`
	## (any ligature when `any`).
	scan_ligatures : List(U64), U64, U64, U64, Bool -> U64
	scan_ligatures = |values, p, end, target, any| {
		var $p = p
		var $scanning = True
		while $scanning and $p < end {
			components = values.get($p + 1) ?? 0
			if components == 0 or any or (values.get($p + 2) ?? 0) == target {
				$scanning = False
			} else {
				$p = $p + 2 + components
			}
		}
		$p
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
				{ info, out, idx, output, serial, random, ops, stopped, aliased } = LayoutGsub.unsafe_to_break_from_outbuffer(buf, before.start, after.end)
				cur = info.get(idx) ?? LayoutGsub.no_item
				glyph = shape.values.get(sub.data + at) ?? 0
				item = LayoutGsub.resubstituted({ ..LayoutGsub.set_glyph_class(shape, cur, glyph, 0, False, False), glyph }, ctx.step)
				# The cursor is inside the input.
				{ buf: { info: info.set(idx, item) ?? [], out, idx, output, serial, random, ops, stopped, aliased }, work, outcome: Applied }
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
		skip = LayoutGsub.skip_of(shape, ctx, item, context)
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

	## HarfBuzz's `may_skip` for one item: skipped outright (`SkipYes`,
	## the lookup flags hide it), skipped unless it matches (`SkipMaybe`, a
	## default ignorable the joiner rules let pass) or never (`SkipNo`).
	skip_of : LayoutGsub, Ctx, Item, Bool -> [SkipYes, SkipMaybe, SkipNo]
	skip_of = |shape, ctx, item, context|
		if !LayoutGsub.check_glyph_property(shape, item, ctx.props) {
			SkipYes
		} else if LayoutGsub.is_default_ignorable(item) and (ctx.positioning or (context and ctx.auto_zwnj) or !ShaperUnicode.is_zwnj(item.props)) and (context or ctx.auto_zwj or !ShaperUnicode.is_zwj(item.props)) and (ctx.positioning or item.props.bitwise_and(ShaperUnicode.hidden) == 0) {
			SkipMaybe
		} else {
			SkipNo
		}

	## The item input matching after the cursor stops at whatever it is
	## asked to match (HarfBuzz's fast path in `LigatureSet::apply`): past
	## the items the lookup flags hide, `Next(glyph)` when that item cannot
	## be skipped, so an input whose next entry is another glyph cannot
	## match; `End` when the run ends first, so no input of two or more
	## entries can match; `Unknown` when the item may be skipped.
	next_input : LayoutGsub, Ctx, Buf -> [Next(U64), End, Unknown]
	next_input = |shape, ctx, buf| {
		n = buf.info.len()
		var $at = buf.idx + 1
		var $result = End
		while $at < n {
			item = buf.info.get($at) ?? LayoutGsub.no_item
			match LayoutGsub.skip_of(shape, ctx, item, False) {
				SkipYes => {
					$at = $at + 1
				}
				SkipMaybe => {
					$result = Unknown
					$at = n
				}
				SkipNo => {
					$result = Next(item.glyph)
					$at = n
				}
			}
		}
		$result
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
						# Only input matching is constrained to the starting syllable;
						# skipped glyphs and context use HarfBuzz's iterator rules.
						syllable = cur.mask.bitwise_and(0x1FE000000000000)
						same_syllable = !ctx.per_syllable or syllable == 0 or item.mask.bitwise_and(0x1FE000000000000) == syllable
						match LayoutGsub.step_item(shape, ctx, item, False, same_syllable and LayoutGsub.seq_matches(shape, seq, $i - 1, item.glyph)) {
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
						syllable = (buf.info.get(buf.idx) ?? LayoutGsub.no_item).mask.bitwise_and(0x1FE000000000000)
						same_syllable = !ctx.per_syllable or syllable == 0 or item.mask.bitwise_and(0x1FE000000000000) == syllable
						match LayoutGsub.step_item(shape, ctx, item, True, same_syllable and LayoutGsub.seq_matches(shape, seq, $i, item.glyph)) {
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
						syllable = (buf.info.get(buf.idx) ?? LayoutGsub.no_item).mask.bitwise_and(0x1FE000000000000)
						same_syllable = !ctx.per_syllable or syllable == 0 or item.mask.bitwise_and(0x1FE000000000000) == syllable
						match LayoutGsub.step_item(shape, ctx, item, True, same_syllable and LayoutGsub.seq_matches(shape, seq, $i, item.glyph)) {
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
		{ info: info_in, out: out_in, idx: idx_in, output, serial: serial_in, random, ops, stopped, aliased } = merged
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
		{ info: $info, out: $out, idx: $idx, output, serial, random, ops, stopped, aliased }
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
		{ info, out, idx, output, serial, random, ops, stopped, aliased } = buf
		if output {
			item = info.get(idx) ?? LayoutGsub.no_item
			{ info, out: out.append(item), idx: idx + 1, output, serial, random, ops, stopped, aliased }
		} else {
			{ info, out, idx: idx + 1, output, serial, random, ops, stopped, aliased }
		}
	}

	next_glyphs : Buf, U64 -> Buf
	next_glyphs = |buf, n| {
		{ info, out, idx, output, serial, random, ops, stopped, aliased } = buf
		if output {
			var $out = out
			for k in idx..<(idx + n) {
				$out = $out.append(info.get(k) ?? LayoutGsub.no_item)
			}
			{ info, out: $out, idx: idx + n, output, serial, random, ops, stopped, aliased }
		} else {
			{ info, out, idx: idx + n, output, serial, random, ops, stopped, aliased }
		}
	}

	## Move the cursor so that the output holds `i` items (HarfBuzz's
	## `move_to`): forward copies input to the output, backward returns
	## output to the input.
	move_to : Buf, U64 -> Buf
	move_to = |buf, i| {
		{ info, out, idx, output, serial, random, ops, stopped, aliased } = buf
		written = out.len()
		if !output {
			{ info, out, idx: i, output, serial, random, ops, stopped, aliased }
		} else if written < i {
			count = (i - written).min(info.len() - idx.min(info.len()))
			var $out = out
			for k in idx..<(idx + count) {
				$out = $out.append(info.get(k) ?? LayoutGsub.no_item)
			}
			{ info, out: $out, idx: idx + count, output, serial, random, ops, stopped, aliased }
		} else if written > i {
			count = written - i
			if idx < count {
				{ info: out.sublist({ start: i, len: count }).concat(info.drop_first(idx)), out: out.take_first(i), idx: 0, output, serial, random, ops, stopped, aliased }
			} else {
				var $info = info
				for k in 0..<count {
					# `idx - count + k < idx <= len`.
					$info = $info.set(idx - count + k, out.get(i + k) ?? LayoutGsub.no_item) ?? []
				}
				{ info: $info, out: out.take_first(i), idx: idx - count, output, serial, random, ops, stopped, aliased }
			}
		} else {
			{ info, out, idx, output, serial, random, ops, stopped, aliased }
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
			{ info, out, idx, output, serial, random, ops, stopped, aliased } = buf
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
			{ info: $info, out: $out, idx, output, serial, random, ops, stopped, aliased }
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
				{ info, out, idx, output, serial, random, ops, stopped, aliased } = buf
				var $out = out
				var $i = $out.len()
				while $i > 0 and ($out.get($i - 1) ?? LayoutGsub.no_item).cluster == old {
					item = $out.get($i - 1) ?? LayoutGsub.no_item
					# `$i - 1` is below the output's length.
					$out = $out.set($i - 1, { ..item, cluster: c, mask: item.mask.bitwise_and(0x7FFFFFFFFFFFFFFF).bitwise_or(cur.mask.bitwise_and(LayoutGsub.unsafe)) }) ?? []
					$i = $i - 1
				}
				{ info, out: $out, idx, output, serial, random, ops, stopped, aliased }
			} else if !has_last and buf.idx + 1 < buf.info.len() {
				LayoutGsub.merge_clusters(buf, buf.idx, buf.idx + 2)
			} else {
				buf
			}
		{ info, out, idx, output, serial, random, ops, stopped, aliased } = merged
		{ info, out, idx: idx + 1, output, serial, random, ops, stopped, aliased }
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
			{ info, out, idx, output, serial, random, ops, stopped, aliased } = buf
			cluster = LayoutGsub.end_cluster(info, start, end, 0xFFFFFFFFFFFFFFFF)
			{ info: LayoutGsub.flag_range(info, start, end, cluster), out, idx, output, serial, random, ops, stopped, aliased }
		}
	}

	## HarfBuzz's `unsafe_to_break(0, len)` for `rand`, over HarfBuzz's
	## input array: while the output shares the input's storage, its first
	## `out.len()` items are the output's (see `Buf`), so they are flagged
	## with the rest of the input as one range; the consumed input between
	## them and the cursor is flagged as HarfBuzz flags it and then
	## discarded. Once separate, the output is not flagged.
	unsafe_to_break_all : Buf -> Buf
	unsafe_to_break_all = |buf| {
		written = buf.out.len()
		if !buf.output or !buf.aliased or written == 0 {
			LayoutGsub.unsafe_to_break(buf, 0, buf.info.len())
		} else {
			{ info, out, idx, output, serial, random, ops, stopped, aliased } = buf
			n = info.len()
			# The output never overtakes the cursor while aliased:
			# `written <= idx <= n`.
			if n > 255 or n < 2 {
				{ info, out, idx, output, serial, random, ops, stopped, aliased }
			} else {
				cluster = (out.get(0) ?? LayoutGsub.no_item).cluster.min((info.get(n - 1) ?? LayoutGsub.no_item).cluster)
				# HarfBuzz's array: the output, then the input after it.
				joined = out.concat(info.drop_first(written))
				flagged = LayoutGsub.flag_range(joined, 0, n, cluster)
				{ info: info.take_first(written).concat(flagged.drop_first(written)), out: flagged.take_first(written), idx, output, serial, random, ops, stopped, aliased }
			}
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
			{ info, out, idx, output, serial, random, ops, stopped, aliased } = buf
			end = end_in.min(info.len())
			if !output {
				cluster = LayoutGsub.end_cluster(info, start, end, 0xFFFFFFFFFFFFFFFF)
				{ info: LayoutGsub.flag_range(info, start, end, cluster), out, idx, output, serial, random, ops, stopped, aliased }
			} else {
				written = out.len()
				c1 = LayoutGsub.end_cluster(info, idx, end, 0xFFFFFFFFFFFFFFFF)
				cluster = LayoutGsub.end_cluster(out, start, written, c1)
				# `written` is taken first: reading the list's length in the
				# call that consumes it would keep it shared and force a copy.
				flagged_info = LayoutGsub.flag_range(info, idx, end, cluster)
				flagged_out = LayoutGsub.flag_range(out, start, written, cluster)
				{ info: flagged_info, out: flagged_out, idx, output, serial, random, ops, stopped, aliased }
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
	## font without `GSUB`). The table is first checked whole as OTS checks
	## it (`ots_check`), against `maxp`'s glyph count and the mark glyph
	## sets of the font's `GDEF`. A table listing more than `max_lookups`
	## lookups is over the limit. The result has no `GDEF` glyph classes
	## until `with_gdef` gives it the font's.
	from_tables : List(U8), List(Sfnt.Table), U64 -> Try(LayoutGsub, [BadTable({ table : Str, offset : U32 }), OverLimit(Str)])
	from_tables = |bytes, tables, max_lookups|
		match Sfnt.located(bytes, tables, "GSUB", 10) {
			Missing => Ok(LayoutGsub.none)
			Bad(at) => Err(Sfnt.bad("GSUB", at))
			Found({ data: gsub, offset }) => {
				# `numGlyphs` as stored (`Face` reads `GSUB` only when `maxp`
				# reads). Tables are found by their tags as numbers (`maxp`
				# 0x6D617870, `GDEF` 0x47444546), which costs no allocation.
				glyphs = match tables.find_first(|t| t.tag == 0x6D617870) {
					Ok(t) if LayoutGsub.fits(t.offset, t.length, bytes.len()) and t.length >= 6 => LayoutGsub.u16(bytes, t.offset + 4)
					_ => 0
				}
				match LayoutGsub.ots_check(gsub, glyphs, LayoutGsub.mark_sets(bytes, tables)) {
					Err(Bad(at)) => Err(Sfnt.bad("GSUB", offset + at))
					Ok(_) =>
						if LayoutGsub.u16(gsub, LayoutGsub.u16(gsub, 8)) > max_lookups {
							Err(OverLimit("max_lookups"))
						} else {
							LayoutGsub.read(gsub).map_err(|Bad(at)| Sfnt.bad("GSUB", offset + at))
						}
				}
			}
		}

	## How many mark glyph sets the font's `GDEF` defines, as OTS counts
	## them (`ots/src/gdef.cc`, `ParseMarkGlyphSetsDefTable`): 0 before
	## version 1.2 or without the table of sets; `Absent` without `GDEF`.
	## A `GDEF` too broken to say is refused by its own check.
	mark_sets : List(U8), List(Sfnt.Table) -> [Present(U64), Absent]
	mark_sets = |bytes, tables|
		match tables.find_first(|t| t.tag == 0x47444546) {
			Ok(t) if LayoutGsub.fits(t.offset, t.length, bytes.len()) and t.length >= 4 => {
				inside = |at, len| LayoutGsub.fits(at, len, t.length)
				field = |at| LayoutGsub.u16(bytes, t.offset + at)
				at = if (field(2) >= 2 and inside(12, 2)) field(12) else 0
				Present(if (at != 0 and inside(at, 4)) field(at + 2) else 0)
			}
			_ => Absent
		}

	# ------------------------------------------------------------ OTS checks

	## What the OTS checks of a `GSUB` table compare with: the table, the
	## font's glyph count (`maxp`), the table's lookup count, the number of
	## mark glyph sets in the font's `GDEF` (when it has one) and the work
	## allowed (see `ots_check`).
	OtsContext : { data : List(U8), glyphs : U64, lookups : U64, sets : [Present(U64), Absent], budget : U64 }

	## Check a `GSUB` table exactly as OTS 9.3.0 does (`ots/src/layout.cc`,
	## `OpenTypeLayoutTable::Parse`, and `ots/src/gsub.cc`; line numbers
	## below are those files'), so a font reads exactly when a browser
	## accepts its substitutions. OTS checks every lookup, script, language
	## system and feature, not only those a feature reaches:
	##
	## - the header: version 1.0 or 1.1, and the lookup, feature and script
	##   lists (each may be absent) after the header and inside the table
	##   (layout.cc 1648-1708);
	## - every lookup (`ots_lookup`), feature (`ots_feature`), script and
	##   language system (`ots_script`), with every glyph id below the glyph
	##   count, every lookup index below the lookup count and every feature
	##   index below the feature count;
	## - every offset past the fixed part of the table it is in (OTS's
	##   "end" of each table) and inside the `GSUB` table.
	##
	## OTS only warns about script and feature records out of tag order, so
	## they are accepted. The `FeatureVariations` table (version 1.1) is
	## checked where its variations are read (`LayoutVar`), not here.
	##
	## Offsets alias, so a few bytes can describe a great deal of work. The
	## work is counted in steps, one per table visited and one per entry,
	## and a table needing more than 64 steps per byte plus 2^20 is refused:
	## a roc-font limit (OTS has none), more than 30 times what any font of
	## the 1,278-font conformance corpus needs (under 2 steps per byte).
	##
	## A problem gives the offset in the table of the structure that is
	## wrong.
	ots_check : List(U8), U64, [Present(U64), Absent] -> Try({}, [Bad(U64)])
	ots_check = |data, glyphs, sets| {
		size = data.len()
		major = LayoutGsub.u16(data, 0)
		minor = LayoutGsub.u16(data, 2)
		# layout.cc 1656-1672: version 1.0 (10-byte header) or 1.1 (14).
		if !LayoutGsub.fits(0, 10, size) or major != 1 or minor > 1 or (minor == 1 and !LayoutGsub.fits(0, 14, size)) {
			return Err(Bad(0))
		}
		header = if (minor == 0) 10 else 14
		script_list = LayoutGsub.u16(data, 4)
		feature_list = LayoutGsub.u16(data, 6)
		lookup_list = LayoutGsub.u16(data, 8)
		base = { data, glyphs, lookups: 0, sets, budget: 64 * size + 1048576 }
		# Each list may be absent; one present lies past the header and
		# inside the table (1677-1708). Lookups first, whose count features
		# use, then features, whose count language systems use.
		if lookup_list != 0 and (lookup_list < header or lookup_list >= size) {
			return Err(Bad(8))
		}
		if feature_list != 0 and (feature_list < header or feature_list >= size) {
			return Err(Bad(6))
		}
		if script_list != 0 and (script_list < header or script_list >= size) {
			return Err(Bad(4))
		}
		lookups = if (lookup_list != 0 and LayoutGsub.fits(lookup_list, 2, size)) LayoutGsub.u16(data, lookup_list) else 0
		ctx = { ..base, lookups }
		after_lookups = if (lookup_list != 0) LayoutGsub.ots_lookup_list(ctx, lookup_list, 0)? else 0
		features = if (feature_list != 0) LayoutGsub.ots_feature_list(ctx, feature_list, after_lookups)? else { count: 0, steps: after_lookups }
		if script_list != 0 {
			LayoutGsub.ots_script_list(ctx, script_list, features.count, features.steps).map_ok(|_| {})
		} else {
			Ok({})
		}
	}

	ots_spend : OtsContext, U64, U64, U64 -> Try(U64, [Bad(U64)])
	ots_spend = |ctx, steps, cost, at| {
		total = steps + cost + 1
		if (total > ctx.budget) Err(Bad(at)) else Ok(total)
	}

	# The offsets of a list: `count` 16-bit offsets at `at`, from `base`,
	# each at least `end` and inside the table (OTS's recurring check).
	ots_offsets : OtsContext, U64, U64, U64, U64 -> Try({}, [Bad(U64)])
	ots_offsets = |ctx, base, at, count, end| {
		size = ctx.data.len()
		if !LayoutGsub.fits(at, 2 * count, size) {
			return Err(Bad(base))
		}
		for i in 0..<count {
			o = LayoutGsub.u16(ctx.data, at + 2 * i)
			if o < end or base + o >= size {
				return Err(Bad(at + 2 * i))
			}
		}
		Ok({})
	}

	# `count` 16-bit glyph ids at `at`, each inside the table and below the
	# glyph count; `table` is reported.
	ots_glyphs : OtsContext, U64, U64, U64 -> Try({}, [Bad(U64)])
	ots_glyphs = |ctx, table, at, count| {
		if !LayoutGsub.fits(at, 2 * count, ctx.data.len()) {
			return Err(Bad(table))
		}
		for i in 0..<count {
			if LayoutGsub.u16(ctx.data, at + 2 * i) >= ctx.glyphs {
				return Err(Bad(at + 2 * i))
			}
		}
		Ok({})
	}

	# layout.cc 1364-1400 (`ParseLookupListTable`): the lookup offsets,
	# then every lookup.
	ots_lookup_list : OtsContext, U64, U64 -> Try(U64, [Bad(U64)])
	ots_lookup_list = |ctx, at, steps| {
		count = ctx.lookups
		if !LayoutGsub.fits(at, 2, ctx.data.len()) or 2 * count + 2 > 65535 {
			return Err(Bad(at))
		}
		LayoutGsub.ots_offsets(ctx, at, at + 2, count, 2 * count + 2)?
		var $steps = LayoutGsub.ots_spend(ctx, steps, count, at)?
		for i in 0..<count {
			$steps = LayoutGsub.ots_lookup(ctx, at + LayoutGsub.u16(ctx.data, at + 2 + 2 * i), $steps)?
		}
		Ok($steps)
	}

	# layout.cc 1292-1359 (`ParseLookupTable`): a lookup type 1 to 8, its
	# subtable offsets, a mark filtering set the font's `GDEF` has (when it
	# has a `GDEF`), then every subtable.
	ots_lookup : OtsContext, U64, U64 -> Try(U64, [Bad(U64)])
	ots_lookup = |ctx, at, steps| {
		data = ctx.data
		kind = LayoutGsub.u16(data, at)
		flag = LayoutGsub.u16(data, at + 2)
		count = LayoutGsub.u16(data, at + 4)
		filtering = flag.bitwise_and(0x10) != 0
		end = 2 * count + (if (filtering) 8 else 6)
		if !LayoutGsub.fits(at, 6, data.len()) or kind < 1 or kind > 8 or end > 65535 {
			return Err(Bad(at))
		}
		LayoutGsub.ots_offsets(ctx, at, at + 6, count, end)?
		if filtering {
			set_at = at + 6 + 2 * count
			if !LayoutGsub.fits(set_at, 2, data.len()) {
				return Err(Bad(at))
			}
			match ctx.sets {
				Present(sets) if sets == 0 or LayoutGsub.u16(data, set_at) >= sets => return Err(Bad(set_at))
				_ => {}
			}
		}
		var $steps = LayoutGsub.ots_spend(ctx, steps, count, at)?
		for i in 0..<count {
			$steps = LayoutGsub.ots_subtable(ctx, kind, at + LayoutGsub.u16(data, at + 6 + 2 * i), $steps)?
		}
		Ok($steps)
	}

	# gsub.cc 502-523 (`ParseLookupSubtable`): one subtable of a lookup type.
	ots_subtable : OtsContext, U64, U64, U64 -> Try(U64, [Bad(U64)])
	ots_subtable = |ctx, kind, at, steps| {
		data = ctx.data
		size = data.len()
		after = LayoutGsub.ots_spend(ctx, steps, 0, at)?
		format = LayoutGsub.u16(data, at)
		coverage = LayoutGsub.u16(data, at + 2)
		if kind == 1 {
			# gsub.cc 145-204: format 1, a delta smaller than the glyph count;
			# format 2, substitutes below it; then the coverage.
			if !LayoutGsub.fits(at, 6, size) {
				return Err(Bad(at))
			}
			end =
				if format == 1 {
					delta = LayoutGsub.u16(data, at + 4)
					magnitude = if (delta >= 32768) 65536 - delta else delta
					if magnitude >= ctx.glyphs {
						return Err(Bad(at + 4))
					}
					6
				} else if format == 2 {
					count = LayoutGsub.u16(data, at + 4)
					if count > ctx.glyphs {
						return Err(Bad(at + 4))
					}
					LayoutGsub.ots_glyphs(ctx, at, at + 6, count)?
					6 + 2 * count
				} else {
					return Err(Bad(at))
				}
			LayoutGsub.ots_coverage_at(ctx, at, coverage, end, LayoutGsub.ots_spend(ctx, after, (end - 6) // 2, at)?)
		} else if kind == 2 or kind == 3 or kind == 4 {
			# gsub.cc 208-378: format 1; sequences and alternate sets of
			# glyphs below the glyph count, or ligature sets; then the
			# coverage.
			count = LayoutGsub.u16(data, at + 4)
			end = 6 + 2 * count
			if !LayoutGsub.fits(at, 6, size) or format != 1 or end > 65535 {
				return Err(Bad(at))
			}
			LayoutGsub.ots_offsets(ctx, at, at + 6, count, end)?
			var $steps = LayoutGsub.ots_spend(ctx, after, count, at)?
			for i in 0..<count {
				set = at + LayoutGsub.u16(data, at + 6 + 2 * i)
				n = LayoutGsub.u16(data, set)
				if !LayoutGsub.fits(set, 2, size) {
					return Err(Bad(set))
				}
				$steps = LayoutGsub.ots_spend(ctx, $steps, n, set)?
				if kind == 4 {
					# gsub.cc 107-137 and 75-105: ligatures of a glyph below the
					# glyph count and at least one component, each below it.
					if 2 + 2 * n > 65535 {
						return Err(Bad(set))
					}
					LayoutGsub.ots_offsets(ctx, set, set + 2, n, 2 + 2 * n)?
					for l in 0..<n {
						lig = set + LayoutGsub.u16(data, set + 2 + 2 * l)
						components = LayoutGsub.u16(data, lig + 2)
						if !LayoutGsub.fits(lig, 4, size) or LayoutGsub.u16(data, lig) >= ctx.glyphs or components == 0 {
							return Err(Bad(lig))
						}
						LayoutGsub.ots_glyphs(ctx, lig, lig + 4, components - 1)?
						$steps = LayoutGsub.ots_spend(ctx, $steps, components, lig)?
					}
				} else {
					# gsub.cc 32-73: glyphs below the glyph count.
					LayoutGsub.ots_glyphs(ctx, set, set + 2, n)?
				}
			}
			LayoutGsub.ots_coverage_at(ctx, at, coverage, end, $steps)
		} else if kind == 5 {
			LayoutGsub.ots_context(ctx, format, at, after)
		} else if kind == 6 {
			LayoutGsub.ots_chain(ctx, format, at, after)
		} else if kind == 7 {
			# layout.cc 1546-1580: format 1 pointing at a subtable of another
			# valid type, past the 8-byte header and inside the table.
			real = LayoutGsub.u16(data, at + 2)
			offset = LayoutGsub.u32(data, at + 4)
			if !LayoutGsub.fits(at, 8, size) or format != 1 or real < 1 or real > 8 or real == 7 or offset < 8 or at + offset >= size {
				return Err(Bad(at))
			}
			LayoutGsub.ots_subtable(ctx, real, at + offset, after)
		} else {
			# gsub.cc 394-493: backtrack and lookahead coverages, substitutes
			# below the glyph count, then the coverages. OTS does not check
			# the format.
			if !LayoutGsub.fits(at, 6, size) {
				return Err(Bad(at))
			}
			back = LayoutGsub.u16(data, at + 4)
			ahead_at = at + 6 + 2 * back
			if !LayoutGsub.fits(ahead_at, 2, size) {
				return Err(Bad(at))
			}
			ahead = LayoutGsub.u16(data, ahead_at)
			glyphs_at = ahead_at + 2 + 2 * ahead
			if !LayoutGsub.fits(glyphs_at, 2, size) {
				return Err(Bad(at))
			}
			count = LayoutGsub.u16(data, glyphs_at)
			LayoutGsub.ots_glyphs(ctx, at, glyphs_at + 2, count)?
			end = 10 + 2 * (back + ahead + count)
			if end > 65535 {
				return Err(Bad(at))
			}
			var $steps = LayoutGsub.ots_coverage_at(ctx, at, coverage, end, LayoutGsub.ots_spend(ctx, after, back + ahead + count, at)?)?
			for i in 0..<back {
				$steps = LayoutGsub.ots_coverage_at(ctx, at, LayoutGsub.u16(data, at + 6 + 2 * i), end, $steps)?
			}
			for i in 0..<ahead {
				$steps = LayoutGsub.ots_coverage_at(ctx, at, LayoutGsub.u16(data, ahead_at + 2 + 2 * i), end, $steps)?
			}
			Ok($steps)
		}
	}

	# A coverage at `offset` from `base`: at least `end` and inside the
	# table, then checked.
	ots_coverage_at : OtsContext, U64, U64, U64, U64 -> Try(U64, [Bad(U64)])
	ots_coverage_at = |ctx, base, offset, end, steps|
		if offset < end or base + offset >= ctx.data.len() {
			Err(Bad(base))
		} else {
			LayoutGsub.ots_coverage(ctx, base + offset, steps)
		}

	# layout.cc 1421-1438, 261-346 (`ParseCoverageTable`): format 1, at most
	# as many glyphs as the font has, each below the glyph count; format 2,
	# at most that many ranges, each in order (a range may start on the
	# previous range's end) and starting at the coverage index the previous
	# ranges reach (counted in 16 bits, as OTS counts).
	ots_coverage : OtsContext, U64, U64 -> Try(U64, [Bad(U64)])
	ots_coverage = |ctx, at, steps| {
		data = ctx.data
		format = LayoutGsub.u16(data, at)
		count = LayoutGsub.u16(data, at + 2)
		if !LayoutGsub.fits(at, 4, data.len()) or (format != 1 and format != 2) or count > ctx.glyphs {
			return Err(Bad(at))
		}
		after = LayoutGsub.ots_spend(ctx, steps, count, at)?
		if format == 1 {
			LayoutGsub.ots_glyphs(ctx, at, at + 4, count)?
		} else {
			if !LayoutGsub.fits(at + 4, 6 * count, data.len()) {
				return Err(Bad(at))
			}
			var $last_end = 0
			var $index = 0
			for i in 0..<count {
				r = at + 4 + 6 * i
				first = LayoutGsub.u16(data, r)
				last = LayoutGsub.u16(data, r + 2)
				if first > last or ($last_end != 0 and first < $last_end) or LayoutGsub.u16(data, r + 4) != $index {
					return Err(Bad(r))
				}
				$last_end = last
				$index = ($index + last - first + 1) % 65536
			}
		}
		Ok(after)
	}

	# layout.cc 1402-1419, 178-259 (`ParseClassDefTable`): format 1, a start
	# glyph below the glyph count and at most that many classes; format 2,
	# at most that many ranges, each in order and not overlapping the
	# previous one. Class values are not limited in `GSUB`.
	ots_classes_at : OtsContext, U64, U64, U64, U64 -> Try(U64, [Bad(U64)])
	ots_classes_at = |ctx, base, offset, end, steps| {
		data = ctx.data
		size = data.len()
		if offset < end or base + offset >= size {
			return Err(Bad(base))
		}
		at = base + offset
		format = LayoutGsub.u16(data, at)
		if format == 1 {
			first = LayoutGsub.u16(data, at + 2)
			count = LayoutGsub.u16(data, at + 4)
			if !LayoutGsub.fits(at, 6, size) or first >= ctx.glyphs or count > ctx.glyphs or !LayoutGsub.fits(at + 6, 2 * count, size) {
				return Err(Bad(at))
			}
			LayoutGsub.ots_spend(ctx, steps, count, at)
		} else if format == 2 {
			count = LayoutGsub.u16(data, at + 2)
			if !LayoutGsub.fits(at, 4, size) or count > ctx.glyphs or !LayoutGsub.fits(at + 4, 6 * count, size) {
				return Err(Bad(at))
			}
			var $last_end = 0
			for i in 0..<count {
				r = at + 4 + 6 * i
				first = LayoutGsub.u16(data, r)
				last = LayoutGsub.u16(data, r + 2)
				if first > last or ($last_end != 0 and first <= $last_end) {
					return Err(Bad(r))
				}
				$last_end = last
			}
			LayoutGsub.ots_spend(ctx, steps, count, at)
		} else {
			Err(Bad(at))
		}
	}

	# layout.cc 350-366 (`ParseLookupRecord`): `count` records at `at`, each
	# a sequence index below the font's glyph count (as OTS compares it)
	# and a lookup index below the lookup count.
	ots_records : OtsContext, U64, U64, U64, U64 -> Try(U64, [Bad(U64)])
	ots_records = |ctx, table, at, count, steps| {
		if !LayoutGsub.fits(at, 4 * count, ctx.data.len()) {
			return Err(Bad(table))
		}
		for i in 0..<count {
			r = at + 4 * i
			if LayoutGsub.u16(ctx.data, r) >= ctx.glyphs or LayoutGsub.u16(ctx.data, r + 2) >= ctx.lookups {
				return Err(Bad(r))
			}
		}
		LayoutGsub.ots_spend(ctx, steps, count, at)
	}

	# The rule sets of a contextual subtable: `count` offsets at `at` from
	# `base`, each at least `end` (absent sets allowed when `nullable`),
	# each set's rules checked by `rule`.
	ots_rule_sets : OtsContext, U64, U64, U64, U64, Bool, U64, (OtsContext, U64, U64 -> Try(U64, [Bad(U64)])) -> Try(U64, [Bad(U64)])
	ots_rule_sets = |ctx, base, at, count, end, nullable, steps, rule| {
		data = ctx.data
		size = data.len()
		if !LayoutGsub.fits(at, 2 * count, size) {
			return Err(Bad(base))
		}
		var $steps = LayoutGsub.ots_spend(ctx, steps, count, base)?
		for i in 0..<count {
			o = LayoutGsub.u16(data, at + 2 * i)
			if !(nullable and o == 0) {
				if o < end or base + o >= size {
					return Err(Bad(at + 2 * i))
				}
				# A rule set (layout.cc 402-432 and its kin): rule offsets past
				# the count and the offsets, inside the table.
				set = base + o
				rules = LayoutGsub.u16(data, set)
				if !LayoutGsub.fits(set, 2, size) or 2 * rules + 2 > 65535 {
					return Err(Bad(set))
				}
				LayoutGsub.ots_offsets(ctx, set, set + 2, rules, 2 * rules + 2)?
				$steps = LayoutGsub.ots_spend(ctx, $steps, rules, set)?
				for r in 0..<rules {
					$steps = rule(ctx, set + LayoutGsub.u16(data, set + 2 + 2 * r), $steps)?
				}
			}
		}
		Ok($steps)
	}

	# layout.cc 1476-1509 (`ParseContextSubtable`) with formats 1 (434-477),
	# 2 (544-600) and 3 (602-643).
	ots_context : OtsContext, U64, U64, U64 -> Try(U64, [Bad(U64)])
	ots_context = |ctx, format, at, steps| {
		data = ctx.data
		size = data.len()
		if format == 1 {
			count = LayoutGsub.u16(data, at + 4)
			end = 6 + 2 * count
			if !LayoutGsub.fits(at, 6, size) or end > 65535 {
				return Err(Bad(at))
			}
			after = LayoutGsub.ots_coverage_at(ctx, at, LayoutGsub.u16(data, at + 2), end, steps)?
			LayoutGsub.ots_rule_sets(ctx, at, at + 6, count, end, False, after, LayoutGsub.ots_rule)
		} else if format == 2 {
			count = LayoutGsub.u16(data, at + 6)
			end = 8 + 2 * count
			if !LayoutGsub.fits(at, 8, size) or end > 65535 {
				return Err(Bad(at))
			}
			with_coverage = LayoutGsub.ots_coverage_at(ctx, at, LayoutGsub.u16(data, at + 2), end, steps)?
			classed = LayoutGsub.ots_classes_at(ctx, at, LayoutGsub.u16(data, at + 4), end, with_coverage)?
			LayoutGsub.ots_rule_sets(ctx, at, at + 8, count, end, True, classed, LayoutGsub.ots_class_rule)
		} else if format == 3 {
			count = LayoutGsub.u16(data, at + 2)
			records = LayoutGsub.u16(data, at + 4)
			end = 2 * count + 4 * records + 6
			if !LayoutGsub.fits(at, 6, size) or end > 65535 or !LayoutGsub.fits(at + 6, 2 * count, size) {
				return Err(Bad(at))
			}
			var $steps = steps
			for i in 0..<count {
				$steps = LayoutGsub.ots_coverage_at(ctx, at, LayoutGsub.u16(data, at + 6 + 2 * i), end, $steps)?
			}
			LayoutGsub.ots_records(ctx, at, at + 6 + 2 * count, records, $steps)
		} else {
			Err(Bad(at))
		}
	}

	# layout.cc 368-400 (`ParseRuleSubtable`): at least one input glyph,
	# those after the first below the glyph count, then lookup records.
	ots_rule : OtsContext, U64, U64 -> Try(U64, [Bad(U64)])
	ots_rule = |ctx, at, steps| {
		count = LayoutGsub.u16(ctx.data, at)
		if !LayoutGsub.fits(at, 4, ctx.data.len()) or count == 0 {
			return Err(Bad(at))
		}
		LayoutGsub.ots_glyphs(ctx, at, at + 4, count - 1)?
		LayoutGsub.ots_records(ctx, at, at + 4 + 2 * (count - 1), LayoutGsub.u16(ctx.data, at + 2), LayoutGsub.ots_spend(ctx, steps, count, at)?)
	}

	# layout.cc 479-509 (`ParseClassRuleTable`): at least one input class
	# (classes are not checked), then lookup records.
	ots_class_rule : OtsContext, U64, U64 -> Try(U64, [Bad(U64)])
	ots_class_rule = |ctx, at, steps| {
		count = LayoutGsub.u16(ctx.data, at)
		if !LayoutGsub.fits(at, 4, ctx.data.len()) or count == 0 or !LayoutGsub.fits(at + 4, 2 * (count - 1), ctx.data.len()) {
			return Err(Bad(at))
		}
		LayoutGsub.ots_records(ctx, at, at + 4 + 2 * (count - 1), LayoutGsub.u16(ctx.data, at + 2), LayoutGsub.ots_spend(ctx, steps, count, at)?)
	}

	# layout.cc 1511-1544 (`ParseChainingContextSubtable`) with formats 1
	# (744-789), 2 (874-963) and 3 (965-1074).
	ots_chain : OtsContext, U64, U64, U64 -> Try(U64, [Bad(U64)])
	ots_chain = |ctx, format, at, steps| {
		data = ctx.data
		size = data.len()
		if format == 1 {
			count = LayoutGsub.u16(data, at + 4)
			end = 6 + 2 * count
			if !LayoutGsub.fits(at, 6, size) or end > 65535 {
				return Err(Bad(at))
			}
			after = LayoutGsub.ots_coverage_at(ctx, at, LayoutGsub.u16(data, at + 2), end, steps)?
			LayoutGsub.ots_rule_sets(ctx, at, at + 6, count, end, False, after, LayoutGsub.ots_chain_rule)
		} else if format == 2 {
			count = LayoutGsub.u16(data, at + 10)
			end = 12 + 2 * count
			if !LayoutGsub.fits(at, 12, size) or end > 65535 {
				return Err(Bad(at))
			}
			var $steps = LayoutGsub.ots_coverage_at(ctx, at, LayoutGsub.u16(data, at + 2), end, steps)?
			# Backtrack and lookahead classes may be absent; input classes
			# may not.
			back = LayoutGsub.u16(data, at + 4)
			if back != 0 {
				$steps = LayoutGsub.ots_classes_at(ctx, at, back, end, $steps)?
			}
			$steps = LayoutGsub.ots_classes_at(ctx, at, LayoutGsub.u16(data, at + 6), end, $steps)?
			ahead = LayoutGsub.u16(data, at + 8)
			if ahead != 0 {
				$steps = LayoutGsub.ots_classes_at(ctx, at, ahead, end, $steps)?
			}
			LayoutGsub.ots_rule_sets(ctx, at, at + 12, count, end, True, $steps, LayoutGsub.ots_chain_class_rule)
		} else if format == 3 {
			# The offsets and lookup records first, then the coverages, each
			# past all of them.
			back = LayoutGsub.u16(data, at + 2)
			input_at = at + 4 + 2 * back
			input = LayoutGsub.u16(data, input_at)
			ahead_at = input_at + 2 + 2 * input
			ahead = LayoutGsub.u16(data, ahead_at)
			records_at = ahead_at + 2 + 2 * ahead
			records = LayoutGsub.u16(data, records_at)
			if !LayoutGsub.fits(at, 4, size) or !LayoutGsub.fits(input_at, 2, size) or !LayoutGsub.fits(ahead_at, 2, size) or !LayoutGsub.fits(records_at, 2, size) {
				return Err(Bad(at))
			}
			after = LayoutGsub.ots_records(ctx, at, records_at + 2, records, steps)?
			end = 2 * (back + input + ahead) + 4 * records + 10
			if end > 65535 {
				return Err(Bad(at))
			}
			var $steps = after
			for i in 0..<back {
				$steps = LayoutGsub.ots_coverage_at(ctx, at, LayoutGsub.u16(data, at + 4 + 2 * i), end, $steps)?
			}
			for i in 0..<input {
				$steps = LayoutGsub.ots_coverage_at(ctx, at, LayoutGsub.u16(data, input_at + 2 + 2 * i), end, $steps)?
			}
			for i in 0..<ahead {
				$steps = LayoutGsub.ots_coverage_at(ctx, at, LayoutGsub.u16(data, ahead_at + 2 + 2 * i), end, $steps)?
			}
			Ok($steps)
		} else {
			Err(Bad(at))
		}
	}

	# layout.cc 647-709 (`ParseChainRuleSubtable`): backtrack glyphs, at
	# least one input glyph and lookahead glyphs, all below the glyph count,
	# then lookup records.
	ots_chain_rule : OtsContext, U64, U64 -> Try(U64, [Bad(U64)])
	ots_chain_rule = |ctx, at, steps| {
		data = ctx.data
		size = data.len()
		back = LayoutGsub.u16(data, at)
		if !LayoutGsub.fits(at, 2, size) {
			return Err(Bad(at))
		}
		LayoutGsub.ots_glyphs(ctx, at, at + 2, back)?
		input_at = at + 2 + 2 * back
		input = LayoutGsub.u16(data, input_at)
		if !LayoutGsub.fits(input_at, 2, size) or input == 0 {
			return Err(Bad(at))
		}
		LayoutGsub.ots_glyphs(ctx, at, input_at + 2, input - 1)?
		ahead_at = input_at + 2 * input
		ahead = LayoutGsub.u16(data, ahead_at)
		if !LayoutGsub.fits(ahead_at, 2, size) {
			return Err(Bad(at))
		}
		LayoutGsub.ots_glyphs(ctx, at, ahead_at + 2, ahead)?
		records_at = ahead_at + 2 + 2 * ahead
		if !LayoutGsub.fits(records_at, 2, size) {
			return Err(Bad(at))
		}
		LayoutGsub.ots_records(ctx, at, records_at + 2, LayoutGsub.u16(data, records_at), LayoutGsub.ots_spend(ctx, steps, back + input + ahead, at)?)
	}

	# layout.cc 791-838 (`ParseChainClassRuleSubtable`): backtrack classes,
	# at least one input class and lookahead classes (not checked), then
	# lookup records.
	ots_chain_class_rule : OtsContext, U64, U64 -> Try(U64, [Bad(U64)])
	ots_chain_class_rule = |ctx, at, steps| {
		data = ctx.data
		size = data.len()
		back = LayoutGsub.u16(data, at)
		input_at = at + 2 + 2 * back
		input = LayoutGsub.u16(data, input_at)
		if !LayoutGsub.fits(at, 2, size) or !LayoutGsub.fits(input_at, 2, size) or input == 0 {
			return Err(Bad(at))
		}
		ahead_at = input_at + 2 * input
		ahead = LayoutGsub.u16(data, ahead_at)
		records_at = ahead_at + 2 + 2 * ahead
		if !LayoutGsub.fits(ahead_at, 2, size) or !LayoutGsub.fits(records_at, 2, size) {
			return Err(Bad(at))
		}
		LayoutGsub.ots_records(ctx, at, records_at + 2, LayoutGsub.u16(data, records_at), LayoutGsub.ots_spend(ctx, steps, back + input + ahead, at)?)
	}

	# layout.cc 1246-1290 (`ParseFeatureListTable`) and 141-176
	# (`ParseFeatureTable`): feature offsets past the records, inside the
	# table; each feature's parameters (when present) past its lookup
	# indices, and each lookup index below the lookup count.
	ots_feature_list : OtsContext, U64, U64 -> Try({ count : U64, steps : U64 }, [Bad(U64)])
	ots_feature_list = |ctx, at, steps| {
		data = ctx.data
		size = data.len()
		count = LayoutGsub.u16(data, at)
		end = 6 * count + 2
		if !LayoutGsub.fits(at, 2, size) or end > 65535 or !LayoutGsub.fits(at + 2, 6 * count, size) {
			return Err(Bad(at))
		}
		for i in 0..<count {
			o = LayoutGsub.u16(data, at + 2 + 6 * i + 4)
			if o < end or at + o >= size {
				return Err(Bad(at + 2 + 6 * i))
			}
		}
		var $steps = LayoutGsub.ots_spend(ctx, steps, count, at)?
		for i in 0..<count {
			feature = at + LayoutGsub.u16(data, at + 2 + 6 * i + 4)
			params = LayoutGsub.u16(data, feature)
			lookups = LayoutGsub.u16(data, feature + 2)
			feature_end = 2 * lookups + 4
			if !LayoutGsub.fits(feature, 4, size) or feature_end > 65535 or (params != 0 and (params < feature_end or feature + params >= size)) or !LayoutGsub.fits(feature + 4, 2 * lookups, size) {
				return Err(Bad(feature))
			}
			for k in 0..<lookups {
				if LayoutGsub.u16(data, feature + 4 + 2 * k) >= ctx.lookups {
					return Err(Bad(feature + 4 + 2 * k))
				}
			}
			$steps = LayoutGsub.ots_spend(ctx, $steps, lookups, feature)?
		}
		Ok({ count, steps: $steps })
	}

	# layout.cc 1192-1242 (`ParseScriptListTable`), 83-139
	# (`ParseScriptTable`) and 48-81 (`ParseLangSysTable`): script offsets
	# past the records, inside the table; a `DFLT` script with a default
	# language system; language system records in tag order, past the
	# records and inside the table; and each language system's reserved
	# lookup order 0, its required feature (if any) and feature indices
	# below the feature count, and no more indices than features. OTS does
	# not check the default language system table itself.
	ots_script_list : OtsContext, U64, U64, U64 -> Try(U64, [Bad(U64)])
	ots_script_list = |ctx, at, features, steps| {
		data = ctx.data
		size = data.len()
		count = LayoutGsub.u16(data, at)
		end = 6 * count + 2
		if !LayoutGsub.fits(at, 2, size) or end > 65535 or !LayoutGsub.fits(at + 2, 6 * count, size) {
			return Err(Bad(at))
		}
		for i in 0..<count {
			o = LayoutGsub.u16(data, at + 2 + 6 * i + 4)
			if o < end or at + o >= size {
				return Err(Bad(at + 2 + 6 * i))
			}
		}
		var $steps = LayoutGsub.ots_spend(ctx, steps, count, at)?
		for i in 0..<count {
			script = at + LayoutGsub.u16(data, at + 2 + 6 * i + 4)
			script_tag = LayoutGsub.u32(data, at + 2 + 6 * i)
			langs = LayoutGsub.u16(data, script + 2)
			langs_end = 6 * langs + 4
			if !LayoutGsub.fits(script, 4, size) or (script_tag == 0x44464C54 and LayoutGsub.u16(data, script) == 0) or langs_end > 65535 or !LayoutGsub.fits(script + 4, 6 * langs, size) {
				return Err(Bad(script))
			}
			var $last_tag = 0
			for l in 0..<langs {
				rec = script + 4 + 6 * l
				lang_tag = LayoutGsub.u32(data, rec)
				o = LayoutGsub.u16(data, rec + 4)
				if ($last_tag != 0 and $last_tag > lang_tag) or o < langs_end or script + o >= size {
					return Err(Bad(rec))
				}
				$last_tag = lang_tag
			}
			$steps = LayoutGsub.ots_spend(ctx, $steps, langs, script)?
			for l in 0..<langs {
				lang = script + LayoutGsub.u16(data, script + 4 + 6 * l + 4)
				required = LayoutGsub.u16(data, lang + 2)
				indices = LayoutGsub.u16(data, lang + 4)
				if !LayoutGsub.fits(lang, 6, size) or LayoutGsub.u16(data, lang) != 0 or (required != 0xFFFF and required >= features) or indices > features or !LayoutGsub.fits(lang + 6, 2 * indices, size) {
					return Err(Bad(lang))
				}
				for k in 0..<indices {
					if LayoutGsub.u16(data, lang + 6 + 2 * k) >= features {
						return Err(Bad(lang + 6 + 2 * k))
					}
				}
				$steps = LayoutGsub.ots_spend(ctx, $steps, indices, lang)?
			}
		}
		Ok($steps)
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
			} else if kind == 8 and format != 1 {
				# OTS does not check the format (gsub.cc 394-493); HarfBuzz
				# applies only format 1, so another never applies.
				Ok({ subtables: subtables.append({ ..LayoutGsub.no_sub, kind: 8, coverage: ranges.len(), coverage_len: 0, data: values.len(), data_len: 0, match_kind: 2, back: values.len(), ahead: values.len() }), ranges, values, rules, steps })
			} else if kind == 8 {
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
					# OTS accepts a rule with no input (layout.cc 991-1006);
					# with no first coverage it never applies, as in HarfBuzz.
					LayoutGsub.inert_context(1, { subtables, ranges: ahead.ranges, values: records.values, rules, steps: records.steps })
				} else {
					rule = { back: back.start, back_len: back.count, input: input.start + 2, input_len: input.count - 1, ahead: ahead.start, ahead_len: ahead.count, records: records.start, records_len: records.count }
					LayoutGsub.context3_of(input.start, rule, 1, { subtables, ranges: ahead.ranges, values: records.values, rules, steps: records.steps })
				}
			} else {
				count = LayoutGsub.u16(data, at + 2)
				record_count = LayoutGsub.u16(data, at + 4)
				if !LayoutGsub.fits(at, 6 + 2 * count, data.len()) {
					Err(Bad(at))
				} else if count == 0 {
					# OTS accepts a rule with no input (layout.cc 602-643); with
					# no first coverage it never applies, as in HarfBuzz.
					LayoutGsub.inert_context(0, { subtables, ranges, values, rules, steps })
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

	# A context subtable that never applies: no coverage and no rule sets.
	# `chained` is 1 for a chained subtable.
	inert_context : I64, Built -> Try(Built, [Bad(U64)])
	inert_context = |chained, { subtables, ranges, values, rules, steps }| {
		sub = { ..LayoutGsub.no_sub, kind: 5, coverage: ranges.len(), coverage_len: 0, delta: chained, data: values.len(), data_len: 0, match_kind: 2 }
		Ok({ subtables: subtables.append(sub), ranges, values: values.append(rules.len()), rules, steps })
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

# ----------------------------------------------------------------------

# Tests of what `Font` never lets reach this module. The behaviour
# callers see is tested through the public API in `tests/api/`. Top-level
# expects and helpers are not part of the module's API. Run with
# `roc test package/LayoutGsub.roc`.

# A table too short for its header is refused by the reader itself; `Font`
# refuses such a table before reading it, so only a direct call reaches
# this check.
expect LayoutGsub.read([]).is_err()
expect LayoutGsub.read(List.repeat(0, 9)).is_err()

# ------------------------------------------------------------ ligature sets

# A big-endian 16-bit value.
be16 : U64 -> List(U8)
be16 = |v| [v.shr_zf_wrap(8).to_u8_wrap(), v.to_u8_wrap()]

# A `GSUB` with one `liga` lookup (lookup flag `flag`) of one ligature
# subtable for glyph 10, whose set holds, in order: 10 12 -> 100, 10 11 11
# -> 101, 10 11 -> 102 and 10 -> 103.
liga_gsub : U64 -> List(U8)
liga_gsub = |flag| {
	ligatures : List(List(U64))
	ligatures = [[100, 12], [101, 11, 11], [102, 11], [103]]
	# Ligature tables after the set's count and offsets.
	set_head = 2 + 2 * ligatures.len()
	{ offsets, tables } = ligatures.fold(
		{ offsets: [], tables: [] },
		|acc, lig| {
			at = set_head + acc.tables.len()
			table = be16(lig.first() ?? 0).concat(be16(lig.len())).concat(lig.drop_first(1).fold([], |b, g| b.concat(be16(g))))
			{ offsets: acc.offsets.concat(be16(at)), tables: acc.tables.concat(table) }
		},
	)
	set = be16(ligatures.len()).concat(offsets).concat(tables)
	# Format 1, coverage at 8, one set at 14; coverage of glyph 10.
	subtable = be16(1).concat(be16(8)).concat(be16(1)).concat(be16(14)).concat(be16(1)).concat(be16(1)).concat(be16(10)).concat(set)
	lookup = be16(4).concat(be16(flag)).concat(be16(1)).concat(be16(8)).concat(subtable)
	# Header, empty script list at 10, feature list at 12 (`liga` at 20),
	# lookup list at 26 (the lookup at 30).
	[0, 1, 0, 0].concat(be16(10)).concat(be16(12)).concat(be16(26))
		.concat(be16(0))
		.concat(be16(1)).concat(['l', 'i', 'g', 'a']).concat(be16(8)).concat(be16(0)).concat(be16(1)).concat(be16(0))
		.concat(be16(1)).concat(be16(4))
		.concat(lookup)
}

zwj_props : U64
zwj_props = ShaperUnicode.props(0x200D)

# A mark, by its glyph properties.
mark_props : U64
mark_props = LayoutGsub.mark.shl_wrap(16)

# Glyphs and clusters after applying the lookup to glyphs given with their
# property words, one cluster each.
ligated : U64, Bool, List({ glyph : U64, props : U64 }) -> { glyphs : List(U64), clusters : List(U64) }
ligated = |flag, auto_zwj, input| match LayoutGsub.read(liga_gsub(flag)) {
	Ok(gsub) => {
		items = input.map_with_index(|g, i| { glyph: g.glyph, cluster: i, mask: 1, props: g.props })
		plan = [{ index: 0, mask: 1, auto_zwnj: True, auto_zwj, random: False }]
		applied = LayoutGsub.apply(gsub, plan, items, { limit: 64, budget: 64, depth: 8 })
		{ glyphs: applied.items.map(|item| item.glyph), clusters: applied.items.map(|item| item.cluster) }
	}
	Err(_) => { glyphs: [], clusters: [] }
}

letters : List(U64) -> List({ glyph : U64, props : U64 })
letters = |glyphs| glyphs.map(|glyph| { glyph, props: ShaperUnicode.lowercase_letter })

# The first ligature of the set whose components follow, ligatures whose
# second component is another glyph passed over, clusters merged.
expect ligated(0, True, letters([10, 11])) == { glyphs: [102], clusters: [0] }
expect ligated(0, True, letters([10, 11, 11])) == { glyphs: [101], clusters: [0] }
expect ligated(0, True, letters([10, 12, 11])) == { glyphs: [100, 11], clusters: [0, 2] }
expect ligated(0, True, letters([10, 11, 10, 12])) == { glyphs: [102, 100], clusters: [0, 2] }

# At the end of the run, or before a glyph no ligature continues with, only
# the one-glyph ligature applies.
expect ligated(0, True, letters([10])) == { glyphs: [103], clusters: [0] }
expect ligated(0, True, letters([11, 10])) == { glyphs: [11, 103], clusters: [0, 1] }
expect ligated(0, True, letters([10, 13])) == { glyphs: [103, 13], clusters: [0, 1] }

# A mark the lookup flag ignores is passed over, and stays after the
# ligature; a mark it does not ignore stops the match.
expect ligated(0x08, True, [{ glyph: 10, props: 0 }, { glyph: 30, props: mark_props }, { glyph: 11, props: 0 }]).glyphs == [102, 30]
expect ligated(0x08, True, [{ glyph: 10, props: 0 }, { glyph: 30, props: mark_props }, { glyph: 30, props: mark_props }, { glyph: 11, props: 0 }, { glyph: 11, props: 0 }]).glyphs == [101, 30, 30]
expect ligated(0, True, [{ glyph: 10, props: 0 }, { glyph: 30, props: mark_props }, { glyph: 11, props: 0 }]).glyphs == [103, 30, 11]

# A ZWJ between components is skipped when the feature skips joiners, and
# stops the match when it does not; a ZWJ at the end leaves the
# one-glyph ligature.
expect ligated(0, True, [{ glyph: 10, props: 0 }, { glyph: 20, props: zwj_props }, { glyph: 11, props: 0 }]).glyphs == [102, 20]
expect ligated(0, False, [{ glyph: 10, props: 0 }, { glyph: 20, props: zwj_props }, { glyph: 11, props: 0 }]).glyphs == [103, 20, 11]
expect ligated(0, True, [{ glyph: 10, props: 0 }, { glyph: 20, props: zwj_props }]).glyphs == [103, 20]

# Resuming must retain global origin indices and ligature serials; a
# stage with no applicable lookup still occupies a plan step.
expect {
	match LayoutGsub.read(liga_gsub(0)) {
		Ok(shape) => {
			items = [10.U64, 11, 10, 12].map_with_index(|glyph, cluster| { glyph, cluster, mask: 1, props: 0 })
			no_op = { index: 999, mask: 1, auto_zwnj: True, auto_zwj: True, random: False }
			lig = { ..no_op, index: 0 }
			limits = { limit: 64, budget: 64, depth: 8 }
			whole = LayoutGsub.apply(shape, [no_op, lig], items, limits)
			first = LayoutGsub.resume(shape, [{ step: no_op, per_syllable: False }], LayoutGsub.begin(items), limits)
			resumed = LayoutGsub.resume(shape, [{ step: lig, per_syllable: False }], first, limits)
			resumed.items == whole.items and resumed.step_offset == 2 and resumed.serial == 2 and resumed.items.all(|item| LayoutGsub.origin_step(item) == 1) and resumed.operations == whole.operations and resumed.stopped == whole.stopped
		}
		Err(_) => False
	}
}

# A feature restricted to syllables cannot ligate across the boundary.
expect {
	match LayoutGsub.read(liga_gsub(0)) {
		Ok(shape) => {
			items = [10.U64, 11].map_with_index(|glyph, cluster| { glyph, cluster, mask: 1 + (cluster + 1).shl_wrap(49), props: 0 })
			step = { index: 0, mask: 1, auto_zwnj: True, auto_zwj: True, random: False }
			limits = { limit: 64, budget: 64, depth: 8 }
			separate = LayoutGsub.resume(shape, [{ step, per_syllable: True }], LayoutGsub.begin(items), limits)
			joined = LayoutGsub.resume(shape, [{ step, per_syllable: False }], LayoutGsub.begin(items), limits)
			separate.items.map(|item| item.glyph) == [103, 11] and joined.items.map(|item| item.glyph) == [102]
		}
		Err(_) => False
	}
}

expect {
	match LayoutGsub.read(liga_gsub(0)) {
		Ok(shape) => {
			a = LayoutGsub.would_substitute(shape, [0], [10, 11], True, 1)
			b = LayoutGsub.would_substitute(shape, [0], [10, 11, 11], False, 1)
			c = LayoutGsub.would_substitute(shape, [0], [10, 12, 11], False, 1)
			d = LayoutGsub.would_substitute(shape, [999, 0], [10, 11], True, 1)
			e = LayoutGsub.would_substitute(shape, [0], [], True, 0)
			a == { matches: True, operations: 1, stopped: 0 } and b.matches and !c.matches and d == { matches: False, operations: 1, stopped: LayoutGsub.stopped_operations } and e == { matches: False, operations: 0, stopped: 0 }
		}
		Err(_) => False
	}
}

expect {
	item = { glyph: 7, cluster: 9, mask: 0x8002000000000001, props: 0xAB123456007A4321 }
	cleared = LayoutGsub.clear_substitution_flags([item])
	cleared == [{ ..item, props: 0xAB123456000A4321 }]
}

# Sixteen stages may contain 16*65535 steps when the read limit permits
# all OpenType lookups. A sparse final lookup keeps its exact origin even
# above the former17-bit bound, without consuming a nested-call budget.
expect {
	match LayoutGsub.read(liga_gsub(0)) {
		Ok(shape) => {
			last = 16 * 65535 - 1
			item = { glyph: 10, cluster: 9, mask: 1, props: 0 }
			initial = { ..LayoutGsub.begin([item]), step_offset: last }
			step = { index: 0, mask: 1, auto_zwnj: True, auto_zwj: True, random: False }
			resumed = LayoutGsub.resume(shape, [{ step, per_syllable: False }], initial, { limit: 64, budget: 0, depth: 8 })
			resumed.items.len() == 1 and resumed.items.all(|made| made.glyph == 103 and LayoutGsub.origin_step(made) == last and made.cluster == 9) and resumed.operations == 0 and resumed.stopped == 0
		}
		Err(_) => False
	}
}

# ## fuzz regression: contextual PRES must not cross a reused syllable's
# intervening boundary, including backtrack and lookahead matching.
expect {
	shape = LayoutGsub.from_synthesized([], { subtables: [], ranges: [], values: [10], rules: [], steps: 0 }, LayoutGdef.none)
	items = [10.U64, 10, 10].map_with_index(|glyph, i| { glyph, cluster: i, mask: 1 + (i + 1).shl_wrap(49), props: 0 })
	buf = { info: items, out: [], idx: 1, output: False, serial: 0, random: 1, ops: 0, stopped: 0, aliased: False }
	ctx = { mask: 1, props: 0, auto_zwnj: True, auto_zwj: True, random: False, step: 0, per_syllable: True, positioning: False }
	seq = { kind: 0, classes: 0, classes_len: 0, at: 0, stride: 1 }
	!LayoutGsub.match_backtrack(shape, ctx, buf, seq, 1).ok and !LayoutGsub.match_lookahead(shape, ctx, buf, seq, 1, 2).ok and LayoutGsub.match_backtrack(shape, { ..ctx, per_syllable: False }, buf, seq, 1).ok and LayoutGsub.match_lookahead(shape, { ..ctx, per_syllable: False }, buf, seq, 1, 2).ok
}
