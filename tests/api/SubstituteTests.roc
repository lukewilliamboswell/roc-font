import font.Font
import build.FontBuild

## The tests of substitutions (ligatures, contextual forms and the rest of
## `GSUB`), through the public `Font` API exactly as the package ships it:
## each test builds a font with a `GSUB` table, reads it with
## `Font.from_bytes` and shapes text with `Font.shape`. Run with
## `roc test tests/api/main.roc`.
SubstituteTests :: {}.{}

# ------------------------------------------------------------ test helpers
#
# Each test puts a `GSUB` table built with `FontBuild` into a font of 65535
# glyphs whose character map draws U+10000 + g with glyph g (for g from 1),
# so text can name any glyph; U+10000 itself draws glyph 0. Each character
# takes four bytes of UTF-8, so glyph i of the input has cluster 4 i.

# The text whose characters draw these glyphs.
text_of : List(U64) -> Str
text_of = |glyphs| {
	var $bytes = []
	for g in glyphs {
		c = 0x10000 + g
		$bytes = $bytes.concat([0xF0 + c.shr_zf_wrap(18), 0x80 + c.shr_zf_wrap(12).bitwise_and(0x3F), 0x80 + c.shr_zf_wrap(6).bitwise_and(0x3F), 0x80 + c.bitwise_and(0x3F)].map(|b| b.to_u8_wrap()))
	}
	Str.from_utf8($bytes) ?? ""
}

many_glyphs : List({ tag : Str, data : List(U8) })
many_glyphs = [
	{ tag: "head", data: FontBuild.head(1000, False) },
	{ tag: "hhea", data: FontBuild.hhea(800, -200, 1) },
	{ tag: "maxp", data: FontBuild.maxp(65535) },
	{ tag: "hmtx", data: FontBuild.hmtx([500]).concat(List.repeat(0, 2 * 65534)) },
	{ tag: "cmap", data: FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 0x10001, last: 0x1FFFE, glyph: 1 }]) }]) },
]

# The font with the given `GSUB` table.
read : List(U8) -> Try(Font, List(Font.Problem))
read = |gsub| Font.from_bytes(FontBuild.file(FontBuild.replace(many_glyphs, "GSUB", gsub)), Font.ReadOptions.{})

run_of : Font, List(U64) -> Font.Run
run_of = |font, glyphs| Font.shape(font, text_of(glyphs), Font.ShapeOptions.{})

# The glyphs of a shaped run, or [99999] when the font cannot be read.
shaped : List(U8), List(U64) -> List(U32)
shaped = |gsub, glyphs|
	match read(gsub) {
		Ok(font) => run_of(font, glyphs).glyphs
		Err(_) => [99999]
	}

# Glyphs with their clusters as indices into the input glyphs.
shaped_items : List(U8), List(U64) -> List({ glyph : U32, cluster : U64 })
shaped_items = |gsub, glyphs|
	match read(gsub) {
		Ok(font) => {
			run = run_of(font, glyphs)
			run.glyphs.map2(run.clusters, |glyph, cluster| { glyph, cluster: cluster // 4 })
		}
		Err(_) => []
	}

readable : List(U8) -> Bool
readable = |gsub|
	match read(gsub) {
		Ok(font) => Font.dropped(font).is_empty()
		Err(_) => False
	}

is_gsub : Font.Problem -> Bool
is_gsub = |p|
	match p {
		BadTable(b) => b.table == "GSUB"
		_ => False
	}

# A problem only `GSUB` can cause: broken, or listing more lookups than
# the limit allows.
gsub_problem : Font.Problem -> Bool
gsub_problem = |p|
	match p {
		OverLimit(which) => which == "max_lookups"
		_ => is_gsub(p)
	}

# The table is broken: reading refuses the font for it, lenient or strict,
# as OTS (and so a browser) refuses it, naming only the table.
refused : List(U8) -> Bool
refused = |gsub| {
	bytes = FontBuild.file(FontBuild.replace(many_glyphs, "GSUB", gsub))
	only_gsub = |problems| !problems.is_empty() and problems.all(is_gsub)
	lenient = match Font.from_bytes(bytes, Font.ReadOptions.{}) {
		Ok(_) => False
		Err(problems) => only_gsub(problems)
	}
	strict = match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
		Ok(_) => False
		Err(problems) => only_gsub(problems)
	}
	lenient and strict
}

# A table whose `calt` feature uses the first lookup; the others are only
# reached from it.
first_active : List({ kind : U64, subtables : List(List(U8)) }) -> List(U8)
first_active = |lookups| FontBuild.layout("latn", [{ tag: "calt", lookups: [0] }], lookups)

# A table whose `liga` feature uses every lookup.
all_active : List({ kind : U64, subtables : List(List(U8)) }) -> List(U8)
all_active = |lookups| FontBuild.layout("latn", [{ tag: "liga", lookups: FontBuild.counting(lookups.len()) }], lookups)

# Lookup 1 adds 10, lookup 2 replaces 2 by 20 and 3 by 30, for the context
# tests.
called_lookups : List({ kind : U64, subtables : List(List(U8)) })
called_lookups = [{ kind: 1, subtables: [FontBuild.single1(FontBuild.counting(40), 10)] }, { kind: 1, subtables: [FontBuild.single2([2, 3], [20, 30])] }]

# ------------------------------------------------------------ single

expect shaped(all_active([{ kind: 1, subtables: [FontBuild.single1([5, 6], 10)] }]), [5, 6, 7, 4]) == [15, 16, 7, 4]

# Deltas wrap modulo 65536.
expect shaped(all_active([{ kind: 1, subtables: [FontBuild.single1([5], -6)] }]), [5]) == [65535]
expect shaped(all_active([{ kind: 1, subtables: [FontBuild.single1([65534], 3)] }]), [65534]) == [1]

expect shaped(all_active([{ kind: 1, subtables: [FontBuild.single2([5, 7], [50, 70])] }]), [5, 6, 7]) == [50, 6, 70]

# A coverage of format 2 (ranges with their first coverage index).
expect {
	shaped(all_active([{ kind: 1, subtables: [FontBuild.pack([U16(2), Ref(FontBuild.coverage2([{ first: 3, last: 4, index: 0 }, { first: 8, last: 8, index: 2 }])), U16(3), U16(30), U16(40), U16(80)])] }]), [3, 4, 5, 8, 9]) == [30, 40, 5, 80, 9]
}

# The first subtable that covers a glyph decides it.
expect shaped(all_active([{ kind: 1, subtables: [FontBuild.single2([5], [50]), FontBuild.single1([5, 6], 100)] }]), [5, 6]) == [50, 106]

# Clusters are kept.
expect shaped_items(all_active([{ kind: 1, subtables: [FontBuild.single1([5], 1)] }]), [5, 5]) == [{ glyph: 6, cluster: 0 }, { glyph: 6, cluster: 1 }]

# ------------------------------------------------------------ multiple

expect shaped_items(all_active([{ kind: 2, subtables: [FontBuild.multiple([5], [[1, 2, 3]])] }]), [4, 5, 6]) == [{ glyph: 4, cluster: 0 }, { glyph: 1, cluster: 1 }, { glyph: 2, cluster: 1 }, { glyph: 3, cluster: 1 }, { glyph: 6, cluster: 2 }]

# An empty sequence deletes the glyph.
expect shaped(all_active([{ kind: 2, subtables: [FontBuild.multiple([5], [[]])] }]), [4, 5, 6]) == [4, 6]

# A run grows as far as the substitutions take it, up to 64 glyphs per
# input glyph or 16384 in all, whichever is more (HarfBuzz's bound); past
# that, substitutions that would grow it are not made.
expect shaped(all_active([{ kind: 2, subtables: [FontBuild.multiple([1], [List.repeat(2, 100)])] }]), List.repeat(1, 10)).len() == 1000
expect {
	result = shaped(all_active([{ kind: 2, subtables: [FontBuild.multiple([1], [List.repeat(2, 100)])] }]), List.repeat(1, 300))
	result.len() <= 64 * 300 and result.len() >= 300
}

# A smaller growth limit binds sooner, but never below 16384 glyphs.
expect {
	match read(all_active([{ kind: 2, subtables: [FontBuild.multiple([1], [List.repeat(2, 100)])] }])) {
		Ok(font) => {
			options = Font.ShapeOptions.{ limits: Font.ShapeLimits.{ growth: 1 } }
			run = Font.shape(font, text_of(List.repeat(1, 300)), options)
			run.glyphs.len() <= 16384 and run.glyphs.len() > 300
		}
		Err(_) => False
	}
}

# ------------------------------------------------------------ ligature

ligature_table : List(U8)
ligature_table = all_active([{ kind: 4, subtables: [FontBuild.ligature([1], [[{ glyph: 9, rest: [2, 3] }, { glyph: 8, rest: [2] }]])] }])

# The first ligature of the set that matches wins; an incomplete one at the
# end of the run does not apply.
expect shaped(ligature_table, [1, 2, 3]) == [9]
expect shaped(ligature_table, [1, 2, 4]) == [8, 4]
expect shaped(ligature_table, [1, 2]) == [8]
expect shaped(ligature_table, [1]) == [1]
expect shaped(ligature_table, [0, 1, 2, 3, 1, 2, 3]) == [0, 9, 9]
expect shaped_items(ligature_table, [7, 1, 2, 4]) == [{ glyph: 7, cluster: 0 }, { glyph: 8, cluster: 1 }, { glyph: 4, cluster: 3 }]

# A ligature with no components is a bad table.
expect refused(all_active([{ kind: 4, subtables: [FontBuild.pack([U16(1), Ref(FontBuild.coverage1([1])), U16(1), Ref(FontBuild.pack([U16(1), Ref(FontBuild.pack([U16(9), U16(0)]))]))])] }]))

# ------------------------------------------------------------ context

# Format 1: glyph 1 then 2: add 10 to the first and replace the second.
expect {
	gsub = first_active([{ kind: 5, subtables: [FontBuild.context1([1], [[FontBuild.rule([2], [{ at: 0, lookup: 1 }, { at: 1, lookup: 2 }])]])] }].concat(called_lookups))
	shaped(gsub, [1, 2, 1, 3, 2]) == [11, 20, 1, 3, 2]
}

# Rules are tried in order; the first that matches applies.
expect {
	gsub = first_active([{ kind: 5, subtables: [FontBuild.context1([1], [[FontBuild.rule([3], [{ at: 0, lookup: 1 }]), FontBuild.rule([2], [{ at: 1, lookup: 2 }])]])] }].concat(called_lookups))
	shaped(gsub, [1, 2, 1, 3]) == [1, 20, 11, 3]
}

# Format 2: glyphs 1 and 2 are class 1, glyph 3 class 2. Class 1 followed
# by class 2: add 10 to the class 2 glyph. Class 0 has no rules.
expect {
	classes = FontBuild.classes1(1, [1, 1, 2])
	gsub = first_active([{ kind: 5, subtables: [FontBuild.context2([1, 2, 3], classes, [[], [FontBuild.rule([2], [{ at: 1, lookup: 1 }])]])] }].concat(called_lookups))
	shaped(gsub, [1, 3, 2, 3, 3, 4, 3]) == [1, 13, 2, 13, 3, 4, 3]
}

# Format 3: a coverage per position.
expect {
	gsub = first_active([{ kind: 5, subtables: [FontBuild.context3([[1, 2], [3]], [{ at: 0, lookup: 1 }])] }].concat(called_lookups))
	shaped(gsub, [2, 3, 1, 1, 3]) == [12, 3, 1, 11, 3]
}

# Context of format 3 with no input is read, as OTS reads it, and never
# applies.
expect readable(first_active([{ kind: 5, subtables: [FontBuild.context3([], [])] }]))
expect shaped(first_active([{ kind: 5, subtables: [FontBuild.context3([], [])] }]), [1, 2]) == [1, 2]

# ------------------------------------------------------------ chained context

# Format 1: after 7, the pair 1 2, before 3: add 10 to the 2.
chained_glyphs : List(U8)
chained_glyphs = first_active([{ kind: 6, subtables: [FontBuild.chain1([1], [[FontBuild.chain_rule([7], [2], [3], [{ at: 1, lookup: 1 }])]])] }].concat(called_lookups))

expect shaped(chained_glyphs, [7, 1, 2, 3]) == [7, 1, 12, 3]
expect shaped(chained_glyphs, [1, 2, 3]) == [1, 2, 3]
expect shaped(chained_glyphs, [7, 1, 2, 4]) == [7, 1, 2, 4]
expect shaped(chained_glyphs, [7, 1, 2]) == [7, 1, 2]

# Backtrack is listed nearest first.
expect {
	gsub = first_active([{ kind: 6, subtables: [FontBuild.chain1([1], [[FontBuild.chain_rule([7, 8], [], [], [{ at: 0, lookup: 1 }])]])] }].concat(called_lookups))
	shaped(gsub, [8, 7, 1, 7, 8, 1]) == [8, 7, 11, 7, 8, 1]
}

# Backtrack reads the glyphs already substituted by the same lookup.
expect {
	gsub = first_active([{ kind: 6, subtables: [FontBuild.chain3([[11]], [[1]], [], [{ at: 0, lookup: 1 }])] }, { kind: 1, subtables: [FontBuild.single1([1], 10)] }])
	shaped(gsub, [11, 1, 1, 1]) == [11, 11, 11, 11]
}

# Format 2: glyph 7 is backtrack class 1; glyphs 1 and 2 input classes 1
# and 2; glyph 3 lookahead class 1.
expect {
	gsub = first_active([{ kind: 6, subtables: [FontBuild.chain2([1], FontBuild.classes1(7, [1]), FontBuild.classes2([{ first: 1, last: 1, class: 1 }, { first: 2, last: 2, class: 2 }]), FontBuild.classes1(3, [1]), [[], [FontBuild.chain_rule([1], [2], [1], [{ at: 0, lookup: 1 }])]])] }].concat(called_lookups))
	shaped(gsub, [7, 1, 2, 3, 8, 1, 2, 3]) == [7, 11, 2, 3, 8, 1, 2, 3]
}

# Format 3: coverages for backtrack, input and lookahead; two lookup
# records.
expect {
	gsub = first_active([{ kind: 6, subtables: [FontBuild.chain3([[7]], [[1], [2]], [[3]], [{ at: 0, lookup: 1 }, { at: 1, lookup: 1 }])] }].concat(called_lookups))
	shaped(gsub, [7, 1, 2, 3, 1, 2, 3]) == [7, 11, 12, 3, 1, 2, 3]
}

# A record that points past the matched input is ignored.
expect {
	gsub = first_active([{ kind: 6, subtables: [FontBuild.chain3([], [[1]], [], [{ at: 5, lookup: 1 }, { at: 0, lookup: 2 }])] }].concat(called_lookups))
	shaped(gsub, [1, 1]) == [1, 1]
}

# A nested ligature shortens the input; a nested multiple substitution
# lengthens it, and later records see the new positions.
expect {
	gsub = first_active([
		{ kind: 6, subtables: [FontBuild.chain3([], [[1], [2], [3]], [], [{ at: 0, lookup: 1 }, { at: 1, lookup: 2 }])] },
		{ kind: 4, subtables: [FontBuild.ligature([1], [[{ glyph: 9, rest: [2] }]])] },
		{ kind: 1, subtables: [FontBuild.single2([3], [30])] },
	])
	shaped(gsub, [1, 2, 3, 4]) == [9, 30, 4]
}
expect {
	gsub = first_active([
		{ kind: 6, subtables: [FontBuild.chain3([], [[1], [2]], [], [{ at: 0, lookup: 1 }, { at: 3, lookup: 2 }])] },
		{ kind: 2, subtables: [FontBuild.multiple([1], [[5, 5, 5]])] },
		{ kind: 1, subtables: [FontBuild.single2([2], [20])] },
	])
	shaped(gsub, [1, 2, 4]) == [5, 5, 5, 20, 4]
}

# Nested substitutions in the middle of a run keep the glyphs before and
# after the matched input, with their clusters; a nested multiple
# substitution may also delete its glyph.
expect {
	gsub = first_active([
		{ kind: 6, subtables: [FontBuild.chain3([], [[1], [2]], [], [{ at: 0, lookup: 1 }])] },
		{ kind: 4, subtables: [FontBuild.ligature([1], [[{ glyph: 9, rest: [2] }]])] },
	])
	shaped_items(gsub, [5, 1, 2, 6, 1, 2]) == [{ glyph: 5, cluster: 0 }, { glyph: 9, cluster: 1 }, { glyph: 6, cluster: 3 }, { glyph: 9, cluster: 4 }]
}
expect {
	gsub = first_active([
		{ kind: 6, subtables: [FontBuild.chain3([], [[1], [2]], [], [{ at: 0, lookup: 1 }])] },
		{ kind: 2, subtables: [FontBuild.multiple([1], [[3, 4, 5]])] },
	])
	shaped_items(gsub, [5, 1, 2, 6]) == [{ glyph: 5, cluster: 0 }, { glyph: 3, cluster: 1 }, { glyph: 4, cluster: 1 }, { glyph: 5, cluster: 1 }, { glyph: 2, cluster: 2 }, { glyph: 6, cluster: 3 }]
}
expect {
	gsub = first_active([
		{ kind: 6, subtables: [FontBuild.chain3([], [[1], [2]], [], [{ at: 0, lookup: 1 }, { at: 0, lookup: 2 }])] },
		{ kind: 2, subtables: [FontBuild.multiple([1], [[]])] },
		{ kind: 1, subtables: [FontBuild.single2([2], [20])] },
	])
	shaped(gsub, [5, 1, 2, 6]) == [5, 20, 6]
}

# A contextual rule reached from another rule reads its backtrack from
# everything already written, as HarfBuzz 14.6.0 does: glyph 7 before the
# outer rule's input still matches the inner rule's backtrack.
expect {
	inner = [
		{ kind: 6, subtables: [FontBuild.chain3([[7]], [[1]], [], [{ at: 0, lookup: 2 }])] },
		{ kind: 1, subtables: [FontBuild.single1([1], 10)] },
	]
	outside = first_active([{ kind: 6, subtables: [FontBuild.chain3([], [[1]], [], [{ at: 0, lookup: 1 }])] }].concat(inner))
	within = first_active([{ kind: 6, subtables: [FontBuild.chain3([], [[7], [1]], [], [{ at: 1, lookup: 1 }])] }].concat(inner))
	shaped(outside, [7, 1]) == [7, 11] and shaped(within, [7, 1]) == [7, 11]
}

# ------------------------------------------------------------ extension

expect shaped(all_active([{ kind: 7, subtables: [FontBuild.extension(1, FontBuild.single1([5], 10))] }]), [5, 6]) == [15, 6]
expect {
	gsub = first_active([{ kind: 7, subtables: [FontBuild.extension(6, FontBuild.chain3([], [[1]], [[2]], [{ at: 0, lookup: 1 }]))] }, { kind: 7, subtables: [FontBuild.extension(1, FontBuild.single1([1], 10))] }])
	shaped(gsub, [1, 2, 1]) == [11, 2, 1]
}

# An extension subtable past the table is a bad table.
expect refused(all_active([{ kind: 7, subtables: [FontBuild.pack([U16(1), U16(1), U32(100000)])] }]))

# Alternate (3) and reverse chaining (8) lookups are read and applied
# (tests/api/ShapeParityTests.roc); a subtable of either that does not fit
# its table is a bad table.
expect refused(all_active([{ kind: 8, subtables: [FontBuild.pack([U16(1), Ref(FontBuild.coverage1([5])), U16(60000)])] }]))

# ------------------------------------------------------------ features

# Only the features a browser applies by default to left-to-right text
# apply: not small capitals, discretionary ligatures or right-to-left
# forms. As in HarfBuzz, default features apply in whichever table lists
# them, so `kern` and `mark` lookups in `GSUB` apply too.
expect {
	tags = ["rvrn", "ltra", "ltrm", "ccmp", "locl", "rlig", "liga", "clig", "calt", "rclt", "smcp", "dlig", "rtla", "rtlm", "kern", "mark"]
	lookups = tags.map(|_| { kind: 1, subtables: [FontBuild.single1(FontBuild.counting(200), 1)] })
	features = tags.map_with_index(|tag, i| { tag, lookups: [i] })
	shaped(FontBuild.layout("latn", features, lookups), [5]) == [17]
}

# Lookups apply in lookup order, not feature order; a lookup listed by
# two features applies once.
expect {
	lookups = [{ kind: 1, subtables: [FontBuild.single2([5], [6])] }, { kind: 1, subtables: [FontBuild.single2([6], [7])] }]
	shaped(FontBuild.layout("latn", [{ tag: "liga", lookups: [1, 0] }, { tag: "calt", lookups: [0] }], lookups), [5]) == [7]
}

# The default script is used when there is no Latin one; other scripts are
# not.
expect shaped(FontBuild.layout("DFLT", [{ tag: "liga", lookups: [0] }], [{ kind: 1, subtables: [FontBuild.single1([5], 1)] }]), [5]) == [6]
expect shaped(FontBuild.layout("cyrl", [{ tag: "liga", lookups: [0] }], [{ kind: 1, subtables: [FontBuild.single1([5], 1)] }]), [5]) == [5]

# Only the features the default language lists apply, and its required
# feature.
expect {
	lookups = [{ kind: 1, subtables: [FontBuild.single1([5], 1)] }, { kind: 1, subtables: [FontBuild.single1(FontBuild.counting(200), 10)] }]
	features = [{ tag: "liga", lookups: [0] }, { tag: "calt", lookups: [1] }]
	shaped(FontBuild.layout_listing("latn", [1], 0xFFFF, features, lookups), [5]) == [15] and shaped(FontBuild.layout_listing("latn", [], 0, features, lookups), [5]) == [6]
}

# A listed feature past the feature list, or a feature's lookup past the
# lookup list, is a bad table, as OTS refuses it.
expect refused(FontBuild.layout_listing("latn", [3], 0xFFFF, [{ tag: "liga", lookups: [0] }], [{ kind: 1, subtables: [FontBuild.single1([5], 1)] }]))
expect refused(FontBuild.layout("latn", [{ tag: "liga", lookups: [0, 7] }], [{ kind: 1, subtables: [FontBuild.single1([5], 1)] }]))

# A lookup reached only from a rule does not apply on its own; one that a
# rule calls past the lookup list is a bad table.
expect shaped(first_active([{ kind: 5, subtables: [FontBuild.context3([[1]], [{ at: 0, lookup: 1 }])] }].concat(called_lookups)), [5, 2]) == [5, 2]
expect refused(first_active([{ kind: 5, subtables: [FontBuild.context3([[1]], [{ at: 0, lookup: 9 }])] }]))

# ------------------------------------------------------------ edge cases

expect shaped(all_active([{ kind: 1, subtables: [FontBuild.single1([5], 1)] }]), []) == []
# A font without substitutions keeps every glyph as the character map
# gives it; characters it does not map draw glyph 0.
expect {
	match Font.from_bytes(FontBuild.file(FontBuild.basic), Font.ReadOptions.{}) {
		Ok(font) => Font.shape(font, "ABC@", Font.ShapeOptions.{}).glyphs == [1, 2, 3, 0]
		Err(_) => False
	}
}

# Glyph 0 and glyphs substitutions give past the font pass through every
# kind of lookup.
expect {
	gsub = all_active([
		{ kind: 1, subtables: [FontBuild.single1([5], -6)] },
		{ kind: 2, subtables: [FontBuild.multiple([7], [[1, 2]])] },
		{ kind: 4, subtables: [FontBuild.ligature([1], [[{ glyph: 9, rest: [2] }]])] },
		{ kind: 6, subtables: [FontBuild.chain3([[1]], [[2]], [[3]], [])] },
	])
	shaped(gsub, [0, 5, 0]) == [0, 65535, 0]
}

# Lookups that call themselves stop at a fixed depth.
expect {
	gsub = first_active([{ kind: 5, subtables: [FontBuild.context3([FontBuild.counting(40)], [{ at: 0, lookup: 0 }, { at: 0, lookup: 1 }])] }].concat(called_lookups))
	result = shaped(gsub, [1])
	result.len() == 1 and result != [99999]
}

## fuzz regression: lookups whose rules call each other many times over
## must not take time exponential in the depth. Each of these rules calls
## its own lookup 50 times; without a limit on nested applications, one
## glyph would take 50^7 of them.
expect {
	calls = List.repeat({ at: 0, lookup: 0 }, 50)
	gsub = first_active([{ kind: 5, subtables: [FontBuild.context3([[1]], calls.append({ at: 0, lookup: 1 }))] }, { kind: 1, subtables: [FontBuild.single1([1], 0)] }])
	shaped(gsub, [1, 1, 1]) == [1, 1, 1]
}

## fuzz regression: a contextual rule that calls a multiple substitution
## once per input glyph must not grow the run past its bound (here 16384
## glyphs); each rule could otherwise grow its own window to that size.
expect {
	gsub = first_active([{ kind: 6, subtables: [FontBuild.chain3([], [[1]], [], [{ at: 0, lookup: 1 }])] }, { kind: 2, subtables: [FontBuild.multiple([1], [List.repeat(2, 60)])] }])
	shaped(gsub, List.repeat(1, 20)).len() == 1200 and shaped(gsub, List.repeat(1, 400)).len() <= 64 * 400
}

# Applying is deterministic.
expect {
	gsub = first_active([{ kind: 6, subtables: [FontBuild.chain3([[7]], [[1], [2]], [[3]], [{ at: 0, lookup: 1 }, { at: 1, lookup: 2 }])] }].concat(called_lookups))
	shaped(gsub, [7, 1, 2, 3, 7, 1, 2, 3]) == shaped(gsub, [7, 1, 2, 3, 7, 1, 2, 3])
}

# ------------------------------------------------------------ reading

expect refused([])
expect refused(List.repeat(0, 9))
expect refused(List.repeat(0, 10))
expect readable(FontBuild.layout("latn", [], []))

# Unknown subtable, coverage and class formats, and coverage tables past
# the table.
expect refused(all_active([{ kind: 1, subtables: [FontBuild.patch(FontBuild.single1([5], 1), 0, FontBuild.u16(3))] }]))
expect refused(all_active([{ kind: 5, subtables: [FontBuild.patch(FontBuild.context3([[1]], []), 0, FontBuild.u16(4))] }]))
expect refused(all_active([{ kind: 1, subtables: [FontBuild.patch(FontBuild.single1([5], 1), 2, FontBuild.u16(60000))] }]))
expect refused(all_active([{ kind: 1, subtables: [FontBuild.pack([U16(1), Ref(FontBuild.pack([U16(3), U16(0)])), I16(1)])] }]))
expect refused(first_active([{ kind: 5, subtables: [FontBuild.context2([1], FontBuild.pack([U16(3)]), [])] }]))

# A coverage range may start on the previous range's last glyph, as OTS
# allows (Noto Sans Adlam Unjoined has such a coverage); coverage ranges
# out of order and class ranges that overlap are bad tables, as OTS refuses
# them.
expect {
	gsub = all_active([{ kind: 1, subtables: [FontBuild.pack([U16(1), Ref(FontBuild.coverage2([{ first: 1, last: 6, index: 0 }, { first: 6, last: 19, index: 6 }])), I16(100)])] }])
	shaped(gsub, [1, 6, 19, 20]) == [101, 106, 119, 20]
}
expect refused(all_active([{ kind: 1, subtables: [FontBuild.pack([U16(1), Ref(FontBuild.coverage2([{ first: 5, last: 9, index: 0 }, { first: 2, last: 3, index: 5 }, { first: 12, last: 11, index: 0 }])), I16(1)])] }]))
expect refused(first_active([{ kind: 5, subtables: [FontBuild.context2([1], FontBuild.classes2([{ first: 5, last: 9, class: 1 }, { first: 9, last: 10, class: 2 }]), [])] }]))

## fuzz regression: a chained context of format 2 may leave its backtrack
## and lookahead class definitions out (a null offset), putting every
## glyph in class 0; Noto Music does. Reading the subtable itself as a
## class definition refused the whole table.
expect {
	sets = [U16(0), FontBuild.rule_set([FontBuild.chain_rule([0], [], [0], [{ at: 0, lookup: 1 }])])]
	subtable = FontBuild.pack([U16(2), Ref(FontBuild.coverage1([1])), U16(0), Ref(FontBuild.classes1(1, [1])), U16(0), U16(2)].concat(sets))
	gsub = first_active([{ kind: 6, subtables: [subtable] }].concat(called_lookups))
	shaped(gsub, [7, 1, 8, 1]) == [7, 11, 8, 1]
}

# Every prefix of a table with every kind of lookup, and every byte of it
# set to 0 or 0xFF, is read or refused; what is read applies without
# growing past the bound.
every_kind : List(U8)
every_kind = FontBuild.every_lookup

expect readable(every_kind)

expect {
	var $outcomes = 0
	for n in 0..<every_kind.len() {
		match read(every_kind.take_first(n)) {
			Ok(font) => {
				glyphs = run_of(font, [7, 1, 2, 3, 1, 2]).glyphs
				gsub_only = Font.dropped(font).all(gsub_problem)
				$outcomes = $outcomes + (if (glyphs.len() <= 16384 and gsub_only) 1 else 1000000)
			}
			# A broken `GSUB` rejects the font, naming only `GSUB`.
			Err(found) => {
				$outcomes = $outcomes + (if (!found.is_empty() and found.all(is_gsub)) 1 else 1000000)
			}
		}
	}
	$outcomes == every_kind.len()
}

expect {
	var $outcomes = 0
	for at in 0..<every_kind.len() {
		for value in [0, 1, 0xFF] {
			match read(every_kind.set(at, value) ?? []) {
				Ok(font) => {
					glyphs = run_of(font, [7, 1, 2, 3, 1, 2, 0, 9]).glyphs
					gsub_only = Font.dropped(font).all(gsub_problem)
					$outcomes = $outcomes + (if (glyphs.len() <= 16384 and gsub_only) 1 else 1000000)
				}
				Err(found) => {
					$outcomes = $outcomes + (if (!found.is_empty() and found.all(is_gsub)) 1 else 1000000)
				}
			}
		}
	}
	$outcomes == 3 * every_kind.len()
}

## fuzz regression: lookups that share one subtable thousands of times are
## refused rather than read thousands of times over.
expect {
	count = 2000
	# A lookup list whose entries all point at one lookup, whose subtable
	# offsets all point at one subtable.
	lookup_list = [U16(count)].concat(List.repeat(U16(2 + 2 * count), count))
	lookup = [U16(1), U16(0), U16(count)].concat(List.repeat(U16(6 + 2 * count), count))
	body = FontBuild.pack(lookup_list.concat(lookup)).concat(FontBuild.single1(FontBuild.counting(10), 1))
	features = FontBuild.pack([U16(1), Tag("liga"), U16(8), U16(0), U16(count)].concat(FontBuild.counting(count).map(|i| U16(i))))
	language = FontBuild.pack([U16(0), U16(0xFFFF), U16(1), U16(0)])
	scripts = FontBuild.pack([U16(1), Tag("latn"), Ref(FontBuild.pack([Ref(language), U16(0)]))])
	header = FontBuild.pack([U32(0x00010000), Ref(scripts), Ref(features), Ref(body)])
	refused(header)
}

# The same sharing on a small scale is read.
expect {
	count = 3
	lookup_list = [U16(count)].concat(List.repeat(U16(2 + 2 * count), count))
	lookup = [U16(1), U16(0), U16(count)].concat(List.repeat(U16(6 + 2 * count), count))
	body = FontBuild.pack(lookup_list.concat(lookup)).concat(FontBuild.single1(FontBuild.counting(10), 1))
	features = FontBuild.pack([U16(1), Tag("liga"), U16(8), U16(0), U16(count)].concat(FontBuild.counting(count).map(|i| U16(i))))
	language = FontBuild.pack([U16(0), U16(0xFFFF), U16(1), U16(0)])
	scripts = FontBuild.pack([U16(1), Tag("latn"), Ref(FontBuild.pack([Ref(language), U16(0)]))])
	shaped(FontBuild.pack([U32(0x00010000), Ref(scripts), Ref(features), Ref(body)]), [5]) == [8]
}

# ------------------------------------------------------------ lookup variations

# A variable font (`wght` 100 to 900, default 400) whose `liga` feature
# uses lookup 0 (glyph 1 becomes 2) and has a lookup variation record (a
# `FeatureVariations` extension HarfBuzz reads) that, from half way to the
# heaviest weight, adds lookup 1 (2 becomes 4) to the feature's own when
# `keep`, or else replaces them with lookup 2 (1 becomes 5). A record
# that does not keep the feature's lookups replaces them even where no
# condition holds, leaving the feature none. Lookups 1 and 2 are listed
# by no feature, so reading must read them for the variation. Expected
# glyphs are HarfBuzz 14.6.0's (uharfbuzz 0.56.3) for these files.
lookup_varied : Bool -> List(U8)
lookup_varied = |keep| {
	lookups = [
		{ kind: 1, flag: 0, set: 0, subtables: [FontBuild.single1([1], 1)] },
		{ kind: 1, flag: 0, set: 0, subtables: [FontBuild.single1([2], 2)] },
		{ kind: 1, flag: 0, set: 0, subtables: [FontBuild.single1([1], 4)] },
	]
	variations = FontBuild.lookup_variations([{ feature: 0, keep, conditions: [{ axis: 0, min: 8192, max: 16384, lookups: [if (keep) 1 else 2] }] }])
	FontBuild.file(many_glyphs.concat([{ tag: "fvar", data: FontBuild.fvar([{ tag: "wght", min: 100, default: 400, max: 900 }]) }, { tag: "GSUB", data: FontBuild.flagged_layout_varied("liga", [0], lookups, variations) }]))
}

lookup_varied_glyphs : Bool, U16 -> List(U32)
lookup_varied_glyphs = |keep, weight|
	match Font.from_bytes(lookup_varied(keep), Font.ReadOptions.{}) {
		Ok(font) => Font.shape(Font.at(font, Font.Variation.{ weight: Weight(weight) }), text_of([1, 3]), Font.ShapeOptions.{}).glyphs
		Err(_) => []
	}

expect lookup_varied_glyphs(True, 400) == [2, 3] and lookup_varied_glyphs(True, 600) == [2, 3] and lookup_varied_glyphs(True, 700) == [4, 3] and lookup_varied_glyphs(True, 900) == [4, 3]
expect lookup_varied_glyphs(False, 400) == [1, 3] and lookup_varied_glyphs(False, 600) == [1, 3] and lookup_varied_glyphs(False, 700) == [5, 3] and lookup_varied_glyphs(False, 900) == [5, 3]
