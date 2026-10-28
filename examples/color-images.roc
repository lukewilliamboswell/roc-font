app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	font: "../package/main.roc",
}
import cli.OsStr
import cli.Path
import cli.Stdout
import cli.Stderr
import font.Font

# Shape emoji, then retrieve the encoded artwork for the resulting glyphs.
# The caller chooses an exact strike index; no nearest-size selection is
# hidden in the library. Inspect the listed strike facts before drawing.
#
#     roc examples/color-images.roc -- path/to/emoji.ttf 0 "👩‍💻 ❤️"
#
# With no file this uses Font.sans, which has no embedded bitmap/SVG data.
# The example does not decode images, draw pixels or write output files.
main! = |args| {
	bytes = match args.first() {
		Ok(path) => match Path.read_bytes!(Path.utf8(OsStr.display(path))) {
			Ok(value) => value
			Err(_) => {
				Stderr.line!("Could not read the font file.")?
				return Err(Exit(1))
			}
		}
		Err(_) => Font.sans_bytes
	}
	font = match Font.from_bytes(bytes, Font.ReadOptions.{}) {
		Ok(value) => value
		Err(problems) => {
			for problem in problems {
				Stderr.line!(Font.describe_problem(problem))?
			}
			return Err(Exit(1))
		}
	}
	strikes = Font.bitmap_strikes(font)
	Stdout.line!("Bitmap strikes: ${strikes.len().to_str()}")?
	for i in 0..<strikes.len() {
		match strikes.get(i) {
			Ok(fact) => Stdout.line!("  ${i.to_str()}: ${Str.inspect(fact)}")?
			Err(_) => {}
		}
	}
	strike = match args.get(1) {
		Ok(arg) => U32.from_str(OsStr.display(arg)) ?? 0
		Err(_) => 0
	}
	text = match args.get(2) {
		Ok(arg) => OsStr.display(arg)
		Err(_) => "👩‍💻 ❤️"
	}
	run = Font.shape(font, text, Font.ShapeOptions.{})
	for i in 0..<run.glyphs.len() {
		glyph = run.glyphs.get(i) ?? 0
		advance = run.advances.get(i) ?? { x: 0, y: 0 }
		Stdout.line!("Glyph ${glyph.to_str()}: advance ${advance.x.to_str()} font units")?
		match Font.bitmap_glyph(font, glyph, strike) {
			Present(image) => {
				Stdout.line!("  Strike ${strike.to_str()}: ${Str.inspect(image.format)}, ${image.bytes.len().to_str()} encoded bytes")?
				Stdout.line!("  Placement in native strike pixels: ${Str.inspect(image.placement)}")?
			}
			Absent => Stdout.line!("  No bitmap at strike ${strike.to_str()}")?
		}
		match Font.svg_glyph(font, glyph) {
			Present(doc) => Stdout.line!("  SVG: ${Str.inspect(doc.encoding)}, ${doc.bytes.len().to_str()} encoded bytes, glyphs ${doc.first_glyph.to_str()} to ${doc.last_glyph.to_str()}")?
			Absent => {}
		}
	}
	Ok({})
}
