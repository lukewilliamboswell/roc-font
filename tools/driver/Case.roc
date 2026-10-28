## The driver's request protocol and result notation, without effects.
##
## `scripts/conformance.py` parses the JSONC case files and sends one request
## per line (scripts/_common.py, `driver_request`):
##
##     <tag> TAB <font path> TAB <kind> TAB <items> TAB <flags>
##
## `kind` is `shape`, `read`, `width`, `coords`, `advances`, `metrics` or
## `extents`. Items are lower-case hexadecimal without prefix,
## comma-separated: code points for `shape` and `width` (empty for empty
## text), glyph ids or the word `all` for `advances` and `extents`, empty
## for the other kinds. Flags are comma-separated, from `no-clusters`,
## `no-positions`, `no-advances`, `utf8-clusters` and `font-size=<n>`, and
## (protocol 2) `face=<n>`, `instance=<n>`, `weight=<w>`, `width=<w>`,
## `optical-size=<s>` and repeatable `axis=<tag>:<decimal>`, and (protocol
## 3) the shaping options `direction=ltr|rtl`, `script=<ISO 15924>`,
## `language=<BCP 47>`, `cluster-level=0|1` and repeatable
## `feature=<tag>:<value>:<start>:<end>` (`end` is `*` for the end of the
## text). Shaping results are printed in hb-shape's text notation with
## glyph ids: `[gid=cluster@dx,dy+ax,ay|...]`. See docs/conformance.adoc.
Case :: {}.{

	## Which glyphs a font-fact request lists: every glyph of the font, in
	## order, or the given ids in request order.
	Glyphs : [All, Listed(List(U32))]

	## What a request asks for.
	Kind : [Shape, Read, Width, Coords, Advances(Glyphs), Metrics, Metadata, Extents(Glyphs)]

	## The output settings of a shaping request. `font_size` is 0 when not
	## given.
	Settings : { clusters : Bool, positions : Bool, advances : Bool, utf8 : Bool, font_size : U64, text_range : [Whole, Range({ start : U64, end : U64 })] }

	## Where to measure, mirroring `Font.Variation` (whose field types these
	## are, structurally) and named instances.
	Variation : {
		weight : [Thin, ExtraLight, Light, Regular, Medium, SemiBold, Bold, ExtraBold, Black, Weight(U16)],
		width : [UltraCondensed, ExtraCondensed, Condensed, SemiCondensed, Normal, SemiExpanded, Expanded, ExtraExpanded, UltraExpanded, Percent(Dec)],
		optical_size : [FontDefault, Size(Dec)],
		axes : List({ tag : Str, value : Dec }),
	}

	## No location flag (`Font.Variation.{}`, Regular), a named instance, or
	## a variation built from the location flags.
	Location : [Regular, Instance(U32), At(Variation)]

	## The shaping options, mirroring `Font.ShapeOptions` (whose field types
	## these are, structurally); with no shaping flag, the defaults.
	Shaping : {
		script : Str,
		language : Str,
		direction : [FromScript, LeftToRight, RightToLeft],
		features : List({ tag : Str, value : U32, start : U64, end : U64 }),
		clusters : [Graphemes, Characters],
	}

	## Everything the flags field selects.
	Flags : { settings : Settings, face : U32, location : Location, shaping : Shaping }

	## One parsed request line.
	Request : { tag : Str, font : Str, kind : Kind, scalars : List(U32), settings : Settings, face : U32, location : Location, shaping : Shaping }

	## The shaping options with no shaping flag: `Font.ShapeOptions.{}`.
	default_shaping : Shaping
	default_shaping = { script: "", language: "", direction: FromScript, features: [], clusters: Graphemes }

	## One positioned output glyph, in font units.
	Glyph : { glyph : U64, cluster : U64, dx : I64, dy : I64, ax : I64, ay : I64 }

	## Parse one request line. A malformed line yields its tag (the text
	## before the first tab, or the whole line) and what was wrong.
	request : Str -> Try(Request, [Malformed({ tag : Str, why : Str })])
	request = |line|
		match line.split_on("\t") {
			[tag, font, kind_text, points, flag_text] => {
				parsed = match kind_text {
					"shape" => Case.scalars(points).map_ok(|s| (Shape, s))
					"width" => Case.scalars(points).map_ok(|s| (Width, s))
					"advances" => Case.glyph_ids(points).map_ok(|g| (Advances(g), []))
					"extents" => Case.glyph_ids(points).map_ok(|g| (Extents(g), []))
					"read" => if (points.is_empty()) Ok((Read, [])) else Err(BadItems)
					"coords" => if (points.is_empty()) Ok((Coords, [])) else Err(BadItems)
					"metrics" => if (points.is_empty()) Ok((Metrics, [])) else Err(BadItems)
					"metadata" => if (points.is_empty()) Ok((Metadata, [])) else Err(BadItems)
					_ => Err(BadKind)
				}
				match (parsed, Case.flags(flag_text)) {
					(Ok((kind, scalars)), Ok(f)) =>
						if (tag.is_empty() or font.is_empty()) Err(Malformed({ tag, why: "empty-field" })) else Ok({ tag, font, kind, scalars, settings: f.settings, face: f.face, location: f.location, shaping: f.shaping })
					(Err(BadKind), _) => Err(Malformed({ tag, why: "kind" }))
					(Err(BadUnicodes), _) => Err(Malformed({ tag, why: "code-points" }))
					(Err(_), _) => Err(Malformed({ tag, why: "items" }))
					(_, Err(flag)) => Err(Malformed({ tag, why: "flag-${flag}" }))
				}
			}
			[tag, ..] => Err(Malformed({ tag, why: "fields" }))
			[] => Err(Malformed({ tag: "", why: "fields" }))
		}

	## The settings, face and location from the comma-separated flags field,
	## or the first flag not understood. `instance` cannot be combined with
	## the other location flags.
	flags : Str -> Try(Flags, Str)
	flags = |field| {
		var $s = { clusters: True, positions: True, advances: True, utf8: False, font_size: 0, text_range: Whole }
		var $face = 0.U32
		var $instance = 0.U32
		var $has_instance = False
		var $v = { weight: Regular, width: Normal, optical_size: FontDefault, axes: [] }
		var $varied = False
		var $shaping = Case.default_shaping
		var $bad = ""
		for flag in field.split_on(",") {
			if $bad.is_empty() and !flag.is_empty() {
				if flag.starts_with("direction=") or flag.starts_with("script=") or flag.starts_with("language=") or flag.starts_with("cluster-level=") or flag.starts_with("feature=") {
					match Case.shaping_flag($shaping, flag) {
						Ok(next) => {
							$shaping = next
						}
						Err(_) => {
							$bad = flag
						}
					}
				} else if flag == "no-clusters" {
					$s = { ..$s, clusters: False }
				} else if flag == "no-positions" {
					$s = { ..$s, positions: False }
				} else if flag == "no-advances" {
					$s = { ..$s, advances: False }
				} else if flag == "utf8-clusters" {
					$s = { ..$s, utf8: True }
				} else if flag.starts_with("text-range=") {
					match flag.drop_prefix("text-range=").split_on(":") {
						[start, end] => match (Case.decimal(start), Case.decimal(end)) {
							(Ok(a), Ok(b)) => {
								$s = { ..$s, text_range: Range({ start: a, end: b }), utf8: True }
							}
							_ => {
								$bad = flag
							}
						}
						_ => {
							$bad = flag
						}
					}
				} else if flag.starts_with("font-size=") {
					match Case.decimal(flag.drop_prefix("font-size=")) {
						Ok(size) if size > 0 => {
							$s = { ..$s, font_size: size }
						}
						_ => {
							$bad = flag
						}
					}
				} else if flag.starts_with("face=") {
					match Case.decimal(flag.drop_prefix("face=")) {
						Ok(n) if n <= 0xFFFF => {
							$face = n.to_u32_wrap()
						}
						_ => {
							$bad = flag
						}
					}
				} else if flag.starts_with("instance=") {
					match Case.decimal(flag.drop_prefix("instance=")) {
						Ok(n) if n <= 0xFFFF and !$varied => {
							$instance = n.to_u32_wrap()
							$has_instance = True
						}
						_ => {
							$bad = flag
						}
					}
				} else {
					# The location flags; each is refused after `instance`.
					parsed = if $has_instance {
						Err({})
					} else if flag.starts_with("weight=") {
						Case.weight(flag.drop_prefix("weight=")).map_ok(|w| { ..$v, weight: w })
					} else if flag.starts_with("width=") {
						Case.width_flag(flag.drop_prefix("width=")).map_ok(|w| { ..$v, width: w })
					} else if flag.starts_with("optical-size=") {
						text = flag.drop_prefix("optical-size=")
						if (text == "FontDefault") Ok({ ..$v, optical_size: FontDefault }) else Case.dec(text).map_ok(|d| { ..$v, optical_size: Size(d) })
					} else if flag.starts_with("axis=") {
						match flag.drop_prefix("axis=").split_first(":") {
							Ok({ before, after }) if !before.is_empty() => Case.dec(after).map_ok(|d| { ..$v, axes: $v.axes.append({ tag: before, value: d }) })
							_ => Err({})
						}
					} else {
						Err({})
					}
					match parsed {
						Ok(next) => {
							$v = next
							$varied = True
						}
						Err(_) => {
							$bad = flag
						}
					}
				}
			}
		}
		location = if $has_instance {
			Instance($instance)
		} else if $varied {
			At($v)
		} else {
			Regular
		}
		if ($bad.is_empty()) Ok({ settings: $s, face: $face, location, shaping: $shaping }) else Err($bad)
	}

	## The shaping options after one shaping flag (protocol 3), or `Err`
	## when its value is not understood. Features accumulate in order.
	shaping_flag : Shaping, Str -> Try(Shaping, {})
	shaping_flag = |shaping, flag|
		if flag.starts_with("direction=") {
			match flag.drop_prefix("direction=") {
				"ltr" => Ok({ ..shaping, direction: LeftToRight })
				"rtl" => Ok({ ..shaping, direction: RightToLeft })
				_ => Err({})
			}
		} else if flag.starts_with("script=") {
			text = flag.drop_prefix("script=")
			if (text.is_empty()) Err({}) else Ok({ ..shaping, script: text })
		} else if flag.starts_with("language=") {
			text = flag.drop_prefix("language=")
			if (text.is_empty()) Err({}) else Ok({ ..shaping, language: text })
		} else if flag.starts_with("cluster-level=") {
			match flag.drop_prefix("cluster-level=") {
				"0" => Ok({ ..shaping, clusters: Graphemes })
				"1" => Ok({ ..shaping, clusters: Characters })
				_ => Err({})
			}
		} else {
			match flag.drop_prefix("feature=").split_on(":") {
				[tag, value_text, start_text, end_text] if !tag.is_empty() =>
					match (Case.decimal_digits(value_text), Case.decimal_digits(start_text), Case.feature_end(end_text)) {
						(Ok(value), Ok(start), Ok(end)) if value <= 0xFFFFFFFF => Ok({ ..shaping, features: shaping.features.append({ tag, value: value.to_u32_wrap(), start, end }) })
						_ => Err({})
					}
				_ => Err({})
			}
		}

	## A feature range's end: `*` for the end of the text, or a decimal.
	feature_end : Str -> Try(U64, {})
	feature_end = |text| if (text == "*") Ok(18_446_744_073_709_551_615) else Case.decimal_digits(text)

	## `Font.Variation.weight` from a flag value: a CSS weight name or a
	## decimal integer 0-65535.
	weight : Str -> Try([Thin, ExtraLight, Light, Regular, Medium, SemiBold, Bold, ExtraBold, Black, Weight(U16)], {})
	weight = |text|
		match text {
			"Thin" => Ok(Thin)
			"ExtraLight" => Ok(ExtraLight)
			"Light" => Ok(Light)
			"Regular" => Ok(Regular)
			"Medium" => Ok(Medium)
			"SemiBold" => Ok(SemiBold)
			"Bold" => Ok(Bold)
			"ExtraBold" => Ok(ExtraBold)
			"Black" => Ok(Black)
			_ =>
				match Case.decimal(text) {
					Ok(n) if n <= 0xFFFF => Ok(Weight(n.to_u16_wrap()))
					_ => Err({})
				}
		}

	## `Font.Variation.width` from a flag value: a CSS width name or a
	## decimal percentage.
	width_flag : Str -> Try([UltraCondensed, ExtraCondensed, Condensed, SemiCondensed, Normal, SemiExpanded, Expanded, ExtraExpanded, UltraExpanded, Percent(Dec)], {})
	width_flag = |text|
		match text {
			"UltraCondensed" => Ok(UltraCondensed)
			"ExtraCondensed" => Ok(ExtraCondensed)
			"Condensed" => Ok(Condensed)
			"SemiCondensed" => Ok(SemiCondensed)
			"Normal" => Ok(Normal)
			"SemiExpanded" => Ok(SemiExpanded)
			"Expanded" => Ok(Expanded)
			"ExtraExpanded" => Ok(ExtraExpanded)
			"UltraExpanded" => Ok(UltraExpanded)
			_ => Case.dec(text).map_ok(|d| Percent(d))
		}

	## A decimal `-?[0-9]+(.[0-9]+)?` with at most 10 integer digits and 18
	## decimal places, exactly, as a `Dec`.
	dec : Str -> Try(Dec, {})
	dec = |text| {
		negative = text.starts_with("-")
		body = text.drop_prefix("-")
		(whole, fraction, has_point) = match body.split_first(".") {
			Ok({ before, after }) => (before, after, True)
			Err(_) => (body, "", False)
		}
		fraction_digits = fraction.to_utf8()
		ok = (!has_point or !fraction_digits.is_empty()) and fraction_digits.len() <= 18 and whole.to_utf8().len() <= 10
		match (Case.decimal_digits(whole), Case.decimal_digits_or_empty(fraction)) {
			(Ok(w), Ok(f)) if ok => {
				var $scale = 1.I128
				for _ in fraction_digits.len()..<18 {
					$scale = $scale * 10
				}
				attos = w.to_i128() * 1_000_000_000_000_000_000 + f.to_i128() * $scale
				Ok(Dec.from_attos(if (negative) -attos else attos))
			}
			_ => Err({})
		}
	}

	## Decimal digits (at least one, at most 18) as a number.
	decimal_digits : Str -> Try(U64, {})
	decimal_digits = |text| {
		digits = text.to_utf8()
		var $value = 0.U64
		var $ok = !digits.is_empty() and digits.len() <= 18
		for b in digits {
			if b >= '0' and b <= '9' {
				$value = $value * 10 + (b - '0').to_u64()
			} else {
				$ok = False
			}
		}
		if ($ok) Ok($value) else Err({})
	}

	decimal_digits_or_empty : Str -> Try(U64, {})
	decimal_digits_or_empty = |text| if (text.is_empty()) Ok(0) else Case.decimal_digits(text)

	## Glyph ids from the request field: `all`, or hexadecimal numbers below
	## 2^32 without prefix, separated by commas. Empty means none.
	glyph_ids : Str -> Try(Glyphs, [BadGlyphs])
	glyph_ids = |field|
		if field == "all" {
			Ok(All)
		} else {
			var $out = []
			var $ok = True
			if !field.is_empty() {
				for word in field.split_on(",") {
					match Case.hex_digits(word, 8) {
						Ok(value) => {
							$out = $out.append(value.to_u32_wrap())
						}
						Err(_) => {
							$ok = False
						}
					}
				}
			}
			if ($ok) Ok(Listed($out)) else Err(BadGlyphs)
		}

	decimal : Str -> Try(U64, [BadNumber])
	decimal = |text| {
		digits = text.to_utf8()
		var $value = 0.U64
		var $ok = !digits.is_empty() and digits.len() <= 9
		for b in digits {
			if b >= '0' and b <= '9' {
				$value = $value * 10 + (b - '0').to_u64()
			} else {
				$ok = False
			}
		}
		if ($ok) Ok($value) else Err(BadNumber)
	}

	## Code points from the request field: lower- or upper-case hexadecimal
	## numbers without prefix, separated by commas. Empty means empty text.
	scalars : Str -> Try(List(U32), [BadUnicodes])
	scalars = |field| {
		var $out = []
		var $ok = True
		if !field.is_empty() {
			for word in field.split_on(",") {
				match Case.hex(word) {
					Ok(value) => {
						$out = $out.append(value)
					}
					Err(_) => {
						$ok = False
					}
				}
			}
		}
		if ($ok) Ok($out) else Err(BadUnicodes)
	}

	hex : Str -> Try(U32, [BadHex])
	hex = |word|
		match Case.hex_digits(word, 6) {
			# Surrogates and values past U+10FFFF are not scalar values.
			Ok(value) if value <= 0x10FFFF and (value < 0xD800 or value > 0xDFFF) => Ok(value.to_u32_wrap())
			_ => Err(BadHex)
		}

	## One to `most` hexadecimal digits, either case, as a number.
	hex_digits : Str, U64 -> Try(U64, {})
	hex_digits = |word, most| {
		digits = word.to_utf8()
		var $value = 0.U64
		var $ok = !digits.is_empty() and digits.len().to_u64() <= most
		for b in digits {
			d = if b >= '0' and b <= '9' {
				Ok((b - '0').to_u64())
			} else if b >= 'a' and b <= 'f' {
				Ok((b - 'a').to_u64() + 10)
			} else if b >= 'A' and b <= 'F' {
				Ok((b - 'A').to_u64() + 10)
			} else {
				Err({})
			}
			match d {
				Ok(v) => {
					$value = $value * 16 + v
				}
				Err(_) => {
					$ok = False
				}
			}
		}
		if ($ok) Ok($value) else Err({})
	}

	## The UTF-8 byte offset of each scalar, followed by the total length, so
	## a scalar index maps to the byte cluster hb-shape `--utf8-clusters`
	## prints.
	utf8_offsets : List(U32) -> List(U64)
	utf8_offsets = |code_points| {
		var $out = List.with_capacity(code_points.len() + 1)
		var $at = 0.U64
		for s in code_points {
			$out = $out.append($at)
			width = if (s < 0x80) 1 else if (s < 0x800) 2 else if (s < 0x10000) 3 else 4
			$at = $at + width
		}
		$out.append($at)
	}

	## A run in hb-shape text notation, as `hb_buffer_serialize` writes it
	## with `HB_BUFFER_SERIALIZE_FLAG_NO_GLYPH_NAMES`: offsets only when
	## non-zero, a vertical advance only when non-zero, and with
	## `no-advances` the offsets become pen positions. An empty run is `[]`.
	serialize : Settings, List(Glyph) -> Str
	serialize = |s, glyphs| {
		var $parts = List.with_capacity(glyphs.len())
		var $x = 0.I64
		var $y = 0.I64
		for g in glyphs {
			cluster = if (s.clusters) "=${g.cluster.to_str()}" else ""
			px = $x + g.dx
			py = $y + g.dy
			offset = if (s.positions and (px != 0 or py != 0)) "@${px.to_str()},${py.to_str()}" else ""
			advance = if s.positions and s.advances {
				if (g.ay != 0) "+${g.ax.to_str()},${g.ay.to_str()}" else "+${g.ax.to_str()}"
			} else {
				""
			}
			if !s.advances {
				$x = $x + g.ax
				$y = $y + g.ay
			}
			$parts = $parts.append("${g.glyph.to_str()}${cluster}${offset}${advance}")
		}
		"[${Str.join_with($parts, "|")}]"
	}

	## The total horizontal advance of a run, as a width result.
	width : List(Glyph) -> Str
	width = |glyphs| {
		var $sum = 0.I64
		for g in glyphs {
			$sum = $sum + g.ax
		}
		"width:${$sum.to_str()}"
	}

	## Per-glyph advances as a font-fact result.
	advances : List(I64) -> Str
	advances = |values| "advances:${Str.join_with(values.map(|a| a.to_str()), ",")}"

	## The nine line and decoration metrics as a font-fact result, in the
	## notation's order (descent negative below the baseline).
	metrics : { ascent : I64, descent : I64, line_gap : I64, cap_height : I64, x_height : I64, underline_position : I64, underline_thickness : I64, strikeout_position : I64, strikeout_thickness : I64 } -> Str
	metrics = |m| {
		pairs = [
			("ascent", m.ascent),
			("descent", m.descent),
			("line_gap", m.line_gap),
			("cap_height", m.cap_height),
			("x_height", m.x_height),
			("underline_position", m.underline_position),
			("underline_thickness", m.underline_thickness),
			("strikeout_position", m.strikeout_position),
			("strikeout_thickness", m.strikeout_thickness),
		]
		"metrics:${Str.join_with(pairs.map(|(name, value)| "${name}=${value.to_str()}"), ",")}"
	}

	## Glyph ink boxes as a font-fact result, one entry per glyph in request
	## order.
	extents : List({ glyph : U64, box : [Box({ x_min : I64, y_min : I64, x_max : I64, y_max : I64 }), Empty] }) -> Str
	extents = |entries| {
		parts = entries.map(
			|e|
				match e.box {
					Box(b) => "${e.glyph.to_str()}=${b.x_min.to_str()},${b.y_min.to_str()},${b.x_max.to_str()},${b.y_max.to_str()}"
					Empty => "${e.glyph.to_str()}=empty"
				},
		)
		"extents:${Str.join_with(parts, "|")}"
	}
}

plain : Case.Settings
plain = { clusters: True, positions: True, advances: True, utf8: False, font_size: 0, text_range: Whole }

expect Case.request("inter/a\tf.ttf\tshape\t41,1f600\tutf8-clusters") == Ok({ tag: "inter/a", font: "f.ttf", kind: Shape, scalars: [0x41, 0x1F600], settings: { ..plain, utf8: True }, face: 0, location: Regular, shaping: Case.default_shaping })
expect Case.request("reading/x\tf.ttf\tread\t\t") == Ok({ tag: "reading/x", font: "f.ttf", kind: Read, scalars: [], settings: plain, face: 0, location: Regular, shaping: Case.default_shaping })
expect Case.request("w\tf.ttf\twidth\t48,49\t") == Ok({ tag: "w", font: "f.ttf", kind: Width, scalars: [0x48, 0x49], settings: plain, face: 0, location: Regular, shaping: Case.default_shaping })
expect Case.request("t\tf.ttf\tshape\t41\tno-clusters,no-advances,font-size=1000") == Ok({ tag: "t", font: "f.ttf", kind: Shape, scalars: [0x41], settings: { ..plain, clusters: False, advances: False, font_size: 1000 }, face: 0, location: Regular, shaping: Case.default_shaping })
expect Case.request("t\tf.ttf\tshape\t41") == Err(Malformed({ tag: "t", why: "fields" }))
expect Case.request("t\tf.ttf\tdraw\t41\t") == Err(Malformed({ tag: "t", why: "kind" }))
expect Case.request("t\tf.ttf\tshape\td800\t") == Err(Malformed({ tag: "t", why: "code-points" }))
expect Case.request("t\tf.ttf\tshape\t41\tbold") == Err(Malformed({ tag: "t", why: "flag-bold" }))
expect Case.request("t\t\tshape\t41\t") == Err(Malformed({ tag: "t", why: "empty-field" }))
expect Case.scalars("41,1F600") == Ok([0x41, 0x1F600])
expect Case.scalars("") == Ok([])
expect Case.scalars("41,,42") == Err(BadUnicodes)
expect Case.scalars("110000") == Err(BadUnicodes)
expect Case.scalars("U+0041") == Err(BadUnicodes)
expect Case.flags("font-size=0") == Err("font-size=0")
expect Case.request("t\tf.ttf\tcoords\t41\t") == Err(Malformed({ tag: "t", why: "items" }))
expect Case.request("t\tf.ttf\tadvances\t0,zz\t") == Err(Malformed({ tag: "t", why: "items" }))
expect Case.request("t\tf.ttf\tmetrics\t\tface=2") == Ok({ tag: "t", font: "f.ttf", kind: Metrics, scalars: [], settings: plain, face: 2, location: Regular, shaping: Case.default_shaping })
expect Case.request("t\tf.ttf\tadvances\t0,1c8,ffffffff\t") == Ok({ tag: "t", font: "f.ttf", kind: Advances(Listed([0, 456, 0xFFFFFFFF])), scalars: [], settings: plain, face: 0, location: Regular, shaping: Case.default_shaping })
expect Case.request("t\tf.ttf\textents\tall\tinstance=8") == Ok({ tag: "t", font: "f.ttf", kind: Extents(All), scalars: [], settings: plain, face: 0, location: Instance(8), shaping: Case.default_shaping })
expect Case.glyph_ids("") == Ok(Listed([]))
expect Case.glyph_ids("100000000") == Err(BadGlyphs)

expect {
	at = |v| Ok({ settings: plain, face: 0, location: At(v), shaping: Case.default_shaping })
	base = { weight: Regular, width: Normal, optical_size: FontDefault, axes: [] }
	Case.flags("weight=Bold") == at({ ..base, weight: Bold })
		and Case.flags("weight=650,width=SemiCondensed,optical-size=12.5") == at({ ..base, weight: Weight(650), width: SemiCondensed, optical_size: Size(12.5) })
		and Case.flags("width=87.5,optical-size=FontDefault") == at({ ..base, width: Percent(87.5) })
		and Case.flags("axis=wght:700,axis=HV:-0.25,axis=wght:300.000000000000000001") == at({ ..base, axes: [{ tag: "wght", value: 700 }, { tag: "HV", value: -0.25 }, { tag: "wght", value: 300.000000000000000001 }] })
}

expect Case.flags("instance=1,weight=Bold") == Err("weight=Bold")
expect Case.flags("weight=Bold,instance=1") == Err("instance=1")
expect Case.flags("axis=wght:.5") == Err("axis=wght:.5")
expect Case.flags("axis=wght:1.") == Err("axis=wght:1.")
expect Case.flags("axis=:1") == Err("axis=:1")
expect Case.flags("axis=wght:1.0000000000000000001") == Err("axis=wght:1.0000000000000000001")
expect Case.flags("weight=Heavy") == Err("weight=Heavy")
expect Case.flags("weight=65536") == Err("weight=65536")
expect Case.flags("face=x") == Err("face=x")
expect Case.dec("-0.5") == Ok(-0.5)
expect Case.dec("1000000000") == Ok(1000000000)
expect Case.advances([1200, -3]) == "advances:1200,-3"
expect Case.advances([]) == "advances:"
expect Case.metrics({ ascent: 1984, descent: -494, line_gap: 0, cap_height: 1490, x_height: 1118, underline_position: -395, underline_thickness: 46, strikeout_position: 671, strikeout_thickness: 46 }) == "metrics:ascent=1984,descent=-494,line_gap=0,cap_height=1490,x_height=1118,underline_position=-395,underline_thickness=46,strikeout_position=671,strikeout_thickness=46"
expect Case.extents([{ glyph: 0, box: Box({ x_min: 80, y_min: -104, x_max: 1120, y_max: 1478 }) }, { glyph: 3, box: Empty }]) == "extents:0=80,-104,1120,1478|3=empty"
expect Case.utf8_offsets([0x41, 0xE9, 0x20AC, 0x1F600]) == [0, 1, 3, 6, 10]

expect {
	Case.serialize(plain, [{ glyph: 2, cluster: 0, dx: 0, dy: 0, ax: 1273, ay: 0 }, { glyph: 456, cluster: 1, dx: -5, dy: 10, ax: 1273, ay: 7 }]) == "[2=0+1273|456=1@-5,10+1273,7]"
}

expect Case.serialize(plain, []) == "[]"

expect {
	# With no-clusters and no-advances (hb-shape --ned), offsets accumulate
	# the advances, as hb_buffer_serialize does.
	s = { ..plain, clusters: False, advances: False }
	Case.serialize(s, [{ glyph: 1, cluster: 0, dx: 0, dy: 0, ax: 100, ay: 0 }, { glyph: 2, cluster: 1, dx: 0, dy: 0, ax: 50, ay: 0 }]) == "[1|2@100,0]"
}

expect Case.width([{ glyph: 1, cluster: 0, dx: 0, dy: 0, ax: 100, ay: 0 }, { glyph: 2, cluster: 1, dx: 0, dy: 0, ax: -30, ay: 0 }]) == "width:70"
expect Case.width([]) == "width:0"

expect {
	parsed = Case.flags("utf8-clusters,direction=rtl,script=Arab,language=ar,cluster-level=1,feature=liga:0:0:*,feature=kern:2:3:5")
	shaping = { script: "Arab", language: "ar", direction: RightToLeft, features: [{ tag: "liga", value: 0, start: 0, end: 18_446_744_073_709_551_615 }, { tag: "kern", value: 2, start: 3, end: 5 }], clusters: Characters }
	parsed == Ok({ settings: { ..plain, utf8: True }, face: 0, location: Regular, shaping })
}

expect Case.flags("direction=ttb") == Err("direction=ttb")
expect Case.flags("cluster-level=2") == Err("cluster-level=2")
expect Case.flags("script=") == Err("script=")
expect Case.flags("feature=liga:1:0") == Err("feature=liga:1:0")
expect Case.flags("feature=:1:0:*") == Err("feature=:1:0:*")
expect Case.flags("feature=liga:4294967296:0:*") == Err("feature=liga:4294967296:0:*")
expect Case.flags("feature=liga:on:0:*") == Err("feature=liga:on:0:*")
