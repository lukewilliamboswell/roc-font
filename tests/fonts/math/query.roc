app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	font: "../../../package/main.roc",
}

import cli.OsStr
import cli.Path
import cli.Stdin
import cli.Stdout
import font.Font

# Dedicated MATH conformance driver. Each request is case id, font path,
# and weight (tab separated). Emits canonical font facts, never pixels.
# verify.py builds it against the served bundle and compares cached oracles.
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	input = Str.from_utf8_lossy(Stdin.read_to_end!()?)
	for line in input.split_on("\n") {
		if !line.is_empty() {
			match line.split_on("\t") {
				[tag, path, weight_text] => {
					bytes = Path.read_bytes!(Path.utf8(path))?
					read = match Font.from_bytes(bytes, Font.ReadOptions.{}) {
						Ok(font) => font
						Err(problems) => crash Str.inspect(problems)
					}
					weight = U16.from_str(weight_text) ?? 400
					font = Font.at(read, Font.Variation.{ weight: Weight(weight) })
					for fact in facts(font) {
						Stdout.line!("${tag}\t${fact}")?
					}
				}
				_ => crash "MATH driver request needs id, path and weight"
			}
		}
	}
	Ok({})
}

optional : [Present(I64), Absent] -> Str
optional = |value| match value {
	Present(n) => n.to_str()
	Absent => "_"
}

numbers : List(I64) -> Str
numbers = |values| Str.join_with(values.map(|n| n.to_str()), ",")

constants_values : Font.MathConstants -> List(I64)
constants_values = |c| [
	c.script_percent_scale_down.to_i64(),
	c.script_script_percent_scale_down.to_i64(),
	c.delimited_sub_formula_min_height.to_i64(),
	c.display_operator_min_height.to_i64(),
	c.math_leading,
	c.axis_height,
	c.accent_base_height,
	c.flattened_accent_base_height,
	c.subscript_shift_down,
	c.subscript_top_max,
	c.subscript_baseline_drop_min,
	c.superscript_shift_up,
	c.superscript_shift_up_cramped,
	c.superscript_bottom_min,
	c.superscript_baseline_drop_max,
	c.sub_superscript_gap_min,
	c.superscript_bottom_max_with_subscript,
	c.space_after_script,
	c.upper_limit_gap_min,
	c.upper_limit_baseline_rise_min,
	c.lower_limit_gap_min,
	c.lower_limit_baseline_drop_min,
	c.stack_top_shift_up,
	c.stack_top_display_style_shift_up,
	c.stack_bottom_shift_down,
	c.stack_bottom_display_style_shift_down,
	c.stack_gap_min,
	c.stack_display_style_gap_min,
	c.stretch_stack_top_shift_up,
	c.stretch_stack_bottom_shift_down,
	c.stretch_stack_gap_above_min,
	c.stretch_stack_gap_below_min,
	c.fraction_numerator_shift_up,
	c.fraction_numerator_display_style_shift_up,
	c.fraction_denominator_shift_down,
	c.fraction_denominator_display_style_shift_down,
	c.fraction_numerator_gap_min,
	c.fraction_num_display_style_gap_min,
	c.fraction_rule_thickness,
	c.fraction_denominator_gap_min,
	c.fraction_denom_display_style_gap_min,
	c.skewed_fraction_horizontal_gap,
	c.skewed_fraction_vertical_gap,
	c.overbar_vertical_gap,
	c.overbar_rule_thickness,
	c.overbar_extra_ascender,
	c.underbar_vertical_gap,
	c.underbar_rule_thickness,
	c.underbar_extra_descender,
	c.radical_vertical_gap,
	c.radical_display_style_vertical_gap,
	c.radical_rule_thickness,
	c.radical_extra_ascender,
	c.radical_kern_before_degree,
	c.radical_kern_after_degree,
	c.radical_degree_bottom_raise_percent.to_i64(),
]

facts : Font -> List(Str)
facts = |font| {
	constants = match Font.math_constants(font) {
		Present(c) => constants_values(c)
		Absent => []
	}
	var $out = ["constants|${numbers(constants)}", "overlap|${Font.math_min_connector_overlap(font).to_str()}"]
	for glyph in 0..<Font.glyph_count(font).to_u64() {
		g = glyph.to_u32_wrap()
		italic = optional(Font.math_italic_correction(font, g))
		accent = optional(Font.math_top_accent_attachment(font, g))
		extended = if (Font.math_extended_shape(font, g)) "1" else "0"
		$out = $out.append("glyph|${glyph.to_str()}|${italic}|${accent}|${extended}")
		for (corner, index) in [(TopRight, 0.U64), (TopLeft, 1), (BottomRight, 2), (BottomLeft, 3)] {
			table = Font.math_kern_table(font, g, corner)
			if !table.values.is_empty() {
				$out = $out.append("kern-table|${glyph.to_str()}|${index.to_str()}|${numbers(table.heights)}|${numbers(table.values)}")
				# These original and real fonts have ordered heights at every case's
				# selected location. Only this finite list, not font data, is sorted.
				candidates = [-2147483648.I64, 0, 2147483647].concat(table.heights.join_map(|h| [h - 1, h, h + 1]))
				ordered = candidates.sort_with(
					|a, b| if a < b {
						Before
					} else if a > b {
						After
					} else {
						Same
					},
				)
				var $previous = 0.I64
				var $first = True
				for h in ordered {
					if $first or h.to_i64() != $previous {
						$out = $out.append("kern|${glyph.to_str()}|${index.to_str()}|${h.to_str()}|${Font.math_kern(font, g, corner, h).to_str()}")
						$previous = h.to_i64()
						$first = False
					}
				}
			}
		}
		for (axis, index) in [(Vertical, 0.U64), (Horizontal, 1)] {
			variants = Font.math_variants(font, g, axis)
			if !variants.is_empty() {
				text = Str.join_with(variants.map(|v| "${v.glyph.to_str()}:${v.advance.to_str()}"), ",")
				$out = $out.append("variants|${glyph.to_str()}|${index.to_str()}|${text}")
			}
			match Font.math_assembly(font, g, axis) {
				Present(a) => {
					parts = Str.join_with(
						a.parts.map(
							|p| {
								flag = if (p.extender) "1" else "0"
								"${p.glyph.to_str()}:${p.start_connector.to_str()}:${p.end_connector.to_str()}:${p.full_advance.to_str()}:${flag}"
							},
						),
						",",
					)
					$out = $out.append("assembly|${glyph.to_str()}|${index.to_str()}|${a.italic_correction.to_str()}|${parts}")
				}
				Absent => {}
			}
		}
	}
	$out
}
