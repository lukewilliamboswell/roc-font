import Bytes
import Face
import GraphiteAttributes
import GraphiteSilf
import GraphiteFeatures
import GraphiteSlots
import GraphiteMachine
import GraphiteRules
import GraphiteMetrics
import GraphitePosition
import GraphiteCollision
import GraphiteRun
import TableVar
import TableGraphite

## Prepared numeric features and direction policy for a Graphite program.
## Text and surrounding style runs remain per-call inputs. The runtime
## uses the font program's positions without an additional OpenType pass.
ShaperGraphite := {
	defaults : List(U16),
	subtable : U64,
	rtl : Bool,
	reverse_input : Bool,
	growth : U64,
	operations : U64,
}.{
	Options : { language : Str, features : List({ id : U32, value : I16 }), direction : [Ltr, Rtl, Ttb, Btt], native : [Ltr, Rtl, Either], growth : U64, operations : U64 }

	make : TableGraphite, Options -> ShaperGraphite
	make = |table, options| {
		horizontal = options.direction == Ltr or options.direction == Rtl
		requested_rtl = options.direction == Rtl
		reverse_input = if (horizontal) match options.native {
			Ltr => requested_rtl
			Rtl => !requested_rtl
			Either => False
		} else options.direction == Btt
		rtl = horizontal and (if (reverse_input) !requested_rtl else requested_rtl)
		{ defaults: GraphiteFeatures.resolve(table.features, ShaperGraphite.language(options.language), options.features), subtable: 0, rtl, reverse_input, growth: options.growth, operations: options.operations }
	}

	Result : { run : GraphiteRun.Run, origins : List(GraphiteRun.Origin), stopped : U64, operations : U64, abort : [NoAbort, ProgramAbort] }

	shape : Face, ShaperGraphite, List({ scalar : U32, offset : U64 }), Bool -> Result
	shape = |face, plan, scalars, trace| ShaperGraphite.execute(face, plan, scalars, trace, GraphiteCollision.collisions)

	# The collision phase is an explicit pure dependency. The public
	# dispatcher supplies the complete font-program collision executor;
	# all phases share this call's remaining work budget.
	execute : Face, ShaperGraphite, List({ scalar : U32, offset : U64 }), Bool, (GraphiteSlots, GraphiteCollision.Context, U64, U64, U64, (U64, U64, I32 -> I32) -> GraphiteCollision.Applied) -> Result
	execute = |face, plan, original, trace, collisions| {
		if original.is_empty() {
			return { run: GraphiteRun.empty.run, origins: [], stopped: 0, operations: 0, abort: NoAbort }
		}
		sub = face.graphite.program.subtables.get(plan.subtable) ?? return { run: GraphiteRun.empty.run, origins: [], stopped: 0, operations: 0, abort: NoAbort }
		scalars = if (plan.reverse_input) ShaperGraphite.reverse_clusters(original) else original
		limit = ShaperGraphite.bound(plan.growth, scalars.len())
		budget = ShaperGraphite.bound(plan.operations, scalars.len())
		context = { table: face.graphite, sub, defaults: plan.defaults, rtl: plan.rtl, reverse: False }
		collision_context = { table: face.graphite, sub, rtl: plan.rtl }
		metrics = GraphiteMetrics.make(face)
		metric = |glyph, wanted, level| GraphiteMetrics.get(metrics, GraphiteMachine.real(context, glyph), wanted, level)
		var $state = GraphiteSlots.make_with_levels(sub.user_count, sub.justification_count, scalars.len())
		var $operations = 0
		var $stopped = 0
		for i in 0..<scalars.len() {
			c = scalars.get(i) ?? crash "input character span"
			mapped = match Face.glyph(face, c.scalar) {
				Ok(glyph) => { glyph, missing: False }
				Err(_) => match GraphiteSilf.pseudo(face.graphite.program, sub, c.scalar) {
					Found(glyph) => { glyph, missing: False }
					Missing => { glyph: 0, missing: True }
				}
			}
			cell = GraphiteSlots.new_feature($state)
			added = GraphiteSlots.append(cell.state, { ..GraphiteSlots.no_slot, feature: cell.id, glyph: mapped.glyph, missing: mapped.missing, before: i.to_i64_wrap(), after: i.to_i64_wrap(), original: i.to_i64_wrap(), advance_x: TableVar.f32_from_int(metric(mapped.glyph, 8, 0).to_i64()), advance_y: TableVar.f32_from_int(metric(mapped.glyph, 9, 0).to_i64()), break_weight: GraphiteAttributes.get(face.graphite.attributes, mapped.glyph, sub.break_attribute).to_i8_wrap().to_i32() })
			$state = added.state
		}
		if scalars.len() > limit {
			$stopped = 1
		}
		var $mirrored = !plan.rtl
		if !$mirrored and sub.bidi == 255 {
			changed = ShaperGraphite.mirror($state, face.graphite.attributes, sub.mirror_attribute, budget - $operations, metric)
			$state = changed.state
			$operations = $operations + changed.operations
			$stopped = $stopped.bitwise_or(changed.stopped)
			$mirrored = True
		}
		var $prepared_collision = sub.flags.bitwise_and(32) == 0
		for index in sub.pass_start..<sub.pass_end {
			if $stopped != 0 {
				break
			}
			if !$mirrored and index == sub.pass_start + sub.bidi {
				changed = ShaperGraphite.mirror($state, face.graphite.attributes, sub.mirror_attribute, budget - $operations, metric)
				$state = changed.state
				$operations = $operations + changed.operations
				$stopped = $stopped.bitwise_or(changed.stopped)
				$mirrored = True
			}
			if !$prepared_collision and index == sub.pass_start + sub.positioning {
				prepared = GraphiteCollision.prepare($state, collision_context, budget - $operations)
				$state = prepared.state
				$operations = $operations + prepared.operations
				$stopped = $stopped.bitwise_or(prepared.stopped)
				$prepared_collision = True
			}
			if $stopped == 0 {
				pass = face.graphite.program.passes.get(index) ?? crash "selected prepared pass span"
				native_rtl = sub.direction.bitwise_and(1) == 0
				reverse = (plan.rtl != native_rtl) != (pass.flags.bitwise_and(32) != 0)
				changed = GraphiteRules.apply({ ..context, reverse }, pass, $state, { operations: budget - $operations, glyphs: limit }, metric)
				$state = changed.state
				$operations = $operations + changed.operations
				$stopped = $stopped.bitwise_or(changed.stopped)
				if changed.aborted {
					return { run: GraphiteRun.empty.run, origins: [], stopped: $stopped, operations: $operations, abort: ProgramAbort }
				}
				if $stopped == 0 and pass.flags.bitwise_and(31) != 0 {
					fixed = collisions($state, collision_context, pass.flags, pass.collision_threshold, budget - $operations, metric)
					$state = fixed.state
					$operations = $operations + fixed.operations
					$stopped = $stopped.bitwise_or(fixed.stopped)
				}
			}
		}
		if !$mirrored and $stopped == 0 {
			changed = ShaperGraphite.mirror($state, face.graphite.attributes, sub.mirror_attribute, budget - $operations, metric)
			$state = changed.state
			$operations = $operations + changed.operations
			$stopped = $stopped.bitwise_or(changed.stopped)
		}
		if !$prepared_collision and $stopped == 0 {
			prepared = GraphiteCollision.prepare($state, collision_context, budget - $operations)
			$state = prepared.state
			$operations = $operations + prepared.operations
			$stopped = $stopped.bitwise_or(prepared.stopped)
		}
		placed = GraphitePosition.position($state, plan.rtl, budget - $operations)
		$operations = $operations + placed.operations
		$stopped = $stopped.bitwise_or(placed.stopped)
		finished = GraphiteRun.finish(placed.state, scalars, plan.rtl, trace, |glyph| GraphiteMachine.real(context, glyph).to_u32_wrap())
		{ run: finished.run, origins: finished.origins, stopped: $stopped, operations: $operations, abort: if (finished.valid) NoAbort else ProgramAbort }
	}

	mirror : GraphiteSlots, GraphiteAttributes, U64, U64, (U64, U64, I32 -> I32) -> GraphitePosition.Applied
	mirror = |state, attributes, attribute, budget, metric| {
		var $state = state
		var $id = state.first
		var $operations = 0
		while $id != 0 {
			if $operations >= budget {
				return { state: $state, operations: $operations, stopped: 2 }
			}
			$operations = $operations + 1
			slot = GraphiteSlots.get($state, $id)
			glyph = GraphiteAttributes.get(attributes, slot.glyph, attribute).to_u16_wrap().to_u64()
			if glyph != 0 {
				$state = GraphiteSlots.set({ ..$state, positioned: False }, $id, { ..slot, glyph, missing: False, advance_x: TableVar.f32_from_int(metric(glyph, 8, 0).to_i64()), advance_y: TableVar.f32_from_int(metric(glyph, 9, 0).to_i64()), trace: if (slot.trace == 2) 2 else 1 })
			}
			$id = slot.next
		}
		{ state: $state, operations: $operations, stopped: 0 }
	}

	bound : U64, U64 -> U64
	bound = |factor, count| (factor.to_u128() * count.to_u128()).min(18446744073709551615).to_u64_wrap().max(65536)

	reverse_clusters : List({ scalar : U32, offset : U64 }) -> List({ scalar : U32, offset : U64 })
	reverse_clusters = |scalars| {
		var $out = List.with_capacity(scalars.len())
		var $end = scalars.len()
		while $end != 0 {
			cluster = (scalars.get($end - 1) ?? crash "nonempty cluster").offset
			var $start = $end - 1
			while $start > 0 and (scalars.get($start - 1) ?? crash "character span").offset == cluster {
				$start = $start - 1
			}
			for i in $start..<$end {
				$out = $out.append(scalars.get(i) ?? crash "character span")
			}
			$end = $start
		}
		$out
	}

	# HarfBuzz passes the primary BCP47 subtag, without ISO639 conversion.
	# Graphite's Sill keys use NULL padding and ignore trailing tag spaces.
	language : Str -> U32
	language = |language| {
		var $tag = 0.U32
		var $n = 0
		for byte in language.to_utf8() {
			if byte == 45 or byte == 95 or $n == 4 {
				break
			}
			lower = if (byte >= 65 and byte <= 90) byte + 32 else byte
			if !((lower >= 97 and lower <= 122) or (lower >= 48 and lower <= 57)) {
				break
			}
			$tag = $tag.bitwise_or(lower.to_u32().shl_wrap((24 - 8 * $n).to_u8_wrap()))
			$n = $n + 1
		}
		$tag
	}
}

expect ShaperGraphite.language("ksw-MM") == 0x6B737700 and ShaperGraphite.language("VI-vn") == 0x76690000 and ShaperGraphite.language("") == 0
expect {
	options = { language: "", features: [], direction: Rtl, native: Ltr, growth: 256, operations: 4096 }
	a = ShaperGraphite.make(TableGraphite.none, options)
	b = ShaperGraphite.make(TableGraphite.none, { ..options, native: Rtl })
	c = ShaperGraphite.make(TableGraphite.none, { ..options, direction: Btt })
	a.reverse_input and !a.rtl and !b.reverse_input and b.rtl and c.reverse_input and !c.rtl
}
