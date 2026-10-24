app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.23.0/GNN5tt2gKdX4dhawg4915C4YB193woHFdcCkz31fhGxv.tar.zst",
	rf: "../../package/main.roc",
}

import cli.OsStr
import cli.Path
import cli.Stdin
import cli.Stdout
import rf.Font
import Case

## Conformance driver. Reads requests on stdin, one per line, in the protocol
## of Case.roc (written by scripts/conformance.py from the JSONC case files),
## reads each distinct font once, and prints one line per request, in order:
##
##     <tag><TAB><result>
##
## A result is hb-shape notation with glyph ids, `width:<n>`, `read:accept`,
## `read:reject`, `unsupported:--font-size=<n>` (a size other than the units
## per em), `error:font-file` (the font could not be read from disk) or
## `error:malformed-request:<why>`. See docs/conformance.adoc.
##
## With `--explain` as an argument, a rejected font's line gets a third
## tab-separated column listing the reader's problems. It is for triage and
## is never compared with oracle records.
main! : List(OsStr) => Try({}, _)
main! = |args| {
	explain = args.map(OsStr.display).contains("--explain")
	input = match Stdin.read_to_end!() {
		Ok(bytes) => Str.from_utf8_lossy(bytes)
		Err(_) => ""
	}
	var $fonts = Dict.with_capacity(16)
	var $out = []
	for line in input.split_on("\n") {
		if !line.is_empty() {
			match Case.request(line) {
				Ok(req) => {
					state = match $fonts.get(req.font) {
						Ok(found) => found
						Err(_) => {
							loaded = load!(req.font)
							$fonts = $fonts.insert(req.font, loaded)
							loaded
						}
					}
					why = match state {
						Rejected(problems) if explain => "\t${problems}"
						_ => ""
					}
					$out = $out.append("${req.tag}\t${run(state, req)}${why}")
				}
				Err(Malformed(bad)) => {
					$out = $out.append("${bad.tag}\terror:malformed-request:${bad.why}")
				}
			}
		}
	}
	if !$out.is_empty() {
		Stdout.write!("${Str.join_with($out, "\n")}\n") ?? {}
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

run : FontState, Case.Request -> Str
run = |state, req|
	match state {
		NoFile => "error:font-file"
		Rejected(_) => "read:reject"
		Ready(font) =>
			match req.kind {
				Read => "read:accept"
				Width => Case.width(glyphs(font, req.settings, req.scalars))
				Shape =>
					if req.settings.font_size != 0 and req.settings.font_size.to_f64() != Font.units_per_em(font) {
						"unsupported:--font-size=${req.settings.font_size.to_str()}"
					} else {
						Case.serialize(req.settings, glyphs(font, req.settings, req.scalars))
					}
			}
	}

# The current public API shapes in four steps: map code points to glyphs,
# apply the default substitutions, take advances and add pair kerning.
# Offsets are always zero and clusters are code point indices (converted to
# UTF-8 byte offsets for `utf8-clusters`). A code point the font does not
# map is drawn with glyph 0, as hb-shape does; that is this driver's choice,
# not the package's.
glyphs : Font, Case.Settings, List(U32) -> List(Case.Glyph)
glyphs = |font, settings, scalars| {
	var $items = List.with_capacity(scalars.len())
	var $index = 0
	for code_point in scalars {
		$items = $items.append({ glyph: Font.glyph(font, code_point) ?? 0, cluster: $index })
		$index = $index + 1
	}
	substituted = Font.substitute(font, $items)
	kerning = Font.kerning(font, substituted.map(|g| g.glyph))
	offsets = Case.utf8_offsets(scalars)
	var $run = List.with_capacity(substituted.len())
	var $i = 0
	for g in substituted {
		advance = Font.advance(font, g.glyph) + (kerning.get($i) ?? 0.0)
		cluster = if (settings.utf8) (offsets.get(g.cluster) ?? 0) else g.cluster
		$run = $run.append({ glyph: g.glyph, cluster, dx: 0, dy: 0, ax: advance.to_i64_wrap(), ay: 0 })
		$i = $i + 1
	}
	$run
}
