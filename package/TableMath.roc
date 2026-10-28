import Bytes
import LayoutVar

## OpenType mathematical typesetting data, checked once and queried in
## font units. Internal: layout of expressions belongs to the caller.
## Prepared data retains checked bytes and scalar offsets, not nested
## lists. Queries follow table order and are total, including absent data
## and glyph ids past the font. Pixel devices are validated but contribute
## zero at our font-unit boundary; variation devices use the GDEF store.
TableMath := {
	bytes : List(U8),
	constants_at : U64,
	glyph_info : U64,
	variants_at : U64,
	glyph_count : U64,
	lv : LayoutVar,
	loc : LayoutVar.Location,
}.{
	Corner : [TopRight, TopLeft, BottomRight, BottomLeft]
	Axis : [Horizontal, Vertical]
	Variant : { glyph : U32, advance : I32 }
	Part : { glyph : U32, start_connector : I32, end_connector : I32, full_advance : I32, extender : Bool }
	Assembly : { italic_correction : I64, parts : List(Part) }
	KernTable : { heights : List(I64), values : List(I64) }

	## Percentages are distinct named fields, never font-unit lengths.
	Constants : {
		script_percent_scale_down : I16,
		script_script_percent_scale_down : I16,
		delimited_sub_formula_min_height : I32,
		display_operator_min_height : I32,
		math_leading : I64,
		axis_height : I64,
		accent_base_height : I64,
		flattened_accent_base_height : I64,
		subscript_shift_down : I64,
		subscript_top_max : I64,
		subscript_baseline_drop_min : I64,
		superscript_shift_up : I64,
		superscript_shift_up_cramped : I64,
		superscript_bottom_min : I64,
		superscript_baseline_drop_max : I64,
		sub_superscript_gap_min : I64,
		superscript_bottom_max_with_subscript : I64,
		space_after_script : I64,
		upper_limit_gap_min : I64,
		upper_limit_baseline_rise_min : I64,
		lower_limit_gap_min : I64,
		lower_limit_baseline_drop_min : I64,
		stack_top_shift_up : I64,
		stack_top_display_style_shift_up : I64,
		stack_bottom_shift_down : I64,
		stack_bottom_display_style_shift_down : I64,
		stack_gap_min : I64,
		stack_display_style_gap_min : I64,
		stretch_stack_top_shift_up : I64,
		stretch_stack_bottom_shift_down : I64,
		stretch_stack_gap_above_min : I64,
		stretch_stack_gap_below_min : I64,
		fraction_numerator_shift_up : I64,
		fraction_numerator_display_style_shift_up : I64,
		fraction_denominator_shift_down : I64,
		fraction_denominator_display_style_shift_down : I64,
		fraction_numerator_gap_min : I64,
		fraction_num_display_style_gap_min : I64,
		fraction_rule_thickness : I64,
		fraction_denominator_gap_min : I64,
		fraction_denom_display_style_gap_min : I64,
		skewed_fraction_horizontal_gap : I64,
		skewed_fraction_vertical_gap : I64,
		overbar_vertical_gap : I64,
		overbar_rule_thickness : I64,
		overbar_extra_ascender : I64,
		underbar_vertical_gap : I64,
		underbar_rule_thickness : I64,
		underbar_extra_descender : I64,
		radical_vertical_gap : I64,
		radical_display_style_vertical_gap : I64,
		radical_rule_thickness : I64,
		radical_extra_ascender : I64,
		radical_kern_before_degree : I64,
		radical_kern_after_degree : I64,
		radical_degree_bottom_raise_percent : I16,
	}

	none : TableMath
	none = { bytes: [], constants_at: 0, glyph_info: 0, variants_at: 0, glyph_count: 0, lv: LayoutVar.none(0), loc: LayoutVar.default_location }

	has_data : TableMath -> Bool
	has_data = |math| !math.bytes.is_empty()

	at_location : TableMath, LayoutVar.Location -> TableMath
	at_location = |math, loc| { ..math, loc }

	constants : TableMath -> [Present(Constants), Absent]
	constants = |math| {
		if !TableMath.has_data(math) {
			return Absent
		}
		at = math.constants_at
		data = math.bytes
		Present({
			script_percent_scale_down: Bytes.i16(data, at).to_i16_wrap(),
			script_script_percent_scale_down: Bytes.i16(data, at + 2).to_i16_wrap(),
			delimited_sub_formula_min_height: Bytes.u16(data, at + 4).to_i32_wrap(),
			display_operator_min_height: Bytes.u16(data, at + 6).to_i32_wrap(),
			math_leading: TableMath.value(math, at, at + 8),
			axis_height: TableMath.value(math, at, at + 12),
			accent_base_height: TableMath.value(math, at, at + 16),
			flattened_accent_base_height: TableMath.value(math, at, at + 20),
			subscript_shift_down: TableMath.value(math, at, at + 24),
			subscript_top_max: TableMath.value(math, at, at + 28),
			subscript_baseline_drop_min: TableMath.value(math, at, at + 32),
			superscript_shift_up: TableMath.value(math, at, at + 36),
			superscript_shift_up_cramped: TableMath.value(math, at, at + 40),
			superscript_bottom_min: TableMath.value(math, at, at + 44),
			superscript_baseline_drop_max: TableMath.value(math, at, at + 48),
			sub_superscript_gap_min: TableMath.value(math, at, at + 52),
			superscript_bottom_max_with_subscript: TableMath.value(math, at, at + 56),
			space_after_script: TableMath.value(math, at, at + 60),
			upper_limit_gap_min: TableMath.value(math, at, at + 64),
			upper_limit_baseline_rise_min: TableMath.value(math, at, at + 68),
			lower_limit_gap_min: TableMath.value(math, at, at + 72),
			lower_limit_baseline_drop_min: TableMath.value(math, at, at + 76),
			stack_top_shift_up: TableMath.value(math, at, at + 80),
			stack_top_display_style_shift_up: TableMath.value(math, at, at + 84),
			stack_bottom_shift_down: TableMath.value(math, at, at + 88),
			stack_bottom_display_style_shift_down: TableMath.value(math, at, at + 92),
			stack_gap_min: TableMath.value(math, at, at + 96),
			stack_display_style_gap_min: TableMath.value(math, at, at + 100),
			stretch_stack_top_shift_up: TableMath.value(math, at, at + 104),
			stretch_stack_bottom_shift_down: TableMath.value(math, at, at + 108),
			stretch_stack_gap_above_min: TableMath.value(math, at, at + 112),
			stretch_stack_gap_below_min: TableMath.value(math, at, at + 116),
			fraction_numerator_shift_up: TableMath.value(math, at, at + 120),
			fraction_numerator_display_style_shift_up: TableMath.value(math, at, at + 124),
			fraction_denominator_shift_down: TableMath.value(math, at, at + 128),
			fraction_denominator_display_style_shift_down: TableMath.value(math, at, at + 132),
			fraction_numerator_gap_min: TableMath.value(math, at, at + 136),
			fraction_num_display_style_gap_min: TableMath.value(math, at, at + 140),
			fraction_rule_thickness: TableMath.value(math, at, at + 144),
			fraction_denominator_gap_min: TableMath.value(math, at, at + 148),
			fraction_denom_display_style_gap_min: TableMath.value(math, at, at + 152),
			skewed_fraction_horizontal_gap: TableMath.value(math, at, at + 156),
			skewed_fraction_vertical_gap: TableMath.value(math, at, at + 160),
			overbar_vertical_gap: TableMath.value(math, at, at + 164),
			overbar_rule_thickness: TableMath.value(math, at, at + 168),
			overbar_extra_ascender: TableMath.value(math, at, at + 172),
			underbar_vertical_gap: TableMath.value(math, at, at + 176),
			underbar_rule_thickness: TableMath.value(math, at, at + 180),
			underbar_extra_descender: TableMath.value(math, at, at + 184),
			radical_vertical_gap: TableMath.value(math, at, at + 188),
			radical_display_style_vertical_gap: TableMath.value(math, at, at + 192),
			radical_rule_thickness: TableMath.value(math, at, at + 196),
			radical_extra_ascender: TableMath.value(math, at, at + 200),
			radical_kern_before_degree: TableMath.value(math, at, at + 204),
			radical_kern_after_degree: TableMath.value(math, at, at + 208),
			radical_degree_bottom_raise_percent: Bytes.i16(data, at + 212).to_i16_wrap(),
		})
	}

	value : TableMath, U64, U64 -> I64
	value = |math, base, at| {
		v = Bytes.i16(math.bytes, at) + LayoutVar.device_delta(math.lv, math.loc, math.bytes, base, at + 2)
		# A valid row has at most65535columns, each scalar at most1,
		# and each delta fits I32. Even allowing binary32 accumulation
		# error, the rounded delta is below2^48 in magnitude. Adding an
		# I16 base therefore fits I64 without clamping valid font facts.
		v
	}

	info_child : TableMath, U64 -> U64
	info_child = |math, field| {
		if !TableMath.has_data(math) {
			return 0
		}
		offset = Bytes.u16(math.bytes, math.glyph_info + field)
		if (offset == 0) 0 else math.glyph_info + offset
	}

	glyph_value : TableMath, U32, U64 -> [Present(I64), Absent]
	glyph_value = |math, glyph, field| {
		at = TableMath.info_child(math, field)
		if at == 0 or glyph.to_u64() >= math.glyph_count {
			return Absent
		}
		match TableMath.covered(math.bytes, at + Bytes.u16(math.bytes, at), glyph.to_u64()) {
			Present(index) => Present(TableMath.value(math, at, at + 4 + 4 * index))
			Absent => Absent
		}
	}

	italic_correction : TableMath, U32 -> [Present(I64), Absent]
	italic_correction = |math, glyph| TableMath.glyph_value(math, glyph, 0)

	top_accent_attachment : TableMath, U32 -> [Present(I64), Absent]
	top_accent_attachment = |math, glyph| TableMath.glyph_value(math, glyph, 2)

	extended_shape : TableMath, U32 -> Bool
	extended_shape = |math, glyph| {
		at = TableMath.info_child(math, 4)
		if at == 0 or glyph.to_u64() >= math.glyph_count {
			return False
		}
		match TableMath.covered(math.bytes, at, glyph.to_u64()) {
			Present(_) => True
			Absent => False
		}
	}

	corner_index : Corner -> U64
	corner_index = |corner| match corner {
		TopRight => 0
		TopLeft => 1
		BottomRight => 2
		BottomLeft => 3
	}

	kern_at : TableMath, U32, Corner -> U64
	kern_at = |math, glyph, corner| {
		at = TableMath.info_child(math, 6)
		if at == 0 or glyph.to_u64() >= math.glyph_count {
			return 0
		}
		match TableMath.covered(math.bytes, at + Bytes.u16(math.bytes, at), glyph.to_u64()) {
			Absent => 0
			Present(index) => {
				offset = Bytes.u16(math.bytes, at + 4 + 8 * index + 2 * TableMath.corner_index(corner))
				if (offset == 0) 0 else at + offset
			}
		}
	}

	## Equality at a threshold selects the following range, as HarfBuzz does.
	kern : TableMath, U32, Corner, I64 -> I64
	kern = |math, glyph, corner, height| {
		at = TableMath.kern_at(math, glyph, corner)
		if at == 0 {
			return 0
		}
		n = Bytes.u16(math.bytes, at)
		# HarfBuzz's inclusive binary search stops on the first equality
		# it visits. Preserve that deterministic tie rule for duplicate
		# heights instead of sorting, repairing or skipping equal records.
		var $lo = 0.I64
		var $hi = n.to_i64_wrap() - 1
		while $lo <= $hi {
			mid = $lo + ($hi - $lo) // 2
			candidate = TableMath.value(math, at, at + 2 + 4 * mid.to_u64_wrap())
			if height < candidate {
				$hi = mid - 1
			} else if height > candidate {
				$lo = mid + 1
			} else {
				return TableMath.value(math, at, at + 2 + 4 * (n + mid.to_u64_wrap() + 1))
			}
		}
		TableMath.value(math, at, at + 2 + 4 * (n + $lo.to_u64_wrap()))
	}

	kern_table : TableMath, U32, Corner -> KernTable
	kern_table = |math, glyph, corner| {
		at = TableMath.kern_at(math, glyph, corner)
		if at == 0 {
			return { heights: [], values: [] }
		}
		n = Bytes.u16(math.bytes, at)
		var $heights = List.with_capacity(n)
		var $values = List.with_capacity(n + 1)
		for i in 0..<n {
			$heights = $heights.append(TableMath.value(math, at, at + 2 + 4 * i))
		}
		for i in 0..<(n + 1) {
			$values = $values.append(TableMath.value(math, at, at + 2 + 4 * (n + i)))
		}
		{ heights: $heights, values: $values }
	}

	construction : TableMath, U32, Axis -> U64
	construction = |math, glyph, axis| {
		if !TableMath.has_data(math) or glyph.to_u64() >= math.glyph_count {
			return 0
		}
		at = math.variants_at
		cov_field = match axis {
			Vertical => 2
			Horizontal => 4
		}
		offset = Bytes.u16(math.bytes, at + cov_field)
		if offset == 0 {
			return 0
		}
		match TableMath.covered(math.bytes, at + offset, glyph.to_u64()) {
			Absent => 0
			Present(index) => {
				skip = match axis {
					Vertical => 0
					Horizontal => Bytes.u16(math.bytes, at + 6)
				}
				at + Bytes.u16(math.bytes, at + 10 + 2 * (skip + index))
			}
		}
	}

	variants : TableMath, U32, Axis -> List(Variant)
	variants = |math, glyph, axis| {
		at = TableMath.construction(math, glyph, axis)
		if at == 0 {
			return []
		}
		n = Bytes.u16(math.bytes, at + 2)
		var $out = List.with_capacity(n)
		for i in 0..<n {
			r = at + 4 + 4 * i
			$out = $out.append({ glyph: Bytes.u16(math.bytes, r).to_u32_wrap(), advance: Bytes.u16(math.bytes, r + 2).to_i32_wrap() })
		}
		$out
	}

	assembly : TableMath, U32, Axis -> [Present(Assembly), Absent]
	assembly = |math, glyph, axis| {
		at = TableMath.construction(math, glyph, axis)
		if at == 0 {
			return Absent
		}
		offset = Bytes.u16(math.bytes, at)
		if offset == 0 {
			return Absent
		}
		base = at + offset
		n = Bytes.u16(math.bytes, base + 4)
		var $parts = List.with_capacity(n)
		for i in 0..<n {
			r = base + 6 + 10 * i
			$parts = $parts.append({ glyph: Bytes.u16(math.bytes, r).to_u32_wrap(), start_connector: Bytes.u16(math.bytes, r + 2).to_i32_wrap(), end_connector: Bytes.u16(math.bytes, r + 4).to_i32_wrap(), full_advance: Bytes.u16(math.bytes, r + 6).to_i32_wrap(), extender: Bytes.u16(math.bytes, r + 8).bitwise_and(1) != 0 })
		}
		Present({ italic_correction: TableMath.value(math, base, base), parts: $parts })
	}

	min_connector_overlap : TableMath -> I32
	min_connector_overlap = |math| if (TableMath.has_data(math)) Bytes.u16(math.bytes, math.variants_at).to_i32_wrap() else 0

	## Read one complete MATH table. Problems are offsets relative to it.
	## Independent constants, glyph-info children and variant directions are
	## checked even when another fails. Each validation branch has a budget
	## of eight visits per byte plus 16384, bounding malicious shared offsets.
	read : List(U8), U64, LayoutVar -> Try(TableMath, List(U64))
	read = |data, glyph_count, lv| {
		if !Bytes.fits(0, 10, data.len()) {
			return Err([0])
		}
		if Bytes.u16(data, 0) != 1 or Bytes.u16(data, 2) != 0 {
			return Err([0])
		}
		c = Bytes.u16(data, 4)
		g = Bytes.u16(data, 6)
		v = Bytes.u16(data, 8)
		var $problems = []
		match TableMath.check_constants(data, c, lv) {
			Ok(_) => {}
			Err(Bad(at)) => {
				$problems = $problems.append(at)
			}
		}
		if g == 0 or !Bytes.fits(g, 8, data.len()) {
			$problems = $problems.append(6)
		} else {
			for field in [0.U64, 2, 4, 6] {
				offset = Bytes.u16(data, g + field)
				if offset != 0 {
					at = g + offset
					checked = if field == 4 {
						match TableMath.check_coverage(data, at, glyph_count) {
							Ok(_) => Ok({})
							Err(e) => Err(e)
						}
					} else if field == 6 {
						match TableMath.check_kern_info(data, at, glyph_count, lv) {
							Ok(_) => Ok({})
							Err(e) => Err(e)
						}
					} else {
						TableMath.check_glyph_values(data, at, glyph_count, lv)
					}
					match checked {
						Ok(_) => {}
						Err(Bad(bad)) => {
							$problems = $problems.append(bad)
						}
					}
				}
			}
		}
		if v == 0 or !Bytes.fits(v, 10, data.len()) {
			$problems = $problems.append(8)
		} else {
			for axis in [Vertical, Horizontal] {
				match TableMath.check_variants(data, v, glyph_count, axis, lv) {
					Ok(_) => {}
					Err(Bad(at)) => {
						$problems = $problems.append(at)
					}
				}
			}
		}
		if $problems.is_empty() {
			Ok({ bytes: data, constants_at: c, glyph_info: g, variants_at: v, glyph_count, lv, loc: LayoutVar.default_location })
		} else {
			Err($problems)
		}
	}

	spend : List(U8), U64, U64, U64 -> Try(U64, [Bad(U64)])
	spend = |data, steps, cost, at| {
		total = steps + cost + 1
		if (total > data.len() * 8 + 16384) Err(Bad(at)) else Ok(total)
	}

	check_value : List(U8), U64, U64, LayoutVar -> Try({}, [Bad(U64)])
	check_value = |data, base, at, lv| {
		if !Bytes.fits(at, 4, data.len()) {
			return Err(Bad(at))
		}
		offset = Bytes.u16(data, at + 2)
		if offset == 0 {
			return Ok({})
		}
		device = base + offset
		if !Bytes.fits(device, 6, data.len()) {
			return Err(Bad(at + 2))
		}
		start = Bytes.u16(data, device)
		end = Bytes.u16(data, device + 2)
		format = Bytes.u16(data, device + 4)
		if format == 0x8000 {
			if (LayoutVar.valid_index(lv, start, end)) Ok({}) else Err(Bad(device))
		} else if format >= 1 and format <= 3 and start <= end {
			per_word = (1.U64).shl_wrap((4 - format).to_u8_wrap())
			words = (end - start) // per_word + 1
			if (Bytes.fits(device + 6, 2 * words, data.len())) Ok({}) else Err(Bad(device))
		} else {
			Err(Bad(device + 4))
		}
	}

	check_constants : List(U8), U64, LayoutVar -> Try({}, [Bad(U64)])
	check_constants = |data, at, lv| {
		if at == 0 or !Bytes.fits(at, 214, data.len()) {
			return Err(Bad(4))
		}
		for i in 0..<51 {
			TableMath.check_value(data, at, at + 8 + 4 * i, lv)?
		}
		Ok({})
	}

	## Validate without expanding ranges or allocating from an untrusted count.
	check_coverage : List(U8), U64, U64 -> Try(U64, [Bad(U64)])
	check_coverage = |data, at, glyph_count| {
		if !Bytes.fits(at, 4, data.len()) {
			return Err(Bad(at))
		}
		format = Bytes.u16(data, at)
		n = Bytes.u16(data, at + 2)
		width = if (format == 1) 2 else 6
		if (format != 1 and format != 2) or !Bytes.fits(at + 4, width * n, data.len()) {
			return Err(Bad(at))
		}
		var $count = 0
		var $previous = 0
		for i in 0..<n {
			r = at + 4 + width * i
			first = Bytes.u16(data, r)
			last = if (format == 1) first else Bytes.u16(data, r + 2)
			if first > last or last >= glyph_count or (i > 0 and first <= $previous) {
				return Err(Bad(r))
			}
			if format == 2 and Bytes.u16(data, r + 4) != $count {
				return Err(Bad(r + 4))
			}
			$count = $count + last - first + 1
			$previous = last
		}
		Ok($count)
	}

	covered : List(U8), U64, U64 -> [Present(U64), Absent]
	covered = |data, at, glyph| {
		format = Bytes.u16(data, at)
		width = if (format == 1) 2 else 6
		var $lo = 0
		var $hi = Bytes.u16(data, at + 2)
		while $lo < $hi {
			mid = $lo + ($hi - $lo) // 2
			r = at + 4 + width * mid
			first = Bytes.u16(data, r)
			last = if (format == 1) first else Bytes.u16(data, r + 2)
			if glyph < first {
				$hi = mid
			} else if glyph > last {
				$lo = mid + 1
			} else {
				return Present(if (format == 1) mid else Bytes.u16(data, r + 4) + glyph - first)
			}
		}
		Absent
	}

	check_glyph_values : List(U8), U64, U64, LayoutVar -> Try({}, [Bad(U64)])
	check_glyph_values = |data, at, glyph_count, lv| {
		if !Bytes.fits(at, 4, data.len()) {
			return Err(Bad(at))
		}
		n = Bytes.u16(data, at + 2)
		offset = Bytes.u16(data, at)
		if !Bytes.fits(at + 4, 4 * n, data.len()) or offset == 0 {
			return Err(Bad(at))
		}
		coverage_count = TableMath.check_coverage(data, at + offset, glyph_count)?
		if coverage_count != n {
			return Err(Bad(at + 2))
		}
		for i in 0..<n {
			TableMath.check_value(data, at, at + 4 + 4 * i, lv)?
		}
		Ok({})
	}

	check_kern_info : List(U8), U64, U64, LayoutVar -> Try(U64, [Bad(U64)])
	check_kern_info = |data, at, glyph_count, lv| {
		if !Bytes.fits(at, 4, data.len()) {
			return Err(Bad(at))
		}
		n = Bytes.u16(data, at + 2)
		offset = Bytes.u16(data, at)
		if offset == 0 or !Bytes.fits(at + 4, 8 * n, data.len()) {
			return Err(Bad(at))
		}
		coverage_count = TableMath.check_coverage(data, at + offset, glyph_count)?
		if coverage_count != n {
			return Err(Bad(at + 2))
		}
		var $steps = TableMath.spend(data, 0, n, at)?
		for i in 0..<(4 * n) {
			r = at + 4 + 2 * i
			child = Bytes.u16(data, r)
			if child != 0 {
				$steps = TableMath.check_kern(data, at + child, $steps, lv)?
			}
		}
		Ok($steps)
	}

	check_kern : List(U8), U64, U64, LayoutVar -> Try(U64, [Bad(U64)])
	check_kern = |data, at, steps, lv| {
		if !Bytes.fits(at, 2, data.len()) {
			return Err(Bad(at))
		}
		n = Bytes.u16(data, at)
		if !Bytes.fits(at + 2, 4 * (2 * n + 1), data.len()) {
			return Err(Bad(at))
		}
		spent = TableMath.spend(data, steps, 2 * n + 1, at)?
		var $previous = -32769.I64
		for i in 0..<n {
			r = at + 2 + 4 * i
			height = Bytes.i16(data, r)
			if height < $previous {
				return Err(Bad(r))
			}
			$previous = height
		}
		for i in 0..<(2 * n + 1) {
			TableMath.check_value(data, at, at + 2 + 4 * i, lv)?
		}
		Ok(spent)
	}

	check_variants : List(U8), U64, U64, Axis, LayoutVar -> Try(U64, [Bad(U64)])
	check_variants = |data, at, glyph_count, axis, lv| {
		count_field = match axis {
			Vertical => 6
			Horizontal => 8
		}
		coverage_field = match axis {
			Vertical => 2
			Horizontal => 4
		}
		n = Bytes.u16(data, at + count_field)
		offset = Bytes.u16(data, at + coverage_field)
		first = at + 10 + (
			match axis {
				Vertical => 0
				Horizontal => 2 * Bytes.u16(data, at + 6)
			}
		)
		if !Bytes.fits(first, 2 * n, data.len()) {
			return Err(Bad(first))
		}
		if offset == 0 {
			return if (n == 0) Ok(0) else Err(Bad(at + coverage_field))
		}
		coverage_count = TableMath.check_coverage(data, at + offset, glyph_count)?
		if coverage_count != n {
			return Err(Bad(at + count_field))
		}
		var $steps = TableMath.spend(data, 0, n, at)?
		for i in 0..<n {
			r = first + 2 * i
			child = Bytes.u16(data, r)
			if child == 0 {
				return Err(Bad(r))
			}
			$steps = TableMath.check_construction(data, at + child, glyph_count, $steps, lv)?
		}
		Ok($steps)
	}

	check_construction : List(U8), U64, U64, U64, LayoutVar -> Try(U64, [Bad(U64)])
	check_construction = |data, at, glyph_count, steps, lv| {
		if !Bytes.fits(at, 4, data.len()) {
			return Err(Bad(at))
		}
		n = Bytes.u16(data, at + 2)
		if !Bytes.fits(at + 4, 4 * n, data.len()) {
			return Err(Bad(at))
		}
		var $spent = TableMath.spend(data, steps, n, at)?
		var $previous = 0
		for i in 0..<n {
			r = at + 4 + 4 * i
			advance = Bytes.u16(data, r + 2)
			if Bytes.u16(data, r) >= glyph_count {
				return Err(Bad(r))
			}
			if i > 0 and advance < $previous {
				return Err(Bad(r + 2))
			}
			$previous = advance
		}
		assembly_offset = Bytes.u16(data, at)
		if assembly_offset != 0 {
			base = at + assembly_offset
			if !Bytes.fits(base, 6, data.len()) {
				return Err(Bad(at))
			}
			count = Bytes.u16(data, base + 4)
			if !Bytes.fits(base + 6, 10 * count, data.len()) {
				return Err(Bad(base + 4))
			}
			$spent = TableMath.spend(data, $spent, count, base)?
			TableMath.check_value(data, base, base, lv)?
			for i in 0..<count {
				r = base + 6 + 10 * i
				if Bytes.u16(data, r) >= glyph_count {
					return Err(Bad(r))
				}
				# Connector lengths are font facts; the format does not bound
				# them by fullAdvance (real Noto parts exceed it).
				if Bytes.u16(data, r + 8) > 1 {
					return Err(Bad(r + 8))
				}
			}
		}
		Ok($spent)
	}
}

# Small original fixture table copied by tests/fonts/inline_tables.py.
# Its public answers belong in tests/api/MathTests.roc; these expects
# test private validation and relative error offsets.
math_fixture_bytes : List(U8)
math_fixture_bytes = [
	[0, 1, 0, 0, 0, 10, 0, 248, 1, 116, 0, 80, 0, 60, 0, 0],
	[0, 0, 0, 0, 0, 0, 0, 250, 0, 0, 0, 0, 0, 0, 0, 0],
	[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 40, 0, 214, 0, 0],
	[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	[0, 0, 0, 0, 0, 222, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	[0, 230, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 65],
	[0, 10, 0, 12, 0, 1, 196, 0, 0, 9, 0, 10, 0, 2, 227, 0],
	[0, 8, 0, 8, 0, 3, 248, 0, 0, 8, 0, 20, 0, 32, 0, 40],
	[0, 24, 0, 2, 0, 12, 0, 0, 255, 247, 0, 0, 0, 12, 0, 2],
	[0, 240, 0, 0, 0, 0, 0, 0, 0, 1, 0, 2, 0, 1, 0, 3],
	[0, 98, 0, 1, 0, 12, 0, 34, 0, 48, 0, 54, 0, 2, 255, 156],
	[0, 0, 0, 100, 0, 0, 0, 10, 0, 0, 0, 20, 0, 0, 0, 30],
	[0, 0, 0, 1, 0, 50, 0, 0, 255, 246, 0, 0, 0, 25, 0, 0],
	[0, 0, 0, 7, 0, 0, 0, 3, 255, 206, 0, 0, 0, 0, 0, 0],
	[0, 50, 0, 0, 255, 226, 0, 0, 255, 236, 0, 0, 255, 246, 0, 0],
	[0, 0, 0, 0, 0, 20, 0, 14, 0, 20, 0, 1, 0, 1, 0, 26],
	[0, 74, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 3, 0, 12],
	[0, 2, 0, 2, 2, 188, 0, 3, 4, 76, 0, 30, 0, 0, 0, 3],
	[0, 6, 0, 0, 0, 100, 1, 144, 0, 0, 0, 7, 0, 100, 0, 100],
	[0, 200, 0, 1, 0, 8, 0, 100, 0, 0, 1, 144, 0, 0, 0, 12],
	[0, 2, 0, 4, 3, 32, 0, 5, 4, 176, 0, 0, 0, 0, 0, 0],
].join_map(|row| row)

expect match TableMath.read(math_fixture_bytes, 16, LayoutVar.none(0)) {
	Ok(_) => True
	Err(_) => False
}
expect match TableMath.read([], 16, LayoutVar.none(0)) {
	Err(offsets) => offsets == [0]
	Ok(_) => False
}
expect match TableMath.read(math_fixture_bytes, 0, LayoutVar.none(0)) {
	Err(offsets) => offsets.len() >= 3
	Ok(_) => False
}
expect !TableMath.has_data(TableMath.none)

## fuzz regression: connector lengths may exceed fullAdvance. Noto Sans
## Math contains such parts; reading must expose them without repair.
expect {
	# Both fixture indices are proven in bounds.
	bytes = math_fixture_bytes.set(418, 127) ?? []
	changed = bytes.set(419, 255) ?? []
	match TableMath.read(changed, 16, LayoutVar.none(0)) {
		Ok(math) => match TableMath.assembly(math, 1, Vertical) {
			Present(a) => (a.parts.first() ?? { glyph: 0, start_connector: 0, end_connector: 0, full_advance: 0, extender: False }).start_connector == 32767
			Absent => False
		}
		Err(_) => False
	}
}

## fuzz regression: equal correction heights are preserved in table order.
## HarfBuzz's inclusive binary search selects the value after its first
## visited equal record, not after every equal record.
expect {
	# Both fixture indices are proven in bounds.
	bytes = math_fixture_bytes.set(306, 255) ?? []
	changed = bytes.set(307, 156) ?? []
	match TableMath.read(changed, 16, LayoutVar.none(0)) {
		Ok(math) => TableMath.kern(math, 1, TopRight, -100) == 20 and TableMath.kern(math, 1, TopRight, -99) == 30
		Err(_) => False
	}
}
