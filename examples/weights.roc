app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	font: "../package/main.roc",
}

import cli.Stdout
import cli.OsStr
import font.Font

# Select genuine built-in static faces. Bytes match the font measured.
main! = |args| {
	text = "Hello, world!"
	for (name, font, bytes) in [
		("Regular", Font.sans, Font.sans_bytes),
		("Bold", Font.sans_bold, Font.sans_bold_bytes),
		("Italic", Font.sans_italic, Font.sans_italic_bytes),
		("Bold Italic", Font.sans_bold_italic, Font.sans_bold_italic_bytes),
	] {
		Stdout.line!("${name}: ${Font.width(font, text).to_str()} font units; ${bytes.len().to_str()} font bytes")?
	}
	# A strict consumer checks the shaped run, then uses clusters to locate
	# unsupported text before producing output. This serif lacks U+2318.
	sample = match args.first() {
		Ok(arg) => OsStr.display(arg)
		Err(_) => "⌘K"
	}
	run = Font.shape(Font.serif, sample, Font.ShapeOptions.{})
	missing = if (run.flags.any(Font.is_missing)) "yes" else "no"
	Stdout.line!("Serif has missing glyphs: ${missing}")?
	Ok({})
}
