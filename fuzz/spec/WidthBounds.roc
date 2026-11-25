import build.FontBuild
import font.Font

# OpenType GPOS ValueRecords and the Item Variation Store. Both regions
# reach full strength at the selected location. roc-font accepts long
# deltas here, although OpenType recommends that form only for COLR.
# https://learn.microsoft.com/en-us/typography/opentype/spec/gpos#valuerecord
# https://learn.microsoft.com/en-us/typography/opentype/spec/otvarcommonformats#item-variation-store
WidthBounds := {}.{
	check : {} -> Bool
	check = |_| {
		font = fixture({})
		varied = Font.at(font, Font.Variation.{ weight: Black, width: UltraExpanded })
		plan = Font.plan(varied, Font.ShapeOptions.{})
		no_kern = Font.plan(varied, Font.ShapeOptions.{ features: [Font.Feature.{ tag: "kern", value: 0 }] })
		max = I32.highest
		min = I32.lowest
		zero = { x: 0, y: 0 }
		clipped = { x: max, y: min }
		# The mixed runs have the same total, 700 + 2 * (max + min),
		# even though their prefixes cross opposite signed limits.
		cases = [
			{ text: "DC", advances: [300, 700], offsets: [{ x: 13, y: 3 }, zero], width: 1000 },
			{ text: "AABBC", advances: [max, max, min, min, 700], offsets: [zero, zero, clipped, clipped, zero], width: 698 },
			{ text: "BBCAA", advances: [min, min, 700, max, max], offsets: [clipped, clipped, zero, zero, zero], width: 698 },
			{ text: "AA", advances: [max, max], offsets: [zero, zero], width: max },
			{ text: "BBC", advances: [min, min, 700], offsets: [clipped, clipped, zero], width: min },
		]
		for case in cases {
			run = Font.shape_planned(varied, plan, case.text)
			got = (run.advances, run.offsets, Font.width(varied, case.text), Font.width_planned(varied, plan, case.text))
			want = (case.advances.map(|x| { x, y: 0 }), case.offsets, case.width, case.width)
			if got != want {
				crash "wide advances for ${case.text} were ${Str.inspect(got)}. Expected ${Str.inspect(want)}"
			}
		}
		Font.advance(varied, 1) == max
			and Font.advance(varied, 2) == 100
			and Font.width(font, "AABBC") == 1900
			and Font.width(Font.at(font, Font.Variation.{ axes: [{ tag: "wght", value: 400.030517578125 }] }), "AABBC") == -129172
			and Font.width_planned(varied, no_kern, "AABBC") == max
	}
}

pair : U64, List(I64), List(U64) -> List(FontBuild.Field)
pair = |second, stored, rows| [U16(second)].concat(stored.map(|v| I16(v))).concat(rows.map(|row| FontBuild.device_field(Index(0, row))))

pair_table : List({ glyph : U64, pairs : List(List(FontBuild.Field)) }) -> List(U8)
pair_table = |sets| {
	# PairPos format 1, x/y placement and x advance with their devices.
	# Each device is relative to the PairSet that holds the record.
	coverage = FontBuild.coverage1(sets.map(|set| set.glyph))
	fields = [U16(1), Ref(coverage), U16(0x77), U16(0), U16(sets.len())]
	FontBuild.pack(fields.concat(sets.map(|set| Ref(FontBuild.pack([U16(set.pairs.len())].concat(set.pairs.join_map(|record| record)))))))
}

fixture : {} -> Font
fixture = |_| {
	ramp = { start: 0, peak: 16384, end: 16384 }
	neutral = { start: 0, peak: 0, end: 0 }
	regions = [[ramp, neutral], [neutral, ramp]]
	positive = [1073741824, 1073741824]
	negative = [-1073741824, -1073741824]
	very_negative = [-2147483648, -2147483648]
	zero = [0, 0]
	hvar = FontBuild.hvar(FontBuild.variation_store_long(2, regions, [zero, positive, zero, zero, zero]), [])
	gdef = FontBuild.gdef_store(FontBuild.variation_store_long(2, regions, [positive, negative, very_negative]))
	# B's signed adjustments exceed the public bounds. D's opposing
	# adjustments cancel across lookups, leaving its small stored offsets.
	first = pair_table([
		{ glyph: 2, pairs: [pair(2, [0, 0, 0], [0, 2, 2]), pair(3, [0, 0, 0], [0, 2, 2])] },
		{ glyph: 4, pairs: [pair(3, [3, -4, 17], [0, 1, 0])] },
	])
	second = pair_table([{ glyph: 4, pairs: [pair(3, [10, 7, -17], [1, 0, 1])] }])
	gpos = FontBuild.layout("latn", [{ tag: "kern", lookups: [0, 1] }], [{ kind: 2, subtables: [first] }, { kind: 2, subtables: [second] }])
	fvar = FontBuild.fvar([{ tag: "wght", min: 100, default: 400, max: 900 }, { tag: "wdth", min: 50, default: 100, max: 200 }])
	cmap = FontBuild.cmap([{ system: 3, encoding: 1, subtable: FontBuild.cmap4([{ first: 'A', last: 'D', delta: 65536 - 64, glyphs: [] }]) }])
	bytes = FontBuild.glyphs_font([500, 500, 100, 700, 300], cmap, [{ tag: "fvar", data: fvar }, { tag: "HVAR", data: hvar }, { tag: "GDEF", data: gdef }, { tag: "GPOS", data: gpos }])
	Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "valid width fixture did not read strictly"
}
