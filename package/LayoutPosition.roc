import ShaperUnicode
import Bytes
import LayoutGdef
import LayoutGsub
import LayoutVar
import TableVar
import PositionSum

## Full horizontal OpenType positioning. Prepared lookups and subtables are
## scalar spans into flat lists. Context matching shares the substitution
## engine's checked rule representation; execution uses an explicit bounded
## stack because contextual positioning may call itself.
LayoutPosition := {
	data : List(U8),
	lookups : List({ start : U64, end : U64, props : U64 }),
	subtables : List({ kind : U64, at : U64, context : U64, d0 : U64, d1 : U64, d2 : U64 }),
	contexts : LayoutGsub,
	active : Bool,
	mark_starts : List(U64),
}.{
	Lookup : { start : U64, end : U64, props : U64 }
	Sub : { kind : U64, at : U64, context : U64, d0 : U64, d1 : U64, d2 : U64 }
	none : LayoutPosition
	none = { data: [], lookups: [], subtables: [], contexts: LayoutGsub.none, active: False, mark_starts: [] }
	no_lookup : Lookup
	no_lookup = { start: 0, end: 0, props: 0 }
	no_sub : Sub
	no_sub = { kind: 0, at: 0, context: 0, d0: 0, d1: 0, d2: 0 }
	State : { items : List(LayoutGsub.Item), ax : List(I64), dx : List(I64), dy : List(I64), parents : List(U64), attachments : List(U8), stopped : U64, operations : U64 }
	Limits : { budget : U64, depth : U64 }
	ContextCalls : { records : U64, records_len : U64, next : U64, positions : List(U64), depth : U64 }
	Frame : { records : U64, records_len : U64, next : U64, positions_start : U64, positions_len : U64, depth : U64 }
	no_frame : Frame
	no_frame = { records: 0, records_len: 0, next: 0, positions_start: 0, positions_len: 0, depth: 0 }
	Match : { state : State, next : U64, applied : Bool, calls : [Calls(ContextCalls), NoCalls] }

	## Record lists stay in the checked prepared pool. At most one frame
	## and 64 matched glyph positions per permitted nesting level are live.
	push_context : ContextCalls, List(Frame), List(U64) -> { frames : List(Frame), positions : List(U64) }
	push_context = |calls, frames, pool| {
		{ records, records_len, next, positions, depth } = calls
		start = pool.len()
		frame = { records, records_len, next, positions_start: start, positions_len: positions.len(), depth }
		{ frames: frames.append(frame), positions: pool.concat(positions) }
	}

	## OTS accepts sequence indices past a rule's matched input; those
	## records are ignored, as by the reference. Scan lazily without calls.
	next_record : List(U64), U64, U64, U64, U64 -> U64
	next_record = |values, records, count, start, input_count| {
		var $i = start
		while $i < count and (values.get(records + 2 * $i) ?? input_count) >= input_count {
			$i = $i + 1
		}
		$i
	}

	## Only fonts needing more than the existing pair engine use this value.
	is_active : LayoutPosition -> Bool
	is_active = |p| p.active

	## The pair engine is sufficient when no non-pair lookup in this plan
	## can see a glyph in the run. In particular ordinary labels do not pay
	## for mark attachment arrays just because their font supports marks.
	needs_run : LayoutPosition, List({ index : U64, mask : U64 }), List(LayoutGsub.Item) -> Bool
	needs_run = |p, plan, items| {
		if !p.active {
			return False
		}
		var $other = False
		for step in plan {
			lookup = p.lookups.get(step.index) ?? LayoutPosition.no_lookup
			for k in lookup.start..<lookup.end {
				s = p.subtables.get(k) ?? LayoutPosition.no_sub
				if s.kind != 2 and (s.kind < 4 or s.kind > 6) {
					$other = True
				}
			}
		}
		if !$other {
			var $mark = False
			for item in items {
				word = p.mark_starts.get(item.glyph // 64) ?? 0
				if word.shr_zf_wrap(item.glyph.bitwise_and(63).to_u8_wrap()).bitwise_and(1) != 0 {
					$mark = True
				}
			}
			if !$mark {
				return False
			}
		}
		run = LayoutGsub.run_digest(items)
		for step in plan {
			lookup = p.lookups.get(step.index) ?? LayoutPosition.no_lookup
			for k in lookup.start..<lookup.end {
				s = p.subtables.get(k) ?? LayoutPosition.no_sub
				if s.kind != 2 and s.d0.bitwise_and(run.d0) != 0 and s.d1.bitwise_and(run.d1) != 0 and s.d2.bitwise_and(run.d2) != 0 {
					for item in items {
						if LayoutGsub.applies(item.mask, step.mask) {
							covered = if s.kind == 7 or s.kind == 8 {
								sub = p.contexts.subtables.get(s.context) ?? LayoutGsub.no_sub
								LayoutGsub.covered_in(p.contexts.ranges, sub.coverage, sub.coverage_len, item.glyph).is_ok()
							} else {
								LayoutPosition.covered(p.data, s.at + Bytes.u16(p.data, s.at + 2), item.glyph).is_ok()
							}
							if covered {
								return True
							}
						}
					}
				}
			}
		}
		False
	}

	## Validate every lookup, including lookups only contextual rules call.
	## Invalid variation indices are returned separately, as the font reader
	## drops the variation space rather than the positioning table for them.
	read : List(U8), U64, LayoutVar -> Try({ value : LayoutPosition, deltas : List(U64) }, [Bad(U64)])
	read = |data, glyphs, lv| {
		list = Bytes.u16(data, 8)
		count = Bytes.u16(data, list)
		var $lookups = List.with_capacity(count)
		var $subs = []
		var $built = { subtables: [], ranges: [], values: [], rules: [], steps: 0 }
		validation = { data, glyphs, lookups: count, sets: Absent, budget: 64 * data.len() + 1048576 }
		var $active = False
		var $deltas = []
		var $mark_starts = List.repeat(0.U64, (glyphs + 63) // 64)
		for i in 0..<count {
			at = list + Bytes.u16(data, list + 2 + 2 * i)
			if !Bytes.fits(at, 6, data.len()) {
				return Err(Bad(at))
			}
			kind = Bytes.u16(data, at)
			flags = Bytes.u16(data, at + 2)
			n = Bytes.u16(data, at + 4)
			filtering = flags.bitwise_and(0x10) != 0
			if kind < 1 or kind > 9 or !Bytes.fits(at, 6 + 2 * n + (if (filtering) 2 else 0), data.len()) {
				return Err(Bad(at))
			}
			props = flags + (if (filtering) Bytes.u16(data, at + 6 + 2 * n) * 65536 else 0)
			start = $subs.len()
			$built = { ..$built, steps: LayoutPosition.spend(data, $built.steps, n)? }
			for j in 0..<n {
				first = at + Bytes.u16(data, at + 6 + 2 * j)
				target = if kind == 9 {
					if !Bytes.fits(first, 8, data.len()) or Bytes.u16(data, first) != 1 {
						return Err(Bad(first))
					}
					real = Bytes.u16(data, first + 2)
					if real < 1 or real > 8 {
						return Err(Bad(first + 2))
					}
					{ kind: real, at: first + Bytes.u32(data, first + 4) }
				} else {
					{ kind, at: first }
				}
				if !Bytes.fits(target.at, 2, data.len()) {
					return Err(Bad(target.at))
				}
				context = $built.subtables.len()
				if target.kind == 7 or target.kind == 8 {
					format = Bytes.u16(data, target.at)
					validated = if (target.kind == 7) LayoutGsub.ots_context(validation, format, target.at, $built.steps)? else LayoutGsub.ots_chain(validation, format, target.at, $built.steps)?
					$built = LayoutGsub.read_context(data, target.kind == 8, format, target.at, { ..$built, steps: validated })?
				} else if target.kind != 2 {
					checked = LayoutPosition.check(data, target, lv, glyphs, $built.steps)?
					$built = { ..$built, steps: checked.steps }
					$deltas = $deltas.concat(checked.deltas)
				}
				$active = $active or target.kind != 2
				var $d0 = 0
				var $d1 = 0
				var $d2 = 0
				if target.kind != 2 {
					ranges = if target.kind == 7 or target.kind == 8 {
						s = $built.subtables.get(context) ?? LayoutGsub.no_sub
						$built.ranges.sublist({ start: s.coverage, len: s.coverage_len })
					} else {
						(LayoutGsub.read_coverage(data, target.at + Bytes.u16(data, target.at + 2), $built.steps)?).value
					}
					for r in ranges {
						if target.kind >= 4 and target.kind <= 6 and r.first <= r.last {
							first_word = r.first // 64
							last_word = r.last // 64
							$built = { ..$built, steps: LayoutPosition.spend(data, $built.steps, last_word - first_word + 1)? }
							for word in first_word..=last_word {
								low = r.first.max(word * 64)
								high = r.last.min(word * 64 + 63)
								mask = LayoutGsub.digest_range(0, 0, low, high)
								# OTS permits format-2 ranges extending past the font.
								# Only glyphs the font has can start this path.
								if word < $mark_starts.len() {
									$mark_starts = $mark_starts.set(word, ($mark_starts.get(word) ?? 0).bitwise_or(mask)) ?? []
								}
							}
						}
						$d0 = LayoutGsub.digest_range($d0, 0, r.first, r.last)
						$d1 = LayoutGsub.digest_range($d1, 4, r.first, r.last)
						$d2 = LayoutGsub.digest_range($d2, 9, r.first, r.last)
					}
				}
				$subs = $subs.append({ kind: target.kind, at: target.at, context, d0: $d0, d1: $d1, d2: $d2 })
			}
			$lookups = $lookups.append({ start, end: $subs.len(), props })
		}
		for r in $built.rules {
			for i in 0..<r.records_len {
				if ($built.values.get(r.records + 2 * i + 1) ?? count) >= count {
					return Err(Bad(list))
				}
			}
		}
		Ok({ value: { data, lookups: $lookups, subtables: $subs, contexts: LayoutGsub.from_contexts($built), active: $active, mark_starts: $mark_starts }, deltas: $deltas })
	}

	spend : List(U8), U64, U64 -> Try(U64, [Bad(U64)])
	spend = |data, steps, count| {
		total = steps + count + 1
		if total > 8 * data.len() + 16384 {
			Err(Bad(0))
		} else {
			Ok(total)
		}
	}

	## Bounds are checked before loops or allocations depending on counts.
	check : List(U8), { kind : U64, at : U64 }, LayoutVar, U64, U64 -> Try({ steps : U64, deltas : List(U64) }, [Bad(U64)])
	check = |data, sub, lv, glyphs, steps| {
		at = sub.at
		format = Bytes.u16(data, at)
		var $steps = LayoutPosition.spend(data, steps, 1)?
		var $deltas = []
		if sub.kind == 1 {
			if !Bytes.fits(at, 6, data.len()) or (format != 1 and format != 2) {
				return Err(Bad(at))
			}
			$steps = LayoutPosition.check_coverage(data, at + Bytes.u16(data, at + 2), glyphs, $steps)?
			vf = Bytes.u16(data, at + 4)
			if vf > 255 {
				return Err(Bad(at + 4))
			}
			n = if (format == 1) 1 else Bytes.u16(data, at + 6)
			start = if (format == 1) at + 6 else at + 8
			size = LayoutVar.value_size(vf)
			if !Bytes.fits(start, n * size, data.len()) {
				return Err(Bad(start))
			}
			$steps = LayoutPosition.spend(data, $steps, n)?
			for i in 0..<n {
				checked = LayoutPosition.check_value(data, at, start + i * size, vf, lv)?
				$deltas = $deltas.concat(checked)
			}
		} else if sub.kind == 3 {
			if format != 1 or !Bytes.fits(at, 6, data.len()) {
				return Err(Bad(at))
			}
			cov_steps = LayoutPosition.check_coverage(data, at + Bytes.u16(data, at + 2), glyphs, $steps)?
			n = Bytes.u16(data, at + 4)
			if !Bytes.fits(at + 6, 4 * n, data.len()) {
				return Err(Bad(at + 4))
			}
			$steps = LayoutPosition.spend(data, cov_steps, n)?
			for i in 0..<(2 * n) {
				o = Bytes.u16(data, at + 6 + 2 * i)
				if o != 0 {
					a = LayoutPosition.check_anchor(data, at + o, lv, $steps)?
					$steps = a.steps
					$deltas = $deltas.concat(a.deltas)
				}
			}
		} else {
			if format != 1 or !Bytes.fits(at, 12, data.len()) {
				return Err(Bad(at))
			}
			first_steps = LayoutPosition.check_coverage(data, at + Bytes.u16(data, at + 2), glyphs, $steps)?
			second_steps = LayoutPosition.check_coverage(data, at + Bytes.u16(data, at + 4), glyphs, first_steps)?
			classes = Bytes.u16(data, at + 6)
			marks = at + Bytes.u16(data, at + 8)
			n = Bytes.u16(data, marks)
			if classes == 0 or !Bytes.fits(marks, 2 + 4 * n, data.len()) {
				return Err(Bad(marks))
			}
			$steps = LayoutPosition.spend(data, second_steps, n)?
			for i in 0..<n {
				record = marks + 2 + 4 * i
				if Bytes.u16(data, record) >= classes {
					return Err(Bad(record))
				}
				o = Bytes.u16(data, record + 2)
				if o == 0 {
					return Err(Bad(record + 2))
				}
				a = LayoutPosition.check_anchor(data, marks + o, lv, $steps)?
				$steps = a.steps
				$deltas = $deltas.concat(a.deltas)
			}
			bases = at + Bytes.u16(data, at + 10)
			if !Bytes.fits(bases, 2, data.len()) {
				return Err(Bad(bases))
			}
			if sub.kind == 5 {
				count = Bytes.u16(data, bases)
				if !Bytes.fits(bases + 2, 2 * count, data.len()) {
					return Err(Bad(bases))
				}
				$steps = LayoutPosition.spend(data, $steps, count)?
				for i in 0..<count {
					o = Bytes.u16(data, bases + 2 + 2 * i)
					if o != 0 {
						a = LayoutPosition.check_matrix(data, bases + o, classes, lv, $steps)?
						$steps = a.steps
						$deltas = $deltas.concat(a.deltas)
					}
				}
			} else {
				a = LayoutPosition.check_matrix(data, bases, classes, lv, $steps)?
				$steps = a.steps
				$deltas = $deltas.concat(a.deltas)
			}
		}
		Ok({ steps: $steps, deltas: $deltas })
	}

	check_coverage : List(U8), U64, U64, U64 -> Try(U64, [Bad(U64)])
	check_coverage = |data, at, glyphs, steps| LayoutGsub.ots_coverage({ data, glyphs, lookups: 0, sets: Absent, budget: 8 * data.len() + 16384 }, at, steps)

	check_matrix : List(U8), U64, U64, LayoutVar, U64 -> Try({ steps : U64, deltas : List(U64) }, [Bad(U64)])
	check_matrix = |data, at, classes, lv, steps| {
		count = Bytes.u16(data, at) * classes
		if !Bytes.fits(at, 2 + 2 * count, data.len()) {
			return Err(Bad(at))
		}
		var $steps = LayoutPosition.spend(data, steps, count)?
		var $deltas = []
		for i in 0..<count {
			o = Bytes.u16(data, at + 2 + 2 * i)
			if o != 0 {
				a = LayoutPosition.check_anchor(data, at + o, lv, $steps)?
				$steps = a.steps
				$deltas = $deltas.concat(a.deltas)
			}
		}
		Ok({ steps: $steps, deltas: $deltas })
	}

	check_anchor : List(U8), U64, LayoutVar, U64 -> Try({ steps : U64, deltas : List(U64) }, [Bad(U64)])
	check_anchor = |data, at, lv, steps| {
		format = Bytes.u16(data, at)
		size = if (format == 1) 6 else if (format == 2) 8 else if (format == 3) 10 else 0
		if size == 0 or !Bytes.fits(at, size, data.len()) {
			return Err(Bad(at))
		}
		var $deltas = []
		if format == 3 {
			# Both device fields are in the checked ten-byte anchor. Iterate
			# their positions without allocating a temporary list per anchor.
			for i in 0..<2 {
				field = at + 6 + 2 * i
				$deltas = $deltas.concat(LayoutPosition.check_device(data, at, field, lv)?)
			}
		}
		Ok({ steps: LayoutPosition.spend(data, steps, 1)?, deltas: $deltas })
	}

	check_value : List(U8), U64, U64, U64, LayoutVar -> Try(List(U64), [Bad(U64)])
	check_value = |data, base, at, vf, lv| {
		var $deltas = []
		var $field = at + 2 * LayoutVar.bits(vf, 15)
		for bit in [16, 32, 64, 128] {
			if vf.bitwise_and(bit) != 0 {
				$deltas = $deltas.concat(LayoutPosition.check_device(data, base, $field, lv)?)
				$field = $field + 2
			}
		}
		Ok($deltas)
	}

	check_device : List(U8), U64, U64, LayoutVar -> Try(List(U64), [Bad(U64)])
	check_device = |data, base, field, lv| {
		o = Bytes.u16(data, field)
		if o == 0 {
			return Ok([])
		}
		at = base + o
		if !Bytes.fits(at, 6, data.len()) {
			return Err(Bad(field))
		}
		format = Bytes.u16(data, at + 4)
		if format == 0x8000 {
			match LayoutVar.check_device_index(lv, data, base, field) {
				True => Ok([])
				False => Ok([at])
			}
		} else if format >= 1 and format <= 3 {
			first = Bytes.u16(data, at)
			last = Bytes.u16(data, at + 2)
			if first > last {
				return Err(Bad(at))
			}
			bits = (1.U64).shl_wrap(format.to_u8_wrap())
			words = ((last - first + 1) * bits + 15) // 16
			if Bytes.fits(at + 6, 2 * words, data.len()) {
				Ok([])
			} else {
				Err(Bad(at))
			}
		} else {
			Err(Bad(at + 4))
		}
	}

	## A conservative allocation-free probe. The existing pair reader checks
	## the headers before calling this; the full reader checks all extra data.
	needed : List(U8) -> Bool
	needed = |data| {
		list = Bytes.u16(data, 8)
		var $needed = False
		var $remaining = 8 * data.len() + 16384
		for i in 0..<Bytes.u16(data, list) {
			at = list + Bytes.u16(data, list + 2 + 2 * i)
			kind = Bytes.u16(data, at)
			if kind != 2 and kind != 9 {
				$needed = True
			}
			if kind == 9 {
				for j in 0..<Bytes.u16(data, at + 4) {
					if $remaining == 0 {
						return True
					}
					$remaining = $remaining - 1
					sub = at + Bytes.u16(data, at + 6 + 2 * j)
					if Bytes.u16(data, sub + 2) != 2 {
						$needed = True
					}
				}
			}
		}
		$needed
	}

	Ctx : { lv : LayoutVar, loc : LayoutVar.Location, gdef : LayoutGdef, backward : Bool, previous : List(U64), auto_zwj : Bool, limits : Limits }
	position : LayoutPosition, LayoutVar, LayoutVar.Location, LayoutGdef, List({ index : U64, mask : U64 }), List(Bool), Bool, List(LayoutGsub.Item), List(I64), Bool, Limits -> State
	position = |p, lv, loc, gdef, plan, auto_zwj, zero_late, items, base, backward, limits| {
		count = items.len()
		# Most plans automatically skip ZWJ. Build the second previous-base
		# index only when a manual-ZWJ lookup can consume it. Missing flags
		# select automatic skipping, as in the lookup loop below.
		manual = auto_zwj.any(|automatic| !automatic)
		var $previous = List.with_capacity(count)
		var $manual_previous = List.with_capacity(if (manual) count else 0)
		var $manual_last = 0
		var $initial = base
		var $last = 0
		for i in 0..<count {
			advance = $initial.get(i) ?? 0
			if advance < -2147483648 or advance > 2147483647 {
				$initial = $initial.set(i, LayoutVar.position_clamp(advance)) ?? []
			}
			$previous = $previous.append($last)
			if manual {
				$manual_previous = $manual_previous.append($manual_last)
				item = items.get(i) ?? LayoutGsub.no_item
				if !LayoutGsub.is_mark_item(item) and !LayoutPosition.skip_ignorable(item, False) {
					$manual_last = i + 1
				}
			}
			if !LayoutGsub.is_mark_item(items.get(i) ?? LayoutGsub.no_item) and !LayoutGsub.is_default_ignorable(items.get(i) ?? LayoutGsub.no_item) {
				$last = i + 1
			}
		}

		var $s = { items, ax: $initial, dx: List.repeat(0, count), dy: List.repeat(0, count), parents: List.repeat(0, count), attachments: List.repeat(0, count), stopped: 0, operations: 0 }
		var $frames = []
		var $positions = []
		for step_index in 0..<plan.len() {
			step = plan.get(step_index) ?? { index: 0, mask: 0 }
			automatic = auto_zwj.get(step_index) ?? True
			ctx = { lv, loc, gdef, backward, previous: if (automatic) $previous else $manual_previous, auto_zwj: automatic, limits }
			var $i = 0
			while $i < count {
				{ state: after, next, applied: _, calls } = LayoutPosition.once(p, ctx, step.index, step.mask, $i, 0, $s)
				$s = after
				$i = next.max($i + 1)
				match calls {
					Calls(found) => {
						{ frames, positions } = LayoutPosition.push_context(found, $frames, $positions)
						$frames = frames
						$positions = positions
					}
					NoCalls => {}
				}
				while !$frames.is_empty() {
					frame = $frames.last() ?? LayoutPosition.no_frame
					r = LayoutPosition.next_record(p.contexts.values, frame.records, frame.records_len, frame.next, frame.positions_len)
					if r == frame.records_len {
						$frames = $frames.drop_last(1)
						$positions = $positions.take_first(frame.positions_start)
					} else if $s.operations >= limits.budget {
						$s = { ..$s, stopped: $s.stopped.bitwise_or(LayoutGsub.stopped_operations) }
						$frames = $frames.clear()
						$positions = $positions.clear()
					} else {
						seq = p.contexts.values.get(frame.records + 2 * r) ?? crash "a checked positioning record lost its sequence index"
						index = p.contexts.values.get(frame.records + 2 * r + 1) ?? crash "a checked positioning record lost its lookup index"
						at = $positions.get(frame.positions_start + seq) ?? crash "a matched positioning input lost its glyph position"
						# The nonempty stack proves this index is in bounds.
						$frames = $frames.set($frames.len() - 1, { ..frame, next: r + 1 }) ?? []
						{ state: nested_state, next: _, applied: _, calls: nested_calls } = LayoutPosition.once(p, ctx, index, step.mask, at, frame.depth, $s)
						$s = nested_state
						match nested_calls {
							Calls(found) => {
								{ frames, positions } = LayoutPosition.push_context(found, $frames, $positions)
								$frames = frames
								$positions = positions
							}
							NoCalls => {}
						}
					}
				}
			}
		}
		# Late zeroing precedes attachment propagation; NONE and EARLY keep
		# advances supplied by GPOS. Default ignorables always lose advances.
		{ items: final_items, ax, dx, dy, parents, attachments, stopped, operations } = $s
		var $ax = ax
		for i in 0..<count {
			if (zero_late and LayoutGsub.is_mark_item(final_items.get(i) ?? LayoutGsub.no_item)) or LayoutGsub.is_default_ignorable(final_items.get(i) ?? LayoutGsub.no_item) {
				$ax = $ax.set(i, 0) ?? []
			}
		}
		{ items: final_items, ax: $ax, dx, dy, parents, attachments, stopped, operations }
	}

	once : LayoutPosition, Ctx, U64, U64, U64, U64, State -> Match
	once = |p, ctx, index, mask, i, depth, state| {
		lookup = p.lookups.get(index) ?? LayoutPosition.no_lookup
		props = LayoutGdef.sanitize_props(ctx.gdef, lookup.props)
		item = state.items.get(i) ?? LayoutGsub.no_item
		var $s = { ..state, operations: state.operations + (if (depth > 0) 1 else 0) }
		if i >= $s.items.len() or !LayoutGsub.applies(item.mask, mask) or !LayoutPosition.sees(ctx.gdef, item, props) {
			return { state: $s, next: i + 1, applied: False, calls: NoCalls }
		}
		var $next = i + 1
		var $applied = False
		var $calls = NoCalls
		var $k = lookup.start
		while $k < lookup.end {
			sub = p.subtables.get($k) ?? LayoutPosition.no_sub
			{ state: after, next, applied, calls } = LayoutPosition.subtable(p, ctx, sub, props, mask, i, depth, $s)
			$s = after
			$next = next
			$applied = applied
			$calls = calls
			$k = if (applied) lookup.end else $k + 1
		}
		{ state: $s, next: $next, applied: $applied, calls: $calls }
	}

	sees : LayoutGdef, LayoutGsub.Item, U64 -> Bool
	sees = |gdef, item, props| props == 0 or LayoutGdef.check_glyph_property(gdef, item.glyph, LayoutGsub.gprops(item), props)

	skip_ignorable : LayoutGsub.Item, Bool -> Bool
	skip_ignorable = |item, automatic| LayoutGsub.is_default_ignorable(item) and (automatic or !ShaperUnicode.is_zwj(item.props))

	## Positioning always skips ZWNJ; feature policy controls ZWJ. Input masks stop a search;
	## backtracking for attachment uses the lookup's filtering rules only.
	next : List(LayoutGsub.Item), U64, U64, U64, LayoutGdef, Bool -> Try(U64, [NoGlyph])
	next = |items, i, mask, props, gdef, automatic| {
		var $j = i + 1
		while $j < items.len() {
			item = items.get($j) ?? LayoutGsub.no_item
			if !LayoutPosition.sees(gdef, item, props) or LayoutPosition.skip_ignorable(item, automatic) {
				$j = $j + 1
			}
			else if LayoutGsub.applies(item.mask, mask) {
				return Ok($j)
			}
			else {
				return Err(NoGlyph)
			}
		}
		Err(NoGlyph)
	}

	subtable : LayoutPosition, Ctx, Sub, U64, U64, U64, U64, State -> Match
	subtable = |p, ctx, sub, props, mask, i, depth, state| {
		data = p.data
		at = sub.at
		item = state.items.get(i) ?? LayoutGsub.no_item

		if sub.kind == 7 or sub.kind == 8 {
			matcher = LayoutGsub.with_gdef(p.contexts, ctx.gdef)
			buf = { info: state.items, out: [], idx: i, output: False, serial: 0, random: 1, ops: 0, stopped: 0, aliased: False }
			match_ctx = { mask, props, auto_zwnj: True, auto_zwj: ctx.auto_zwj, random: False, step: 0, per_syllable: False, positioning: True }
			matched = LayoutGsub.apply_context(matcher, matcher.subtables.get(sub.context) ?? LayoutGsub.no_sub, match_ctx, buf, { scratch: [], frames: [], positions: [] })
			s = { ..state, items: matched.buf.info }
			match matched.outcome {
				Context(found) => {
					first = LayoutPosition.next_record(matcher.values, found.records, found.records_len, 0, found.count)
					if first == found.records_len {
						{ state: s, next: found.end, applied: True, calls: NoCalls }
					} else if s.operations >= ctx.limits.budget {
						# Budget is checked before depth, matching pending-call order.
						{ state: { ..s, stopped: s.stopped.bitwise_or(LayoutGsub.stopped_operations) }, next: found.end, applied: True, calls: NoCalls }
					} else if depth >= ctx.limits.depth {
						# Every child would be rejected for depth. Avoid materializing
						# any of them, while retaining the successful context match.
						{ state: { ..s, stopped: s.stopped.bitwise_or(LayoutGsub.stopped_depth) }, next: found.end, applied: True, calls: NoCalls }
					} else {
						{ state: s, next: found.end, applied: True, calls: Calls({ records: found.records, records_len: found.records_len, next: first, positions: matched.work.scratch, depth: depth + 1 }) }
					}
				}
				_ => { state: s, next: i + 1, applied: False, calls: NoCalls }
			}
		} else {
			match LayoutPosition.covered(data, at + Bytes.u16(data, at + 2), item.glyph) {
				Err(_) => { state, next: i + 1, applied: False, calls: NoCalls }
				Ok(coverage) => {
					if sub.kind == 1 {
						format = Bytes.u16(data, at)
						vf = Bytes.u16(data, at + 4)
						if format == 2 and coverage >= Bytes.u16(data, at + 6) {
							return { state, next: i + 1, applied: False, calls: NoCalls }
						}
						record = if (format == 1) at + 6 else at + 8 + coverage * LayoutVar.value_size(vf)
						{ state: LayoutPosition.add_value(state, ctx, data, at, record, vf, i), next: i + 1, applied: True, calls: NoCalls }
					} else if sub.kind == 2 {
						LayoutPosition.pair(p, ctx, at, coverage, props, mask, i, state)
					} else if sub.kind == 3 {
						LayoutPosition.cursive(p, ctx, at, coverage, props, mask, i, state)
					} else {
						LayoutPosition.mark(p, ctx, sub, coverage, props, i, state)
					}
				}
			}
		}
	}

	add_value : State, Ctx, List(U8), U64, U64, U64, U64 -> State
	add_value = |state, ctx, data, base, record, format, i| {
		{ items, ax, dx, dy, parents, attachments, stopped, operations } = state
		v = LayoutVar.apply_value(ctx.lv, ctx.loc, data, base, record, format, { x_advance: ax.get(i) ?? 0, x_placement: dx.get(i) ?? 0, y_placement: dy.get(i) ?? 0, y_advance: 0 })
		# The caller's cursor is in the aligned run. Stored and device
		# corrections saturate separately, preserving their application order.
		{ items, ax: ax.set(i, v.x_advance) ?? [], dx: dx.set(i, v.x_placement) ?? [], dy: dy.set(i, v.y_placement) ?? [], parents, attachments, stopped, operations }
	}

	pair : LayoutPosition, Ctx, U64, U64, U64, U64, U64, State -> Match
	pair = |p, ctx, at, coverage, props, mask, i, state| {
		data = p.data

		j = LayoutPosition.next(state.items, i, mask, props, ctx.gdef, ctx.auto_zwj) ?? return { state, next: i + 1, applied: False, calls: NoCalls }
		second = state.items.get(j) ?? LayoutGsub.no_item
		vf1 = Bytes.u16(data, at + 4)
		vf2 = Bytes.u16(data, at + 6)
		size1 = LayoutVar.value_size(vf1)
		size2 = LayoutVar.value_size(vf2)
		var $base = at
		var $record = 0
		if Bytes.u16(data, at) == 1 {
			if coverage >= Bytes.u16(data, at + 8) {
				return { state, next: i + 1, applied: False, calls: NoCalls }
			}
			set = at + Bytes.u16(data, at + 10 + 2 * coverage)
			$base = set
			var $low = 0
			var $high = Bytes.u16(data, set)
			while $low < $high {
				mid = ($low + $high) // 2
				r = set + 2 + mid * (2 + size1 + size2)
				g = Bytes.u16(data, r)
				if second.glyph < g {
					$high = mid
				} else if second.glyph > g {
					$low = mid + 1
				}
				else {
					$record = r + 2
					$low = $high
				}
			}
			if $record == 0 {
				return { state, next: i + 1, applied: False, calls: NoCalls }
			}
		} else {
			first = state.items.get(i) ?? LayoutGsub.no_item
			row = LayoutPosition.class_of(data, at + Bytes.u16(data, at + 8), first.glyph)
			col = LayoutPosition.class_of(data, at + Bytes.u16(data, at + 10), second.glyph)
			width = Bytes.u16(data, at + 14)
			if row >= Bytes.u16(data, at + 12) or col >= width {
				return { state, next: i + 1, applied: False, calls: NoCalls }
			}
			$record = at + 16 + (row * width + col) * (size1 + size2)
		}
		s1 = LayoutPosition.add_value(state, ctx, data, $base, $record, vf1, i)
		s2 = LayoutPosition.add_value(s1, ctx, data, $base, $record + size1, vf2, j)
		worked = LayoutPosition.value_applies(data, $record, vf1, ctx.loc.active) or LayoutPosition.value_applies(data, $record + size1, vf2, ctx.loc.active)
		flagged = if (worked) LayoutPosition.flag(s2.items, i, j + 1) else s2.items
		# Any second value record consumes the second glyph, including an
		# all-zero record: the following boundary is unsafe too (HB#3824).
		flags = if (vf2 != 0) LayoutPosition.flag(flagged, i, j + 2) else flagged
		{ state: { ..s2, items: flags }, next: if (vf2 != 0) j + 1 else j, applied: True, calls: NoCalls }
	}

	## ValueFormat.apply_value reports nonzero stored horizontal fields,
	## or a device reference when normalized coordinates are nonzero. A
	## zero pair record still matches but must not mark a break unsafe.
	value_applies : List(U8), U64, U64, Bool -> Bool
	value_applies = |data, record, format, active| {
		var $field = record
		var $bit = 1.U64
		while $bit <= 0x40 {
			if format.bitwise_and($bit) != 0 {
				if ($bit <= 4 or (active and $bit >= 0x10 and $bit <= 0x40)) and Bytes.u16(data, $field) != 0 {
					return True
				}
				$field = $field + 2
			}
			$bit = $bit * 2
		}
		False
	}

	# Anchors are integral at unit scale, but format3's integer device delta
	# is added in binary32. Preserve that rounding before subtracting anchors.
	anchor_coordinate : I64, I64 -> I64
	anchor_coordinate = |stored, delta| if (delta == 0) stored else TableVar.f32_floor(TableVar.f32_add(TableVar.f32_from_int(stored), TableVar.f32_from_int(delta)))

	# HarfBuzz also rounds the binary32 sum with 0.5 before storing a position.
	# Large integral floats can change at this step; small coordinates cannot.
	anchor_round : I64 -> I64
	anchor_round = |value| {
		rounded = if (value >= -8388608 and value <= 8388608) value else TableVar.f32_round_half_up(TableVar.f32_from_int(value))
		LayoutVar.position_clamp(rounded)
	}

	anchor_difference : I64, I64 -> I64
	anchor_difference = |a, b| LayoutPosition.anchor_round(a - b)

	# A chain is stored as a signed 16-bit relative index by the reference.
	attachable : U64, U64 -> Bool
	attachable = |child, parent| if (parent >= child) parent - child <= 32767 else child - parent <= 32768

	anchor : LayoutPosition, Ctx, U64 -> { x : I64, y : I64 }
	anchor = |p, ctx, at| {
		varied = Bytes.u16(p.data, at) == 3
		x = LayoutPosition.anchor_coordinate(Bytes.i16(p.data, at + 2), if (varied) LayoutVar.device_delta(ctx.lv, ctx.loc, p.data, at, at + 6) else 0)
		y = LayoutPosition.anchor_coordinate(Bytes.i16(p.data, at + 4), if (varied) LayoutVar.device_delta(ctx.lv, ctx.loc, p.data, at, at + 8) else 0)
		# Format2 uses stored coordinates; contour points require ppem hinting.
		{ x, y }
	}

	mark : LayoutPosition, Ctx, Sub, U64, U64, U64, State -> Match
	mark = |p, ctx, sub, coverage, props, i, state| {
		data = p.data
		at = sub.at
		marks = at + Bytes.u16(data, at + 8)
		if coverage >= Bytes.u16(data, marks) {
			return { state, next: i + 1, applied: False, calls: NoCalls }
		}
		mark_record = marks + 2 + 4 * coverage
		klass = Bytes.u16(data, mark_record)
		var $j = i
		if sub.kind == 6 {
			var $search = True
			while $search and $j > 0 {
				$j = $j - 1
				candidate = state.items.get($j) ?? LayoutGsub.no_item
				if LayoutPosition.sees(ctx.gdef, candidate, props.bitwise_and(0xFFFFFFFFFFFFFFF1)) and !LayoutPosition.skip_ignorable(candidate, ctx.auto_zwj) {
					$search = False
				}
			}
			if $search {
				return { state, next: i + 1, applied: False, calls: NoCalls }
			}
			candidate = state.items.get($j) ?? LayoutGsub.no_item
			if !LayoutGsub.is_mark_item(candidate) {
				return { state, next: i + 1, applied: False, calls: NoCalls }
			}
			current = state.items.get(i) ?? LayoutGsub.no_item
			id1 = LayoutGsub.lig_id(current)
			id2 = LayoutGsub.lig_id(candidate)
			comp1 = LayoutGsub.lig_comp(current)
			comp2 = LayoutGsub.lig_comp(candidate)
			if !((id1 == id2 and (id1 == 0 or comp1 == comp2)) or (id1 != id2 and ((id1 > 0 and comp1 == 0) or (id2 > 0 and comp2 == 0)))) {
				return { state, next: i + 1, applied: False, calls: NoCalls }
			}
		} else {
			var $prev = ctx.previous.get(i) ?? 0
			var $found = False
			while $prev > 0 and !$found {
				candidate_index = $prev - 1
				candidate = state.items.get(candidate_index) ?? LayoutGsub.no_item
				multiplied = LayoutGsub.gprops(candidate).bitwise_and(LayoutGsub.multiplied) != 0
				comp = LayoutGsub.lig_comp(candidate)
				preceding = if (candidate_index > 0) state.items.get(candidate_index - 1) ?? LayoutGsub.no_item else LayoutGsub.no_item
				accepted = !multiplied or comp == 0 or (sub.kind == 4 and (candidate_index == 0 or LayoutGsub.is_mark_item(preceding) or LayoutGsub.gprops(preceding).bitwise_and(LayoutGsub.multiplied) == 0 or LayoutGsub.lig_id(candidate) != LayoutGsub.lig_id(preceding) or comp != LayoutGsub.lig_comp(preceding) + 1))
				if accepted or LayoutPosition.covered(data, at + Bytes.u16(data, at + 4), candidate.glyph).is_ok() {
					$j = candidate_index
					$found = True
				} else {
					$prev = ctx.previous.get(candidate_index) ?? 0
				}
			}
			if !$found {
				return { state, next: i + 1, applied: False, calls: NoCalls }
			}
		}
		base_item = state.items.get($j) ?? LayoutGsub.no_item
		base_cov = LayoutPosition.covered(data, at + Bytes.u16(data, at + 4), base_item.glyph) ?? return { state, next: i + 1, applied: False, calls: NoCalls }
		classes = Bytes.u16(data, at + 6)
		bases = at + Bytes.u16(data, at + 10)
		if base_cov >= Bytes.u16(data, bases) {
			return { state, next: i + 1, applied: False, calls: NoCalls }
		}
		var $matrix = bases
		var $row = base_cov
		if sub.kind == 5 {
			o = Bytes.u16(data, bases + 2 + 2 * base_cov)
			if o == 0 {
				return { state, next: i + 1, applied: False, calls: NoCalls }
			}
			$matrix = bases + o
			components = Bytes.u16(data, $matrix)
			if components == 0 {
				return { state, next: i + 1, applied: False, calls: NoCalls }
			}
			current = state.items.get(i) ?? LayoutGsub.no_item
			comp = LayoutGsub.lig_comp(current)
			$row = if (LayoutGsub.lig_id(base_item) != 0 and LayoutGsub.lig_id(base_item) == LayoutGsub.lig_id(current) and comp > 0) (comp - 1).min(components - 1) else components - 1
		}
		o = Bytes.u16(data, $matrix + 2 + 2 * ($row * classes + klass))
		if o == 0 {
			return { state, next: i + 1, applied: False, calls: NoCalls }
		}
		base_anchor = LayoutPosition.anchor(p, ctx, $matrix + o)
		mark_anchor = LayoutPosition.anchor(p, ctx, marks + Bytes.u16(data, mark_record + 2))
		base_cross = LayoutPosition.cross_offset(state, $j)
		{ items, ax, dx, dy, parents, attachments, stopped, operations } = state
		# Overflow detaches the old edge and keeps the offsets already present.
		if !LayoutPosition.attachable(i, $j) {
			return { state: { items: LayoutPosition.flag(items, $j, i + 1), ax, dx, dy, parents: parents.set(i, 0) ?? [], attachments, stopped, operations }, next: i + 1, applied: True, calls: NoCalls }
		}
		# Both indices are in the run and all arrays have its length.
		s = { items: LayoutPosition.flag(items, $j, i + 1), ax, dx: dx.set(i, LayoutPosition.anchor_difference(base_anchor.x, mark_anchor.x)) ?? [], dy: dy.set(i, LayoutVar.position_add(LayoutPosition.anchor_difference(base_anchor.y, mark_anchor.y), base_cross)) ?? [], parents: parents.set(i, $j + 1) ?? [], attachments: attachments.set(i, 1) ?? [], stopped, operations }
		{ state: s, next: i + 1, applied: True, calls: NoCalls }
	}

	cursive : LayoutPosition, Ctx, U64, U64, U64, U64, U64, State -> Match
	cursive = |p, ctx, at, coverage, props, mask, cursor, state| {
		data = p.data
		if coverage >= Bytes.u16(data, at + 4) {
			return { state, next: cursor + 1, applied: False, calls: NoCalls }
		}
		entry_offset = Bytes.u16(data, at + 6 + 4 * coverage)
		if entry_offset == 0 {
			return { state, next: cursor + 1, applied: False, calls: NoCalls }
		}
		var $previous = cursor
		var $found = False
		var $searching = True
		while $searching and $previous > 0 {
			$previous = $previous - 1
			item = state.items.get($previous) ?? LayoutGsub.no_item
			if LayoutPosition.sees(ctx.gdef, item, props) and !LayoutPosition.skip_ignorable(item, ctx.auto_zwj) {
				$found = LayoutGsub.applies(item.mask, mask)
				$searching = False
			}
		}
		if !$found {
			return { state, next: cursor + 1, applied: False, calls: NoCalls }
		}
		i = $previous
		j = cursor
		other = state.items.get(i) ?? LayoutGsub.no_item
		cov = LayoutPosition.covered(data, at + Bytes.u16(data, at + 2), other.glyph) ?? return { state, next: cursor + 1, applied: False, calls: NoCalls }
		if cov >= Bytes.u16(data, at + 4) {
			return { state, next: cursor + 1, applied: False, calls: NoCalls }
		}
		exit_offset = Bytes.u16(data, at + 8 + 4 * cov)
		if exit_offset == 0 {
			return { state, next: cursor + 1, applied: False, calls: NoCalls }
		}
		exit = LayoutPosition.anchor(p, ctx, at + exit_offset)
		entry = LayoutPosition.anchor(p, ctx, at + entry_offset)
		{ items, ax, dx, dy, parents, attachments, stopped, operations } = state
		var $ax = ax
		var $dx = dx
		if !ctx.backward {
			$ax = $ax.set(i, LayoutVar.position_add(LayoutPosition.anchor_round(exit.x), $dx.get(i) ?? 0)) ?? []
			d = LayoutVar.position_add(LayoutPosition.anchor_round(entry.x), $dx.get(j) ?? 0)
			$ax = $ax.set(j, LayoutVar.position_sub($ax.get(j) ?? 0, d)) ?? []
			$dx = $dx.set(j, LayoutVar.position_sub($dx.get(j) ?? 0, d)) ?? []
		} else {
			d = LayoutVar.position_add(LayoutPosition.anchor_round(exit.x), $dx.get(i) ?? 0)
			$ax = $ax.set(i, LayoutVar.position_sub($ax.get(i) ?? 0, d)) ?? []
			$dx = $dx.set(i, LayoutVar.position_sub($dx.get(i) ?? 0, d)) ?? []
			$ax = $ax.set(j, LayoutVar.position_add(LayoutPosition.anchor_round(entry.x), $dx.get(j) ?? 0)) ?? []
		}
		child = if (props.bitwise_and(1) != 0) i else j
		parent = if (props.bitwise_and(1) != 0) j else i
		cross = if (props.bitwise_and(1) != 0) LayoutPosition.anchor_difference(entry.y, exit.y) else LayoutVar.position_neg(LayoutPosition.anchor_difference(entry.y, exit.y))
		# Re-root the old cursive chain iteratively before adding the edge.
		var $parents = parents
		var $attachments = attachments
		var $dy = dy
		var $chain = child
		var $edges = []
		var $walking = True
		var $remaining = items.len().min(65)
		while $walking and $remaining > 0 {
			$remaining = $remaining - 1
			old_parent = $parents.get($chain) ?? 0
			if old_parent == 0 or ($attachments.get($chain) ?? 0) != 2 {
				$walking = False
			}
			else {
				$parents = $parents.set($chain, 0) ?? []
				if old_parent - 1 == parent or !LayoutPosition.attachable(old_parent - 1, $chain) {
					$walking = False
				}
				else {
					$edges = $edges.append({ child: $chain, parent: old_parent - 1 })
					$chain = old_parent - 1
				}
			}
		}
		var $e = $edges.len()
		while $e > 0 {
			$e = $e - 1
			edge = $edges.get($e) ?? { child, parent }
			$dy = $dy.set(edge.parent, LayoutVar.position_neg($dy.get(edge.child) ?? 0)) ?? []
			$parents = $parents.set(edge.parent, edge.child + 1) ?? []
			$attachments = $attachments.set(edge.parent, 2) ?? []
		}
		if !LayoutPosition.attachable(child, parent) {
			return { state: { items: LayoutPosition.flag(items, i, j + 1), ax: $ax, dx: $dx, dy: $dy, parents: $parents.set(child, 0) ?? [], attachments: $attachments, stopped, operations }, next: j + 1, applied: True, calls: NoCalls }
		}
		$dy = $dy.set(child, cross) ?? []
		$parents = $parents.set(child, parent + 1) ?? []
		$attachments = $attachments.set(child, 2) ?? []
		if ($parents.get(parent) ?? 0) == child + 1 {
			$parents = $parents.set(parent, 0) ?? []
			$dy = $dy.set(parent, 0) ?? []
		}
		s = { items: LayoutPosition.flag(items, i, j + 1), ax: $ax, dx: $dx, dy: $dy, parents: $parents, attachments: $attachments, stopped, operations }
		{ state: s, next: j + 1, applied: True, calls: NoCalls }
	}

	cross_offset : State, U64 -> I64
	cross_offset = |state, start| {
		var $at = start
		var $offset = state.dy.get(start) ?? 0
		var $remaining = state.items.len()
		var $walking = True
		while $walking and $remaining > 0 and (state.attachments.get($at) ?? 0) == 2 {
			$remaining = $remaining - 1
			parent = state.parents.get($at) ?? 0
			if parent == 0 or parent > state.items.len() {
				$walking = False
			}
			else {
				$at = parent - 1
				$offset = LayoutVar.position_add($offset, state.dy.get($at) ?? 0)
			}
		}
		$offset
	}

	## Propagate the advance-direction offsets after all lookups and mark
	## zeroing. Cross offsets of marks are captured when they attach, while
	## cursive cross offsets follow their parent at the end. Prefix sums make
	## distances constant time; iterative traversal follows the reference nesting cap.
	resolve : State, Bool -> State
	resolve = |state, backward| {
		{ items, ax, dx, dy, parents, attachments, stopped, operations } = state
		count = items.len()
		var $prefix = List.with_capacity(count + 1).append(0.I128)
		var $sum = 0.I128
		var $positive = False
		var $negative = False
		for advance in ax {
			$sum = $sum + advance.to_i128()
			$positive = $positive or advance > 0
			$negative = $negative or advance < 0
			$prefix = $prefix.append($sum)
		}
		mixed = $positive and $negative
		ranges = if (mixed) PositionSum.make(ax) else PositionSum.make([])
		var $parents = parents
		var $dx = dx
		var $dy = dy
		var $path = List.with_capacity(count.min(64))
		for index in 0..<count {
			# HarfBuzz visits RTL buffers backwards. Each root gets 64
			# propagating frames; the 65th call clears its edge and returns.
			i = if (backward) count - 1 - index else index
			$path = $path.clear()
			var $at = i
			var $left = 64
			var $walk = ($parents.get($at) ?? 0) != 0
			while $walk {
				parent = $parents.get($at) ?? 0
				$parents = $parents.set($at, 0) ?? []
				if parent == 0 or parent > count or $left == 0 {
					$walk = False
				} else {
					$path = $path.append({ child: $at, parent: parent - 1 })
					$at = parent - 1
					$left = $left - 1
					$walk = ($parents.get($at) ?? 0) != 0
				}
			}
			while !$path.is_empty() {
				edge = $path.last() ?? { child: 0, parent: 0 }
				$path = $path.drop_last(1)
				j = edge.child
				k = edge.parent
				if (attachments.get(j) ?? 0) == 2 {
					$dy = $dy.set(j, LayoutVar.position_add($dy.get(j) ?? 0, $dy.get(k) ?? 0)) ?? []
				}
				if (attachments.get(j) ?? 0) == 1 {
					start = (j.min(k)) + (if (backward) 1 else 0)
					end = (j.max(k)) + (if (backward) 1 else 0)
					subtract = if (k < j) !backward else backward
					initial = LayoutVar.position_add($dx.get(j) ?? 0, $dx.get(k) ?? 0)
					resolved = if mixed {
						PositionSum.apply(ranges, start, end, initial, subtract)
					} else {
						distance = ($prefix.get(end) ?? 0) - ($prefix.get(start) ?? 0)
						total = initial.to_i128() + (if (subtract) -distance else distance)
						total.max(-2147483648).min(2147483647).to_i64_wrap()
					}
					$dx = $dx.set(j, resolved) ?? []
				}
			}
		}
		{ items, ax, dx: $dx, dy: $dy, parents: $parents, attachments, stopped, operations }
	}

	flag : List(LayoutGsub.Item), U64, U64 -> List(LayoutGsub.Item)
	flag = |items, start, end| {
		# hb_buffer_t::_set_glyph_flags checks the raw span before clamping.
		if end < start or end - start > 255 {
			items
		}
		else {
			LayoutGsub.flag_range(items, start, end.min(items.len()), LayoutGsub.min_cluster(items, start, end.min(items.len()), 0xFFFFFFFFFFFFFFFF))
		}
	}

	covered : List(U8), U64, U64 -> Try(U64, [NotCovered])
	covered = |data, at, glyph| {
		var $low = 0
		var $high = Bytes.u16(data, at + 2)
		while $low < $high {
			mid = ($low + $high) // 2
			if Bytes.u16(data, at) == 1 {
				probe = Bytes.u16(data, at + 4 + 2 * mid)
				if glyph < probe {
					$high = mid
				} else if glyph > probe {
					$low = mid + 1
				} else {
					return Ok(mid)
				}
			} else {
				r = at + 4 + 6 * mid
				if glyph < Bytes.u16(data, r) {
					$high = mid
				}
				else if glyph > Bytes.u16(data, r + 2) {
					$low = mid + 1
				}
				else {
					return Ok(Bytes.u16(data, r + 4) + glyph - Bytes.u16(data, r))
				}
			}
		}
		Err(NotCovered)
	}

	class_of : List(U8), U64, U64 -> U64
	class_of = |data, at, glyph| {
		if Bytes.u16(data, at) == 1 {
			start = Bytes.u16(data, at + 2)
			if glyph >= start and glyph - start < Bytes.u16(data, at + 4) {
				Bytes.u16(data, at + 6 + 2 * (glyph - start))
			} else {
				0
			}
		} else {
			var $low = 0
			var $high = Bytes.u16(data, at + 2)
			while $low < $high {
				mid = ($low + $high) // 2
				r = at + 4 + 6 * mid
				if glyph < Bytes.u16(data, r) {
					$high = mid
				}
				else if glyph > Bytes.u16(data, r + 2) {
					$low = mid + 1
				}
				else {
					return Bytes.u16(data, r + 4)
				}
			}
			0
		}
	}
}

# The65th nested propagation call detaches without inheriting offsets.
# Both directions visit roots in their native order; RTL exposes the cap.
expect {
	[64.U64, 65, 66, 129].all(
		|count| {
			state = { items: List.repeat(LayoutGsub.no_item, count), ax: List.repeat(0.I64, count), dx: List.repeat(0.I64, count).set(0, 13) ?? [], dy: List.repeat(0.I64, count), parents: List.repeat(0.U64, count).map_with_index(|_x, i| i), attachments: List.repeat(1.U8, count), stopped: 0, operations: 0 }
			placed = LayoutPosition.resolve(state, True)
			(placed.dx.last() ?? 0) == (if (count <= 65) 13 else 0) and placed.parents.all(|p| p == 0)
		},
	)
}

# Binary32 anchor arithmetic precedes the half-up position conversion.
expect LayoutPosition.anchor_coordinate(1, 16777216) == 16777216 and LayoutPosition.anchor_difference(LayoutPosition.anchor_coordinate(1, 16777216), LayoutPosition.anchor_coordinate(0, 16777216)) == 0
expect LayoutPosition.anchor_round(8388609) == 8388610 and LayoutPosition.anchor_round(-8388609) == -8388608
expect LayoutPosition.attachable(32768, 0) and !LayoutPosition.attachable(32769, 0) and LayoutPosition.attachable(0, 32767) and !LayoutPosition.attachable(0, 32768)
