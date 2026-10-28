app [target] {
	build: "../tests/support/main.roc",
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}
import font.Font
import fuzz.Fuzz
import build.FontBuild
import "../tests/fonts/outlines-carets/outlines-carets.ttf" as fixture : List(U8)

## Paths and ligature carets: hostile seeded bytes, variable locations,
## deterministic bounded paths with finite fractional coordinates, and
## unavailable point carets preserving table cardinality. The narrow
## generated feature has32,128,512 contour points and explicit carets;
## allocations must scale linearly and every query must release its data.
finite = |p| p.x >= -2535301200456458802993406410752.F64 and p.x <= 2535301200456458802993406410752.F64 and p.y >= -2535301200456458802993406410752.F64 and p.y <= 2535301200456458802993406410752.F64

finite_command = |c| match c {
	MoveTo(p) => finite(p)
	LineTo(p) => finite(p)
	QuadraticTo(q) => finite(q.control) and finite(q.end)
	CubicTo(q) => finite(q.control1) and finite(q.control2) and finite(q.end)
	Close => True
}

recipe = |n, bytes| {
	points = FontBuild.counting(n).map(|i| { x: i.to_i64_wrap(), y: (bytes.get(i % bytes.len().max(1)) ?? 0).to_i64() - 128, on: i % 3 != 1 })
	glyph = FontBuild.simple_glyph([points])
	values = FontBuild.counting(n).map(|i| Ref(FontBuild.pack([U16(1), I16(i.to_i64_wrap())])))
	lig = FontBuild.pack([U16(n)].concat(values))
	carets = FontBuild.pack([Ref(FontBuild.coverage1([1])), U16(1), Ref(lig)])
	gdef = FontBuild.pack([U32(0x10000), U16(0), U16(0), Ref(carets), U16(0)])
	cmap = FontBuild.cmap([{ system: 3, encoding: 1, subtable: FontBuild.cmap4([{ first: 65, last: 65, delta: 65472, glyphs: [] }]) }])
	FontBuild.outline_font([[], glyph], [500, 600], [0, 0], 2, True, cmap, [{ tag: "GDEF", data: gdef }])
}

query = |font| match Font.outline(font, 1) {
	Outline(path) => path.len() + Font.ligature_carets(font, 1).len()
	Unknown => crash "generated outline unavailable"
}

test! = |bytes| {
	var $last_allocations = 0.U64
	for n in [32.U64, 128, 512] {
		file = recipe(n, bytes)
		font = match Font.from_bytes(file, Font.ReadOptions.{ strict: True }) {
			Ok(f) => f
			Err(problems) => crash Str.inspect(problems)
		}
		carets = Font.ligature_carets(font, 1)
		if carets.len() != n or !carets.map_with_index(|position, i| position == Position(i.to_f64())).all(|ok| ok) {
			crash "caret index alignment"
		}
		match Font.outline(font, 1) {
			Outline(path) => {
				if path.len() > 3 * n or !path.all(finite_command) {
					crash "path bounds"
				}
			}
			Unknown => crash "outline missing"
		}
		measured = Fuzz.measure_allocs!(|{}| query(font))
		Fuzz.expect_no_leaks!(|{}| query(font))
		if n > 32 and measured.allocations > 8 * $last_allocations + 64 {
			crash "outline/caret allocation scaling"
		}
		$last_allocations = measured.allocations
	}
	seed = match (bytes.first() ?? 0) % 4 {
		0 => fixture
		1 => Font.sans_bytes
		2 => Font.serif_bytes
		_ => Font.mono_bytes
	}
	mutated = if bytes.len() > 3 {
		seed.set((((bytes.get(1) ?? 0).to_u64() * 256) + (bytes.get(2) ?? 0).to_u64()) % seed.len(), bytes.get(3) ?? 0) ?? []
	} else {
		seed
	}
	match Font.from_bytes(mutated, Font.ReadOptions.{}) {
		Err(problems) => match Font.from_bytes(mutated, Font.ReadOptions.{}) {
			Err(again) => {
				if problems != again {
					crash "reading is not deterministic"
				}
			}
			Ok(_) => crash "reading changed"
		}
		Ok(font) => {
			moved = Font.at(font, Font.Variation.{ weight: Weight(100 + (bytes.get(4) ?? 0).to_u16() * 3) })
			glyph = (bytes.get(5) ?? 1).to_u32()
			a = Font.outline(moved, glyph)
			if a != Font.outline(moved, glyph) {
				crash "outline nondeterministic"
			}
			match a {
				Outline(path) => {
					if path.len() > 600000 or !path.all(finite_command) {
						crash "unbounded/nonfinite path"
					}
				}
				Unknown => {}
			}
			if Font.ligature_carets(moved, glyph) != Font.ligature_carets(moved, glyph) {
				crash "caret nondeterministic"
			}
			Fuzz.expect_no_leaks!(
				|{}| match Font.outline(moved, glyph) {
					Outline(path) => path.len()
					Unknown => 0
				},
			)
		}
	}
	Fuzz.keep
}

target = Fuzz.target_with!({ name: "font-outlines", generator: Fuzz.raw_bytes, test!, show: |bytes| Str.inspect(bytes.take_first(16)) })
