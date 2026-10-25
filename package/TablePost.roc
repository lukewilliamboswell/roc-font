import Sfnt
import Bytes
import "fonts/Inter-Variable.ttf" as inter_file : List(U8)
import "fonts/Merriweather-Variable.ttf" as merriweather_file : List(U8)
import "fonts/FiraCode-Variable.ttf" as fira_file : List(U8)

## The PostScript table (`post`): the underline's position and thickness,
## the italic angle, whether the font is monospaced, and the glyphs'
## PostScript names.
##
## Internal. Reading checks the table once, exactly as OTS 9.3.0 checks it
## (see `read`), so a font reads exactly when a browser accepts its `post`
## table, and reports every independent problem; after a successful read
## every query here is total. Versions 1.0, 2.0 and 3.0 are read; any other
## version, including the deprecated 2.5, is a problem, as OTS refuses it.
##
## Glyph names by version:
##
## - 1.0: the first 258 glyphs carry the standard Macintosh names, in their
##   standard order.
## - 2.0: each glyph has an index; below 258 it selects a standard name, from
##   258 a name stored in the table as a length byte and that many bytes.
##   Reading finds where each stored name a glyph refers to starts, in one
##   list of offsets into the table bytes; the names are neither copied nor
##   decoded until a query asks for one. A version 2.0 table that lists no
##   glyphs (which OTS allows for fonts of at most 258 glyphs) gives no
##   names.
## - 3.0: no names.
##
## Only glyphs below the font's glyph count (from `maxp`) have names. A glyph
## whose stored name is empty has no name.
##
## The format gives stored names no encoding; they are meant to be ASCII. A
## name is decoded as ISO 8859-1 (each byte is the character of that
## number), as fontTools does, so every name is a valid `Str` and ASCII names
## are returned unchanged.
##
## Problems name the table and the byte offset in the file: the version, a
## glyph count other than the font's or whose index array does not fit, the
## first stored name that runs past the end of the table or holds a zero
## byte, and each glyph whose index selects no name.
TablePost := {
	# Fixed 16.16 degrees, counter-clockwise from vertical.
	italic_angle : I32,
	underline_position : I16,
	underline_thickness : I16,
	fixed_pitch : Bool,
	names : Names,
}.{

	# Where glyph names come from. `count` is the number of glyphs that have
	# a name entry and lie below the font's glyph count. `Indexed` holds the
	# table bytes (indices from byte 34) and where each stored name starts
	# (its length byte).
	Names : [NoNames, Standard(U64), Indexed({ bytes : List(U8), count : U64, starts : List(U32) })]

	## A table with zero metrics and no glyph names.
	none : TablePost
	none = { italic_angle: 0, underline_position: 0, underline_thickness: 0, fixed_pitch: Bool.False, names: NoNames }

	# ------------------------------------------------------------ queries

	## The underline's position (the top of the line, negative below the
	## baseline) and thickness, in font units.
	underline : TablePost -> { position : I32, thickness : I32 }
	underline = |post| { position: post.underline_position.to_i32(), thickness: post.underline_thickness.to_i32() }

	## The italic angle in degrees counter-clockwise from vertical, as the
	## table stores it: a fixed-point number with 16 fractional bits
	## (`-12.5` degrees is `-819200`).
	italic_angle : TablePost -> I32
	italic_angle = |post| post.italic_angle

	## Whether the font says its glyphs all have the same advance.
	fixed_pitch : TablePost -> Bool
	fixed_pitch = |post| post.fixed_pitch

	## A glyph's PostScript name, if the table gives it one.
	glyph_name : TablePost, U32 -> Try(Str, [Missing])
	glyph_name = |post, glyph| {
		g = glyph.to_u64()
		match post.names {
			NoNames => Err(Missing)
			Standard(count) => if (g < count) Ok(TablePost.standard_name(g)) else Err(Missing)
			Indexed({ bytes, count, starts }) =>
				if g >= count {
					Err(Missing)
				} else {
					index = Bytes.u16(bytes, 34 + 2 * g)
					if index < 258 {
						Ok(TablePost.standard_name(index))
					} else {
						# Reading found a start for every stored name a glyph
						# below `count` refers to, and checked that the name
						# lies inside the table.
						start = (starts.get(index - 258) ?? 0).to_u64()
						length = Bytes.u8(bytes, start)
						if (length == 0) Err(Missing) else Ok(TablePost.latin1(bytes, start + 1, length))
					}
				}
		}
	}

	# A standard Macintosh glyph name. Callers pass indices below 258, so
	# the fallback is unreachable.
	standard_name : U64 -> Str
	standard_name = |index| TablePost.standard.get(index) ?? ""

	# Decode ISO 8859-1. Every byte is a character, so the fallback is
	# unreachable.
	latin1 : List(U8), U64, U64 -> Str
	latin1 = |data, start, length| {
		var $out = List.with_capacity(2 * length)
		for i in 0..<length {
			b = Bytes.u8(data, start + i)
			$out =
				if b < 0x80 {
					$out.append(b.to_u8_wrap())
				} else {
					$out.append(b.shr_zf_wrap(6).bitwise_or(0xC0).to_u8_wrap()).append(b.bitwise_and(0x3F).bitwise_or(0x80).to_u8_wrap())
				}
		}
		Str.from_utf8($out) ?? ""
	}

	# ------------------------------------------------------------ reading

	## The PostScript table of a font file with `glyph_count` glyphs, or
	## `Absent` when the font has none. The table is optional.
	from_tables : List(U8), List(Sfnt.Table), U64 -> Try([Present(TablePost), Absent], List([BadTable({ table : Str, offset : U32 })]))
	from_tables = |bytes, tables, glyph_count| {
		tag = Sfnt.tag_of("post")
		match tables.find_first(|t| t.tag == tag) {
			Err(_) => Ok(Absent)
			Ok(t) =>
				if Bytes.fits(t.offset, t.length, bytes.len()) {
					match TablePost.read(bytes.sublist({ start: t.offset, len: t.length }), t.offset, glyph_count) {
						Ok(post) => Ok(Present(post))
						Err(problems) => Err(problems)
					}
				} else {
					Err([TablePost.bad(t.offset, 0)])
				}
		}
	}

	## Check a `post` table's bytes for a font with `glyph_count` glyphs,
	## exactly as OTS 9.3.0 does (`ots/src/post.cc`, `OpenTypePOST::Parse`;
	## line numbers below are that file's). `base` is the table's offset in
	## the file, used only to place problems.
	read : List(U8), U64, U64 -> Try(TablePost, List([BadTable({ table : Str, offset : U32 })]))
	read = |data, base, glyph_count| {
		size = data.len()
		version = Bytes.u32(data, 0)
		# Lines 17-36: versions 1.0, 2.0 and 3.0 (OTS does not accept the
		# deprecated 2.5), and the 32-byte header.
		if size < 32 or (version != 0x00010000 and version != 0x00020000 and version != 0x00030000) {
			return Err([TablePost.bad(base, 0)])
		}
		header = |names| {
			italic_angle: Bytes.u32(data, 4).to_u32_wrap().to_i32_wrap(),
			underline_position: Bytes.i16(data, 8).to_i16_wrap(),
			underline_thickness: Bytes.i16(data, 10).to_i16_wrap(),
			fixed_pitch: Bytes.u32(data, 12) != 0,
			names,
		}
		if version == 0x00010000 {
			Ok(header(Standard(if (glyph_count < 258) glyph_count else 258)))
		} else if version == 0x00030000 {
			Ok(header(NoNames))
		} else {
			match TablePost.read_indexed(data, base, glyph_count) {
				Ok(names) => Ok(header(names))
				Err(problems) => Err(problems)
			}
		}
	}

	# Version 2.0: the glyph name indices and the stored names they use.
	read_indexed : List(U8), U64, U64 -> Try(Names, List([BadTable({ table : Str, offset : U32 })]))
	read_indexed = |data, base, glyph_count| {
		size = data.len()
		listed = Bytes.u16(data, 32)
		# Lines 48-51: the glyph count readable.
		if size < 34 {
			return Err([TablePost.bad(base, 32)])
		}
		# Lines 59-68: no glyphs listed, allowed for at most 258 glyphs.
		if listed == 0 {
			return if (glyph_count > 258) Err([TablePost.bad(base, 32)]) else Ok(NoNames)
		}
		# Lines 75-83: every index readable.
		if !Bytes.fits(34, 2 * listed, size) {
			return Err([TablePost.bad(base, 32)])
		}
		# Lines 70-73: exactly the font's glyph count.
		var $problems = if (listed != glyph_count) [TablePost.bad(base, 32)] else []
		var $highest = 0.U64
		for g in 0..<listed {
			$highest = $highest.max(Bytes.u16(data, 34 + 2 * g))
		}
		# Stored names the glyphs refer to: 0 up to `needed`. Each takes at
		# least its length byte, so `needed` is bounded by the table before
		# anything is allocated for it.
		needed = (if ($highest >= 258) $highest - 257 else 0).min(size)
		# Lines 85-104: every stored name, up to the end of the table, fits
		# and holds no zero byte.
		var $starts = List.with_capacity(needed)
		var $stored = 0
		var $at = 34 + 2 * listed
		var $broken = Bool.False
		while !$broken and $at < size {
			length = Bytes.u8(data, $at)
			if !Bytes.fits($at + 1, length, size) or TablePost.has_zero(data, $at + 1, length) {
				$problems = $problems.append(TablePost.bad(base, $at))
				$broken = Bool.True
			} else {
				if $stored < needed {
					$starts = $starts.append($at.to_u32_wrap())
				}
				$stored = $stored + 1
				$at = $at + 1 + length
			}
		}
		# Lines 106-117: every index selects a standard or stored name (only
		# known once every stored name was read).
		if !$broken {
			for g in 0..<listed {
				index = Bytes.u16(data, 34 + 2 * g)
				if index >= 258 and index - 258 >= $stored {
					$problems = $problems.append(TablePost.bad(base, 34 + 2 * g))
				}
			}
		}
		if $problems.is_empty() {
			Ok(Indexed({ bytes: data, count: listed.min(glyph_count), starts: $starts }))
		} else {
			Err($problems)
		}
	}

	# Whether any of `length` bytes from `start` is zero.
	has_zero : List(U8), U64, U64 -> Bool
	has_zero = |data, start, length| {
		var $i = 0
		while $i < length and Bytes.u8(data, start + $i) != 0 {
			$i = $i + 1
		}
		$i < length
	}

	# A problem at byte `at` of a table at `base` in the file. Fonts larger
	# than 4 GiB are refused before tables are read, so the sum fits.
	bad : U64, U64 -> [BadTable({ table : Str, offset : U32 })]
	bad = |base, at| BadTable({ table: "post", offset: (base + at).to_u32_wrap() })

	# The 258 standard Macintosh glyph names, in their standard order.
	standard : List(Str)
	standard = [".notdef", ".null", "nonmarkingreturn", "space", "exclam", "quotedbl", "numbersign", "dollar", "percent", "ampersand", "quotesingle", "parenleft", "parenright", "asterisk", "plus", "comma", "hyphen", "period", "slash", "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "colon", "semicolon", "less", "equal", "greater", "question", "at", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "bracketleft", "backslash", "bracketright", "asciicircum", "underscore", "grave", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "braceleft", "bar", "braceright", "asciitilde", "Adieresis", "Aring", "Ccedilla", "Eacute", "Ntilde", "Odieresis", "Udieresis", "aacute", "agrave", "acircumflex", "adieresis", "atilde", "aring", "ccedilla", "eacute", "egrave", "ecircumflex", "edieresis", "iacute", "igrave", "icircumflex", "idieresis", "ntilde", "oacute", "ograve", "ocircumflex", "odieresis", "otilde", "uacute", "ugrave", "ucircumflex", "udieresis", "dagger", "degree", "cent", "sterling", "section", "bullet", "paragraph", "germandbls", "registered", "copyright", "trademark", "acute", "dieresis", "notequal", "AE", "Oslash", "infinity", "plusminus", "lessequal", "greaterequal", "yen", "mu", "partialdiff", "summation", "product", "pi", "integral", "ordfeminine", "ordmasculine", "Omega", "ae", "oslash", "questiondown", "exclamdown", "logicalnot", "radical", "florin", "approxequal", "Delta", "guillemotleft", "guillemotright", "ellipsis", "nonbreakingspace", "Agrave", "Atilde", "Otilde", "OE", "oe", "endash", "emdash", "quotedblleft", "quotedblright", "quoteleft", "quoteright", "divide", "lozenge", "ydieresis", "Ydieresis", "fraction", "currency", "guilsinglleft", "guilsinglright", "fi", "fl", "daggerdbl", "periodcentered", "quotesinglbase", "quotedblbase", "perthousand", "Acircumflex", "Ecircumflex", "Aacute", "Edieresis", "Egrave", "Iacute", "Icircumflex", "Idieresis", "Igrave", "Oacute", "Ocircumflex", "apple", "Ograve", "Uacute", "Ucircumflex", "Ugrave", "dotlessi", "circumflex", "tilde", "macron", "breve", "dotaccent", "ring", "cedilla", "hungarumlaut", "ogonek", "caron", "Lslash", "lslash", "Scaron", "scaron", "Zcaron", "zcaron", "brokenbar", "Eth", "eth", "Yacute", "yacute", "Thorn", "thorn", "minus", "multiply", "onesuperior", "twosuperior", "threesuperior", "onehalf", "onequarter", "threequarters", "franc", "Gbreve", "gbreve", "Idotaccent", "Scedilla", "scedilla", "Cacute", "cacute", "Ccaron", "ccaron", "dcroat"]
}

# ----------------------------------------------------------------------

# Tests of the reader on hand-built tables, on the defaults and on the
# `post` tables of the fixtures in `tests/fonts/name-post/` (generated by
# its `generate.py`), embedded below. Expected names and metrics of real
# fonts are fontTools 4.61.1's (the `post` table's names behind
# `getGlyphOrder()`, before fontTools renames duplicates and fills in
# missing names). Across the corpus, the defaults and the fixtures, all
# 27,832 glyph names fontTools reads from version 2.0 tables agree. Glyph
# names callers see are tested through the public API in `tests/api/`.
# Top-level expects and helpers are not part of the module's API. Run with
# `roc test package/TablePost.roc`.

# ------------------------------------------------------------ helpers

u16 : U64 -> List(U8)
u16 = |v| [v.shr_zf_wrap(8).bitwise_and(0xFF).to_u8_wrap(), v.bitwise_and(0xFF).to_u8_wrap()]

u32 : U64 -> List(U8)
u32 = |v| u16(v.shr_zf_wrap(16).bitwise_and(0xFFFF)).concat(u16(v.bitwise_and(0xFFFF)))

# A table header of `version`: italic angle -1.5 degrees, underline at -100,
# 50 thick, fixed pitch.
header : U64 -> List(U8)
header = |version| u32(version).concat(u32(0xFFFE8000)).concat(u16(0xFF9C)).concat(u16(50)).concat(u32(1)).concat(List.repeat(0, 16))

# A version 2.0 table: the glyph name indices, then the stored names.
v2 : List(U64), List(Str) -> List(U8)
v2 = |indices, stored| {
	var $out = header(0x00020000).concat(u16(indices.len()))
	for i in indices {
		$out = $out.concat(u16(i))
	}
	for s in stored {
		$out = $out.append(s.to_utf8().len().to_u8_wrap()).concat(s.to_utf8())
	}
	$out
}

# A version 2.5 table with signed offsets (deprecated; OTS refuses it).
v25 : List(I64) -> List(U8)
v25 = |offsets| header(0x00025000).concat(u16(offsets.len())).concat(offsets.map(|o| o.to_u64_wrap().bitwise_and(0xFF).to_u8_wrap()))

# Glyph ids 0 up to `n`.
ids : U64 -> List(U32)
ids = |n| {
	var $out = List.with_capacity(n)
	for g in 0..<n {
		$out = $out.append(g.to_u32_wrap())
	}
	$out
}

read : List(U8), U64 -> Try(TablePost, [Rejected])
read = |table, glyph_count| TablePost.read(table, 0, glyph_count).map_err(|_| Rejected)

names : List(U8), U64, U64 -> List(Try(Str, [Missing, Rejected]))
names = |table, glyph_count, upto|
	match TablePost.read(table, 0, glyph_count) {
		Ok(post) => ids(upto).map(|g| TablePost.glyph_name(post, g).map_err(|_| Missing))
		Err(_) => [Err(Rejected)]
	}

problems : List(U8), U64, U64 -> List([BadTable({ table : Str, offset : U32 })])
problems = |table, base, glyph_count|
	match TablePost.read(table, base, glyph_count) {
		Ok(_) => []
		Err(found) => found
	}

bad : U32 -> [BadTable({ table : Str, offset : U32 })]
bad = |offset| BadTable({ table: "post", offset })

from_file : List(U8) -> Try(TablePost, [Absent, Rejected])
from_file = |bytes|
	match Sfnt.directory(bytes) {
		Err(_) => Err(Rejected)
		Ok(tables) => {
			glyph_count = match Sfnt.table(bytes, tables, "maxp", 6) {
				Found(maxp) => Bytes.u16(maxp, 4)
				_ => 0
			}
			match TablePost.from_tables(bytes, tables, glyph_count) {
				Ok(Present(post)) => Ok(post)
				Ok(Absent) => Err(Absent)
				Err(_) => Err(Rejected)
			}
		}
	}

post_facts : TablePost -> { underline : { position : I32, thickness : I32 }, angle : I32, fixed : Bool }
post_facts = |post| { underline: TablePost.underline(post), angle: TablePost.italic_angle(post), fixed: TablePost.fixed_pitch(post) }

facts : List(U8) -> Try({ underline : { position : I32, thickness : I32 }, angle : I32, fixed : Bool }, [Absent, Rejected])
facts = |bytes| from_file(bytes).map_ok(post_facts)

facts_of : List(U8), U64 -> Try({ underline : { position : I32, thickness : I32 }, angle : I32, fixed : Bool }, [Rejected])
facts_of = |table, glyph_count| read(table, glyph_count).map_ok(post_facts)

# ------------------------------------------------------------ real fonts

# The defaults' glyph names are tested through the public API in
# `tests/api/`; their underline, italic angle and fixed pitch here.
expect facts(inter_file) == Ok({ underline: { position: -348, thickness: 140 }, angle: 0, fixed: Bool.False })
expect facts(merriweather_file) == Ok({ underline: { position: -244, thickness: 60 }, angle: 0, fixed: Bool.False })
expect facts(fira_file) == Ok({ underline: { position: -100, thickness: 50 }, angle: 0, fixed: Bool.True })

# A font without a `post` table reads as absent, not as a problem. This
# file's directory lists only a four-byte `head` table.
expect {
	directory = [0, 1, 0, 0, 0, 1, 0, 16, 0, 0, 0, 0]
	record = "head".to_utf8().concat([0, 0, 0, 0]).concat([0, 0, 0, 28]).concat([0, 0, 0, 4])
	facts(directory.concat(record).concat([0, 0, 0, 0])) == Err(Absent)
}

# ------------------------------------------------------------ fixtures

# The `post` tables of the fixtures in `tests/fonts/name-post/` (generated
# by its `generate.py`), and their glyph counts. Their glyph names are
# tested through the public API in `tests/api/`.

# Generated from `tests/fonts/name-post/mac-roman-v1.ttf` by `tests/fonts/inline_tables.py`.

mac_glyph_count : U64
mac_glyph_count = 8

# The `post` table, 32 bytes.
mac_post : List(U8)
mac_post = [
	[0x00, 0x01, 0x00, 0x00, 0xFF, 0xF3, 0x80, 0x00, 0xFF, 0x6A, 0x00, 0x3C, 0x00, 0x00, 0x00, 0x01],
	[0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
].join_map(|row| row)

# Generated from `tests/fonts/name-post/ranking-v2.ttf` by `tests/fonts/inline_tables.py`.

ranking_glyph_count : U64
ranking_glyph_count = 6

# The `post` table, 66 bytes.
ranking_post : List(U8)
ranking_post = [
	[0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x9C, 0x00, 0x32, 0x00, 0x00, 0x00, 0x00],
	[0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
	[0x00, 0x06, 0x00, 0x00, 0x00, 0x03, 0x00, 0x24, 0x01, 0x02, 0x01, 0x03, 0x01, 0x04, 0x05, 0x61],
	[0x2E, 0x61, 0x6C, 0x74, 0x04, 0x63, 0x61, 0x66, 0xE9, 0x08, 0x75, 0x6E, 0x69, 0x31, 0x46, 0x36],
	[0x30, 0x30],
].join_map(|row| row)

# Generated from `tests/fonts/name-post/format1-v25.ttf` by `tests/fonts/inline_tables.py`.

format1_glyph_count : U64
format1_glyph_count = 5

# The `post` table, 39 bytes.
format1_post : List(U8)
format1_post = [
	[0x00, 0x02, 0x50, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x88, 0x00, 0x28, 0x00, 0x00, 0x00, 0x00],
	[0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
	[0x00, 0x05, 0x00, 0x23, 0x23, 0x00, 0x40],
].join_map(|row| row)

# Generated from `tests/fonts/name-post/japanese-v3.ttf` by `tests/fonts/inline_tables.py`.

japanese_glyph_count : U64
japanese_glyph_count = 3

# The `post` table, 32 bytes.
japanese_post : List(U8)
japanese_post = [
	[0x00, 0x03, 0x00, 0x00, 0x00, 0x0B, 0x40, 0x00, 0xFF, 0xB5, 0x00, 0x19, 0x00, 0x00, 0x00, 0x00],
	[0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
].join_map(|row| row)

# Version 1.0.
expect facts_of(mac_post, mac_glyph_count) == Ok({ underline: { position: -150, thickness: 60 }, angle: -819200, fixed: Bool.True })

# Version 2.0.
expect facts_of(ranking_post, ranking_glyph_count) == Ok({ underline: { position: -100, thickness: 50 }, angle: 0, fixed: Bool.False })

# Version 2.5 (deprecated): OTS 9.3.0 refuses it ("Unsupported table
# version", post.cc lines 21-26), so reading does too.
expect names(format1_post, format1_glyph_count, 2) == [Err(Rejected)]
expect facts_of(format1_post, format1_glyph_count) == Err(Rejected)

# Version 3.0: metrics, no names. 11.25 degrees is 737280 in 16.16.
expect facts_of(japanese_post, japanese_glyph_count) == Ok({ underline: { position: -75, thickness: 25 }, angle: 737280, fixed: Bool.False })

# ------------------------------------------------------------ inline tables

# The header: a negative italic angle and underline position.
expect
	match read(header(0x00030000), 10) {
		Ok(post) => TablePost.italic_angle(post) == -98304 and TablePost.underline(post) == { position: -100, thickness: 50 } and TablePost.fixed_pitch(post)
		Err(_) => Bool.False
	}

# Version 1.0 names the first 258 glyphs only.
expect names(header(0x00010000), 300, 260).drop_first(256) == [Ok("ccaron"), Ok("dcroat"), Err(Missing), Err(Missing)]

# Version 2.0: an empty stored name is no name; glyphs past the font have
# no name.
expect names(v2([0, 258, 259, 3], ["", "b.alt"]), 4, 6) == [Ok(".notdef"), Err(Missing), Ok("b.alt"), Ok("space"), Err(Missing), Err(Missing)]

# Stored names nothing refers to, and trailing empty names, are allowed.
expect names(v2([259], ["a", "b", "c"]).concat([0, 0]), 1, 1) == [Ok("b")]

# A table listing no glyphs gives no names; OTS allows it for fonts of up
# to 258 glyphs (post.cc lines 59-68).
expect names(header(0x00020000).concat(u16(0)), 258, 2) == [Err(Missing), Err(Missing)]
expect problems(header(0x00020000).concat(u16(0)), 500, 259) == [bad(532)]

expect
	match read(header(0x00020000).concat(u16(0)), 0) {
		Ok(post) => TablePost.glyph_name(post, 0) == Err(Missing)
		Err(_) => Bool.False
	}

expect TablePost.glyph_name(TablePost.none, 0) == Err(Missing)
expect TablePost.underline(TablePost.none) == { position: 0, thickness: 0 }

# ------------------------------------------------------------ problems

# Too short for the header, and versions OTS does not read (4.0, 2.0 spelt
# wrongly, the deprecated 2.5). Offsets are in the file (the table is at 500).
expect problems(List.repeat(0, 31), 500, 1) == [bad(500)]
expect problems(header(0x00040000), 500, 1) == [bad(500)]
expect problems(header(0x00000002), 500, 1) == [bad(500)]
expect problems(v25([0, 127, -2]), 500, 3) == [bad(500)]

# Version 2.0: indices past the end of the table (placed at the count).
expect problems(header(0x00020000).concat(u16(3)).concat(u16(0)), 500, 3) == [bad(532)]

# Version 2.0: each glyph that refers to a stored name that is not there
# (placed at its index); a stored name that runs past the end of the table
# or holds a zero byte (placed at its length byte, post.cc lines 91-103).
expect problems(v2([258, 260], ["a", "b"]), 500, 2) == [bad(500 + 36)]
expect problems(v2([0xFFFF, 0, 0xFFFF], ["a"]), 500, 3) == [bad(500 + 34), bad(500 + 38)]
expect problems(v2([258], []).concat([5, 0x41]), 500, 1) == [bad(500 + 36)]
expect problems(v2([258], ["a"]).concat([5, 0x41]), 500, 1) == [bad(500 + 38)]
expect problems(v2([258], ["a\u(0)b"]), 500, 1) == [bad(500 + 36)]

# A count other than the font's glyph count (post.cc lines 70-73), reported
# with any bad index.
expect problems(v2([0, 0xFFFF], []), 500, 1) == [bad(532), bad(536)]
expect problems(v2([3], []), 500, 2) == [bad(532)]

# A table that lies outside the file is placed at its offset.
expect {
	tables = [{ tag: Sfnt.tag_of("post"), offset: 40, length: 32 }]
	match TablePost.from_tables(List.repeat(0, 60), tables, 1) {
		Err(found) => found == [bad(40)]
		Ok(_) => Bool.False
	}
}
