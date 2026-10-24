app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.23.0/GNN5tt2gKdX4dhawg4915C4YB193woHFdcCkz31fhGxv.tar.zst",
	rf: "../../package/main.roc",
}

import cli.OsStr
import cli.Path
import cli.Stdin
import cli.Stdout
import cli.Stderr
import rf.Font
import Case

## Conformance driver: reads HarfBuzz-format case files named on the command
## line (or one from stdin when none, or `-`, is named), reads each distinct
## font once, runs every case and prints one line per case:
##
##     <case file>:<line number><TAB><result>
##
## A result is hb-shape notation with glyph ids, `read:accept`,
## `read:reject`, `unsupported:<option>` (an option the driver cannot honour
## yet), `error:font-file` (the font could not be read from disk) or
## `error:malformed-case`. See docs/conformance.adoc.
##
## With `--explain` as the first argument, a rejected font's line gets a third
## tab-separated column listing the reader's problems. It is for triage and
## is never compared with oracle records.
main! : List(OsStr) => Try({}, _)
main! = |args| {
	all_names = args.map(OsStr.display)
	explain = all_names.first() == Ok("--explain")
	names = if (explain) all_names.drop_first(1) else all_names
	sources = if (names.is_empty()) ["-"] else names
	var $fonts = Dict.with_capacity(16)
	for source in sources {
		text = if source == "-" {
			match Stdin.read_to_end!() {
				Ok(bytes) => Ok(Str.from_utf8_lossy(bytes))
				Err(_) => Err({})
			}
		} else {
			match Path.read_bytes!(Path.utf8(source)) {
				Ok(bytes) => Ok(Str.from_utf8_lossy(bytes))
				Err(_) => Err({})
			}
		}
		match text {
			Err(_) => {
				Stderr.line!("driver: cannot read case file ${source}") ?? {}
				return Err(Exit(2))
			}
			Ok(content) => {
				var $out = []
				var $number = 0.U64
				for line in content.split_on("\n") {
					$number = $number + 1
					match Case.classify(line) {
						Shape(c) => {
							path = Case.resolve(source, c.font)
							state = match $fonts.get(path) {
								Ok(found) => found
								Err(_) => {
									loaded = load!(path)
									$fonts = $fonts.insert(path, loaded)
									loaded
								}
							}
							why = match state {
								Rejected(problems) if explain => "\t${problems}"
								_ => ""
							}
							$out = $out.append("${source}:${$number.to_str()}\t${run(state, c.options, c.unicodes)}${why}")
						}
						Malformed => {
							$out = $out.append("${source}:${$number.to_str()}\terror:malformed-case")
						}
						_ => {}
					}
				}
				if !$out.is_empty() {
					Stdout.write!("${Str.join_with($out, "\n")}\n") ?? {}
				}
			}
		}
	}
	Ok({})
}

FontState : [Ready(Font), Rejected(Str), NoFile]

load! : Str => FontState
load! = |path|
	match Path.read_bytes!(Path.utf8(path)) {
		Err(_) => NoFile
		Ok(bytes) =>
			match Font.from_bytes(bytes) {
				Ok(font) => Ready(font)
				Err(problems) => Rejected(Str.inspect(problems))
			}
	}

run : FontState, List(Str), Str -> Str
run = |state, options, unicodes|
	match Case.settings(options) {
		Err(option) => "unsupported:${option}"
		Ok(settings) =>
			match Case.scalars(unicodes) {
				Err(_) => "error:malformed-case"
				Ok(scalars) =>
					match state {
						NoFile => "error:font-file"
						Rejected(_) => "read:reject"
						Ready(font) => if (settings.read) "read:accept" else shape(font, settings, scalars)
					}
			}
	}

# The current public API shapes in four steps: map code points to glyphs,
# apply the default substitutions, take advances and add pair kerning.
# Offsets are always zero and clusters are code point indices (converted to
# UTF-8 byte offsets for `--utf8-clusters`). A code point the font does not
# map is drawn with glyph 0, as hb-shape does; that is this driver's choice,
# not the package's.
shape : Font, Case.Settings, List(U32) -> Str
shape = |font, settings, scalars| {
	var $items = List.with_capacity(scalars.len())
	var $index = 0
	for code_point in scalars {
		$items = $items.append({ glyph: Font.glyph(font, code_point) ?? 0, cluster: $index })
		$index = $index + 1
	}
	glyphs = Font.substitute(font, $items)
	kerning = Font.kerning(font, glyphs.map(|g| g.glyph))
	offsets = Case.utf8_offsets(scalars)
	var $run = List.with_capacity(glyphs.len())
	var $i = 0
	for g in glyphs {
		advance = Font.advance(font, g.glyph) + (kerning.get($i) ?? 0.0)
		cluster = if (settings.utf8) (offsets.get(g.cluster) ?? 0) else g.cluster
		$run = $run.append({ glyph: g.glyph, cluster, dx: 0, dy: 0, ax: advance.to_i64_wrap(), ay: 0 })
		$i = $i + 1
	}
	Case.serialize(settings, $run)
}
