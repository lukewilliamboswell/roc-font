import FontBuild

## Small GPOS mark attachment fixtures.
MarkBuild :: {}.{
	Mark : { glyph : U64, class : U64, anchor : List(U8) }

	Row : { glyph : U64, anchors : List(List(U8)) }

	Lookup := { kind : U64, flag : U64 ?? 0, set : U64 ?? 0, subtables : List(List(U8)) }

	anchor : I64, I64 -> List(U8)
	anchor = |x, y| FontBuild.pack([U16(1), I16(x), I16(y)])

	point_anchor : I64, I64, U64 -> List(U8)
	point_anchor = |x, y, index| FontBuild.pack([U16(2), I16(x), I16(y), U16(index)])

	device_anchor : I64, I64, List(U8), List(U8) -> List(U8)
	device_anchor = |x, y, dx, dy| FontBuild.pack([U16(3), I16(x), I16(y), MarkBuild.optional(dx), MarkBuild.optional(dy)])

	optional : List(U8) -> FontBuild.Field
	optional = |bytes| if (bytes.is_empty()) U16(0) else Ref(bytes)

	mark_array : List(Mark) -> List(U8)
	mark_array = |marks| FontBuild.pack([U16(marks.len())].concat(marks.join_map(|mark| [U16(mark.class), Ref(mark.anchor)])))

	## Shared format 1 encoding of a mark-to-base or mark-to-mark subtable.
	## Empty anchors in a target row produce null offsets.
	position : List(Mark), U64, List(Row) -> List(U8)
	position = |marks, classes, rows| {
		array = FontBuild.pack([U16(rows.len())].concat(rows.join_map(|r| r.anchors.map(MarkBuild.optional))))
		MarkBuild.subtable(marks, classes, rows.map(|row| row.glyph), array)
	}

	subtable : List(Mark), U64, List(U64), List(U8) -> List(U8)
	subtable = |marks, classes, glyphs, parent_array| FontBuild.pack(
		[U16(1), Ref(FontBuild.coverage1(marks.map(|m| m.glyph))), Ref(FontBuild.coverage1(glyphs)), U16(classes), Ref(MarkBuild.mark_array(marks)), Ref(parent_array)],
	)

	## One script and its default language system, with explicit flags
	## and mark filtering set numbers on the lookups.
	layout : Str, List({ tag : Str, lookups : List(U64) }), List(Lookup) -> List(U8)
	layout = |script, features, lookups| {
		# The ordinary builder ends with its empty lookup list.
		header = FontBuild.layout(script, features, []).drop_last(2)
		lookup_list = FontBuild.pack(
			[U16(lookups.len())].concat(
				lookups.map(
					|lookup| {
						filter = if (lookup.flag.bitwise_and(0x10) != 0) [U16(lookup.set)] else []
						Ref(FontBuild.pack([U16(lookup.kind), U16(lookup.flag), U16(lookup.subtables.len())].concat(lookup.subtables.map(|s| Ref(s))).concat(filter)))
					},
				),
			),
		)
		header.concat(lookup_list)
	}

	## A GDEF class definition and mark glyph sets.
	gdef : List({ first : U64, last : U64, class : U64 }), List(List(U64)) -> List(U8)
	gdef = |classes, sets| {
		mark_sets = FontBuild.pack([U16(1), U16(sets.len())].concat(sets.map(|glyphs| Ref32(FontBuild.coverage1(glyphs)))))
		FontBuild.pack([U32(0x00010002), Ref(FontBuild.classes2(classes)), U16(0), U16(0), U16(0), Ref(mark_sets)])
	}
}
