import font.Font
import build.FontBuild
import "../../tests/fonts/math/math.ttf" as math_file : List(U8)
import "../../tests/fonts/math/math-variable.ttf" as variable_file : List(U8)
import "../../tests/fonts/math/math-empty.ttf" as empty_file : List(U8)
import "../../tests/fonts/math/NotoSansMath-Regular.ttf" as noto_file : List(U8)

## Public MATH font facts. Constants, corrections, all corners and stretch
## recipes are checked against HarfBuzz 14.6.0/fontTools 4.61.1 records by
## tests/fonts/math/verify.py. These expects cover public absence, location
## behavior, strict/lenient policy, hostile offsets and aggregated problems.
MathTests :: {}.{}

read : List(U8) -> Font
read = |bytes| match Font.from_bytes(bytes, Font.ReadOptions.{}) {
	Ok(font) => font
	Err(ps) => crash Str.inspect(ps)
}

math_font : Font
math_font = read(math_file)

expect Font.has_math(math_font)
expect match Font.math_constants(math_font) {
	Present(c) => c.script_percent_scale_down == 80 and c.script_script_percent_scale_down == 60 and c.axis_height == 250 and c.fraction_rule_thickness == 40 and c.radical_degree_bottom_raise_percent == 65
	Absent => False
}
expect Font.math_italic_correction(math_font, 1) == Present(12)
expect Font.math_italic_correction(math_font, 3) == Present(-9)
expect Font.math_italic_correction(math_font, 2) == Absent
expect Font.math_top_accent_attachment(math_font, 1) == Present(240)
expect Font.math_top_accent_attachment(math_font, 3) == Present(0)
expect Font.math_top_accent_attachment(math_font, 2) == Absent
expect Font.math_extended_shape(math_font, 1) and Font.math_extended_shape(math_font, 3) and !Font.math_extended_shape(math_font, 2)
expect Font.math_kern_table(math_font, 1, TopRight) == { heights: [-100, 100], values: [10, 20, 30] }
expect [-101, -100, -99, 99, 100, 101].map(|h| Font.math_kern(math_font, 1, TopRight, h)) == [10, 20, 20, 20, 30, 30]
expect Font.math_kern_table(math_font, 1, TopLeft) == { heights: [50], values: [-10, 25] }
expect Font.math_kern_table(math_font, 1, BottomRight) == { heights: [], values: [7] }
expect Font.math_kern(math_font, 1, BottomRight, -2147483648) == 7 and Font.math_kern(math_font, 1, BottomRight, 2147483647) == 7
expect Font.math_kern_table(math_font, 1, BottomLeft) == { heights: [-50, 0, 50], values: [-30, -20, -10, 0] }
expect Font.math_variants(math_font, 1, Vertical) == [{ glyph: 2, advance: 700 }, { glyph: 3, advance: 1100 }]
expect Font.math_variants(math_font, 3, Horizontal) == [{ glyph: 4, advance: 800 }, { glyph: 5, advance: 1200 }]
expect Font.math_variants(math_font, 1, Horizontal).is_empty()
expect Font.math_min_connector_overlap(math_font) == 20
expect Font.math_assembly(math_font, 1, Vertical) == Present({
	italic_correction: 30,
	parts: [
		{ glyph: 6, start_connector: 0, end_connector: 100, full_advance: 400, extender: False },
		{ glyph: 7, start_connector: 100, end_connector: 100, full_advance: 200, extender: True },
		{ glyph: 8, start_connector: 100, end_connector: 0, full_advance: 400, extender: False },
	],
})
# Empty assembly is present, distinct from no construction recipe.
expect Font.math_assembly(math_font, 3, Horizontal) == Present({ italic_correction: 0, parts: [] })
expect Font.math_assembly(math_font, 2, Vertical) == Absent

expect {
	empty = read(empty_file)
	!Font.has_math(Font.sans) and Font.math_constants(Font.sans) == Absent and Font.has_math(empty) and (
		match Font.math_constants(empty) {
			Present(c) => c.axis_height == 250
			Absent => False
		}
	)
}
expect {
	empty = read(empty_file)
	Font.math_variants(empty, 1, Vertical).is_empty() and Font.math_assembly(empty, 1, Vertical) == Absent and Font.math_italic_correction(empty, 1) == Absent
}
expect [Font.sans, math_font, read(empty_file)].all(
	|font| [16.U32, 65535, 4294967295].all(
		|g| {
			Font.math_italic_correction(font, g) == Absent and Font.math_top_accent_attachment(font, g) == Absent and !Font.math_extended_shape(font, g) and Font.math_kern(font, g, TopRight, 0) == 0 and Font.math_kern_table(font, g, TopLeft) == { heights: [], values: [] } and Font.math_variants(font, g, Vertical).is_empty() and Font.math_assembly(font, g, Horizontal) == Absent
		},
	),
)

# Variation devices use GDEF, without pixel devices affecting font units.
# HarfBuzz 14.6 ignores MATH VariationIndex devices; these variable answers
# use the independent fontTools materialization oracle (oracle.jsonl).
expect {
	base = read(variable_file)
	half = Font.at(base, Font.Variation.{ weight: Weight(650) })
	full = Font.at(base, Font.Variation.{ weight: Black })
	(
		match (Font.math_constants(base), Font.math_constants(half), Font.math_constants(full)) {
			(Present(a), Present(b), Present(c)) => a.axis_height == 250 and b.axis_height == 300 and c.axis_height == 350 and c.fraction_rule_thickness == 40
			_ => False
		}
	) and Font.math_italic_correction(half, 1) == Present(22) and Font.math_italic_correction(full, 1) == Present(32) and Font.math_top_accent_attachment(full, 1) == Present(200) and Font.math_kern_table(full, 1, TopRight) == { heights: [-100, 125], values: [40, 20, 30] } and (
		match Font.math_assembly(full, 1, Vertical) {
			Present(a) => a.italic_correction == 80
			Absent => False
		}
	) and Font.math_italic_correction(Font.at(full, Font.Variation.{}), 1) == Present(12)
}

# Real unmodified TrueType MATH font: no CFF prerequisite for these facts.
expect {
	noto = read(noto_file)
	glyph = Font.glyph(noto, 0x28) ?? 0
	Font.has_math(noto) and Font.math_variants(noto, glyph, Vertical).len() == 13 and (
		match Font.math_assembly(noto, glyph, Vertical) {
			Present(a) => !a.parts.is_empty()
			Absent => False
		}
	)
}

# Locate a table in a test font without importing package internals.
be : List(U8), U64 -> U64
be = |bytes, at| (bytes.get(at) ?? 0).to_u64() * 256 + (bytes.get(at + 1) ?? 0).to_u64()

math_bytes : List(U8)
math_bytes = {
	var $out = []
	for i in 0..<be(math_file, 4) {
		at = 12 + 16 * i
		if math_file.sublist({ start: at, len: 4 }) == "MATH".to_utf8() {
			start = be(math_file, at + 8) * 65536 + be(math_file, at + 10)
			length = be(math_file, at + 12) * 65536 + be(math_file, at + 14)
			$out = math_file.sublist({ start, len: length })
		}
	}
	$out
}

# Every malformed optional MATH is dropped in lenient mode, never repaired.
# Strict mode rejects it, and the original table is still usable.
broken : List(U8) -> Bool
broken = |table| {
	bytes = FontBuild.parity_font([{ tag: "MATH", data: table }])
	match (Font.from_bytes(bytes, Font.ReadOptions.{}), Font.from_bytes(bytes, Font.ReadOptions.{ strict: True })) {
		(Ok(font), Err(ps)) => !Font.has_math(font) and !ps.is_empty() and !Font.dropped(font).is_empty() and Font.dropped(font).all(
			|p| match p {
				BadTable(b) => b.table == "MATH"
				_ => False
			},
		)
		_ => False
	}
}

expect [1.U64, 9, 10, 100, 223].all(|n| broken(math_bytes.take_first(n)))
expect broken(FontBuild.patch(math_bytes, 0, [0, 2]))
expect broken(FontBuild.patch(math_bytes, 4, [255, 255]))
expect broken(FontBuild.patch(math_bytes, 6, [255, 255]))
expect broken(FontBuild.patch(math_bytes, 8, [255, 255]))
expect {
	table = FontBuild.patch(FontBuild.patch(FontBuild.patch(math_bytes, 4, [255, 255]), 6, [255, 255]), 8, [255, 255])
	match Font.from_bytes(FontBuild.parity_font([{ tag: "MATH", data: table }]), Font.ReadOptions.{}) {
		Ok(font) => Font.dropped(font).len() == 3
		Err(_) => False
	}
}
# Variant glyph past the font; the format's reference is never clamped.
expect {
	variants = be(math_bytes, 8)
	construction = variants + be(math_bytes, variants + 10)
	broken(FontBuild.patch(math_bytes, construction + 4, [255, 255]))
}
# Truncated device payload is invalid even though ppem is zero.
expect {
	constants = be(math_bytes, 4)
	record = constants + 8 + 4 * 34
	device = math_bytes.len()
	table = FontBuild.patch(math_bytes.concat([0, 10, 0, 10, 0, 1]), record + 2, FontBuild.u16(device - constants))
	broken(table)
}

# Counts and sorted coverage indexes must agree before a query can use them.
expect {
	info = be(math_bytes, 6)
	italic = info + be(math_bytes, info)
	broken(FontBuild.patch(math_bytes, italic + 2, [0, 1]))
}
expect {
	info = be(math_bytes, 6)
	italic = info + be(math_bytes, info)
	coverage = italic + be(math_bytes, italic)
	# This fixture's correction coverage is format 1 with glyphs 1 and 3.
	broken(FontBuild.patch(math_bytes, coverage + 6, [0, 1]))
}
# All branches of the device format are checked, even at zero ppem.
expect {
	constants = be(math_bytes, 4)
	record = constants + 8 + 4 * 34
	device = constants + be(math_bytes, record + 2)
	broken(FontBuild.patch(math_bytes, device + 4, [0, 4]))
}
# A variation device with no GDEF row is invalid; the format's explicit
# no-variation sentinel is valid and contributes exactly zero.
expect {
	constants = be(math_bytes, 4)
	record = constants + 8 + 4 * 34
	target = math_bytes.len()
	with_device = |data| FontBuild.patch(math_bytes.concat(data), record + 2, FontBuild.u16(target - constants))
	invalid = with_device([0, 0, 0, 0, 128, 0])
	sentinel = with_device([255, 255, 255, 255, 128, 0])
	broken(invalid) and (
		match Font.from_bytes(FontBuild.parity_font([{ tag: "MATH", data: sentinel }]), Font.ReadOptions.{ strict: True }) {
			Ok(font) => match Font.math_constants(font) {
				Present(c) => c.fraction_rule_thickness == 40
				Absent => False
			}
			Err(_) => False
		}
	)
}

# An empty table directory entry is a structural font error, before the
# optional MATH policy is applied.
expect {
	bytes = FontBuild.parity_font([{ tag: "MATH", data: [] }])
	match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
		Ok(_) => False
		Err(problems) => problems.any(
			|p| match p {
				BadTable(b) => b.table == "MATH"
				_ => False
			},
		)
	}
}

# Equal correction heights preserve table order and HarfBuzz's first
# visited binary-search tie, rather than upper_bound over all equal values.
expect Font.math_kern_table(math_font, 3, TopRight) == { heights: [0, 0, 100, 100], values: [1, 2, 3, 4, 5] }
expect [-1.I32, 0, 1, 99, 100, 101].map(|h| Font.math_kern(math_font, 3, TopRight, h)) == [1, 3, 3, 3, 4, 5]
expect {
	full = Font.at(read(variable_file), Font.Variation.{ weight: Black })
	Font.math_kern_table(full, 3, TopRight) == { heights: [0, 25, 100, 100], values: [1, 2, 3, 4, 5] } and Font.math_kern(full, 3, TopRight, 0) == 2 and Font.math_kern(full, 3, TopRight, 100) == 4
}

# Mathematical leaf shaping uses the existing public feature controls.
# Direct HarfBuzz14.6/uharfbuzz0.56.3 results for this pinned Noto font:
# mathematical italic x is1056, scriptstyle1240, scriptscriptstyle1300.
expect {
	noto = read(noto_file)
	ordinary = Font.shape(noto, "𝑥", Font.ShapeOptions.{ script: "Zmth" })
	script = Font.shape(noto, "𝑥", Font.ShapeOptions.{ script: "Zmth", features: [Font.Feature.{ tag: "ssty", value: 1 }] })
	script_script = Font.shape(noto, "𝑥", Font.ShapeOptions.{ script: "Zmth", features: [Font.Feature.{ tag: "ssty", value: 2 }] })
	ordinary.glyphs == [1056] and script.glyphs == [1240] and script_script.glyphs == [1300]
}
