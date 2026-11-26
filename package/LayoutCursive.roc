import Bytes
import LayoutAnchor
import LayoutCoverage
import LayoutVar

## GPOS type 3 format 1. Entry and exit references are relative to the
## subtable. An absent anchor does not make the glyph transparent.
LayoutCursive := {}.{
	read : List(U8), U64, U64, U64, LayoutVar, List(U64) -> Try({ steps : U64, deltas : List(U64) }, [Bad(U64)])
	read = |data, at, glyph_count, steps, lv, deltas| {
		if !Bytes.fits(at, 6, data.len()) or Bytes.u16(data, at) != 1 {
			return Err(Bad(at))
		}
		relative = Bytes.u16(data, at + 2)
		coverage = at + relative
		if relative == 0 or !Bytes.fits(coverage, 4, data.len()) {
			return Err(Bad(at + 2))
		}
		count = Bytes.u16(data, at + 4)
		index = LayoutCoverage.check(data, coverage, glyph_count, steps)?
		if count != index.count or !Bytes.fits(at + 6, 4 * count, data.len()) {
			return Err(Bad(at + 4))
		}
		spent = LayoutVar.spend(data, index.steps, 2 * count).map_err(|_| Bad(at + 4))?
		var $deltas = deltas
		for word in 0..<(2 * count) {
			field = at + 6 + 2 * word
			offset = Bytes.u16(data, field)
			if offset != 0 {
				if !Bytes.fits(at + offset, 6, data.len()) {
					return Err(Bad(field))
				}
				$deltas = LayoutAnchor.check(data, at + offset, lv, $deltas)?
			}
		}
		Ok({ steps: spent, deltas: $deltas })
	}

	## Use only design coordinates for cursive anchors in this slice.
	pair : List(U8), U64, U64, U64 -> Try({ entry : LayoutAnchor.Coordinates, exit : LayoutAnchor.Coordinates }, [NotCovered])
	pair = |data, at, previous, current| {
		coverage = at + Bytes.u16(data, at + 2)
		to = LayoutCoverage.index(data, coverage, current)?
		entry = Bytes.u16(data, at + 6 + 4 * to)
		if entry == 0 {
			return Err(NotCovered)
		}
		from = LayoutCoverage.index(data, coverage, previous)?
		exit = Bytes.u16(data, at + 8 + 4 * from)
		if exit == 0 {
			return Err(NotCovered)
		}
		coords = |offset| {
			anchor = at + offset
			{ x: Bytes.i16(data, anchor + 2), y: Bytes.i16(data, anchor + 4) }
		}
		Ok({ entry: coords(entry), exit: coords(exit) })
	}
}
