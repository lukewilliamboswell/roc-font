app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	font: "../package/main.roc",
}

import cli.Stdout
import font.Font

# Turn text into the glyphs that draw it, and where each one goes.
#
#     roc examples/shape.roc
#
# This is what a renderer needs: a glyph id to draw, how far to move the pen
# after it (its advance), and a nudge from the pen position (its offset).
# The cluster says which part of your text each glyph draws, so you can map
# a click back to a character or put a cursor between glyphs.
main! = |_args| {
	# Merriweather (`Font.serif`) joins "fi" into one glyph, a ligature, so
	# the run has fewer glyphs than the text has characters.
	font = Font.serif
	text = "Office fit"

	# Empty options are the browser defaults: Latin script, left to right,
	# with the font's standard ligatures, contextual forms and kerning.
	run = Font.shape(font, text, Font.ShapeOptions.{})

	Stdout.line!("Shaping \"${text}\" gives ${run.glyphs.len().to_str()} glyphs for ${text.count_utf8_bytes().to_str()} bytes of text:")?
	Stdout.line!("")?
	Stdout.line!("glyph  name       cluster  text  advance")?

	# The lists in a run are index-aligned: entry `i` of each describes the
	# same glyph. Glyphs are in visual order, left to right.
	bytes = text.to_utf8()
	# A cluster is a UTF-8 byte offset into the text. The text a glyph
	# draws runs from its cluster to the next larger cluster (or the end of
	# the text); `Font.cluster_ranges` gives that range for every glyph.
	ranges = Font.cluster_ranges(run, bytes.len())
	for i in 0..<run.glyphs.len() {
		glyph = run.glyphs.get(i) ?? 0
		cluster = run.clusters.get(i) ?? 0
		advance = (run.advances.get(i) ?? { x: 0, y: 0 }).x
		range = ranges.get(i) ?? { start: 0, end: 0 }
		drawn = Str.from_utf8(bytes.sublist({ start: range.start, len: range.end - range.start })) ?? "?"

		# Glyph names are optional in fonts; ids are what you draw with.
		name = Font.glyph_name(font, glyph) ?? ""
		Stdout.line!("${pad(glyph.to_str(), 7)}${pad(name, 11)}${pad(cluster.to_str(), 9)}${pad("\"${drawn}\"", 6)}${advance.to_str()}")?
	}

	total = run.advances.fold(0, |sum, a| sum + a.x)
	Stdout.line!("")?
	Stdout.line!("Total advance: ${total.to_str()} font units (${Font.units_per_em(font).to_str()} to the em).")?
	Ok({})
}

# Left-align a column by padding it with spaces.
pad : Str, U64 -> Str
pad = |str, width| {
	used = str.count_utf8_bytes()
	if used >= width {
		"${str} "
	} else {
		Str.concat(str, Str.repeat(" ", width - used))
	}
}
