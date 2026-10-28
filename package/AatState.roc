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

## Extended AAT state tables, prepared as flat scalar transition rows.
## Reading follows every reachable next state before use. A class outside
## the font's class lookup takes the specified out-of-bounds class (1).
AatState := { classes : AatLookup, columns : U64, transitions : List(Entry) }.{

	Entry : { next : U64, flags : U64, a : U64, b : U64 }
	no_entry : Entry
	no_entry = { next: 0, flags: 0, a: 0, b: 0 }

	read : List(U8), U64, U64, U64 -> Try(AatState, [Bad(U64)])
	read = |bytes, base, glyphs, extra_words| {
		if extra_words > 2 or !Bytes.fits(base, 16, bytes.len()) {
			return Err(Bad(base))
		}
		columns = Bytes.u32(bytes, base)
		class_at = base + Bytes.u32(bytes, base + 4)
		states_at = base + Bytes.u32(bytes, base + 8)
		entries_at = base + Bytes.u32(bytes, base + 12)
		if columns < 4 or columns > 65536 {
			return Err(Bad(base))
		}
		classes = AatLookup.read(bytes, class_at, glyphs, 2)?
		if !AatLookup.values_valid(classes, glyphs, columns, False) {
			return Err(Bad(class_at))
		}
		row_bytes = columns * 2
		entry_bytes = 4 + extra_words * 2
		# States 0 and 1 are the specified start-of-text/start-of-line states.
		# Every discovered row is checked before its transition cells allocate.
		var $last = 1
		var $state = 0
		while $state <= $last {
			row = states_at + $state * row_bytes
			if !Bytes.fits(row, row_bytes, bytes.len()) {
				return Err(Bad(row))
			}
			for c in 0..<columns {
				entry = entries_at + Bytes.u16(bytes, row + c * 2) * entry_bytes
				if !Bytes.fits(entry, entry_bytes, bytes.len()) {
					return Err(Bad(entry))
				}
				$last = $last.max(Bytes.u16(bytes, entry))
			}
			$state = $state + 1
		}
		# The preceding traversal proves all row/entry spans and bounds the
		# final cell count by the checked byte length of the font table.
		var $transitions = List.with_capacity(($last + 1) * columns)
		for state in 0..<($last + 1) {
			for c in 0..<columns {
				entry = entries_at + Bytes.u16(bytes, states_at + state * row_bytes + c * 2) * entry_bytes
				$transitions = $transitions.append({ next: Bytes.u16(bytes, entry), flags: Bytes.u16(bytes, entry + 2), a: if (extra_words > 0) Bytes.u16(bytes, entry + 4) else 0, b: if (extra_words > 1) Bytes.u16(bytes, entry + 6) else 0 })
			}
		}
		Ok({ classes, columns, transitions: $transitions })
	}

	class : AatState, U64 -> U64
	class = |machine, glyph| if glyph == 65535 {
		2
	} else match AatLookup.get(machine.classes, glyph) {
		Found(c) => c.to_u64()
		Missing => 1
	}

	entry : AatState, U64, U64 -> Entry
	entry = |machine, state, class_id| machine.transitions.get(state * machine.columns + class_id) ?? AatState.no_entry

	entries : AatState -> List(Entry)
	entries = |machine| machine.transitions
}

expect {
	match AatState.read(List.repeat(0.U8, 16), 0, 0, 0) {
		Err(Bad(0)) => True
		_ => False
	}
}
