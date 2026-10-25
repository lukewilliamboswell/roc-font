app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	font: "../package/main.roc",
}

import cli.OsStr
import cli.Path
import cli.Stderr
import cli.Stdout
import font.Font

# Shape right-to-left text, and find the characters a font cannot draw.
#
#     roc examples/right-to-left.roc
#     roc examples/right-to-left.roc -- path/to/a-hebrew-font.ttf
#
# The text is Hebrew for "peace (world)". None of the built-in fonts has
# Hebrew letters, so by default this shapes with `Font.sans` and shows how a
# run marks the glyphs a font is missing: that is where a program would
# switch to a fallback font. Give it a font with Hebrew to see real glyphs.
main! = |args| {
	font = match args.first() {
		Ok(arg) => {
			path = OsStr.display(arg)
			match Path.read_bytes!(Path.utf8(path)) {
				Err(_) => {
					Stderr.line!("Could not read ${path}")?
					return Err(Exit(1))
				}
				Ok(bytes) =>
					match Font.from_bytes(bytes, Font.ReadOptions.{}) {
						Ok(read) => read
						Err(_) => {
							Stderr.line!("${path} is not a font roc-font can use")?
							return Err(Exit(1))
						}
					}
			}
		}
		Err(_) => Font.sans
	}

	text = "שלום (עולם)"

	# The script code `Hebr` tells the shaper which script the text is in;
	# its direction follows from that (right to left). roc-font does not
	# guess scripts or reorder mixed-direction paragraphs: split a paragraph
	# into runs of one script and direction (the `unicode` package can) and
	# shape each run.
	run = Font.shape(font, text, Font.ShapeOptions.{ script: "Hebr", language: "he" })

	# A run is always in visual order, left to right as drawn, so for
	# right-to-left text the clusters count down: the first glyph drawn
	# (leftmost) is the last character of the text. Brackets are mirrored:
	# the "(" at byte 9 is drawn with the font's ")" glyph, which opens the
	# bracket when read from the right.
	Stdout.line!("glyph  name         cluster  missing")?
	for i in 0..<run.glyphs.len() {
		glyph = run.glyphs.get(i) ?? 0
		cluster = run.clusters.get(i) ?? 0

		# A glyph is `missing` when the font has no glyph for the
		# character, so glyph 0 (the font's "missing" box) stands in.
		missing = Font.missing(run.flags.get(i) ?? 0)
		name = Font.glyph_name(font, glyph) ?? ""
		Stdout.line!("${pad(glyph.to_str(), 7)}${pad(name, 13)}${pad(cluster.to_str(), 9)}${if (missing) "yes" else "no"}")?
	}

	missing_count = run.flags.count_if(Font.missing)
	Stdout.line!("")?
	Stdout.line!("${missing_count.to_str()} of ${run.glyphs.len().to_str()} glyphs need a fallback font.")?
	Ok({})
}

# Left-align a column by padding it with spaces.
pad : Str, U64 -> Str
pad = |str, width| Str.concat(str, Str.repeat(" ", width - str.count_utf8_bytes().min(width)))
