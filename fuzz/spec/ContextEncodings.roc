import build.FontBuild
import font.Font

ContextEncodings := [].{
	check : {} -> Bool
	check = |{}| {
		cases = [
			{ text: "DEAEBECEDEG", glyphs: [4, 5, 1, 5, 2, 5, 9, 5, 4, 5, 7] },
			{ text: "DAHECDH", glyphs: [4, 1, 8, 5, 9, 4, 8] },
			{ text: "ADBCDG", glyphs: [1, 4, 2, 3, 4, 7] },
			{ text: "DABCGD", glyphs: [4, 1, 2, 3, 7, 4] },
			{ text: "DABCD", glyphs: [4, 1, 2, 3, 4] },
			{ text: "DAACDG", glyphs: [4, 1, 1, 3, 4, 7] },
			{ text: "DABCDA", glyphs: [4, 1, 2, 3, 4, 1] },
		]
		for format in [Glyphs, Classes, Coverages] {
			face = chained_font(format)
			for case in cases {
				run = Font.shape(face, case.text, Font.ShapeOptions.{ script: "Latn" })
				if (run.glyphs, run.clusters) != (case.glyphs, FontBuild.counting(case.glyphs.len())) {
					crash "chained format ${Str.inspect(format)} for ${case.text}: ${Str.inspect((run.glyphs, run.clusters))}"
				}
			}
		}
		True
	}
}

ChainedFormat : [Glyphs, Classes, Coverages]

# Replace C in DA[BH]CD[GH], ignoring GDEF marks E and F.
# OpenType orders backtrack nearest first. The lookahead starts after
# both matched input glyphs, allowing for marks skipped along the way.
# https://learn.microsoft.com/en-us/typography/opentype/spec/chapter2#chained-sequence-context-format-1-simple-glyph-contexts
chained_font : ChainedFormat -> Font
chained_font = |format| {
	calls = [{ at: 1, lookup: 1 }]
	subtable = match format {
		Glyphs => {
			rules = [7, 8].map(|last| FontBuild.chain_rule([1, 4], [3], [4, last], calls))
			FontBuild.chain1([2, 8], [rules, rules])
		}
		Classes => {
			# Unassigned B and H both select input class 0, despite having
			# different coverage indices. G and H are unassigned in lookahead.
			back = FontBuild.classes1(1, [1, 0, 0, 2])
			input = FontBuild.classes2([
				{ first: 0, last: 1, class: 2 },
				{ first: 3, last: 3, class: 1 },
				{ first: 4, last: 7, class: 2 },
				{ first: 9, last: 9, class: 2 },
			])
			ahead = FontBuild.classes2([
				{ first: 0, last: 3, class: 2 },
				{ first: 4, last: 4, class: 1 },
				{ first: 5, last: 6, class: 2 },
				{ first: 9, last: 9, class: 2 },
			])
			FontBuild.chain2([2, 8], back, input, ahead, [[FontBuild.chain_rule([1, 2], [1], [1, 0], calls)], [], []])
		}
		Coverages => FontBuild.chain3([[1], [4]], [[2, 8], [3]], [[4], [7, 8]], calls)
	}
	gsub = FontBuild.flagged_listing(
		"calt",
		[0],
		[
			{ kind: 6, flag: 0x08, set: 0, subtables: [subtable] },
			{ kind: 1, flag: 0, set: 0, subtables: [FontBuild.single2([3], [9])] },
		],
	)
	cmap = FontBuild.cmap([{ system: 3, encoding: 1, subtable: FontBuild.cmap4([{ first: 'A', last: 'H', delta: 65536 - 64, glyphs: [] }]) }])
	file = FontBuild.glyphs_font(List.repeat(500, 10), cmap, [{ tag: "GDEF", data: FontBuild.marks_gdef }, { tag: "GSUB", data: gsub }])
	Font.from_bytes(file, Font.ReadOptions.{ strict: True }) ?? crash "chained context fixture did not read strictly"
}
