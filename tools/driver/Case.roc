## The driver's request protocol and result notation, without effects.
##
## `scripts/conformance.py` parses the JSONC case files and sends one request
## per line (scripts/_common.py, `driver_request`):
##
##     <tag> TAB <font path> TAB <kind> TAB <code points> TAB <flags>
##
## `kind` is `shape`, `read` or `width`; code points are lower-case
## hexadecimal without prefix, comma-separated (empty for empty text); flags
## are comma-separated, from `no-clusters`, `no-positions`, `no-advances`,
## `utf8-clusters` and `font-size=<n>`. Shaping results are printed in
## hb-shape's text notation with glyph ids: `[gid=cluster@dx,dy+ax,ay|...]`.
## See docs/conformance.adoc.
Case :: {}.{

	## What a request asks for.
	Kind : [Shape, Read, Width]

	## The output settings of a shaping request. `font_size` is 0 when not
	## given.
	Settings : { clusters : Bool, positions : Bool, advances : Bool, utf8 : Bool, font_size : U64 }

	## One parsed request line.
	Request : { tag : Str, font : Str, kind : Kind, scalars : List(U32), settings : Settings }

	## One positioned output glyph, in font units.
	Glyph : { glyph : U64, cluster : U64, dx : I64, dy : I64, ax : I64, ay : I64 }

	## Parse one request line. A malformed line yields its tag (the text
	## before the first tab, or the whole line) and what was wrong.
	request : Str -> Try(Request, [Malformed({ tag : Str, why : Str })])
	request = |line|
		match line.split_on("\t") {
			[tag, font, kind_text, points, flag_text] => {
				kind = match kind_text {
					"shape" => Ok(Shape)
					"read" => Ok(Read)
					"width" => Ok(Width)
					_ => Err("kind")
				}
				match (kind, Case.scalars(points), Case.flags(flag_text)) {
					(Ok(k), Ok(s), Ok(settings)) =>
						if (tag.is_empty() or font.is_empty()) Err(Malformed({ tag, why: "empty-field" })) else Ok({ tag, font, kind: k, scalars: s, settings })
					(Err(why), _, _) => Err(Malformed({ tag, why }))
					(_, Err(_), _) => Err(Malformed({ tag, why: "code-points" }))
					(_, _, Err(flag)) => Err(Malformed({ tag, why: "flag-${flag}" }))
				}
			}
			[tag, ..] => Err(Malformed({ tag, why: "fields" }))
			[] => Err(Malformed({ tag: "", why: "fields" }))
		}

	## Settings from the comma-separated flags field, or the first flag not
	## understood.
	flags : Str -> Try(Settings, Str)
	flags = |field| {
		var $s = { clusters: True, positions: True, advances: True, utf8: False, font_size: 0 }
		var $bad = ""
		for flag in field.split_on(",") {
			if $bad.is_empty() and !flag.is_empty() {
				if flag == "no-clusters" {
					$s = { ..$s, clusters: False }
				} else if flag == "no-positions" {
					$s = { ..$s, positions: False }
				} else if flag == "no-advances" {
					$s = { ..$s, advances: False }
				} else if flag == "utf8-clusters" {
					$s = { ..$s, utf8: True }
				} else if flag.starts_with("font-size=") {
					match Case.decimal(flag.drop_prefix("font-size=")) {
						Ok(size) if size > 0 => {
							$s = { ..$s, font_size: size }
						}
						_ => {
							$bad = flag
						}
					}
				} else {
					$bad = flag
				}
			}
		}
		if ($bad.is_empty()) Ok($s) else Err($bad)
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
	hex = |word| {
		digits = word.to_utf8()
		var $value = 0.U64
		var $ok = !digits.is_empty() and digits.len() <= 6
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
		# Surrogates and values past U+10FFFF are not scalar values.
		if $ok and $value <= 0x10FFFF and ($value < 0xD800 or $value > 0xDFFF) {
			Ok($value.to_u32_wrap())
		} else {
			Err(BadHex)
		}
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
}

plain : Case.Settings
plain = { clusters: True, positions: True, advances: True, utf8: False, font_size: 0 }

expect Case.request("inter/a\tf.ttf\tshape\t41,1f600\tutf8-clusters") == Ok({ tag: "inter/a", font: "f.ttf", kind: Shape, scalars: [0x41, 0x1F600], settings: { ..plain, utf8: True } })
expect Case.request("reading/x\tf.ttf\tread\t\t") == Ok({ tag: "reading/x", font: "f.ttf", kind: Read, scalars: [], settings: plain })
expect Case.request("w\tf.ttf\twidth\t48,49\t") == Ok({ tag: "w", font: "f.ttf", kind: Width, scalars: [0x48, 0x49], settings: plain })
expect Case.request("t\tf.ttf\tshape\t41\tno-clusters,no-advances,font-size=1000") == Ok({ tag: "t", font: "f.ttf", kind: Shape, scalars: [0x41], settings: { ..plain, clusters: False, advances: False, font_size: 1000 } })
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
