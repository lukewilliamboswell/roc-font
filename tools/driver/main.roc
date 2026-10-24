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

## A font read for the driver: measured at its default location (protocol
## 1 compares with HarfBuzz's default instance; without `at` a variable font
## measures at Regular), with the tags of the tables lenient reading dropped.
FontState : [Ready({ font : Font, dropped : List(Str) }), Rejected(Str), NoFile]

load! : Str => FontState
load! = |path|
	match Path.read_bytes!(Path.utf8(path)) {
		Err(_) => NoFile
		Ok(bytes) =>
			match Font.from_bytes(bytes, Font.ReadOptions.{}) {
				Ok(read) => {
					axes = Font.axes(read).map(|a| { tag: a.tag, value: a.default })
					font = Font.at(read, Font.Variation.{ axes })
					Ready({ font, dropped: dropped_tags(Font.dropped(read)) })
				}
				Err(problems) => Rejected(Str.inspect(problems))
			}
	}

# The tags of the tables a reading result can name (the oracle's
# `READ_TABLES`), each once, sorted as the oracle sorts them.
dropped_tags : List(Font.Problem) -> List(Str)
dropped_tags = |problems| {
	known = ["GPOS", "GSUB", "OS/2", "cmap", "glyf", "head", "hhea", "hmtx", "kern", "loca", "maxp"]
	var $tags = []
	for p in problems {
		match p {
			BadTable(b) if known.contains(b.table) and !$tags.contains(b.table) => {
				$tags = $tags.append(b.table)
			}
			_ => {}
		}
	}
	# `known` is in the oracle's order.
	known.keep_if(|t| $tags.contains(t))
}

run : FontState, Case.Request -> Str
run = |state, req|
	match state {
		NoFile => "error:font-file"
		Rejected(_) => "read:reject"
		Ready({ font, dropped }) =>
			match req.kind {
				Read => if (dropped.is_empty()) "read:accept" else "read:drop=${Str.join_with(dropped, ",")}"
				Width => Case.width(glyphs(font, req.settings, req.scalars))
				Shape =>
					if req.settings.font_size != 0 and req.settings.font_size != Font.units_per_em(font).to_u64() {
						"unsupported:--font-size=${req.settings.font_size.to_str()}"
					} else {
						Case.serialize(req.settings, glyphs(font, req.settings, req.scalars))
					}
			}
	}

# Shape the scalars with the default options. Each scalar's offset is its
# UTF-8 byte offset (`utf8-clusters`) or its index, so the run's clusters
# are already what hb-shape prints. A code point the font does not map is
# drawn with glyph 0, as in hb-shape.
glyphs : Font, Case.Settings, List(U32) -> List(Case.Glyph)
glyphs = |font, settings, scalars| {
	offsets = Case.utf8_offsets(scalars)
	items = scalars.map_with_index(|scalar, i| { scalar, offset: (if (settings.utf8) offsets.get(i) ?? 0 else i).to_u32_wrap() })
	shaped = Font.shape_scalars(font, Font.plan(font, Font.ShapeOptions.{}), items)
	var $out = List.with_capacity(shaped.glyphs.len())
	for i in 0..<shaped.glyphs.len() {
		advance = shaped.advances.get(i) ?? { x: 0, y: 0 }
		offset = shaped.offsets.get(i) ?? { x: 0, y: 0 }
		$out = $out.append({ glyph: (shaped.glyphs.get(i) ?? 0).to_u64(), cluster: (shaped.clusters.get(i) ?? 0).to_u64(), dx: offset.x.to_i64(), dy: offset.y.to_i64(), ax: advance.x.to_i64(), ay: advance.y.to_i64() })
	}
	$out
}
