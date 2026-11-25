import build.FontBuild
import build.MarkBuild
import font.Font

MarkLigatureTests :: {}.{}

ligature_font : Bool -> Font
ligature_font = |rtl| {
	a = MarkBuild.anchor
	script = if (rtl) "hebr" else "latn"
	cmap = FontBuild.cmap([
		{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 'A', last: 'B', glyph: 1 }, { first: 'C', last: 'C', glyph: 5 }, { first: 0x0300, last: 0x0301, glyph: 3 }]) },
	])
	gdef = MarkBuild.gdef([{ first: 1, last: 2, class: 1 }, { first: 3, last: 4, class: 3 }, { first: 5, last: 5, class: 2 }], [])
	gsub = MarkBuild.layout(
		script,
		[{ tag: "liga", lookups: [0] }],
		[MarkBuild.Lookup.{ kind: 4, flag: 8, subtables: [FontBuild.ligature([1], [[{ glyph: 5, rest: [2] }]])] }],
	)
	mark = MarkBuild.ligatures(
		[{ glyph: 3, class: 0, anchor: a(11, 17) }, { glyph: 4, class: 0, anchor: a(-9, 27) }],
		1,
		[{ glyph: 5, components: [[a(150, 220)], [a(380, -80)]] }],
	)
	lookup = if (rtl) MarkBuild.Lookup.{ kind: 9, subtables: [FontBuild.extension(5, mark)] } else MarkBuild.Lookup.{ kind: 5, subtables: [mark] }
	gpos = MarkBuild.layout(script, [{ tag: "mark", lookups: [0] }], [lookup])
	bytes = FontBuild.glyphs_font([500, 610, 370, 90, 80, 700], cmap, [{ tag: "GDEF", data: gdef }, { tag: "GSUB", data: gsub }, { tag: "GPOS", data: gpos }])
	Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "mark-to-ligature fixture was rejected"
}

# A mark skipped by GSUB belongs to its original component. A trailing
# mark and a cmap ligature without provenance both use the last component.
# HarfBuzz 14.6.0 agrees using an independent fontTools fixture.
expect {
	cases = [
		{ rtl: False, text: "A\u(300)B\u(301)", glyphs: [5, 3, 4], clusters: [0, 0, 4], advances: [700, 0, 0], offsets: [(0, 0), (-561, 203), (-311, -107)], flags: [0, 0, 1] },
		{ rtl: True, text: "A\u(300)B\u(301)", glyphs: [4, 3, 5], clusters: [4, 0, 0], advances: [0, 0, 700], offsets: [(389, -107), (139, 203), (0, 0)], flags: [1, 0, 0] },
		{ rtl: False, text: "C\u(300)", glyphs: [5, 3], clusters: [0, 1], advances: [700, 0], offsets: [(0, 0), (-331, -97)], flags: [0, 1] },
		{ rtl: True, text: "C\u(300)", glyphs: [3, 5], clusters: [1, 0], advances: [0, 700], offsets: [(369, -97), (0, 0)], flags: [1, 0] },
	]
	cases.all(
		|row| {
			options = Font.ShapeOptions.{ script: if (row.rtl) "Hebr" else "Latn", direction: if (row.rtl) RightToLeft else LeftToRight, clusters: Characters }
			run = Font.shape(ligature_font(row.rtl), row.text, options)
			ok = run.glyphs == row.glyphs and run.clusters == row.clusters
				and run.advances == row.advances.map(|x| { x, y: 0 }) and run.offsets == row.offsets.map(|(x, y)| { x, y })
				and run.flags == row.flags
			if ok {
				True
			} else {
				crash "mark-to-ligature expected ${Str.inspect(row)} but got ${Str.inspect(run)}"
			}
		},
	)
}
