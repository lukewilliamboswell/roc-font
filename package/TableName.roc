import Sfnt
import Bytes

## The naming table (`name`): the font's human-readable strings, such as its
## family name, stored once per platform, encoding and language.
##
## Internal. Reading checks the table exactly as OTS 9.3.0 does (see
## `read`), so a font reads exactly when a browser accepts its names, and
## reports every independent problem. After a successful read every query
## here is total and returns a valid `Str`. Nothing is decoded or copied when reading: the prepared
## table is the checked table bytes, and a query decodes the one string it
## chooses.
##
## Strings are decoded from two encodings:
##
## - UTF-16BE, for the Unicode platform (0; encodings 0 to 4 and 6) and the
##   Windows platform's symbol, BMP and full-repertoire encodings (3, 0),
##   (3, 1) and (3, 10). A query never chooses such a string with an odd
##   number of bytes or a surrogate that is not part of a high-low pair:
##   there is no `Str` that holds it, and replacing the bad code unit would
##   be a repair. (OTS accepts such strings, so reading does too.)
## - Mac OS Roman, for the Macintosh platform's Roman encoding (1, 0), where
##   every byte is a character.
##
## Strings in other encodings (other Macintosh scripts, the Windows
## ShiftJIS, PRC, Big5, Wansung and Johab encodings, and anything unknown)
## are never decoded, so a query never chooses them; nor does it choose a
## record whose string lies outside the table, which OTS discards.
##
## Problems name the table and the byte offset in the file of what was
## wrong: the header field, or the language-tag record outside the table.
TableName := {
	# The checked table.
	bytes : List(U8),
	# Name records, 12 bytes each from byte 6.
	count : U64,
	# Start of string storage within `bytes`.
	storage : U64,
	# Language-tag records (format 1), 4 bytes each from `tags_at`; 0 and 0
	# for format 0.
	tag_count : U64,
	tags_at : U64,
}.{

	## A naming table with no strings: every query is `Missing`.
	none : TableName
	none = { bytes: [], count: 0, storage: 0, tag_count: 0, tags_at: 0 }

	# ------------------------------------------------------------ queries

	## The font's family name: the typographic family name (name ID 16) when
	## the font has a usable one, else the family name (name ID 1). Of the
	## records for one name ID, the first in table order of the best rank
	## wins:
	##
	## 1. Windows Unicode (3, 0), (3, 1) or (3, 10) in US English (0x0409);
	## 2. Windows Unicode in another English (primary language 0x09, or a
	##    language tag `en` or `en-...`);
	## 3. Unicode platform (0) with an English language tag;
	## 4. Unicode platform in any language;
	## 5. Macintosh Roman (1, 0) in English (language 0);
	## 6. Windows Unicode in any other language.
	##
	## This is the browsers' and fontTools' preference for an English name,
	## made deterministic: fontTools also consults name ID 21 and, with no
	## English record, takes the last record rather than ranking them.
	family_name : TableName -> Try(Str, [Missing])
	family_name = |name|
		match TableName.string(name, 16) {
			Ok(family) => Ok(family)
			Err(Missing) => TableName.string(name, 1)
		}

	## The best string for a name ID, chosen as `family_name` describes.
	string : TableName, U64 -> Try(Str, [Missing])
	string = |name, id| {
		var $best = TableName.unranked
		var $at = 0
		for i in 0..<name.count {
			at = 6 + 12 * i
			if Bytes.u16(name.bytes, at + 6) == id {
				rank = TableName.rank(name, at)
				if rank < $best {
					$best = rank
					$at = at
				}
			}
		}
		if $best == TableName.unranked {
			Err(Missing)
		} else {
			platform_id = Bytes.u16(name.bytes, $at)
			start = name.storage + Bytes.u16(name.bytes, $at + 10)
			length = Bytes.u16(name.bytes, $at + 8)
			if platform_id == 1 {
				Ok(TableName.mac_roman(name.bytes, start, length))
			} else {
				Ok(TableName.utf16(name.bytes, start, length))
			}
		}
	}

	unranked : U64
	unranked = 99

	# The rank of the record at `at` as `family_name` lists them, from 0. A
	# record OTS discards (`kept`), in an encoding this module does not
	# decode, or whose UTF-16BE string is not well-formed is unranked, so
	# a chosen string always decodes.
	rank : TableName, U64 -> U64
	rank = |name, at| {
		platform_id = Bytes.u16(name.bytes, at)
		encoding = Bytes.u16(name.bytes, at + 2)
		language = Bytes.u16(name.bytes, at + 4)
		utf16 = TableName.utf16_encoding(platform_id, encoding)
		usable = TableName.kept(name, at) and (!utf16 or TableName.well_formed(name.bytes, name.storage + Bytes.u16(name.bytes, at + 10), Bytes.u16(name.bytes, at + 8)))
		if !usable {
			TableName.unranked
		} else if platform_id == 3 and TableName.utf16_encoding(platform_id, encoding) {
			if language == 0x0409 {
				0
			} else if TableName.english(name, language) {
				1
			} else {
				5
			}
		} else if platform_id == 0 and TableName.utf16_encoding(platform_id, encoding) {
			if (language >= 0x8000 and TableName.english(name, language)) 2 else 3
		} else if platform_id == 1 and encoding == 0 and language == 0 {
			4
		} else {
			TableName.unranked
		}
	}

	# Whether a language is English: a Windows language ID whose primary
	# language is 0x09, or a language tag `en` or `en-...` in any case.
	english : TableName, U64 -> Bool
	english = |name, language|
		if language < 0x8000 {
			language.bitwise_and(0x3FF) == 0x09
		} else if language - 0x8000 >= name.tag_count {
			Bool.False
		} else {
			at = name.tags_at + 2 + 4 * (language - 0x8000)
			length = Bytes.u16(name.bytes, at)
			start = name.storage + Bytes.u16(name.bytes, at + 2)
			e = Bytes.u16(name.bytes, start).bitwise_or(0x20)
			n = Bytes.u16(name.bytes, start + 2).bitwise_or(0x20)
			english_start = length >= 4 and e == 0x65 and n == 0x6E
			english_start and (length == 4 or (length >= 6 and Bytes.u16(name.bytes, start + 4) == 0x2D))
		}

	# Whether strings in a platform's encoding are UTF-16BE.
	utf16_encoding : U64, U64 -> Bool
	utf16_encoding = |platform_id, encoding|
		if platform_id == 0 {
			encoding <= 4 or encoding == 6
		} else if platform_id == 3 {
			encoding == 0 or encoding == 1 or encoding == 10
		} else {
			Bool.False
		}

	# ------------------------------------------------------------ reading

	## The naming table of a font file, or `Absent` when the font has none.
	## The table is optional.
	from_tables : List(U8), List(Sfnt.Table) -> Try([Present(TableName), Absent], List([BadTable({ table : Str, offset : U32 })]))
	from_tables = |bytes, tables| {
		tag = Sfnt.tag_of("name")
		match tables.find_first(|t| t.tag == tag) {
			Err(_) => Ok(Absent)
			Ok(t) =>
				if Bytes.fits(t.offset, t.length, bytes.len()) {
					match TableName.read(bytes.sublist({ start: t.offset, len: t.length }), t.offset) {
						Ok(name) => Ok(Present(name))
						Err(problems) => Err(problems)
					}
				} else {
					Err([TableName.bad(t.offset, 0)])
				}
		}
	}

	## Check a `name` table's bytes exactly as OTS 9.3.0 does
	## (`ots/src/name.cc`, `OpenTypeNAME::Parse` and `Serialize`; line
	## numbers below are that file's), so a font reads exactly when a
	## browser accepts its names. `base` is the table's offset in the file,
	## used only to place problems.
	##
	## OTS refuses a table whose header, name records or language-tag
	## records do not fit, whose string storage starts inside those records,
	## or whose language tag lies outside the table or is longer than 200
	## bytes. It also refuses one it cannot write back: more than 5460 name
	## records, or more than 65535 bytes of strings, counting only the
	## records it keeps and the names it adds (below). Each problem gives the
	## byte offset in the file of the field that was wrong.
	##
	## OTS keeps a font whose individual records are unusable, discarding
	## those records: an unknown platform or encoding, a string outside the
	## table, or a PostScript name (ID 6) that is too long or, in UTF-16, not
	## Latin-1. roc-font accepts the same fonts and never chooses such a
	## record, nor a UTF-16BE string that is not well-formed (an odd length
	## or an unpaired surrogate, which no `Str` holds) or a language ID past
	## the language tags; OTS keeps those, but a query cannot decode them.
	## OTS also adds placeholder names ("OTS derived font") for name IDs 1,
	## 2, 4, 5 and 6 when no kept Macintosh or Windows record has them; they
	## count towards its size limit here, but a query never returns them.
	## (OTS can add further placeholder names for IDs that `fvar` or `STAT`
	## refer to; they are not counted, and no corpus font comes near the
	## limit.)
	read : List(U8), U64 -> Try(TableName, List([BadTable({ table : Str, offset : U32 })]))
	read = |data, base| {
		size = data.len()
		format = Bytes.u16(data, 0)
		count = Bytes.u16(data, 2)
		storage = Bytes.u16(data, 4)
		tags_at = 6 + 12 * count
		# Lines 69-82: the format (0 or 1), the count and the string offset,
		# which lies inside the table.
		if size < 6 or format > 1 {
			return Err([TableName.bad(base, 0)])
		}
		if storage > size {
			return Err([TableName.bad(base, 4)])
		}
		# Lines 92-102: every name record readable.
		if !Bytes.fits(6, 12 * count, size) {
			return Err([TableName.bad(base, 2)])
		}
		# Lines 166-177: the language-tag count and records readable.
		if format == 1 and !Bytes.fits(tags_at, 2, size) {
			return Err([TableName.bad(base, tags_at)])
		}
		tag_count = if (format == 1) Bytes.u16(data, tags_at) else 0
		if format == 1 and !Bytes.fits(tags_at + 2, 4 * tag_count, size) {
			return Err([TableName.bad(base, tags_at)])
		}
		# Lines 178-190: each tag inside the table and at most 200 bytes.
		var $problems = []
		var $tag_bytes = 0
		for k in 0..<tag_count {
			at = tags_at + 2 + 4 * k
			length = Bytes.u16(data, at)
			if storage + Bytes.u16(data, at + 2) + length > size or length > 200 {
				$problems = $problems.append(TableName.bad(base, at))
			}
			$tag_bytes = $tag_bytes + length
		}
		# Lines 196-200: the string storage starts after the records.
		records_end = if (format == 1) tags_at + 2 + 4 * tag_count else tags_at
		if records_end > storage {
			$problems = $problems.append(TableName.bad(base, 4))
		}
		if !$problems.is_empty() {
			return Err($problems)
		}
		name = { bytes: data, count, storage, tag_count, tags_at: if (format == 1) tags_at else 0 }
		# Serialize, lines 266-314: what OTS writes back. Lines 202-257: the
		# names OTS adds, for each of IDs 1, 2, 4, 5 and 6 (whose texts are
		# 16, 11, 16, 5 and 16 bytes) without a kept Macintosh or Windows
		# record, a Macintosh copy and a Windows copy of twice the length.
		var $kept = 0
		var $string_bytes = 0
		var $standard = 0
		for i in 0..<count {
			at = 6 + 12 * i
			if TableName.kept(name, at) {
				platform_id = Bytes.u16(data, at)
				id = Bytes.u16(data, at + 6)
				$kept = $kept + 1
				$string_bytes = $string_bytes + Bytes.u16(data, at + 8)
				if (platform_id == 1 or platform_id == 3) and id <= 6 {
					$standard = $standard.bitwise_or((1.U64).shl_wrap(id.to_u8_wrap()))
				}
			}
		}
		var $names = $kept
		var $added_bytes = 0
		for std in [{ id: 1, length: 16 }, { id: 2, length: 11 }, { id: 4, length: 16 }, { id: 5, length: 5 }, { id: 6, length: 16 }] {
			if $standard.bitwise_and((1.U64).shl_wrap(std.id.to_u8_wrap())) == 0 {
				$names = $names + 2
				$added_bytes = $added_bytes + 3 * std.length
			}
		}
		# Lines 267-279: the string offset OTS would write (its record count
		# is a 16-bit number) fits 16 bits; lines 286-313: so does the
		# string storage, names first, then language tags.
		string_offset = 6 + 12 * ($names % 65536) + (if (tag_count > 0) 2 + 4 * tag_count else 0)
		if string_offset > 0xFFFF {
			return Err([TableName.bad(base, 2)])
		}
		if $string_bytes + $added_bytes + $tag_bytes > 0xFFFF {
			return Err([TableName.bad(base, 4)])
		}
		Ok(name)
	}

	# Whether OTS keeps the name record at `at` (name.cc lines 103-155): a
	# known platform and encoding, a string inside the table, and a
	# PostScript name (ID 6) of at most 63 characters, all Latin-1 in
	# UTF-16.
	kept : TableName, U64 -> Bool
	kept = |name, at| {
		platform_id = Bytes.u16(name.bytes, at)
		encoding = Bytes.u16(name.bytes, at + 2)
		id = Bytes.u16(name.bytes, at + 6)
		length = Bytes.u16(name.bytes, at + 8)
		start = name.storage + Bytes.u16(name.bytes, at + 10)
		known =
			if platform_id == 0 {
				encoding <= 6
			} else if platform_id == 1 {
				encoding <= 32
			} else if platform_id == 2 {
				encoding <= 2
			} else if platform_id == 3 {
				encoding <= 6 or encoding == 10
			} else {
				platform_id == 4 and encoding <= 255
			}
		inside = start + length <= name.bytes.len()
		postscript =
			if id != 6 {
				Bool.True
			} else if platform_id == 1 {
				length <= 63
			} else if platform_id == 0 or platform_id == 3 {
				length % 2 == 0 and length <= 126 and TableName.latin1_utf16(name.bytes, start, length)
			} else {
				Bool.True
			}
		known and inside and postscript
	}

	# Whether every UTF-16BE code unit of `length` bytes from `start` (an
	# even length inside `data`) has a zero high byte.
	latin1_utf16 : List(U8), U64, U64 -> Bool
	latin1_utf16 = |data, start, length| {
		var $ok = Bool.True
		var $i = 0
		while $ok and $i < length {
			$ok = Bytes.u8(data, start + $i) == 0
			$i = $i + 2
		}
		$ok
	}

	# A problem at byte `at` of a table at `base` in the file. Fonts larger
	# than 4 GiB are refused before tables are read, so the sum fits.
	bad : U64, U64 -> [BadTable({ table : Str, offset : U32 })]
	bad = |base, at| BadTable({ table: "name", offset: (base + at).to_u32_wrap() })

	# Whether `length` bytes from `start` (inside `data`) are well-formed
	# UTF-16BE: an even length, and every surrogate in a high-low pair.
	well_formed : List(U8), U64, U64 -> Bool
	well_formed = |data, start, length| {
		var $ok = length % 2 == 0
		var $i = 0
		while $ok and $i < length {
			unit = Bytes.u16(data, start + $i)
			if unit >= 0xD800 and unit < 0xDC00 {
				low = if ($i + 4 <= length) Bytes.u16(data, start + $i + 2) else 0
				$ok = low >= 0xDC00 and low < 0xE000
				$i = $i + 4
			} else {
				$ok = unit < 0xDC00 or unit >= 0xE000
				$i = $i + 2
			}
		}
		$ok
	}

	# ------------------------------------------------------------ decoding

	# Decode UTF-16BE that `well_formed` accepted. The fallback of
	# `Str.from_utf8` is unreachable: every scalar encoded is a valid one.
	utf16 : List(U8), U64, U64 -> Str
	utf16 = |data, start, length| {
		var $out = List.with_capacity(length // 2 * 3)
		var $i = 0
		while $i + 1 < length {
			unit = Bytes.u16(data, start + $i)
			if unit >= 0xD800 and unit < 0xDC00 {
				low = Bytes.u16(data, start + $i + 2)
				$out = TableName.push_utf8($out, 0x10000 + (unit - 0xD800) * 0x400 + (low - 0xDC00))
				$i = $i + 4
			} else {
				$out = TableName.push_utf8($out, unit)
				$i = $i + 2
			}
		}
		Str.from_utf8($out) ?? ""
	}

	# Decode Mac OS Roman. Every byte is a character, so the fallbacks are
	# unreachable.
	mac_roman : List(U8), U64, U64 -> Str
	mac_roman = |data, start, length| {
		var $out = List.with_capacity(length * 3)
		for i in 0..<length {
			b = Bytes.u8(data, start + i)
			c = if (b < 0x80) b else (TableName.mac_roman_high.get(b - 0x80) ?? 0).to_u64()
			$out = TableName.push_utf8($out, c)
		}
		Str.from_utf8($out) ?? ""
	}

	## Append the UTF-8 encoding of a Unicode scalar value.
	push_utf8 : List(U8), U64 -> List(U8)
	push_utf8 = |out, c|
		if c < 0x80 {
			out.append(c.to_u8_wrap())
		} else if c < 0x800 {
			out.append(c.shr_zf_wrap(6).bitwise_or(0xC0).to_u8_wrap()).append(c.bitwise_and(0x3F).bitwise_or(0x80).to_u8_wrap())
		} else if c < 0x10000 {
			out
				.append(c.shr_zf_wrap(12).bitwise_or(0xE0).to_u8_wrap())
				.append(c.shr_zf_wrap(6).bitwise_and(0x3F).bitwise_or(0x80).to_u8_wrap())
				.append(c.bitwise_and(0x3F).bitwise_or(0x80).to_u8_wrap())
		} else {
			out
				.append(c.shr_zf_wrap(18).bitwise_or(0xF0).to_u8_wrap())
				.append(c.shr_zf_wrap(12).bitwise_and(0x3F).bitwise_or(0x80).to_u8_wrap())
				.append(c.shr_zf_wrap(6).bitwise_and(0x3F).bitwise_or(0x80).to_u8_wrap())
				.append(c.bitwise_and(0x3F).bitwise_or(0x80).to_u8_wrap())
		}

	# The characters of Mac OS Roman bytes 0x80 to 0xFF (Apple's ROMAN.TXT,
	# as Python's `mac_roman` codec and HarfBuzz have it: 0xDB is the euro
	# sign and 0xF0 the Apple logo, U+F8FF).
	mac_roman_high : List(U16)
	mac_roman_high = [0x00C4, 0x00C5, 0x00C7, 0x00C9, 0x00D1, 0x00D6, 0x00DC, 0x00E1, 0x00E0, 0x00E2, 0x00E4, 0x00E3, 0x00E5, 0x00E7, 0x00E9, 0x00E8, 0x00EA, 0x00EB, 0x00ED, 0x00EC, 0x00EE, 0x00EF, 0x00F1, 0x00F3, 0x00F2, 0x00F4, 0x00F6, 0x00F5, 0x00FA, 0x00F9, 0x00FB, 0x00FC, 0x2020, 0x00B0, 0x00A2, 0x00A3, 0x00A7, 0x2022, 0x00B6, 0x00DF, 0x00AE, 0x00A9, 0x2122, 0x00B4, 0x00A8, 0x2260, 0x00C6, 0x00D8, 0x221E, 0x00B1, 0x2264, 0x2265, 0x00A5, 0x00B5, 0x2202, 0x2211, 0x220F, 0x03C0, 0x222B, 0x00AA, 0x00BA, 0x03A9, 0x00E6, 0x00F8, 0x00BF, 0x00A1, 0x00AC, 0x221A, 0x0192, 0x2248, 0x2206, 0x00AB, 0x00BB, 0x2026, 0x00A0, 0x00C0, 0x00C3, 0x00D5, 0x0152, 0x0153, 0x2013, 0x2014, 0x201C, 0x201D, 0x2018, 0x2019, 0x00F7, 0x25CA, 0x00FF, 0x0178, 0x2044, 0x20AC, 0x2039, 0x203A, 0xFB01, 0xFB02, 0x2021, 0x00B7, 0x201A, 0x201E, 0x2030, 0x00C2, 0x00CA, 0x00C1, 0x00CB, 0x00C8, 0x00CD, 0x00CE, 0x00CF, 0x00CC, 0x00D3, 0x00D4, 0xF8FF, 0x00D2, 0x00DA, 0x00DB, 0x00D9, 0x0131, 0x02C6, 0x02DC, 0x00AF, 0x02D8, 0x02D9, 0x02DA, 0x00B8, 0x02DD, 0x02DB, 0x02C7]
}

# ----------------------------------------------------------------------

# Tests of the reader on hand-built tables and on naming tables of the
# fixtures in `tests/fonts/name-post/` (generated by its `generate.py`),
# embedded below. Expected family names of real fonts are fontTools 4.61.1's
# `getBestFamilyName()`. Across the corpus, the defaults and the fixtures
# fontTools reads (543 fonts), roc-font agrees with it on 540; one font's
# naming table lies outside the file, which both refuse, and on two fonts
# fontTools prefers a Macintosh record to a Windows one (`TestAVAR.ttf` in
# the HarfBuzz tests, and `ranking-v2.ttf` below). Family names callers see
# are tested through the public API in `tests/api/`. Top-level expects and
# helpers are not part of the module's API. Run with
# `roc test package/TableName.roc`.

# ------------------------------------------------------------ helpers

u16 : U64 -> List(U8)
u16 = |v| [v.shr_zf_wrap(8).bitwise_and(0xFF).to_u8_wrap(), v.bitwise_and(0xFF).to_u8_wrap()]

# ASCII text as UTF-16BE.
utf16 : Str -> List(U8)
utf16 = |text| text.to_utf8().join_map(|b| [0, b])

Record : { pid : U64, encoding : U64, language : U64, id : U64, text : List(U8) }

# A naming table of `format` with the records in order, then the language
# tags (format 1 only), each string stored once, in order.
build : U64, List(Record), List(List(U8)) -> List(U8)
build = |format, records, tags| {
	tag_part = if (format == 1) 2 + 4 * tags.len() else 0
	storage = 6 + 12 * records.len() + tag_part
	var $head = u16(format).concat(u16(records.len())).concat(u16(storage))
	var $strings = []
	for r in records {
		$head = $head.concat(u16(r.pid)).concat(u16(r.encoding)).concat(u16(r.language)).concat(u16(r.id)).concat(u16(r.text.len())).concat(u16($strings.len()))
		$strings = $strings.concat(r.text)
	}
	if format == 1 {
		$head = $head.concat(u16(tags.len()))
		for t in tags {
			$head = $head.concat(u16(t.len())).concat(u16($strings.len()))
			$strings = $strings.concat(t)
		}
	}
	$head.concat($strings)
}

win : U64, U64, Str -> Record
win = |language, id, text| { pid: 3, encoding: 1, language, id, text: utf16(text) }

family : List(U8) -> Try(Str, [Missing, Rejected])
family = |table|
	match TableName.read(table, 0) {
		Ok(name) => TableName.family_name(name).map_err(|_| Missing)
		Err(_) => Err(Rejected)
	}

problems : List(U8), U64 -> List([BadTable({ table : Str, offset : U32 })])
problems = |table, base|
	match TableName.read(table, base) {
		Ok(_) => []
		Err(found) => found
	}

# Replace a byte; tests pass indices inside the table.
put : List(U8), U64, U8 -> List(U8)
put = |list, at, value| list.set(at, value) ?? []

bad : U32 -> [BadTable({ table : Str, offset : U32 })]
bad = |offset| BadTable({ table: "name", offset })

from_file : List(U8) -> Try(Str, [Missing, Absent, Rejected])
from_file = |bytes|
	match Sfnt.directory(bytes) {
		Err(_) => Err(Rejected)
		Ok(tables) =>
			match TableName.from_tables(bytes, tables) {
				Ok(Present(name)) => TableName.family_name(name).map_err(|_| Missing)
				Ok(Absent) => Err(Absent)
				Err(_) => Err(Rejected)
			}
	}

# ------------------------------------------------------------ fonts

# A font without a naming table reads as absent, not as a problem. This
# file's directory lists only a four-byte `head` table.
expect {
	directory = [0, 1, 0, 0, 0, 1, 0, 16, 0, 0, 0, 0]
	record = "head".to_utf8().concat([0, 0, 0, 0]).concat([0, 0, 0, 28]).concat([0, 0, 0, 4])
	from_file(directory.concat(record).concat([0, 0, 0, 0])) == Err(Absent)
}

# The naming table of the fixture `ranking-v2.ttf` (generated by
# `tests/fonts/name-post/generate.py`). Its family name as callers see it
# is tested through the public API in `tests/api/`.
# Generated from `tests/fonts/name-post/ranking-v2.ttf` by `tests/fonts/inline_tables.py`.

# The `name` table, 192 bytes.
ranking_name : List(U8)
ranking_name = [
	[0x00, 0x00, 0x00, 0x06, 0x00, 0x4E, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, 0x00, 0x1C],
	[0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x0A, 0x00, 0x1C, 0x00, 0x01],
	[0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x00, 0x08, 0x00, 0x26, 0x00, 0x03, 0x00, 0x01, 0x04, 0x07],
	[0x00, 0x01, 0x00, 0x0E, 0x00, 0x2E, 0x00, 0x03, 0x00, 0x01, 0x08, 0x09, 0x00, 0x01, 0x00, 0x1C],
	[0x00, 0x3C, 0x00, 0x03, 0x00, 0x0A, 0x04, 0x09, 0x00, 0x10, 0x00, 0x1A, 0x00, 0x58, 0x00, 0x55],
	[0x00, 0x6E, 0x00, 0x69, 0x00, 0x63, 0x00, 0x6F, 0x00, 0x64, 0x00, 0x65, 0x00, 0x20, 0x00, 0x46],
	[0x00, 0x61, 0x00, 0x6D, 0x00, 0x69, 0x00, 0x6C, 0x00, 0x79, 0x4D, 0x61, 0x63, 0x20, 0x46, 0x61],
	[0x6D, 0x69, 0x6C, 0x79, 0x4D, 0x61, 0x63, 0x20, 0x54, 0x79, 0x70, 0x6F, 0x00, 0x44, 0x00, 0x65],
	[0x00, 0x75, 0x00, 0x74, 0x00, 0x73, 0x00, 0x63, 0x00, 0x68, 0x00, 0x42, 0x00, 0x72, 0x00, 0x69],
	[0x00, 0x74, 0x00, 0x69, 0x00, 0x73, 0x00, 0x68, 0x00, 0x20, 0x00, 0x46, 0x00, 0x61, 0x00, 0x6D],
	[0x00, 0x69, 0x00, 0x6C, 0x00, 0x79, 0x00, 0x45, 0x00, 0x6D, 0x00, 0x6F, 0x00, 0x6A, 0x00, 0x69],
	[0x00, 0x20, 0xD8, 0x3D, 0xDE, 0x00, 0x00, 0x20, 0x00, 0x53, 0x00, 0x61, 0x00, 0x6E, 0x00, 0x73],
].join_map(|row| row)

# Of the family names (ID 1), British English beats German, the Unicode
# platform and Macintosh. fontTools answers "Mac Family": it takes the
# first English record in table order, and the Macintosh records sort
# first.
expect
	match TableName.read(ranking_name, 0) {
		Ok(name) => TableName.string(name, 1) == Ok("British Family")
		Err(_) => Bool.False
	}

# The naming table of the fixture `format1-v25.ttf`, whose `post` table
# makes the font unreadable, so its family name is not observable through
# the public API.
# Generated from `tests/fonts/name-post/format1-v25.ttf` by `tests/fonts/inline_tables.py`.

# The `name` table, 98 bytes.
format1_name : List(U8)
format1_name = [
	[0x00, 0x01, 0x00, 0x02, 0x00, 0x28, 0x00, 0x00, 0x00, 0x04, 0x80, 0x00, 0x00, 0x01, 0x00, 0x16],
	[0x00, 0x00, 0x00, 0x00, 0x00, 0x04, 0x80, 0x01, 0x00, 0x01, 0x00, 0x16, 0x00, 0x16, 0x00, 0x02],
	[0x00, 0x04, 0x00, 0x2C, 0x00, 0x0A, 0x00, 0x30, 0x00, 0x44, 0x00, 0x65, 0x00, 0x75, 0x00, 0x74],
	[0x00, 0x73, 0x00, 0x63, 0x00, 0x68, 0x00, 0x20, 0x00, 0x54, 0x00, 0x61, 0x00, 0x67, 0x00, 0x45],
	[0x00, 0x6E, 0x00, 0x67, 0x00, 0x6C, 0x00, 0x69, 0x00, 0x73, 0x00, 0x68, 0x00, 0x20, 0x00, 0x54],
	[0x00, 0x61, 0x00, 0x67, 0x00, 0x64, 0x00, 0x65, 0x00, 0x45, 0x00, 0x4E, 0x00, 0x2D, 0x00, 0x75],
	[0x00, 0x73],
].join_map(|row| row)

# A format 1 table: the record tagged `EN-us` beats the earlier one tagged
# `de`. fontTools agrees.
expect family(format1_name) == Ok("English Tag")

# ------------------------------------------------------------ preference

# Each rank beats the next, whatever the record order.
expect {
	mac = { pid: 1, encoding: 0, language: 0, id: 1, text: "Mac".to_utf8() }
	unicode = { pid: 0, encoding: 3, language: 0, id: 1, text: utf16("Unicode") }
	other = win(0x407, 1, "Other")
	english = win(0x0C09, 1, "Australian")
	us = win(0x409, 1, "US")
	all = [
		family(build(0, [other, mac, unicode, english, us], [])) == Ok("US"),
		family(build(0, [other, mac, unicode, english], [])) == Ok("Australian"),
		family(build(0, [other, mac, unicode], [])) == Ok("Unicode"),
		family(build(0, [other, mac], [])) == Ok("Mac"),
		family(build(0, [other], [])) == Ok("Other"),
	]
	all.all(|ok| ok)
}

# The typographic family name beats the family name, and the first record
# of a rank wins.
expect family(build(0, [win(0x409, 1, "Family"), win(0x407, 16, "First"), win(0x407, 16, "Second")], [])) == Ok("First")

# Windows symbol and full-repertoire encodings are UTF-16 too.
expect family(build(0, [{ pid: 3, encoding: 0, language: 0x409, id: 1, text: utf16("Symbol") }], [])) == Ok("Symbol")
expect family(build(0, [{ pid: 3, encoding: 10, language: 0x409, id: 1, text: [0xD8, 0x3D, 0xDE, 0x00] }], [])) == Ok("\u(1F600)")

# Strings in encodings this module does not decode are never chosen:
# Windows ShiftJIS, Macintosh Japanese, Macintosh Roman in French, and a
# Unicode variation-sequence encoding.
expect {
	records = [
		{ pid: 3, encoding: 2, language: 0x411, id: 1, text: [0x93, 0xFA] },
		{ pid: 1, encoding: 1, language: 11, id: 1, text: [0x93] },
		{ pid: 1, encoding: 0, language: 1, id: 1, text: "Fran".to_utf8() },
		{ pid: 0, encoding: 5, language: 0, id: 1, text: utf16("Variation") },
	]
	family(build(0, records, [])) == Err(Missing)
}

# A Windows record with an English language tag ranks as English.
expect {
	records = [win(0x407, 1, "German"), win(0x8000, 1, "Tagged")]
	family(build(1, records, [utf16("en-AU")])) == Ok("Tagged")
}

# `eng` and `enx` are not English tags.
expect {
	records = [{ pid: 0, encoding: 4, language: 0x8000, id: 1, text: utf16("First") }, { pid: 0, encoding: 4, language: 0x8001, id: 1, text: utf16("Second") }]
	family(build(1, records, [utf16("de"), utf16("eng")])) == Ok("First")
}

# ------------------------------------------------------------ degenerate tables

expect family(build(0, [], [])) == Err(Missing)
expect family(build(1, [], [])) == Err(Missing)
expect TableName.family_name(TableName.none) == Err(Missing)

# An empty string is a name.
expect family(build(0, [win(0x409, 1, "")], [])) == Ok("")

# A name ID with no records is missing, whatever else the table holds.
expect family(build(0, [win(0x409, 2, "Regular")], [])) == Err(Missing)

# ------------------------------------------------------------ problems

# Too short for the header, an unknown format, records past the end, string
# storage past the end. Offsets are in the file (the table is at 1000).
expect problems([0, 0, 0], 1000) == [bad(1000)]
expect problems(build(2, [], []), 1000) == [bad(1000)]
expect problems(u16(0).concat(u16(2)).concat(u16(26)).concat(List.repeat(0, 20)), 1000) == [bad(1002)]
expect problems(u16(0).concat(u16(0)).concat(u16(7)), 1000) == [bad(1004)]

# A format 1 table too short for its language-tag count, or for its tags.
expect problems(u16(1).concat(u16(0)).concat(u16(6)), 0) == [bad(6)]
expect problems(u16(1).concat(u16(0)).concat(u16(8)).concat(u16(1)), 0) == [bad(6)]

# OTS keeps a table whose records are unusable, and so does reading; a
# query never chooses them: a string past the end, an odd-length UTF-16
# string, a lone low surrogate and a high surrogate at the end.
expect {
	records = [
		win(0x409, 1, "Good"),
		win(0x409, 1, "Odd"),
		{ pid: 0, encoding: 3, language: 0, id: 1, text: [0, 0x41, 0xDC, 0x00] },
		{ pid: 3, encoding: 10, language: 0x409, id: 1, text: [0, 0x41, 0xD8, 0x00] },
		{ pid: 1, encoding: 0, language: 0, id: 1, text: "Mac".to_utf8() },
	]
	table = build(0, records, [])
	# Make record 1 odd (length 5 of its 6 bytes) and record 0 run past
	# the end (offset 0xFF00).
	odd = put(table, 6 + 12 + 9, 5)
	broken = put(odd, 6 + 10, 0xFF)
	problems(broken, 0) == [] and family(broken) == Ok("Mac")
}

# A high surrogate followed by something other than a low surrogate.
expect {
	table = build(0, [{ pid: 3, encoding: 1, language: 0x409, id: 1, text: [0xD8, 0x3D, 0, 0x41] }], [])
	problems(table, 0) == [] and family(table) == Err(Missing)
}

# Records OTS discards are never chosen: an unknown platform or encoding,
# and a PostScript name (ID 6) in UTF-16 that is not Latin-1.
expect {
	records = [
		{ pid: 5, encoding: 0, language: 0, id: 1, text: "Five".to_utf8() },
		{ pid: 3, encoding: 7, language: 0x409, id: 1, text: utf16("Seven") },
		{ pid: 3, encoding: 1, language: 0x409, id: 6, text: [0x01, 0x41] },
	]
	table = build(0, records, [])
	match TableName.read(table, 0) {
		Ok(name) => TableName.family_name(name) == Err(Missing) and TableName.string(name, 6) == Err(Missing)
		Err(_) => Bool.False
	}
}
expect {
	match TableName.read(build(0, [win(0x409, 6, "Name-PS")], []), 0) {
		Ok(name) => TableName.string(name, 6) == Ok("Name-PS")
		Err(_) => Bool.False
	}
}

# Strings in encodings this module does not decode are accepted, even past
# the end of the table (OTS discards them).
expect problems(build(0, [{ pid: 3, encoding: 2, language: 0x411, id: 1, text: [0x93, 0xFA, 0x41] }], []), 0) == []
expect {
	table = build(0, [{ pid: 1, encoding: 1, language: 11, id: 1, text: [0x93] }], [])
	problems(put(table, 16, 0xFF), 0) == []
}

# A language tag past the end is placed at its tag record; one that is
# not well-formed UTF-16, or a language ID past the tags, is accepted (as
# OTS accepts it) and is not English.
expect {
	records = [{ pid: 0, encoding: 4, language: 0x8002, id: 1, text: utf16("A") }]
	table = build(1, records, [utf16("en"), [0xDC, 0x00]])
	broken = put(table, 6 + 12 + 2 + 2, 0xFF)
	problems(broken, 0) == [bad(20)] and family(table) == Ok("A")
}

# A language tag longer than 200 bytes (name.cc lines 188-190).
expect {
	records = [win(0x409, 1, "A")]
	problems(build(1, records, [List.repeat(0x41, 200)]), 0) == [] and problems(build(1, records, [List.repeat(0x41, 202)]), 0) == [bad(20)]
}

# String storage that starts inside the name records (lines 196-200),
# placed at the string offset; both tag problems and this are reported.
expect problems(u16(0).concat(u16(1)).concat(u16(6)).concat(List.repeat(0, 12)), 0) == [bad(4)]
expect {
	table = build(1, [], [utf16("en")])
	# Storage moved back to 8, inside the tag record; the tag (at 4 from
	# there) still fits.
	problems(put(table, 5, 8), 0) == [bad(4)]
}

# A table OTS cannot write back: more than 5460 records once it adds its
# 10 placeholder names (lines 267-279), or more than 65535 bytes of strings
# with its 192 bytes of placeholders (lines 286-313), records sharing one
# string counted once each.
shared : List(U64), U64 -> List(U8)
shared = |lengths, id| {
	storage = 6 + 12 * lengths.len()
	longest = lengths.fold(0, |m, l| if (l > m) l else m)
	var $out = u16(0).concat(u16(lengths.len())).concat(u16(storage))
	for l in lengths {
		$out = $out.concat(u16(3)).concat(u16(1)).concat(u16(0x409)).concat(u16(id)).concat(u16(l)).concat(u16(0))
	}
	$out.concat(List.repeat(0x41, longest))
}
expect problems(shared(List.repeat(0, 5450), 0), 0) == []
expect problems(shared(List.repeat(0, 5451), 0), 0) == [bad(2)]
expect problems(shared(List.repeat(250, 261).append(93), 0), 0) == []
expect problems(shared(List.repeat(250, 261).append(94), 0), 0) == [bad(4)]

# Kept Windows names for IDs 1, 2, 4, 5 and 6 mean OTS adds none, so the
# same strings fit with 192 bytes more.
expect {
	standard = [1, 2, 4, 5, 6].map(|id| { pid: 3, encoding: 1, language: 0x409, id, text: utf16("A") })
	table = build(0, standard, [])
	problems(table, 0) == []
}

# A naming table that lies outside the file is placed at its offset.
expect {
	tables = [{ tag: Sfnt.tag_of("name"), offset: 100, length: 50 }]
	match TableName.from_tables(List.repeat(0, 120), tables) {
		Err(found) => found == [bad(100)]
		Ok(_) => Bool.False
	}
}
