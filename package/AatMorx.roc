#
# Copyright © 2017  Google, Inc.
#
#  This is part of HarfBuzz, a text shaping library.
#
# Permission is hereby granted, without written agreement and without
# license or royalty fees, to use, copy, modify, and distribute this
# software and its documentation for any purpose, provided that the
# above copyright notice and the following two paragraphs appear in
# all copies of this software.
#
# IN NO EVENT SHALL THE COPYRIGHT HOLDER BE LIABLE TO ANY PARTY FOR
# DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES
# ARISING OUT OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN
# IF THE COPYRIGHT HOLDER HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH
# DAMAGE.
#
# THE COPYRIGHT HOLDER SPECIFICALLY DISCLAIMS ANY WARRANTIES, INCLUDING,
# BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
# FITNESS FOR A PARTICULAR PURPOSE.  THE SOFTWARE PROVIDED HEREUNDER IS
# ON AN "AS IS" BASIS, AND THE COPYRIGHT HOLDER HAS NO OBLIGATION TO
# PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS.
#
# Google Author(s): Behdad Esfahbod
#

import Bytes
import AatLookup
import AatState
import LayoutGsub
import ShaperUnicode
import Sorted

## Checked extended Apple glyph metamorphosis chains. Internal. Table
## programs are bounded by the caller's shaping work and glyph budgets.
AatMorx := { chains : List(Chain), features : List(Feature), subtables : List(Subtable) }.{

	Feature : { type : U64, setting : U64, enable : U64, disable : U64 }
	Chain : { flags : U64, feature_start : U64, feature_count : U64, sub_start : U64, sub_count : U64 }
	Subtable : { coverage : U64, flags : U64, body : Body }
	Body : [Rearrange(AatState), Contextual({ machine : AatState, lookups : List(AatLookup), legacy_zero_missing : Bool }), Noncontextual(AatLookup), Insertion({ machine : AatState, glyphs : List(U32) }), Ligature(Ligatures)]
	Ligatures : { machine : AatState, actions : List(U32), components : List(U16), glyphs : List(U16), glyph_count : U64, legacy : Bool, component_base : U64, glyph_base : U64 }
	Requested : { type : U64, setting : U64, start : U64, end : U64, exclusive : Bool }
	RangeFlags : { first : U64, last : U64, flags : U64 }
	Plan : { spans : List({ start : U64, count : U64 }), ranges : List(RangeFlags) }
	FlagsContext : { ranges : List(RangeFlags), start : U64, count : U64, fallback : U64, subflags : U64 }
	Applied : { items : List(LayoutGsub.Item), operations : U64, stopped : U64 }

	none : AatMorx
	none = { chains: [], features: [], subtables: [] }

	read : List(U8), U64 -> Try(AatMorx, [Bad(U64)])
	read = |bytes, glyphs| {
		if bytes.len() < 8 {
			return Err(Bad(0))
		}
		version = Bytes.u32(bytes, 0)
		if version != 0x00020000 and version != 0x00030000 {
			return Err(Bad(0))
		}
		count = Bytes.u32(bytes, 4)
		if count > (bytes.len() - 8) // 16 {
			return Err(Bad(4))
		}
		var $at = 8
		var $chains = List.with_capacity(count)
		var $features = []
		var $subtables = []
		for _ in 0..<count {
			if !Bytes.fits($at, 16, bytes.len()) {
				return Err(Bad($at))
			}
			length = Bytes.u32(bytes, $at + 4)
			features = Bytes.u32(bytes, $at + 8)
			subtables = Bytes.u32(bytes, $at + 12)
			if length < 16 or !Bytes.fits($at, length, bytes.len()) or features > (length - 16) // 12 {
				return Err(Bad($at + 4))
			}
			end = $at + length
			var $sub = $at + 16 + features * 12
			if subtables > (end - $sub) // 12 {
				return Err(Bad($at + 12))
			}
			chain = { flags: Bytes.u32(bytes, $at), feature_start: $features.len(), feature_count: features, sub_start: $subtables.len(), sub_count: subtables }
			for i in 0..<features {
				f = $at + 16 + i * 12
				$features = $features.append({ type: Bytes.u16(bytes, f), setting: Bytes.u16(bytes, f + 2), enable: Bytes.u32(bytes, f + 4), disable: Bytes.u32(bytes, f + 8) })
			}
			for _ in 0..<subtables {
				if !Bytes.fits($sub, 12, end) {
					return Err(Bad($sub))
				}
				len = Bytes.u32(bytes, $sub)
				coverage = Bytes.u32(bytes, $sub + 4)
				if len < 12 or !Bytes.fits($sub, len, end) {
					return Err(Bad($sub))
				}
				data = bytes.sublist({ start: $sub + 12, len: len - 12 })
				body = AatMorx.read_body(data, glyphs, coverage.bitwise_and(255)).map_err(
					|problem| match problem {
						Bad(offset) => Bad($sub + 12 + offset)
					},
				)?
				$subtables = $subtables.append({ coverage, flags: Bytes.u32(bytes, $sub + 8), body })
				$sub = $sub + len
			}
			if version == 0x00030000 {
				# Version 3 appends one optional glyph-coverage bitset offset
				# per subtable. These accelerate lookup only; validate all spans.
				if !Bytes.fits($sub, subtables * 4, end) {
					return Err(Bad($sub))
				}
				for i in 0..<subtables {
					offset = Bytes.u32(bytes, $sub + i * 4)
					if offset != 0 and !Bytes.fits($sub + offset, (glyphs + 7) // 8, end) {
						return Err(Bad($sub + i * 4))
					}
				}
			}
			$chains = $chains.append(chain)
			$at = end
		}
		Ok({ chains: $chains, features: $features, subtables: $subtables })
	}

	read_body : List(U8), U64, U64 -> Try(Body, [Bad(U64)])
	read_body = |bytes, glyphs, kind| {
		if kind == 4 {
			lookup = AatLookup.read(bytes, 0, glyphs, 2)?
			AatMorx.check_substitutions(lookup, glyphs)?
			return Ok(Noncontextual(lookup))
		}
		if kind == 0 {
			return Ok(Rearrange(AatState.read(bytes, 0, glyphs, 0)?))
		}
		if kind == 2 {
			machine = AatState.read(bytes, 0, glyphs, 1)?
			if bytes.len() < 28 {
				return Err(Bad(16))
			}
			action_at = Bytes.u32(bytes, 16)
			component_at = Bytes.u32(bytes, 20)
			glyph_at = Bytes.u32(bytes, 24)
			if !Bytes.fits(action_at, 4, bytes.len()) or !Bytes.fits(component_at, 2, bytes.len()) or !Bytes.fits(glyph_at, 2, bytes.len()) {
				return Err(Bad(16))
			}
			# Compute terminating suffixes once, so many entries sharing a
			# long action stream cannot make preparation quadratic.
			words = (bytes.len() - action_at) // 4
			var $ends = List.repeat(0.U64, words)
			var $terminal = 0
			for i in 0..<words {
				index = words - 1 - i
				if Bytes.u32(bytes, action_at + index * 4).bitwise_and(0x80000000) != 0 {
					$terminal = index + 1
				}
				$ends = $ends.set(index, $terminal) ?? []
			}
			var $action_count = 0
			for e in AatState.entries(machine) {
				if e.flags.bitwise_and(0x2000) != 0 {
					end_index = $ends.get(e.a) ?? 0
					if end_index == 0 {
						return Err(Bad(action_at + e.a * 4))
					}
					$action_count = $action_count.max(end_index)
				}
			}
			var $actions = List.with_capacity($action_count)
			for i in 0..<$action_count {
				$actions = $actions.append(Bytes.u32(bytes, action_at + i * 4).to_u32_wrap())
			}
			var $components = List.with_capacity((bytes.len() - component_at) // 2)
			for i in 0..<((bytes.len() - component_at) // 2) {
				$components = $components.append(Bytes.u16(bytes, component_at + i * 2).to_u16_wrap())
			}
			var $glyphs = List.with_capacity((bytes.len() - glyph_at) // 2)
			for i in 0..<((bytes.len() - glyph_at) // 2) {
				$glyphs = $glyphs.append(Bytes.u16(bytes, glyph_at + i * 2).to_u16_wrap())
			}
			return Ok(Ligature({ machine, actions: $actions, components: $components, glyphs: $glyphs, glyph_count: glyphs, legacy: False, component_base: 0, glyph_base: 0 }))
		}
		if kind == 5 {
			machine = AatState.read(bytes, 0, glyphs, 2)?
			if bytes.len() < 20 {
				return Err(Bad(16))
			}
			at = Bytes.u32(bytes, 16)
			var $count = 0
			for e in AatState.entries(machine) {
				if e.a != 65535 {
					$count = $count.max(e.a + e.flags.shr_zf_wrap(5).bitwise_and(31))
				}
				if e.b != 65535 {
					$count = $count.max(e.b + e.flags.bitwise_and(31))
				}
			}
			if at == 0 or !Bytes.fits(at, $count * 2, bytes.len()) {
				return Err(Bad(16))
			}
			var $glyphs = List.with_capacity($count)
			for i in 0..<$count {
				g = Bytes.u16(bytes, at + i * 2)
				if g >= glyphs and g != 65535 {
					return Err(Bad(at + i * 2))
				}
				$glyphs = $glyphs.append(g.to_u32_wrap())
			}
			return Ok(Insertion({ machine, glyphs: $glyphs }))
		}
		if kind != 1 {
			return Err(Bad(0))
		}
		machine = AatState.read(bytes, 0, glyphs, 2)?
		if bytes.len() < 20 {
			return Err(Bad(16))
		}
		at = Bytes.u32(bytes, 16)
		var $count = 0
		for entry in AatState.entries(machine) {
			if entry.a != 65535 {
				$count = $count.max(entry.a + 1)
			}
			if entry.b != 65535 {
				$count = $count.max(entry.b + 1)
			}
		}
		if !Bytes.fits(at, $count * 4, bytes.len()) {
			return Err(Bad(16))
		}
		var $lookups = List.with_capacity($count)
		for i in 0..<$count {
			lookup_at = at + Bytes.u32(bytes, at + i * 4)
			lookup = AatLookup.read(bytes, lookup_at, glyphs, 2)?
			AatMorx.check_substitutions(lookup, glyphs)?
			$lookups = $lookups.append(lookup)
		}
		Ok(Contextual({ machine, lookups: $lookups, legacy_zero_missing: False }))
	}

	check_substitutions : AatLookup, U64 -> Try({}, [Bad(U64)])
	check_substitutions = |lookup, glyphs| {
		if (AatLookup.values_valid(lookup, glyphs, glyphs, True)) Ok({}) else Err(Bad(0))
	}

	## Feature choices are reusable work for the exact font and plan.
	## The common no-override path stores no additional range arrays.
	plan : AatMorx, List(Requested) -> Plan
	plan = |table, requested| AatMorx.plan_languages(table, requested, [])

	plan_languages : AatMorx, List(Requested), List(U64) -> Plan
	plan_languages = |table, requested, languages| {
		if requested.is_empty() and languages.is_empty() {
			return { spans: [], ranges: [] }
		}
		var $boundaries = [0.U64]
		for r in requested {
			$boundaries = $boundaries.append(r.start)
			if r.end != 0xFFFFFFFFFFFFFFFF {
				$boundaries = $boundaries.append(r.end)
			}
		}
		boundaries = Sorted.unique($boundaries)
		var $spans = List.with_capacity(table.chains.len())
		var $ranges = List.with_capacity(table.chains.len() * boundaries.len())
		for chain in table.chains {
			start = $ranges.len()
			for i in 0..<boundaries.len() {
				first = boundaries.get(i) ?? 0
				last = match boundaries.get(i + 1) {
					Ok(next) => next - 1
					Err(_) => 0xFFFFFFFFFFFFFFFF
				}
				$ranges = $ranges.append({ first, last, flags: AatMorx.flags_for(table, chain, requested, languages, first) })
			}
			$spans = $spans.append({ start, count: $ranges.len() - start })
		}
		{ spans: $spans, ranges: $ranges }
	}

	enabled : FlagsContext, U64 -> Bool
	enabled = |ctx, cluster| {
		if ctx.count == 0 {
			return ctx.fallback.bitwise_and(ctx.subflags) != 0
		}
		var $lo = ctx.start
		var $hi = ctx.start + ctx.count
		while $lo < $hi {
			mid = $lo + ($hi - $lo) // 2
			r = ctx.ranges.get(mid) ?? { first: 0, last: 0, flags: 0 }
			if cluster < r.first {
				$hi = mid
			} else if cluster > r.last {
				$lo = mid + 1
			} else {
				return r.flags.bitwise_and(ctx.subflags) != 0
			}
		}
		False
	}

	apply : AatMorx, List(LayoutGsub.Item), Plan, Bool, Bool, U64, U64 -> Applied
	apply = |table, items, selected, vertical, backward, budget, limit| {
		var $items = items
		var $operations = 0
		for chain_index in 0..<table.chains.len() {
			chain = table.chains.get(chain_index) ?? { flags: 0, feature_start: 0, feature_count: 0, sub_start: 0, sub_count: 0 }
			span = selected.spans.get(chain_index) ?? { start: 0, count: 0 }
			for i in chain.sub_start..<(chain.sub_start + chain.sub_count) {
				match table.subtables.get(i) {
					Err(_) => {}
					Ok(sub) => {
						coverage = sub.coverage.shr_zf_wrap(24)
						ctx = { ranges: selected.ranges, start: span.start, count: span.count, fallback: chain.flags, subflags: sub.flags }
						possible = if (span.count > 1) True else AatMorx.enabled(ctx, 0)
						if possible and (coverage.bitwise_and(0x20) != 0 or (coverage.bitwise_and(0x80) != 0) == vertical) and AatMorx.intersects(sub.body, $items) {
							reverse = (coverage.bitwise_and(0x40) != 0) != (coverage.bitwise_and(0x10) == 0 and backward)
							input = if (reverse) AatMorx.reversed($items) else $items
							out = AatMorx.apply_body(sub.body, input, budget - $operations, limit, ctx)
							$items = if (reverse) AatMorx.reversed(out.items) else out.items
							$operations = $operations + out.operations
							if out.stopped != 0 {
								return { items: $items, operations: $operations, stopped: out.stopped }
							}
						}
					}
				}
			}
		}
		{ items: $items, operations: $operations, stopped: 0 }
	}

	# Match the reference accelerator's initial-action glyph set. End of
	# text alone does not start a program with no applicable input glyph.
	intersects : Body, List(LayoutGsub.Item) -> Bool
	intersects = |body, items| {
		machine = match body {
			Noncontextual(lookup) => return items.any(
				|item| match AatLookup.get(lookup, item.glyph) {
					Found(_) => True
					Missing => False
				},
			)
			Rearrange(state) => state
			Contextual(value) => value.machine
			Ligature(value) => value.machine
			Insertion(value) => value.machine
		}
		lookup = AatState.class_lookup(machine)
		columns = AatState.column_count(machine)
		kind = match body {
			Rearrange(_) => 0
			Contextual(_) => 1
			Ligature(_) => 2
			Insertion(_) => 5
			Noncontextual(_) => 4
		}
		for item in items {
			found = if (item.glyph == 65535 and columns <= 512) Found(2.U32) else AatLookup.get(lookup, item.glyph)
			match found {
				Missing => {}
				Found(class) => {
					if columns > 512 {
						return True
					}
					entry = AatState.entry(machine, 0, class.to_u64())
					action = match kind {
						0 => entry.flags.bitwise_and(15) != 0
						1 => entry.a != 65535 or entry.b != 65535
						2 => entry.flags.bitwise_and(0x2000) != 0
						5 => entry.flags.bitwise_and(0x03FF) != 0 and (entry.a != 65535 or entry.b != 65535)
						_ => False
					}
					if entry.next != 0 or entry.flags.bitwise_and(0x8000) != 0 or action {
						return True
					}
				}
			}
		}
		False
	}

	flags_for : AatMorx, Chain, List(Requested), List(U64), U64 -> U64
	flags_for = |table, chain, requested, languages, cluster| {
		var $flags = chain.flags
		for i in chain.feature_start..<(chain.feature_start + chain.feature_count) {
			f = table.features.get(i) ?? { type: 0, setting: 0, enable: 0, disable: 0 }
			matches = (f.type == 39 and f.setting != 0 and languages.contains(f.setting)) or AatMorx.selected(requested, f.type, f.setting, cluster) or (f.type == 3 and f.setting == 3 and AatMorx.selected(requested, 37, 1, cluster))
			if matches {
				$flags = $flags.bitwise_and(f.disable).bitwise_or(f.enable)
			}
		}
		$flags
	}

	selected : List(Requested), U64, U64, U64 -> Bool
	selected = |requested, type, setting, cluster| {
		for r in requested {
			if r.type == type and (r.exclusive or r.setting.bitwise_and(0xFFFE) == setting.bitwise_and(0xFFFE)) and cluster >= r.start and (cluster < r.end or r.end == 0xFFFFFFFFFFFFFFFF) {
				# HarfBuzz's AAT map keeps the first active selector per
				# exclusive group/on-off pair, unlike its OpenType masks.
				return r.setting == setting
			}
		}
		False
	}

	apply_body : Body, List(LayoutGsub.Item), U64, U64, FlagsContext -> Applied
	apply_body = |body, items, budget, limit, ctx| {
		var $items = items
		var $operations = 0
		match body {
			Insertion(c) => return AatMorx.insert(c.machine, c.glyphs, $items, budget, limit, ctx)
			Ligature(c) => return AatMorx.ligate(c, $items, budget, ctx)
			Noncontextual(lookup) => {
				for i in 0..<$items.len() {
					if $operations >= budget {
						return { items: $items, operations: $operations, stopped: 2 }
					}
					$operations = $operations + 1
					item = $items.get(i) ?? LayoutGsub.no_item
					if AatMorx.enabled(ctx, item.cluster) {
						match AatLookup.get(lookup, item.glyph) {
							Found(g) => {
								$items = $items.set(i, AatMorx.replace(item, g.to_u64())) ?? []
							}
							Missing => {}
						}
					}
				}
			}
			Rearrange(machine) | Contextual({ machine, .. }) => {
				kind = match body {
					Rearrange(_) => 0
					_ => 1
				}
				var $state = 0
				var $index = 0
				var $mark = 0
				var $marked = False
				var $start = 0
				var $end = 0
				while $index <= $items.len() {
					if $operations >= budget {
						return { items: $items, operations: $operations, stopped: 2 }
					}
					$operations = $operations + 1
					item = $items.get($index) ?? LayoutGsub.no_item
					cluster = if ($index < $items.len()) item.cluster else ($items.last() ?? LayoutGsub.no_item).cluster
					if !AatMorx.enabled(ctx, cluster) {
						if $index == $items.len() {
							break
						}
						$state = 0
						$index = $index + 1
					} else {
						class_id = if ($index == $items.len()) 0 else AatState.class(machine, item.glyph)
						e = AatState.entry(machine, $state, class_id)
						if $index > 0 and $index < $items.len() and !AatMorx.safe_to_break(machine, kind, $state, class_id, e) {
							$items = AatMorx.unsafe_range($items, $index - 1, $index + 1)
						}
						match body {
							Rearrange(_) => {
								if e.flags.bitwise_and(0x8000) != 0 {
									$start = $index
								}
								if e.flags.bitwise_and(0x2000) != 0 {
									$end = ($index + 1).min($items.len())
								}
								if e.flags.bitwise_and(15) != 0 and $start < $end {
									$items = AatMorx.rearrange($items, $start, $end, ($index + 1).min($items.len()), e.flags.bitwise_and(15))
								}
							}
							Contextual(c) => {
								if $index < $items.len() or $marked {
									if e.a != 65535 and $mark < $items.len() {
										lookup = c.lookups.get(e.a) ?? AatLookup.empty
										marked = $items.get($mark) ?? LayoutGsub.no_item
										match AatLookup.get(lookup, marked.glyph) {
											Found(g) if !c.legacy_zero_missing or g != 0 => {
												$items = AatMorx.unsafe_range($items, $mark, ($index + 1).min($items.len()))
												$items = $items.set($mark, AatMorx.replace($items.get($mark) ?? LayoutGsub.no_item, g.to_u64())) ?? []
											}
											_ => {}
										}
									}
									if e.b != 65535 and !$items.is_empty() {
										at = $index.min($items.len() - 1)
										lookup = c.lookups.get(e.b) ?? AatLookup.empty
										current = $items.get(at) ?? LayoutGsub.no_item
										match AatLookup.get(lookup, current.glyph) {
											Found(g) if !c.legacy_zero_missing or g != 0 => {
												$items = $items.set(at, AatMorx.replace(current, g.to_u64())) ?? []
											}
											_ => {}
										}
									}
									if e.flags.bitwise_and(0x8000) != 0 {
										$mark = $index
										$marked = True
									}
								}
							}
							Noncontextual(_) | Insertion(_) | Ligature(_) => {}
						}
						$state = e.next
						if $index == $items.len() {
							break
						}
						if e.flags.bitwise_and(0x4000) == 0 {
							$index = $index + 1
						}
					}
				}
			}
		}
		{ items: $items, operations: $operations, stopped: 0 }
	}

	actionable : U64, AatState.Entry -> Bool
	actionable = |kind, e| match kind {
		0 => e.flags.bitwise_and(15) != 0
		1 => e.a != 65535 or e.b != 65535
		2 => e.flags.bitwise_and(0x2000) != 0
		5 => e.flags.bitwise_and(0x03FF) != 0 and (e.a != 65535 or e.b != 65535)
		_ => False
	}

	safe_to_break : AatState, U64, U64, U64, AatState.Entry -> Bool
	safe_to_break = |machine, kind, state, class_id, e| {
		start = AatState.entry(machine, 0, class_id)
		!AatMorx.actionable(kind, e) and
			(state == 0 or (e.flags.bitwise_and(0x4000) != 0 and e.next == 0) or
				(!AatMorx.actionable(kind, start) and e.next == start.next and e.flags.bitwise_and(0x4000) == start.flags.bitwise_and(0x4000))) and
				!AatMorx.actionable(kind, AatState.entry(machine, state, 0))
	}

	buffer : List(LayoutGsub.Item) -> LayoutGsub.Buf
	buffer = |items| { info: items, out: [], idx: 0, output: True, serial: 0, random: 0, ops: 0, stopped: 0, aliased: False }

	finish : LayoutGsub.Buf, U64, U64 -> Applied
	finish = |buf, operations, stopped| { items: buf.out.concat(buf.info.drop_first(buf.idx)), operations, stopped }

	remove_deleted : List(LayoutGsub.Item) -> List(LayoutGsub.Item)
	remove_deleted = |items| {
		if !items.any(|item| item.glyph == 65535) {
			return items
		}
		var $buf = AatMorx.buffer(items)
		while $buf.idx < $buf.info.len() {
			if ($buf.info.get($buf.idx) ?? LayoutGsub.no_item).glyph == 65535 {
				$buf = LayoutGsub.delete_glyph($buf)
			} else {
				$buf = LayoutGsub.next_glyph($buf)
			}
		}
		$buf.out
	}

	ligate : Ligatures, List(LayoutGsub.Item), U64, FlagsContext -> Applied
	ligate = |table, items, budget, ctx| {
		var $buf = AatMorx.buffer(items)
		var $operations = 0
		var $state = 0
		# HarfBuzz retains the last 64 component positions in a circular
		# stack. A logical count preserves the reference's wrap behavior.
		var $positions = List.repeat(0.U64, 64)
		var $count = 0
		while $buf.idx <= $buf.info.len() {
			if $operations >= budget {
				return AatMorx.finish($buf, $operations, 2)
			}
			$operations = $operations + 1
			if !AatMorx.enabled(ctx, AatMorx.buffer_cluster($buf)) {
				if $buf.idx == $buf.info.len() {
					break
				}
				$state = 0
				$buf = LayoutGsub.next_glyph($buf)
			} else {
				class_id = if ($buf.idx == $buf.info.len()) 0 else AatState.class(table.machine, ($buf.info.get($buf.idx) ?? LayoutGsub.no_item).glyph)
				e = AatState.entry(table.machine, $state, class_id)
				if !$buf.out.is_empty() and $buf.idx < $buf.info.len() and !AatMorx.safe_to_break(table.machine, 2, $state, class_id, e) {
					start = $buf.out.len() - 1
					end_index = $buf.idx + 1
					$buf = LayoutGsub.unsafe_to_break_from_outbuffer($buf, start, end_index)
				}
				if e.flags.bitwise_and(0x8000) != 0 {
					if $count > 0 and ($positions.get(($count - 1) % 64) ?? 0) == $buf.out.len() {
						$count = $count - 1
					}
					$positions = $positions.set($count % 64, $buf.out.len()) ?? []
					$count = $count + 1
				}
				if e.flags.bitwise_and(0x2000) != 0 and $count != 0 and $buf.idx < $buf.info.len() {
					end = $buf.out.len()
					var $cursor = $count
					var $action = e.a
					var $ligature = 0
					var $done = False
					while !$done {
						if $operations >= budget {
							return AatMorx.finish($buf, $operations, 2)
						}
						$operations = $operations + 1
						if $cursor == 0 {
							$count = 0
							break
						}
						$cursor = $cursor - 1
						$buf = LayoutGsub.move_to($buf, $positions.get($cursor % 64) ?? 0)
						word = (table.actions.get($action) ?? 0).to_u64()
						raw = word.bitwise_and(0x3FFFFFFF)
						offset = if (raw.bitwise_and(0x20000000) != 0) raw.to_i64_wrap() - 1073741824 else raw.to_i64_wrap()
						component_index = ($buf.info.get($buf.idx) ?? LayoutGsub.no_item).glyph.to_i64_wrap() + offset - table.component_base.to_i64_wrap()
						# A text-dependent action outside the available component
						# domain aborts this action stream, as the reference VM does;
						# no missing operand becomes component or glyph zero.
						if component_index < 0 {
							break
						}
						component = match table.components.get(component_index.to_u64_wrap()) {
							Ok(v) => v.to_u64()
							Err(_) => break
						}
						$ligature = ($ligature + component).to_u32_wrap().to_u64()
						if word.bitwise_and(0xC0000000) != 0 {
							# Legacy programs accumulate a byte offset, and store
							# its rebased index back into the same accumulator.
							if table.legacy {
								if $ligature < table.glyph_base {
									break
								}
								$ligature = ($ligature - table.glyph_base) // 2
							}
							glyph = match table.glyphs.get($ligature) {
								Ok(v) => v.to_u64()
								Err(_) => break
							}
							if glyph >= table.glyph_count and glyph != 65535 {
								break
							}
							current = $buf.info.get($buf.idx) ?? LayoutGsub.no_item
							$buf = { ..$buf, info: $buf.info.set($buf.idx, LayoutGsub.with_origin(AatMorx.replace(current, glyph), LayoutGsub.origin_ligature, 0, $count - $cursor)) ?? [] }
							lig_end = ($positions.get(($count - 1) % 64) ?? 0) + 1
							while $count - 1 > $cursor {
								if $operations >= budget {
									return AatMorx.finish($buf, $operations, 2)
								}
								$operations = $operations + 1
								$count = $count - 1
								$buf = LayoutGsub.move_to($buf, $positions.get($count % 64) ?? 0)
								# AAT deletion leaves a placeholder until all chains
								# finish, preserving component-stack positions.
								deleted = AatMorx.replace($buf.info.get($buf.idx) ?? LayoutGsub.no_item, 65535)
								$buf = { ..$buf, info: $buf.info.set($buf.idx, deleted) ?? [] }
								$buf = LayoutGsub.next_glyph($buf)
							}
							$buf = LayoutGsub.move_to($buf, lig_end)
							$buf = AatMorx.merge_output($buf, $positions.get($cursor % 64) ?? 0)
						}
						$done = word.bitwise_and(0x80000000) != 0
						$action = $action + 1
					}
					$buf = LayoutGsub.move_to($buf, end)
				}
				$state = e.next
				if $buf.idx == $buf.info.len() {
					break
				}
				if e.flags.bitwise_and(0x4000) == 0 {
					$buf = LayoutGsub.next_glyph($buf)
				}
			}
		}
		AatMorx.finish($buf, $operations, 0)
	}

	merge_output : LayoutGsub.Buf, U64 -> LayoutGsub.Buf
	merge_output = |buf, start| {
		cluster = buf.out.drop_first(start).fold(0xFFFFFFFFFFFFFFFF.U64, |a, item| a.min(item.cluster))
		{ info, out, idx, output, serial, random, ops, stopped, aliased } = buf
		var $out = out
		for i in start..<$out.len() {
			$out = $out.set(i, LayoutGsub.set_cluster($out.get(i) ?? LayoutGsub.no_item, cluster)) ?? []
		}
		{ info, out: $out, idx, output, serial, random, ops, stopped, aliased }
	}

	insert : AatState, List(U32), List(LayoutGsub.Item), U64, U64, FlagsContext -> Applied
	insert = |machine, glyphs, items, budget, limit, ctx| {
		var $buf = AatMorx.buffer(items)
		var $operations = 0
		var $state = 0
		var $mark = 0
		while $buf.idx <= $buf.info.len() {
			if $operations >= budget {
				return AatMorx.finish($buf, $operations, 2)
			}
			$operations = $operations + 1
			if !AatMorx.enabled(ctx, AatMorx.buffer_cluster($buf)) {
				if $buf.idx == $buf.info.len() {
					break
				}
				$state = 0
				$buf = LayoutGsub.next_glyph($buf)
			} else {
				class_id = if ($buf.idx == $buf.info.len()) 0 else AatState.class(machine, ($buf.info.get($buf.idx) ?? LayoutGsub.no_item).glyph)
				e = AatState.entry(machine, $state, class_id)
				if !$buf.out.is_empty() and $buf.idx < $buf.info.len() and !AatMorx.safe_to_break(machine, 5, $state, class_id, e) {
					start = $buf.out.len() - 1
					end_index = $buf.idx + 1
					$buf = LayoutGsub.unsafe_to_break_from_outbuffer($buf, start, end_index)
				}
				marked_count = if (e.b == 65535) 0 else e.flags.bitwise_and(31)
				current_count = if (e.a == 65535) 0 else e.flags.shr_zf_wrap(5).bitwise_and(31)
				added = marked_count + current_count
				if added > budget - $operations {
					return AatMorx.finish($buf, $operations, 2)
				}
				if added > limit or $buf.out.len() + $buf.info.len() - $buf.idx > limit - added {
					return AatMorx.finish($buf, $operations, 1)
				}
				$operations = $operations + added
				mark_location = $buf.out.len()
				if marked_count != 0 {
					end = $buf.out.len()
					$buf = LayoutGsub.move_to($buf, $mark)
					$buf = AatMorx.insert_at($buf, glyphs, e.b, marked_count, e.flags.bitwise_and(0x0400) != 0)
					$buf = LayoutGsub.move_to($buf, end + marked_count)
					end_index = ($buf.idx + 1).min($buf.info.len())
					$buf = LayoutGsub.unsafe_to_break_from_outbuffer($buf, $mark, end_index)
				}
				if e.flags.bitwise_and(0x8000) != 0 {
					$mark = mark_location
				}
				if current_count != 0 {
					end = $buf.out.len()
					$buf = AatMorx.insert_at($buf, glyphs, e.a, current_count, e.flags.bitwise_and(0x0800) != 0)
					$buf = LayoutGsub.move_to($buf, if (e.flags.bitwise_and(0x4000) != 0) end else end + current_count)
				}
				$state = e.next
				if $buf.idx == $buf.info.len() {
					break
				}
				if e.flags.bitwise_and(0x4000) == 0 {
					$buf = LayoutGsub.next_glyph($buf)
				}
			}
		}
		AatMorx.finish($buf, $operations, 0)
	}

	insert_at : LayoutGsub.Buf, List(U32), U64, U64, Bool -> LayoutGsub.Buf
	insert_at = |buf, glyphs, start, count, before| {
		source = if (buf.idx < buf.info.len()) buf.info.get(buf.idx) ?? LayoutGsub.no_item else buf.out.last() ?? LayoutGsub.no_item
		existing = buf.idx < buf.info.len()
		copied = if (existing and !before) LayoutGsub.next_glyph(buf) else buf
		{ info, out, idx, output, serial, random, ops, stopped, aliased } = copied
		var $out = out
		for i in start..<(start + count) {
			# Reading proves every referenced insertion span and glyph.
			inserted = LayoutGsub.with_origin(AatMorx.replace(source, (glyphs.get(i) ?? 0).to_u64()), LayoutGsub.origin_inserted, 0, 0)
			$out = $out.append(inserted)
		}
		{ info, out: $out, idx, output, serial, random, ops, stopped, aliased }
	}

	buffer_cluster : LayoutGsub.Buf -> U64
	buffer_cluster = |buf| (if (buf.idx < buf.info.len()) buf.info.get(buf.idx) ?? LayoutGsub.no_item else buf.out.last() ?? LayoutGsub.no_item).cluster

	reversed : List(a) -> List(a)
	reversed = |list| {
		var $out = List.with_capacity(list.len())
		for i in 0..<list.len() {
			match list.get(list.len() - 1 - i) {
				Ok(v) => {
					$out = $out.append(v)
				}
				Err(_) => {}
			}
		}
		$out
	}

	replace : LayoutGsub.Item, U64 -> LayoutGsub.Item
	replace = |item, glyph| {
		changed = LayoutGsub.resubstituted({ ..item, glyph }, 0)
		props = changed.props.bitwise_or(LayoutGsub.substituted.shl_wrap(16))
		{ ..changed, props: if (glyph == 65535) ShaperUnicode.with_category(props, ShaperUnicode.format).bitwise_or(ShaperUnicode.hidden) else props }
	}

	unsafe_range : List(LayoutGsub.Item), U64, U64 -> List(LayoutGsub.Item)
	unsafe_range = |items, start, end| {
		if end <= start or end - start > 255 {
			return items
		}
		cluster = LayoutGsub.end_cluster(items, start, end, 0xFFFFFFFFFFFFFFFF)
		LayoutGsub.flag_range(items, start, end, cluster)
	}

	rearrange : List(LayoutGsub.Item), U64, U64, U64, U64 -> List(LayoutGsub.Item)
	rearrange = |items, start, end, current_end, verb| {
		map = [0x00.U64, 0x10, 0x01, 0x11, 0x20, 0x30, 0x02, 0x03, 0x12, 0x13, 0x21, 0x31, 0x22, 0x32, 0x23, 0x33].get(verb) ?? 0
		left = map.shr_zf_wrap(4).min(2)
		right = map.bitwise_and(15).min(2)
		if end - start < left + right or end - start > 64 {
			return items
		}
		# Source indices define a permutation; capture the at-most-four
		# boundary items before mutating the unique flat output list.
		l0 = items.get(start) ?? LayoutGsub.no_item
		l1 = items.get(start + 1) ?? LayoutGsub.no_item
		r0 = items.get(end - right) ?? LayoutGsub.no_item
		r1 = items.get(end - right + 1) ?? LayoutGsub.no_item
		middle_count = end - start - left - right
		cluster = LayoutGsub.min_cluster(items, start, end.max(current_end), 0xFFFFFFFFFFFFFFFF)
		var $items = items
		if left != right {
			# Move towards the free boundary, preserving overlapping source
			# items: backwards for a right shift, forwards for a left shift.
			for step in 0..<middle_count {
				i = if (right > left) middle_count - step - 1 else step
				item = $items.get(start + left + i) ?? LayoutGsub.no_item
				$items = $items.set(start + right + i, item) ?? []
			}
		}
		for i in 0..<right {
			first = if (map.bitwise_and(15) == 3) i == 1 else i == 0
			$items = $items.set(start + i, if (first) r0 else r1) ?? []
		}
		for i in 0..<left {
			first = if (map.shr_zf_wrap(4) == 3) i == 1 else i == 0
			$items = $items.set(end - left + i, if (first) l0 else l1) ?? []
		}
		for i in start..<end {
			item = $items.get(i) ?? LayoutGsub.no_item
			$items = $items.set(i, LayoutGsub.set_cluster(item, cluster)) ?? []
		}
		AatMorx.unsafe_range($items, start, end.max(current_end))
	}
}
