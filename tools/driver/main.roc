app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	rf: "../../package/main.roc",
}

import cli.OsStr
import cli.Path
import cli.Stdin
import cli.Stdout
import rf.Font
import Case
import Metadata

## Conformance driver. Reads requests on stdin, one per line, in the protocol
## of Case.roc (written by scripts/conformance.py from the JSONC case files),
## reads each distinct font once, and prints one line per request, in order:
##
##     <tag><TAB><result>
##
## Protocol 2: each distinct (font path, face) is read once; every request
## then measures at its own location with `Font.at`, which is cheap.
## Protocol 3: shaping requests carry their script, language, direction,
## features and cluster level.
##
## A result is hb-shape notation with glyph ids, `width:<n>`, `read:accept`,
## `read:reject`, `read:drop=<tags>`, a font-fact result (`coords:`,
## `advances:`, `metrics:`, `extents:`), `unsupported:<what>` (a font size
## other than the units per em, or a named instance past the font's),
## `error:font-file` (the font could not be read from disk) or
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
					key = "${req.face.to_str()}\t${req.font}"
					state = match $fonts.get(key) {
						Ok(found) => found
						Err(_) => {
							loaded = load!(req.font, req.face)
							$fonts = $fonts.insert(key, loaded)
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

## A font read for the driver, at `Font.Variation.{}` (Regular, as
## `from_bytes` leaves it), with the tags of the tables lenient reading
## dropped.
FontState : [Ready({ font : Font, dropped : List(Str) }), Rejected(Str), NoFile]

load! : Str, U32 => FontState
load! = |path, face|
	match Path.read_bytes!(Path.utf8(path)) {
		Err(_) => NoFile
		Ok(bytes) =>
			match Font.from_bytes(bytes, Font.ReadOptions.{ face }) {
				Ok(font) => Ready({ font, dropped: dropped_tags(Font.dropped(font)) })
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
		Ready({ font: read, dropped }) =>
			match req.location {
				# A named instance is its axis values; an index past the
				# font's instances is an oracle error, never recorded.
				Instance(n) =>
					match Font.instances(read).get(n.to_u64()) {
						Ok(instance) => answer(Font.at(read, Font.Variation.{ axes: instance.axes }), dropped, req)
						Err(_) => "unsupported:instance"
					}
				Regular => answer(read, dropped, req)
				At(v) => answer(Font.at(read, Font.Variation.{ weight: v.weight, width: v.width, optical_size: v.optical_size, axes: v.axes }), dropped, req)
			}
	}

answer : Font, List(Str), Case.Request -> Str
answer = |font, dropped, req|
	match req.kind {
		Metadata => Metadata.serialize(font)
		Read => if (dropped.is_empty()) "read:accept" else "read:drop=${Str.join_with(dropped, ",")}"
		Width => Case.width(glyphs(font, req.settings, req.shaping, req.scalars))
		Shape =>
			if req.settings.font_size != 0 and req.settings.font_size != Font.units_per_em(font).to_u64() {
				"unsupported:--font-size=${req.settings.font_size.to_str()}"
			} else {
				Case.serialize(req.settings, glyphs(font, req.settings, req.shaping, req.scalars))
			}
		Coords => "coords:${Str.join_with(Font.coordinates(font).map(|c| "${c.tag}=${c.value.to_str()}"), ",")}"
		Advances(which) => Case.advances(ids(font, which).map(|g| Font.advance(font, g).to_i64()))
		Metrics => {
			m = Font.metrics(font)
			# roc-font's descent is a depth (positive below the baseline);
			# the notation's is a position, as HarfBuzz reports it.
			Case.metrics({ ascent: m.ascent.to_i64(), descent: -(m.descent.to_i64()), line_gap: m.line_gap.to_i64(), cap_height: m.cap_height.to_i64(), x_height: m.x_height.to_i64(), underline_position: m.underline.position.to_i64(), underline_thickness: m.underline.thickness.to_i64(), strikeout_position: m.strikeout.position.to_i64(), strikeout_thickness: m.strikeout.thickness.to_i64() })
		}
		Extents(which) =>
			Case.extents(
				ids(font, which).map(
					|g|
						match Font.extents(font, g) {
							Extents(b) => { glyph: g.to_u64(), box: Box({ x_min: b.x_min.to_i64(), y_min: b.y_min.to_i64(), x_max: b.x_max.to_i64(), y_max: b.y_max.to_i64() }) }
							Empty => { glyph: g.to_u64(), box: Empty }
							# Outlines roc-font does not read (CFF): no box, as
							# before the public API told the two apart.
							Unknown => { glyph: g.to_u64(), box: Empty }
						},
				),
			)
	}

# The glyph ids a font-fact request lists: `all` is every glyph in order.
ids : Font, Case.Glyphs -> List(U32)
ids = |font, which|
	match which {
		All => {
			count = Font.glyph_count(font)
			var $out = List.with_capacity(count.to_u64())
			for g in 0..<count {
				$out = $out.append(g)
			}
			$out
		}
		Listed(list) => list
	}

# Shape the scalars with the request's shaping options (the defaults
# without shaping flags). Each scalar's offset is its UTF-8 byte offset
# (`utf8-clusters`) or its index, so the run's clusters are already what
# hb-shape prints, and feature ranges count in the same units, as
# hb-shape's do. A code point the font does not map is drawn with glyph
# 0, as in hb-shape.
glyphs : Font, Case.Settings, Case.Shaping, List(U32) -> List(Case.Glyph)
glyphs = |font, settings, shaping, scalars| {
	offsets = Case.utf8_offsets(scalars)
	items = scalars.map_with_index(|scalar, i| { scalar, offset: if (settings.utf8) offsets.get(i) ?? 0 else i })
	features = shaping.features.map(|f| Font.Feature.{ tag: f.tag, value: f.value, start: f.start, end: f.end })
	options = Font.ShapeOptions.{ script: shaping.script, language: shaping.language, direction: shaping.direction, features, clusters: shaping.clusters }
	plan = Font.plan(font, options)
	shaped = match settings.text_range {
		Whole => Font.shape_scalars(font, plan, items)
		Range(range) => Font.shape_range(font, plan, scalar_text(scalars), Font.TextRange.{ start: range.start, end: range.end })
	}
	var $out = List.with_capacity(shaped.glyphs.len())
	for i in 0..<shaped.glyphs.len() {
		advance = shaped.advances.get(i) ?? { x: 0, y: 0 }
		offset = shaped.offsets.get(i) ?? { x: 0, y: 0 }
		$out = $out.append({ glyph: (shaped.glyphs.get(i) ?? 0).to_u64(), cluster: (shaped.clusters.get(i) ?? 0).to_u64(), dx: offset.x.to_i64(), dy: offset.y.to_i64(), ax: advance.x.to_i64(), ay: advance.y.to_i64(), flags: if (Font.is_unsafe_to_break(shaped.flags.get(i) ?? 0)) 1 else 0 })
	}
	$out
}

# Case parsing proved these are Unicode scalar values.
scalar_text : List(U32) -> Str
scalar_text = |scalars| {
	bytes = scalars.join_map(
		|cp|
			if cp < 0x80 {
				[cp]
			}
			else if cp < 0x800 {
				[0xC0 + cp.shr_zf_wrap(6), 0x80 + cp.bitwise_and(63)]
			}
			else if cp < 0x10000 {
				[0xE0 + cp.shr_zf_wrap(12), 0x80 + cp.shr_zf_wrap(6).bitwise_and(63), 0x80 + cp.bitwise_and(63)]
			}
			else {
				[0xF0 + cp.shr_zf_wrap(18), 0x80 + cp.shr_zf_wrap(12).bitwise_and(63), 0x80 + cp.shr_zf_wrap(6).bitwise_and(63), 0x80 + cp.bitwise_and(63)]
			},
	)
	Str.from_utf8(bytes.map(|b| b.to_u8_wrap())) ?? ""
}
