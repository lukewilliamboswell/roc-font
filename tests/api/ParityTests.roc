import font.Font
import build.FontBuild
import "../../tests/cases/parity/rand-plain.ttf" as rand_plain_file : List(U8)
import "../../tests/cases/parity/rand-after-ligature.ttf" as rand_after_ligature_file : List(U8)
import "../../tests/cases/parity/rand-after-multiple.ttf" as rand_after_multiple_file : List(U8)
import "../../tests/cases/parity/rand-multiple-ligature.ttf" as rand_multiple_ligature_file : List(U8)
import "../../tests/cases/parity/rand-ligature-multiple.ttf" as rand_ligature_multiple_file : List(U8)
import "../../tests/cases/parity/rand-after-liga.ttf" as rand_after_liga_file : List(U8)

## Tests where roc-font computes a result differently from HarfBuzz but
## must agree with it bit for bit, through the public `Font` API. Expected
## values are HarfBuzz 14.6.0's (uharfbuzz 0.56.3) for the same font bytes.
## Run with `roc test tests/api/main.roc`.
ParityTests :: {}.{}

# ------------------------------------------------------------ rand
#
# `rand` (on by default) picks an alternate of glyph 1 (20, 21 or 22) and
# marks the whole run unsafe to break. HarfBuzz writes its output over its
# input until a multiple substitution needs room, so glyphs already output
# in the same lookup are marked only while that has not happened. The fonts
# are `FontBuild.rand_fonts`; the committed copies, which the conformance
# cases in tests/cases/parity.jsonc shape, are the same bytes.

expect {
	committed = [
		("rand-plain", rand_plain_file),
		("rand-after-ligature", rand_after_ligature_file),
		("rand-after-multiple", rand_after_multiple_file),
		("rand-multiple-ligature", rand_multiple_ligature_file),
		("rand-ligature-multiple", rand_ligature_multiple_file),
		("rand-after-liga", rand_after_liga_file),
	]
	committed.len() == FontBuild.rand_fonts.len()
		and committed.all(|(name, bytes)| FontBuild.rand_fonts.any(|f| f.name == name and f.data == bytes))
}

text_of : List(U64) -> Str
text_of = |glyphs| {
	var $bytes = []
	for g in glyphs {
		c = 0x10000 + g
		$bytes = $bytes.concat([0xF0 + c.shr_zf_wrap(18), 0x80 + c.shr_zf_wrap(12).bitwise_and(0x3F), 0x80 + c.shr_zf_wrap(6).bitwise_and(0x3F), 0x80 + c.bitwise_and(0x3F)].map(|b| b.to_u8_wrap()))
	}
	Str.from_utf8($bytes) ?? ""
}

Shaped : { glyphs : List(U32), clusters : List(U64), flags : List(U8) }

## The run of glyphs `input` (glyph g as U+10000 + g) in the named font.
shaped : Str, List(U64) -> Shaped
shaped = |name, input| {
	bytes = FontBuild.rand_fonts.find_first(|f| f.name == name).map_ok(|f| f.data) ?? []
	match Font.from_bytes(bytes, Font.ReadOptions.{}) {
		Ok(font) => {
			run = Font.shape(font, text_of(input), Font.ShapeOptions.{})
			{ glyphs: run.glyphs, clusters: run.clusters, flags: run.flags }
		}
		Err(_) => { glyphs: [], clusters: [], flags: [] }
	}
}

# Glyphs output before the alternate in its lookup are marked too.
expect shaped("rand-plain", [1]) == { glyphs: [21], clusters: [0], flags: [0] }
expect shaped("rand-plain", [2, 3, 1]) == { glyphs: [2, 3, 21], clusters: [0, 4, 8], flags: [0, 1, 1] }
expect shaped("rand-plain", [2, 3, 1, 1]) == { glyphs: [2, 3, 21, 20], clusters: [0, 4, 8, 12], flags: [0, 1, 1, 1] }
expect shaped("rand-plain", [1, 2, 3, 1, 4]) == { glyphs: [21, 2, 3, 20, 4], clusters: [0, 4, 8, 12, 16], flags: [0, 1, 1, 1, 1] }
expect shaped("rand-plain", [7, 8, 1, 8, 7, 1]) == { glyphs: [7, 8, 21, 8, 7, 20], clusters: [0, 4, 8, 12, 16, 20], flags: [0, 1, 1, 1, 1, 1] }

# Up to 255 glyphs, the whole run is marked; past that, nothing.
expect {
	run = shaped("rand-plain", List.repeat(2, 254).append(1))
	run.glyphs == List.repeat(2, 254).append(21) and run.flags == [0].concat(List.repeat(1, 254))
}
expect {
	run = shaped("rand-plain", List.repeat(2, 255).append(1))
	run.glyphs == List.repeat(2, 255).append(21) and run.flags == List.repeat(0, 256)
}

# A ligature before the alternate in the same lookup (through a contextual
# rule) shortens the output; it is marked.
expect shaped("rand-after-ligature", [2, 3, 1]) == { glyphs: [9, 21], clusters: [0, 8], flags: [0, 1] }
expect shaped("rand-after-ligature", [7, 2, 3, 1, 8]) == { glyphs: [7, 9, 21, 8], clusters: [0, 4, 12, 16], flags: [0, 1, 1, 1] }
expect shaped("rand-after-ligature", [7, 8, 2, 3, 1, 1, 8]) == { glyphs: [7, 8, 9, 21, 1, 8], clusters: [0, 4, 8, 16, 20, 24], flags: [0, 1, 1, 1, 1, 1] }

# After a multiple substitution in the same lookup, the output is apart
# from the input and is not marked.
expect shaped("rand-after-multiple", [2, 1]) == { glyphs: [4, 5, 21], clusters: [0, 0, 4], flags: [0, 0, 1] }
expect shaped("rand-after-multiple", [7, 2, 1, 8]) == { glyphs: [7, 4, 5, 21, 8], clusters: [0, 4, 4, 8, 12], flags: [0, 0, 0, 1, 1] }
expect shaped("rand-after-multiple", [7, 8, 2, 1, 1, 8]) == { glyphs: [7, 8, 4, 5, 21, 1, 8], clusters: [0, 4, 8, 8, 12, 16, 20], flags: [0, 0, 0, 0, 1, 1, 1] }

# A ligature after the multiple substitution makes the run as long as its
# input again; the output stays apart.
expect shaped("rand-multiple-ligature", [2, 3, 6, 1]) == { glyphs: [4, 5, 9, 21], clusters: [0, 0, 4, 12], flags: [0, 0, 1, 1] }
expect shaped("rand-multiple-ligature", [7, 2, 3, 6, 1, 8]) == { glyphs: [7, 4, 5, 9, 21, 8], clusters: [0, 4, 4, 8, 16, 20], flags: [0, 0, 0, 1, 1, 1] }
expect shaped("rand-multiple-ligature", [7, 8, 2, 3, 6, 1, 1]) == { glyphs: [7, 8, 4, 5, 9, 21, 1], clusters: [0, 4, 8, 8, 12, 20, 24], flags: [0, 0, 0, 0, 1, 1, 1] }

# A multiple substitution after a ligature ends as long as its input, but
# its second glyph needed room: the output is apart.
expect shaped("rand-ligature-multiple", [2, 3, 6, 1]) == { glyphs: [9, 4, 5, 21], clusters: [0, 8, 8, 12], flags: [0, 1, 1, 1] }
expect shaped("rand-ligature-multiple", [7, 2, 3, 6, 1, 8]) == { glyphs: [7, 9, 4, 5, 21, 8], clusters: [0, 4, 12, 12, 16, 20], flags: [0, 0, 1, 1, 1, 1] }
expect shaped("rand-ligature-multiple", [7, 8, 2, 3, 6, 1, 1]) == { glyphs: [7, 8, 9, 4, 5, 21, 1], clusters: [0, 4, 8, 16, 16, 20, 24], flags: [0, 0, 0, 1, 1, 1, 1] }

# Substitutions in an earlier lookup (`liga`) start `rand`'s lookup afresh.
expect shaped("rand-after-liga", [2, 3, 1]) == { glyphs: [9, 21], clusters: [0, 8], flags: [0, 1] }
expect shaped("rand-after-liga", [7, 2, 3, 1, 8]) == { glyphs: [7, 9, 21, 8], clusters: [0, 4, 12, 16], flags: [0, 1, 1, 1] }
expect shaped("rand-after-liga", [1, 2, 3, 1]) == { glyphs: [21, 9, 20], clusters: [0, 4, 12], flags: [0, 1, 1] }

# ------------------------------------------------------------ device deltas
#
# A `VariationIndex` device's delta is a single-precision sum of region
# scalars times stored deltas, rounded by `floorf(v + 0.5f)`: ties round
# up (also when negative), deltas past 2^24 lose bits as single-precision
# numbers do, and a product can land just off a half, so the result can
# differ from the exactly rounded value. The units per em do not matter.
# Each font kerns glyph 1 before 2 by 0 plus one device's delta, at
# design value `coord` of an axis whose normalised coordinate is
# `coord` / 16384 (`FontBuild.device_delta_font`).

device_advance : U64, I64, List(I64), List(I64) -> I32
device_advance = |units, coord, peaks, deltas|
	match Font.from_bytes(FontBuild.device_delta_font(units, peaks, deltas), Font.ReadOptions.{}) {
		Ok(read) => {
			font = Font.at(read, Font.Variation.{ axes: [{ tag: "TEST", value: coord.to_dec() }] })
			(Font.shape(font, text_of([1, 2]), Font.ShapeOptions.{}).advances.get(0) ?? { x: 0, y: 0 }).x
		}
		Err(_) => 0
	}

# Ties at a scalar of exactly one half round up, also below zero.
expect device_advance(1000, 8192, [16384], [3]) == 502
expect device_advance(1000, 8192, [16384], [-3]) == 499
expect device_advance(2048, 8192, [16384], [-3]) == 499
expect device_advance(1950, 8192, [16384], [-3]) == 499
expect device_advance(1000, 8192, [16384], [8388609]) == 4194805
expect device_advance(1000, 8192, [16384], [-8388609]) == -4193804
expect device_advance(2048, 8192, [16384], [16777215]) == 8389108
expect device_advance(1950, 8192, [16384], [-16777215]) == -8388107
# Past 2^24 a stored delta rounds to an even single-precision number.
expect device_advance(1000, 8192, [16384], [16777217]) == 8389108
expect device_advance(1000, 8192, [16384], [16777219]) == 8389110
expect device_advance(1950, 8192, [16384], [33554431]) == 16777716
# Products just off a half: the exactly rounded deltas are -127, -293,
# 150, -47664396 and 9286667.
expect device_advance(1000, 102, [740], [-925]) == 372
expect device_advance(1950, 6, [672], [-32872]) == 206
expect device_advance(2048, 6, [12831], [319706]) == 649
expect device_advance(1000, 1236, [5307], [-204656110]) == -47663900
expect device_advance(2048, 11494, [11981], [9680142]) == 9287168
# Two regions, summed in single precision.
expect device_advance(1950, 12288, [16384, 8192], [-16777215, 16777215]) == -4193803
expect device_advance(1000, 16383, [16384, 16384], [1073741823, -1073741823]) == 500
