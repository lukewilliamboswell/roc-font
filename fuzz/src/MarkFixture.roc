import build.FontBuild
import build.MarkBuild

MarkFixture :: {}.{
	Fault : [Valid, BadClass, BadAnchor, BadCoverage, ShortAnchor]

	bytes : U64, Bool, I64, I64, U64, Fault -> List(U8)
	bytes = |kind, extended, x, y, count, fault| {
		actual = MarkBuild.anchor(x, y)
		source = if (fault == BadAnchor) [0, 4, 0, 11, 0, 0] else MarkBuild.point_anchor(11, -23, 0)
		marks = [{ glyph: 2, class: if (fault == BadClass) 1 else 0, anchor: source }]
		first = if (kind == 6) 3 else 1
		glyphs = [first].concat(FontBuild.counting(count).map(|i| i + 4))
		subtable = if kind == 5 {
			rows = glyphs.map(|g| { glyph: g, components: [[MarkBuild.anchor(x + 1, y + 1)], [actual]] })
			MarkBuild.ligatures(marks, 1, rows)
		} else {
			MarkBuild.position(marks, 1, glyphs.map(|g| { glyph: g, anchors: [actual] }))
		}
		position = match fault {
			ShortAnchor => subtable.take_first(subtable.len() - 1)
			# The mark coverage must have as many entries as the mark array.
			BadCoverage => {
				coverage = (subtable.get(2) ?? 0).to_u64() * 256 + (subtable.get(3) ?? 0).to_u64()
				subtable.set(coverage + 3, 0) ?? []
			}
			_ => subtable
		}
		lookup = if (extended) MarkBuild.Lookup.{ kind: 9, subtables: [FontBuild.extension(kind, position)] } else MarkBuild.Lookup.{ kind, subtables: [position] }
		tag = if (kind == 6) "mkmk" else "mark"
		gpos = MarkBuild.layout("latn", [{ tag, lookups: [0] }], [lookup])
		gdef = MarkBuild.gdef([{ first: 1, last: 1, class: if (kind == 5) 2 else 1 }, { first: 2, last: 3, class: 3 }], [])
		cmap = FontBuild.cmap([
			{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 'A', last: 'A', glyph: 1 }, { first: 0x0300, last: 0x0301, glyph: 2 }]) },
		])
		FontBuild.glyphs_font([500, 610, 90, 80].concat(List.repeat(10, count)), cmap, [{ tag: "GDEF", data: gdef }, { tag: "GPOS", data: gpos }])
	}
}
