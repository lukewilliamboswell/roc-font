import GraphiteSlots
import TableVar

## Convert associated Graphite slots into the package's aligned integer run.
## Association groups determine advances; glyph offsets retain their actual
## font-program positions. A final reverse preserves order inside a cluster.
GraphiteRun :: {}.{
	Run : { glyphs : List(U32), advances : List({ x : I32, y : I32 }), offsets : List({ x : I32, y : I32 }), clusters : List(U64), flags : List(U8) }
	Origin : [Nominal, Substituted, Inserted]
	Result : { run : Run, origins : List(Origin), valid : Bool }
	Group : { char_start : U64, char_count : U64, glyph_start : U64, glyph_count : U64, advance : I32 }
	Row : { glyph : U32, cluster : U64, group : U64, advance_x : I32, advance_y : I32, offset_x : I32, offset_y : I32, trace : U8, missing : Bool }
	empty : Result
	empty = { run: { glyphs: [], advances: [], offsets: [], clusters: [], flags: [] }, origins: [], valid: True }

	finish : GraphiteSlots, List({ scalar : U32, offset : U64 }), Bool, Bool, (U64 -> U32) -> Result
	finish = |state, scalars, rtl, trace, glyph_id| {
		if state.active == 0 {
			return GraphiteRun.empty
		}
		if scalars.is_empty() {
			return { ..GraphiteRun.empty, valid: False }
		}
		var $slots = List.with_capacity(state.active)
		var $id = state.first
		while $id != 0 {
			s = GraphiteSlots.get(state, $id)
			if s.before < 0 or s.after < s.before or s.after.to_u64_wrap() >= scalars.len() {
				return { ..GraphiteRun.empty, valid: False }
			}
			$slots = $slots.append(s)
			$id = s.next
		}
		first = $slots.first() ?? crash "nonempty active slot chain"
		var $current = if (rtl) GraphiteSlots.integer(first.position_x) else 0
		var $groups = [{ char_start: 0, char_count: 0, glyph_start: 0, glyph_count: 0, advance: if (rtl) GraphiteRun.offset(state.advance_x, 0 - $current.to_i64()) else 0 }]
		var $raw_clusters = List.with_capacity($slots.len())
		for i in 0..<$slots.len() {
			s = $slots.get(i) ?? GraphiteSlots.no_slot
			before = s.before.to_u64_wrap()
			after = s.after.to_u64_wrap()
			a = (scalars.get(before) ?? crash "checked association").offset
			b = (scalars.get(after) ?? crash "checked association").offset
			$raw_clusters = $raw_clusters.append(a.min(b))
			while $groups.len() > 1 and ($groups.last() ?? GraphiteRun.no_group).char_start > before {
				last = $groups.last() ?? GraphiteRun.no_group
				$groups = $groups.drop_last(1)
				prior = $groups.last() ?? GraphiteRun.no_group
				$groups = $groups.set($groups.len() - 1, { ..prior, char_count: prior.char_count + last.char_count, glyph_count: prior.glyph_count + last.glyph_count, advance: GraphiteRun.sat(prior.advance.to_i64() + last.advance.to_i64()) }) ?? []
			}
			g = $groups.last() ?? GraphiteRun.no_group
			if s.insert_before and g.char_count != 0 and before >= g.char_start + g.char_count {
				start = g.char_start + g.char_count
				var $advance = 0
				if rtl {
					$advance = GraphiteRun.offset(s.position_x.bitwise_xor(0x80000000), $current.to_i64())
					$current = GraphiteRun.sat($current.to_i64() - $advance.to_i64())
				} else {
					origin = GraphiteSlots.integer(s.position_x)
					increment = GraphiteRun.sat(origin.to_i64() - $current.to_i64())
					$groups = $groups.set($groups.len() - 1, { ..g, advance: GraphiteRun.sat(g.advance.to_i64() + increment.to_i64()) }) ?? []
					$current = origin
				}
				$groups = $groups.append({ char_start: start, char_count: before - start, glyph_start: i, glyph_count: 0, advance: $advance })
			}
			last = $groups.last() ?? GraphiteRun.no_group
			$groups = $groups.set($groups.len() - 1, { ..last, glyph_count: last.glyph_count + 1, char_count: last.char_count.max(after + 1 - last.char_start) }) ?? []
		}
		last = $groups.last() ?? GraphiteRun.no_group
		last_advance = if (rtl) GraphiteRun.sat(last.advance.to_i64() + $current.to_i64()) else GraphiteRun.offset(state.advance_x, last.advance.to_i64() - $current.to_i64())
		$groups = $groups.set($groups.len() - 1, { ..last, advance: last_advance }) ?? []
		var $rows = List.with_capacity($slots.len())
		var $pen_x = if (rtl) GraphiteSlots.integer(state.advance_x) else 0
		var $pen_y = 0.I32
		var $minimum = 0xFFFFFFFFFFFFFFFF.U64
		for group in $groups {
			var $cluster = 0xFFFFFFFFFFFFFFFF.U64
			for i in group.glyph_start..<(group.glyph_start + group.glyph_count) {
				$cluster = $cluster.min($raw_clusters.get(i) ?? 0)
			}
			$minimum = $minimum.min($cluster)
			for i in group.glyph_start..<(group.glyph_start + group.glyph_count) {
				s = $slots.get(i) ?? GraphiteSlots.no_slot
				advance_x = if (i == group.glyph_start) group.advance else 0
				advance_y = GraphiteSlots.integer(s.advance_y)
				if rtl {
					$pen_x = GraphiteRun.sat($pen_x.to_i64() - advance_x.to_i64())
					$pen_y = GraphiteRun.sat($pen_y.to_i64() - advance_y.to_i64())
				}
				delta_x = if (rtl) 0 - group.advance.to_i64() - $pen_x.to_i64() + advance_x.to_i64() else 0 - $pen_x.to_i64()
				$rows = $rows.append({ glyph: glyph_id(s.glyph), cluster: $cluster, group: group.glyph_start, advance_x, advance_y, offset_x: GraphiteRun.offset(s.position_x, delta_x), offset_y: GraphiteRun.offset(s.position_y, 0 - $pen_y.to_i64()), trace: s.trace, missing: s.missing })
				if !rtl {
					$pen_x = GraphiteRun.sat($pen_x.to_i64() + advance_x.to_i64())
					$pen_y = GraphiteRun.sat($pen_y.to_i64() + advance_y.to_i64())
				}
			}
		}
		var $order = List.with_capacity($rows.len())
		if rtl {
			var $end = $rows.len()
			while $end != 0 {
				cluster = ($rows.get($end - 1) ?? GraphiteRun.no_row).cluster
				var $start = $end - 1
				while $start > 0 and ($rows.get($start - 1) ?? GraphiteRun.no_row).cluster == cluster {
					$start = $start - 1
				}
				for i in $start..<$end {
					$order = $order.append(i)
				}
				$end = $start
			}
		} else {
			for i in 0..<$rows.len() {
				$order = $order.append(i)
			}
		}
		var $glyphs = List.with_capacity($rows.len())
		var $advances = List.with_capacity($rows.len())
		var $offsets = List.with_capacity($rows.len())
		var $clusters = List.with_capacity($rows.len())
		var $flags = List.with_capacity($rows.len())
		var $origins = if (trace) List.with_capacity($rows.len()) else []
		for index in $order {
			row = $rows.get(index) ?? GraphiteRun.no_row
			$glyphs = $glyphs.append(row.glyph)
			$advances = $advances.append({ x: row.advance_x, y: row.advance_y })
			$offsets = $offsets.append({ x: row.offset_x, y: row.offset_y })
			$clusters = $clusters.append(row.cluster)
			$flags = $flags.append((if (row.cluster == $minimum) 0.U8 else 1).bitwise_or(if (row.missing and row.glyph == 0) 2 else 0))
			if trace {
				$origins = $origins.append(if (row.trace == 2) Inserted else if (row.trace == 1) Substituted else Nominal)
			}
		}
		{ run: { glyphs: $glyphs, advances: $advances, offsets: $offsets, clusters: $clusters, flags: $flags }, origins: $origins, valid: True }
	}

	# Binary32 is exactly representable in double. Adding an integer pen
	# therefore needs no intermediate binary32 rounding. Separate its floor
	# and fractional bit before integer translation and truncation.
	offset : U32, I64 -> I32
	offset = |bits, delta| {
		floor = TableVar.f32_floor(bits)
		whole = floor + delta
		fraction = TableVar.f32_from_int(floor) != bits and bits.bitwise_and(0x7FFFFFFF) != 0
		GraphiteRun.sat(if (whole < 0 and fraction) whole + 1 else whole)
	}

	sat : I64 -> I32
	sat = |value| value.max(-2147483648).min(2147483647).to_i32_wrap()
	no_group : Group
	no_group = { char_start: 0, char_count: 0, glyph_start: 0, glyph_count: 0, advance: 0 }
	no_row : Row
	no_row = { glyph: 0, cluster: 0, group: 0, advance_x: 0, advance_y: 0, offset_x: 0, offset_y: 0, trace: 0, missing: False }
}

expect GraphiteRun.offset(0x3F000000, -1) == 0 and GraphiteRun.offset(0xBF000000, 1) == 0 and GraphiteRun.offset(0x4EFFFFFF, -2147483647) == -127
expect {
	a = GraphiteSlots.append(GraphiteSlots.make(0, 2), { ..GraphiteSlots.no_slot, glyph: 1, position_x: 0 })
	b = GraphiteSlots.append(a.state, { ..GraphiteSlots.no_slot, glyph: 2, before: 1, after: 1, position_x: TableVar.f32_from_int(601), trace: 1 })
	state = { ..b.state, advance_x: TableVar.f32_from_int(1203) }
	run = GraphiteRun.finish(state, [{ scalar: 97, offset: 0 }, { scalar: 98, offset: 1 }], False, True, |glyph| glyph.to_u32_wrap())
	run.valid and run.run.advances == [{ x: 601, y: 0 }, { x: 602, y: 0 }] and run.run.offsets == [{ x: 0, y: 0 }, { x: 0, y: 0 }] and run.run.flags == [0, 1] and run.origins == [Nominal, Substituted]
}
expect {
	a = GraphiteSlots.append(GraphiteSlots.make(0, 2), { ..GraphiteSlots.no_slot, glyph: 1, position_x: TableVar.f32_from_int(602) })
	b = GraphiteSlots.append(a.state, { ..GraphiteSlots.no_slot, glyph: 2, before: 1, after: 1 })
	state = { ..b.state, advance_x: TableVar.f32_from_int(1203) }
	run = GraphiteRun.finish(state, [{ scalar: 97, offset: 0 }, { scalar: 98, offset: 1 }], True, False, |glyph| glyph.to_u32_wrap())
	run.valid and run.run.glyphs == [2, 1] and run.run.advances == [{ x: 602, y: 0 }, { x: 601, y: 0 }] and run.run.offsets == [{ x: 0, y: 0 }, { x: 0, y: 0 }] and run.origins.is_empty()
}
