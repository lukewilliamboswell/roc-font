import font.Font
import build.FontBuild

## Tests of pair positioning under lookup flags, through the public `Font`
## API: a `GPOS` pair adjustment lookup that ignores base glyphs,
## ligatures or marks, keeps only the marks of a mark filtering set or of
## a mark attachment type, finds its pair across the glyphs it ignores and
## across default-ignorable characters, as HarfBuzz's skipping iterator
## finds it; and a TrueType `kern` table, which HarfBuzz applies ignoring
## marks. The fonts are built from `FontBuild.sixty_four` with
## `FontBuild.marks_gdef`: glyphs 1 to 4 are base glyphs, 5 and 6 marks
## (attachment classes 1 and 2, glyph 5 alone in mark glyph set 0), 7 a
## ligature. Expected runs are HarfBuzz 14.6.0's (uharfbuzz 0.56.3) for
## exactly these font files. Run with `roc test tests/api/main.roc`.
GposFlagTests :: {}.{

	## Every case: the font file, the glyphs of its text (0 stands for
	## U+200D ZERO WIDTH JOINER) and the weight it is shaped at (0 for the
	## default, Regular), in the order of `expected`.
	cases : List({ name : Str, font : List(U8), text : List(U64), weight : U64 })
	cases = [
		{ name: "no flag: a mark blocks the pair", font: GposFlagTests.gpos(0, 0), text: [1, 5, 2], weight: 0 },
		{ name: "ignore marks: across one mark", font: GposFlagTests.gpos(0x08, 0), text: [1, 5, 2], weight: 0 },
		{ name: "ignore marks: across two marks", font: GposFlagTests.gpos(0x08, 0), text: [1, 5, 6, 2], weight: 0 },
		{ name: "mark filtering set: its mark blocks", font: GposFlagTests.gpos(0x10, 0), text: [1, 5, 2], weight: 0 },
		{ name: "mark filtering set: another mark is skipped", font: GposFlagTests.gpos(0x10, 0), text: [1, 6, 2], weight: 0 },
		{ name: "mark attachment type: another class is skipped", font: GposFlagTests.gpos(0x0100, 0), text: [1, 6, 2], weight: 0 },
		{ name: "mark attachment type: its class blocks", font: GposFlagTests.gpos(0x0100, 0), text: [1, 5, 2], weight: 0 },
		{ name: "ignore base glyphs: marks pair across a base", font: GposFlagTests.gpos(0x02, 0), text: [5, 1, 6], weight: 0 },
		{ name: "ignore base glyphs: no base starts a pair", font: GposFlagTests.gpos(0x02, 0), text: [1, 2], weight: 0 },
		{ name: "ignore ligatures: across a ligature", font: GposFlagTests.gpos(0x04, 0), text: [1, 7, 2], weight: 0 },
		{ name: "ignore marks: no mark starts a pair", font: GposFlagTests.gpos(0x08, 0), text: [5, 6], weight: 0 },
		{ name: "no flag: marks pair", font: GposFlagTests.gpos(0, 0), text: [5, 6], weight: 0 },
		{ name: "no flag: across a joiner", font: GposFlagTests.gpos(0, 0), text: [1, 0, 2], weight: 0 },
		{ name: "missing mark filtering set: the flag is off", font: GposFlagTests.gpos(0x18, 7), text: [1, 5, 2], weight: 0 },
		{ name: "ignore marks with a filtering set", font: GposFlagTests.gpos(0x18, 0), text: [1, 5, 2], weight: 0 },
		{ name: "extension lookup ignoring marks", font: GposFlagTests.extended(0x08), text: [1, 5, 2], weight: 0 },
		{ name: "class pairs ignoring marks", font: GposFlagTests.classes(0x08), text: [1, 5, 2, 6, 1], weight: 0 },
		{ name: "second value record moves past the pair", font: GposFlagTests.both(0x08), text: [1, 5, 2, 1, 2], weight: 0 },
		{ name: "kern table: across marks", font: GposFlagTests.legacy, text: [1, 5, 6, 2], weight: 0 },
		{ name: "kern table: a leading mark", font: GposFlagTests.legacy, text: [5, 1, 2], weight: 0 },
		{ name: "feature variations: the default lookup", font: GposFlagTests.varied, text: [1, 2, 1, 5, 2], weight: 0 },
		{ name: "feature variations: a lookup only an alternate lists", font: GposFlagTests.varied, text: [1, 2, 1, 5, 2], weight: 900 },
	]

	## Pairs 1 + 2 (-100 on the first glyph's advance) and 5 + 6 (-40 on
	## the first glyph's x placement, since mark advances become zero).
	pairs : List(U8)
	pairs = FontBuild.pair1(5, 0, [{ glyph: 1, pairs: [{ second: 2, values: [0, -100] }] }, { glyph: 5, pairs: [{ second: 6, values: [-40, 0] }] }])

	font_with : List({ tag : Str, data : List(U8) }) -> List(U8)
	font_with = |extra| FontBuild.file(FontBuild.sixty_four.concat([{ tag: "GDEF", data: FontBuild.marks_gdef }]).concat(extra))

	kern_lookup : U64, U64, List(U8) -> List(U8)
	kern_lookup = |flag, set, subtable| FontBuild.flagged_layout("kern", [{ kind: 2, flag, set, subtables: [subtable] }])

	## `pairs` in a `kern` lookup with a flag and mark filtering set.
	gpos : U64, U64 -> List(U8)
	gpos = |flag, set| GposFlagTests.font_with([{ tag: "GPOS", data: GposFlagTests.kern_lookup(flag, set, GposFlagTests.pairs) }])

	## `pairs` through an extension lookup.
	extended : U64 -> List(U8)
	extended = |flag| GposFlagTests.font_with([{ tag: "GPOS", data: FontBuild.flagged_layout("kern", [{ kind: 9, flag, set: 0, subtables: [FontBuild.extension(2, GposFlagTests.pairs)] }]) }])

	## Class pairs: first class 1 is glyph 1, second class 1 glyph 2 (-100)
	## and second class 2 glyph 6 (-30).
	classes : U64 -> List(U8)
	classes = |flag| {
		subtable = FontBuild.pair2(4, 0, FontBuild.coverage1([1, 2]), FontBuild.classes2([{ first: 1, last: 1, class: 1 }]), FontBuild.classes2([{ first: 2, last: 2, class: 1 }, { first: 6, last: 6, class: 2 }]), 2, 3, [0, 0, 0, 0, -100, -30])
		GposFlagTests.font_with([{ tag: "GPOS", data: GposFlagTests.kern_lookup(flag, 0, subtable) }])
	}

	## Pair 1 + 2 with a value record for each glyph (-100 and 7 on the
	## advances), so the lookup moves past the second glyph.
	both : U64 -> List(U8)
	both = |flag| GposFlagTests.font_with([{ tag: "GPOS", data: GposFlagTests.kern_lookup(flag, 0, FontBuild.pair1(4, 4, [{ glyph: 1, pairs: [{ second: 2, values: [-100, 7] }] }])) }])

	## A `kern` table with pairs 1 + 2 (-100) and 5 + 1 (-60), and no `GPOS`.
	legacy : List(U8)
	legacy = GposFlagTests.font_with([{ tag: "kern", data: FontBuild.kern([{ coverage: 1, pairs: [{ left: 1, right: 2, value: -100 }, { left: 5, right: 1, value: -60 }] }]) }])

	## A variable font (`wght` 100 to 900, default 400) whose `kern` feature
	## uses lookup 0 (`pairs`, no flag) and, from half way to the heaviest
	## weight, only lookup 1 (pair 1 + 2 at -300, ignoring marks), which no
	## feature lists outside `FeatureVariations`.
	varied : List(U8)
	varied = {
		heavy = FontBuild.pair1(4, 0, [{ glyph: 1, pairs: [{ second: 2, values: [-300] }] }])
		lookups = [{ kind: 2, flag: 0, set: 0, subtables: [GposFlagTests.pairs] }, { kind: 2, flag: 0x08, set: 0, subtables: [heavy] }]
		variations = FontBuild.feature_variations([{ conditions: [{ axis: 0, min: 8192, max: 16384 }], substitutions: [{ feature: 0, lookups: [1] }] }])
		GposFlagTests.font_with([{ tag: "fvar", data: FontBuild.fvar([{ tag: "wght", min: 100, default: 400, max: 900 }]) }, { tag: "GPOS", data: FontBuild.flagged_layout_varied("kern", [0], lookups, variations) }])
	}

	## The text of glyphs (glyph g draws U+10000 + g; 0 is U+200D).
	text_of : List(U64) -> Str
	text_of = |glyphs| {
		var $bytes = []
		for g in glyphs {
			$bytes = $bytes.concat(
				if g == 0 {
					[0xE2, 0x80, 0x8D]
				} else {
					c = 0x10000 + g
					[0xF0 + c.shr_zf_wrap(18), 0x80 + c.shr_zf_wrap(12).bitwise_and(0x3F), 0x80 + c.shr_zf_wrap(6).bitwise_and(0x3F), 0x80 + c.bitwise_and(0x3F)].map(|b| b.to_u8_wrap())
				},
			)
		}
		Str.from_utf8($bytes) ?? ""
	}

	## A shaped run as HarfBuzz's serialisation without names:
	## `glyph=cluster@x_offset,y_offset+x_advance` separated by `|`.
	serialized : List(U8), List(U64), U64 -> Str
	serialized = |file, glyphs, weight|
		match Font.from_bytes(file, Font.ReadOptions.{}) {
			Err(_) => "unreadable"
			Ok(read) => {
				font = if (weight == 0) read else Font.at(read, Font.Variation.{ weight: Weight(weight.to_u16_wrap()) })
				run = Font.shape(font, GposFlagTests.text_of(glyphs), Font.ShapeOptions.{})
				var $parts = []
				for i in 0..<run.glyphs.len() {
					offset = run.offsets.get(i) ?? { x: 0, y: 0 }
					placed = if (offset.x == 0 and offset.y == 0) "" else "@${offset.x.to_str()},${offset.y.to_str()}"
					$parts = $parts.append("${(run.glyphs.get(i) ?? 0).to_str()}=${(run.clusters.get(i) ?? 0).to_str()}${placed}+${((run.advances.get(i) ?? { x: 0, y: 0 }).x).to_str()}")
				}
				"[${Str.join_with($parts, "|")}]"
			}
		}

	## HarfBuzz's runs for `cases`, in order.
	expected : List(Str)
	expected = [
		"[1=0+500|5=4+0|2=8+500]",
		"[1=0+400|5=4+0|2=8+500]",
		"[1=0+400|5=4+0|6=8+0|2=12+500]",
		"[1=0+500|5=4+0|2=8+500]",
		"[1=0+400|6=4+0|2=8+500]",
		"[1=0+400|6=4+0|2=8+500]",
		"[1=0+500|5=4+0|2=8+500]",
		"[5=0@-40,0+0|1=4+500|6=8+0]",
		"[1=0+500|2=4+500]",
		"[1=0+400|7=4+500|2=8+500]",
		"[5=0+0|6=4+0]",
		"[5=0@-40,0+0|6=4+0]",
		"[1=0+400|3=0+0|2=7+500]",
		"[1=0+400|5=4+0|2=8+500]",
		"[1=0+400|5=4+0|2=8+500]",
		"[1=0+400|5=4+0|2=8+500]",
		"[1=0+400|5=4+0|2=8+500|6=12+0|1=16+500]",
		"[1=0+400|5=4+0|2=8+507|1=12+400|2=16+507]",
		"[1=0+450|5=4@-500,0+0|6=8@-500,0+0|2=12@-50,0+450]",
		"[5=0@-470,0+0|1=4@-30,0+420|2=8@-50,0+450]",
		"[1=0+400|2=4+500|1=8+500|5=12+0|2=16+500]",
		"[1=0+200|2=4+500|1=8+200|5=12+0|2=16+500]",
	]
}

expect GposFlagTests.cases.len() == GposFlagTests.expected.len()

# Every case agrees with HarfBuzz; a failure lists the cases that differ.
expect {
	var $differ = []
	for i in 0..<GposFlagTests.cases.len() {
		c = GposFlagTests.cases.get(i) ?? { name: "", font: [], text: [], weight: 0 }
		if GposFlagTests.serialized(c.font, c.text, c.weight) != (GposFlagTests.expected.get(i) ?? "") {
			$differ = $differ.append(c.name)
		}
	}
	$differ == []
}
