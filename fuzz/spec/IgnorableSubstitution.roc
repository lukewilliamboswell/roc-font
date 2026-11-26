import build.FontBuild
import font.Font

# A font can substitute a mapped default-ignorable glyph before positioning.
# The replacement participates in kerning and remains visible. If the
# source has no nominal glyph or ccmp is disabled, kerning skips across it
# and the final run hides it. All cases agree with HarfBuzz 14.6.0 on an
# independent FontTools face with matching cmap, GSUB and GPOS.
# https://github.com/harfbuzz/harfbuzz/blob/14.6.0/src/hb-ot-layout.hh#L320-L324
IgnorableSubstitution := {}.{
	check : {} -> Bool
	check = |_| {
		for nominal in [False, True] {
			for space in [False, True] {
				font = fixture(nominal, space)
				for ccmp in [False, True] {
					features = if (ccmp) [] else [Font.Feature.{ tag: "ccmp", value: 0, start: 1, end: 3 }]
					run = Font.shape(font, "A\u(AD)B", Font.ShapeOptions.{ features })
					want = expected(nominal and ccmp, space)
					if run != want {
						crash "soft hyphen with nominal = ${Str.inspect(nominal)}, space = ${Str.inspect(space)}, ccmp = ${Str.inspect(ccmp)}: expected ${Str.inspect(want)}, got ${Str.inspect(run)}"
					}
				}
			}
		}
		True
	}
}

expected : Bool, Bool -> Font.Run
expected = |substituted, space| {
	(glyphs, clusters, widths, flags) =
		if substituted {
			([1, 4, 2], [0, 1, 3], [483, 56, 500], [0, 1, 1])
		} else if space {
			([1, 5, 2], [0, 1, 3], [450, 0, 500], [0, 1, 1])
		} else {
			([1, 2], [0, 3], [450, 500], [0, 1])
		}
	{
		glyphs,
		clusters,
		advances: widths.map(|x| { x, y: 0 }),
		offsets: List.repeat({ x: 0, y: 0 }, glyphs.len()),
		flags,
	}
}

fixture : Bool, Bool -> Font
fixture = |nominal, space| {
	space_map = if (space) [{ first: ' ', last: ' ', glyph: 5 }] else []
	hyphen_map = if (nominal) [{ first: 0xAD, last: 0xAD, glyph: 3 }] else []
	subtable = FontBuild.cmap12(space_map.append({ first: 'A', last: 'B', glyph: 1 }).concat(hyphen_map))
	cmap = FontBuild.cmap([{ system: 3, encoding: 10, subtable }])
	gsub = FontBuild.layout(
		"latn",
		[{ tag: "ccmp", lookups: [0] }],
		[
			{ kind: 1, subtables: [FontBuild.single2([3], [4])] },
		],
	)
	pairs = FontBuild.pair1(
		4,
		0,
		[
			{ glyph: 1, pairs: [{ second: 2, values: [-50] }, { second: 4, values: [-17] }] },
			{ glyph: 4, pairs: [{ second: 2, values: [-33] }] },
		],
	)
	gpos = FontBuild.layout("latn", [{ tag: "kern", lookups: [0] }], [{ kind: 2, subtables: [pairs] }])
	bytes = FontBuild.glyphs_font(
		[500, 500, 500, 83, 89, 200],
		cmap,
		[
			{ tag: "GSUB", data: gsub },
			{ tag: "GPOS", data: gpos },
		],
	)
	Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "ignorable substitution fixture did not read strictly"
}
