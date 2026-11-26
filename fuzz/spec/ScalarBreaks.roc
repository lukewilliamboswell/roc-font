import build.FontBuild
import font.Font

# HarfBuzz 14.6.0 clears unsafe-to-break on glyphs whose clusters change
# while merging. Otherwise an old break boundary can survive composition.
# https://github.com/harfbuzz/harfbuzz/blob/14.6.0/src/hb-buffer.cc#L532
ScalarBreaks := [].{
	check : {} -> Bool
	check = |{}| {
		face = fixture({})
		options = Font.ShapeOptions.{ script: "Latn", clusters: Characters }
		run = Font.shape(face, "a\u(301)\u(323)y", options)
		check_run(run, ([4, 2, 5], [0, 0, 5], [0, 0, 0]))

		# Reversing graphemes for an RTL request also merges a previously
		# marked cluster. This acute has no composition in the fixture.
		rtl_options = Font.ShapeOptions.{ script: "Latn", clusters: Characters, direction: RightToLeft }
		reversed = Font.shape(face, "a\u(301)y", rtl_options)
		check_run(reversed, ([5, 1, 2], [3, 0, 0], [0, 0, 0]))

		characters = Font.plan(face, options)
		graphemes = Font.plan(face, Font.ShapeOptions.{ script: "Latn" })
		# The caller's last two scalars share an offset. Moving the dot
		# below before the acute merges both marks and carries along y.
		# Composing a with the dot below then merges them into the starter.
		# Translating the source offsets changes only the cluster labels.
		for base in [20, 5_000_000_000] {
			unordered = scalars(base, 0x0301, 0x0323, 10)
			check_run(Font.shape_scalars(face, characters, unordered), ([4, 2, 5], List.repeat(base, 3), [0, 0, 0]))
			check_run(Font.shape_scalars(face, graphemes, unordered), ([4, 2, 5], List.repeat(base, 3), [0, 0, 0]))
			shared_starter = scalars(base, 0x0301, 0x0323, 0)
			check_run(Font.shape_scalars(face, characters, shared_starter), ([4, 2, 5], List.repeat(base, 3), [0, 0, 0]))

			# With the marks already in canonical order, the acute and y
			# keep their later offset. Both rows retain its unsafe flag.
			ordered = scalars(base, 0x0323, 0x0301, 10)
			check_run(Font.shape_scalars(face, characters, ordered), ([4, 2, 5], [base, base + 20, base + 20], [0, 1, 1]))
		}
		True
	}
}

scalars : U64, U32, U32, U64 -> List({ scalar : U32, offset : U64 })
scalars = |base, first, second, first_delta| [
	{ scalar: 'a', offset: base },
	{ scalar: first, offset: base + first_delta },
	{ scalar: second, offset: base + 20 },
	{ scalar: 'y', offset: base + 20 },
]

check_run : Font.Run, (List(U32), List(U64), List(U8)) -> {}
check_run = |run, want| {
	got = (run.glyphs, run.clusters, run.flags)
	if got != want {
		crash "expected ${Str.inspect(want)}, got ${Str.inspect(got)}"
	}
}

fixture : {} -> Font
fixture = |{}| {
	cmap = FontBuild.cmap([
		{
			system: 3,
			encoding: 10,
			subtable: FontBuild.cmap12([
				{ first: 'a', last: 'a', glyph: 1 },
				{ first: 'y', last: 'y', glyph: 5 },
				{ first: 0x0301, last: 0x0301, glyph: 2 },
				{ first: 0x0323, last: 0x0323, glyph: 3 },
				{ first: 0x1EA1, last: 0x1EA1, glyph: 4 },
			]),
		},
	])
	Font.from_bytes(FontBuild.glyphs_font(List.repeat(500, 6), cmap, []), Font.ReadOptions.{ strict: True }) ?? crash "scalar break fixture did not read strictly"
}
