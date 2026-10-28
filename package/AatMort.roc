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

import AatMorx
import AatState
import AatLookup
import Bytes
import LayoutGsub

## Original Apple metamorphosis programs are prepared into the same
## bounded runtime representation as extended metamorphosis programs.
AatMort :: {}.{
	none : AatMorx
	none = AatMorx.{ chains: [], features: [], subtables: [] }
	with_entries : AatState, List(AatState.Entry) -> AatState
	with_entries = |machine, entries| AatState.{ classes: machine.classes, columns: machine.columns, transitions: entries }

	read : List(U8), U64 -> Try(AatMorx, [Bad(U64)])
	read = |bytes, glyphs| {
		if glyphs > 65536 or bytes.len() < 8 or Bytes.u32(bytes, 0) != 0x00010000 {
			return Err(Bad(0))
		}
		count = Bytes.u32(bytes, 4)
		if count > (bytes.len() - 8) // 12 {
			return Err(Bad(4))
		}
		var $at = 8
		var $chains = List.with_capacity(count)
		var $features = []
		var $subtables = []
		for _ in 0..<count {
			if !Bytes.fits($at, 12, bytes.len()) {
				return Err(Bad($at))
			}
			length = Bytes.u32(bytes, $at + 4)
			features = Bytes.u16(bytes, $at + 8)
			subtables = Bytes.u16(bytes, $at + 10)
			if length < 12 or !Bytes.fits($at, length, bytes.len()) or features > (length - 12) // 12 {
				return Err(Bad($at + 4))
			}
			end = $at + length
			var $sub = $at + 12 + features * 12
			if subtables > (end - $sub) // 8 {
				return Err(Bad($at + 10))
			}
			chain = { flags: Bytes.u32(bytes, $at), feature_start: $features.len(), feature_count: features, sub_start: $subtables.len(), sub_count: subtables }
			for i in 0..<features {
				at = $at + 12 + i * 12
				$features = $features.append({ type: Bytes.u16(bytes, at), setting: Bytes.u16(bytes, at + 2), enable: Bytes.u32(bytes, at + 4), disable: Bytes.u32(bytes, at + 8) })
			}
			for _ in 0..<subtables {
				if !Bytes.fits($sub, 8, end) {
					return Err(Bad($sub))
				}
				len = Bytes.u16(bytes, $sub)
				coverage = Bytes.u16(bytes, $sub + 2)
				if len < 8 or !Bytes.fits($sub, len, end) {
					return Err(Bad($sub))
				}
				body = AatMort.read_body(bytes.drop_first($sub + 8).take_first(len - 8), glyphs, coverage.bitwise_and(255)).map_err(
					|problem| match problem {
						Bad(offset) => Bad($sub + 8 + offset)
					},
				)?
				# Both headers use the same eight high coverage bits, at
				# different widths. The low byte is the subtable type.
				$subtables = $subtables.append({ coverage: coverage.bitwise_and(0xFF00).shl_wrap(16).bitwise_or(coverage.bitwise_and(255)), flags: Bytes.u32(bytes, $sub + 4), body })
				$sub = $sub + len
			}
			$chains = $chains.append(chain)
			$at = end
		}
		Ok(AatMorx.{ chains: $chains, features: $features, subtables: $subtables })
	}

	read_body : List(U8), U64, U64 -> Try(AatMorx.Body, [Bad(U64)])
	read_body = |bytes, glyphs, kind| {
		if kind == 4 {
			lookup = AatLookup.read(bytes, 0, glyphs, 2)?
			AatMorx.check_substitutions(lookup, glyphs)?
			return Ok(Noncontextual(lookup))
		}
		if kind == 0 {
			return Ok(Rearrange(AatState.read_legacy(bytes, 0, glyphs, 0)?))
		}
		if kind == 5 {
			machine = AatState.read_legacy(bytes, 0, glyphs, 2)?
			if bytes.len() < 10 {
				return Err(Bad(8))
			}
			at = Bytes.u16(bytes, 8)
			var $count = 0
			for entry in AatState.entries(machine) {
				if entry.a != 65535 {
					$count = $count.max(entry.a + entry.flags.shr_zf_wrap(5).bitwise_and(31))
				}
				if entry.b != 65535 {
					$count = $count.max(entry.b + entry.flags.bitwise_and(31))
				}
			}
			if at == 0 or !Bytes.fits(at, $count * 2, bytes.len()) {
				return Err(Bad(8))
			}
			var $values = List.with_capacity($count)
			for i in 0..<$count {
				value = Bytes.u16(bytes, at + i * 2)
				if value >= glyphs and value != 65535 {
					return Err(Bad(at + i * 2))
				}
				$values = $values.append(value.to_u32_wrap())
			}
			return Ok(Insertion({ machine, glyphs: $values }))
		}
		if kind == 1 {
			return AatMort.contextual(bytes, glyphs)
		}
		if kind == 2 {
			return AatMort.ligature(bytes, glyphs)
		}
		Err(Bad(0))
	}

	contextual : List(U8), U64 -> Try(AatMorx.Body, [Bad(U64)])
	contextual = |bytes, glyphs| {
		machine = AatState.read_legacy(bytes, 0, glyphs, 2)?
		if bytes.len() < 10 {
			return Err(Bad(8))
		}
		at = Bytes.u16(bytes, 8)
		if at == 0 or at > bytes.len() {
			return Err(Bad(8))
		}
		state_at = Bytes.u16(bytes, 4)
		entry_at = Bytes.u16(bytes, 6)
		# Legacy state cells are bytes: at most256 distinct entry records.
		# Collect offsets once per record rather than once per state cell.
		var $seen = List.repeat(False, 256)
		var $entry_ids = []
		var $offsets = []
		for i in 0..<AatState.entries(machine).len() {
			id = Bytes.u8(bytes, state_at + i)
			if !($seen.get(id) ?? True) {
				$seen = $seen.set(id, True) ?? []
				$entry_ids = $entry_ids.append(id)
				for j in 0..<2 {
					offset = Bytes.u16(bytes, entry_at + id * 8 + 4 + j * 2)
					if offset != 0 and !$offsets.contains(offset) {
						$offsets = $offsets.append(offset)
					}
				}
			}
		}
		pool_count = if ($offsets.is_empty()) 0 else (bytes.len() - at) // 2
		var $values = List.with_capacity(pool_count)
		for i in 0..<pool_count {
			$values = $values.append(Bytes.u16(bytes, at + i * 2).to_u32_wrap())
		}
		# All lookups share one immutable pool. A difference array proves
		# the union of referenced spans in linear work, even when hundreds
		# of signed offsets address almost the same substitution array.
		var $used = List.repeat(0.I64, pool_count + 1)
		var $lookups = List.with_capacity($offsets.len())
		for raw in $offsets {
			offset = if (raw.bitwise_and(32768) == 0) raw.to_i64_wrap() else raw.to_i64_wrap() - 65536
			base_word = ((at + 1) // 2).to_i64_wrap()
			first = (base_word - offset).max(0)
			last = (base_word + pool_count.to_i64_wrap() - offset).min(glyphs.to_i64_wrap())
			if first >= last {
				$lookups = $lookups.append(AatLookup.empty)
			} else {
				start = (offset + first - base_word).to_u64_wrap()
				end = start + (last - first).to_u64_wrap()
				$used = $used.set(start, ($used.get(start) ?? 0) + 1) ?? []
				$used = $used.set(end, ($used.get(end) ?? 0) - 1) ?? []
				$lookups = $lookups.append(AatLookup.{ ranges: [{ first: first.to_u64_wrap(), last: last.to_u64_wrap() - 1, value: start, array: True }], values: $values })
			}
		}
		var $active = 0
		for i in 0..<pool_count {
			$active = $active + ($used.get(i) ?? 0)
			if $active != 0 {
				value = $values.get(i) ?? 0
				if value.to_u64() >= glyphs and value != 65535 {
					return Err(Bad(at + i * 2))
				}
			}
		}
		var $mapped = List.repeat({ a: 65535.U64, b: 65535.U64 }, 256)
		for id in $entry_ids {
			a = AatMort.offset_index($offsets, Bytes.u16(bytes, entry_at + id * 8 + 4))
			b = AatMort.offset_index($offsets, Bytes.u16(bytes, entry_at + id * 8 + 6))
			$mapped = $mapped.set(id, { a, b }) ?? []
		}
		entries = AatState.entries(machine).map_with_index(
			|entry, i| {
				indices = $mapped.get(Bytes.u8(bytes, state_at + i)) ?? { a: 65535, b: 65535 }
				{ ..entry, a: indices.a, b: indices.b }
			},
		)
		Ok(Contextual({ machine: AatMort.with_entries(machine, entries), lookups: $lookups, legacy_zero_missing: True }))
	}

	offset_index : List(U64), U64 -> U64
	offset_index = |offsets, raw| {
		if raw != 0 {
			for i in 0..<offsets.len() {
				if (offsets.get(i) ?? 0) == raw {
					return i
				}
			}
		}
		65535
	}

	ligature : List(U8), U64 -> Try(AatMorx.Body, [Bad(U64)])
	ligature = |bytes, glyphs| {
		machine = AatState.read_legacy(bytes, 0, glyphs, 0)?
		if bytes.len() < 14 {
			return Err(Bad(8))
		}
		action_at = Bytes.u16(bytes, 8)
		component_at = Bytes.u16(bytes, 10)
		glyph_at = Bytes.u16(bytes, 12)
		if !Bytes.fits(action_at, 4, bytes.len()) or !Bytes.fits(component_at, 2, bytes.len()) or !Bytes.fits(glyph_at, 2, bytes.len()) {
			return Err(Bad(8))
		}
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
		var $entries = List.with_capacity(AatState.entries(machine).len())
		for entry in AatState.entries(machine) {
			raw = entry.flags.bitwise_and(0x3FFF)
			var $index = 0
			flags = entry.flags.bitwise_and(0xC000).bitwise_or(if (raw == 0) 0 else 0x2000)
			if raw != 0 {
				if raw < action_at or raw % 4 != 0 or (raw - action_at) % 4 != 0 {
					return Err(Bad(raw))
				}
				$index = (raw - action_at) // 4
				end = $ends.get($index) ?? 0
				if end == 0 {
					return Err(Bad(raw))
				}
				$action_count = $action_count.max(end)
			}
			$entries = $entries.append({ ..entry, flags, a: $index })
		}
		var $actions = List.with_capacity($action_count)
		for i in 0..<$action_count {
			$actions = $actions.append(Bytes.u32(bytes, action_at + i * 4).to_u32_wrap())
		}
		var $components = List.with_capacity((bytes.len() - component_at) // 2)
		for i in 0..<((bytes.len() - component_at) // 2) {
			$components = $components.append(Bytes.u16(bytes, component_at + i * 2).to_u16_wrap())
		}
		var $ligatures = List.with_capacity((bytes.len() - glyph_at) // 2)
		for i in 0..<((bytes.len() - glyph_at) // 2) {
			$ligatures = $ligatures.append(Bytes.u16(bytes, glyph_at + i * 2).to_u16_wrap())
		}
		Ok(Ligature({ machine: AatMort.with_entries(machine, $entries), actions: $actions, components: $components, glyphs: $ligatures, glyph_count: glyphs, legacy: True, component_base: (component_at + 1) // 2, glyph_base: glyph_at }))
	}
}

test_direct : List(U8)
test_direct = [0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 32, 0, 0, 0, 1, 0, 20, 0, 4, 0, 0, 0, 1, 0, 8, 0, 1, 0, 2, 0, 3, 0, 2, 0, 0]

test_context_zero : List(U8)
test_context_zero = [0, 5, 0, 10, 0, 18, 0, 28, 0, 44, 0, 0, 0, 4, 1, 4, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 18, 0, 0, 0, 0, 0, 0, 0, 18, 0, 0, 0, 0, 0, 21, 0, 0]

test_context_negative : List(U8)
test_context_negative = [0, 6, 0, 10, 0, 16, 0, 28, 0, 44, 0, 23, 0, 2, 4, 5, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 16, 0, 0, 0, 0, 0, 0, 0, 16, 0, 0, 0, 0, 255, 255, 0, 5]

test_insertion : List(U8)
test_insertion = [0, 5, 0, 10, 0, 18, 0, 28, 0, 44, 0, 0, 0, 4, 1, 4, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 18, 0, 0, 255, 255, 255, 255, 0, 18, 8, 32, 0, 0, 255, 255, 0, 3]

test_rearrange : List(U8)
test_rearrange = [0, 4, 0, 8, 0, 12, 0, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 12, 0, 0]

test_ligature : List(U8)
test_ligature = [0, 6, 0, 14, 0, 22, 0, 40, 0, 52, 0, 60, 0, 68, 0, 0, 0, 4, 1, 4, 5, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 2, 0, 22, 0, 0, 0, 34, 128, 0, 0, 22, 128, 52, 0, 0, 0, 28, 128, 0, 0, 29, 0, 34, 0, 0, 0, 0, 0, 0, 0, 3]

test_run : AatMorx.Body, List(U64) -> List(U64)
test_run = |body, glyphs| {
	prepared = AatMorx.{ chains: [{ flags: 1, feature_start: 0, feature_count: 0, sub_start: 0, sub_count: 1 }], features: [], subtables: [{ coverage: 0, flags: 1, body }] }
	input = glyphs.map_with_index(|glyph, cluster| { ..LayoutGsub.no_item, glyph, cluster })
	AatMorx.apply(prepared, input, AatMorx.plan(prepared, []), False, False, 1000, 1000).items.map(|item| item.glyph)
}
expect {
	match AatMort.read(test_direct, 4) {
		Ok(table) => {
			input = [1, 2].map_with_index(|glyph, cluster| { ..LayoutGsub.no_item, glyph, cluster })
			AatMorx.apply(table, input, AatMorx.plan(table, []), False, False, 100, 100).items.map(|item| item.glyph) == [3, 2]
		}
		Err(_) => False
	}
}
expect {
	match AatMort.read_body(test_ligature, 4, 2) {
		Ok(body) => test_run(body, [1, 2]) == [3, 65535]
		Err(_) => False
	}
}
expect {
	# Old coverage bits occupy the high byte of a16-bit field.
	match AatMort.read(test_direct.set(22, 0x20) ?? [], 4) {
		Ok(table) => (table.subtables.first() ?? { coverage: 0, flags: 0, body: Noncontextual(AatLookup.empty) }).coverage == 0x20000004
		Err(_) => False
	}
}
expect {
	match AatMort.read_body(test_context_zero.set(45, 4) ?? [], 4, 1) {
		Err(Bad(44)) => True
		_ => False
	}
}
expect {
	match AatMort.read(test_direct.take_first(39), 4) {
		Err(Bad(_)) => True
		_ => False
	}
}
expect {
	match AatMort.read_body([], 4, 3) {
		Err(Bad(0)) => True
		_ => False
	}
}
expect {
	match AatMort.read_body(test_context_zero, 4, 1) {
		Ok(body) => test_run(body, [1]) == [1]
		Err(_) => False
	}
}
expect {
	# 0xFFFF is signed offset−1 in mort, not morx's missing-index sentinel.
	match AatMort.read_body(test_context_negative, 64, 1) {
		Ok(body) => test_run(body, [23]) == [5]
		Err(_) => False
	}
}
expect {
	match AatMort.read_body(test_insertion, 4, 5) {
		Ok(body) => test_run(body, [1]) == [3, 1]
		Err(_) => False
	}
}
expect {
	match AatMort.read_body(test_rearrange, 4, 0) {
		Ok(Rearrange(machine)) => AatState.column_count(machine) == 4 and AatState.entries(machine).len() == 8 and AatState.entries(machine).all(|entry| entry.next == 0)
		_ => False
	}
}
