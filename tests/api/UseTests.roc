import font.Font
import build.FontBuild
import "../../tests/fonts/shaping/use-joining/UseNKoSans.ttf" as nko_bytes : List(U8)
import "../../tests/fonts/shaping/use-joining/UseNKoUnjoined.ttf" as unjoined_bytes : List(U8)
import "../../tests/fonts/shaping/use-joining/UseAdlamSans.ttf" as adlam_bytes : List(U8)
import "../../tests/fonts/shaping/use-joining/UseAdlamDisplay.ttf" as display_bytes : List(U8)
import "../../tests/fonts/shaping/use-joining/UseMongolianSans.ttf" as mongol_bytes : List(U8)

# Actual USE joining examples with exact HB14.6 glyphs and byte clusters.
UseTests :: {}.{}

read : List(U8) -> Font
read = |bytes| match Font.from_bytes(bytes, Font.ReadOptions.{}) {
	Ok(font) => font
	Err(problems) => crash Str.inspect(problems)
}

nko : Font
nko = read(nko_bytes)

unjoined : Font
unjoined = read(unjoined_bytes)

adlam : Font
adlam = read(adlam_bytes)

display : Font
display = read(display_bytes)

mongol : Font
mongol = read(mongol_bytes)

expect {
	run = Font.shape(nko, "ߒߞߏ", Font.ShapeOptions.{ script: "Nkoo", direction: RightToLeft })
	run.glyphs == [76, 122, 87] and run.clusters == [4, 2, 0] and run.advances.map(|a| a.x) == [551, 544, 685] and run.flags == [1, 1, 0]
}
expect {
	run = Font.shape(unjoined, "ߒߞߏ", Font.ShapeOptions.{ script: "Nkoo", direction: RightToLeft })
	run.glyphs == [17, 32, 20] and run.clusters == [4, 2, 0] and run.advances.map(|a| a.x) == [551, 544, 685] and run.flags == [1, 1, 0]
}
expect {
	run = Font.shape(adlam, "𞤀𞤣𞤤𞤢𞤥", Font.ShapeOptions.{ script: "Adlm", direction: RightToLeft })
	run.glyphs == [224, 140, 222, 163, 3] and run.clusters == [16, 12, 8, 4, 0] and run.advances.map(|a| a.x) == [588, 669, 616, 625, 715] and run.flags == [1, 1, 1, 1, 0]
}
expect {
	run = Font.shape(display, "𞤀𞤣𞤤𞤢𞤥", Font.ShapeOptions.{ script: "Adlm", direction: RightToLeft })
	run.glyphs == [39, 36, 38, 37, 1] and run.clusters == [16, 12, 8, 4, 0] and run.advances.map(|a| a.x) == [1228, 1343, 1249, 1261, 1413] and run.offsets.map(|a| a.x) == [0, 0, -20, 0, 0]
}
expect {
	run = Font.shape(mongol, "ᠠ᠋", Font.ShapeOptions.{ script: "Mong", direction: LeftToRight })
	run.glyphs == [925, 896] and run.clusters == [0, 0] and run.advances.map(|a| a.x) == [824, 0]
}
expect {
	plan = Font.plan(nko, Font.ShapeOptions.{ script: "Nkoo", direction: RightToLeft })
	run = Font.shape_range(nko, plan, "ߊߊߊ", Font.TextRange.{ start: 2, end: 4 })
	run.glyphs == [62] and run.clusters == [2] and run.advances.map(|a| a.x) == [265] and run.flags == [0]
}
expect {
	run = Font.shape(nko, "ߊ‌͏߫ߊ", Font.ShapeOptions.{ script: "Nkoo", direction: RightToLeft })
	run.glyphs == [12, 45, 1, 1, 12] and run.clusters == [9, 2, 2, 2, 0] and run.advances.map(|a| a.x) == [265, 0, 0, 0, 265] and run.flags == [0, 1, 1, 1, 0]
}
expect Font.shape(nko, "", Font.ShapeOptions.{ script: "Nkoo" }).glyphs.is_empty()

## fuzz regression: a halant consumed by ccmp remains a ligature across
## USE's substitution-flag pauses. It must not stop a pre-base vowel.
expect {
	cmap = FontBuild.cmap([
		{
			system: 3,
			encoding: 10,
			subtable: FontBuild.cmap12([
				{ first: 0x1B13, last: 0x1B13, glyph: 3 },
				{ first: 0x1B1B, last: 0x1B1B, glyph: 1 },
				{ first: 0x1B3E, last: 0x1B3E, glyph: 4 },
				{ first: 0x1B44, last: 0x1B44, glyph: 2 },
			]),
		},
	])
	gsub = FontBuild.layout(
		"bali",
		[{ tag: "ccmp", lookups: [0] }],
		[
			{ kind: 4, subtables: [FontBuild.ligature([2], [[{ glyph: 5, rest: [3] }]])] },
		],
	)
	bytes = FontBuild.file(FontBuild.replace(FontBuild.sixty_four, "cmap", cmap).concat([{ tag: "GSUB", data: gsub }]))
	font = read(bytes)
	run = Font.shape(font, "ᬛ᭄ᬓᬾ", Font.ShapeOptions.{ script: "Bali" })
	run.glyphs == [4, 1, 5] and run.clusters == [0, 0, 0]
}
