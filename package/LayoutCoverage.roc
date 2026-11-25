import Bytes
import LayoutVar

## In-place GPOS coverage lookup after reading has checked each table.
LayoutCoverage := {}.{

	## A checked coverage and the number of covered glyphs. GPOS mark
	## arrays use that count as the exact number of indexed records.
	check : List(U8), U64, U64, U64 -> Try({ count : U64, steps : U64 }, [Bad(U64)])
	check = |data, at, glyph_count, steps| {
		format = Bytes.u16(data, at)
		count = Bytes.u16(data, at + 2)
		width = match format {
			1 => 2
			2 => 6
			_ => return Err(Bad(at))
		}
		if !Bytes.fits(at, 4 + width * count, data.len()) {
			return Err(Bad(at))
		}
		spent = LayoutVar.spend(data, steps, count).map_err(|_| Bad(at))?
		var $previous = 0
		var $index = 0
		for i in 0..<count {
			entry = at + 4 + width * i
			first = Bytes.u16(data, entry)
			last = if (format == 1) first else Bytes.u16(data, entry + 2)
			if (i > 0 and first <= $previous) or last < first or last >= glyph_count {
				return Err(Bad(entry))
			}
			if format == 2 and Bytes.u16(data, entry + 4) != $index {
				return Err(Bad(entry + 4))
			}
			$index = $index + last - first + 1
			$previous = last
		}
		Ok({ count: $index, steps: spent })
	}

	## The coverage index of a glyph in a checked coverage table: a sorted
	## glyph array (format 1) or ranges with their first index (format 2).
	## Ranges are searched as stored; one whose last glyph comes before its
	## first matches nothing.
	index : List(U8), U64, U64 -> Try(U64, [NotCovered])
	index = |data, at, glyph| {
		count = Bytes.u16(data, at + 2)
		var $low = 0
		var $high = count
		var $result = Err(NotCovered)
		if Bytes.u16(data, at) == 1 {
			while $low < $high {
				mid = ($low + $high) // 2
				probe = Bytes.u16(data, at + 4 + 2 * mid)
				if glyph < probe {
					$high = mid
				} else if glyph > probe {
					$low = mid + 1
				} else {
					$result = Ok(mid)
					$low = $high
				}
			}
		} else {
			while $low < $high {
				mid = ($low + $high) // 2
				r = at + 4 + 6 * mid
				if glyph < Bytes.u16(data, r) {
					$high = mid
				} else if glyph > Bytes.u16(data, r + 2) {
					$low = mid + 1
				} else {
					$result = Ok(Bytes.u16(data, r + 4) + glyph - Bytes.u16(data, r))
					$low = $high
				}
			}
		}
		$result
	}

}
