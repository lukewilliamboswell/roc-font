app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	font: "../package/main.roc",
}

import cli.Stdout
import font.Font

# Measure the same text at several weights of a variable font.
#
#     roc examples/weights.roc
#
# A variable font holds a whole range of designs in one file: lighter and
# bolder, narrower and wider. All three built-in fonts are variable. Bold
# text is wider than regular text, so measure it at the weight you draw it.
main! = |_args| {
	text = "Hello, world!"

	# The axes a font can vary along, by their four-letter tags: `wght` is
	# weight, `wdth` width and `opsz` optical size.
	axes = Font.axes(Font.sans).map(|axis| "${axis.tag} ${axis.min.to_str()} to ${axis.max.to_str()}")
	Stdout.line!("Font.sans varies along: ${Str.join_with(axes, ", ")}")?
	Stdout.line!("")?

	# `Font.at` gives the font at another point of its range. It is cheap:
	# the font's tables are shared, so there is no reading again. Weights
	# follow CSS: `Light` is 300, `Regular` 400 and `Bold` 700, and
	# `Weight(550)` is any value in between.
	weights = [("Light", Light), ("Regular", Regular), ("Weight(550)", Weight(550)), ("Bold", Bold)]
	for (name, weight) in weights {
		font = Font.at(Font.sans, Font.Variation.{ weight })
		Stdout.line!("${pad(name, 12)} \"${text}\" is ${Font.width(font, text).to_str()} font units wide")?
	}

	# Fira Code (`Font.mono`) is monospaced at every weight: weight changes
	# how dark the letters are, never how much room they take.
	Stdout.line!("")?
	for (name, weight) in [("Light", Light), ("Bold", Bold)] {
		font = Font.at(Font.mono, Font.Variation.{ weight })
		Stdout.line!("Font.mono ${pad(name, 6)} \"${text}\" is ${Font.width(font, text).to_str()} font units wide")?
	}
	Ok({})
}

# Left-align a column by padding it with spaces.
pad : Str, U64 -> Str
pad = |str, width| Str.concat(str, Str.repeat(" ", width - str.count_utf8_bytes().min(width)))
