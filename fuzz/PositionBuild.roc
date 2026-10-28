import build.FontBuild

## Feature-isolated valid positioning tables at increasing lookup counts.
## Lookup zero (a single adjustment) is reachable only from contextual
## types. The feature lists one tested lookup; extra copies stress reading
## and indexing without changing the shaped result.
PositionBuild :: {}.{
	anchor : I64, I64 -> List(U8)
	anchor = |x, y| FontBuild.pack([U16(1), I16(x), I16(y)])

	file : U8, List(U8), U64 -> List(U8)
	file = |choice, values, copies| {
		value = (values.first() ?? 17).to_i64() - 128
		single = FontBuild.pack([U16(1), Ref(FontBuild.coverage1([1])), U16(7), I16(value), I16(value // 2), I16(value // 3)])
		kind = [1, 3, 4, 5, 6, 7, 8].get(choice.to_u64() % 7) ?? 1
		mark_array = |glyph| FontBuild.pack([U16(1), U16(0), Ref(PositionBuild.anchor(glyph.to_i64_wrap(), value))])
		matrix = FontBuild.pack([U16(1), Ref(PositionBuild.anchor(300, 700))])
		sub = match kind {
			1 => single
			3 => FontBuild.pack([U16(1), Ref(FontBuild.coverage1([1, 2])), U16(2), Ref(PositionBuild.anchor(20, 30)), Ref(PositionBuild.anchor(450, value)), Ref(PositionBuild.anchor(40, 50)), Ref(PositionBuild.anchor(470, 80))])
			4 => FontBuild.pack([U16(1), Ref(FontBuild.coverage1([5])), Ref(FontBuild.coverage1([1])), U16(1), Ref(mark_array(10.U64)), Ref(matrix)])
			5 => {
				components = FontBuild.pack([U16(2), Ref(PositionBuild.anchor(200, 600)), Ref(PositionBuild.anchor(500, 800))])
				FontBuild.pack([U16(1), Ref(FontBuild.coverage1([5])), Ref(FontBuild.coverage1([7])), U16(1), Ref(mark_array(10.U64)), Ref(FontBuild.pack([U16(1), Ref(components)]))])
			}
			6 => FontBuild.pack([U16(1), Ref(FontBuild.coverage1([6])), Ref(FontBuild.coverage1([5])), U16(1), Ref(mark_array(20.U64)), Ref(matrix)])
			7 => FontBuild.pack([U16(3), U16(2), U16(1), Ref(FontBuild.coverage1([1])), Ref(FontBuild.coverage1([2])), U16(0), U16(0)])
			_ => FontBuild.pack([U16(3), U16(1), Ref(FontBuild.coverage1([3])), U16(1), Ref(FontBuild.coverage1([1])), U16(1), Ref(FontBuild.coverage1([2])), U16(1), U16(0), U16(0)])
		}
		extended = choice.bitwise_and(8) != 0
		actual = if (extended) 9 else kind
		bytes = if (extended) FontBuild.extension(kind, sub) else sub
		flags = if (kind == 3 and choice.bitwise_and(16) != 0) 1 else 0
		lookup = { kind: actual, flag: flags, set: 0, subtables: [bytes] }
		lookups = [{ kind: 1, flag: 0, set: 0, subtables: [single] }].concat(List.repeat(lookup, copies))
		layout = FontBuild.flagged_listing("dist", [1], lookups)
		outlines = FontBuild.outlines(List.repeat(FontBuild.boxed(0, 0, 200, 300), 64), False)
		names = FontBuild.naming([1, 2, 6].map(|id| { system: 3, encoding: 1, language: 0x409, id, text: FontBuild.utf16("PositionTest") }), [])
		FontBuild.file(
			FontBuild.sixty_four.concat([
				{ tag: "GDEF", data: FontBuild.marks_gdef },
				{ tag: "GPOS", data: layout },
				{ tag: "glyf", data: outlines.glyf },
				{ tag: "loca", data: outlines.loca },
				{ tag: "name", data: names },
				{ tag: "post", data: FontBuild.post(0x30000, [], []) },
				{ tag: "OS/2", data: FontBuild.os2({ use_typo: True, typo_ascent: 800, typo_descent: -200, win_ascent: 800, win_descent: 200 }) },
			]),
		)
	}

	text : List(U8) -> Str
	text = |bytes| {
		glyphs = [3, 1, 2, 1, 5, 6, 7, 5].concat(bytes.take_first(32).map(|b| 1 + b.to_u64() % 7))
		Str.from_utf8(
			glyphs.join_map(
				|g| {
					c = 0x10000 + g
					[0xF0 + c.shr_zf_wrap(18), 0x80 + c.shr_zf_wrap(12).bitwise_and(63), 0x80 + c.shr_zf_wrap(6).bitwise_and(63), 0x80 + c.bitwise_and(63)].map(|b| b.to_u8_wrap())
				},
			),
		) ?? ""
	}
}
