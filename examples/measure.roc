app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	font: "../package/main.roc",
}

import cli.Stdout
import font.Font

# How wide is a string, in pixels, at a given font size?
#
#     roc examples/measure.roc
#
# `Font.sans` is a font built into roc-font (Inter), so no font file is
# needed. `Font.width` shapes the text as a browser would, with the font's
# default ligatures and kerning, and adds up the glyphs' advances.
main! = |_args| {
	text = "Hello, world!"
	size = 16.I32 # the font size in pixels: the height of one em

	# roc-font measures in font units, integers on the font's own grid of
	# `units_per_em` units to the em.
	units = Font.width(Font.sans, text)
	units_per_em = Font.units_per_em(Font.sans)

	# Scale to pixels. Rounding, if you want it, is yours to choose.
	pixels = (units * size).to_dec() / units_per_em.to_dec()

	Stdout.line!("\"${text}\" is ${units.to_str()} font units wide (${units_per_em.to_str()} to the em),")?
	Stdout.line!("which is ${pixels.to_str()} px at ${size.to_str()} px.")?
	Ok({})
}
