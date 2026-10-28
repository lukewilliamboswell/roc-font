import TableVar

## Layout at any location of a variable font: the deltas `GPOS` adjustments
## take from the `GDEF` item variation store, and the alternate feature
## tables a `GSUB` or `GPOS` table substitutes at some locations.
##
## Internal. Three parts, and a check of the whole `GDEF` table as OTS
## makes it (`check_gdef`), since lenient reading rejects exactly the
## `GDEF` tables OTS rejects:
##
## - The `GDEF` item variation store (`GDEF` version 1.3 `itemVarStoreOffset`)
##   and its location state (`location`): region scalars, computed once per
##   location.
## - Value records with device offsets (`ValueRecord` `xPlaDevice`,
##   `yPlaDevice`, `xAdvDevice`, `yAdvDevice`): `check_gpos` checks, once,
##   every device a pair adjustment can reach; `x_advance` and `value` read a
##   value record in place and add each `VariationIndex` device's delta.
## - `FeatureVariations` (`GSUB`/`GPOS` version 1.1): condition sets and
##   feature table substitutions, read once and flattened, evaluated per
##   location by `substitutions_at`.
##
## Numbers follow HarfBuzz bit for bit (`TableVar` holds the single-precision
## arithmetic). A device delta is the store's single-precision sum rounded
## half up (`roundf` in HarfBuzz is `floor(x + 0.5)`), added to the value
## record's own value, each device separately. HarfBuzz applies no device
## at the default location (every coordinate zero), even where a malformed
## region would give a nonzero scalar there, so neither does this module.
## Hinting devices (delta formats 1 to 3) adjust by pixels per em, which a
## font-unit result never has, so they add nothing (HarfBuzz at a ppem of 0).
##
## After a successful read every query here is total.
LayoutVar := {
	# The GDEF store; with no store, one with no data subtables, in which
	# only `no_variation` is a valid index.
	store : TableVar.Store,
}.{

	## What was wrong, where. `offset` is from the start of `table`.
	Problem : { table : Str, offset : U64, reason : Reason }

	Reason : [
		Truncated,
		UnsupportedVersion,
		BadFormat,
		BadRecordSize,
		TooManyAxes,
		AxisOrder,
		AxisCountMismatch,
		MapMissingIdentity,
		MapOrder,
		MapRange,
		TooManyRegions,
		RegionIndex,
		WordCount,
		DeltaIndex,
		ItemCount,
		TagOrder,
		NoAxes,
		AxisTag,
		RegionOrder,
		RegionRange,
		DeviceFormat,
		GlyphIndex,
		RangeOrder,
		ClassValue,
		AxisIndex,
		FeatureIndex,
		LookupIndex,
		SubstitutionOrder,
		NestingDepth,
		TooMuchWork,
	]

	## The location state for layout: whether any coordinate is nonzero
	## (HarfBuzz applies devices only then) and the `GDEF` store's region
	## scalars, as `TableVar.region_scalars` computes them.
	Location : { active : Bool, scalars : List(U32) }

	## A value record's four values at a location, in font units.
	Value : { x_placement : I64, y_placement : I64, x_advance : I64, y_advance : I64 }

	## A table's `FeatureVariations`, read and checked. Record r's condition
	## set is the postfix program `kinds[starts[r]]` up to `starts[r + 1]`
	## (with operands `a`, `b`, `c`); its substitutions are entries
	## `substitution_starts[r]` up to `substitution_starts[r + 1]` of
	## `features` (feature indices, in the table's order) and `tables` (the
	## offset in `data` of each alternate feature table).
	##
	## Lookup variation records (version 1.1 of the `FeatureVariations`
	## table, an extension HarfBuzz reads): record v replaces the lookups of
	## feature `lookup_features[v]` with those of its conditions that hold,
	## plus the feature's own (after substitution) when `lookup_defaults[v]`.
	## Its conditions are entries `lookup_record_starts[v]` up to
	## `lookup_record_starts[v + 1]` of `condition_starts` (where each
	## condition's program starts, one more entry closing the last) and
	## `condition_lookups` (the offset in `data` of each condition's lookup
	## index list, 0 for none).
	FeatureVariations : {
		data : List(U8),
		starts : List(U64),
		kinds : List(U8),
		a : List(I64),
		b : List(I64),
		c : List(I64),
		uses_values : Bool,
		substitution_starts : List(U64),
		features : List(U64),
		tables : List(U64),
		lookup_features : List(U64),
		lookup_defaults : List(Bool),
		lookup_record_starts : List(U64),
		condition_starts : List(U64),
		condition_lookups : List(U64),
	}

	# ------------------------------------------------------------ limits

	## Nested conditions accepted (HarfBuzz's `HB_MAX_NESTING_LEVEL`).
	nesting_limit : U64
	nesting_limit = 64

	## Reading work is counted in steps, one per table visited and one per
	## entry checked. Offsets may point many times at the same data, so a few
	## bytes could describe billions of entries; a table that takes more than
	## eight steps per byte (plus a fixed allowance) is refused, as
	## `LayoutKerning` refuses one.
	spend : List(U8), U64, U64 -> Try(U64, [TooMuchWork])
	spend = |data, steps, cost| {
		total = steps + cost + 1
		if (total > 8 * data.len() + 16384) Err(TooMuchWork) else Ok(total)
	}

	# ------------------------------------------------------------ GDEF

	## No `GDEF` store: every device delta is zero.
	none : U64 -> LayoutVar
	none = |axis_count| { store: LayoutVar.empty_store(axis_count) }

	empty_store : U64 -> TableVar.Store
	# No data subtables, so no list is ever indexed (`TableVar.delta` stops
	# at the item count) and nothing is allocated.
	empty_store = |axis_count| { axis_count, region_count: 0, regions: [], item_counts: [], word_counts: [], long_words: [], index_starts: [], region_indexes: [], row_starts: [], row_sizes: [], bytes: [] }

	## Read the item variation store of a `GDEF` table for a font with
	## `axis_count` axes. A `GDEF` before version 1.3, or with a null store
	## offset, has none.
	read_gdef : List(U8), U64 -> Try(LayoutVar, List(Problem))
	read_gdef = |gdef, axis_count| {
		bad = |at, reason| Err([{ table: "GDEF", offset: at, reason }])
		if gdef.len() < 4 {
			return bad(0, Truncated)
		}
		if TableVar.u16(gdef, 0) != 1 {
			return bad(0, UnsupportedVersion)
		}
		if TableVar.u16(gdef, 2) < 3 {
			return Ok(LayoutVar.none(axis_count))
		}
		if gdef.len() < 18 {
			return bad(0, Truncated)
		}
		at = TableVar.u32(gdef, 14)
		if at == 0 {
			return Ok(LayoutVar.none(axis_count))
		}
		match TableVar.read_store(gdef, "GDEF", at, axis_count) {
			Ok(store) => Ok({ store: store })
			Err(problems) => Err(problems.map(LayoutVar.from_var))
		}
	}

	has_store : LayoutVar -> Bool
	has_store = |lv| !lv.store.item_counts.is_empty()

	from_var : TableVar.Problem -> Problem
	from_var = |p| {
		reason = match p.reason {
			Truncated => Truncated
			UnsupportedVersion => UnsupportedVersion
			BadFormat => BadFormat
			BadRecordSize => BadRecordSize
			TooManyAxes => TooManyAxes
			AxisOrder => AxisOrder
			AxisCountMismatch => AxisCountMismatch
			MapMissingIdentity => MapMissingIdentity
			MapOrder => MapOrder
			MapRange => MapRange
			TooManyRegions => TooManyRegions
			RegionIndex => RegionIndex
			WordCount => WordCount
			DeltaIndex => DeltaIndex
			ItemCount => ItemCount
			TagOrder => TagOrder
			NoAxes => NoAxes
			AxisTag => AxisTag
			RegionOrder => RegionOrder
			RegionRange => RegionRange
		}
		{ table: p.table, offset: p.offset, reason }
	}

	# ------------------------------------------------------------ GDEF structure

	## Check a whole `GDEF` table as OTS 9.3.0 checks it (`gdef.cc`), so
	## lenient reading rejects exactly the `GDEF` tables browsers reject:
	## the header (version 1.0, 1.2 or 1.3 and later; there is no 1.1), the
	## glyph class definition (classes up to 4), the attachment point list,
	## the ligature caret list with its caret values and device tables, the
	## mark attachment class definition, the mark glyph sets and the item
	## variation store (`TableVar.check_store_ots`, with `axes` the `fvar`
	## axis count, or `Absent` without `fvar`). Coverage and class
	## definitions name glyphs below `glyph_count`, as OTS requires. Work is
	## bounded like every other reader's (`spend`): a table that would take
	## more than eight steps per byte is refused, where OTS would take the
	## time.
	check_gdef : List(U8), U64, [Present(U64), Absent] -> Try({}, Problem)
	check_gdef = |gdef, glyph_count, axes| {
		size = gdef.len()
		bad = |at, reason| Err({ table: "GDEF", offset: at, reason })
		if size < 12 {
			return bad(0, Truncated)
		}
		minor = TableVar.u16(gdef, 2)
		if TableVar.u16(gdef, 0) != 1 or minor == 1 {
			return bad(0, UnsupportedVersion)
		}
		header_end = 12 + (if (minor >= 2) 2 else 0) + (if (minor >= 3) 4 else 0)
		if size < header_end {
			return bad(0, Truncated)
		}
		# An offset to a part: inside the table and after the header.
		part = |field, value|
			if value == 0 {
				Ok(Absent)
			} else if value >= size or value < header_end {
				Err({ table: "GDEF", offset: field, reason: Truncated })
			} else {
				Ok(Present(value))
			}
		var $steps = 0
		match part(4, TableVar.u16(gdef, 4))? {
			Present(at) => {
				$steps = LayoutVar.check_class_def(gdef, at, glyph_count, 4, $steps)?
			}
			Absent => {}
		}
		match part(6, TableVar.u16(gdef, 6))? {
			Present(at) => {
				$steps = LayoutVar.check_attach_list(gdef, at, glyph_count, $steps)?
			}
			Absent => {}
		}
		match part(8, TableVar.u16(gdef, 8))? {
			Present(at) => {
				$steps = LayoutVar.check_caret_list(gdef, at, glyph_count, $steps)?
			}
			Absent => {}
		}
		match part(10, TableVar.u16(gdef, 10))? {
			Present(at) => {
				$steps = LayoutVar.check_class_def(gdef, at, glyph_count, 0xFFFF, $steps)?
			}
			Absent => {}
		}
		if minor >= 2 {
			match part(12, TableVar.u16(gdef, 12))? {
				Present(at) => {
					$steps = LayoutVar.check_mark_sets(gdef, at, glyph_count, $steps)?
				}
				Absent => {}
			}
		}
		if minor >= 3 {
			match part(14, TableVar.u32(gdef, 14))? {
				Present(at) => {
					match TableVar.check_store_ots(gdef, at, axes) {
						Ok(_) => {}
						Err(offset) => return bad(offset, BadFormat)
					}
				}
				Absent => {}
			}
		}
		Ok({})
	}

	# Spend steps for `cost` entries, as a `GDEF` problem at `at`.
	gdef_spend : List(U8), U64, U64, U64 -> Try(U64, Problem)
	gdef_spend = |data, steps, cost, at|
		match LayoutVar.spend(data, steps, cost) {
			Ok(s) => Ok(s)
			Err(TooMuchWork) => Err({ table: "GDEF", offset: at, reason: TooMuchWork })
		}

	## OTS's `ParseCoverageTable` on the coverage at `at` (to the table's
	## end), for a font of `glyph_count` glyphs.
	check_coverage_ots : List(U8), U64, U64, U64 -> Try(U64, Problem)
	check_coverage_ots = |data, at, glyph_count, steps| {
		size = data.len()
		bad = |offset, reason| Err({ table: "GDEF", offset, reason })
		if !TableVar.fits(at, 4, size) {
			return bad(at, Truncated)
		}
		format = TableVar.u16(data, at)
		count = TableVar.u16(data, at + 2)
		if format == 1 {
			if count > glyph_count {
				return bad(at + 2, GlyphIndex)
			}
			if !TableVar.fits(at + 4, 2 * count, size) {
				return bad(at, Truncated)
			}
			for i in 0..<count {
				if TableVar.u16(data, at + 4 + 2 * i) >= glyph_count {
					return bad(at + 4 + 2 * i, GlyphIndex)
				}
			}
			LayoutVar.gdef_spend(data, steps, count, at)
		} else if format == 2 {
			if count > glyph_count {
				return bad(at + 2, GlyphIndex)
			}
			if !TableVar.fits(at + 4, 6 * count, size) {
				return bad(at, Truncated)
			}
			var $last_end = 0
			var $index = 0
			for i in 0..<count {
				r = at + 4 + 6 * i
				first = TableVar.u16(data, r)
				last = TableVar.u16(data, r + 2)
				if first > last or ($last_end != 0 and first < $last_end) {
					return bad(r, RangeOrder)
				}
				if TableVar.u16(data, r + 4) != $index {
					return bad(r + 4, RangeOrder)
				}
				$last_end = last
				# OTS keeps the running index in 16 bits.
				$index = ($index + last - first + 1).bitwise_and(0xFFFF)
			}
			LayoutVar.gdef_spend(data, steps, count, at)
		} else {
			bad(at, BadFormat)
		}
	}

	## OTS's `ParseClassDefTable` at `at` with classes up to `classes`.
	check_class_def : List(U8), U64, U64, U64, U64 -> Try(U64, Problem)
	check_class_def = |data, at, glyph_count, classes, steps| {
		size = data.len()
		bad = |offset, reason| Err({ table: "GDEF", offset, reason })
		if !TableVar.fits(at, 4, size) {
			return bad(at, Truncated)
		}
		format = TableVar.u16(data, at)
		if format == 1 {
			start = TableVar.u16(data, at + 2)
			if start >= glyph_count {
				return bad(at + 2, GlyphIndex)
			}
			if !TableVar.fits(at + 4, 2, size) {
				return bad(at, Truncated)
			}
			count = TableVar.u16(data, at + 4)
			if count > glyph_count {
				return bad(at + 4, GlyphIndex)
			}
			if !TableVar.fits(at + 6, 2 * count, size) {
				return bad(at, Truncated)
			}
			for i in 0..<count {
				if TableVar.u16(data, at + 6 + 2 * i) > classes {
					return bad(at + 6 + 2 * i, ClassValue)
				}
			}
			LayoutVar.gdef_spend(data, steps, count, at)
		} else if format == 2 {
			count = TableVar.u16(data, at + 2)
			if count > glyph_count {
				return bad(at + 2, GlyphIndex)
			}
			if !TableVar.fits(at + 4, 6 * count, size) {
				return bad(at, Truncated)
			}
			var $last_end = 0
			for i in 0..<count {
				r = at + 4 + 6 * i
				first = TableVar.u16(data, r)
				last = TableVar.u16(data, r + 2)
				if first > last or ($last_end != 0 and first <= $last_end) {
					return bad(r, RangeOrder)
				}
				if TableVar.u16(data, r + 4) > classes {
					return bad(r + 4, ClassValue)
				}
				$last_end = last
			}
			LayoutVar.gdef_spend(data, steps, count, at)
		} else {
			bad(at, BadFormat)
		}
	}

	# OTS's `ParseAttachListTable`.
	check_attach_list : List(U8), U64, U64, U64 -> Try(U64, Problem)
	check_attach_list = |gdef, at, glyph_count, steps| {
		length = gdef.len() - at
		bad = |offset, reason| Err({ table: "GDEF", offset, reason })
		if length < 4 {
			return bad(at, Truncated)
		}
		coverage = TableVar.u16(gdef, at)
		count = TableVar.u16(gdef, at + 2)
		points_end = 2 * count + 4
		if points_end > 0xFFFF or coverage == 0 or coverage >= length or coverage < points_end {
			return bad(at, Truncated)
		}
		if count > glyph_count {
			return bad(at + 2, GlyphIndex)
		}
		if length < points_end {
			return bad(at, Truncated)
		}
		for i in 0..<count {
			p = TableVar.u16(gdef, at + 4 + 2 * i)
			if p >= length or p < points_end {
				return bad(at + 4 + 2 * i, Truncated)
			}
		}
		var $steps = LayoutVar.check_coverage_ots(gdef, at + coverage, glyph_count, steps)?
		for i in 0..<count {
			p = at + TableVar.u16(gdef, at + 4 + 2 * i)
			if !TableVar.fits(p, 2, gdef.len()) {
				return bad(p, Truncated)
			}
			points = TableVar.u16(gdef, p)
			if points == 0 {
				return bad(p, Truncated)
			}
			if !TableVar.fits(p + 2, 2 * points, gdef.len()) {
				return bad(p, Truncated)
			}
			$steps = LayoutVar.gdef_spend(gdef, $steps, points, p)?
			var $last = 0
			for j in 0..<points {
				index = TableVar.u16(gdef, p + 2 + 2 * j)
				if $last != 0 and $last >= index {
					return bad(p + 2 + 2 * j, RangeOrder)
				}
				$last = index
			}
		}
		Ok($steps)
	}

	# OTS's `ParseLigCaretListTable`.
	check_caret_list : List(U8), U64, U64, U64 -> Try(U64, Problem)
	check_caret_list = |gdef, at, glyph_count, steps| {
		length = gdef.len() - at
		bad = |offset, reason| Err({ table: "GDEF", offset, reason })
		if length < 4 {
			return bad(at, Truncated)
		}
		coverage = TableVar.u16(gdef, at)
		count = TableVar.u16(gdef, at + 2)
		glyphs_end = 2 * count + 4
		if glyphs_end > 0xFFFF or coverage == 0 or coverage >= length or coverage < glyphs_end {
			return bad(at, Truncated)
		}
		if count > glyph_count {
			return bad(at + 2, GlyphIndex)
		}
		if length < glyphs_end {
			return bad(at, Truncated)
		}
		for i in 0..<count {
			g = TableVar.u16(gdef, at + 4 + 2 * i)
			if g >= length or g < glyphs_end {
				return bad(at + 4 + 2 * i, Truncated)
			}
		}
		var $steps = LayoutVar.check_coverage_ots(gdef, at + coverage, glyph_count, steps)?
		for i in 0..<count {
			lig = TableVar.u16(gdef, at + 4 + 2 * i)
			g = at + lig
			if !TableVar.fits(g, 2, gdef.len()) {
				return bad(g, Truncated)
			}
			carets = TableVar.u16(gdef, g)
			if carets == 0 {
				return bad(g, Truncated)
			}
			if !TableVar.fits(g + 2, 2 * carets, gdef.len()) {
				return bad(g, Truncated)
			}
			$steps = LayoutVar.gdef_spend(gdef, $steps, carets, g)?
			offsets_end = 2 * carets + 2
			for j in 0..<carets {
				c = TableVar.u16(gdef, g + 2 + 2 * j)
				if c >= length or c < offsets_end {
					return bad(g + 2 + 2 * j, Truncated)
				}
			}
			for j in 0..<carets {
				value_at = g + TableVar.u16(gdef, g + 2 + 2 * j)
				if !TableVar.fits(value_at, 4, gdef.len()) {
					return bad(value_at, Truncated)
				}
				format = TableVar.u16(gdef, value_at)
				if format == 0 or format > 3 {
					return bad(value_at, BadFormat)
				}
				if format == 3 {
					if !TableVar.fits(value_at + 4, 2, gdef.len()) {
						return bad(value_at, Truncated)
					}
					device = TableVar.u16(gdef, value_at + 4)
					# OTS measures this offset from the ligature glyph's table.
					absolute = lig + TableVar.u16(gdef, g + 2 + 2 * j) + device
					if device == 0 or absolute >= length {
						return bad(value_at + 4, Truncated)
					}
					match LayoutVar.check_device_ots(gdef, at + absolute) {
						Ok(_) => {}
						Err(reason) => return bad(at + absolute, reason)
					}
				}
			}
		}
		Ok($steps)
	}

	## OTS's `ParseDeviceTable` at `at` (to the table's end).
	check_device_ots : List(U8), U64 -> Try({}, Reason)
	check_device_ots = |data, at| {
		if !TableVar.fits(at, 6, data.len()) {
			return Err(Truncated)
		}
		start = TableVar.u16(data, at)
		end = TableVar.u16(data, at + 2)
		format = TableVar.u16(data, at + 4)
		if format == 0x8000 {
			Ok({})
		} else if start > end or format == 0 or format > 3 {
			Err(DeviceFormat)
		} else {
			units = (end - start) // (1.U64).shl_wrap((4 - format).to_u8_wrap()) + 1
			if (TableVar.fits(at + 6, 2 * units, data.len())) Ok({}) else Err(Truncated)
		}
	}

	# OTS's `ParseMarkGlyphSetsDefTable`.
	check_mark_sets : List(U8), U64, U64, U64 -> Try(U64, Problem)
	check_mark_sets = |gdef, at, glyph_count, steps| {
		length = gdef.len() - at
		bad = |offset, reason| Err({ table: "GDEF", offset, reason })
		if length < 4 {
			return bad(at, Truncated)
		}
		if TableVar.u16(gdef, at) != 1 {
			return bad(at, BadFormat)
		}
		count = TableVar.u16(gdef, at + 2)
		sets_end = 2 * count + 4
		if sets_end > 0xFFFF {
			return bad(at + 2, Truncated)
		}
		var $steps = LayoutVar.gdef_spend(gdef, steps, count, at)?
		for i in 0..<count {
			if !TableVar.fits(at + 4 + 4 * i, 4, gdef.len()) {
				return bad(at + 4 + 4 * i, Truncated)
			}
			coverage = TableVar.u32(gdef, at + 4 + 4 * i)
			if coverage >= length or coverage < sets_end {
				return bad(at + 4 + 4 * i, Truncated)
			}
			$steps = LayoutVar.check_coverage_ots(gdef, at + coverage, glyph_count, $steps)?
		}
		Ok($steps)
	}

	# ------------------------------------------------------------ location

	## The location state at normalised coordinates (F2Dot14, one per axis).
	## At the default location nothing is computed.
	location : LayoutVar, List(I16) -> Location
	location = |lv, coords|
		if coords.any(|c| c != 0) {
			{ active: True, scalars: TableVar.region_scalars(lv.store, coords) }
		} else {
			LayoutVar.default_location
		}

	## MATH facts use the variation store at every location, including a
	## default or zero-axis region, without a shaper-specific 2.30 cache.
	math_location : LayoutVar, List(I16) -> Location
	math_location = |lv, coords| if (lv.store.region_count == 0) LayoutVar.default_location else { active: True, scalars: TableVar.region_scalars_precise(lv.store, coords) }

	## The default location: no device applies.
	default_location : Location
	default_location = { active: False, scalars: [] }

	## Whether an outer/inner pair names a prepared variation-store row,
	## including the format's no-variation sentinel. Readers use this
	## before retaining variation indices in other font tables.
	valid_index : LayoutVar, U64, U64 -> Bool
	valid_index = |lv, outer, inner| TableVar.valid_index(lv.store, outer, inner)

	## Validate the device or variation index referenced by a checked
	## positioning record. Offsets in the record are relative to `base`.
	check_device_index : LayoutVar, List(U8), U64, U64 -> Bool
	check_device_index = |lv, data, base, field| LayoutVar.check_device(lv.store.item_counts, data, base, field).is_ok()

	## The delta of a `VariationIndex` (outer and inner index) at a
	## location, rounded half up as HarfBuzz rounds it: `em_scalef`
	## multiplies the single-precision sum by `x_scale / upem`, which is
	## exactly 1 at a scale of units per em whatever the units per em, then
	## takes `floorf(v + 0.5f)`, so the only roundings are the sum's and
	## that addition's. `no_variation` has none.
	delta : LayoutVar, Location, U64, U64 -> I64
	delta = |lv, loc, outer, inner|
		if loc.active {
			TableVar.f32_round_half_up(TableVar.delta(lv.store, loc.scalars, outer, inner))
		} else {
			0
		}

	# ------------------------------------------------------------ value records

	## Size in bytes of a value record of a format. Only the eight defined
	## bits count, as in HarfBuzz and `LayoutKerning`.
	value_size : U64 -> U64
	value_size = |format| 2 * LayoutVar.bits(format, 0xFF)

	bits : U64, U64 -> U64
	bits = |format, mask| format.bitwise_and(mask).to_u8_wrap().count_one_bits().to_u64()

	## Whether a value format has a device offset that can vary the x
	## advance. Without one, `x_advance` is the stored value.
	varies_x_advance : U64 -> Bool
	varies_x_advance = |format| format.bitwise_and(0x40) != 0

	## The x advance of a checked value record at `at` in `data`, with
	## `format`, at a location: its stored value plus its device's delta.
	## Device offsets count from `base`: the pair set for pair adjustment
	## format 1, the subtable for format 2 (as HarfBuzz and fontTools).
	x_advance : LayoutVar, Location, List(U8), U64, U64, U64 -> I64
	x_advance = |lv, loc, data, base, at, format| {
		stored = if (format.bitwise_and(4) == 0) 0 else TableVar.i16(data, at + 2 * LayoutVar.bits(format, 3))
		if loc.active and format.bitwise_and(0x40) != 0 {
			stored + LayoutVar.device_delta(lv, loc, data, base, at + 2 * LayoutVar.bits(format, 0x3F))
		} else {
			stored
		}
	}

	## All four values of a checked value record at a location; see
	## `x_advance`. A y advance applies only to vertical text and the
	## placements only once glyph offsets are positioned; the caller picks.
	value : LayoutVar, Location, List(U8), U64, U64, U64 -> Value
	value = |lv, loc, data, base, at, format| {
		field = |bit| at + 2 * LayoutVar.bits(format, bit - 1)
		stored = |bit| if (format.bitwise_and(bit) == 0) 0 else TableVar.i16(data, field(bit))
		varied = |bit| if (loc.active and format.bitwise_and(bit) != 0) LayoutVar.device_delta(lv, loc, data, base, field(bit)) else 0
		{
			x_placement: stored(0x01) + varied(0x10),
			y_placement: stored(0x02) + varied(0x20),
			x_advance: stored(0x04) + varied(0x40),
			y_advance: stored(0x08) + varied(0x80),
		}
	}

	# The delta of the checked device whose offset (from `base`) is at
	# `field`: a `VariationIndex` table's, or none.
	device_delta : LayoutVar, Location, List(U8), U64, U64 -> I64
	device_delta = |lv, loc, data, base, field| {
		offset = TableVar.u16(data, field)
		if offset == 0 {
			0
		} else {
			device = base + offset
			if (TableVar.u16(data, device + 4) == 0x8000) LayoutVar.delta(lv, loc, TableVar.u16(data, device), TableVar.u16(data, device + 2)) else 0
		}
	}

	# ------------------------------------------------------------ checking devices

	## Check every device offset of every pair adjustment value record in a
	## `GPOS` table (lookup type 2, directly or through an extension) that a
	## query can reach: each device lies inside the table, has a delta format
	## of 1 to 3 or `VariationIndex` (0x8000), and a `VariationIndex` names a
	## row of the `GDEF` store or is `no_variation` in both halves. Returns
	## how many device offsets were checked. One problem is reported per bad
	## subtable. A pair set of a first glyph at or past `glyph_count` is never
	## looked at, so it is not checked (as `LayoutKerning`).
	check_gpos : LayoutVar, List(U8), U64 -> Try(U64, List(Problem))
	check_gpos = |lv, gpos, glyph_count| {
		bad = |at, reason| Err([{ table: "GPOS", offset: at, reason }])
		size = gpos.len()
		if size < 10 {
			return bad(0, Truncated)
		}
		if TableVar.u16(gpos, 0) != 1 {
			return bad(0, UnsupportedVersion)
		}
		lookups = TableVar.u16(gpos, 8)
		if !TableVar.fits(lookups, 2, size) {
			return bad(8, Truncated)
		}
		lookup_count = TableVar.u16(gpos, lookups)
		if !TableVar.fits(lookups + 2, 2 * lookup_count, size) {
			return bad(lookups, Truncated)
		}
		var $steps = match LayoutVar.spend(gpos, 0, lookup_count) {
			Ok(s) => s
			Err(TooMuchWork) => return bad(lookups, TooMuchWork)
		}
		var $problems = []
		var $checked = 0
		for index in 0..<lookup_count {
			lookup = lookups + TableVar.u16(gpos, lookups + 2 + 2 * index)
			kind = TableVar.u16(gpos, lookup)
			count = TableVar.u16(gpos, lookup + 4)
			if kind != 2 and kind != 9 {
				{}
			} else if !TableVar.fits(lookup, 6 + 2 * count, size) {
				$problems = $problems.append({ table: "GPOS", offset: lookup, reason: Truncated })
			} else {
				for s in 0..<count {
					at = lookup + TableVar.u16(gpos, lookup + 6 + 2 * s)
					target =
						if kind == 2 {
							Pair(at)
						} else if !TableVar.fits(at, 8, size) {
							Broken(at)
						} else if TableVar.u16(gpos, at + 2) == 2 {
							Pair(at + TableVar.u32(gpos, at + 4))
						} else {
							Other
						}
					match target {
						Pair(start) =>
							match LayoutVar.check_pair(lv, gpos, start, glyph_count, $steps) {
								Ok(done) => {
									$steps = done.steps
									$checked = $checked + done.checked
								}
								Err(BadAt(problem)) => {
									$problems = $problems.append(problem)
								}
								Err(Exhausted(problem)) => return Err($problems.append(problem))
							}
						Broken(start) => {
							$problems = $problems.append({ table: "GPOS", offset: start, reason: Truncated })
						}
						Other => {}
					}
				}
			}
		}
		if ($problems.is_empty()) Ok($checked) else Err($problems)
	}

	## Check the devices of one pair adjustment subtable at `at`, spending
	## from `steps`. A subtable whose value formats have no device costs one
	## step. `Exhausted` means the table's work allowance ran out.
	check_pair : LayoutVar, List(U8), U64, U64, U64 -> Try({ steps : U64, checked : U64 }, [BadAt(Problem), Exhausted(Problem)])
	check_pair = |lv, data, at, glyph_count, steps| {
		size = data.len()
		bad = |offset, reason| Err(BadAt({ table: "GPOS", offset, reason }))
		if !TableVar.fits(at, 10, size) {
			return bad(at, Truncated)
		}
		format = TableVar.u16(data, at)
		format1 = TableVar.u16(data, at + 4)
		format2 = TableVar.u16(data, at + 6)
		if format1.bitwise_or(format2).bitwise_and(0xF0) == 0 {
			return Ok({ steps: steps + 1, checked: 0 })
		}
		size1 = LayoutVar.value_size(format1)
		size2 = LayoutVar.value_size(format2)
		# Only the store's row counts are needed per device.
		items = lv.store.item_counts
		coverage = at + TableVar.u16(data, at + 2)
		covered = TableVar.u16(data, coverage + 2)
		coverage_format = TableVar.u16(data, coverage)
		if !TableVar.fits(coverage, 4, size) {
			return bad(at + 2, Truncated)
		}
		if coverage_format != 1 and coverage_format != 2 {
			return bad(coverage, BadFormat)
		}
		if !TableVar.fits(coverage + 4, (if (coverage_format == 1) 2 else 6) * covered, size) {
			return bad(coverage, Truncated)
		}
		exhausted = |offset| Err(Exhausted({ table: "GPOS", offset, reason: TooMuchWork }))
		var $steps = match LayoutVar.spend(data, steps, covered) {
			Ok(s) => s
			Err(TooMuchWork) => return exhausted(coverage)
		}
		var $checked = 0
		if format == 1 {
			set_count = TableVar.u16(data, at + 8)
			if !TableVar.fits(at + 10, 2 * set_count, size) {
				return bad(at + 8, Truncated)
			}
			record = 2 + size1 + size2
			# The pair set indices a query can reach, each a run of
			# consecutive indices.
			for i in 0..<covered {
				span =
					if coverage_format == 1 {
						glyph = TableVar.u16(data, coverage + 4 + 2 * i)
						if (glyph < glyph_count and i < set_count) { first: i, count: 1 } else { first: 0, count: 0 }
					} else {
						r = coverage + 4 + 6 * i
						first = TableVar.u16(data, r)
						last = TableVar.u16(data, r + 2)
						index = TableVar.u16(data, r + 4)
						if first <= last and first < glyph_count and index < set_count {
							{ first: index, count: (last.min(glyph_count - 1) - first + 1).min(set_count - index) }
						} else {
							{ first: 0, count: 0 }
						}
					}
				for k in 0..<span.count {
					field = at + 10 + 2 * (span.first + k)
					set = at + TableVar.u16(data, field)
					pairs = TableVar.u16(data, set)
					if !TableVar.fits(set, 2, size) or !TableVar.fits(set + 2, record * pairs, size) {
						return bad(field, Truncated)
					}
					$steps = match LayoutVar.spend(data, $steps, pairs) {
						Ok(s) => s
						Err(TooMuchWork) => return exhausted(set)
					}
					for p in 0..<pairs {
						r = set + 2 + record * p
						match LayoutVar.check_devices(items, data, set, r + 2, format1) {
							Ok(n) => {
								$checked = $checked + n
							}
							Err(problem) => return Err(BadAt(problem))
						}
						match LayoutVar.check_devices(items, data, set, r + 2 + size1, format2) {
							Ok(n) => {
								$checked = $checked + n
							}
							Err(problem) => return Err(BadAt(problem))
						}
					}
				}
			}
		} else if format == 2 {
			if !TableVar.fits(at, 16, size) {
				return bad(at, Truncated)
			}
			height = TableVar.u16(data, at + 12)
			width = TableVar.u16(data, at + 14)
			cells = height * width
			if !TableVar.fits(at + 16, (size1 + size2) * cells, size) {
				return bad(at + 12, Truncated)
			}
			$steps = match LayoutVar.spend(data, $steps, cells) {
				Ok(s) => s
				Err(TooMuchWork) => return exhausted(at + 12)
			}
			for cell in 0..<cells {
				r = at + 16 + (size1 + size2) * cell
				match LayoutVar.check_devices(items, data, at, r, format1) {
					Ok(n) => {
						$checked = $checked + n
					}
					Err(problem) => return Err(BadAt(problem))
				}
				match LayoutVar.check_devices(items, data, at, r + size1, format2) {
					Ok(n) => {
						$checked = $checked + n
					}
					Err(problem) => return Err(BadAt(problem))
				}
			}
		} else {
			return bad(at, BadFormat)
		}
		Ok({ steps: $steps, checked: $checked })
	}

	## Check the device offsets of the value record at `at` (inside the
	## table) with `format`, counted from `base`. Returns how many there are.
	## `items` is the store's row count per data subtable
	## (`TableVar.Store.item_counts`).
	check_devices : List(U64), List(U8), U64, U64, U64 -> Try(U64, Problem)
	check_devices = |items, data, base, at, format| {
		# The device fields follow the values: their offsets in the record
		# are found once per record, with no list.
		var $n = 0
		var $field = at + 2 * LayoutVar.bits(format, 0x0F)
		var $bit = 0x10
		while $bit <= 0x80 {
			if format.bitwise_and($bit) != 0 {
				LayoutVar.check_device(items, data, base, $field)?
				$field = $field + 2
				$n = $n + 1
			}
			$bit = $bit * 2
		}
		Ok($n)
	}

	check_device : List(U64), List(U8), U64, U64 -> Try({}, Problem)
	check_device = |items, data, base, field| {
		offset = TableVar.u16(data, field)
		device = base + offset
		delta_format = TableVar.u16(data, device + 4)
		if offset == 0 {
			Ok({})
		} else if !TableVar.fits(device, 6, data.len()) {
			Err({ table: "GPOS", offset: field, reason: Truncated })
		} else if delta_format == 0x8000 {
			outer = TableVar.u16(data, device)
			inner = TableVar.u16(data, device + 2)
			# `TableVar.valid_index` on the row counts alone.
			if ((outer == TableVar.no_variation and inner == TableVar.no_variation) or inner < (items.get(outer) ?? 0)) Ok({}) else Err({ table: "GPOS", offset: device, reason: DeltaIndex })
		} else if delta_format >= 1 and delta_format <= 3 {
			Ok({})
		} else {
			Err({ table: "GPOS", offset: device + 4, reason: DeviceFormat })
		}
	}

	# ------------------------------------------------------------ feature variations

	## No feature variations.
	no_feature_variations : FeatureVariations
	no_feature_variations = { data: [], starts: [0], kinds: [], a: [], b: [], c: [], uses_values: False, substitution_starts: [0], features: [], tables: [], lookup_features: [], lookup_defaults: [], lookup_record_starts: [0], condition_starts: [0], condition_lookups: [] }

	# Condition program operations.
	op_true : U8
	op_true = 0

	op_false : U8
	op_false = 1

	op_range : U8
	op_range = 2

	op_value : U8
	op_value = 3

	op_and : U8
	op_and = 4

	op_or : U8
	op_or = 5

	op_not : U8
	op_not = 6

	## Read the `FeatureVariations` of a `GSUB` or `GPOS` table (`table` is
	## its tag, for problems) for a font with `axis_count` axes. A table
	## before version 1.1, or with a null offset, has none.
	##
	## Each record's condition set and its conditions are read into one flat
	## postfix program: axis ranges (format 1), values from the `GDEF` store
	## (format 2), and the combinations and, or and not (formats 3 to 5) as
	## HarfBuzz reads them. A null condition holds (HarfBuzz's format 0); a
	## condition of an unknown format does not hold, as the specification
	## asks. Conditions nest at most `nesting_limit` deep. As OTS requires,
	## each condition of a set and each alternate feature table lies after
	## its offset and inside the table, a range condition directly in a set
	## stays inside [-1, 1], and each alternate feature table's lookups
	## exist. Substitutions may name features in any order, and features the
	## table lacks (which never apply); `substitutions_at` keeps the first
	## for a feature, as HarfBuzz does. Lookup variation records (version 1.1
	## of the `FeatureVariations` table, which HarfBuzz reads) follow the
	## records; see the note in the body for how they are checked.
	read_feature_variations : List(U8), Str, LayoutVar, U64 -> Try(FeatureVariations, List(Problem))
	read_feature_variations = |data, table, lv, axis_count| {
		size = data.len()
		bad = |at, reason| Err([{ table, offset: at, reason }])
		if size < 10 {
			return bad(0, Truncated)
		}
		if TableVar.u16(data, 0) != 1 {
			return bad(0, UnsupportedVersion)
		}
		if TableVar.u16(data, 2) < 1 {
			return Ok({ ..LayoutVar.no_feature_variations, data })
		}
		if size < 14 {
			return bad(0, Truncated)
		}
		base = TableVar.u32(data, 10)
		if base == 0 {
			return Ok({ ..LayoutVar.no_feature_variations, data })
		}
		features_at = TableVar.u16(data, 6)
		lookups_at = TableVar.u16(data, 8)
		if !TableVar.fits(features_at, 2, size) {
			return bad(6, Truncated)
		}
		if !TableVar.fits(lookups_at, 2, size) {
			return bad(8, Truncated)
		}
		lookup_count = TableVar.u16(data, lookups_at)
		if !TableVar.fits(base, 8, size) {
			return bad(10, Truncated)
		}
		if TableVar.u16(data, base) != 1 {
			return bad(base, UnsupportedVersion)
		}
		count = TableVar.u32(data, base + 4)
		if !TableVar.fits(base + 8, 8 * count, size) {
			return bad(base + 4, Truncated)
		}
		var $steps = match LayoutVar.spend(data, 0, count) {
			Ok(s) => s
			Err(TooMuchWork) => return bad(base + 4, TooMuchWork)
		}
		var $problems = []
		var $program = { kinds: [], a: [], b: [], c: [], uses_values: False }
		var $starts = List.with_capacity(count + 1)
		var $substitution_starts = List.with_capacity(count + 1)
		var $features = []
		var $tables = []
		for r in 0..<count {
			record = base + 8 + 8 * r
			$starts = $starts.append($program.kinds.len())
			$substitution_starts = $substitution_starts.append($features.len())
			# The condition set.
			set_offset = TableVar.u32(data, record)
			match LayoutVar.read_condition_set(data, table, lv, axis_count, if (set_offset == 0) 0 else base + set_offset, $program, $steps) {
				Ok(done) => {
					$program = done.program
					$steps = done.steps
				}
				Err(Bad(problem)) => {
					$problems = $problems.append(problem)
				}
				Err(Exhausted(problem)) => return Err($problems.append(problem))
			}
			# The substitutions.
			substitutions_offset = TableVar.u32(data, record + 4)
			if substitutions_offset != 0 {
				at = base + substitutions_offset
				n = TableVar.u16(data, at + 4)
				if !TableVar.fits(at, 6, size) {
					$problems = $problems.append({ table, offset: record + 4, reason: Truncated })
				} else if TableVar.u16(data, at) != 1 {
					$problems = $problems.append({ table, offset: at, reason: UnsupportedVersion })
				} else if !TableVar.fits(at + 6, 6 * n, size) {
					$problems = $problems.append({ table, offset: at + 4, reason: Truncated })
				} else {
					$steps = match LayoutVar.spend(data, $steps, n) {
						Ok(s) => s
						Err(TooMuchWork) => return Err($problems.append({ table, offset: at + 4, reason: TooMuchWork }))
					}
					var $ok = True
					var $k = 0
					while $ok and $k < n {
						entry = at + 6 + 6 * $k
						feature = TableVar.u16(data, entry)
						alternate = TableVar.u32(data, entry + 2)
						feature_at = at + alternate
						lookup_total = TableVar.u16(data, feature_at + 2)
						# As OTS: the alternate feature table after the records and
						# inside the table. Feature indices are not checked (one
						# past the feature list never applies), nor their order:
						# HarfBuzz takes the first record for a feature.
						problem =
							if alternate < 6 + 6 * n or !TableVar.fits(feature_at, 4, size) or !TableVar.fits(feature_at + 4, 2 * lookup_total, size) {
								Some({ table, offset: entry + 2, reason: Truncated })
							} else {
								var $found = None
								var $j = 0
								while $j < lookup_total {
									if TableVar.u16(data, feature_at + 4 + 2 * $j) >= lookup_count {
										$found = Some({ table, offset: feature_at + 4 + 2 * $j, reason: LookupIndex })
										$j = lookup_total
									} else {
										$j = $j + 1
									}
								}
								$found
							}
						match problem {
							Some(p) => {
								$problems = $problems.append(p)
								$ok = False
							}
							None => {
								$steps = match LayoutVar.spend(data, $steps, if (alternate == 0) 0 else lookup_total) {
									Ok(s) => s
									Err(TooMuchWork) => return Err($problems.append({ table, offset: entry + 2, reason: TooMuchWork }))
								}
								$features = $features.append(feature)
								$tables = $tables.append(if (alternate == 0) 0 else feature_at)
							}
						}
						$k = $k + 1
					}
				}
			}
		}
		$starts = $starts.append($program.kinds.len())
		$substitution_starts = $substitution_starts.append($features.len())
		if !$problems.is_empty() {
			return Err($problems)
		}
		# Lookup variation records (version 1.1). OTS does not read them, so
		# they never reject the font. A record list that does not lie inside
		# the table, or more reading work than the allowance, drops the whole
		# `FeatureVariations`, as HarfBuzz's sanitizer drops it; a feature
		# lookups table or lookup index list that does not lie inside counts
		# as absent (the sanitizer nulls its offset), and conditions are read
		# leniently (`read_condition`).
		dropped = Ok({ ..LayoutVar.no_feature_variations, data })
		var $lookup_features = []
		var $lookup_defaults = []
		var $lookup_record_starts = [0]
		var $condition_starts = [$program.kinds.len()]
		var $condition_lookups = []
		if TableVar.u16(data, base + 2) >= 1 {
			list = base + 8 + 8 * count
			records = TableVar.u32(data, list)
			if !TableVar.fits(list, 4, size) or !TableVar.fits(list + 4, 6 * records, size) {
				return dropped
			}
			$steps = match LayoutVar.spend(data, $steps, records) {
				Ok(spent) => spent
				Err(TooMuchWork) => return dropped
			}
			for v in 0..<records {
				record = list + 4 + 6 * v
				offset = TableVar.u32(data, record + 2)
				table_at = base + offset
				conditions = TableVar.u32(data, table_at + 6)
				present = offset != 0 and TableVar.fits(table_at, 10, size) and TableVar.u16(data, table_at) == 1 and TableVar.fits(table_at + 10, 8 * conditions, size)
				$lookup_features = $lookup_features.append(TableVar.u16(data, record))
				$lookup_defaults = $lookup_defaults.append(present and TableVar.u16(data, table_at + 4).bitwise_and(1) != 0)
				if present {
					$steps = match LayoutVar.spend(data, $steps, conditions) {
						Ok(spent) => spent
						Err(TooMuchWork) => return dropped
					}
					for q in 0..<conditions {
						entry = table_at + 10 + 8 * q
						condition = TableVar.u32(data, entry)
						match LayoutVar.read_condition(data, table, lv, axis_count, if (condition == 0) 0 else table_at + condition, $program, $steps) {
							Ok(done) => {
								$program = done.program
								$steps = done.steps
							}
							# Lenient reading reports no problem; only work runs out.
							Err(_) => return dropped
						}
						indices = TableVar.u32(data, entry + 4)
						list_at = table_at + indices
						n = TableVar.u16(data, list_at)
						fits = indices != 0 and TableVar.fits(list_at, 2, size) and TableVar.fits(list_at + 2, 2 * n, size)
						if fits {
							$steps = match LayoutVar.spend(data, $steps, n) {
								Ok(spent) => spent
								Err(TooMuchWork) => return dropped
							}
						}
						$condition_lookups = $condition_lookups.append(if (fits) list_at else 0)
						$condition_starts = $condition_starts.append($program.kinds.len())
					}
				}
				$lookup_record_starts = $lookup_record_starts.append($condition_lookups.len())
			}
		}
		Ok({
			data,
			starts: $starts,
			kinds: $program.kinds,
			a: $program.a,
			b: $program.b,
			c: $program.c,
			uses_values: $program.uses_values,
			substitution_starts: $substitution_starts,
			features: $features,
			tables: $tables,
			lookup_features: $lookup_features,
			lookup_defaults: $lookup_defaults,
			lookup_record_starts: $lookup_record_starts,
			condition_starts: $condition_starts,
			condition_lookups: $condition_lookups,
		})
	}

	Program : { kinds : List(U8), a : List(I64), b : List(I64), c : List(I64), uses_values : Bool }

	emit : Program, U8, I64, I64, I64 -> Program
	emit = |p, kind, a, b, c| { kinds: p.kinds.append(kind), a: p.a.append(a), b: p.b.append(b), c: p.c.append(c), uses_values: p.uses_values or kind == LayoutVar.op_value }

	# Append the postfix program of the condition set at `at` (0 for a null
	# offset: no conditions, which holds). Conditions are visited through an
	# explicit work list: `Visit` a condition at a depth, or `Emit` an
	# operation once its operands are in the program.
	read_condition_set : List(U8), Str, LayoutVar, U64, U64, Program, U64 -> Try({ program : Program, steps : U64 }, [Bad(Problem), Exhausted(Problem)])
	read_condition_set = |data, table, lv, axis_count, at, program_in, steps_in| {
		size = data.len()
		count = if (at == 0) 0 else TableVar.u16(data, at)
		if at != 0 and !TableVar.fits(at, 2 + 4 * count, size) {
			return Err(Bad({ table, offset: at, reason: Truncated }))
		}
		var $steps = match LayoutVar.spend(data, steps_in, count) {
			Ok(s) => s
			Err(TooMuchWork) => return Err(Exhausted({ table, offset: at, reason: TooMuchWork }))
		}
		var $program = program_in
		# The work list, as parallel lists: kind 0 visits the condition at
		# `place` (0 for null) at `depth`; kinds op_and, op_or and op_not emit
		# that operation with `place` operands.
		var $kinds = [LayoutVar.op_and]
		var $places = [count]
		var $depth = [0]
		for i in 0..<count {
			k = count - 1 - i
			offset = TableVar.u32(data, at + 2 + 4 * k)
			# As OTS: each condition of the set after its offset and inside
			# the table.
			if offset < 2 + 4 * (k + 1) or at + offset >= size {
				return Err(Bad({ table, offset: at + 2 + 4 * k, reason: Truncated }))
			}
			$kinds = $kinds.append(0)
			$places = $places.append(if (offset == 0) 0 else at + offset)
			$depth = $depth.append(1)
		}
		LayoutVar.run_conditions(data, table, lv, axis_count, at, { kinds: $kinds, places: $places, depth: $depth }, $program, $steps, False)
	}

	# Append the postfix program of the single condition at `at` (0 for a
	# null offset, which holds) of a lookup variation record. OTS does not
	# read these, so nothing here rejects the font; problems are resolved as
	# HarfBuzz's sanitizer and evaluation resolve them (see
	# `run_conditions`). Only running out of reading work fails.
	read_condition : List(U8), Str, LayoutVar, U64, U64, Program, U64 -> Try({ program : Program, steps : U64 }, [Bad(Problem), Exhausted(Problem)])
	read_condition = |data, table, lv, axis_count, at, program, steps|
		LayoutVar.run_conditions(data, table, lv, axis_count, at, { kinds: [0], places: [at], depth: [1] }, program, steps, True)

	# Run a condition work list (see `read_condition_set`) into the
	# program. `lenient` for a lookup variation record's condition, which
	# OTS never checks: a condition that does not lie inside the table, or
	# nests too deep, holds (HarfBuzz's sanitizer replaces it with a null
	# offset); an axis past the font reads coordinate 0 and a variation
	# index outside the store gives delta 0, as HarfBuzz evaluates them; the
	# range of a condition is not limited.
	run_conditions : List(U8), Str, LayoutVar, U64, U64, { kinds : List(U8), places : List(U64), depth : List(U64) }, Program, U64, Bool -> Try({ program : Program, steps : U64 }, [Bad(Problem), Exhausted(Problem)])
	run_conditions = |data, table, lv, axis_count, at, work, program_in, steps_in, lenient| {
		size = data.len()
		var $steps = steps_in
		var $program = program_in
		var $kinds = work.kinds
		var $places = work.places
		var $depth = work.depth
		while !$kinds.is_empty() {
			last = $kinds.len() - 1
			kind = $kinds.get(last) ?? 0
			place = $places.get(last) ?? 0
			depth = $depth.get(last) ?? 0
			$kinds = $kinds.drop_last(1)
			$places = $places.drop_last(1)
			$depth = $depth.drop_last(1)
			$steps = match LayoutVar.spend(data, $steps, 0) {
				Ok(s) => s
				Err(TooMuchWork) => return Err(Exhausted({ table, offset: at, reason: TooMuchWork }))
			}
			if kind != 0 {
				$program = LayoutVar.emit($program, kind, place.to_i64_wrap(), 0, 0)
			} else if place == 0 {
				$program = LayoutVar.emit($program, LayoutVar.op_true, 0, 0, 0)
			} else if lenient and (depth > LayoutVar.nesting_limit or !TableVar.fits(place, 2, size) or LayoutVar.condition_truncated(data, place)) {
				$program = LayoutVar.emit($program, LayoutVar.op_true, 0, 0, 0)
			} else if depth > LayoutVar.nesting_limit {
				return Err(Bad({ table, offset: place, reason: NestingDepth }))
			} else if !TableVar.fits(place, 2, size) {
				return Err(Bad({ table, offset: place, reason: Truncated }))
			} else {
				format = TableVar.u16(data, place)
				if format == 0 {
					$program = LayoutVar.emit($program, LayoutVar.op_true, 0, 0, 0)
				} else if format == 1 {
					if !TableVar.fits(place, 8, size) {
						return Err(Bad({ table, offset: place, reason: Truncated }))
					}
					axis = TableVar.u16(data, place + 2)
					if axis >= axis_count and !lenient {
						return Err(Bad({ table, offset: place + 2, reason: AxisIndex }))
					}
					# OTS checks the range of a condition directly in a set.
					if depth == 1 and !lenient and (TableVar.i16(data, place + 4) < -0x4000 or TableVar.i16(data, place + 6) > 0x4000) {
						return Err(Bad({ table, offset: place + 4, reason: MapRange }))
					}
					$program = LayoutVar.emit($program, LayoutVar.op_range, axis.to_i64_wrap(), TableVar.i16(data, place + 4), TableVar.i16(data, place + 6))
				} else if format == 2 {
					if !TableVar.fits(place, 8, size) {
						return Err(Bad({ table, offset: place, reason: Truncated }))
					}
					outer = TableVar.u16(data, place + 4)
					inner = TableVar.u16(data, place + 6)
					if !lenient and !TableVar.valid_index(lv.store, outer, inner) {
						return Err(Bad({ table, offset: place + 4, reason: DeltaIndex }))
					}
					$program = LayoutVar.emit($program, LayoutVar.op_value, TableVar.i16(data, place + 2), outer.to_i64_wrap(), inner.to_i64_wrap())
				} else if format == 3 or format == 4 {
					n = TableVar.u8(data, place + 2)
					if !TableVar.fits(place, 3 + 3 * n, size) {
						return Err(Bad({ table, offset: place, reason: Truncated }))
					}
					$kinds = $kinds.append(if (format == 3) LayoutVar.op_and else LayoutVar.op_or)
					$places = $places.append(n)
					$depth = $depth.append(depth)
					for i in 0..<n {
						k = n - 1 - i
						field = place + 3 + 3 * k
						offset = TableVar.u8(data, field) * 65536 + TableVar.u16(data, field + 1)
						$kinds = $kinds.append(0)
						$places = $places.append(if (offset == 0) 0 else place + offset)
						$depth = $depth.append(depth + 1)
					}
				} else if format == 5 {
					if !TableVar.fits(place, 5, size) {
						return Err(Bad({ table, offset: place, reason: Truncated }))
					}
					offset = TableVar.u8(data, place + 2) * 65536 + TableVar.u16(data, place + 3)
					$kinds = $kinds.append(LayoutVar.op_not).append(0)
					$places = $places.append(1).append(if (offset == 0) 0 else place + offset)
					$depth = $depth.append(depth).append(depth + 1)
				} else {
					$program = LayoutVar.emit($program, LayoutVar.op_false, 0, 0, 0)
				}
			}
		}
		Ok({ program: $program, steps: $steps })
	}

	# Whether a condition's fields run past the table, by its format.
	condition_truncated : List(U8), U64 -> Bool
	condition_truncated = |data, place| {
		format = TableVar.u16(data, place)
		size = data.len()
		if format == 1 or format == 2 {
			!TableVar.fits(place, 8, size)
		} else if format == 3 or format == 4 {
			!TableVar.fits(place, 3, size) or !TableVar.fits(place, 3 + 3 * TableVar.u8(data, place + 2), size)
		} else if format == 5 {
			!TableVar.fits(place, 5, size)
		} else {
			False
		}
	}

	## The index of the first record whose conditions hold at normalised
	## coordinates `coords` (F2Dot14, one per axis), as HarfBuzz chooses it.
	matching_record : FeatureVariations, LayoutVar, List(I16) -> Try(U64, [NoMatch])
	matching_record = |fv, lv, coords| {
		records = fv.starts.len() - 1
		# Value conditions use unquantised scalars, as HarfBuzz evaluates
		# them without its scalar cache; with no coordinates they are zero.
		scalars = if (fv.uses_values and !coords.is_empty()) LayoutVar.exact_scalars(lv.store, coords) else []
		# One stack serves every record, so planning allocates the same
		# however many records fail to match.
		var $stack = []
		var $r = 0
		while $r < records {
			checked = LayoutVar.holds(fv, lv, coords, scalars, fv.starts.get($r) ?? 0, fv.starts.get($r + 1) ?? 0, $stack)
			$stack = checked.stack
			if checked.result {
				return Ok($r)
			}
			$r = $r + 1
		}
		Err(NoMatch)
	}

	## The feature table substitutions that apply at a location: for each
	## substituted feature (by index in the table's feature list), the
	## offset in the table of its alternate feature table, in the record's
	## order with only the first substitution of each feature kept (as
	## HarfBuzz's `find_substitute`). Empty when no record matches.
	substitutions_at : FeatureVariations, LayoutVar, List(I16) -> List({ feature : U64, table : U64 })
	substitutions_at = |fv, lv, coords|
		match LayoutVar.matching_record(fv, lv, coords) {
			Ok(r) => {
				first = fv.substitution_starts.get(r) ?? 0
				last = fv.substitution_starts.get(r + 1) ?? 0
				var $out = List.with_capacity(last - first)
				for k in first..<last {
					feature = fv.features.get(k) ?? 0
					if !$out.any(|e| e.feature == feature) {
						$out = $out.append({ feature, table: fv.tables.get(k) ?? 0 })
					}
				}
				$out
			}
			Err(NoMatch) => []
		}

	## The lookup indices of a checked alternate feature table.
	lookups_of : FeatureVariations, U64 -> List(U64)
	lookups_of = |fv, at|
		if at == 0 {
			[]
		} else {
			n = TableVar.u16(fv.data, at + 2)
			var $out = List.with_capacity(n)
			for j in 0..<n {
				$out = $out.append(TableVar.u16(fv.data, at + 4 + 2 * j))
			}
			$out
		}

	## The lookup variations in force at normalised coordinates `coords`:
	## for each lookup variation record, in the table's order, its feature,
	## whether the feature keeps its own lookups (`defaults`), and the
	## lookups of every condition of the record that holds there, in record
	## order (duplicates possible; indices are not checked against the
	## lookup list). Empty for a table without lookup variations.
	lookup_variations_at : FeatureVariations, LayoutVar, List(I16) -> List({ feature : U64, defaults : Bool, lookups : List(U64) })
	lookup_variations_at = |fv, lv, coords| {
		count = fv.lookup_features.len()
		if count == 0 {
			return []
		}
		scalars = if (fv.uses_values and !coords.is_empty()) LayoutVar.exact_scalars(lv.store, coords) else []
		var $out = List.with_capacity(count)
		var $stack = []
		for v in 0..<count {
			var $lookups = []
			for q in (fv.lookup_record_starts.get(v) ?? 0)..<(fv.lookup_record_starts.get(v + 1) ?? 0) {
				checked = LayoutVar.holds(fv, lv, coords, scalars, fv.condition_starts.get(q) ?? 0, fv.condition_starts.get(q + 1) ?? 0, $stack)
				$stack = checked.stack
				if checked.result {
					at = fv.condition_lookups.get(q) ?? 0
					if at != 0 {
						for j in 0..<TableVar.u16(fv.data, at) {
							$lookups = $lookups.append(TableVar.u16(fv.data, at + 2 + 2 * j))
						}
					}
				}
			}
			$out = $out.append({ feature: fv.lookup_features.get(v) ?? 0, defaults: fv.lookup_defaults.get(v) ?? False, lookups: $lookups })
		}
		$out
	}

	## The lookups of feature `feature`, whose own lookups (after any
	## feature table substitution) are `current`, under the lookup
	## variations in force (`lookup_variations_at`): the first variation for
	## the feature, as HarfBuzz takes it, replaces them with its lookups,
	## plus `current` when it keeps them. Order and repeats do not matter to
	## a plan, which applies each lookup once in lookup index order.
	varied_lookups : List({ feature : U64, defaults : Bool, lookups : List(U64) }), U64, List(U64) -> List(U64)
	varied_lookups = |variations, feature, current|
		match variations.find_first(|v| v.feature == feature) {
			Ok(v) => if (v.defaults) current.concat(v.lookups) else v.lookups
			Err(_) => current
		}

	## Mark as used, in `used_in` (one entry per lookup of the table), the
	## lookups the `FeatureVariations` of a `GSUB` or `GPOS` table can swap
	## in at some location: those of every alternate feature table and of
	## every lookup variation record (version 1.1). Parts that do not lie
	## inside the table are passed over here: checking the list is
	## `read_feature_variations`'s, and a font whose list is broken never
	## selects them. The walk is bounded by the reading allowance.
	variation_lookups : List(U8), List(Bool) -> List(Bool)
	variation_lookups = |data, used_in| {
		size = data.len()
		limit = 8 * size + 16384
		list = if (TableVar.u16(data, 2) >= 1 and TableVar.fits(0, 14, size)) TableVar.u32(data, 10) else 0
		if list == 0 or !TableVar.fits(list, 8, size) {
			return used_in
		}
		count = TableVar.u32(data, list + 4)
		if !TableVar.fits(list + 8, 8 * count, size) {
			return used_in
		}
		var $used = used_in
		var $steps = 0
		for r in 0..<count {
			offset = TableVar.u32(data, list + 8 + 8 * r + 4)
			table = list + offset
			subs = TableVar.u16(data, table + 4)
			if offset != 0 and TableVar.fits(table, 6 + 6 * subs, size) {
				for k in 0..<subs {
					feature = table + TableVar.u32(data, table + 6 + 6 * k + 2)
					n = TableVar.u16(data, feature + 2)
					$steps = $steps + n + 1
					if TableVar.fits(feature, 4 + 2 * n, size) and $steps <= limit {
						$used = LayoutVar.mark_used($used, data, feature + 4, n)
					}
				}
			}
		}
		records_at = list + 8 + 8 * count
		records = TableVar.u32(data, records_at)
		if TableVar.u16(data, list + 2) >= 1 and TableVar.fits(records_at, 4, size) and TableVar.fits(records_at + 4, 6 * records, size) {
			for v in 0..<records {
				offset = TableVar.u32(data, records_at + 4 + 6 * v + 2)
				table = list + offset
				conditions = TableVar.u32(data, table + 6)
				if offset != 0 and TableVar.fits(table, 10, size) and TableVar.fits(table + 10, 8 * conditions, size) {
					for q in 0..<conditions {
						indices = TableVar.u32(data, table + 10 + 8 * q + 4)
						at = table + indices
						n = TableVar.u16(data, at)
						$steps = $steps + n + 1
						if indices != 0 and TableVar.fits(at, 2 + 2 * n, size) and $steps <= limit {
							$used = LayoutVar.mark_used($used, data, at + 2, n)
						}
					}
				}
			}
		}
		$used
	}

	# Mark the `n` lookup indices at `at` used; indices past the list are
	# passed over.
	mark_used : List(Bool), List(U8), U64, U64 -> List(Bool)
	mark_used = |used_in, data, at, n| {
		var $used = used_in
		for j in 0..<n {
			lookup = TableVar.u16(data, at + 2 * j)
			if lookup < $used.len() {
				# Checked against the list's length.
				$used = $used.set(lookup, True) ?? []
			}
		}
		$used
	}

	# Evaluate the postfix program `kinds[first ..< last]` (a record's
	# condition set, or a lookup variation's condition) on a stack of
	# booleans. A checked program leaves exactly one value; each
	# operation's operands are on the stack, so every index below is in
	# bounds. The caller's stack is reused, grown only when this program
	# needs more room, and handed back for the next program.
	holds : FeatureVariations, LayoutVar, List(I16), List(U32), U64, U64, List(Bool) -> { result : Bool, stack : List(Bool) }
	holds = |fv, lv, coords, scalars, first, last, given| {
		need = last - first
		var $stack = if (given.len() >= need) given else given.concat(List.repeat(False, need - given.len()))
		var $top = 0
		for i in first..<last {
			kind = fv.kinds.get(i) ?? 0
			a = fv.a.get(i) ?? 0
			if kind == LayoutVar.op_true {
				$stack = $stack.set($top, True) ?? []
				$top = $top + 1
			} else if kind == LayoutVar.op_false {
				$stack = $stack.set($top, False) ?? []
				$top = $top + 1
			} else if kind == LayoutVar.op_range {
				coord = (coords.get(a.to_u64_wrap()) ?? 0).to_i64()
				result = (fv.b.get(i) ?? 0) <= coord and coord <= (fv.c.get(i) ?? 0)
				$stack = $stack.set($top, result) ?? []
				$top = $top + 1
			} else if kind == LayoutVar.op_value {
				d = TableVar.delta(lv.store, scalars, (fv.b.get(i) ?? 0).to_u64_wrap(), (fv.c.get(i) ?? 0).to_u64_wrap())
				# default + delta > 0, exactly as HarfBuzz's double sum.
				result = TableVar.f32_lt(TableVar.f32_from_int(0 - a), d)
				$stack = $stack.set($top, result) ?? []
				$top = $top + 1
			} else if kind == LayoutVar.op_not {
				$stack = $stack.set($top - 1, !($stack.get($top - 1) ?? False)) ?? []
			} else {
				n = a.to_u64_wrap()
				var $result = kind == LayoutVar.op_and
				for k in ($top - n)..<$top {
					v = $stack.get(k) ?? False
					$result = if (kind == LayoutVar.op_and) $result and v else $result or v
				}
				$top = $top - n
				$stack = $stack.set($top, $result) ?? []
				$top = $top + 1
			}
		}
		{ result: $stack.get(0) ?? False, stack: $stack }
	}

	# Every region's scalar without HarfBuzz's cache quantisation.
	exact_scalars : TableVar.Store, List(I16) -> List(U32)
	exact_scalars = |store, coords| {
		axes = store.axis_count
		var $out = List.with_capacity(store.region_count)
		for r in 0..<store.region_count {
			var $v = TableVar.f32_one
			var $a = 0
			while $a < axes {
				base = 3 * (r * axes + $a)
				factor = TableVar.axis_scalar(
					(coords.get($a) ?? 0).to_i64(),
					(store.regions.get(base) ?? 0).to_i64(),
					(store.regions.get(base + 1) ?? 0).to_i64(),
					(store.regions.get(base + 2) ?? 0).to_i64(),
				)
				if factor == 0 {
					$v = 0
					$a = axes
				} else {
					$v = TableVar.f32_mul($v, factor)
					$a = $a + 1
				}
			}
			$out = $out.append($v)
		}
		$out
	}
}

# ----------------------------------------------------------------------

# Tests of the readers on hand-built tables and on the tables of the
# fixtures `kern-var.ttf` and `feature-var.ttf` (generated by
# `tests/fonts/variable-layout/generate.py`), embedded below. The fixtures'
# kerning and substitutions against HarfBuzz are tested through the public
# API in `tests/api/`. Top-level expects and helpers are not part of the
# module's API. Run with `roc test package/LayoutVar.roc`.

# ------------------------------------------------------------ helpers

u16 : U64 -> List(U8)
u16 = |v| [v.shr_zf_wrap(8).bitwise_and(0xFF).to_u8_wrap(), v.bitwise_and(0xFF).to_u8_wrap()]

i16 : I64 -> List(U8)
i16 = |v| u16(v.to_u64_wrap().bitwise_and(0xFFFF))

u24 : U64 -> List(U8)
u24 = |v| [v.shr_zf_wrap(16).bitwise_and(0xFF).to_u8_wrap()].concat(u16(v.bitwise_and(0xFFFF)))

u32 : U64 -> List(U8)
u32 = |v| u16(v.shr_zf_wrap(16).bitwise_and(0xFFFF)).concat(u16(v.bitwise_and(0xFFFF)))

be : List(U8), U64, U64 -> U64
be = |bytes, at, len| {
	var $v = 0
	for k in 0..<len {
		$v = $v * 256 + (bytes.get(at + k) ?? 0).to_u64()
	}
	$v
}

# A table's bytes from a font file, or none.
reasons : List(LayoutVar.Problem) -> List(LayoutVar.Reason)
reasons = |problems| problems.map(|p| p.reason)

# ------------------------------------------------------------ finding pairs

# A value record: its offset, its format and where its device offsets
# count from.
Found : { base : U64, at : U64, format : U64 }

# The coverage index of a glyph, searched linearly (the fixtures are tiny).
coverage_index : List(U8), U64, U64 -> Try(U64, [NotCovered])
coverage_index = |data, at, glyph| {
	count = be(data, at + 2, 2)
	for i in 0..<count {
		if be(data, at, 2) == 1 {
			if be(data, at + 4 + 2 * i, 2) == glyph {
				return Ok(i)
			}
		} else {
			r = at + 4 + 6 * i
			if glyph >= be(data, r, 2) and glyph <= be(data, r + 2, 2) {
				return Ok(be(data, r + 4, 2) + glyph - be(data, r, 2))
			}
		}
	}
	Err(NotCovered)
}

class_of : List(U8), U64, U64 -> U64
class_of = |data, at, glyph| {
	if be(data, at, 2) == 1 {
		start = be(data, at + 2, 2)
		if (glyph >= start and glyph - start < be(data, at + 4, 2)) be(data, at + 6 + 2 * (glyph - start), 2) else 0
	} else {
		var $class = 0
		for i in 0..<be(data, at + 2, 2) {
			r = at + 4 + 6 * i
			if glyph >= be(data, r, 2) and glyph <= be(data, r + 2, 2) {
				$class = be(data, r + 4, 2)
			}
		}
		$class
	}
}

# The pair's value records in one pair adjustment subtable, if it has them.
in_subtable : List(U8), U64, U64, U64 -> Try({ first : Found, second : Found }, [NoPair])
in_subtable = |data, st, left, right| {
	format1 = be(data, st + 4, 2)
	format2 = be(data, st + 6, 2)
	size1 = LayoutVar.value_size(format1)
	size2 = LayoutVar.value_size(format2)
	match coverage_index(data, st + be(data, st + 2, 2), left) {
		Err(NotCovered) => Err(NoPair)
		Ok(index) =>
			if be(data, st, 2) == 1 {
				if index >= be(data, st + 8, 2) {
					return Err(NoPair)
				}
				set = st + be(data, st + 10 + 2 * index, 2)
				record = 2 + size1 + size2
				for p in 0..<be(data, set, 2) {
					r = set + 2 + record * p
					if be(data, r, 2) == right {
						return Ok({ first: { base: set, at: r + 2, format: format1 }, second: { base: set, at: r + 2 + size1, format: format2 } })
					}
				}
				Err(NoPair)
			} else {
				row = class_of(data, st + be(data, st + 8, 2), left)
				column = class_of(data, st + be(data, st + 10, 2), right)
				width = be(data, st + 14, 2)
				if row >= be(data, st + 12, 2) or column >= width {
					Err(NoPair)
				} else {
					r = st + 16 + (size1 + size2) * (row * width + column)
					Ok({ first: { base: st, at: r, format: format1 }, second: { base: st, at: r + size1, format: format2 } })
				}
			}
	}
}

# For each lookup of the `kern` feature, the first subtable with the pair
# decides it, as HarfBuzz and `LayoutKerning` apply a lookup to two glyphs.
pair_records : List(U8), U64, U64 -> List({ first : Found, second : Found })
pair_records = |gpos, left, right| {
	features = be(gpos, 6, 2)
	lookups = be(gpos, 8, 2)
	var $out = []
	for f in 0..<be(gpos, features, 2) {
		record = features + 2 + 6 * f
		if be(gpos, record, 4) == 0x6B65726E {
			feature = features + be(gpos, record + 4, 2)
			for j in 0..<be(gpos, feature + 2, 2) {
				lookup = lookups + be(gpos, lookups + 2 + 2 * be(gpos, feature + 4 + 2 * j, 2), 2)
				kind = be(gpos, lookup, 2)
				var $done = False
				for s in 0..<be(gpos, lookup + 4, 2) {
					at = lookup + be(gpos, lookup + 6 + 2 * s, 2)
					st = if (kind == 9) at + be(gpos, at + 4, 4) else at
					if !$done {
						match in_subtable(gpos, st, left, right) {
							Ok(found) => {
								$out = $out.append(found)
								$done = True
							}
							Err(NoPair) => {}
						}
					}
				}
			}
		}
	}
	$out
}

# The tables of the fixture `kern-var.ttf` (two axes, a `GDEF` item variation
# store and a `GPOS` `kern` feature over glyphs a-g), for the expects below.
# Generated from `tests/fonts/variable-layout/kern-var.ttf` by `tests/fonts/inline_tables.py`.

# The `GDEF` table, 203 bytes.
kern_gdef : List(U8)
kern_gdef = [
	[0x00, 0x01, 0x00, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
	[0x00, 0x12, 0x00, 0x01, 0x00, 0x00, 0x00, 0x14, 0x00, 0x03, 0x00, 0x00, 0x00, 0x54, 0x00, 0x00],
	[0x00, 0x96, 0x00, 0x00, 0x00, 0xB0, 0x00, 0x02, 0x00, 0x05, 0x00, 0x00, 0x40, 0x00, 0x40, 0x00],
	[0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC0, 0x00, 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
	[0x00, 0x00, 0x0C, 0xCD, 0x20, 0x00, 0x33, 0x33, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
	[0x40, 0x00, 0x40, 0x00, 0x00, 0x00, 0x40, 0x00, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
	[0xC0, 0x00, 0xC0, 0x00, 0x00, 0x00, 0x00, 0x05, 0x00, 0x05, 0x00, 0x05, 0x00, 0x00, 0x00, 0x01],
	[0x00, 0x02, 0x00, 0x03, 0x00, 0x04, 0x00, 0x65, 0xFF, 0xC4, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
	[0xFF, 0x9B, 0x00, 0x00, 0x00, 0x21, 0x00, 0x00, 0x00, 0x07, 0x00, 0x0A, 0x00, 0x0A, 0x00, 0x0A],
	[0xFF, 0xB3, 0x00, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFD],
	[0x00, 0xFA, 0xFF, 0xFF, 0x00, 0x01, 0xFF, 0x7F, 0x00, 0x02, 0x80, 0x02, 0x00, 0x02, 0x00, 0x03],
	[0x00, 0x00, 0x00, 0x00, 0x9C, 0x40, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x05, 0x00, 0x01],
	[0x11, 0x70, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x02, 0xF9],
].join_map(|row| row)

# The `GPOS` table, 496 bytes.
kern_gpos : List(U8)
kern_gpos = [
	[0x00, 0x01, 0x00, 0x00, 0x00, 0x0A, 0x00, 0x12, 0x00, 0x1A, 0x00, 0x01, 0x44, 0x46, 0x4C, 0x54],
	[0x00, 0x18, 0x00, 0x01, 0x6B, 0x65, 0x72, 0x6E, 0x00, 0x24, 0x00, 0x03, 0x00, 0x26, 0x00, 0x0C],
	[0x00, 0x14, 0x00, 0x28, 0x00, 0x00, 0x00, 0x09, 0x00, 0x00, 0x00, 0x01, 0x00, 0x2C, 0x00, 0x02],
	[0x00, 0x00, 0x00, 0x01, 0x00, 0x3A, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, 0x00, 0x02],
	[0x00, 0x02, 0x00, 0x00, 0x00, 0x02, 0x00, 0x1A, 0x00, 0x40, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x01],
	[0x00, 0x00, 0x00, 0x01, 0x00, 0x02, 0x00, 0x00, 0x01, 0x36, 0x00, 0x01, 0x00, 0xA2, 0x00, 0x44],
	[0x00, 0x00, 0x00, 0x02, 0x00, 0xBA, 0x00, 0xCE, 0x00, 0x02, 0x00, 0x9C, 0x00, 0x04, 0x00, 0x00],
	[0x00, 0xA4, 0x00, 0xA4, 0x00, 0x02, 0x00, 0x02, 0xFF, 0xE2, 0x00, 0x0B, 0xFF, 0xFC, 0x00, 0x00],
	[0x00, 0x02, 0x00, 0xCE, 0x00, 0x55, 0x00, 0x22, 0x00, 0xDA, 0x00, 0xEA, 0x00, 0x03, 0x00, 0x03],
	[0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0xFF, 0xFB],
	[0x00, 0xC8, 0x01, 0x64, 0x00, 0x03, 0x00, 0xC2, 0x00, 0x00, 0x00, 0x07, 0x00, 0x00, 0x00, 0xBC],
	[0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0x01, 0x64, 0x00, 0x00, 0xFF, 0xFE, 0x01, 0x58],
	[0xFF, 0xFD, 0x00, 0x0C, 0x00, 0xC2, 0x01, 0x5E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x02],
	[0x01, 0x58, 0x01, 0x58, 0x00, 0x01, 0x00, 0xC8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x6A],
	[0x00, 0x00, 0x01, 0x64, 0x00, 0x05, 0xFF, 0xF7, 0x00, 0x00, 0x00, 0xC8, 0x00, 0x00, 0x00, 0x00],
	[0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x02],
	[0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x02, 0x00, 0x06, 0x00, 0x07, 0x00, 0x01, 0x00, 0x07],
	[0x00, 0x01, 0x00, 0x01, 0x00, 0x03, 0x00, 0x02, 0xFF, 0xCE, 0x00, 0xC4, 0x00, 0x03, 0x00, 0x14],
	[0x00, 0xCA, 0x00, 0x04, 0x00, 0x00, 0x00, 0x66, 0x00, 0x03, 0x00, 0x01, 0xFF, 0xF6, 0x00, 0x58],
	[0x00, 0x05, 0x00, 0x0F, 0x00, 0x00, 0x00, 0x06, 0x00, 0x05, 0x00, 0xC2, 0x00, 0x02, 0x00, 0x00],
	[0x80, 0x00, 0x00, 0x01, 0x00, 0x01, 0x80, 0x00, 0x00, 0x00, 0x00, 0x02, 0x80, 0x00, 0x00, 0x01],
	[0x00, 0x04, 0x00, 0x01, 0x00, 0x03, 0x00, 0x04, 0x00, 0x07, 0x00, 0x01, 0x00, 0x03, 0x00, 0x05],
	[0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x02, 0x00, 0x02, 0x00, 0x01],
	[0x00, 0x02, 0x00, 0x01, 0x00, 0x05, 0x00, 0x06, 0x00, 0x02, 0xFF, 0xFF, 0xFF, 0xFF, 0x80, 0x00],
	[0x00, 0x09, 0x00, 0x0C, 0x00, 0x01, 0x71, 0x00, 0x00, 0x01, 0x00, 0x0E, 0x00, 0x00, 0x00, 0xFF],
	[0x00, 0x02, 0x00, 0x16, 0x00, 0x2A, 0x00, 0x01, 0x00, 0x02, 0x00, 0x03, 0x00, 0x05, 0x00, 0x01],
	[0x00, 0x04, 0x00, 0x04, 0xFF, 0xFC, 0x00, 0x08, 0x00, 0x0C, 0x00, 0x3A, 0x00, 0x40, 0x00, 0x46],
	[0x00, 0x4C, 0x00, 0x02, 0x00, 0x01, 0xFF, 0xFA, 0x00, 0x06, 0xFF, 0xF4, 0xFF, 0xEE, 0x00, 0x26],
	[0x00, 0x2C, 0x00, 0x32, 0x00, 0x38, 0x00, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
	[0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00],
	[0x00, 0x01, 0x80, 0x00, 0x00, 0x00, 0x00, 0x04, 0x80, 0x00, 0x00, 0x01, 0x00, 0x00, 0x80, 0x00],
].join_map(|row| row)

KernFixture : { lv : LayoutVar, gpos : List(U8) }

kern_fixture : List(U8), List(U8) -> Try(KernFixture, [Bad])
kern_fixture = |gdef, gpos|
	match LayoutVar.read_gdef(gdef, 2) {
		Ok(lv) =>
			match LayoutVar.check_gpos(lv, gpos, 8) {
				Ok(45) => Ok({ lv, gpos })
				_ => Err(Bad)
			}
		Err(_) => Err(Bad)
	}

# ------------------------------------------------------------ pair kerning

# The locations at which the public tests compare the fixture's kerning with
# HarfBuzz, as normalised coordinates.
kern_locations : List(List(I16))
kern_locations = [
	[0, 0],
	[-16384, 0],
	[-8192, 0],
	[0, 0],
	[3277, 0],
	[4096, 0],
	[8192, 0],
	[9831, 0],
	[16384, 0],
	[0, -16384],
	[0, 16384],
	[8192, 8192],
	[16384, 16384],
	[1858, 3359],
	[13501, -6226],
	[-13653, -13107],
]

# The x advance that kerning reads on its own agrees with the x advance of
# the whole value record, for every pair of glyphs a-g at every location.
expect
	match kern_fixture(kern_gdef, kern_gpos) {
		Ok(f) => {
			var $ok = True
			for coords in kern_locations {
				loc = LayoutVar.location(f.lv, coords)
				for left in 1..<8 {
					for right in 1..<8 {
						for found in pair_records(f.gpos, left, right) {
							r = found.first
							if LayoutVar.x_advance(f.lv, loc, f.gpos, r.base, r.at, r.format) != LayoutVar.value(f.lv, loc, f.gpos, r.base, r.at, r.format).x_advance {
								$ok = False
							}
						}
					}
				}
			}
			$ok
		}
		Err(_) => False
	}

# x_advance is the stored value at the default location, even where a
# device's row would vary.
expect
	match kern_fixture(kern_gdef, kern_gpos) {
		Ok(f) => {
			# Pair (a, b): subtable 0's first pair set, x advance -50 with a
			# device on row (0, 0).
			found = pair_records(f.gpos, 1, 2)
			match found.first() {
				Ok(r) => {
					at_default = LayoutVar.location(f.lv, [0, 0])
					bold = LayoutVar.location(f.lv, [16384, 0])
					LayoutVar.x_advance(f.lv, at_default, f.gpos, r.first.base, r.first.at, r.first.format) == -50
						and LayoutVar.x_advance(f.lv, bold, f.gpos, r.first.base, r.first.at, r.first.format) == 51
						and !at_default.active
						and LayoutVar.delta(f.lv, bold, 0, 0) == 101
						and LayoutVar.delta(f.lv, bold, 0xFFFF, 0xFFFF) == 0
						and LayoutVar.delta(f.lv, at_default, 0, 0) == 0
						and LayoutVar.varies_x_advance(r.first.format)
				}
				Err(_) => False
			}
		}
		Err(_) => False
	}

# ------------------------------------------------------------ feature variations

# The tables of the fixture `feature-var.ttf` (a `GSUB` with five
# `FeatureVariations` records), for the expects below.
# Generated from `tests/fonts/variable-layout/feature-var.ttf` by `tests/fonts/inline_tables.py`.

# The `GDEF` table, 56 bytes.
feature_gdef : List(U8)
feature_gdef = [
	[0x00, 0x01, 0x00, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
	[0x00, 0x12, 0x00, 0x01, 0x00, 0x00, 0x00, 0x0C, 0x00, 0x01, 0x00, 0x00, 0x00, 0x1C, 0x00, 0x02],
	[0x00, 0x01, 0xC0, 0x00, 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01],
	[0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0xC8],
].join_map(|row| row)

# The `GSUB` table, 383 bytes.
feature_gsub : List(U8)
feature_gsub = [
	[0x00, 0x01, 0x00, 0x01, 0x00, 0x0E, 0x00, 0x20, 0x00, 0x16, 0x00, 0x00, 0x00, 0x84, 0x00, 0x01],
	[0x44, 0x46, 0x4C, 0x54, 0x00, 0x20, 0x00, 0x04, 0x00, 0x1C, 0x00, 0x24, 0x00, 0x2C, 0x00, 0x34],
	[0x00, 0x02, 0x63, 0x61, 0x6C, 0x74, 0x00, 0x32, 0x6C, 0x69, 0x67, 0x61, 0x00, 0x32, 0x00, 0x28],
	[0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x2E, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01],
	[0x00, 0x2C, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x2A, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01],
	[0x00, 0x28, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x02, 0x00, 0x00, 0x00, 0x01],
	[0x00, 0x01, 0x00, 0x18, 0x00, 0x03, 0x00, 0x01, 0x00, 0x12, 0x00, 0x02, 0x00, 0x01, 0x00, 0x12],
	[0x00, 0x03, 0x00, 0x01, 0x00, 0x0C, 0x00, 0x04, 0x00, 0x01, 0x00, 0x01, 0x00, 0x01, 0x00, 0x01],
	[0x00, 0x01, 0x00, 0x02, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00, 0x48],
	[0x00, 0x00, 0x00, 0x82, 0x00, 0x00, 0x00, 0x30, 0x00, 0x00, 0x00, 0x52, 0x00, 0x00, 0x00, 0x36],
	[0x00, 0x00, 0x00, 0x5E, 0x00, 0x00, 0x00, 0x3C, 0x00, 0x00, 0x00, 0x6A, 0x00, 0x00, 0x00, 0x42],
	[0x00, 0x00, 0x00, 0x76, 0x00, 0x01, 0x00, 0x00, 0x00, 0x6C, 0x00, 0x01, 0x00, 0x00, 0x00, 0x6E],
	[0x00, 0x01, 0x00, 0x00, 0x00, 0x58, 0x00, 0x01, 0x00, 0x00, 0x00, 0x6B, 0x00, 0x02, 0x00, 0x00],
	[0x00, 0x54, 0x00, 0x00, 0x00, 0x6E, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00],
	[0x00, 0x78, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x72, 0x00, 0x01],
	[0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x54, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01],
	[0x00, 0x01, 0x00, 0x00, 0x00, 0x4E, 0x00, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00],
	[0x00, 0x48, 0x00, 0x01, 0x00, 0x00, 0x00, 0x4E, 0x00, 0x02, 0xFF, 0x9C, 0x00, 0x00, 0x00, 0x00],
	[0x00, 0x01, 0x00, 0x00, 0x20, 0x00, 0x40, 0x00, 0x00, 0x04, 0x02, 0x00, 0x00, 0x37, 0x00, 0x00],
	[0x32, 0x00, 0x03, 0x02, 0x00, 0x00, 0x36, 0x00, 0x00, 0x3E, 0x00, 0x01, 0x00, 0x01, 0xC0, 0x00],
	[0xE0, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x03, 0x00, 0x00],
	[0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x02, 0x00, 0x05, 0x00, 0x00, 0x1D, 0x00],
	[0x01, 0x00, 0x01, 0x30, 0x00, 0x40, 0x00, 0x00, 0x01, 0x00, 0x01, 0xC0, 0x00, 0xC8, 0x00, 0x00],
	[0x01, 0x00, 0x00, 0xF8, 0x00, 0x08, 0x00, 0x00, 0x01, 0x00, 0x00, 0xD0, 0x00, 0x40, 0x00],
].join_map(|row| row)

feature_fixture : List(U8), List(U8) -> Try({ lv : LayoutVar, fv : LayoutVar.FeatureVariations }, [Bad])
feature_fixture = |gdef, gsub|
	match LayoutVar.read_gdef(gdef, 2) {
		Ok(lv) =>
			match LayoutVar.read_feature_variations(gsub, "GSUB", lv, 2) {
				Ok(fv) => Ok({ lv, fv })
				Err(_) => Err(Bad)
			}
		Err(_) => Err(Bad)
	}

# The substitutions of each record: record 0 replaces both features
# (calt, index 0, and liga, index 1) and lists them in order.
expect
	match feature_fixture(feature_gdef, feature_gsub) {
		Ok(f) => {
			lookups = |coords| LayoutVar.substitutions_at(f.fv, f.lv, coords).map(|s| (s.feature, LayoutVar.lookups_of(f.fv, s.table)))
			lookups([8192, -8192]) == [(0, [1]), (1, [2])]
				and lookups([8192, 0]) == [(0, [1])]
				and lookups([0, 16384]) == [(0, [2])]
				and lookups([-10240, 0]) == [(0, [0])]
				and lookups([0, -16384]) == [(1, [3])]
				and lookups([0, 0]) == []
		}
		Err(_) => False
	}

# ------------------------------------------------------------ hand-built GDEF

gdef_header : U64, U64 -> List(U8)
gdef_header = |minor, store_at| u16(1).concat(u16(minor)).concat(List.repeat(0, 10)).concat(u32(store_at))

# A store for one axis: one region (peak 1), one data subtable with one
# 16-bit row.
one_store : I64 -> List(U8)
one_store = |d| u16(1).concat(u32(12)).concat(u16(1)).concat(u32(22)).concat(u16(1)).concat(u16(1)).concat(i16(0)).concat(i16(16384)).concat(i16(16384)).concat(u16(1)).concat(u16(1)).concat(u16(1)).concat(u16(0)).concat(i16(d))

expect
	match LayoutVar.read_gdef(gdef_header(3, 18).concat(one_store(-75)), 1) {
		Ok(lv) => LayoutVar.has_store(lv) and LayoutVar.delta(lv, LayoutVar.location(lv, [8192]), 0, 0) == -37
		Err(_) => False
	}

gdef_problems : List(U8), U64 -> List(LayoutVar.Problem)
gdef_problems = |bytes, axes|
	match LayoutVar.read_gdef(bytes, axes) {
		Ok(_) => []
		Err(problems) => problems
	}

# Before version 1.3, or with a null offset, there is no store.
expect
	match (LayoutVar.read_gdef(u16(1).concat(u16(2)).concat(List.repeat(0, 10)), 1), LayoutVar.read_gdef(gdef_header(3, 0), 1)) {
		(Ok(a), Ok(b)) => !LayoutVar.has_store(a) and !LayoutVar.has_store(b)
		_ => False
	}

expect gdef_problems([0, 1], 1) == [{ table: "GDEF", offset: 0, reason: Truncated }]
expect gdef_problems(u16(2).concat(u16(0)), 1) == [{ table: "GDEF", offset: 0, reason: UnsupportedVersion }]
expect gdef_problems(u16(1).concat(u16(3)).concat(List.repeat(0, 8)), 1) == [{ table: "GDEF", offset: 0, reason: Truncated }]

# The store's own problems keep their reasons, with offsets in GDEF: here
# its region list has two axes for a font with one.
expect gdef_problems(gdef_header(3, 18).concat(one_store(1)), 2) == [{ table: "GDEF", offset: 30, reason: AxisCountMismatch }]

# ------------------------------------------------------------ hand-built GPOS devices

# A GPOS whose lookup list has one pair adjustment lookup per device: format
# 1, first glyph 1, one pair with glyph 2, value format 0x44 (x advance and
# its device) with `x` as the x advance and `offset` as the device offset
# (from the pair set), and `device` 8 bytes after the pair set.
gpos_devices : List({ offset : U64, device : List(U8) }) -> List(U8)
gpos_devices = |devices| {
	n = devices.len()
	header = u16(1).concat(u16(0)).concat(u16(0)).concat(u16(0)).concat(u16(10))
	var $offsets = []
	var $lookups = []
	var $at = 2 + 2 * n
	for d in devices {
		$offsets = $offsets.concat(u16($at))
		subtable = u16(1).concat(u16(12)).concat(u16(0x44)).concat(u16(0)).concat(u16(1)).concat(u16(18)).concat(u16(1)).concat(u16(1)).concat(u16(1)).concat(u16(1)).concat(u16(2)).concat(i16(-20)).concat(u16(d.offset)).concat(d.device)
		lookup = u16(2).concat(u16(0)).concat(u16(1)).concat(u16(8))
		$lookups = $lookups.concat(lookup).concat(subtable)
		$at = $at + lookup.len() + subtable.len()
	}
	header.concat(u16(n)).concat($offsets).concat($lookups)
}

device_store : LayoutVar
device_store =
	match LayoutVar.read_gdef(gdef_header(3, 18).concat(one_store(-75)), 1) {
		Ok(lv) => lv
		Err(_) => LayoutVar.none(1)
	}

expect LayoutVar.check_gpos(device_store, gpos_devices([{ offset: 8, device: u16(0).concat(u16(0)).concat(u16(0x8000)) }]), 3) == Ok(1)
expect LayoutVar.check_gpos(device_store, gpos_devices([{ offset: 8, device: u16(0xFFFF).concat(u16(0xFFFF)).concat(u16(0x8000)) }]), 3) == Ok(1)
expect LayoutVar.check_gpos(device_store, gpos_devices([{ offset: 8, device: u16(9).concat(u16(9)).concat(u16(2)) }]), 3) == Ok(1)
expect LayoutVar.check_gpos(device_store, gpos_devices([{ offset: 0, device: [] }]), 3) == Ok(1)

# A row past the store, an unknown delta format and a device past the end
# of the table, in three lookups: three problems in one result.
expect {
	gpos = gpos_devices([
		{ offset: 8, device: u16(0).concat(u16(1)).concat(u16(0x8000)) },
		{ offset: 8, device: u16(0).concat(u16(0)).concat(u16(0x8001)) },
		{ offset: 8, device: u16(0).concat(u16(0)) },
	])
	match LayoutVar.check_gpos(device_store, gpos, 3) {
		Err(problems) => reasons(problems) == [DeltaIndex, DeviceFormat, Truncated] and problems.all(|p| p.table == "GPOS")
		Ok(_) => False
	}
}

# Offsets: the first lookup is at 14 and its subtable at 22; the pair set
# at 40, its device field at 46 and the device at 48.
expect
	LayoutVar.check_gpos(device_store, gpos_devices([{ offset: 8, device: u16(0).concat(u16(1)).concat(u16(0x8000)) }]), 3)
		== Err([{ table: "GPOS", offset: 48, reason: DeltaIndex }])

# Without a GDEF store only `no_variation` is a valid index.
expect
	match LayoutVar.check_gpos(LayoutVar.none(1), gpos_devices([{ offset: 8, device: u16(0).concat(u16(0)).concat(u16(0x8000)) }]), 3) {
		Err(problems) => reasons(problems) == [DeltaIndex]
		Ok(_) => False
	}

# A pair set of a first glyph past the font is never looked at.
expect LayoutVar.check_gpos(device_store, gpos_devices([{ offset: 8, device: u16(0).concat(u16(1)).concat(u16(0x8000)) }]), 1) == Ok(0)

# Value records: the device of the x advance applies at a location.
expect {
	gpos = gpos_devices([{ offset: 8, device: u16(0).concat(u16(0)).concat(u16(0x8000)) }])
	# The pair record is at 40 + 2; its value record at 44.
	loc = LayoutVar.location(device_store, [16384])
	LayoutVar.x_advance(device_store, loc, gpos, 40, 44, 0x44) == -95
		and LayoutVar.value(device_store, loc, gpos, 40, 44, 0x44) == { x_placement: 0, y_placement: 0, x_advance: -95, y_advance: 0 }
		and LayoutVar.x_advance(device_store, LayoutVar.default_location, gpos, 40, 44, 0x44) == -20
}

# Many pair sets sharing one large set: the work allowance refuses it.
expect {
	n = 2000
	header = u16(1).concat(u16(0)).concat(u16(0)).concat(u16(0)).concat(u16(10))
	lookups = u16(1).concat(u16(4))
	lookup = u16(2).concat(u16(0)).concat(u16(1)).concat(u16(8))
	set_at = 10 + 2 * n + 4 + 6
	fields = u16(1).concat(u16(10 + 2 * n)).concat(u16(0x44)).concat(u16(0)).concat(u16(n))
	offsets = List.repeat(u16(set_at), n).join_map(|o| o)
	coverage = u16(2).concat(u16(1)).concat(u16(0)).concat(u16(n - 1)).concat(u16(0))
	var $set = u16(n)
	for g in 0..<n {
		$set = $set.concat(u16(g)).concat(i16(-1)).concat(u16(0))
	}
	gpos = header.concat(lookups).concat(lookup).concat(fields).concat(offsets).concat(coverage).concat($set)
	match LayoutVar.check_gpos(device_store, gpos, n) {
		Err(problems) => reasons(problems) == [TooMuchWork]
		Ok(_) => False
	}
}

# ------------------------------------------------------------ hand-built feature variations

cond_range : U64, I64, I64 -> List(U8)
cond_range = |axis, low, high| u16(1).concat(u16(axis)).concat(i16(low)).concat(i16(high))

cond_value : I64, U64, U64 -> List(U8)
cond_value = |default, outer, inner| u16(2).concat(i16(default)).concat(u16(outer)).concat(u16(inner))

# And (3) or or (4) of conditions; a null child where an entry is empty.
cond_combine : U64, List(List(U8)) -> List(U8)
cond_combine = |format, children| {
	n = children.len()
	var $offsets = []
	var $blobs = []
	var $at = 3 + 3 * n
	for child in children {
		$offsets = $offsets.concat(u24(if (child.is_empty()) 0 else $at))
		$blobs = $blobs.concat(child)
		$at = $at + child.len()
	}
	u16(format).concat([n.to_u8_wrap()]).concat($offsets).concat($blobs)
}

cond_not : List(U8) -> List(U8)
cond_not = |child| u16(5).concat(u24(5)).concat(child)

condition_set : List(List(U8)) -> List(U8)
condition_set = |conditions| {
	n = conditions.len()
	var $offsets = []
	var $blobs = []
	var $at = 2 + 4 * n
	for c in conditions {
		$offsets = $offsets.concat(u32(if (c.is_empty()) 0 else $at))
		$blobs = $blobs.concat(c)
		$at = $at + c.len()
	}
	u16(n).concat($offsets).concat($blobs)
}

# Substituted features with their lookups; a feature with lookup list `[]`
# gets a null alternate feature offset.
substitution : List((U64, List(U64))) -> List(U8)
substitution = |entries| {
	n = entries.len()
	var $records = []
	var $blobs = []
	var $at = 6 + 6 * n
	for (feature, lookups) in entries {
		blob = u16(0).concat(u16(lookups.len())).concat(lookups.join_map(u16))
		$records = $records.concat(u16(feature)).concat(u32($at))
		$blobs = $blobs.concat(blob)
		$at = $at + blob.len()
	}
	u16(1).concat(u16(0)).concat(u16(n)).concat($records).concat($blobs)
}

# A GSUB 1.1 with two features and three lookups (only their counts are
# read) and FeatureVariations records of a condition set and substitutions
# (an empty list for a null offset).
gsub_with : List((List(U8), List(U8))) -> List(U8)
gsub_with = |records| {
	n = records.len()
	head = u16(1).concat(u16(1)).concat(u16(0)).concat(u16(14)).concat(u16(16)).concat(u32(18))
	var $entries = []
	var $blobs = []
	var $at = 8 + 8 * n
	for (set, subst) in records {
		set_at = if (set.is_empty()) 0 else $at
		subst_at = if (subst.is_empty()) 0 else $at + set.len()
		$entries = $entries.concat(u32(set_at)).concat(u32(subst_at))
		$blobs = $blobs.concat(set).concat(subst)
		$at = $at + set.len() + subst.len()
	}
	head.concat(u16(2)).concat(u16(3)).concat(u16(1)).concat(u16(0)).concat(u32(n)).concat($entries).concat($blobs)
}

record_at : List(U8), List(I16) -> I64
record_at = |gsub, coords|
	match LayoutVar.read_feature_variations(gsub, "GSUB", device_store, 1) {
		Ok(fv) =>
			match LayoutVar.matching_record(fv, device_store, coords) {
				Ok(r) => r.to_i64_wrap()
				Err(NoMatch) => -1
			}
		Err(_) => -2
	}

fv_problems : List(U8) -> List(LayoutVar.Problem)
fv_problems = |gsub|
	match LayoutVar.read_feature_variations(gsub, "GSUB", device_store, 1) {
		Ok(_) => []
		Err(problems) => problems
	}

# A null condition set always holds; an unknown condition format never does.
expect {
	gsub = gsub_with([(condition_set([u16(9).concat(u16(0))]), substitution([(0, [1])])), ([], substitution([(1, [2])]))])
	record_at(gsub, [0]) == 1 and record_at(gsub, [16384]) == 1
}

# A null child of an and holds. A null condition directly in a set is a
# problem, as OTS rejects it.
expect {
	gsub = gsub_with([(condition_set([cond_combine(3, [[], cond_range(0, 0, 16384)])]), substitution([(0, [1])]))])
	record_at(gsub, [100]) == 0 and record_at(gsub, [-100]) == -1
}
expect reasons(fv_problems(gsub_with([(condition_set([[], cond_range(0, 0, 16384)]), substitution([(0, [1])]))]))) == [Truncated]

# Not, or and value conditions. Row (0, 0) is -75 at peak 1: -75 * s + 40 > 0
# holds below s = 40 / 75.
expect {
	gsub = gsub_with([(condition_set([cond_not(cond_combine(4, [cond_range(0, -16384, -8192), cond_value(40, 0, 0)]))]), substitution([(0, [])]))])
	# Not (coord <= -0.5 or value > 0): holds where the value is not positive.
	record_at(gsub, [-16384]) == -1 and record_at(gsub, [0]) == -1 and record_at(gsub, [8000]) == -1 and record_at(gsub, [8800]) == 0 and record_at(gsub, [16384]) == 0
}

# The value condition at the exact zero: 40 - 75 * (8 / 15) is not above 0,
# whatever the rounding of the single-precision delta. -75 * s + 75 > 0 for
# every s below 1, and not at 1.
expect {
	gsub = gsub_with([(condition_set([cond_value(75, 0, 0)]), substitution([(0, [1])]))])
	record_at(gsub, [16383]) == 0 and record_at(gsub, [16384]) == -1
}

# The substitutions at a location, with a feature that loses its lookups.
expect
	match LayoutVar.read_feature_variations(gsub_with([(condition_set([cond_range(0, 0, 16384)]), substitution([(0, []), (1, [2, 0])]))]), "GSUB", device_store, 1) {
		Ok(fv) =>
			LayoutVar.substitutions_at(fv, device_store, [5]).map(|s| (s.feature, LayoutVar.lookups_of(fv, s.table))) == [(0, []), (1, [2, 0])]
				and LayoutVar.substitutions_at(fv, device_store, [-5]) == []
		Err(_) => False
	}

# Before version 1.1 there are no feature variations.
expect
	match LayoutVar.read_feature_variations(u16(1).concat(u16(0)).concat(u16(0)).concat(u16(10)).concat(u16(12)).concat(u16(0)).concat(u16(0)), "GSUB", device_store, 1) {
		Ok(fv) => LayoutVar.matching_record(fv, device_store, [0]) == Err(NoMatch)
		Err(_) => False
	}

# Problems, one per bad record, all reported: a lookup index past the
# lookup list, an axis the font lacks, an unsupported substitution version,
# an alternate feature table inside the records, and a range condition
# outside [-1, 1]. A feature index past the feature list and substitutions
# out of order are accepted, as OTS accepts them.
expect {
	gsub = gsub_with([
		([], substitution([(2, [0])])),
		([], substitution([(1, [0]), (0, [0]), (1, [1])])),
		([], substitution([(0, [3])])),
		(condition_set([cond_range(1, 0, 1)]), []),
		([], u16(2).concat(u16(0)).concat(u16(0))),
		([], u16(1).concat(u16(0)).concat(u16(1)).concat(u16(0)).concat(u32(2))),
		(condition_set([cond_range(0, -16385, 0)]), []),
	])
	reasons(fv_problems(gsub)) == [LookupIndex, AxisIndex, UnsupportedVersion, Truncated, MapRange]
}

# A value condition naming a row the store lacks.
expect reasons(fv_problems(gsub_with([(condition_set([cond_value(1, 0, 3)]), [])]))) == [DeltaIndex]

# Conditions nested 64 deep (63 nots around a range, so the range negated)
# are read; 65 deep are refused.
expect {
	nest = |depth| {
		var $c = cond_range(0, 0, 16384)
		for _ in 1..<depth {
			$c = cond_not($c)
		}
		$c
	}
	ok = gsub_with([(condition_set([nest(64)]), [])])
	deep = gsub_with([(condition_set([nest(65)]), [])])
	record_at(ok, [5]) == -1 and record_at(ok, [-5]) == 0 and reasons(fv_problems(deep)) == [NestingDepth]
}

# A condition shared through offsets many times over: a chain of ors each
# naming the next twice describes 2^40 conditions in a few hundred bytes,
# and the work allowance refuses it.
expect {
	var $c = cond_range(0, 0, 16384)
	for _ in 0..<40 {
		# Both entries point at the same child, 9 bytes on.
		$c = u16(4).concat([2]).concat(u24(9)).concat(u24(9)).concat($c)
	}
	reasons(fv_problems(gsub_with([(condition_set([$c]), [])]))) == [TooMuchWork]
}

# Truncated: a condition set running past the table.
expect reasons(fv_problems(gsub_with([(u16(5).concat(u32(6)), [])]))) == [Truncated]

# ------------------------------------------------------------ corrupted bytes

# Every byte of the fixture's GPOS and GDEF corrupted in turn: never a
# crash, a problem whenever reading fails, and repeatable adjustments when
# it succeeds. The value records are those of the intact table (the pair
# search here is a test helper that does not check what it walks); reading
# a value record is total on any bytes.
expect {
	gpos = kern_gpos
	gdef = kern_gdef
	locations = [[0, 0], [16384, 0], [-8192, 12000], [9000, -16384]]
	var $records = []
	for left in 0..<9 {
		for right in [1, 2, 5, 9] {
			$records = $records.concat(pair_records(gpos, left, right))
		}
	}
	records = $records
	run = |lv, g| {
		var $sum = 0
		for coords in locations {
			loc = LayoutVar.location(lv, coords)
			for found in records {
				v = LayoutVar.value(lv, loc, g, found.first.base, found.first.at, found.first.format)
				$sum = $sum + v.x_advance + v.x_placement + v.y_placement + LayoutVar.x_advance(lv, loc, g, found.second.base, found.second.at, found.second.format)
			}
		}
		$sum
	}
	var $ok = True
	for i in 0..<gpos.len() {
		bad = gpos.set(i, (gpos.get(i) ?? 0).bitwise_xor(0x5A)) ?? []
		match LayoutVar.read_gdef(gdef, 2) {
			Ok(lv) =>
				match LayoutVar.check_gpos(lv, bad, 8) {
					Ok(_) => {
						$ok = $ok and run(lv, bad) == run(lv, bad)
					}
					Err(problems) => {
						$ok = $ok and !problems.is_empty()
					}
				}
			Err(_) => {
				$ok = False
			}
		}
	}
	for i in 0..<gdef.len() {
		bad = gdef.set(i, (gdef.get(i) ?? 0).bitwise_xor(0x5A)) ?? []
		match LayoutVar.read_gdef(bad, 2) {
			Ok(lv) =>
				match LayoutVar.check_gpos(lv, gpos, 8) {
					Ok(_) => {
						$ok = $ok and run(lv, gpos) == run(lv, gpos)
					}
					Err(problems) => {
						$ok = $ok and !problems.is_empty()
					}
				}
			Err(problems) => {
				$ok = $ok and !problems.is_empty()
			}
		}
	}
	$ok
}

# Every byte of the fixture's GSUB corrupted in turn: never a crash, a
# problem whenever reading fails, and a repeatable record when it succeeds.
expect
	match LayoutVar.read_gdef(feature_gdef, 2) {
		Ok(lv) => {
			gsub = feature_gsub
			var $ok = True
			for i in 0..<gsub.len() {
				for flip in [0x5A, 0xFF] {
					bad = gsub.set(i, (gsub.get(i) ?? 0).bitwise_xor(flip)) ?? []
					match LayoutVar.read_feature_variations(bad, "GSUB", lv, 2) {
						Ok(fv) =>
							for coords in [[0, 0], [8192, -8192], [-16384, 16384], [-10240, 0]] {
								a = LayoutVar.substitutions_at(fv, lv, coords)
								b = LayoutVar.substitutions_at(fv, lv, coords)
								$ok = $ok and a == b and a.all(|s| LayoutVar.lookups_of(fv, s.table).all(|l| l < 4))
							}
						Err(problems) => {
							$ok = $ok and !problems.is_empty()
						}
					}
				}
			}
			$ok
		}
		Err(_) => False
	}

# ------------------------------------------------------------ GDEF as OTS checks it

gdef_ok : List(U8), U64, [Present(U64), Absent] -> Bool
gdef_ok = |gdef, glyphs, axes| LayoutVar.check_gdef(gdef, glyphs, axes).is_ok()

# A version 1.3 table with a store on the font's one axis passes; the same
# store on a font with two axes, or with no `fvar`, does not (its region
# list names one axis); a store with a region crossing zero does not.
expect gdef_ok(gdef_header(3, 18).concat(one_store(-75)), 10, Present(1))
expect !gdef_ok(gdef_header(3, 18).concat(one_store(-75)), 10, Present(2))
expect !gdef_ok(gdef_header(3, 18).concat(one_store(-75)), 10, Absent)
expect {
	crossing = gdef_header(3, 18).concat(one_store(-75))
	# The region's start (at 18 + 12 + 4) moved below zero, its peak 1.
	bad = crossing.take_first(34).concat(i16(-16384)).concat(crossing.drop_first(36))
	!gdef_ok(bad, 10, Present(1))
}

# An attachment list: coverage of glyphs 1 and 2, each with increasing
# point indices. Points out of order, a coverage glyph past the font, and
# a zero point count are what OTS rejects.
attach : List(U64), List(List(U64)) -> List(U8)
attach = |glyphs, points| {
	n = glyphs.len()
	coverage = u16(1).concat(u16(n)).concat(glyphs.join_map(u16))
	var $tables = []
	var $offsets = []
	var $at = 4 + 2 * n + coverage.len()
	for p in points {
		t = u16(p.len()).concat(p.join_map(u16))
		$offsets = $offsets.concat(u16($at))
		$tables = $tables.concat(t)
		$at = $at + t.len()
	}
	list = u16(4 + 2 * n).concat(u16(n)).concat($offsets).concat(coverage).concat($tables)
	u16(1).concat(u16(0)).concat(u16(0)).concat(u16(12)).concat(u16(0)).concat(u16(0)).concat(list)
}

expect gdef_ok(attach([1, 2], [[0, 3], [2]]), 10, Absent)
expect !gdef_ok(attach([1, 2], [[3, 3], [2]]), 10, Absent)
expect !gdef_ok(attach([1, 12], [[0, 3], [2]]), 10, Absent)
expect !gdef_ok(attach([1, 2], [[], [2]]), 10, Absent)

# Glyph classes up to 4 only; a class range that overlaps the one before;
# version 1.1 (which does not exist) and a truncated header.
classes : List(U8) -> List(U8)
classes = |class_def| u16(1).concat(u16(0)).concat(u16(12)).concat(List.repeat(0, 6)).concat(class_def)

expect gdef_ok(classes(u16(2).concat(u16(2)).concat(u16(1)).concat(u16(2)).concat(u16(1)).concat(u16(3)).concat(u16(5)).concat(u16(3))), 10, Absent)
expect !gdef_ok(classes(u16(2).concat(u16(1)).concat(u16(1)).concat(u16(2)).concat(u16(5))), 10, Absent)
expect !gdef_ok(classes(u16(2).concat(u16(2)).concat(u16(1)).concat(u16(4)).concat(u16(1)).concat(u16(3)).concat(u16(5)).concat(u16(3))), 10, Absent)
expect !gdef_ok(u16(1).concat(u16(1)).concat(List.repeat(0, 8)), 10, Absent)
expect !gdef_ok(u16(1).concat(u16(0)).concat(List.repeat(0, 4)), 10, Absent)

# ------------------------------------------------------------ lookup variations

# A GSUB 1.1 like `gsub_with`, without feature variation records, whose
# FeatureVariations (version 1.1) has lookup variation records: a feature,
# its flags (1 keeps the feature's own lookups) and conditions with the
# lookups each adds (an empty condition for a null offset).
gsub_lookup_variations : List((U64, U64, List((List(U8), List(U64))))) -> List(U8)
gsub_lookup_variations = |records| {
	m = records.len()
	head = u16(1).concat(u16(1)).concat(u16(0)).concat(u16(14)).concat(u16(16)).concat(u32(18))
	var $entries = []
	var $blobs = []
	var $at = 8 + 4 + 6 * m
	for (feature, flags, conditions) in records {
		k = conditions.len()
		var $fields = []
		var $parts = []
		var $inner = 10 + 8 * k
		for (condition, lookups) in conditions {
			list = u16(lookups.len()).concat(lookups.join_map(u16))
			$fields = $fields.concat(u32(if (condition.is_empty()) 0 else $inner)).concat(u32($inner + condition.len()))
			$parts = $parts.concat(condition).concat(list)
			$inner = $inner + condition.len() + list.len()
		}
		lookups_table = u16(1).concat(u16(0)).concat(u16(flags)).concat(u32(k)).concat($fields).concat($parts)
		$entries = $entries.concat(u16(feature)).concat(u32($at))
		$blobs = $blobs.concat(lookups_table)
		$at = $at + lookups_table.len()
	}
	head.concat(u16(2)).concat(u16(3)).concat(u16(1)).concat(u16(1)).concat(u32(0)).concat(u32(m)).concat($entries).concat($blobs)
}

lookup_variations : List(U8), List(I16) -> List({ feature : U64, defaults : Bool, lookups : List(U64) })
lookup_variations = |gsub, coords|
	match LayoutVar.read_feature_variations(gsub, "GSUB", device_store, 1) {
		Ok(fv) => LayoutVar.lookup_variations_at(fv, device_store, coords)
		Err(_) => [{ feature: 99, defaults: False, lookups: [] }]
	}

two_features : List(U8)
two_features = gsub_lookup_variations([(0, 1, [(cond_range(0, 0, 16384), [2]), ([], [1])]), (1, 0, [(cond_range(0, -16384, -1), [0])])])

# Each record gives its feature, whether it keeps the feature's lookups,
# and the lookups of the conditions that hold; a null condition holds.
expect lookup_variations(two_features, [5]) == [{ feature: 0, defaults: True, lookups: [2, 1] }, { feature: 1, defaults: False, lookups: [] }]
expect lookup_variations(two_features, [-5]) == [{ feature: 0, defaults: True, lookups: [1] }, { feature: 1, defaults: False, lookups: [0] }]

# A variation replaces a feature's lookups, keeping them only when its flag
# asks; a feature without one keeps its own.
expect {
	at = lookup_variations(two_features, [5])
	LayoutVar.varied_lookups(at, 0, [9]) == [9, 2, 1] and LayoutVar.varied_lookups(at, 1, [9]) == [] and LayoutVar.varied_lookups(at, 5, [9]) == [9]
}

# Every lookup a lookup variation names is read, whatever the location.
expect LayoutVar.variation_lookups(two_features, [False, False, False, False]) == [True, True, True, False]

# OTS does not read lookup variations, so nothing in them is a problem: an
# axis past the font reads coordinate 0, a condition past the table holds,
# and a feature lookups table of another version counts as absent.
expect lookup_variations(gsub_lookup_variations([(0, 0, [(cond_range(7, -1, 1), [2])])]), [5]) == [{ feature: 0, defaults: False, lookups: [2] }]
expect {
	gsub = gsub_lookup_variations([(0, 0, [(cond_range(0, -16384, -1), [2])])])
	# The condition offset of the one record (FeatureLookupsTable at 18 + 18,
	# its first field at 10) pointed past the end of the table.
	broken = gsub.sublist({ start: 0, len: 46 }).concat(u32(4000)).concat(gsub.drop_first(50))
	lookup_variations(broken, [5]) == [{ feature: 0, defaults: False, lookups: [2] }]
}
expect {
	gsub = gsub_lookup_variations([(0, 1, [([], [2])])])
	broken = gsub.sublist({ start: 0, len: 36 }).concat(u16(2)).concat(gsub.drop_first(38))
	lookup_variations(broken, [5]) == [{ feature: 0, defaults: False, lookups: [] }]
}

# A lookup variation list past the end of the table drops the whole
# FeatureVariations, as HarfBuzz's sanitizer drops it.
expect {
	gsub = gsub_lookup_variations([(0, 1, [([], [2])])])
	broken = gsub.sublist({ start: 0, len: 26 }).concat(u32(1000)).concat(gsub.drop_first(30))
	lookup_variations(broken, [5]) == []
}
