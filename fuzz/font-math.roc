app [target] {
	build: "../tests/support/main.roc",
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}

import "../tests/fonts/math/math-precise-variable.ttf" as precise_file : List(U8)
import "../tests/fonts/math/math-constant-variable.ttf" as constant_file : List(U8)
import fuzz.Fuzz
import font.Font
import build.FontBuild
import "../tests/fonts/math/NotoSansMath-Regular.ttf" as noto_file : List(U8)
import "../tests/fonts/math/math-variable.ttf" as variable_file : List(U8)

## Narrow MATH target: generated fonts at 8, 64 and 256 covered glyphs
## have only constants, corrections, accents, corner kern tables, coverage
## formats 1/2, extended shapes and glyph constructions. Other font facts
## stay fixed. Reading allocations grow linearly; querying one glyph is
## constant in font size. Query lists are finite, input-aligned where the
## format defines order, and deterministic. Corrupted real-font seeds and
## arbitrary inputs must either report problems or retain total queries.
## No equation layout, text shaping, rasterization or system fonts.
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	choice = (bytes.first() ?? 0).to_u64()
	delta = (bytes.get(1) ?? 0).to_i64() - 128
	small_bytes = generated(8, choice, delta)
	middle_bytes = generated(64, choice, delta)
	large_bytes = generated(256, choice, delta)
	small = check_generated(small_bytes, 8, delta)
	middle = check_generated(middle_bytes, 64, delta)
	large = check_generated(large_bytes, 256, delta)
	a = Fuzz.measure_allocs!(|{}| Font.from_bytes(small_bytes, Font.ReadOptions.{}))
	b = Fuzz.measure_allocs!(|{}| Font.from_bytes(middle_bytes, Font.ReadOptions.{}))
	c = Fuzz.measure_allocs!(|{}| Font.from_bytes(large_bytes, Font.ReadOptions.{}))
	if b.allocations > 10 * a.allocations + 128 or c.allocations > 5 * b.allocations + 128 {
		crash "MATH reading allocations grew faster than the generated table sizes"
	}
	qa = Fuzz.measure_allocs!(|{}| query(small, 1))
	qb = Fuzz.measure_allocs!(|{}| query(middle, 1))
	qc = Fuzz.measure_allocs!(|{}| query(large, 1))
	if qb.allocations > qa.allocations + 2 or qc.allocations > qa.allocations + 2 {
		crash "one MATH glyph query allocates with unrelated glyph count"
	}
	Fuzz.expect_no_leaks!(|{}| Font.from_bytes(large_bytes, Font.ReadOptions.{}))
	Fuzz.expect_no_leaks!(|{}| query(large, 1))
	candidate = if bytes.take_first(4) == [0, 1, 0, 0] or bytes.take_first(4) == "OTTO".to_utf8() or bytes.take_first(4) == "ttcf".to_utf8() {
		bytes
	} else match choice % 6 {
		0 => FontBuild.mutate(noto_file, bytes.drop_first(1))
		1 => FontBuild.mutate(variable_file, bytes.drop_first(1))
		2 => FontBuild.mutate(precise_file, bytes.drop_first(1))
		3 => FontBuild.mutate(constant_file, bytes.drop_first(1))
		4 => FontBuild.mutate(large_bytes, bytes.drop_first(1))
		_ => bytes
	}
	match Font.from_bytes(candidate, Font.ReadOptions.{}) {
		Ok(font) => {
			again = match Font.from_bytes(candidate, Font.ReadOptions.{}) {
				Ok(ready) => ready
				Err(_) => crash "reading the same bytes changed its result"
			}
			for weight in [100.U16, 400, 650, 900] {
				moved = Font.at(font, Font.Variation.{ weight: Weight(weight) })
				repeated = Font.at(again, Font.Variation.{ weight: Weight(weight) })
				for glyph in [0.U32, 1, 3, 7, Font.glyph_count(font), 4294967295] {
					observed = query(moved, glyph)
					if observed != query(repeated, glyph) {
						crash "MATH query is nondeterministic across independent reads"
					}
					if observed.variants.len() > 65535 or observed.tables.any(|t| t.heights.len() > 65535 or t.values.len() > 65536) {
						crash "MATH output escaped its checked counts"
					}
					match observed.assembly {
						Present(assembly) if assembly.parts.len() > 65535 => crash "MATH assembly escaped its checked count"
						_ => {}
					}
				}
			}
			for value in [0.Dec, 1, 256, 16384] {
				settings = Font.Variation.{ axes: [{ tag: "wght", value }, { tag: "AX02", value }, { tag: "AX03", value }] }
				a = Font.at(font, settings)
				b = Font.at(again, settings)
				if query(a, 1) != query(b, 1) {
					crash "precise/default MATH location is nondeterministic"
				}
			}
		}
		Err(_) => {}
	}
	Fuzz.keep
}

query : Font, U32 -> { constants : [Present(Font.MathConstants), Absent], italic : [Present(I64), Absent], accent : [Present(I64), Absent], extended : Bool, kern : List(I64), tables : List(Font.MathKernTable), variants : List(Font.MathVariant), assembly : [Present(Font.MathAssembly), Absent] }
query = |font, g| {
	constants: Font.math_constants(font),
	italic: Font.math_italic_correction(font, g),
	accent: Font.math_top_accent_attachment(font, g),
	extended: Font.math_extended_shape(font, g),
	kern: [TopRight, TopLeft, BottomRight, BottomLeft].join_map(|corner| [-2147483648.I64, -100, 0, 100, 2147483647].map(|height| Font.math_kern(font, g, corner, height))),
	tables: [TopRight, TopLeft, BottomRight, BottomLeft].map(|corner| Font.math_kern_table(font, g, corner)),
	variants: Font.math_variants(font, g, Vertical),
	assembly: Font.math_assembly(font, g, Vertical),
}

check_generated : List(U8), U64, I64 -> Font
check_generated = |bytes, n, delta| {
	font = match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
		Ok(ready) => ready
		Err(ps) => crash "valid generated MATH font rejected: ${Str.inspect(ps)}"
	}
	if !Font.has_math(font) {
		crash "generated MATH disappeared"
	}
	for glyph in [1.U32, n.to_u32_wrap()] {
		if Font.math_italic_correction(font, glyph) != Present(delta) or Font.math_top_accent_attachment(font, glyph) != Present(200) or !Font.math_extended_shape(font, glyph) {
			crash "generated glyph facts changed"
		}
		if Font.math_kern_table(font, glyph, TopRight) != { heights: [-100, 100], values: [-10, 0, 10] } {
			crash "generated corner kern changed"
		}
		if [-101.I64, -100, 99, 100].map(|h| Font.math_kern(font, glyph, TopRight, h)) != [-10, 0, 0, 10] {
			crash "MATH threshold equality changed"
		}
		if Font.math_variants(font, glyph, Vertical) != [{ glyph: 1, advance: 700 }, { glyph: 2, advance: 1100 }] {
			crash "MATH variants changed order"
		}
		match Font.math_assembly(font, glyph, Vertical) {
			Present(a) if a.parts.len() == 3 => {}
			_ => crash "MATH assembly parts changed"
		}
	}
	if Font.math_italic_correction(font, (n + 1).to_u32_wrap()) != Absent or Font.math_kern(font, 4294967295, BottomLeft, 0) != 0 {
		crash "past-font MATH query isn't absent"
	}
	font
}

# Original bytes, built wholly in the test-only FontBuild package.
generated : U64, U64, I64 -> List(U8)
generated = |n, choice, delta| {
	glyphs = FontBuild.counting(n).map(|i| i + 1)
	coverage = if (choice % 2 == 0) FontBuild.coverage1(glyphs) else FontBuild.coverage2([{ first: 1, last: n, index: 0 }])
	constants = FontBuild.pack([I16(80), I16(60), U16(0), U16(0)].concat(List.repeat(Raw([0, 0, 0, 0]), 51)).append(I16(65)))
	italics = FontBuild.pack([Ref(coverage), U16(n)].concat(List.repeat(Raw(FontBuild.i16(delta).concat([0, 0])), n)))
	accents = FontBuild.pack([Ref(coverage), U16(n)].concat(List.repeat(Raw([0, 200, 0, 0]), n)))
	kern = FontBuild.pack([U16(2), I16(-100), U16(0), I16(100), U16(0), I16(-10), U16(0), I16(0), U16(0), I16(10), U16(0)])
	kern_info = FontBuild.pack([Ref(coverage), U16(n)].concat(glyphs.join_map(|_| [Ref(kern), U16(0), U16(0), U16(0)])))
	info = FontBuild.pack([Ref(italics), Ref(accents), Ref(coverage), Ref(kern_info)])
	parts = FontBuild.pack([I16(delta), U16(0), U16(3), U16(1), U16(0), U16(100), U16(400), U16(0), U16(2), U16(100), U16(100), U16(200), U16(1), U16(3), U16(100), U16(0), U16(400), U16(0)])
	construction = FontBuild.pack([Ref(parts), U16(2), U16(1), U16(700), U16(2), U16(1100)])
	variants = FontBuild.pack([U16(20), Ref(coverage), U16(0), U16(n), U16(0)].concat(glyphs.map(|_| Ref(construction))))
	math = FontBuild.pack([U16(1), U16(0), Ref(constants), Ref(info), Ref(variants)])
	FontBuild.file([
		{ tag: "head", data: FontBuild.head(1000, False) },
		{ tag: "hhea", data: FontBuild.hhea(800, -200, n + 1) },
		{ tag: "maxp", data: FontBuild.maxp(n + 1) },
		{ tag: "hmtx", data: FontBuild.hmtx(List.repeat(500, n + 1)) },
		{ tag: "cmap", data: FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 0x10001, last: 0x10000 + n, glyph: 1 }]) }]) },
		{ tag: "MATH", data: math },
	])
}

target = Fuzz.target_with!({ name: "font-math", generator: Fuzz.raw_bytes, test!, show: |bytes| Str.inspect(bytes.take_first(32)) })
