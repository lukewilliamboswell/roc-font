import build.FontBuild
import font.Font

# OpenType 1.9.1 GSUB lookups operate on the current glyph sequence.
# https://learn.microsoft.com/en-us/typography/opentype/spec/gsub
# Font.GlyphOrigin counts the immediate inputs to a ligature, and a
# one-for-one replacement preserves structural kinds with the later tag.
Tracing := {}.{
	check : {} -> Bool
	check = |_| {
		font = fixture({})
		[False, True].all(|rtl| [False, True].all(|expand| agrees(font, rtl, expand)))
	}
}

fixture : {} -> Font
fixture = |_| {
	lookup = |kind, data| { kind, subtables: [data] }
	context = |child| lookup(5, FontBuild.context3([[1], [2], [3]], [{ at: 0, lookup: child }]))
	ligate = |first, rest, glyph| lookup(4, FontBuild.ligature([first], [[{ glyph, rest }]]))
	gsub = FontBuild.layout(
		"DFLT",
		[
			{ tag: "calt", lookups: [0] },
			{ tag: "clig", lookups: [3, 5] },
			{ tag: "liga", lookups: [5] },
			{ tag: "smcp", lookups: [4] },
		],
		[
			context(1),
			context(2),
			ligate(1, [2, 3], 8),
			ligate(8, [4], 9),
			lookup(2, FontBuild.multiple([9], [[10, 11]])),
			lookup(1, FontBuild.single2([5, 9, 10, 11], [15, 12, 13, 14])),
		],
	)
	cmap = FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 0x05D0, last: 0x05D5, glyph: 1 }]) }])
	file = FontBuild.glyphs_font(List.repeat(500, 16), cmap, [{ tag: "GSUB", data: gsub }])
	Font.from_bytes(file, Font.ReadOptions.{ strict: True }) ?? crash "tracing fixture did not read strictly"
}

Row : { glyph : U32, cluster : U64, origin : Font.GlyphOrigin }

phrase : U64, Str, Bool -> List(Row)
phrase = |cluster, tag, expand| {
	# ABC ligates in the inner rule, then the result joins D. That second
	# ligature has two immediate inputs. The optional expansion puts two
	# glyphs on the same cluster. The final lookup also substitutes E.
	name = { feature: tag }
	structure = if (expand) [
		{
			glyph: 13,
			cluster,
			origin: Multiple(name),
		},
		{
			glyph: 14,
			cluster,
			origin: Inserted(name),
		},
	] else [{ glyph: 12, cluster, origin: Ligature({ feature: tag, components: 2 }) }]
	structure.append({
		glyph: 15,
		cluster: cluster + 8,
		origin: Substituted(name),
	})
}

agrees : Font, Bool, Bool -> Bool
agrees = |font, rtl, expand| {
	# Each scalar takes two bytes. The limit on liga starts at the first
	# character of the second phrase, so the same final lookup has a
	# different credited feature for the two otherwise identical phrases.
	options = Font.ShapeOptions.{
		script: if (rtl) "Hebr" else "Latn",
		direction: if (rtl) RightToLeft else LeftToRight,
		features: [Font.Feature.{ tag: "liga", value: 0, start: 12 }].concat(if (expand) [Font.Feature.{ tag: "smcp" }] else []),
	}
	logical = phrase(0, "liga", expand).append({ glyph: 6, cluster: 10, origin: Mapped }).concat(phrase(12, "clig", expand))
	want = if (rtl) logical.fold([], |visual, row| visual.prepend(row)) else logical
	plan = Font.plan(font, options)
	match Font.shape_traced(font, plan, "אבגדהואבגדה") {
		Ok({ run, origins }) => {
			got = run.glyphs.map2(run.clusters, |glyph, cluster| { glyph, cluster }).map2(origins, |{ glyph, cluster }, origin| { glyph, cluster, origin })
			if origins.len() == run.glyphs.len() and run.clusters.len() == run.glyphs.len() and got == want {
				True
			} else {
				crash "expected ${Str.inspect(want)}, got ${Str.inspect(got)}"
			}
		}
		Err(_) => False
	}
}
