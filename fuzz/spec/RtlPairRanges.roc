import build.FontBuild
import font.Font

# Hebrew selects the hebr/IWR pair lookup. Both value records move the
# glyphs by distinct amounts. The range is tested at the UTF-8 start
# of each logical character before results are returned in visual order.
# HarfBuzz 14.6.0 agrees on an independent FontTools face.
# https://github.com/harfbuzz/harfbuzz/blob/14.6.0/src/hb-ot-shape.cc#L710-L717
RtlPairRanges := {}.{
	check : {} -> Bool
	check = |_| {
		font = fixture({})
		text = "אבגאבג"
		for (range, right, left) in [
			([], AlefBet, AlefBet),
			([(0, 1)], BetGimel, AlefBet),
			([(1, 2)], AlefBet, AlefBet),
			([(2, 3)], Unpositioned, AlefBet),
			([(6, 7)], AlefBet, BetGimel),
		] {
			features = range.map(|(start, end)| Font.Feature.{ tag: "kern", value: 0, start, end })
			run = Font.shape(font, text, Font.ShapeOptions.{ script: "Hebr", language: "he", features })
			# A nonempty second value record consumes the second glyph and
			# extends the unsafe span through the glyph after the pair.
			rows = reverse(group(right, 0, False).concat(group(left, 6, right == BetGimel)))
			agree(run, rows, Str.inspect(range))
		}
		plain = group(Unpositioned, 0, False).concat(group(Unpositioned, 6, False))
		agree(Font.shape(font, text, Font.ShapeOptions.{ script: "Hebr", language: "en" }), reverse(plain), "language without the lookup")
		agree(Font.shape(font, text, Font.ShapeOptions.{ script: "Hebr", language: "he", direction: LeftToRight }), plain, "direction without matching pairs")
		True
	}
}

Pair : [AlefBet, BetGimel, Unpositioned]

Row : { glyph : U32, cluster : U64, width : I32, x : I32, y : I32, flag : U8 }

group : Pair, U64, Bool -> List(Row)
group = |pair, start, after_previous_pair| {
	first_flag = if (after_previous_pair) 1 else 0
	(advances, offsets, flags) = match pair {
		AlefBet => ([560, 709, 800], [(11, 7), (-23, 29), (0, 0)], [first_flag, 1, 1])
		BetGimel => ([600, 681, 807], [(0, 0), (31, -13), (5, -17)], [first_flag, 0, 1])
		Unpositioned => ([600, 700, 800], [(0, 0), (0, 0), (0, 0)], [first_flag, 0, 0])
	}
	advances.map_with_index(
		|width, i| {
			(x, y) = offsets.get(i) ?? (0, 0)
			{ glyph: 1 + i.to_u32_wrap(), cluster: start + 2 * i, width, x, y, flag: flags.get(i) ?? 0 }
		},
	)
}

reverse : List(Row) -> List(Row)
reverse = |rows| rows.fold([], |xs, row| xs.prepend(row))

agree : Font.Run, List(Row), Str -> {}
agree = |run, rows, context| {
	want = {
		glyphs: rows.map(|r| r.glyph),
		clusters: rows.map(|r| r.cluster),
		advances: rows.map(|r| { x: r.width, y: 0 }),
		offsets: rows.map(|r| { x: r.x, y: r.y }),
		flags: rows.map(|r| r.flag),
	}
	if run != want {
		crash "RTL pair ranges ${context}: expected ${Str.inspect(want)}, got ${Str.inspect(run)}"
	}
}

fixture : {} -> Font
fixture = |_| {
	subtable = FontBuild.pair1(
		7,
		7,
		[
			{ glyph: 1, pairs: [{ second: 2, values: [11, 7, -40, -23, 29, 9] }] },
			{ glyph: 2, pairs: [{ second: 3, values: [31, -13, -19, 5, -17, 7] }] },
		],
	)
	langsys = FontBuild.pack([U16(0), U16(0xFFFF), U16(1), U16(0)])
	script = FontBuild.pack([U16(0), U16(1), Tag("IWR "), Ref(langsys)])
	scripts = FontBuild.pack([U16(1), Tag("hebr"), Ref(script)])
	features = FontBuild.pack([U16(1), Tag("kern"), Ref(FontBuild.pack([U16(0), U16(1), U16(0)]))])
	lookups = FontBuild.pack([U16(1), Ref(FontBuild.pack([U16(2), U16(0), U16(1), Ref(subtable)]))])
	gpos = FontBuild.pack([U32(0x00010000), Ref(scripts), Ref(features), Ref(lookups)])
	cmap = FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 0x05D0, last: 0x05D2, glyph: 1 }]) }])
	bytes = FontBuild.glyphs_font([500, 600, 700, 800], cmap, [{ tag: "GPOS", data: gpos }])
	Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "RTL pair range fixture did not read strictly"
}
