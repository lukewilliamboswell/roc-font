import Sfnt
import Bytes

## Glyph classes from a font's `GDEF` table, as the lookup flags of `GSUB`
## and `GPOS` use them: the glyph class definition (base, ligature, mark,
## component), the mark attachment class definition and the mark glyph
## sets. Both layout tables decide with these which glyphs a lookup sees
## (HarfBuzz's `check_glyph_property`), so they share this value.
##
## Internal. Reading is HarfBuzz's: a `GDEF` whose glyph class definition,
## mark attachment class definition or mark glyph sets do not lie inside
## the table, or that holds more work than the reading allowance (see
## `spend`), gives no classes at all, as HarfBuzz's sanitizer drops the
## table whole. Reporting a broken `GDEF` is the business of whoever
## checks the table for the font (`LayoutVar.check_gdef`, as OTS checks
## it). Reading keeps the table's bytes and the offsets of the parts it
## checked, and allocates nothing; queries read class definitions and
## coverages in place.
LayoutGdef := {
	data : List(U8),
	# Offsets in `data`; 0 for an absent part.
	classes : U64,
	attach : U64,
	# The mark glyph sets table and how many sets it has.
	sets : U64,
	set_count : U64,
}.{

	## No `GDEF`: no glyph classes and no mark glyph sets.
	none : LayoutGdef
	none = { data: [], classes: 0, attach: 0, sets: 0, set_count: 0 }

	## The `GDEF` of a font file, or `none` without one or when HarfBuzz
	## would drop it. (Finding the table by its name allocates; `Face`
	## finds it by its tag number and calls `read`.)
	from_tables : List(U8), List(Sfnt.Table) -> LayoutGdef
	from_tables = |bytes, tables|
		match Sfnt.located(bytes, tables, "GDEF", 12) {
			Found({ data, offset: _ }) => LayoutGdef.read(data) ?? LayoutGdef.none
			_ => LayoutGdef.none
		}

	## Read a `GDEF` table (see the module notes). Problems give their offset
	## in the table.
	read : List(U8) -> Try(LayoutGdef, [Bad(U64)])
	read = |data| {
		size = data.len()
		if !Bytes.fits(0, 12, size) or Bytes.u16(data, 0) != 1 {
			return Err(Bad(0))
		}
		minor = Bytes.u16(data, 2)
		classes = Bytes.u16(data, 4)
		attach = Bytes.u16(data, 10)
		sets_at = if (minor >= 2 and Bytes.fits(0, 14, size)) Bytes.u16(data, 12) else 0
		var $steps = 0
		if classes != 0 {
			$steps = LayoutGdef.check_classes(data, classes, $steps)?
		}
		if attach != 0 {
			$steps = LayoutGdef.check_classes(data, attach, $steps)?
		}
		set_count = if (sets_at == 0) 0 else Bytes.u16(data, sets_at + 2)
		if sets_at != 0 {
			if Bytes.u16(data, sets_at) != 1 or !Bytes.fits(sets_at, 4 + 4 * set_count, size) {
				return Err(Bad(sets_at))
			}
			$steps = LayoutGdef.spend(data, $steps, set_count)?
			for k in 0..<set_count {
				$steps = LayoutGdef.check_coverage(data, sets_at + Bytes.u32(data, sets_at + 4 + 4 * k), $steps)?
			}
		}
		Ok({ data, classes, attach, sets: sets_at, set_count })
	}

	## Reading work is counted in steps, one per part visited and one per
	## entry checked; a table that takes more than eight steps per byte
	## (plus a fixed allowance) is refused, as the layout readers refuse
	## one. Offsets may point many times at the same data (every mark glyph
	## set at one large coverage), so a few bytes could otherwise describe
	## billions of entries.
	spend : List(U8), U64, U64 -> Try(U64, [Bad(U64)])
	spend = |data, steps, cost| {
		total = steps + cost + 1
		if (total > 8 * data.len() + 16384) Err(Bad(0)) else Ok(total)
	}

	check_coverage : List(U8), U64, U64 -> Try(U64, [Bad(U64)])
	check_coverage = |data, at, steps| {
		format = Bytes.u16(data, at)
		count = Bytes.u16(data, at + 2)
		if format == 1 and Bytes.fits(at, 4 + 2 * count, data.len()) {
			LayoutGdef.spend(data, steps, count)
		} else if format == 2 and Bytes.fits(at, 4 + 6 * count, data.len()) {
			LayoutGdef.spend(data, steps, count)
		} else {
			Err(Bad(at))
		}
	}

	check_classes : List(U8), U64, U64 -> Try(U64, [Bad(U64)])
	check_classes = |data, at, steps| {
		format = Bytes.u16(data, at)
		if format == 1 and Bytes.fits(at, 6, data.len()) {
			count = Bytes.u16(data, at + 4)
			if (Bytes.fits(at + 6, 2 * count, data.len())) LayoutGdef.spend(data, steps, count) else Err(Bad(at))
		} else if format == 2 and Bytes.fits(at, 4, data.len()) {
			count = Bytes.u16(data, at + 2)
			if (Bytes.fits(at + 4, 6 * count, data.len())) LayoutGdef.spend(data, steps, count) else Err(Bad(at))
		} else {
			Err(Bad(at))
		}
	}

	# ------------------------------------------------------------ queries

	## HarfBuzz's glyph property flags (the low byte of `glyph_props`). The
	## class flags equal the lookup flags that ignore them.
	base_glyph : U64
	base_glyph = 0x02

	ligature : U64
	ligature = 0x04

	mark : U64
	mark = 0x08

	## Whether the `GDEF` has a glyph class definition (HarfBuzz then takes
	## glyph classes from it, not from Unicode).
	has_glyph_classes : LayoutGdef -> Bool
	has_glyph_classes = |gdef| gdef.classes != 0

	## A glyph's properties, as HarfBuzz's `get_glyph_props`: base,
	## ligature, or mark with its attachment class times 256; 0 for
	## unclassified and component glyphs.
	glyph_props : LayoutGdef, U64 -> U64
	glyph_props = |gdef, glyph| {
		klass = if (gdef.classes == 0) 0 else LayoutGdef.class_of(gdef.data, gdef.classes, glyph)
		if klass == 1 {
			LayoutGdef.base_glyph
		} else if klass == 2 {
			LayoutGdef.ligature
		} else if klass == 3 {
			attach = if (gdef.attach == 0) 0 else LayoutGdef.class_of(gdef.data, gdef.attach, glyph)
			LayoutGdef.mark.bitwise_or(attach.bitwise_and(0xFF).shl_wrap(8))
		} else {
			0
		}
	}

	## How many mark glyph sets the `GDEF` has.
	mark_set_count : LayoutGdef -> U64
	mark_set_count = |gdef| gdef.set_count

	## Whether mark glyph set `set` covers a glyph; a set the font lacks
	## covers nothing.
	mark_set_covers : LayoutGdef, U64, U64 -> Bool
	mark_set_covers = |gdef, set, glyph|
		set < gdef.set_count and LayoutGdef.covered(gdef.data, gdef.sets + Bytes.u32(gdef.data, gdef.sets + 4 + 4 * set), glyph)

	## Lookup properties (the lookup flag, plus the mark filtering set times
	## 65536 when the flag uses one) with a mark filtering set the font does
	## not have turned off, as HarfBuzz's `sanitize_lookup_props`.
	sanitize_props : LayoutGdef, U64 -> U64
	sanitize_props = |gdef, props|
		if props.bitwise_and(0x10) != 0 and props.shr_zf_wrap(16) >= gdef.set_count {
			props.bitwise_and(0xFFFFFFFFFFFFFFEF)
		} else {
			props
		}

	## Whether a lookup with properties `match_props` sees a glyph whose
	## glyph properties are `props` (HarfBuzz's
	## `check_glyph_property`): not when the lookup ignores its class; a
	## mark only when it is in the lookup's mark filtering set, or of its
	## mark attachment type, when the lookup names one.
	check_glyph_property : LayoutGdef, U64, U64, U64 -> Bool
	check_glyph_property = |gdef, glyph, props, match_props| {
		g = props.bitwise_and(0xFFFF)
		if g.bitwise_and(match_props).bitwise_and(0x0E) != 0 {
			False
		} else if g.bitwise_and(LayoutGdef.mark) != 0 {
			if match_props.bitwise_and(0x10) != 0 {
				LayoutGdef.mark_set_covers(gdef, match_props.shr_zf_wrap(16), glyph)
			} else if match_props.bitwise_and(0xFF00) != 0 {
				match_props.bitwise_and(0xFF00) == g.bitwise_and(0xFF00)
			} else {
				True
			}
		} else {
			True
		}
	}

	# A glyph in a checked coverage table: binary search of the glyph array
	# (format 1) or of the ranges (format 2), as stored. A range whose last
	# glyph comes before its first matches nothing.
	covered : List(U8), U64, U64 -> Bool
	covered = |data, at, glyph| {
		count = Bytes.u16(data, at + 2)
		var $low = 0
		var $high = count
		var $found = False
		if Bytes.u16(data, at) == 1 {
			while $low < $high {
				mid = ($low + $high) // 2
				probe = Bytes.u16(data, at + 4 + 2 * mid)
				if glyph < probe {
					$high = mid
				} else if glyph > probe {
					$low = mid + 1
				} else {
					$found = True
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
					$found = True
					$low = $high
				}
			}
		}
		$found
	}

	# A glyph's class in a checked class definition: an array of classes
	# from a start glyph (format 1) or ranges searched as stored (format
	# 2). Other glyphs are in class 0.
	class_of : List(U8), U64, U64 -> U64
	class_of = |data, at, glyph|
		if Bytes.u16(data, at) == 1 {
			start = Bytes.u16(data, at + 2)
			if (glyph >= start and glyph - start < Bytes.u16(data, at + 4)) Bytes.u16(data, at + 6 + 2 * (glyph - start)) else 0
		} else {
			var $low = 0
			var $high = Bytes.u16(data, at + 2)
			var $result = 0
			while $low < $high {
				mid = ($low + $high) // 2
				r = at + 4 + 6 * mid
				if glyph < Bytes.u16(data, r) {
					$high = mid
				} else if glyph > Bytes.u16(data, r + 2) {
					$low = mid + 1
				} else {
					$result = Bytes.u16(data, r + 4)
					$low = $high
				}
			}
			$result
		}
}
