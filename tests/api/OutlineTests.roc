import font.Font
import build.FontBuild
import "../fonts/outlines-carets/outlines-carets.ttf" as fixture : List(U8)
import "../fonts/variable/var-outlines.ttf" as varied_fixture : List(U8)

## Public outline contract; oracle data and provenance live beside the
## fixture. Close supplies the final straight segment, so redundant
## HarfBuzz closing LineTo commands are deliberately omitted.
OutlineTests :: {}.{}

read_or_crash = |bytes| match Font.from_bytes(bytes, Font.ReadOptions.{}) {
	Ok(font) => font
	Err(problems) => crash Str.inspect(problems)
}

font : Font
font = read_or_crash(fixture)

expect Font.outline(font, 1) == Outline([MoveTo({ x: 100, y: 0 }), LineTo({ x: 500, y: 0 }), LineTo({ x: 500, y: 700 }), LineTo({ x: 100, y: 700 }), Close])
expect Font.outline(font, 2) == Outline([MoveTo({ x: 0, y: 0 }), QuadraticTo({ control: { x: 100, y: 200 }, end: { x: 200, y: 200 } }), QuadraticTo({ control: { x: 300, y: 200 }, end: { x: 400, y: 0 } }), Close])
# A contour with no explicit on-curve point starts at the midpoint of its
# last and first control points; every adjacent pair implies a midpoint.
expect Font.outline(font, 3) == Outline([MoveTo({ x: 50, y: 50 }), QuadraticTo({ control: { x: 0, y: 100 }, end: { x: 50, y: 150 } }), QuadraticTo({ control: { x: 100, y: 200 }, end: { x: 150, y: 150 } }), QuadraticTo({ control: { x: 200, y: 100 }, end: { x: 150, y: 50 } }), QuadraticTo({ control: { x: 100, y: 0 }, end: { x: 50, y: 50 } }), Close])
expect Font.outline(font, 0) == Outline([]) and Font.outline(font, 100000) == Outline([])
expect match Font.from_bytes(FontBuild.file(FontBuild.basic), Font.ReadOptions.{}) {
	Ok(metrics_only) => Font.outline(metrics_only, 1) == Unknown
	Err(_) => False
}

# Fractional coordinates after a scaled composite remain fractional font
# units, and all varied phantom shifts are applied to the returned path.
expect {
	varied = read_or_crash(varied_fixture)
	heavy = Font.at(varied, Font.Variation.{ weight: Black })
	Font.outline(heavy, 1) == Outline([MoveTo({ x: 105, y: 0 }), LineTo({ x: 475, y: 0 }), LineTo({ x: 525, y: 740 }), LineTo({ x: 95, y: 740 }), Close])
}
expect {
	varied = read_or_crash(varied_fixture)
	regular = Font.outline(varied, 3)
	regular != Font.outline(Font.at(varied, Font.Variation.{ weight: Black }), 3)
}

# Real built-in fonts: every mapped glyph path is deterministic and all
# coordinate values are finite. This includes composites and true curves.
finite = |p| p.x >= -1267650600228229401496703205376.F64 and p.x <= 1267650600228229401496703205376.F64 and p.y >= -1267650600228229401496703205376.F64 and p.y <= 1267650600228229401496703205376.F64

finite_command = |command| match command {
	MoveTo(p) => finite(p)
	LineTo(p) => finite(p)
	QuadraticTo(q) => finite(q.control) and finite(q.end)
	CubicTo(c) => finite(c.control1) and finite(c.control2) and finite(c.end)
	Close => True
}
expect [Font.sans, Font.serif, Font.mono].all(
	|built_in| {
		["A", "é", "Å", "g", "∫"].all(
			|text| {
				run = Font.shape(built_in, text, Font.ShapeOptions.{})
				run.glyphs.all(
					|glyph| match Font.outline(built_in, glyph) {
						Outline(path) => path.all(finite_command) and Font.outline(built_in, glyph) == Outline(path)
						Unknown => False
					},
				)
			},
		)
	},
)

import "../fonts/outlines-carets/numeric-overflow.ttf" as overflow_fixture : List(U8)
import "../fonts/outlines-carets/deep-identity.ttf" as deep_fixture : List(U8)

# A bounded one-child chain may still overflow binary32. Reject its
# conservative numeric envelope during reading, without reducing the
# permitted depth of an ordinary identity-transform chain.
expect match Font.from_bytes(overflow_fixture, Font.ReadOptions.{}) {
	Err(problems) => problems.any(
		|problem| match problem {
			BadTable({ table, .. }) => table == "glyf"
			_ => False
		},
	)
	Ok(_) => False
}
expect match Font.from_bytes(deep_fixture, Font.ReadOptions.{}) {
	Ok(deep) => match Font.outline(deep, 64) {
		Outline(path) => !path.is_empty() and path.all(finite_command)
		Unknown => False
	}
	Err(_) => False
}
