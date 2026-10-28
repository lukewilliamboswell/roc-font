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

## Checked AAT lookup formats 0, 2, 4, 6, 8 and 10. Sorted scalar ranges
## address a flat value pool; constant ranges do not expand per glyph.
## Internal. Offsets in failures are relative to the supplied table bytes.
AatLookup := { ranges : List(Segment), values : List(U32) }.{

	Segment : { first : U64, last : U64, value : U64, array : Bool }

	empty : AatLookup
	empty = { ranges: [], values: [] }

	segments : AatLookup -> List(Segment)
	segments = |lookup| lookup.ranges

	value_pool : AatLookup -> List(U32)
	value_pool = |lookup| lookup.values

	read : List(U8), U64, U64, U64 -> Try(AatLookup, [Bad(U64)])
	read = |bytes, base, glyphs, width| {
		if glyphs > 65536 or !Bytes.fits(base, 2, bytes.len()) or (width != 1 and width != 2 and width != 4) {
			return Err(Bad(base))
		}
		format = Bytes.u16(bytes, base)
		if format == 0 or format == 8 or format == 10 {
			header = if (format == 0) 2 else if (format == 8) 6 else 8
			if !Bytes.fits(base, header, bytes.len()) {
				return Err(Bad(base))
			}
			first = if (format == 0) 0 else Bytes.u16(bytes, base + header - 4)
			count = if (format == 0) glyphs else Bytes.u16(bytes, base + header - 2)
			size = if (format == 10) Bytes.u16(bytes, base + 2) else width
			if size > 4 or first + count > 65536 or !Bytes.fits(base + header, count * size, bytes.len()) {
				return Err(Bad(base))
			}
			var $values = List.with_capacity(count)
			for i in 0..<count {
				$values = $values.append(AatLookup.number(bytes, base + header + i * size, size).to_u32_wrap())
			}
			return Ok({ ranges: if (count == 0) [] else [{ first, last: first + count - 1, value: 0, array: True }], values: $values })
		}
		if format != 2 and format != 4 and format != 6 {
			return Err(Bad(base))
		}
		if !Bytes.fits(base, 12, bytes.len()) {
			return Err(Bad(base))
		}
		unit = Bytes.u16(bytes, base + 2)
		count = Bytes.u16(bytes, base + 4)
		expected = if (format == 6) 2 + width else if (format == 4) 6 else 4 + width
		if unit != expected or !Bytes.fits(base + 12, count * unit, bytes.len()) {
			return Err(Bad(base + 2))
		}
		# Validate all ranges and array spans before allocating from their counts.
		var $end = 0
		var $seen = False
		var $pool_count = 0
		for i in 0..<count {
			at = base + 12 + i * unit
			last = Bytes.u16(bytes, at)
			first = if (format == 6) last else Bytes.u16(bytes, at + 2)
			if first > last or ($seen and first <= $end) {
				return Err(Bad(at))
			}
			$seen = True
			$end = last
			if format == 4 and first != 65535 {
				offset = Bytes.u16(bytes, at + 4)
				n = last - first + 1
				if !Bytes.fits(base + offset, n * width, bytes.len()) {
					return Err(Bad(at + 4))
				}
				$pool_count = $pool_count + n
			}
		}
		var $ranges = List.with_capacity(count)
		var $values = List.with_capacity($pool_count)
		for i in 0..<count {
			at = base + 12 + i * unit
			last = Bytes.u16(bytes, at)
			first = if (format == 6) last else Bytes.u16(bytes, at + 2)
			if first != 65535 {
				value = AatLookup.number(bytes, at + (if (format == 6) 2 else 4), if (format == 4) 2 else width)
				if format == 4 {
					start = $values.len()
					for j in 0..<(last - first + 1) {
						$values = $values.append(AatLookup.number(bytes, base + value + j * width, width).to_u32_wrap())
					}
					$ranges = $ranges.append({ first, last, value: start, array: True })
				} else {
					$ranges = $ranges.append({ first, last, value, array: False })
				}
			}
		}
		Ok({ ranges: $ranges, values: $values })
	}

	number : List(U8), U64, U64 -> U64
	number = |bytes, at, width| {
		var $v = 0
		for i in 0..<width {
			$v = $v * 256 + Bytes.u8(bytes, at + i)
		}
		$v
	}

	get : AatLookup, U64 -> [Found(U32), Missing]
	get = |lookup, glyph| {
		var $lo = 0
		var $hi = lookup.ranges.len()
		while $lo < $hi {
			mid = $lo + ($hi - $lo) // 2
			r = lookup.ranges.get(mid) ?? { first: 0, last: 0, value: 0, array: False }
			if glyph < r.first {
				$hi = mid
			} else if glyph > r.last {
				$lo = mid + 1
			} else {
				return if (r.array) Found(lookup.values.get(r.value + glyph - r.first) ?? 0) else Found(r.value.to_u32_wrap())
			}
		}
		Missing
	}

	## Validate only values addressable by an existing glyph, in time
	## bounded by the prepared table size rather than glyphs times ranges.
	values_valid : AatLookup, U64, U64, Bool -> Bool
	values_valid = |lookup, glyphs, limit, allow_deleted| {
		valid = |v| v < limit or (allow_deleted and v == 65535)
		for r in lookup.ranges {
			if r.first < glyphs {
				if r.array {
					count = (r.last + 1).min(glyphs) - r.first
					for i in 0..<count {
						# Reading proved this pool span is present.
						if !valid((lookup.values.get(r.value + i) ?? 0).to_u64()) {
							return False
						}
					}
				} else if !valid(r.value) {
					return False
				}
			}
		}
		True
	}

	## The original AAT class array has first/count fields followed by
	## byte or word classes, rather than an extended lookup header.
	legacy_classes : List(U8), U64, U64 -> Try(AatLookup, [Bad(U64)])
	legacy_classes = |bytes, at, width| {
		if (width != 1 and width != 2) or !Bytes.fits(at, 4, bytes.len()) {
			return Err(Bad(at))
		}
		first = Bytes.u16(bytes, at)
		count = Bytes.u16(bytes, at + 2)
		if first + count > 65536 or !Bytes.fits(at + 4, count * width, bytes.len()) {
			return Err(Bad(at))
		}
		var $values = List.with_capacity(count)
		for i in 0..<count {
			$values = $values.append(AatLookup.number(bytes, at + 4 + i * width, width).to_u32_wrap())
		}
		Ok({ ranges: if (count == 0) [] else [{ first, last: first + count - 1, value: 0, array: True }], values: $values })
	}
}

expect {
	# An absent key differs from an explicitly stored zero.
	match AatLookup.read([0, 8, 0, 3, 0, 2, 0, 0, 0, 9], 0, 8, 2) {
		Ok(t) => AatLookup.get(t, 2) == Missing and AatLookup.get(t, 3) == Found(0) and AatLookup.get(t, 4) == Found(9) and AatLookup.get(t, 5) == Missing
		Err(_) => False
	}
}

expect {
	match AatLookup.read([0, 8, 0, 3, 255, 255], 0, 8, 2) {
		Err(Bad(_)) => True
		_ => False
	}
}
