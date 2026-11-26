import build.FontBuild
import font.Font

ClusterRanges := [].{
	check : {} -> Bool
	check = |{}| {
		face = font_without_space({})
		text = "א\u(AD)בג😀"
		bytes = text.to_utf8()
		prefix = "é:"
		base = prefix.count_utf8_bytes()
		paragraph = prefix.concat(text).concat("tail").to_utf8()
		scalars = [
			{ scalar: 0x05D0, offset: base },
			{ scalar: 0x00AD, offset: base + 2 },
			{ scalar: 0x05D1, offset: base + 4 },
			{ scalar: 0x05D2, offset: base + 6 },
			{ scalar: 0x1F600, offset: base + 8 },
		]
		for rtl in [False, True] {
			options = Font.ShapeOptions.{ script: if (rtl) "Hebr" else "Latn", direction: if (rtl) RightToLeft else LeftToRight }
			want = expected(rtl)
			check_slices(Font.shape(face, text, options), bytes, bytes.len(), 0, want)
			# The caller shapes one paragraph fragment with absolute offsets
			# and ends its last range at the fragment's byte boundary.
			run = Font.shape_scalars(face, Font.plan(face, options), scalars)
			check_slices(run, paragraph, base + bytes.len(), base, want)
		}
		True
	}
}

Row : { glyph : U32, range : { start : U64, end : U64 }, drawn : Str }

# HarfBuzz removes default-ignorables when there is no space glyph.
# https://github.com/harfbuzz/harfbuzz/blob/14.6.0/src/hb-ot-shape.cc
expected : Bool -> List(Row)
expected = |rtl| {
	# Joining bet and gimel and then expanding that ligature puts both
	# output glyphs on one cluster. Without a space glyph, soft hyphen
	# is removed. In RTL, both glyphs of the preceding visual cluster
	# take the removed scalar's earlier byte offset.
	if (rtl) [
		{ glyph: 4, range: { start: 8, end: 12 }, drawn: "😀" },
		{ glyph: 7, range: { start: 2, end: 8 }, drawn: "\u(AD)בג" },
		{ glyph: 6, range: { start: 2, end: 8 }, drawn: "\u(AD)בג" },
		{ glyph: 1, range: { start: 0, end: 2 }, drawn: "א" },
	] else [
		{ glyph: 1, range: { start: 0, end: 4 }, drawn: "א\u(AD)" },
		{ glyph: 6, range: { start: 4, end: 8 }, drawn: "בג" },
		{ glyph: 7, range: { start: 4, end: 8 }, drawn: "בג" },
		{ glyph: 4, range: { start: 8, end: 12 }, drawn: "😀" },
	]
}

check_slices : Font.Run, List(U8), U64, U64, List(Row) -> {}
check_slices = |run, bytes, end, base, want| {
	ranges = Font.cluster_ranges(run, end)
	shifted = want.map(|{ range, glyph, drawn }| { range: { start: range.start + base, end: range.end + base }, glyph, drawn })
	if ranges.len() != run.glyphs.len() {
		crash "cluster ranges did not align with the shaped glyphs"
	}
	got = run.glyphs.map2(
		ranges,
		|glyph, range| {
			drawn = Str.from_utf8(bytes.sublist({ start: range.start, len: range.end - range.start })) ?? crash "cluster range split a UTF-8 scalar"
			{ glyph, range, drawn }
		},
	)
	if got != shifted {
		crash "expected ${Str.inspect(shifted)}, got ${Str.inspect(got)}"
	}
}

font_without_space : {} -> Font
font_without_space = |{}| {
	gsub = FontBuild.layout(
		"DFLT",
		[{ tag: "liga", lookups: [0, 1] }],
		[
			{ kind: 4, subtables: [FontBuild.ligature([2], [[{ glyph: 5, rest: [3] }]])] },
			{ kind: 2, subtables: [FontBuild.multiple([5], [[6, 7]])] },
		],
	)
	cmap = FontBuild.cmap([
		{
			system: 3,
			encoding: 10,
			subtable: FontBuild.cmap12([
				{ first: 0x05D0, last: 0x05D2, glyph: 1 },
				{ first: 0x1F600, last: 0x1F600, glyph: 4 },
			]),
		},
	])
	file = FontBuild.glyphs_font(List.repeat(500, 8), cmap, [{ tag: "GSUB", data: gsub }])
	Font.from_bytes(file, Font.ReadOptions.{ strict: True }) ?? crash "cluster range fixture did not read strictly"
}
