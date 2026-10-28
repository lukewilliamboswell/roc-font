app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	font: "../package/main.roc",
}
import cli.OsStr
import cli.Path
import cli.Stdout
import cli.Stderr
import font.Font

# Read the caller's font, shape their text and show the positioned glyphs.
# Font units and original UTF-8 byte clusters can feed a PDF or drawing
# package directly; this program draws nothing and chooses no fallback.
# Example: roc examples/complex-shaping.roc -- font.ttf Deva "र्कि हिन्दी"
main! = |args| {
	bytes = match args.first() {
		Ok(path) => Path.read_bytes!(Path.utf8(OsStr.display(path)))?
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
	script = match args.get(1) {
		Ok(arg) => OsStr.display(arg)
		Err(_) => "Latn"
	}
	text = match args.get(2) {
		Ok(arg) => OsStr.display(arg)
		Err(_) => "office"
	}
	plan = Font.plan(font, Font.ShapeOptions.{ script })
	run = match Font.shape_checked(font, plan, text) {
		Ok(value) => value
		Err(OverBudget(value)) => {
			Stderr.line!("Work limit reached: ${Str.inspect(value.budgets)}")?
			value.run
		}
	}
	Stdout.line!("${run.glyphs.len().to_str()} glyphs; advances and offsets in font units")?
	for i in 0..<run.glyphs.len() {
		glyph = run.glyphs.get(i) ?? 0
		cluster = run.clusters.get(i) ?? 0
		advance = run.advances.get(i) ?? { x: 0, y: 0 }
		offset = run.offsets.get(i) ?? { x: 0, y: 0 }
		flags = run.flags.get(i) ?? 0
		Stdout.line!("glyph=${glyph.to_str()} byte=${cluster.to_str()} advance=${Str.inspect(advance)} offset=${Str.inspect(offset)} unsafe=${Str.inspect(Font.is_unsafe_to_break(flags))} missing=${Str.inspect(Font.is_missing(flags))}")?
	}
	Ok({})
}
