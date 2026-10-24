app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	font: "../package/main.roc",
}

import cli.Stdout
import font.Font

# Turn a font's typographic features on and off, over all or part of the text.
#
#     roc examples/features.roc
#
# Fonts carry optional behaviours, named by four-letter tags: `liga` for
# ligatures, `tnum` for figures of equal width, `smcp` for small capitals,
# `salt` for stylistic alternates, and many more. Shaping with no features
# uses the browser defaults; a `Font.Feature` changes one of them.
main! = |_args| {
	# Ligatures off. Merriweather draws "fi" as one glyph by default; with
	# `liga` set to 0 each letter gets its own glyph, as you might want in
	# letter-spaced headings.
	Stdout.line!("Ligatures in Font.serif")?
	Stdout.line!("  default: ${glyph_names(Font.serif, "office fit", [])}")?
	Stdout.line!("  liga 0:  ${glyph_names(Font.serif, "office fit", [Font.Feature.{ tag: "liga", value: 0 }])}")?

	# Which feature to turn off depends on the font. Fira Code builds its
	# programming ligatures with contextual alternates (`calt`), so turning
	# off `liga` changes nothing and turning off `calt` shows the plain
	# characters.
	code = "a -> b != c"
	Stdout.line!("")?
	Stdout.line!("Programming ligatures in Font.mono")?
	Stdout.line!("  default: ${glyph_names(Font.mono, code, [])}")?
	Stdout.line!("  liga 0:  ${glyph_names(Font.mono, code, [Font.Feature.{ tag: "liga", value: 0 }])}")?
	Stdout.line!("  calt 0:  ${glyph_names(Font.mono, code, [Font.Feature.{ tag: "calt", value: 0 }])}")?

	# Tabular figures. Inter's digits normally have their own widths, so a
	# column of numbers would not line up; `tnum` makes every digit as wide
	# as every other. A plan holds the options, worked out once, for
	# measuring (`Font.width_planned`) or shaping many strings.
	Stdout.line!("")?
	Stdout.line!("Figures in Font.sans, in font units")?
	for features in [[], [Font.Feature.{ tag: "tnum" }]] {
		label = if (features.is_empty()) "default:" else "tnum:    "
		plan = Font.plan(Font.sans, Font.ShapeOptions.{ features })
		ones = Font.width_planned(Font.sans, plan, "1111")
		zeros = Font.width_planned(Font.sans, plan, "0000")
		Stdout.line!("  ${label} \"1111\" is ${ones.to_str()} wide, \"0000\" is ${zeros.to_str()} wide")?
	}

	# Part of the text. `start` and `end` are UTF-8 byte offsets into the
	# text, the same offsets shaping reports as clusters: here they pick out
	# "readme" (bytes 8 to 14) for small capitals.
	note = "see the readme first"
	Stdout.line!("")?
	Stdout.line!("Small capitals on part of \"${note}\" in Font.serif")?
	Stdout.line!("  ${glyph_names(Font.serif, note, [Font.Feature.{ tag: "smcp", start: 8, end: 14 }])}")?

	# Stylistic alternates. `salt` swaps in the font's alternate designs,
	# here for "a" and "1". Where a font offers several alternates for one
	# glyph, the value chooses among them: `value: 2` is the second.
	Stdout.line!("")?
	Stdout.line!("Stylistic alternates in Font.sans")?
	Stdout.line!("  default: ${glyph_names(Font.sans, "a1", [])}")?
	Stdout.line!("  salt:    ${glyph_names(Font.sans, "a1", [Font.Feature.{ tag: "salt" }])}")?

	# Which features a font offers: every tag it names, for any script.
	Stdout.line!("")?
	Stdout.line!("Font.serif offers: ${Str.join_with(Font.features(Font.serif), " ")}")?
	Ok({})
}

# Shape text with the given features and list the names of its glyphs.
glyph_names : Font, Str, List(Font.Feature) -> Str
glyph_names = |font, text, features| {
	run = Font.shape(font, text, Font.ShapeOptions.{ features })
	Str.join_with(run.glyphs.map(|glyph| Font.glyph_name(font, glyph) ?? "?"), " ")
}
