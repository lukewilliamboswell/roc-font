app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	font: "../package/main.roc",
}

import cli.OsStr
import cli.Path
import cli.Stderr
import cli.Stdout
import font.Font

# Read your own font file, and report what is wrong with it if it cannot be
# used.
#
#     roc examples/font-file.roc -- path/to/font.ttf
#     roc examples/font-file.roc
#
# roc-font never opens files itself: your program loads the bytes however
# its platform allows (here with basic-cli's `Path.read_bytes!`) and hands
# them to `Font.from_bytes`. Font files are treated as untrusted. Reading is
# the only step that can fail, and when it does it reports every problem it
# found, not just the first. Without a path, this checks the file that
# `Font.sans` was read from, so it runs as it is.
main! = |args| {
	(name, bytes) = match args.first() {
		Ok(arg) => {
			path = OsStr.display(arg)
			match Path.read_bytes!(Path.utf8(path)) {
				Ok(read) => (path, read)
				Err(_) => {
					Stderr.line!("Could not read ${path}")?
					return Err(Exit(1))
				}
			}
		}
		Err(_) => ("the file of Font.sans", Font.sans_bytes)
	}
	Stdout.line!("Checking ${name}")?

	# A collection (`.ttc`) holds several fonts; `ReadOptions.{ face: 2 }`
	# would read the third. A single font file has one face, numbered 0.
	match Font.face_count(bytes) {
		Ok(count) if count > 1 => Stdout.line!("A collection of ${count.to_str()} fonts; reading the first.")?
		_ => {}
	}

	# By default reading is lenient, as browsers are: a font reads exactly
	# when a browser would draw it. A browser quietly ignores a few broken
	# optional parts (an old-style `kern` table, faulty variation data); so
	# does roc-font, and `Font.dropped` says what was left out.
	match Font.from_bytes(bytes, Font.ReadOptions.{}) {
		Err(problems) => {
			Stdout.line!("This font cannot be used:")?
			for problem in problems {
				Stdout.line!("  - ${describe(problem)}")?
			}
			Err(Exit(1))
		}
		Ok(font) => {
			family = Font.family_name(font) ?? "(no name)"
			Stdout.line!("Family: ${family}")?
			Stdout.line!("Glyphs: ${Font.glyph_count(font).to_str()}, ${Font.units_per_em(font).to_str()} units to the em")?
			Stdout.line!("Characters mapped: ${Font.code_points(font).len().to_str()}")?
			axes = Font.axes(font).map(|axis| axis.tag)
			if !axes.is_empty() {
				Stdout.line!("Variable along: ${Str.join_with(axes, ", ")}")?
			}

			left_out = Font.dropped(font)
			if left_out.is_empty() {
				Stdout.line!("Nothing was left out.")?
			} else {
				Stdout.line!("Left out, as a browser would:")?
				for problem in left_out {
					Stdout.line!("  - ${describe(problem)}")?
				}
			}

			# Strict reading rejects a font for any problem at all. Use it
			# where you will pass the file on, such as embedding it in a PDF,
			# and want it to work everywhere, not just in browsers.
			match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
				Ok(_) => Stdout.line!("Strict reading accepts it too.")?
				Err(problems) => {
					Stdout.line!("Strict reading rejects it:")?
					for problem in problems {
						Stdout.line!("  - ${describe(problem)}")?
					}
				}
			}
			Ok({})
		}
	}
}

# Say what a problem means, in words a user of your program can act on.
describe : Font.Problem -> Str
describe = |problem|
	match problem {
		NotAFont => "not a TrueType or OpenType font file"
		NoSuchFace({ face, count }) => "there is no font ${face.to_str()} in a collection of ${count.to_str()}"
		OverLimit(limit) => "the file asks for more than the ${limit} limit allows"
		MissingTable(table) => "the required `${table}` table is missing"
		BadTable({ table, offset }) => "the `${table}` table is damaged (at byte ${offset.to_str()})"
		BadUnitsPerEm => "the font's units per em are out of range"
		NoUnicodeMapping => "the font has no character map for Unicode text"
	}
