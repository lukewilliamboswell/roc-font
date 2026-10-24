import FontShape
import FontTest

## The tests of `FontShape`. Test-only: `main.roc` does not import this
## module. Run with `roc test package/FontShapeTests.roc`.
FontShapeTests :: {}.{}

# ------------------------------------------------------------ test helpers
#
# Each test builds a `GSUB` table with `FontTest` and shapes a run of glyph
# indices. Glyph indices are arbitrary numbers here; no font is needed.

items_of : List(U64) -> List(FontShape.Item)
items_of = |glyphs| glyphs.map_with_index(|glyph, i| { glyph, cluster: i })

# The glyphs of a shaped run, or [99999] when the table cannot be read.
shaped : List(U8), List(U64) -> List(U64)
shaped = |gsub, glyphs|
	match FontShape.read(gsub) {
		Ok(shape) => FontShape.apply(shape, items_of(glyphs)).map(|item| item.glyph)
		Err(_) => [99999]
	}

shaped_items : List(U8), List(U64) -> List(FontShape.Item)
shaped_items = |gsub, glyphs|
	match FontShape.read(gsub) {
		Ok(shape) => FontShape.apply(shape, items_of(glyphs))
		Err(_) => []
	}

readable : List(U8) -> Bool
readable = |gsub| FontShape.read(gsub).is_ok()

# A table whose `calt` feature uses the first lookup; the others are only
# reached from it.
first_active : List({ kind : U64, subtables : List(List(U8)) }) -> List(U8)
first_active = |lookups| FontTest.layout("latn", [{ tag: "calt", lookups: [0] }], lookups)

# A table whose `liga` feature uses every lookup.
all_active : List({ kind : U64, subtables : List(List(U8)) }) -> List(U8)
all_active = |lookups| FontTest.layout("latn", [{ tag: "liga", lookups: FontTest.counting(lookups.len()) }], lookups)

# Lookup 1 adds 10, lookup 2 replaces 2 by 20 and 3 by 30, for the context
# tests.
called_lookups : List({ kind : U64, subtables : List(List(U8)) })
called_lookups = [{ kind: 1, subtables: [FontTest.single1(FontTest.counting(40), 10)] }, { kind: 1, subtables: [FontTest.single2([2, 3], [20, 30])] }]

# ------------------------------------------------------------ single

expect shaped(all_active([{ kind: 1, subtables: [FontTest.single1([5, 6], 10)] }]), [5, 6, 7, 4]) == [15, 16, 7, 4]

# Deltas wrap modulo 65536.
expect shaped(all_active([{ kind: 1, subtables: [FontTest.single1([5], -6)] }]), [5]) == [65535]
expect shaped(all_active([{ kind: 1, subtables: [FontTest.single1([65535], 2)] }]), [65535]) == [1]

expect shaped(all_active([{ kind: 1, subtables: [FontTest.single2([5, 7], [50, 70])] }]), [5, 6, 7]) == [50, 6, 70]

# A coverage of format 2 (ranges with their first coverage index).
expect {
	shaped(all_active([{ kind: 1, subtables: [FontTest.pack([U16(2), Ref(FontTest.coverage2([{ first: 3, last: 4, index: 0 }, { first: 8, last: 8, index: 2 }])), U16(3), U16(30), U16(40), U16(80)])] }]), [3, 4, 5, 8, 9]) == [30, 40, 5, 80, 9]
}

# The first subtable that covers a glyph decides it.
expect shaped(all_active([{ kind: 1, subtables: [FontTest.single2([5], [50]), FontTest.single1([5, 6], 100)] }]), [5, 6]) == [50, 106]

# Clusters are kept.
expect shaped_items(all_active([{ kind: 1, subtables: [FontTest.single1([5], 1)] }]), [5, 5]) == [{ glyph: 6, cluster: 0 }, { glyph: 6, cluster: 1 }]

# ------------------------------------------------------------ multiple

expect shaped_items(all_active([{ kind: 2, subtables: [FontTest.multiple([5], [[1, 2, 3]])] }]), [4, 5, 6]) == [{ glyph: 4, cluster: 0 }, { glyph: 1, cluster: 1 }, { glyph: 2, cluster: 1 }, { glyph: 3, cluster: 1 }, { glyph: 6, cluster: 2 }]

# An empty sequence deletes the glyph.
expect shaped(all_active([{ kind: 2, subtables: [FontTest.multiple([5], [[]])] }]), [4, 5, 6]) == [4, 6]

# A run never grows past 4 n + 32 glyphs.
expect {
	result = shaped(all_active([{ kind: 2, subtables: [FontTest.multiple([1], [List.repeat(2, 100)])] }]), List.repeat(1, 10))
	result.len() <= 4 * 10 + 32 and result.len() >= 10
}

# ------------------------------------------------------------ ligature

ligature_table : List(U8)
ligature_table = all_active([{ kind: 4, subtables: [FontTest.ligature([1], [[{ glyph: 9, rest: [2, 3] }, { glyph: 8, rest: [2] }]])] }])

# The first ligature of the set that matches wins; an incomplete one at the
# end of the run does not apply.
expect shaped(ligature_table, [1, 2, 3]) == [9]
expect shaped(ligature_table, [1, 2, 4]) == [8, 4]
expect shaped(ligature_table, [1, 2]) == [8]
expect shaped(ligature_table, [1]) == [1]
expect shaped(ligature_table, [0, 1, 2, 3, 1, 2, 3]) == [0, 9, 9]
expect shaped_items(ligature_table, [7, 1, 2, 4]) == [{ glyph: 7, cluster: 0 }, { glyph: 8, cluster: 1 }, { glyph: 4, cluster: 3 }]

# A ligature with no components is a bad table.
expect !readable(all_active([{ kind: 4, subtables: [FontTest.pack([U16(1), Ref(FontTest.coverage1([1])), U16(1), Ref(FontTest.pack([U16(1), Ref(FontTest.pack([U16(9), U16(0)]))]))])] }]))

# ------------------------------------------------------------ context

# Format 1: glyph 1 then 2: add 10 to the first and replace the second.
expect {
	gsub = first_active([{ kind: 5, subtables: [FontTest.context1([1], [[FontTest.rule([2], [{ at: 0, lookup: 1 }, { at: 1, lookup: 2 }])]])] }].concat(called_lookups))
	shaped(gsub, [1, 2, 1, 3, 2]) == [11, 20, 1, 3, 2]
}

# Rules are tried in order; the first that matches applies.
expect {
	gsub = first_active([{ kind: 5, subtables: [FontTest.context1([1], [[FontTest.rule([3], [{ at: 0, lookup: 1 }]), FontTest.rule([2], [{ at: 1, lookup: 2 }])]])] }].concat(called_lookups))
	shaped(gsub, [1, 2, 1, 3]) == [1, 20, 11, 3]
}

# Format 2: glyphs 1 and 2 are class 1, glyph 3 class 2. Class 1 followed
# by class 2: add 10 to the class 2 glyph. Class 0 has no rules.
expect {
	classes = FontTest.classes1(1, [1, 1, 2])
	gsub = first_active([{ kind: 5, subtables: [FontTest.context2([1, 2, 3], classes, [[], [FontTest.rule([2], [{ at: 1, lookup: 1 }])]])] }].concat(called_lookups))
	shaped(gsub, [1, 3, 2, 3, 3, 4, 3]) == [1, 13, 2, 13, 3, 4, 3]
}

# Format 3: a coverage per position.
expect {
	gsub = first_active([{ kind: 5, subtables: [FontTest.context3([[1, 2], [3]], [{ at: 0, lookup: 1 }])] }].concat(called_lookups))
	shaped(gsub, [2, 3, 1, 1, 3]) == [12, 3, 1, 11, 3]
}

# Context of format 3 with no input is a bad table.
expect !readable(first_active([{ kind: 5, subtables: [FontTest.context3([], [])] }]))

# ------------------------------------------------------------ chained context

# Format 1: after 7, the pair 1 2, before 3: add 10 to the 2.
chained_glyphs : List(U8)
chained_glyphs = first_active([{ kind: 6, subtables: [FontTest.chain1([1], [[FontTest.chain_rule([7], [2], [3], [{ at: 1, lookup: 1 }])]])] }].concat(called_lookups))

expect shaped(chained_glyphs, [7, 1, 2, 3]) == [7, 1, 12, 3]
expect shaped(chained_glyphs, [1, 2, 3]) == [1, 2, 3]
expect shaped(chained_glyphs, [7, 1, 2, 4]) == [7, 1, 2, 4]
expect shaped(chained_glyphs, [7, 1, 2]) == [7, 1, 2]

# Backtrack is listed nearest first.
expect {
	gsub = first_active([{ kind: 6, subtables: [FontTest.chain1([1], [[FontTest.chain_rule([7, 8], [], [], [{ at: 0, lookup: 1 }])]])] }].concat(called_lookups))
	shaped(gsub, [8, 7, 1, 7, 8, 1]) == [8, 7, 11, 7, 8, 1]
}

# Backtrack reads the glyphs already substituted by the same lookup.
expect {
	gsub = first_active([{ kind: 6, subtables: [FontTest.chain3([[11]], [[1]], [], [{ at: 0, lookup: 1 }])] }, { kind: 1, subtables: [FontTest.single1([1], 10)] }])
	shaped(gsub, [11, 1, 1, 1]) == [11, 11, 11, 11]
}

# Format 2: glyph 7 is backtrack class 1; glyphs 1 and 2 input classes 1
# and 2; glyph 3 lookahead class 1.
expect {
	gsub = first_active([{ kind: 6, subtables: [FontTest.chain2([1], FontTest.classes1(7, [1]), FontTest.classes2([{ first: 1, last: 1, class: 1 }, { first: 2, last: 2, class: 2 }]), FontTest.classes1(3, [1]), [[], [FontTest.chain_rule([1], [2], [1], [{ at: 0, lookup: 1 }])]])] }].concat(called_lookups))
	shaped(gsub, [7, 1, 2, 3, 8, 1, 2, 3]) == [7, 11, 2, 3, 8, 1, 2, 3]
}

# Format 3: coverages for backtrack, input and lookahead; two lookup
# records.
expect {
	gsub = first_active([{ kind: 6, subtables: [FontTest.chain3([[7]], [[1], [2]], [[3]], [{ at: 0, lookup: 1 }, { at: 1, lookup: 1 }])] }].concat(called_lookups))
	shaped(gsub, [7, 1, 2, 3, 1, 2, 3]) == [7, 11, 12, 3, 1, 2, 3]
}

# A record that points past the matched input is ignored.
expect {
	gsub = first_active([{ kind: 6, subtables: [FontTest.chain3([], [[1]], [], [{ at: 5, lookup: 1 }, { at: 0, lookup: 2 }])] }].concat(called_lookups))
	shaped(gsub, [1, 1]) == [1, 1]
}

# A nested ligature shortens the input; a nested multiple substitution
# lengthens it, and later records see the new positions.
expect {
	gsub = first_active([
		{ kind: 6, subtables: [FontTest.chain3([], [[1], [2], [3]], [], [{ at: 0, lookup: 1 }, { at: 1, lookup: 2 }])] },
		{ kind: 4, subtables: [FontTest.ligature([1], [[{ glyph: 9, rest: [2] }]])] },
		{ kind: 1, subtables: [FontTest.single2([3], [30])] },
	])
	shaped(gsub, [1, 2, 3, 4]) == [9, 30, 4]
}
expect {
	gsub = first_active([
		{ kind: 6, subtables: [FontTest.chain3([], [[1], [2]], [], [{ at: 0, lookup: 1 }, { at: 3, lookup: 2 }])] },
		{ kind: 2, subtables: [FontTest.multiple([1], [[5, 5, 5]])] },
		{ kind: 1, subtables: [FontTest.single2([2], [20])] },
	])
	shaped(gsub, [1, 2, 4]) == [5, 5, 5, 20, 4]
}

# Nested substitutions in the middle of a run keep the glyphs before and
# after the matched input, with their clusters; a nested multiple
# substitution may also delete its glyph.
expect {
	gsub = first_active([
		{ kind: 6, subtables: [FontTest.chain3([], [[1], [2]], [], [{ at: 0, lookup: 1 }])] },
		{ kind: 4, subtables: [FontTest.ligature([1], [[{ glyph: 9, rest: [2] }]])] },
	])
	shaped_items(gsub, [5, 1, 2, 6, 1, 2]) == [{ glyph: 5, cluster: 0 }, { glyph: 9, cluster: 1 }, { glyph: 6, cluster: 3 }, { glyph: 9, cluster: 4 }]
}
expect {
	gsub = first_active([
		{ kind: 6, subtables: [FontTest.chain3([], [[1], [2]], [], [{ at: 0, lookup: 1 }])] },
		{ kind: 2, subtables: [FontTest.multiple([1], [[3, 4, 5]])] },
	])
	shaped_items(gsub, [5, 1, 2, 6]) == [{ glyph: 5, cluster: 0 }, { glyph: 3, cluster: 1 }, { glyph: 4, cluster: 1 }, { glyph: 5, cluster: 1 }, { glyph: 2, cluster: 2 }, { glyph: 6, cluster: 3 }]
}
expect {
	gsub = first_active([
		{ kind: 6, subtables: [FontTest.chain3([], [[1], [2]], [], [{ at: 0, lookup: 1 }, { at: 0, lookup: 2 }])] },
		{ kind: 2, subtables: [FontTest.multiple([1], [[]])] },
		{ kind: 1, subtables: [FontTest.single2([2], [20])] },
	])
	shaped(gsub, [5, 1, 2, 6]) == [5, 20, 6]
}

# A contextual rule reached from another rule reads backtrack only within
# the outer rule's matched input: here glyph 7 lies before it, so the inner
# rule does not match; when 7 is part of the outer input, it does.
expect {
	inner = [
		{ kind: 6, subtables: [FontTest.chain3([[7]], [[1]], [], [{ at: 0, lookup: 2 }])] },
		{ kind: 1, subtables: [FontTest.single1([1], 10)] },
	]
	outside = first_active([{ kind: 6, subtables: [FontTest.chain3([], [[1]], [], [{ at: 0, lookup: 1 }])] }].concat(inner))
	within = first_active([{ kind: 6, subtables: [FontTest.chain3([], [[7], [1]], [], [{ at: 1, lookup: 1 }])] }].concat(inner))
	shaped(outside, [7, 1]) == [7, 1] and shaped(within, [7, 1]) == [7, 11]
}

# ------------------------------------------------------------ extension

expect shaped(all_active([{ kind: 7, subtables: [FontTest.extension(1, FontTest.single1([5], 10))] }]), [5, 6]) == [15, 6]
expect {
	gsub = first_active([{ kind: 7, subtables: [FontTest.extension(6, FontTest.chain3([], [[1]], [[2]], [{ at: 0, lookup: 1 }]))] }, { kind: 7, subtables: [FontTest.extension(1, FontTest.single1([1], 10))] }])
	shaped(gsub, [1, 2, 1]) == [11, 2, 1]
}

# An extension subtable past the table is a bad table.
expect !readable(all_active([{ kind: 7, subtables: [FontTest.pack([U16(1), U16(1), U32(100000)])] }]))

# Alternate (3) and reverse chaining (8) lookups are not applied by
# default; neither is an extension of them.
expect shaped(all_active([{ kind: 3, subtables: [FontTest.single1([5], 10)] }, { kind: 8, subtables: [FontTest.single1([5], 10)] }, { kind: 7, subtables: [FontTest.extension(3, FontTest.single1([5], 10))] }]), [5]) == [5]

# ------------------------------------------------------------ features

# Only the features a browser applies by default to left-to-right text
# apply: not small capitals, discretionary ligatures, right-to-left forms,
# or features of other tables.
expect {
	tags = ["rvrn", "ltra", "ltrm", "ccmp", "locl", "rlig", "liga", "clig", "calt", "rclt", "smcp", "dlig", "rtla", "rtlm", "kern", "mark"]
	lookups = tags.map(|_| { kind: 1, subtables: [FontTest.single1(FontTest.counting(200), 1)] })
	features = tags.map_with_index(|tag, i| { tag, lookups: [i] })
	shaped(FontTest.layout("latn", features, lookups), [5]) == [15]
}

# Lookups apply in lookup order, not feature order; a lookup listed by
# two features applies once.
expect {
	lookups = [{ kind: 1, subtables: [FontTest.single2([5], [6])] }, { kind: 1, subtables: [FontTest.single2([6], [7])] }]
	shaped(FontTest.layout("latn", [{ tag: "liga", lookups: [1, 0] }, { tag: "calt", lookups: [0] }], lookups), [5]) == [7]
}

# The default script is used when there is no Latin one; other scripts are
# not.
expect shaped(FontTest.layout("DFLT", [{ tag: "liga", lookups: [0] }], [{ kind: 1, subtables: [FontTest.single1([5], 1)] }]), [5]) == [6]
expect shaped(FontTest.layout("cyrl", [{ tag: "liga", lookups: [0] }], [{ kind: 1, subtables: [FontTest.single1([5], 1)] }]), [5]) == [5]

# Only the features the default language lists apply, and its required
# feature.
expect {
	lookups = [{ kind: 1, subtables: [FontTest.single1([5], 1)] }, { kind: 1, subtables: [FontTest.single1(FontTest.counting(200), 10)] }]
	features = [{ tag: "liga", lookups: [0] }, { tag: "calt", lookups: [1] }]
	shaped(FontTest.layout_listing("latn", [1], 0xFFFF, features, lookups), [5]) == [15] and shaped(FontTest.layout_listing("latn", [], 0, features, lookups), [5]) == [6]
}

# A listed feature past the feature list is a bad table; a feature's
# lookup past the lookup list is ignored.
expect !readable(FontTest.layout_listing("latn", [3], 0xFFFF, [{ tag: "liga", lookups: [0] }], [{ kind: 1, subtables: [FontTest.single1([5], 1)] }]))
expect shaped(FontTest.layout("latn", [{ tag: "liga", lookups: [0, 7] }], [{ kind: 1, subtables: [FontTest.single1([5], 1)] }]), [5]) == [6]

# A lookup reached only from a rule does not apply on its own; one that a
# rule calls past the lookup list is a bad table.
expect shaped(first_active([{ kind: 5, subtables: [FontTest.context3([[1]], [{ at: 0, lookup: 1 }])] }].concat(called_lookups)), [5, 2]) == [5, 2]
expect !readable(first_active([{ kind: 5, subtables: [FontTest.context3([[1]], [{ at: 0, lookup: 9 }])] }]))

# ------------------------------------------------------------ edge cases

expect shaped(all_active([{ kind: 1, subtables: [FontTest.single1([5], 1)] }]), []) == []
expect FontShape.apply(FontShape.none, items_of([1, 2, 3])) == items_of([1, 2, 3])

# Glyph indices no font has pass through every kind of lookup.
expect {
	gsub = all_active([
		{ kind: 1, subtables: [FontTest.single1([5], 1)] },
		{ kind: 2, subtables: [FontTest.multiple([5], [[1, 2]])] },
		{ kind: 4, subtables: [FontTest.ligature([1], [[{ glyph: 9, rest: [2] }]])] },
		{ kind: 6, subtables: [FontTest.chain3([[1]], [[2]], [[3]], [])] },
	])
	shaped(gsub, [70000, 1000000000, 0xFFFFFFFFFFFFFFFF]) == [70000, 1000000000, 0xFFFFFFFFFFFFFFFF]
}

# Lookups that call themselves stop at a fixed depth.
expect {
	gsub = first_active([{ kind: 5, subtables: [FontTest.context3([FontTest.counting(40)], [{ at: 0, lookup: 0 }, { at: 0, lookup: 1 }])] }].concat(called_lookups))
	result = shaped(gsub, [1])
	result.len() == 1 and result != [99999]
}

## fuzz regression: lookups whose rules call each other many times over
## must not take time exponential in the depth. Each of these rules calls
## its own lookup 50 times; without a limit on nested applications, one
## glyph would take 50^7 of them.
expect {
	calls = List.repeat({ at: 0, lookup: 0 }, 50)
	gsub = first_active([{ kind: 5, subtables: [FontTest.context3([[1]], calls.append({ at: 0, lookup: 1 }))] }, { kind: 1, subtables: [FontTest.single1([1], 0)] }])
	shaped(gsub, [1, 1, 1]) == [1, 1, 1]
}

## fuzz regression: a contextual rule that calls a multiple substitution
## once per input glyph must not grow the run past 4 n + 32 glyphs; each
## rule could otherwise grow its own window to that size.
expect {
	gsub = first_active([{ kind: 6, subtables: [FontTest.chain3([], [[1]], [], [{ at: 0, lookup: 1 }])] }, { kind: 2, subtables: [FontTest.multiple([1], [List.repeat(2, 60)])] }])
	result = shaped(gsub, List.repeat(1, 20))
	result.len() <= 4 * 20 + 32
}

# Applying is deterministic.
expect {
	gsub = first_active([{ kind: 6, subtables: [FontTest.chain3([[7]], [[1], [2]], [[3]], [{ at: 0, lookup: 1 }, { at: 1, lookup: 2 }])] }].concat(called_lookups))
	shaped(gsub, [7, 1, 2, 3, 7, 1, 2, 3]) == shaped(gsub, [7, 1, 2, 3, 7, 1, 2, 3])
}

# ------------------------------------------------------------ reading

expect !readable([])
expect !readable(List.repeat(0, 9))
expect shaped(List.repeat(0, 10), [5]) == [5]
expect readable(FontTest.layout("latn", [], []))

# Unknown subtable, coverage and class formats, and coverage tables past
# the table.
expect !readable(all_active([{ kind: 1, subtables: [FontTest.patch(FontTest.single1([5], 1), 0, FontTest.u16(3))] }]))
expect !readable(all_active([{ kind: 5, subtables: [FontTest.patch(FontTest.context3([[1]], []), 0, FontTest.u16(4))] }]))
expect !readable(all_active([{ kind: 1, subtables: [FontTest.patch(FontTest.single1([5], 1), 2, FontTest.u16(60000))] }]))
expect !readable(all_active([{ kind: 1, subtables: [FontTest.pack([U16(1), Ref(FontTest.pack([U16(3), U16(0)])), I16(1)])] }]))
expect !readable(first_active([{ kind: 5, subtables: [FontTest.context2([1], FontTest.pack([U16(3)]), [])] }]))

# Coverage and class ranges that overlap or are out of order are read, as
# browsers read them (Noto Sans Adlam Unjoined has a coverage whose ranges
# share a glyph); lookups in them stay total and deterministic.
expect {
	gsub = all_active([{ kind: 1, subtables: [FontTest.pack([U16(1), Ref(FontTest.coverage2([{ first: 1, last: 6, index: 0 }, { first: 6, last: 19, index: 6 }])), I16(100)])] }])
	shaped(gsub, [1, 6, 19, 20]) == [101, 106, 119, 20]
}
expect {
	gsub = all_active([{ kind: 1, subtables: [FontTest.pack([U16(1), Ref(FontTest.coverage2([{ first: 5, last: 9, index: 0 }, { first: 2, last: 3, index: 5 }, { first: 12, last: 11, index: 0 }])), I16(1)])] }])
	result = shaped(gsub, [2, 5, 7, 11, 12])
	result.len() == 5 and result == shaped(gsub, [2, 5, 7, 11, 12])
}
expect readable(first_active([{ kind: 5, subtables: [FontTest.context2([1], FontTest.classes2([{ first: 5, last: 9, class: 1 }, { first: 9, last: 10, class: 2 }]), [])] }]))

## fuzz regression: a chained context of format 2 may leave its backtrack
## and lookahead class definitions out (a null offset), putting every
## glyph in class 0; Noto Music does. Reading the subtable itself as a
## class definition refused the whole table.
expect {
	sets = [U16(0), FontTest.rule_set([FontTest.chain_rule([0], [], [0], [{ at: 0, lookup: 1 }])])]
	subtable = FontTest.pack([U16(2), Ref(FontTest.coverage1([1])), U16(0), Ref(FontTest.classes1(1, [1])), U16(0), U16(2)].concat(sets))
	gsub = first_active([{ kind: 6, subtables: [subtable] }].concat(called_lookups))
	shaped(gsub, [7, 1, 8, 1]) == [7, 11, 8, 1]
}

# Every prefix of a table with every kind of lookup, and every byte of it
# set to 0 or 0xFF, is read or refused; what is read applies without
# growing past the bound.
every_kind : List(U8)
every_kind = FontTest.every_lookup

expect readable(every_kind)

expect {
	var $outcomes = 0
	for n in 0..<every_kind.len() {
		match FontShape.read(every_kind.take_first(n)) {
			Ok(shape) => {
				run = items_of([7, 1, 2, 3, 1, 2])
				$outcomes = $outcomes + (if (FontShape.apply(shape, run).len() <= 4 * 6 + 32) 1 else 1000000)
			}
			Err(_) => {
				$outcomes = $outcomes + 1
			}
		}
	}
	$outcomes == every_kind.len()
}

expect {
	var $outcomes = 0
	for at in 0..<every_kind.len() {
		for value in [0, 1, 0xFF] {
			match FontShape.read(every_kind.set(at, value) ?? []) {
				Ok(shape) => {
					run = items_of([7, 1, 2, 3, 1, 2, 0, 9])
					$outcomes = $outcomes + (if (FontShape.apply(shape, run).len() <= 4 * 8 + 32) 1 else 1000000)
				}
				Err(_) => {
					$outcomes = $outcomes + 1
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
	body = FontTest.pack(lookup_list.concat(lookup)).concat(FontTest.single1(FontTest.counting(10), 1))
	features = FontTest.pack([U16(1), Tag("liga"), U16(8), U16(0), U16(count)].concat(FontTest.counting(count).map(|i| U16(i))))
	language = FontTest.pack([U16(0), U16(0xFFFF), U16(1), U16(0)])
	scripts = FontTest.pack([U16(1), Tag("latn"), Ref(FontTest.pack([Ref(language), U16(0)]))])
	header = FontTest.pack([U32(0x00010000), Ref(scripts), Ref(features), Ref(body)])
	!readable(header)
}

# The same sharing on a small scale is read.
expect {
	count = 3
	lookup_list = [U16(count)].concat(List.repeat(U16(2 + 2 * count), count))
	lookup = [U16(1), U16(0), U16(count)].concat(List.repeat(U16(6 + 2 * count), count))
	body = FontTest.pack(lookup_list.concat(lookup)).concat(FontTest.single1(FontTest.counting(10), 1))
	features = FontTest.pack([U16(1), Tag("liga"), U16(8), U16(0), U16(count)].concat(FontTest.counting(count).map(|i| U16(i))))
	language = FontTest.pack([U16(0), U16(0xFFFF), U16(1), U16(0)])
	scripts = FontTest.pack([U16(1), Tag("latn"), Ref(FontTest.pack([Ref(language), U16(0)]))])
	shaped(FontTest.pack([U32(0x00010000), Ref(scripts), Ref(features), Ref(body)]), [5]) == [8]
}
