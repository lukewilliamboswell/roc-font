app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	font: "../package/main.roc",
}

import cli.OsStr
import cli.Path
import cli.Stdout
import font.Font

# Give this example an Arabic font file:
#     roc examples/arabic.roc -- path/to/arabic-font.ttf
# A paragraph layer supplies script and language after splitting mixed text
# into runs. Arabic uses its own joining rules and ordered font features.
main! = |args| {
	path = match args.first() {
		Ok(arg) => OsStr.display(arg)
		Err(_) => {
			Stdout.line!("Usage: arabic <Arabic font file>")?
			return Ok({})
		}
	}
	bytes = match Path.read_bytes!(Path.utf8(path)) {
		Ok(read) => read
		Err(_) => {
			Stdout.line!("Could not read ${path}")?
			return Err(Exit(1))
		}
	}
	match Font.from_bytes(bytes, Font.ReadOptions.{}) {
		Err(problems) => {
			for problem in problems {
				Stdout.line!(Font.describe_problem(problem))?
			}
			Err(Exit(1))
		}
		Ok(font) => {
			text = "السلام عليكم"
			plan = Font.plan(font, Font.ShapeOptions.{ script: "Arab", language: "ar" })
			run = Font.shape_planned(font, plan, text)
			Stdout.line!("${text}: ${run.glyphs.len().to_str()} glyphs, ${Font.width_planned(font, plan, text).to_str()} font units")?
			Stdout.line!("Glyph ids in visual order: ${Str.join_with(run.glyphs.map(|g| g.to_str()), ", ")}")?
			Ok({})
		}
	}
}
