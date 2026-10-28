app [target] {
	build: "../tests/support/main.roc",
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}
import fuzz.Fuzz
import font.Font
import build.FontBuild
import "../tests/fonts/color/noto-emoji-subset.ttf" as real_file : List(U8)
import "../tests/fonts/color/color-all.ttf" as all_file : List(U8)
import "../tests/fonts/color/color-map.ttf" as map_file : List(U8)
import "../tests/fonts/color/color-precision.ttf" as precision_file : List(U8)

## Narrow CPAL/COLRv1 target. Generated 8/64/256-glyph fonts contain only
## the changing base-paint records and their bounded glyph/solid DAGs.
## Read allocation growth is linear; querying one fixed glyph must not
## allocate in proportion to unrelated glyphs. Mutation also exercises all
## paint formats, variation stores/maps, and a licensed real emoji font.
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	choice = (bytes.first() ?? 0).to_u64()
	a_bytes = generated(8, choice)
	b_bytes = generated(64, choice)
	c_bytes = generated(256, choice)
	a = read_generated(a_bytes, 8)
	b = read_generated(b_bytes, 64)
	c = read_generated(c_bytes, 256)
	ma = Fuzz.measure_allocs!(|{}| Font.from_bytes(a_bytes, Font.ReadOptions.{}))
	mb = Fuzz.measure_allocs!(|{}| Font.from_bytes(b_bytes, Font.ReadOptions.{}))
	mc = Fuzz.measure_allocs!(|{}| Font.from_bytes(c_bytes, Font.ReadOptions.{}))
	if mb.allocations > 10 * ma.allocations + 128 or mc.allocations > 5 * mb.allocations + 128 {
		crash "COLR preparation allocations grew faster than feature size"
	}
	qa = Fuzz.measure_allocs!(|{}| Font.color_glyph(a, 1))
	qb = Fuzz.measure_allocs!(|{}| Font.color_glyph(b, 1))
	qc = Fuzz.measure_allocs!(|{}| Font.color_glyph(c, 1))
	if qb.allocations > qa.allocations + 2 or qc.allocations > qa.allocations + 2 {
		crash "one color glyph query allocates with unrelated glyph count"
	}
	Fuzz.expect_no_leaks!(|{}| Font.from_bytes(c_bytes, Font.ReadOptions.{}))
	Fuzz.expect_no_leaks!(|{}| Font.color_glyph(c, 1))
	source = match choice % 5 {
		0 => real_file
		1 => all_file
		2 => map_file
		3 => precision_file
		_ => c_bytes
	}
	candidate = if bytes.take_first(4) == [0, 1, 0, 0] or bytes.take_first(4) == "OTTO".to_utf8() or bytes.take_first(4) == "ttcf".to_utf8() {
		bytes
	} else {
		FontBuild.mutate(source, bytes.drop_first(1))
	}
	match Font.from_bytes(candidate, Font.ReadOptions.{}) {
		Ok(font) => {
			again = match Font.from_bytes(candidate, Font.ReadOptions.{}) {
				Ok(f) => f
				Err(_) => crash "same color bytes changed read result"
			}
			for weight in [100.U16, 400, 650, 900] {
				moved = Font.at(font, Font.Variation.{ weight: Weight(weight) })
				repeated = Font.at(again, Font.Variation.{ weight: Weight(weight) })
				if Font.color_palettes(moved) != Font.color_palettes(repeated) {
					crash "CPAL palette query nondeterministic"
				}
				for id in [0.U32, 1, 3, 7, 32, Font.glyph_count(font), 4294967295] {
					graph = Font.color_glyph(moved, id)
					if graph != Font.color_glyph(repeated, id) or Font.color_layers(moved, id) != Font.color_layers(repeated, id) {
						crash "COLR graph nondeterministic"
					}
					match graph {
						Present(g) => {
							if !valid_graph(g, Font.glyph_count(font), candidate.len()) {
								crash "returned color graph violates finite indexed bounded contract"
							}
						}
						Absent => {}
					}
				}
			}
		}
		Err(_) => {}
	}
	Fuzz.keep
}

finite = |n| n >= -10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000.F64 and n <= 10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000.F64

point = |p| finite(p.x) and finite(p.y)

rect = |r| match r {
	Present(p) => finite(p.x_min) and finite(p.y_min) and finite(p.x_max) and finite(p.y_max)
	Absent => True
}

operation = |op| match op {
	Affine(a) => [a.xx, a.yx, a.xy, a.yy, a.dx, a.dy].all(finite)
	Translate(p) => point(p)
	Scale(s) => finite(s.x) and finite(s.y) and point(s.center)
	Rotate(r) => finite(r.degrees) and point(r.center)
	Skew(s) => finite(s.x_degrees) and finite(s.y_degrees) and point(s.center)
}

valid_graph : Font.ColorGlyph, U32, U64 -> Bool
valid_graph = |g, glyph_count, size| {
	n = g.nodes.len()
	if g.root.to_u64() >= n or n > 8 * size + 16384 or g.edges.len() > 8 * size + 16384 or g.stops.len() > 8 * size + 16384 or !rect(g.clip) {
		return False
	}
	child = |i| i.to_u64() < n
	span = |s, len| s.start <= len and s.len <= len - s.start
	g.edges.all(child) and g.stops.all(|s| finite(s.offset) and finite(s.alpha) and s.alpha >= 0 and s.alpha <= 1) and g.nodes.all(
		|p| match p {
			Layers(s) => span(s, g.edges.len())
			Solid(s) => finite(s.alpha) and s.alpha >= 0 and s.alpha <= 1
			LinearGradient(l) => span(l.stops, g.stops.len()) and point(l.p0) and point(l.p1) and point(l.p2)
			RadialGradient(r) => span(r.stops, g.stops.len()) and point(r.c0) and point(r.c1) and finite(r.radius0) and finite(r.radius1)
			SweepGradient(s) => span(s.stops, g.stops.len()) and point(s.center) and finite(s.start_degrees) and finite(s.end_degrees)
			Glyph(v) => v.glyph < glyph_count and child(v.paint)
			ColorGlyph(v) => v.glyph < glyph_count and child(v.paint) and rect(v.clip)
			Transform(t) => child(t.paint) and operation(t.operation)
			Composite(c) => child(c.source) and child(c.backdrop)
		},
	)
}

read_generated = |bytes, n| {
	font = match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
		Ok(f) => f
		Err(ps) => crash "valid generated color font rejected: ${Str.inspect(ps)}"
	}
	for id in [1.U32, n.to_u32_wrap()] {
		match Font.color_glyph(font, id) {
			Present(g) => {
				if g.nodes.len() != 2 or !valid_graph(g, Font.glyph_count(font), bytes.len()) {
					crash "generated glyph lost its bounded two-node paint"
				}
			}
			Absent => crash "generated COLRv1 glyph absent"
		}
	}
	font
}

generated : U64, U64 -> List(U8)
generated = |n, choice| {
	# Each BaseGlyphPaintRecord offset is relative to BaseGlyphList, then
	# each PaintGlyph Offset24 is relative to that PaintGlyph.
	header = FontBuild.pack([U16(1), U16(0), U32(0), U32(0), U16(0), U32(34), U32(0), U32(0), U32(0), U32(0)])
	records = FontBuild.counting(n).join_map(|i| FontBuild.pack([U16(i + 1), U32(4 + 6 * n + 11 * i)]))
	paints = FontBuild.counting(n).join_map(|i| [10, 0, 0, 6].concat(FontBuild.u16(i + 1)).concat([2, 0, 0, 64, 0]))
	colr = header.concat(FontBuild.u32(n)).concat(records).concat(paints)
	cpal = FontBuild.pack([U16(0), U16(1), U16(1), U16(1), U32(14), U16(0), Raw([choice.to_u8_wrap(), 0, 255, 255])])
	FontBuild.file([
		{ tag: "head", data: FontBuild.head(1000, False) },
		{ tag: "hhea", data: FontBuild.hhea(800, -200, n + 1) },
		{ tag: "maxp", data: FontBuild.maxp(n + 1) },
		{ tag: "hmtx", data: FontBuild.hmtx(List.repeat(500, n + 1)) },
		{ tag: "cmap", data: FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 0x10001, last: 0x10000 + n, glyph: 1 }]) }]) },
		{ tag: "CPAL", data: cpal },
		{ tag: "COLR", data: colr },
	])
}

target = Fuzz.target_with!({ name: "font-color", generator: Fuzz.raw_bytes, test!, show: |bytes| Str.inspect(bytes.take_first(32)) })
