import font.Font
import "../../tests/fonts/variable-layout/kern-var.ttf" as kern_file : List(U8)
import "../../tests/fonts/variable/var-outlines.ttf" as outlines_file : List(U8)
import "../../tests/fonts/variable/var-mapped.ttf" as mapped_file : List(U8)

## The tests of variable fonts away from their default design (kerning
## that varies, glyph boxes of moved outlines, named instances and
## normalised coordinates) and of the built-in fonts, through the public
## `Font` API. Every expected value is HarfBuzz 14.6.0's (uharfbuzz
## 0.56.3), printed by `tests/api/oracle_variations.py`; family names are
## fontTools 4.61.1's. Run with `roc test tests/api/main.roc`.
VariationTests :: {}.{}

read_or_crash : List(U8) -> Font
read_or_crash = |bytes|
	match Font.from_bytes(bytes, Font.ReadOptions.{}) {
		Ok(font) => font
		Err(_) => crash "a variable test font could not be read"
	}

at : Font, List({ tag : Str, value : Dec }) -> Font
at = |font, axes| Font.at(font, Font.Variation.{ axes })

wght : Dec -> List({ tag : Str, value : Dec })
wght = |w| [{ tag: "wght", value: w }]

# The advances and offsets of shaped text.
positions : Font, Str -> { advances : List(I32), offsets : List({ x : I32, y : I32 }) }
positions = |font, text| {
	run = Font.shape(font, text, Font.ShapeOptions.{})
	{ advances: run.advances.map(|a| a.x), offsets: run.offsets }
}

xy : List((I32, I32)) -> List({ x : I32, y : I32 })
xy = |pairs| pairs.map(|(x, y)| { x, y })

# ------------------------------------------------------------ kerning that varies

# `kern-var.ttf`: pair adjustments of formats 1 and 2 (one through an
# extension lookup) whose x advance, x placement and y placement devices
# take deltas from the `GDEF` item variation store. At the default location
# no delta applies.
kern_var : Font
kern_var = read_or_crash(kern_file)

expect positions(kern_var, "abcdefg") == { advances: [550, 610, 619, 638, 640, 661, 660], offsets: xy([(0, 0), (0, 0), (0, 0), (4, -6), (0, 0), (0, 0), (0, 0)]) }
expect positions(kern_var, "gfedcba") == { advances: [656, 620, 640, 629, 620, 600, 600], offsets: xy([(0, 0), (0, 0), (0, 0), (0, 0), (0, -2), (0, 0), (0, 0)]) }
expect positions(kern_var, "aceg") == { advances: [620, 622, 640, 660], offsets: xy([(0, 0), (2, 0), (0, 1), (0, 0)]) }

expect {
	heavy = at(kern_var, wght(900))
	positions(heavy, "abcdefg") == { advances: [651, 610, 619, 635, 640, 661, 660], offsets: xy([(0, 0), (0, 0), (-3, 0), (105, -6), (0, 0), (0, 0), (0, 0)]) }
		and positions(heavy, "gfedcba") == { advances: [656, 620, 640, 629, 620, 600, 600], offsets: xy([(0, 0), (0, 0), (0, 0), (-3, 0), (0, 99), (0, 0), (0, 0)]) }
		and positions(heavy, "aceg") == { advances: [519, 723, 640, 660], offsets: xy([(0, 0), (103, 0), (0, 11), (0, 0)]) }
}
expect {
	light = Font.at(kern_var, Font.Variation.{ weight: Thin })
	positions(light, "abcdefg") == { advances: [490, 610, 619, 888, 640, 661, 660], offsets: xy([(0, 0), (0, 0), (250, 0), (-56, -66), (0, 0), (0, 0), (0, 0)]) }
		and positions(light, "gfedcba") == { advances: [656, 620, 640, 629, 620, 600, 600], offsets: xy([(0, 0), (0, 0), (0, 0), (250, 0), (0, -62), (0, 0), (0, 0)]) }
		and positions(light, "aceg") == { advances: [620, 562, 640, 660], offsets: xy([(0, 0), (-58, 0), (0, 11), (0, 0)]) }
}
# Two axes at once, with an intermediate region and a two-axis region.
expect {
	wide = at(kern_var, [{ tag: "wght", value: 650 }, { tag: "wdth", value: 125 }])
	positions(wide, "abcdefg") == { advances: [601, 610, 619, 636, 640, 661, 660], offsets: xy([(0, 0), (0, 0), (-2, 0), (55, 28), (0, 0), (0, 0), (0, 0)]) }
		and positions(wide, "gfedcba") == { advances: [656, 620, 640, 629, 620, 600, 600], offsets: xy([(0, 0), (0, 0), (0, 0), (-2, 0), (0, 49), (0, 0), (0, 0)]) }
		and positions(wide, "aceg") == { advances: [603, 673, 640, 660], offsets: xy([(0, 0), (53, 0), (0, -3), (0, 0)]) }
}
expect {
	narrow = Font.at(kern_var, Font.Variation.{ width: Percent(50) })
	positions(narrow, "abcdefg") == { advances: [550, 610, 619, 509, 640, 661, 660], offsets: xy([(0, 0), (0, 0), (-129, 0), (4, 1), (0, 0), (0, 0), (0, 0)]) }
		and positions(narrow, "gfedcba") == { advances: [656, 620, 640, 629, 620, 600, 600], offsets: xy([(0, 0), (0, 0), (0, 0), (-129, 0), (0, -2), (0, 0), (0, 0)]) }
		and positions(narrow, "aceg") == { advances: [627, 622, 640, 660], offsets: xy([(0, 0), (2, 0), (0, 4), (0, 0)]) }
}

# Moving back to Regular gives the default kerning again.
expect positions(Font.at(at(kern_var, wght(900)), Font.Variation.{}), "abcdefg") == positions(kern_var, "abcdefg")

# ------------------------------------------------------------ glyph boxes that vary

# `var-outlines.ttf`: simple and composite glyphs (offsets, scales, a 2x2
# transform, anchor points, a nested composite) whose points `gvar` moves,
# with untouched points inferred and phantom points moved.
outlines : Font
outlines = read_or_crash(outlines_file)

Ink : [Extents({ x_min : I32, y_min : I32, x_max : I32, y_max : I32 }), Empty, Unknown]

boxes : Font -> List(Ink)
boxes = |font| [0, 1, 2, 3, 4, 5, 6, 7, 8].map(|g| Font.extents(font, g))

box : I32, I32, I32, I32 -> Ink
box = |x_min, y_min, x_max, y_max| Extents({ x_min, y_min, x_max, y_max })

expect boxes(outlines) == [Empty, box(100, 0, 500, 700), box(80, 0, 480, 820), box(0, -40, 1408, 700), box(0, 60, 720, 1630), box(0, -39, 1867, 775), Empty, box(0, 0, 100, 100), box(0, 0, 100, 100)]
expect boxes(at(outlines, wght(900))) == [Empty, box(95, 0, 525, 740), box(111, 7, 512, 824), box(88, -21, 1460, 740), box(-8, 63, 737, 1671), box(22, -19, 1897, 819), Empty, box(0, 0, 100, 100), box(0, 0, 100, 100)]
expect boxes(at(outlines, wght(100))) == [Empty, box(100, 0, 500, 700), box(80, 0, 480, 820), box(55, -40, 1463, 700), box(0, 60, 720, 1630), box(0, -39, 1867, 775), Empty, box(0, 0, 100, 100), box(0, 0, 100, 100)]
expect boxes(at(outlines, [{ tag: "wght", value: 650 }, { tag: "wdth", value: 125 }])) == [Empty, box(70098, -3, 70513, 717), box(96, 4, 496, 822), box(71, -31, 71063, 717), box(55996, 21058, 56728, 22647), box(36, -24, 71872, 799), Empty, box(0, 0, 100, 100), box(0, 0, 100, 100)]
expect boxes(at(outlines, [{ tag: "wdth", value: 50 }])) == [Empty, box(167, -1000, 400, 1900), box(45, 1, 445, 823), box(-19, -1000, 1469, 1900), box(-186, -820, 580, 2612), box(-45, -1095, 1767, 2095), Empty, box(0, 0, 100, 100), box(0, 0, 100, 100)]

# A glyph past the font has no box anywhere.
expect Font.extents(at(outlines, wght(900)), 9) == Empty and Font.extents(at(outlines, wght(900)), 0xFFFFFFFF) == Empty

# ------------------------------------------------------------ instances and coordinates

mapped : Font
mapped = read_or_crash(mapped_file)

# `wght` goes through the font's `avar` map; `wdth` is linear.
expect Font.coordinates(mapped) == [{ tag: "wght", value: 0 }, { tag: "wdth", value: 0 }]
expect Font.coordinates(at(mapped, wght(700))) == [{ tag: "wght", value: 11235 }, { tag: "wdth", value: 0 }]
expect Font.coordinates(at(mapped, [{ tag: "wght", value: 100 }, { tag: "wdth", value: 125 }])) == [{ tag: "wght", value: -16384 }, { tag: "wdth", value: 16384 }]
expect Font.coordinates(at(mapped, wght(456.7))) == [{ tag: "wght", value: 2787 }, { tag: "wdth", value: 0 }]

expect Font.instances(mapped) == [{ name: "Thin", axes: [{ tag: "wght", value: 100 }, { tag: "wdth", value: 100 }] }, { name: "Regular", axes: [{ tag: "wght", value: 400 }, { tag: "wdth", value: 100 }] }, { name: "Bold Condensed", axes: [{ tag: "wght", value: 700 }, { tag: "wdth", value: 75 }] }]

# Moving to an instance is moving to its axis values.
expect {
	bold = Font.instances(mapped).get(2) ?? { name: "", axes: [] }
	Font.coordinates(at(mapped, bold.axes)) == Font.coordinates(at(mapped, [{ tag: "wght", value: 700 }, { tag: "wdth", value: 75 }]))
}

# ------------------------------------------------------------ built-in fonts

expect Font.family_name(Font.sans) == Ok("Inter Variable") and Font.family_name(Font.serif) == Ok("Merriweather") and Font.family_name(Font.mono) == Ok("Fira Code")
expect [Font.sans, Font.serif, Font.mono].map(Font.units_per_em) == [2048, 2000, 1950]
expect [Font.sans, Font.serif, Font.mono].all(|f| Font.dropped(f).is_empty())

# Each measures at Regular (wght 400), where HarfBuzz is told `wght` 400.
expect ["Hello, world!", "AVATAR office", "Wave To -> 0xFF != 12:30"].map(|t| Font.width(Font.sans, t)) == [12111, 13764, 24564]
expect ["Hello, world!", "AVATAR office", "Wave To -> 0xFF != 12:30"].map(|t| Font.width(Font.serif, t)) == [12032, 13618, 24156]
expect ["Hello, world!", "AVATAR office", "Wave To -> 0xFF != 12:30"].map(|t| Font.width(Font.mono, t)) == [15600, 15600, 28800]
expect [Font.sans, Font.serif, Font.mono].map(|f| Font.width(Font.at(f, Font.Variation.{ weight: Bold }), "AVATAR office")) == [14423, 14016, 15600]

# Glyph boxes at Regular: Merriweather and Fira Code default to Light, so
# theirs are measured on moved outlines.
expect [1, 2, 3, 4].map(|g| Font.extents(Font.sans, g)) == [Empty, box(52, 0, 1361, 1490), box(52, 0, 1361, 1910), box(52, 0, 1361, 1897)]
expect [1, 2, 3, 4].map(|g| Font.extents(Font.serif, g)) == [box(-14, 0, 1424, 1498), box(-14, 0, 1424, 1976), box(-14, 0, 1424, 1926), box(-14, 0, 1424, 2334)]
expect [1, 2, 3, 4].map(|g| Font.extents(Font.mono, g)) == [box(41, 0, 1159, 1377), box(41, 0, 1159, 1812), box(41, 0, 1159, 1781), box(41, 0, 1159, 1821)]

# The bytes are the files that were read, and each licence is the SIL Open
# Font License with the face's copyright notice.
expect Font.sans_bytes.len() == 879708 and Font.serif_bytes.len() == 4628080 and Font.mono_bytes.len() == 286320
expect [Font.sans_licence, Font.serif_licence, Font.mono_licence].all(|l| l.contains("SIL OPEN FONT LICENSE Version 1.1"))
expect Font.sans_licence.contains("The Inter Project Authors") and Font.serif_licence.contains("Merriweather") and Font.mono_licence.contains("The Fira Code Project Authors")
