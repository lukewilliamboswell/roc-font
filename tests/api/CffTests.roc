import font.Font
import build.FontBuild
import "../fonts/cff/sans-cff1.otf" as sans_file : List(U8)
import "../fonts/cff/cid-cff1.otf" as cid_file : List(U8)
import "../fonts/cff/sans-cff2.otf" as sans_variable_file : List(U8)
import "../fonts/cff/serif-cff2.otf" as serif_variable_file : List(U8)
import "../fonts/cff/operators-cff1.otf" as operator_file : List(U8)
import "../fonts/cff/calculator-cff1.otf" as calculator_file : List(U8)

## A consumer can shape a CFF font and draw every returned glyph through
## the same public path API, including variable and CID-keyed outlines.
CffTests :: {}.{}

read = |bytes| match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
	Ok(font) => font
	Err(problems) => crash Str.inspect(problems)
}

finite_point = |point| point.x.is_finite() and point.y.is_finite() and point.x >= -1073741823 and point.x <= 1073741823 and point.y >= -1073741823 and point.y <= 1073741823

finite_command = |command| match command {
	MoveTo(point) | LineTo(point) => finite_point(point)
	QuadraticTo(curve) => finite_point(curve.control) and finite_point(curve.end)
	CubicTo(curve) => finite_point(curve.control1) and finite_point(curve.control2) and finite_point(curve.end)
	Close => True
}
expect [sans_file, cid_file, sans_variable_file, serif_variable_file].all(
	|bytes| {
		font = read(bytes)
		run = Font.shape(font, "Áa fi Ω漢", Font.ShapeOptions.{})
		!run.glyphs.is_empty() and run.glyphs.all(
			|glyph| match Font.outline(font, glyph) {
				Outline(commands) => commands.all(finite_command)
				Unknown => False
			},
		)
	},
)
expect [sans_file, cid_file, sans_variable_file, serif_variable_file].all(
	|bytes| {
		font = read(bytes)
		Font.outline(font, Font.glyph_count(font)) == Outline([]) and Font.outline(font, 0xFFFFFFFF) == Outline([]) and Font.extents(font, 0xFFFFFFFF) == Empty
	},
)
expect {
	font = read(operator_file)
	Font.outline(font, 0) == Outline([]) and Font.outline(font, 1) == Outline([]) and Font.extents(font, 0) == Empty
}
expect {
	# A contour with only a move is retained, while its ink is empty.
	font = read(operator_file)
	Font.outline(font, 22) == Outline([MoveTo({ x: 10, y: 20 }), Close]) and Font.extents(font, 22) == Empty
}
expect {
	font = read(operator_file)
	Font.outline(font, 21) == Outline([MoveTo({ x: 10, y: 20 }), LineTo({ x: 35, y: 55 }), LineTo({ x: 80, y: 110 }), Close])
}
expect {
	# Deprecated endchar seac resolves StandardEncoding base/accent names
	# through the font's charset, retaining its accent translation.
	font = read(operator_file)
	Font.outline(font, 4) == Outline([MoveTo({ x: 10, y: 20 }), LineTo({ x: 110, y: 20 }), LineTo({ x: 110, y: 120 }), LineTo({ x: 10, y: 120 }), Close, MoveTo({ x: 20, y: 200 }), LineTo({ x: 50, y: 250 }), Close])
}
expect {
	# CharString widths and hints do not replace hmtx advances.
	font = read(operator_file)
	Font.advance(font, 20) == 600 and Font.outline(font, 20) == Outline([MoveTo({ x: 10, y: 20 }), LineTo({ x: 60, y: 70 }), Close])
}
expect {
	font = read(serif_variable_file)
	a = Font.at(font, Font.Variation.{ axes: [{ tag: "wght", value: 900 }, { tag: "opsz", value: 60 }] })
	b = Font.at(font, Font.Variation.{ axes: [{ tag: "wght", value: 200 }, { tag: "opsz", value: 8 }] })
	Font.outline(a, 2) != Font.outline(b, 2) and Font.outline(a, 2) == Font.outline(a, 2)
}
expect {
	font = read(calculator_file)
	Font.outline(font, 23) == Outline([MoveTo({ x: 10, y: 20 }), LineTo({ x: 20, y: 40 }), Close]) and Font.outline(font, 34) == Outline([MoveTo({ x: 10, y: 20 }), LineTo({ x: 17, y: 40 }), Close])
}
expect {
	# FreeType2.13.2's documented seeded stream, evaluated in F64. Every
	# query starts the font's initialRandomSeed12345; call order is irrelevant.
	font = read(calculator_file)
	before = Font.outline(font, 39)
	_ = Font.outline(font, 21)
	before == Outline([MoveTo({ x: 10, y: 20 }), LineTo({ x: 198.385009765625, y: 70 }), LineTo({ x: 653.3868408203125, y: 120 }), LineTo({ x: 691.2286376953125, y: 170 }), Close]) and before == Font.outline(font, 39)
}
expect {
	# Both independent malformed required CFF tables are reported.
	file = FontBuild.file(FontBuild.replace(FontBuild.replace(FontBuild.basic, "CFF ", [1]), "CFF2", [2]))
	match Font.from_bytes(file, Font.ReadOptions.{}) {
		Err(problems) => ["CFF ", "CFF2"].all(
			|tag| problems.any(
				|problem| match problem {
					BadTable({ table, .. }) => table == tag
					_ => False
				},
			),
		)
		Ok(_) => False
	}
}
