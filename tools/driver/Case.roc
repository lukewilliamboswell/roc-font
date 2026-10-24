## Conformance case lines and results, without effects.
##
## A case line is HarfBuzz's `.tests` format:
## `font-path;hb-shape options;code points;expected`. Results are printed in
## hb-shape's text notation with glyph ids (`--no-glyph-names` is implied):
## `[gid=cluster@dx,dy+ax,ay|...]`. Reading cases (option `--read-outcome`)
## print `read:accept` or `read:reject`. See docs/conformance.adoc.
Case :: {}.{

	## What one line of a case file holds.
	Line : [Blank, Comment, Directive, Malformed, Shape({ font : Str, options : List(Str), unicodes : Str, expected : Str })]

	## The output and input settings the driver understands.
	Settings : { read : Bool, clusters : Bool, positions : Bool, advances : Bool, utf8 : Bool }

	## One positioned output glyph, in font units.
	Glyph : { glyph : U64, cluster : U64, dx : I64, dy : I64, ax : I64, ay : I64 }

	## Classify a line. `#` starts a comment or a disabled case and `@` a
	## runner directive (backend selection), as in HarfBuzz's runner; neither
	## is run.
	classify : Str -> Line
	classify = |raw| {
		line = raw.trim()
		if line.is_empty() {
			Blank
		} else if line.starts_with("#") {
			Comment
		} else if line.starts_with("@") {
			Directive
		} else {
			match line.split_on(";") {
				[font, options, unicodes, expected] =>
					Shape({ font, options: options.split_on(" ").keep_if(|o| !o.is_empty()), unicodes, expected })
				_ => Malformed
			}
		}
	}

	## Settings from hb-shape options, or the first option the driver does not
	## support.
	settings : List(Str) -> Try(Settings, Str)
	settings = |options| {
		var $s = { read: False, clusters: True, positions: True, advances: True, utf8: False }
		var $bad = ""
		for option in options {
			if $bad.is_empty() {
				if option == "--read-outcome" {
					$s = { ..$s, read: True }
				} else if option == "--no-glyph-names" or option == "--font-funcs=ot" or option == "--font-funcs=ft" {
					{}
				} else if option == "--no-clusters" {
					$s = { ..$s, clusters: False }
				} else if option == "--no-positions" {
					$s = { ..$s, positions: False }
				} else if option == "--no-advances" {
					$s = { ..$s, advances: False }
				} else if option == "--ned" {
					$s = { ..$s, clusters: False, advances: False }
				} else if option == "--utf8-clusters" {
					$s = { ..$s, utf8: True }
				} else if option.starts_with("--direction=") and Case.is_ltr(option.drop_prefix("--direction=")) {
					{}
				} else {
					$bad = option
				}
			}
		}
		if ($bad.is_empty()) Ok($s) else Err($bad)
	}

	# hb_direction_from_string reads only the first letter, in either case.
	is_ltr : Str -> Bool
	is_ltr = |value|
		match value.to_utf8() {
			['l', ..] => True
			['L', ..] => True
			_ => False
		}

	## Code points from hb-shape's `--unicodes` syntax: hexadecimal numbers,
	## each optionally prefixed `U+`, `u+` or `0x`, separated by commas or
	## spaces. An empty field is empty text.
	scalars : Str -> Try(List(U32), [BadUnicodes])
	scalars = |field| {
		var $out = []
		var $ok = True
		for item in field.split_on(",") {
			for word in item.split_on(" ") {
				if !word.is_empty() {
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
		}
		if ($ok) Ok($out) else Err(BadUnicodes)
	}

	hex : Str -> Try(U32, [BadHex])
	hex = |word| {
		digits = match word.to_utf8() {
			['U', '+', .. as rest] => rest
			['u', '+', .. as rest] => rest
			['0', 'x', .. as rest] => rest
			['0', 'X', .. as rest] => rest
			other => other
		}
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
	## `--no-advances` the offsets become pen positions. An empty run is `[]`.
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

	## The directory part of a path, with its trailing slash, or "" for a bare
	## name.
	directory : Str -> Str
	directory = |path| {
		bytes = path.to_utf8()
		var $cut = 0
		var $i = 0
		for b in bytes {
			$i = $i + 1
			if b == '/' {
				$cut = $i
			}
		}
		Str.from_utf8_lossy(bytes.sublist({ start: 0, len: $cut }))
	}

	## A case's font path, resolved against the directory of the file that
	## names it. An absolute path may carry HarfBuzz's `@sha1` suffix, which
	## is dropped.
	resolve : Str, Str -> Str
	resolve = |case_file, font|
		if font.starts_with("/") {
			match font.split_first("@") {
				Ok(parts) => parts.before
				Err(_) => font
			}
		} else {
			"${Case.directory(case_file)}${font}"
		}
}

expect Case.classify("") == Blank
expect Case.classify("# id: plain") == Comment
expect Case.classify("@font-funcs=ot") == Directive
expect Case.classify("a;b;c") == Malformed
expect Case.classify("f.ttf;--ned  --no-glyph-names;U+0041;[1]") == Shape({ font: "f.ttf", options: ["--ned", "--no-glyph-names"], unicodes: "U+0041", expected: "[1]" })
expect Case.scalars("U+0041,U+1F600") == Ok([0x41, 0x1F600])
expect Case.scalars("") == Ok([])
expect Case.scalars("0x41 42") == Ok([0x41, 0x42])
expect Case.scalars("U+D800") == Err(BadUnicodes)
expect Case.scalars("U+110000") == Err(BadUnicodes)
expect Case.scalars("U+00G1") == Err(BadUnicodes)
expect Case.utf8_offsets([0x41, 0xE9, 0x20AC, 0x1F600]) == [0, 1, 3, 6, 10]
expect Case.settings(["--no-glyph-names", "--direction=ltr"]) == Ok({ read: False, clusters: True, positions: True, advances: True, utf8: False })
expect Case.settings(["--ned"]) == Ok({ read: False, clusters: False, positions: True, advances: False, utf8: False })
expect Case.settings(["--features=-kern"]) == Err("--features=-kern")
expect Case.settings(["--direction=rtl"]) == Err("--direction=rtl")
expect Case.resolve("tests/cases/inter.cases", "../fonts/a.ttf") == "tests/cases/../fonts/a.ttf"
expect Case.resolve("-", "a.ttf") == "a.ttf"
expect Case.resolve("x/y.cases", "/abs/a.ttf@0123abcd") == "/abs/a.ttf"

expect {
	s = { read: False, clusters: True, positions: True, advances: True, utf8: False }
	Case.serialize(s, [{ glyph: 2, cluster: 0, dx: 0, dy: 0, ax: 1273, ay: 0 }, { glyph: 456, cluster: 1, dx: -5, dy: 10, ax: 1273, ay: 7 }]) == "[2=0+1273|456=1@-5,10+1273,7]"
}

expect {
	s = { read: False, clusters: True, positions: True, advances: True, utf8: False }
	Case.serialize(s, []) == "[]"
}

expect {
	# With --ned, offsets accumulate the advances, as hb_buffer_serialize does.
	s = { read: False, clusters: False, positions: True, advances: False, utf8: False }
	Case.serialize(s, [{ glyph: 1, cluster: 0, dx: 0, dy: 0, ax: 100, ay: 0 }, { glyph: 2, cluster: 1, dx: 0, dy: 0, ax: 50, ay: 0 }]) == "[1|2@100,0]"
}
