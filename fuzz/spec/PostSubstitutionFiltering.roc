import build.FontBuild
import build.MarkBuild
import font.Font

# HarfBuzz 14.6.0 uses the substituted mark's GDEF properties. Mark
# filtering set membership supersedes the attachment type, and a lookup
# that ignores marks skips them even when its filtering set contains them.
PostSubstitutionFiltering := {}.{
	check : {} -> Bool
	check = |_| {
		font = fixture({})
		cases = [
			{ text: "AXB", replace: True, lookup: "kern", mark: 4, applies: True },
			{ text: "AXB", replace: False, lookup: "kern", mark: 3, applies: False },
			{ text: "AYB", replace: True, lookup: "kern", mark: 4, applies: True },
			{ text: "AXB", replace: True, lookup: "tst1", mark: 4, applies: False },
			{ text: "AXB", replace: False, lookup: "tst1", mark: 3, applies: True },
			{ text: "AXB", replace: True, lookup: "tst2", mark: 4, applies: True },
		]
		for case in cases {
			features = [
				Font.Feature.{ tag: "ccmp", value: if (case.replace) 1 else 0 },
				Font.Feature.{ tag: "kern", value: if (case.lookup == "kern") 1 else 0 },
				Font.Feature.{ tag: "tst1", value: if (case.lookup == "tst1") 1 else 0 },
				Font.Feature.{ tag: "tst2", value: if (case.lookup == "tst2") 1 else 0 },
			]
			run = Font.shape(font, case.text, Font.ShapeOptions.{ script: "Latn", clusters: Characters, features })
			(lead_advance, lead_x, flag) = if (case.applies) (520, 13, 1) else (600, 0, 0)
			if run.glyphs != [1, case.mark, 2] or run.clusters != [0, 1, 2] or run.flags != [0, flag, flag]
				or run.advances != [{ x: lead_advance, y: 0 }, { x: 0, y: 0 }, { x: 700, y: 0 }]
				or run.offsets != [{ x: lead_x, y: 0 }, { x: 0, y: 0 }, { x: 0, y: 0 }] {
				crash "GPOS filtering after substitution ${Str.inspect(case)}: ${Str.inspect(run)}"
			}
		}
		True
	}
}

fixture : {} -> Font
fixture = |_| {
	cmap = FontBuild.cmap([
		{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 'A', last: 'B', glyph: 1 }, { first: 'X', last: 'Y', glyph: 3 }]) },
	])
	classes = FontBuild.classes1(1, [1, 1, 3, 3])
	attachment_classes = FontBuild.classes1(3, [1, 2])
	sets = FontBuild.pack([U16(1), U16(1), Ref32(FontBuild.coverage1([4]))])
	gdef = FontBuild.pack([U32(0x00010002), Ref(classes), U16(0), U16(0), Ref(attachment_classes), Ref(sets)])
	gsub = FontBuild.layout("latn", [{ tag: "ccmp", lookups: [0] }], [{ kind: 1, subtables: [FontBuild.single2([3], [4])] }])
	pair = FontBuild.pair1(5, 0, [{ glyph: 1, pairs: [{ second: 2, values: [13, -80] }] }])
	gpos = MarkBuild.layout(
		"latn",
		[{ tag: "kern", lookups: [0] }, { tag: "tst1", lookups: [1] }, { tag: "tst2", lookups: [2] }],
		[0x0100, 0x0110, 0x0118].map(|flag| MarkBuild.Lookup.{ kind: 2, flag, subtables: [pair] }),
	)
	bytes = FontBuild.glyphs_font([500, 600, 700, 0, 0], cmap, [{ tag: "GDEF", data: gdef }, { tag: "GSUB", data: gsub }, { tag: "GPOS", data: gpos }])
	Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "GPOS filtering fixture rejected"
}
