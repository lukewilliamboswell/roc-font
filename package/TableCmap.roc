import Sfnt
import TableOs2
import Bytes
import Sorted

## The character map (`cmap`): which glyph draws each character.
##
## A font may hold several maps (subtables) for different platforms and
## encodings. Reading picks one in the order HarfBuzz does: a Windows
## symbol map (3, 0) first, then the full Unicode maps (3, 10), (0, 6) and
## (0, 4), then the Basic Multilingual Plane maps (3, 1), (0, 3), (0, 2),
## (0, 1) and (0, 0), and last a Macintosh map (1, 0) or any other
## Macintosh encoding. Within one rank the first record wins. Subtables in
## formats 0, 4, 6, 10, 12 and 13 are read as the map; a record in another
## format (2 or 8, or 14, which holds variation sequences, read below) is
## passed over.
##
## Reading checks every field of the chosen subtable and turns it, whatever
## its format, into one flat list of character ranges in code point order:
## consecutive characters drawn by consecutive glyphs (or, for format 13,
## by one glyph). A lookup is a binary search of that list. The list is
## built with a handful of allocations (one sized by the group count for
## formats 12 and 13; amortised growth for the others), never one per
## character or group. A subtable whose fields do not fit, or whose
## segments or groups are out of order or overlap, is a bad table.
##
## Before choosing, the whole table is checked exactly as OTS 9.3.0 checks
## it (`check`), so a font reads exactly when a browser accepts its map.
## In particular a format 4, 12 or 13 subtable that names a glyph at or
## past `maxp`'s glyph count refuses the font, as OTS refuses it. Formats
## OTS does not check (0 outside the Macintosh Roman map, 6 and 10) may
## still name such glyphs; a lookup treats them as missing.
##
## Why an index rather than reading the subtable in place: on the
## `scripts/bench.py --ops cmap` sweeps (every BMP code point against Inter,
## Noto Sans Arabic and Source Sans) a binary search of the subtable's bytes
## was 1.2 to 4 times slower per lookup, and a lookup that dispatches on the
## format at query time cost as much again on small maps, while building
## the list costs one pass over the subtable when reading.
##
## Some maps do not use Unicode code points. Reading translates them to
## Unicode as HarfBuzz's lookups do, adding the translated characters to
## the list, so a lookup is the same single search for every map:
##
## - A symbol map with no Windows 3.1 font page (the `OS/2` table's version
##   0 page bits) maps the characters a symbol font draws at U+F000 to
##   U+F0FF; a code point up to U+00FF that the map does not have takes the
##   glyph of the code point 0xF000 above it, as Windows does.
## - A symbol map in a simplified or traditional Arabic Windows 3.1 font
##   page holds Arabic in the private use area; a code point the map does
##   not have takes the glyph of its private use code point.
## - A Macintosh Roman map gives ASCII directly and the other 128
##   characters of the Mac Roman encoding through it; any other Macintosh
##   map gives ASCII only.
##
## In every case a character that maps to glyph 0, the missing glyph, is
## not in the list.
##
## Variation sequences (a character followed by a variation selector) come
## from the Unicode variation sequences subtable (platform 0, encoding 5,
## format 14), as HarfBuzz finds it. Reading checks that its records and
## every default and non-default table they point to lie inside the `cmap`
## table, and flattens them into three lists (`Variants`); a lookup is two
## binary searches. A broken format 14 subtable is a bad `cmap`, as OTS
## refuses it.
TableCmap := {
	ranges : List({ first : U32, last : U32, glyph : U32 }),
	same : Bool,
	variants : Variants,
}.{

	## A font's variation sequences: per variation selector (in the
	## subtable's order) the spans of its default ranges and non-default
	## mappings in `defaults` and `mappings`.
	Variants : {
		records : List({ selector : U32, defaults : U64, defaults_end : U64, mappings : U64, mappings_end : U64 }),
		defaults : List({ first : U32, last : U32 }),
		mappings : List({ code : U32, glyph : U32 }),
	}

	no_variants : Variants
	no_variants = { records: [], defaults: [], mappings: [] }

	## The variation sequences of a map.
	variants_of : TableCmap -> Variants
	variants_of = |cmap| cmap.variants

	## The glyph of a variation sequence, as HarfBuzz's
	## `get_glyph_variant` gives it: `Found` (a glyph of its own), `UseDefault`
	## (the character's usual glyph) or `NotFound`. The selector's records
	## and ranges are searched as stored: the format asks for increasing
	## order, which reading does not check, so a font that breaks it gets
	## what a binary search finds, as in HarfBuzz.
	variant : Variants, U32, U32 -> [Found(U64), UseDefault, NotFound]
	variant = |variants, code_point, selector| {
		var $low = 0
		var $high = variants.records.len()
		var $record = Err(NotFound)
		while $low < $high {
			mid = ($low + $high) // 2
			r = variants.records.get(mid) ?? { selector: 0, defaults: 0, defaults_end: 0, mappings: 0, mappings_end: 0 }
			if selector < r.selector {
				$high = mid
			} else if selector > r.selector {
				$low = mid + 1
			} else {
				$record = Ok(r)
				$low = $high
			}
		}
		match $record {
			Err(_) => NotFound
			Ok(r) => {
				var $lo = r.defaults
				var $hi = r.defaults_end
				var $default = False
				while $lo < $hi {
					mid = ($lo + $hi) // 2
					d = variants.defaults.get(mid) ?? { first: 1, last: 0 }
					if code_point < d.first {
						$hi = mid
					} else if code_point > d.last {
						$lo = mid + 1
					} else {
						$default = True
						$lo = $hi
					}
				}
				if $default {
					UseDefault
				} else {
					var $l = r.mappings
					var $h = r.mappings_end
					var $found = NotFound
					while $l < $h {
						mid = ($l + $h) // 2
						m = variants.mappings.get(mid) ?? { code: 0, glyph: 0 }
						if code_point < m.code {
							$h = mid
						} else if code_point > m.code {
							$l = mid + 1
						} else {
							$found = Found(m.glyph.to_u64())
							$l = $h
						}
					}
					$found
				}
			}
		}
	}

	## Find and check the format 14 subtable of a `cmap` table (the first
	## record for platform 0, encoding 5, whose subtable has format 14).
	read_variants : List(U8) -> Try(Variants, [Bad(U64)])
	read_variants = |cmap| {
		count = Bytes.u16(cmap, 2)
		var $at = Err(NotFound)
		var $i = 0
		while $i < count {
			rec = 4 + 8 * $i
			offset = Bytes.u32(cmap, rec + 4)
			if Bytes.u16(cmap, rec) == 0 and Bytes.u16(cmap, rec + 2) == 5 and Bytes.fits(offset, 2, cmap.len()) and Bytes.u16(cmap, offset) == 14 {
				$at = Ok(offset)
				$i = count
			} else {
				$i = $i + 1
			}
		}
		match $at {
			Err(_) => Ok(TableCmap.no_variants)
			Ok(at) => TableCmap.read_format14(Bytes.rest(cmap, at)).map_err(|_| Bad(at))
		}
	}

	# A format 14 subtable (`data` runs to the end of the `cmap` table):
	# records of an increasing variation selector, each with offsets from
	# the subtable's start to a default table (ranges of a 24-bit start and
	# an 8-bit count of further characters) and a non-default table
	# (mappings of a 24-bit character to a glyph). Allocation is sized by
	# counts checked against the data.
	read_format14 : List(U8) -> Try(Variants, [Bad])
	read_format14 = |data| {
		size = data.len()
		count = Bytes.u32(data, 6)
		if !Bytes.fits(0, 10, size) or !Bytes.fits(10, 11 * count, size) {
			return Err(Bad)
		}
		var $records = List.with_capacity(count)
		var $defaults = []
		var $mappings = []
		for i in 0..<count {
			rec = 10 + 11 * i
			selector = Bytes.u16(data, rec) * 256 + Bytes.u8(data, rec + 2)
			default_at = Bytes.u32(data, rec + 3)
			mapping_at = Bytes.u32(data, rec + 7)
			defaults_start = $defaults.len()
			if default_at != 0 {
				n = Bytes.u32(data, default_at)
				if !Bytes.fits(default_at, 4, size) or !Bytes.fits(default_at + 4, 4 * n, size) {
					return Err(Bad)
				}
				for k in 0..<n {
					r = default_at + 4 + 4 * k
					first = Bytes.u16(data, r) * 256 + Bytes.u8(data, r + 2)
					$defaults = $defaults.append({ first: first.to_u32_wrap(), last: (first + Bytes.u8(data, r + 3)).to_u32_wrap() })
				}
			}
			mappings_start = $mappings.len()
			if mapping_at != 0 {
				n = Bytes.u32(data, mapping_at)
				if !Bytes.fits(mapping_at, 4, size) or !Bytes.fits(mapping_at + 4, 5 * n, size) {
					return Err(Bad)
				}
				for k in 0..<n {
					m = mapping_at + 4 + 5 * k
					$mappings = $mappings.append({ code: (Bytes.u16(data, m) * 256 + Bytes.u8(data, m + 2)).to_u32_wrap(), glyph: Bytes.u16(data, m + 3).to_u32_wrap() })
				}
			}
			$records = $records.append({ selector: selector.to_u32_wrap(), defaults: defaults_start, defaults_end: $defaults.len(), mappings: mappings_start, mappings_end: $mappings.len() })
		}
		Ok({ records: $records, defaults: $defaults, mappings: $mappings })
	}

	## Every code point the map gives a glyph below `glyph_count`, in
	## increasing order. Glyphs rise with the code points of a range (or are
	## one glyph), so the mapped code points of a range are a prefix of it.
	## The list is allocated once, at its final length.
	##
	## Why a list rather than an `Iter`: listing every code point (filling a
	## glyph atlas, the common use) took 7.6-7.9 ns per code point through
	## `Iter.custom` against 0.8-1.4 ns for this list, natively at
	## `--opt=speed` on Inter (2852 code points) and Noto Sans (2965), on the
	## 2026-10-23 nightly; an `Iter` only won when stopping after a few.
	code_points : TableCmap, U64 -> List(U32)
	code_points = |cmap, glyph_count| {
		var $count = 0
		for range in cmap.ranges {
			first = range.first.to_u64()
			glyph = range.glyph.to_u64()
			if glyph < glyph_count {
				last = if (cmap.same) range.last.to_u64() else range.last.to_u64().min(first + (glyph_count - 1 - glyph))
				$count = $count + (if (last >= first) last - first + 1 else 0)
			}
		}
		var $out = List.with_capacity($count)
		for range in cmap.ranges {
			first = range.first.to_u64()
			glyph = range.glyph.to_u64()
			if glyph < glyph_count {
				last = if (cmap.same) range.last.to_u64() else range.last.to_u64().min(first + (glyph_count - 1 - glyph))
				var $c = first
				while $c <= last {
					$out = $out.append($c.to_u32_wrap())
					$c = $c + 1
				}
			}
		}
		$out
	}

	## A map that has no characters.
	none : TableCmap
	none = { ranges: [], same: False, variants: TableCmap.no_variants }

	## The glyph of a code point, if the map has one that is not glyph 0 and
	## is below `glyph_count`.
	glyph : TableCmap, U32, U64 -> Try(U64, [Missing])
	glyph = |cmap, code_point, glyph_count| {
		found = TableCmap.range_glyph(cmap.ranges, cmap.same, code_point.to_u64())
		if (found == 0 or found >= glyph_count) Err(Missing) else Ok(found)
	}

	# The range holding `c`: its characters map to consecutive glyphs, or,
	# with `same`, all to its glyph.
	range_glyph : List({ first : U32, last : U32, glyph : U32 }), Bool, U64 -> U64
	range_glyph = |ranges, same, c| {
		var $low = 0
		var $high = ranges.len()
		var $result = 0
		while $low < $high {
			mid = ($low + $high) // 2
			range = ranges.get(mid) ?? { first: 1, last: 0, glyph: 0 }
			if c < range.first.to_u64() {
				$high = mid
			} else if c > range.last.to_u64() {
				$low = mid + 1
			} else {
				$result = if (same) range.glyph.to_u64() else range.glyph.to_u64() + (c - range.first.to_u64())
				$low = $high
			}
		}
		$result
	}

	# ------------------------------------------------------------ reading

	## The character map of a font file. A symbol map's encoding depends on
	## the Windows 3.1 font page of a version 0 `OS/2` table. The table is
	## first checked as OTS checks it (`check`), against the glyph count of
	## `maxp`; then the chosen subtable is read.
	from_tables : List(U8), List(Sfnt.Table) -> Try(TableCmap, [MissingTable(Str), BadTable({ table : Str, offset : U32 }), NoUnicodeMapping])
	from_tables = |bytes, tables| {
		found = Sfnt.required(bytes, tables, "cmap", 4)?
		page = TableOs2.font_page(bytes, tables)
		# OTS compares glyph ids with `maxp`'s glyph count. A `maxp` that
		# cannot be used (missing, short, or no glyphs) is reported by its
		# own reader and refuses the font whatever the glyph ids are, so the
		# glyph ids are not compared with it.
		# (`maxp` found by its tag as a number, 0x6D617870, which costs no
		# allocation; as `TableMaxp` reads it: the first record, at least 6
		# bytes inside the file, a glyph count other than 0.)
		glyph_count = match tables.find_first(|t| t.tag == 0x6D617870) {
			Ok(t) if Bytes.fits(t.offset, t.length, bytes.len()) and t.length >= 6 and Bytes.u16(bytes, t.offset + 4) != 0 => Present(Bytes.u16(bytes, t.offset + 4))
			_ => Absent
		}
		read = match TableCmap.check(found.data, glyph_count) {
			Ok(_) => TableCmap.read(found.data, page)
			Err(problem) => Err(problem)
		}
		match read {
			Ok(map) => Ok(map)
			Err(NoUnicodeMapping) => Err(NoUnicodeMapping)
			Err(Bad(at)) => Err(Sfnt.bad("cmap", found.offset + at))
		}
	}

	## Check a `cmap` table exactly as OTS 9.3.0 does (`ots/src/cmap.cc`,
	## `OpenTypeCMAP::Parse` and `Serialize`; line numbers below are that
	## file's), so a font reads exactly when a browser accepts its map. OTS
	## checks every subtable it can pass on, not only the one a shaper
	## chooses:
	##
	## - the header (version 0, lines 570-582) and every encoding record:
	##   each subtable offset past the records, inside the table and below
	##   1 GiB (603-611), each subtable's header readable (615-658), its
	##   stated length below 1 GiB and inside the table (679-691), and no two
	##   distinct subtables overlapping (694-719; subtables sharing exactly
	##   the same bytes are allowed);
	## - with `maxp`'s glyph count, the subtables OTS passes on (755-835):
	##   format 4 for platform 0 encodings 0, 1 and 3 and platform 3
	##   encodings 0 and 1 (`check_format4`), format 12 for platform 0
	##   encodings 3 and 4 and platform 3 encoding 10 and format 13 for
	##   platform 3 encoding 10 (`check_groups`), format 14 for platform 0
	##   encoding 5 (`check_format14`) and format 0 for platform 1
	##   encoding 0 (`check_format0`). Other subtables are not checked;
	## - at least one of those format 4, 12 or 13 subtables (Serialize,
	##   lines 859-863); otherwise, and for a table with no subtables (580),
	##   there is no map to use (`NoUnicodeMapping`).
	##
	## Each format's checks follow OTS: format 4 and 12 and 13 glyph ids
	## must be below the glyph count (so a map never names a glyph the font
	## lacks), format 4's binary search fields must be exactly those the
	## segment count gives, and so on. A subtable OTS only warns about (an
	## odd final `idRangeOffset`, two final 0xFFFF segments, a format 0
	## language) is accepted, as OTS accepts it.
	##
	## Deliberate divergence: OTS refuses a format 4 subtable when the font
	## has no `OS/2` table (line 72); roc-font does not require `OS/2`.
	##
	## A problem gives the offset in the table of the header (0), of the
	## encoding record (a bad subtable offset), or of the subtable.
	check : List(U8), [Present(U64), Absent] -> Try({}, [Bad(U64), NoUnicodeMapping])
	check = |cmap, glyphs| {
		size = cmap.len()
		count = Bytes.u16(cmap, 2)
		# Lines 570-582: version 0 and at least one subtable.
		if !Bytes.fits(0, 4, size) or Bytes.u16(cmap, 0) != 0 {
			return Err(Bad(0))
		}
		if count == 0 {
			return Err(NoUnicodeMapping)
		}
		# Lines 588-598: the encoding records.
		if !Bytes.fits(4, 8 * count, size) {
			return Err(Bad(0))
		}
		data_start = 4 + 8 * count
		gib = 1024 * 1024 * 1024
		# Lines 603-611: every offset past the records and inside the table.
		for i in 0..<count {
			offset = Bytes.u32(cmap, 4 + 8 * i + 4)
			if offset > gib or offset < data_start or offset >= size {
				return Err(Bad(4 + 8 * i))
			}
		}
		# Lines 615-658 and 679-691: each subtable's header readable, and
		# its stated length (0 for formats OTS does not pass on) below 1 GiB
		# and inside the table.
		#
		# Lines 694-719: OTS sweeps the start and end of every distinct
		# (offset, end) pair, ends before starts at one position, and refuses
		# more than one subtable open at once: two distinct non-empty spans
		# that share a byte. Spans are keyed `offset * 2^32 + end` (both
		# below 2^32). Records usually list subtables in increasing order,
		# which needs one pass and no allocation; otherwise a few records
		# (64 or fewer) are compared pairwise, and more are sorted without
		# repeats first.
		var $in_order = True
		var $previous = 0
		var $open_until = 0
		for i in 0..<count {
			offset = Bytes.u32(cmap, 4 + 8 * i + 4)
			length = TableCmap.stated_length(cmap, offset)?
			key = offset * 0x100000000 + offset + length
			if key < $previous {
				$in_order = False
			} else if $in_order and key != $previous and length != 0 {
				if offset < $open_until {
					return Err(Bad(offset))
				}
				$open_until = $open_until.max(offset + length)
			}
			$previous = $previous.max(key)
		}
		if !$in_order and count <= 64 {
			# A few records: compare every pair, without allocating.
			for i in 0..<count {
				a = Bytes.u32(cmap, 4 + 8 * i + 4)
				a_end = a + (TableCmap.stated_length(cmap, a) ?? 0)
				for j in (i + 1)..<count {
					b = Bytes.u32(cmap, 4 + 8 * j + 4)
					b_end = b + (TableCmap.stated_length(cmap, b) ?? 0)
					distinct = a != b or a_end != b_end
					if distinct and a < a_end and b < b_end and a < b_end and b < a_end {
						return Err(Bad(a.max(b)))
					}
				}
			}
		} else if !$in_order {
			var $spans = List.with_capacity(count)
			for i in 0..<count {
				offset = Bytes.u32(cmap, 4 + 8 * i + 4)
				$spans = $spans.append(offset * 0x100000000 + offset + (TableCmap.stated_length(cmap, offset) ?? 0))
			}
			var $until = 0
			for span in Sorted.unique($spans) {
				start = span // 0x100000000
				end = span % 0x100000000
				if end > start {
					if start < $until {
						return Err(Bad(start))
					}
					$until = $until.max(end)
				}
			}
		}
		match glyphs {
			Absent => Ok({})
			Present(glyph_count) => {
				# Lines 755-835: the subtables OTS passes on.
				var $usable = False
				for i in 0..<count {
					rec = 4 + 8 * i
					system = Bytes.u16(cmap, rec)
					encoding = Bytes.u16(cmap, rec + 2)
					offset = Bytes.u32(cmap, rec + 4)
					format = Bytes.u16(cmap, offset)
					data = cmap.sublist({ start: offset, len: TableCmap.stated_length(cmap, offset) ?? 0 })
					checked =
						if format == 4 and ((system == 0 and (encoding <= 1 or encoding == 3)) or (system == 3 and encoding <= 1)) {
							$usable = True
							TableCmap.check_format4(data, glyph_count)
						} else if format == 12 and ((system == 0 and (encoding == 3 or encoding == 4)) or (system == 3 and encoding == 10)) {
							$usable = True
							TableCmap.check_groups(data, glyph_count, False)
						} else if format == 13 and system == 3 and encoding == 10 {
							$usable = True
							TableCmap.check_groups(data, glyph_count, True)
						} else if format == 14 and system == 0 and encoding == 5 {
							TableCmap.check_format14(data)
						} else if format == 0 and system == 1 and encoding == 0 {
							TableCmap.check_format0(data)
						} else {
							Ok({})
						}
					if checked.is_err() {
						return Err(Bad(offset))
					}
				}
				# Serialize, lines 859-863: a map OTS can pass on.
				if ($usable) Ok({}) else Err(NoUnicodeMapping)
			}
		}
	}

	# The length a subtable states (cmap.cc lines 615-691): 0 for formats
	# OTS does not pass on; refused when its header does not fit, or when
	# it is 1 GiB or more or runs past the table.
	stated_length : List(U8), U64 -> Try(U64, [Bad(U64)])
	stated_length = |cmap, offset| {
		size = cmap.len()
		format = Bytes.u16(cmap, offset)
		header = if (format == 0 or format == 4 or format == 14) 6 else if (format == 12 or format == 13) 12 else 2
		if !Bytes.fits(offset, header, size) {
			return Err(Bad(offset))
		}
		length =
			if format == 0 or format == 4 {
				Bytes.u16(cmap, offset + 2)
			} else if format == 12 or format == 13 {
				Bytes.u32(cmap, offset + 4)
			} else if format == 14 {
				Bytes.u32(cmap, offset + 2)
			} else {
				0
			}
		if (length != 0 and (length > 1024 * 1024 * 1024 or offset + length > size)) Err(Bad(offset)) else Ok(length)
	}

	# A format 4 subtable as OTS checks it (`ParseFormat4`, cmap.cc lines
	# 62-265). `data` holds the subtable's stated length.
	check_format4 : List(U8), U64 -> Try({}, [Bad])
	check_format4 = |data, glyph_count| {
		length = data.len()
		# Lines 76-95: the header; the language must be 0.
		if length < 14 or Bytes.u16(data, 4) != 0 {
			return Err(Bad)
		}
		count_x2 = Bytes.u16(data, 6)
		search_range = Bytes.u16(data, 8)
		entry_selector = Bytes.u16(data, 10)
		range_shift = Bytes.u16(data, 12)
		# Lines 97-104: an even segment count of at least one.
		if count_x2 % 2 != 0 or search_range % 2 != 0 or count_x2 < 2 {
			return Err(Bad)
		}
		count = count_x2 // 2
		# Lines 106-124: the binary search fields exactly as the segment
		# count gives them (`log` is the largest x with 2^x <= count).
		var $log = 0
		while (2.U64).shl_wrap($log.to_u8_wrap()) <= count {
			$log = $log + 1
		}
		if search_range != (2.U64).shl_wrap($log.to_u8_wrap()) or entry_selector != $log or range_shift != (count_x2 + 65536 - search_range) % 65536 {
			return Err(Bad)
		}
		# Lines 126-171: end codes, a zero pad, start codes, deltas and
		# range offsets inside the subtable.
		ends = 14
		starts = 16 + 2 * count
		deltas = 16 + 4 * count
		range_offsets = 16 + 6 * count
		if !Bytes.fits(0, 16 + 8 * count, length) or Bytes.u16(data, 14 + 2 * count) != 0 {
			return Err(Bad)
		}
		# An odd range offset is refused except on the last segment, where
		# OTS takes it as 0 (lines 158-170).
		range_offset_of = |s| {
			raw = Bytes.u16(data, range_offsets + 2 * s)
			if (raw % 2 == 1 and s == count - 1) 0 else raw
		}
		for s in 0..<count {
			if range_offset_of(s) % 2 == 1 {
				return Err(Bad)
			}
		}
		# Lines 173-208: end codes increasing, each start past the previous
		# end; two final 0xFFFF segments are allowed.
		for s in 1..<count {
			last = Bytes.u16(data, ends + 2 * s)
			first = Bytes.u16(data, starts + 2 * s)
			previous_last = Bytes.u16(data, ends + 2 * (s - 1))
			previous_first = Bytes.u16(data, starts + 2 * (s - 1))
			terminators = s == count - 1 and previous_first == 0xFFFF and previous_last == 0xFFFF and first == 0xFFFF and last == 0xFFFF
			if !terminators and (last <= previous_last or first <= previous_last) {
				return Err(Bad)
			}
		}
		# Lines 210-214: the last segment is 0xFFFF alone.
		if Bytes.u16(data, starts + 2 * (count - 1)) != 0xFFFF or Bytes.u16(data, ends + 2 * (count - 1)) != 0xFFFF {
			return Err(Bad)
		}
		# Lines 216-247: every character of every segment maps to a glyph
		# below the glyph count, through entries inside the subtable. Glyph
		# array entries are checked as stored (OTS does not add the delta).
		# Segments do not overlap, so this visits at most 65537 characters.
		for s in 0..<count {
			first = Bytes.u16(data, starts + 2 * s)
			last = Bytes.u16(data, ends + 2 * s)
			range_offset = range_offset_of(s)
			if first <= last {
				if range_offset == 0 {
					# The glyphs run up from `(first + delta) mod 65536`; one
					# past 65535 wraps through 65535, which is never below the
					# glyph count.
					lowest = (first + Bytes.u16(data, deltas + 2 * s)) % 65536
					if lowest + (last - first) >= glyph_count {
						return Err(Bad)
					}
				} else {
					at = range_offsets + 2 * s + range_offset
					for c in first..<(last + 1) {
						entry = at + 2 * (c - first)
						if entry + 1 >= length or Bytes.u16(data, entry) >= glyph_count {
							return Err(Bad)
						}
					}
				}
			}
		}
		Ok({})
	}

	# A format 12 or 13 subtable as OTS checks it (`Parse31012` and
	# `Parse31013`, cmap.cc lines 267-401). `data` holds the subtable's
	# stated length.
	check_groups : List(U8), U64, Bool -> Try({}, [Bad])
	check_groups = |data, glyph_count, same| {
		length = data.len()
		count = Bytes.u32(data, 12)
		# Lines 274-290: language 0, and at least one group, all inside.
		if length < 16 or Bytes.u32(data, 8) != 0 or count == 0 or (length - 16) // 12 < count {
			return Err(Bad)
		}
		for i in 0..<count {
			g = 16 + 12 * i
			first = Bytes.u32(data, g)
			last = Bytes.u32(data, g + 4)
			drawn = Bytes.u32(data, g + 8)
			# Lines 304-309 and 379-383: within Unicode and 16-bit glyph ids.
			if first > 0x10FFFF or last > 0x10FFFF or drawn > 0xFFFF {
				return Err(Bad)
			}
			if same {
				# Lines 385-387: the one glyph below the glyph count. OTS
				# does not require `first <= last` here.
				if drawn >= glyph_count {
					return Err(Bad)
				}
			} else if last < first or (last - first) + drawn >= glyph_count {
				# Lines 313-320: ordered, and every glyph below the count.
				return Err(Bad)
			}
			# Lines 324-333 and 391-398: starts increasing, each past the
			# previous group's end.
			if i > 0 {
				previous = g - 12
				if first <= Bytes.u32(data, previous) or first <= Bytes.u32(data, previous + 4) {
					return Err(Bad)
				}
			}
		}
		Ok({})
	}

	# A format 14 subtable as OTS checks it (`Parse0514`, cmap.cc lines
	# 403-537). `data` holds the subtable's stated length.
	check_format14 : List(U8) -> Try({}, [Bad])
	check_format14 = |data| {
		length = data.len()
		count = Bytes.u32(data, 6)
		# Lines 411-421: 1 to 259 records (one per variation selector).
		if length < 10 or count == 0 or count > 259 or !Bytes.fits(10, 11 * count, length) {
			return Err(Bad)
		}
		for i in 0..<count {
			rec = 10 + 11 * i
			selector = Bytes.u16(data, rec) * 256 + Bytes.u8(data, rec + 2)
			default_at = Bytes.u32(data, rec + 3)
			mapping_at = Bytes.u32(data, rec + 7)
			# Lines 433-445: a variation selector, increasing.
			valid = (selector >= 0x180B and selector <= 0x180D) or (selector >= 0xFE00 and selector <= 0xFE0F) or (selector >= 0xE0100 and selector <= 0xE01EF)
			if !valid or (i > 0 and Bytes.u16(data, rec - 11) * 256 + Bytes.u8(data, rec - 9) >= selector) {
				return Err(Bad)
			}
			# Lines 447-458: at least one table, each starting inside.
			if (default_at == 0 and mapping_at == 0) or (default_at != 0 and default_at >= length) or (mapping_at != 0 and mapping_at >= length) {
				return Err(Bad)
			}
		}
		# Lines 461-530: each table, ending where the next is read.
		var $end = 10 + 11 * count
		for i in 0..<count {
			rec = 10 + 11 * i
			default_at = Bytes.u32(data, rec + 3)
			mapping_at = Bytes.u32(data, rec + 7)
			if default_at != 0 {
				n = Bytes.u32(data, default_at)
				# Lines 465-471: 1 or more ranges, all inside.
				if !Bytes.fits(default_at, 4, length) or n == 0 or (length - default_at - 4) // 4 < n {
					return Err(Bad)
				}
				# Lines 478-493: a start in Unicode (not 0), the range below
				# 2^24, and each start past the previous range's end.
				var $last = 0
				for k in 0..<n {
					r = default_at + 4 + 4 * k
					value = Bytes.u16(data, r) * 256 + Bytes.u8(data, r + 2)
					ends = value + Bytes.u8(data, r + 3)
					if value == 0 or value > 0x10FFFF or ends > 0xFFFFFF or ($last != 0 and value <= $last) {
						return Err(Bad)
					}
					$last = ends
				}
				$end = default_at + 4 + 4 * n
			}
			if mapping_at != 0 {
				n = Bytes.u32(data, mapping_at)
				# Lines 499-505: 1 or more mappings, all inside.
				if !Bytes.fits(mapping_at, 4, length) or n == 0 or (length - mapping_at - 4) // 5 < n {
					return Err(Bad)
				}
				# Lines 512-528: a character in Unicode (not 0), a glyph
				# other than 0, characters increasing.
				var $last = 0
				for k in 0..<n {
					m = mapping_at + 4 + 5 * k
					value = Bytes.u16(data, m) * 256 + Bytes.u8(data, m + 2)
					if Bytes.u16(data, m + 3) == 0 or value == 0 or value > 0x10FFFF or ($last != 0 and value <= $last) {
						return Err(Bad)
					}
					$last = value
				}
				$end = mapping_at + 4 + 5 * n
			}
		}
		# Lines 532-534: the last table read ends the subtable exactly.
		if ($end != length) Err(Bad) else Ok({})
	}

	# A format 0 subtable (platform 1, encoding 0) as OTS checks it
	# (`Parse100`, cmap.cc lines 539-565): 256 glyph ids inside its stated
	# length. OTS only warns about a language other than 0, and does not
	# compare these glyph ids with the glyph count.
	check_format0 : List(U8) -> Try({}, [Bad])
	check_format0 = |data| if (data.len() < 6 + 256) Err(Bad) else Ok({})

	## Choose and check a subtable of a `cmap` table. `font_page` is the
	## `OS/2` table's Windows 3.1 font page (0 for none).
	## A bad table gives the offset (in the table) of the header or of the
	## chosen subtable.
	read : List(U8), U64 -> Try(TableCmap, [Bad(U64), NoUnicodeMapping])
	read = |cmap, font_page| {
		count = Bytes.u16(cmap, 2)
		if !Bytes.fits(0, 4, cmap.len()) or !Bytes.fits(4, 8 * count, cmap.len()) {
			Err(Bad(0))
		} else {
			var $best = { rank: TableCmap.unranked, offset: 0, format: 0 }
			for i in 0..<count {
				at = 4 + 8 * i
				rank = TableCmap.rank(Bytes.u16(cmap, at), Bytes.u16(cmap, at + 2))
				offset = Bytes.u32(cmap, at + 4)
				# An offset outside the table is kept as a candidate, so a
				# broken subtable that would be chosen is reported.
				format = if (Bytes.fits(offset, 2, cmap.len())) Bytes.u16(cmap, offset) else TableCmap.outside
				usable = format == TableCmap.outside or format == 0 or format == 4 or format == 6 or format == 10 or format == 12 or format == 13
				if usable and rank < $best.rank {
					$best = { rank, offset, format }
				}
			}
			best = $best
			if best.rank == TableCmap.unranked {
				Err(NoUnicodeMapping)
			} else {
				data = Bytes.rest(cmap, best.offset)
				subtable = TableCmap.read_subtable(data, best.format).map_err(|_| Bad(best.offset))?
				remap =
					if best.rank == 0 {
						if font_page == 0 {
							Symbol
						} else if font_page == 0xB200 {
							ArabicSimplified
						} else if font_page == 0xB300 {
							ArabicTraditional
						} else {
							Unicode
						}
					} else if best.rank == 9 {
						MacRoman
					} else if best.rank == 10 {
						MacAscii
					} else {
						Unicode
					}
				variants = TableCmap.read_variants(cmap)?
				Ok({ ranges: TableCmap.resolve(subtable.ranges, subtable.same, remap), same: subtable.same, variants })
			}
		}
	}

	# The ranges of a map that does not use Unicode, translated to Unicode
	# when reading, so a lookup is one search whatever the encoding (see the
	# module doc). Characters added this way are single-character ranges,
	# which mean the same whether or not the map's ranges share one glyph.
	resolve : List({ first : U32, last : U32, glyph : U32 }), Bool, [Unicode, Symbol, MacRoman, MacAscii, ArabicSimplified, ArabicTraditional] -> List({ first : U32, last : U32, glyph : U32 })
	resolve = |ranges, same, remap|
		match remap {
			Unicode => ranges
			Symbol => TableCmap.merge(ranges, TableCmap.fallbacks(ranges, same, TableCmap.counting(0x100), TableCmap.counting(0x100).map(|c| c + 0xF000)))
			ArabicSimplified => TableCmap.merge(ranges, TableCmap.fallbacks(ranges, same, TableCmap.arabic_simplified_from.map(|c| c.to_u64()), TableCmap.arabic_simplified_to.map(|c| c.to_u64())))
			ArabicTraditional => TableCmap.merge(ranges, TableCmap.fallbacks(ranges, same, TableCmap.arabic_traditional_from.map(|c| c.to_u64()), TableCmap.arabic_traditional_to.map(|c| c.to_u64())))
			MacAscii => TableCmap.ascii(ranges)
			MacRoman => {
				# Mac Roman codes from 0x80 are characters past ASCII; the
				# translation table is in Unicode order, all after ASCII.
				var $out = TableCmap.ascii(ranges)
				for k in 0..<TableCmap.mac_roman_from.len() {
					g = TableCmap.range_glyph(ranges, same, (TableCmap.mac_roman_to.get(k) ?? 0).to_u64())
					if g != 0 {
						u = (TableCmap.mac_roman_from.get(k) ?? 0).to_u32()
						$out = $out.append({ first: u, last: u, glyph: g.to_u32_wrap() })
					}
				}
				$out
			}
		}

	counting : U64 -> List(U64)
	counting = |n| {
		var $out = List.with_capacity(n)
		for i in 0..<n {
			$out = $out.append(i)
		}
		$out
	}

	# For each code in `codes` (increasing) that the map does not have, the
	# glyph of the code at the same index of `others`, when it has that.
	fallbacks : List({ first : U32, last : U32, glyph : U32 }), Bool, List(U64), List(U64) -> List({ first : U32, last : U32, glyph : U32 })
	fallbacks = |ranges, same, codes, others| {
		var $out = []
		for k in 0..<codes.len() {
			c = codes.get(k) ?? 0
			if TableCmap.range_glyph(ranges, same, c) == 0 {
				g = TableCmap.range_glyph(ranges, same, others.get(k) ?? TableCmap.no_code)
				if g != 0 {
					$out = $out.append({ first: c.to_u32_wrap(), last: c.to_u32_wrap(), glyph: g.to_u32_wrap() })
				}
			}
		}
		$out
	}

	# Two sorted lists of ranges, no code in both, as one sorted list.
	merge : List({ first : U32, last : U32, glyph : U32 }), List({ first : U32, last : U32, glyph : U32 }) -> List({ first : U32, last : U32, glyph : U32 })
	merge = |a, b|
		if b.is_empty() {
			a
		} else {
			var $out = List.with_capacity(a.len() + b.len())
			var $i = 0
			var $j = 0
			while $i < a.len() or $j < b.len() {
				x = a.get($i) ?? { first: 0xFFFFFFFF, last: 0, glyph: 0 }
				y = b.get($j) ?? { first: 0xFFFFFFFF, last: 0, glyph: 0 }
				if x.first <= y.first {
					$out = $out.append(x)
					$i = $i + 1
				} else {
					$out = $out.append(y)
					$j = $j + 1
				}
			}
			$out
		}

	# The ranges' ASCII characters.
	ascii : List({ first : U32, last : U32, glyph : U32 }) -> List({ first : U32, last : U32, glyph : U32 })
	ascii = |ranges| {
		var $out = []
		for range in ranges {
			if range.first <= 0x7F {
				$out = $out.append({ first: range.first, last: range.last.min(0x7F), glyph: range.glyph })
			}
		}
		$out
	}

	no_code : U64
	no_code = 0x110000

	unranked : U64
	unranked = 99

	outside : U64
	outside = 0x10000

	# HarfBuzz's preference among (platform, encoding) pairs, lowest first.
	rank : U64, U64 -> U64
	rank = |system, encoding|
		if system == 3 {
			if encoding == 0 {
				0
			} else if encoding == 10 {
				1
			} else if encoding == 1 {
				4
			} else {
				TableCmap.unranked
			}
		} else if system == 0 {
			if encoding == 6 {
				2
			} else if encoding == 4 {
				3
			} else if encoding <= 3 {
				8 - encoding
			} else {
				TableCmap.unranked
			}
		} else if system == 1 {
			if (encoding == 0) 9 else 10
		} else {
			TableCmap.unranked
		}

	# Check a subtable's fields and list its ranges. `data` runs from the
	# subtable's start to the end of the `cmap` table (the length fields of
	# real fonts are not reliable).
	read_subtable : List(U8), U64 -> Try({ ranges : List({ first : U32, last : U32, glyph : U32 }), same : Bool }, [Bad])
	read_subtable = |data, format| {
		size = data.len()
		if format == 0 {
			if (Bytes.fits(0, 6 + 256, size)) Ok({ ranges: TableCmap.array_runs(data, 6, 1, 0, 256), same: False }) else Err(Bad)
		} else if format == 4 {
			ranges = TableCmap.read_segments(data)?
			Ok({ ranges, same: False })
		} else if format == 6 {
			count = Bytes.u16(data, 8)
			if (Bytes.fits(0, 10, size) and Bytes.fits(10, 2 * count, size)) Ok({ ranges: TableCmap.array_runs(data, 10, 2, Bytes.u16(data, 6), count), same: False }) else Err(Bad)
		} else if format == 10 {
			count = Bytes.u32(data, 16)
			first = Bytes.u32(data, 12)
			# Like format 12 groups, the codes must lie within Unicode's range.
			if Bytes.fits(0, 20, size) and Bytes.fits(20, 2 * count, size) and first + count <= 0x110000 {
				Ok({ ranges: TableCmap.array_runs(data, 20, 2, first, count), same: False })
			} else {
				Err(Bad)
			}
		} else if format == 12 or format == 13 {
			ranges = TableCmap.read_groups(data, format == 13)?
			Ok({ ranges, same: format == 13 })
		} else {
			Err(Bad)
		}
	}

	# Formats 0, 6 and 10: `count` glyph ids of `width` bytes from `at`, for
	# consecutive codes from `first`, as runs; glyph 0 maps nothing.
	array_runs : List(U8), U64, U64, U64, U64 -> List({ first : U32, last : U32, glyph : U32 })
	array_runs = |data, at, width, first, count| {
		var $runs = []
		var $open = TableCmap.closed
		for i in 0..<count {
			g = if (width == 1) Bytes.u8(data, at + i) else Bytes.u16(data, at + 2 * i)
			if g != 0 {
				step = TableCmap.extend($open, first + i, first + i, g)
				$open = step.open
				$runs = TableCmap.push($runs, step.done)
			}
		}
		TableCmap.push($runs, Done($open))
	}

	# Format 4: segments in increasing order without overlaps, and every
	# glyph array entry a segment uses inside the table. The result is runs
	# of consecutive characters drawn by consecutive glyphs, in character
	# order, leaving out U+FFFF (the format's required last segment) and
	# characters drawn by glyph 0. A segment mapped by a delta alone becomes
	# at most two runs, because its glyphs wrap to 0 at most once; a segment
	# mapped through the glyph array is read entry by entry.
	read_segments : List(U8) -> Try(List({ first : U32, last : U32, glyph : U32 }), [Bad])
	read_segments = |data| {
		size = data.len()
		count = Bytes.u16(data, 6) // 2
		ends = 14
		starts = ends + 2 * count + 2
		deltas = starts + 2 * count
		range_offsets = deltas + 2 * count
		if !Bytes.fits(0, 14, size) or !Bytes.fits(ends, 8 * count + 2, size) {
			Err(Bad)
		} else {
			var $bad = False
			var $previous_first = 0
			var $previous_end = 0
			var $runs = List.with_capacity(count)
			var $open = TableCmap.closed
			for s in 0..<count {
				last = Bytes.u16(data, ends + 2 * s)
				first = Bytes.u16(data, starts + 2 * s)
				delta = Bytes.u16(data, deltas + 2 * s)
				range_offset = Bytes.u16(data, range_offsets + 2 * s)
				# U+FFFF is never mapped.
				top = if (last == 0xFFFF) last - 1 else last
				# The order OTS requires (cmap.cc lines 173-194): end codes
				# increasing, each start past the previous end, except for two
				# final 0xFFFF segments. A segment whose start is past its end
				# maps nothing, as OTS allows.
				terminators = s > 0 and s == count - 1 and $previous_first == 0xFFFF and $previous_end == 0xFFFF and first == 0xFFFF and last == 0xFFFF
				if s > 0 and !terminators and (last <= $previous_end or first <= $previous_end) {
					$bad = True
				} else if first > top {
					{}
				} else if range_offset == 0 {
					start = (first + delta) % 65536
					# The character whose glyph wraps to 0.
					wrap = if (start == 0) first else first + 65536 - start
					if wrap > first {
						step = TableCmap.extend($open, first, top.min(wrap - 1), start)
						$open = step.open
						$runs = TableCmap.push($runs, step.done)
					}
					if wrap < top {
						step = TableCmap.extend($open, wrap + 1, top, 1)
						$open = step.open
						$runs = TableCmap.push($runs, step.done)
					}
				} else {
					# Entries are consecutive, so checking the last one is enough.
					entries = range_offsets + 2 * s + range_offset
					if !Bytes.fits(entries + 2 * (top - first), 2, size) {
						$bad = True
					} else {
						for c in first..<(top + 1) {
							raw = Bytes.u16(data, entries + 2 * (c - first))
							if raw != 0 and (raw + delta) % 65536 != 0 {
								step = TableCmap.extend($open, c, c, (raw + delta) % 65536)
								$open = step.open
								$runs = TableCmap.push($runs, step.done)
							}
						}
					}
				}
				$previous_first = first
				$previous_end = last
			}
			if ($bad) Err(Bad) else Ok(TableCmap.push($runs, Done($open)))
		}
	}

	# The run being built from format 4 segments; `last < first` while none
	# is open.
	closed : { first : U64, last : U64, glyph : U64 }
	closed = { first: 1, last: 0, glyph: 0 }

	# Add characters `first` up to `last`, drawn by glyphs from `glyph`, to
	# the open run, or close it (returned as done) and open a new one.
	extend : { first : U64, last : U64, glyph : U64 }, U64, U64, U64 -> { open : { first : U64, last : U64, glyph : U64 }, done : [Done({ first : U64, last : U64, glyph : U64 }), NotDone] }
	extend = |open, first, last, drawn|
		if open.first <= open.last and open.last + 1 == first and open.glyph + (open.last - open.first) + 1 == drawn {
			{ open: { first: open.first, last, glyph: open.glyph }, done: NotDone }
		} else {
			{ open: { first, last, glyph: drawn }, done: Done(open) }
		}

	push : List({ first : U32, last : U32, glyph : U32 }), [Done({ first : U64, last : U64, glyph : U64 }), NotDone] -> List({ first : U32, last : U32, glyph : U32 })
	push = |runs, done|
		match done {
			Done(run) if run.first <= run.last => runs.append({ first: run.first.to_u32_wrap(), last: run.last.to_u32_wrap(), glyph: run.glyph.to_u32_wrap() })
			_ => runs
		}

	# Formats 12 and 13: groups in increasing order without overlaps, within
	# Unicode's range, kept as ranges (one allocation, sized by the checked
	# group count).
	read_groups : List(U8), Bool -> Try(List({ first : U32, last : U32, glyph : U32 }), [Bad])
	read_groups = |data, same| {
		count = Bytes.u32(data, 12)
		if !Bytes.fits(0, 16, data.len()) or !Bytes.fits(16, 12 * count, data.len()) {
			Err(Bad)
		} else {
			var $bad = False
			var $previous_first = 0
			var $previous = 0
			var $ranges = List.with_capacity(count)
			for i in 0..<count {
				g = 16 + 12 * i
				first = Bytes.u32(data, g)
				last = Bytes.u32(data, g + 4)
				# The order OTS requires (cmap.cc lines 304-333 and 379-398):
				# starts increasing, each past the previous group's end. A
				# format 13 group whose start is past its end maps nothing, as
				# OTS allows.
				if (!same and last < first) or (i > 0 and (first <= $previous_first or first <= $previous)) or first > 0x10FFFF or last > 0x10FFFF {
					$bad = True
				}
				start = Bytes.u32(data, g + 8)
				# Glyph 0 maps nothing: a format 12 group starting at it
				# starts one character later at glyph 1; a format 13 group
				# drawn by it is left out. No range then holds a character
				# that maps nothing.
				if first > last {
					{}
				} else if start != 0 {
					$ranges = $ranges.append({ first: first.to_u32_wrap(), last: last.to_u32_wrap(), glyph: start.to_u32_wrap() })
				} else if !same and first < last {
					$ranges = $ranges.append({ first: (first + 1).to_u32_wrap(), last: last.to_u32_wrap(), glyph: 1 })
				}
				$previous_first = first
				$previous = last
			}
			if ($bad) Err(Bad) else Ok($ranges)
		}
	}

	# ------------------------------------------------------------ encodings

	# Unicode to Mac OS Roman for the characters past ASCII, from HarfBuzz.
	mac_roman_from : List(U16)
	mac_roman_from = [0x00A0, 0x00A1, 0x00A2, 0x00A3, 0x00A5, 0x00A7, 0x00A8, 0x00A9, 0x00AA, 0x00AB, 0x00AC, 0x00AE, 0x00AF, 0x00B0, 0x00B1, 0x00B4, 0x00B5, 0x00B6, 0x00B7, 0x00B8, 0x00BA, 0x00BB, 0x00BF, 0x00C0, 0x00C1, 0x00C2, 0x00C3, 0x00C4, 0x00C5, 0x00C6, 0x00C7, 0x00C8, 0x00C9, 0x00CA, 0x00CB, 0x00CC, 0x00CD, 0x00CE, 0x00CF, 0x00D1, 0x00D2, 0x00D3, 0x00D4, 0x00D5, 0x00D6, 0x00D8, 0x00D9, 0x00DA, 0x00DB, 0x00DC, 0x00DF, 0x00E0, 0x00E1, 0x00E2, 0x00E3, 0x00E4, 0x00E5, 0x00E6, 0x00E7, 0x00E8, 0x00E9, 0x00EA, 0x00EB, 0x00EC, 0x00ED, 0x00EE, 0x00EF, 0x00F1, 0x00F2, 0x00F3, 0x00F4, 0x00F5, 0x00F6, 0x00F7, 0x00F8, 0x00F9, 0x00FA, 0x00FB, 0x00FC, 0x00FF, 0x0131, 0x0152, 0x0153, 0x0178, 0x0192, 0x02C6, 0x02C7, 0x02D8, 0x02D9, 0x02DA, 0x02DB, 0x02DC, 0x02DD, 0x03A9, 0x03C0, 0x2013, 0x2014, 0x2018, 0x2019, 0x201A, 0x201C, 0x201D, 0x201E, 0x2020, 0x2021, 0x2022, 0x2026, 0x2030, 0x2039, 0x203A, 0x2044, 0x20AC, 0x2122, 0x2202, 0x2206, 0x220F, 0x2211, 0x221A, 0x221E, 0x222B, 0x2248, 0x2260, 0x2264, 0x2265, 0x25CA, 0xF8FF, 0xFB01, 0xFB02]

	mac_roman_to : List(U16)
	mac_roman_to = [0xCA, 0xC1, 0xA2, 0xA3, 0xB4, 0xA4, 0xAC, 0xA9, 0xBB, 0xC7, 0xC2, 0xA8, 0xF8, 0xA1, 0xB1, 0xAB, 0xB5, 0xA6, 0xE1, 0xFC, 0xBC, 0xC8, 0xC0, 0xCB, 0xE7, 0xE5, 0xCC, 0x80, 0x81, 0xAE, 0x82, 0xE9, 0x83, 0xE6, 0xE8, 0xED, 0xEA, 0xEB, 0xEC, 0x84, 0xF1, 0xEE, 0xEF, 0xCD, 0x85, 0xAF, 0xF4, 0xF2, 0xF3, 0x86, 0xA7, 0x88, 0x87, 0x89, 0x8B, 0x8A, 0x8C, 0xBE, 0x8D, 0x8F, 0x8E, 0x90, 0x91, 0x93, 0x92, 0x94, 0x95, 0x96, 0x98, 0x97, 0x99, 0x9B, 0x9A, 0xD6, 0xBF, 0x9D, 0x9C, 0x9E, 0x9F, 0xD8, 0xF5, 0xCE, 0xCF, 0xD9, 0xC4, 0xF6, 0xFF, 0xF9, 0xFA, 0xFB, 0xFE, 0xF7, 0xFD, 0xBD, 0xB9, 0xD0, 0xD1, 0xD4, 0xD5, 0xE2, 0xD2, 0xD3, 0xE3, 0xA0, 0xE0, 0xA5, 0xC9, 0xE4, 0xDC, 0xDD, 0xDA, 0xDB, 0xAA, 0xB6, 0xC6, 0xB8, 0xB7, 0xC3, 0xB0, 0xBA, 0xC5, 0xAD, 0xB2, 0xB3, 0xD7, 0xF0, 0xDE, 0xDF]

	# Arabic text to the private use code points of Windows 3.1 simplified
	# and traditional Arabic font pages, from HarfBuzz's tables.
	arabic_simplified_from : List(U16)
	arabic_simplified_from = [0x0020, 0x0021, 0x0022, 0x0025, 0x0028, 0x0029, 0x002A, 0x002B, 0x002C, 0x002D, 0x002E, 0x002F, 0x0030, 0x0031, 0x0032, 0x0033, 0x0034, 0x0035, 0x0036, 0x0037, 0x0038, 0x0039, 0x003A, 0x003B, 0x003D, 0x003F, 0x005B, 0x005C, 0x005D, 0x00AB, 0x00BB, 0x00D7, 0x00F7, 0x060C, 0x061B, 0x061F, 0x0621, 0x0622, 0x0623, 0x0624, 0x0625, 0x0626, 0x0627, 0x0628, 0x0629, 0x062A, 0x062B, 0x062C, 0x062D, 0x062E, 0x062F, 0x0630, 0x0631, 0x0632, 0x0633, 0x0634, 0x0635, 0x0636, 0x0637, 0x0638, 0x0639, 0x063A, 0x063B, 0x063C, 0x063D, 0x063E, 0x063F, 0x0640, 0x0641, 0x0642, 0x0643, 0x0644, 0x0645, 0x0646, 0x0647, 0x0648, 0x0649, 0x064A, 0x064B, 0x064C, 0x064D, 0x064E, 0x064F, 0x0650, 0x0651, 0x0652, 0x0653, 0x0654, 0x0655, 0x0656, 0x0657, 0x0658, 0x0659, 0x065A, 0x065B, 0x065C, 0x065D, 0x065E, 0x0660, 0x0661, 0x0662, 0x0663, 0x0664, 0x0665, 0x0666, 0x0667, 0x0668, 0x0669, 0x066B, 0x066C, 0x200C, 0x200D, 0x200E, 0x200F, 0x2018, 0x2019, 0xFE81, 0xFE82, 0xFE83, 0xFE84, 0xFE85, 0xFE86, 0xFE87, 0xFE88, 0xFE89, 0xFE8A, 0xFE8B, 0xFE8C, 0xFE8D, 0xFE8E, 0xFE8F, 0xFE90, 0xFE91, 0xFE92, 0xFE93, 0xFE94, 0xFE95, 0xFE96, 0xFE97, 0xFE98, 0xFE99, 0xFE9A, 0xFE9B, 0xFE9C, 0xFE9D, 0xFE9E, 0xFE9F, 0xFEA0, 0xFEA1, 0xFEA2, 0xFEA3, 0xFEA4, 0xFEA5, 0xFEA6, 0xFEA7, 0xFEA8, 0xFEA9, 0xFEAA, 0xFEAB, 0xFEAC, 0xFEAD, 0xFEAE, 0xFEAF, 0xFEB0, 0xFEB1, 0xFEB2, 0xFEB3, 0xFEB4, 0xFEB5, 0xFEB6, 0xFEB7, 0xFEB8, 0xFEB9, 0xFEBA, 0xFEBB, 0xFEBC, 0xFEBD, 0xFEBE, 0xFEBF, 0xFEC0, 0xFEC1, 0xFEC2, 0xFEC3, 0xFEC4, 0xFEC5, 0xFEC6, 0xFEC7, 0xFEC8, 0xFEC9, 0xFECA, 0xFECB, 0xFECC, 0xFECD, 0xFECE, 0xFECF, 0xFED0, 0xFED1, 0xFED2, 0xFED3, 0xFED4, 0xFED5, 0xFED6, 0xFED7, 0xFED8, 0xFED9, 0xFEDA, 0xFEDB, 0xFEDC, 0xFEDD, 0xFEDE, 0xFEDF, 0xFEE0, 0xFEE1, 0xFEE2, 0xFEE3, 0xFEE4, 0xFEE5, 0xFEE6, 0xFEE7, 0xFEE8, 0xFEE9, 0xFEEA, 0xFEEB, 0xFEEC, 0xFEED, 0xFEEE, 0xFEEF, 0xFEF0, 0xFEF1, 0xFEF2, 0xFEF3, 0xFEF4, 0xFEF5, 0xFEF6, 0xFEF7, 0xFEF8, 0xFEF9, 0xFEFA, 0xFEFB, 0xFEFC]

	arabic_simplified_to : List(U16)
	arabic_simplified_to = [0xF120, 0xF121, 0xF122, 0xF125, 0xF128, 0xF129, 0xF12A, 0xF12B, 0xF15E, 0xF12D, 0xF12E, 0xF12F, 0xF1B0, 0xF1B1, 0xF1B2, 0xF1B3, 0xF1B4, 0xF1B5, 0xF1B6, 0xF1B7, 0xF1B8, 0xF1B9, 0xF13A, 0xF13B, 0xF13D, 0xF13F, 0xF15B, 0xF15C, 0xF15D, 0xF123, 0xF124, 0xF126, 0xF127, 0xF12C, 0xF13B, 0xF13F, 0xF1AD, 0xF145, 0xF143, 0xF1BB, 0xF147, 0xF1BA, 0xF141, 0xF14A, 0xF1A9, 0xF14C, 0xF14E, 0xF151, 0xF154, 0xF157, 0xF158, 0xF159, 0xF15A, 0xF160, 0xF162, 0xF164, 0xF166, 0xF168, 0xF169, 0xF16A, 0xF16E, 0xF172, 0xF100, 0xF100, 0xF100, 0xF100, 0xF100, 0xF15F, 0xF175, 0xF178, 0xF17A, 0xF17C, 0xF17E, 0xF1E1, 0xF1A4, 0xF1A5, 0xF1AC, 0xF1A8, 0xF1C7, 0xF1C8, 0xF1CB, 0xF1C4, 0xF1C5, 0xF1CA, 0xF1C9, 0xF1C6, 0xF100, 0xF100, 0xF100, 0xF100, 0xF100, 0xF100, 0xF100, 0xF100, 0xF100, 0xF100, 0xF100, 0xF100, 0xF130, 0xF131, 0xF132, 0xF133, 0xF134, 0xF135, 0xF136, 0xF137, 0xF138, 0xF139, 0xF15E, 0xF15E, 0xF10C, 0xF10D, 0xF10E, 0xF10F, 0xF13C, 0xF13E, 0xF145, 0xF146, 0xF143, 0xF144, 0xF1BB, 0xF1BB, 0xF147, 0xF148, 0xF1BA, 0xF1AF, 0xF1AE, 0xF1AE, 0xF141, 0xF142, 0xF14A, 0xF14A, 0xF149, 0xF149, 0xF1A9, 0xF1AA, 0xF14C, 0xF14C, 0xF14B, 0xF14B, 0xF14E, 0xF14E, 0xF14D, 0xF14D, 0xF151, 0xF150, 0xF14F, 0xF14F, 0xF154, 0xF153, 0xF152, 0xF152, 0xF157, 0xF156, 0xF155, 0xF155, 0xF158, 0xF158, 0xF159, 0xF159, 0xF15A, 0xF15A, 0xF160, 0xF160, 0xF162, 0xF162, 0xF161, 0xF161, 0xF164, 0xF164, 0xF163, 0xF163, 0xF166, 0xF166, 0xF165, 0xF165, 0xF168, 0xF168, 0xF167, 0xF167, 0xF169, 0xF169, 0xF169, 0xF169, 0xF16A, 0xF16A, 0xF16A, 0xF16A, 0xF16E, 0xF16D, 0xF16B, 0xF16C, 0xF172, 0xF171, 0xF16F, 0xF170, 0xF175, 0xF175, 0xF173, 0xF174, 0xF178, 0xF178, 0xF176, 0xF177, 0xF17A, 0xF17A, 0xF179, 0xF179, 0xF17C, 0xF17C, 0xF17B, 0xF17B, 0xF17E, 0xF17E, 0xF17D, 0xF17D, 0xF1E1, 0xF1E1, 0xF17F, 0xF17F, 0xF1A4, 0xF1A3, 0xF1A1, 0xF1A2, 0xF1A5, 0xF1A5, 0xF1AC, 0xF1AB, 0xF1A8, 0xF1A7, 0xF1A6, 0xF1A6, 0xF1C0, 0xF1C1, 0xF1BE, 0xF1BF, 0xF1C2, 0xF1C3, 0xF1BD, 0xF1BC]

	arabic_traditional_from : List(U16)
	arabic_traditional_from = [0x0020, 0x0021, 0x0022, 0x0025, 0x0028, 0x0029, 0x002A, 0x002B, 0x002C, 0x002D, 0x002E, 0x002F, 0x003A, 0x003B, 0x003D, 0x003F, 0x005B, 0x005D, 0x00AB, 0x00BB, 0x00D7, 0x00F7, 0x060C, 0x061B, 0x061F, 0x0621, 0x0622, 0x0623, 0x0624, 0x0625, 0x0626, 0x0627, 0x0628, 0x0629, 0x062A, 0x062B, 0x062C, 0x062D, 0x062E, 0x062F, 0x0630, 0x0631, 0x0632, 0x0633, 0x0634, 0x0635, 0x0636, 0x0637, 0x0638, 0x0639, 0x063A, 0x063B, 0x063C, 0x063D, 0x063E, 0x063F, 0x0640, 0x0641, 0x0642, 0x0643, 0x0644, 0x0645, 0x0646, 0x0647, 0x0648, 0x0649, 0x064A, 0x064B, 0x064C, 0x064D, 0x064E, 0x064F, 0x0650, 0x0651, 0x0652, 0x0653, 0x0654, 0x0655, 0x0656, 0x0657, 0x0658, 0x0659, 0x065A, 0x065B, 0x065C, 0x065D, 0x065E, 0x0660, 0x0661, 0x0662, 0x0663, 0x0664, 0x0665, 0x0666, 0x0667, 0x0668, 0x0669, 0x066B, 0x066C, 0x200C, 0x200D, 0x200E, 0x200F, 0x201C, 0x201D, 0xFC08, 0xFC0A, 0xFC0E, 0xFC10, 0xFC12, 0xFC32, 0xFC3F, 0xFC40, 0xFC41, 0xFC42, 0xFC43, 0xFC44, 0xFC4E, 0xFC50, 0xFC5E, 0xFC60, 0xFC61, 0xFC62, 0xFC6A, 0xFC6D, 0xFC70, 0xFC73, 0xFC91, 0xFC94, 0xFC9C, 0xFC9D, 0xFC9E, 0xFC9F, 0xFCA1, 0xFCA2, 0xFCA3, 0xFCA4, 0xFCA8, 0xFCAA, 0xFCAC, 0xFCB0, 0xFCC9, 0xFCCA, 0xFCCB, 0xFCCC, 0xFCCD, 0xFCCE, 0xFCCF, 0xFCD0, 0xFCD1, 0xFCD2, 0xFCD3, 0xFCD5, 0xFCDA, 0xFCDB, 0xFCDC, 0xFCDD, 0xFD30, 0xFD3E, 0xFD3F, 0xFD88, 0xFE81, 0xFE82, 0xFE83, 0xFE84, 0xFE85, 0xFE86, 0xFE87, 0xFE88, 0xFE89, 0xFE8A, 0xFE8B, 0xFE8C, 0xFE8D, 0xFE8E, 0xFE8F, 0xFE90, 0xFE91, 0xFE92, 0xFE93, 0xFE94, 0xFE95, 0xFE96, 0xFE97, 0xFE98, 0xFE99, 0xFE9A, 0xFE9B, 0xFE9C, 0xFE9D, 0xFE9E, 0xFE9F, 0xFEA0, 0xFEA1, 0xFEA2, 0xFEA3, 0xFEA4, 0xFEA5, 0xFEA6, 0xFEA7, 0xFEA8, 0xFEA9, 0xFEAA, 0xFEAB, 0xFEAC, 0xFEAD, 0xFEAE, 0xFEAF, 0xFEB0, 0xFEB1, 0xFEB2, 0xFEB3, 0xFEB4, 0xFEB5, 0xFEB6, 0xFEB7, 0xFEB8, 0xFEB9, 0xFEBA, 0xFEBB, 0xFEBC, 0xFEBD, 0xFEBE, 0xFEBF, 0xFEC0, 0xFEC1, 0xFEC2, 0xFEC3, 0xFEC4, 0xFEC5, 0xFEC6, 0xFEC7, 0xFEC8, 0xFEC9, 0xFECA, 0xFECB, 0xFECC, 0xFECD, 0xFECE, 0xFECF, 0xFED0, 0xFED1, 0xFED2, 0xFED3, 0xFED4, 0xFED5, 0xFED6, 0xFED7, 0xFED8, 0xFED9, 0xFEDA, 0xFEDB, 0xFEDC, 0xFEDD, 0xFEDE, 0xFEDF, 0xFEE0, 0xFEE1, 0xFEE2, 0xFEE3, 0xFEE4, 0xFEE5, 0xFEE6, 0xFEE7, 0xFEE8, 0xFEE9, 0xFEEA, 0xFEEB, 0xFEEC, 0xFEED, 0xFEEE, 0xFEEF, 0xFEF0, 0xFEF1, 0xFEF2, 0xFEF3, 0xFEF4, 0xFEF5, 0xFEF6, 0xFEF7, 0xFEF8, 0xFEF9, 0xFEFA, 0xFEFB, 0xFEFC]

	arabic_traditional_to : List(U16)
	arabic_traditional_to = [0xF220, 0xF221, 0xF222, 0xF225, 0xF228, 0xF229, 0xF22A, 0xF22B, 0xF25E, 0xF22D, 0xF22E, 0xF22F, 0xF23A, 0xF23B, 0xF23D, 0xF23F, 0xF25B, 0xF25D, 0xF223, 0xF224, 0xF226, 0xF227, 0xF22C, 0xF23B, 0xF23F, 0xF2D5, 0xF245, 0xF243, 0xF2DA, 0xF247, 0xF2D9, 0xF241, 0xF24C, 0xF2D1, 0xF250, 0xF254, 0xF258, 0xF260, 0xF264, 0xF265, 0xF267, 0xF269, 0xF26B, 0xF270, 0xF274, 0xF278, 0xF27E, 0xF2A2, 0xF2A3, 0xF2AA, 0xF2AE, 0xF200, 0xF200, 0xF200, 0xF200, 0xF200, 0xF25F, 0xF2B2, 0xF2B6, 0xF2BA, 0xF2BE, 0xF2C2, 0xF2C6, 0xF2CA, 0xF2CB, 0xF2D4, 0xF2D0, 0xF2E7, 0xF2E8, 0xF2EB, 0xF2E4, 0xF2E5, 0xF2EA, 0xF2E9, 0xF2E6, 0xF200, 0xF200, 0xF200, 0xF200, 0xF200, 0xF200, 0xF200, 0xF200, 0xF200, 0xF200, 0xF200, 0xF200, 0xF230, 0xF231, 0xF232, 0xF233, 0xF234, 0xF235, 0xF236, 0xF237, 0xF238, 0xF239, 0xF25E, 0xF25E, 0xF20C, 0xF20D, 0xF20E, 0xF20F, 0xF23C, 0xF23E, 0xF202, 0xF21D, 0xF203, 0xF21E, 0xF204, 0xF29F, 0xF212, 0xF213, 0xF214, 0xF205, 0xF295, 0xF21C, 0xF206, 0xF21F, 0xF2EF, 0xF2EC, 0xF2ED, 0xF2F0, 0xF215, 0xF292, 0xF216, 0xF293, 0xF217, 0xF294, 0xF280, 0xF281, 0xF282, 0xF296, 0xF283, 0xF284, 0xF285, 0xF297, 0xF29A, 0xF29B, 0xF29C, 0xF218, 0xF286, 0xF287, 0xF288, 0xF29D, 0xF21A, 0xF289, 0xF28A, 0xF28B, 0xF29E, 0xF28D, 0xF28E, 0xF298, 0xF28F, 0xF290, 0xF291, 0xF299, 0xF219, 0xF27B, 0xF27D, 0xF210, 0xF245, 0xF246, 0xF243, 0xF244, 0xF2DA, 0xF2DB, 0xF247, 0xF248, 0xF2D9, 0xF2D8, 0xF2D6, 0xF2D7, 0xF241, 0xF242, 0xF24C, 0xF24B, 0xF249, 0xF24A, 0xF2D1, 0xF2D2, 0xF250, 0xF24F, 0xF24D, 0xF24E, 0xF254, 0xF253, 0xF251, 0xF252, 0xF258, 0xF257, 0xF255, 0xF256, 0xF260, 0xF25C, 0xF259, 0xF25A, 0xF264, 0xF263, 0xF261, 0xF262, 0xF265, 0xF266, 0xF267, 0xF268, 0xF269, 0xF26A, 0xF26B, 0xF26C, 0xF270, 0xF26F, 0xF26D, 0xF26E, 0xF274, 0xF273, 0xF271, 0xF272, 0xF278, 0xF277, 0xF275, 0xF276, 0xF27E, 0xF27C, 0xF279, 0xF27A, 0xF2A2, 0xF2A1, 0xF27F, 0xF2F1, 0xF2A6, 0xF2A5, 0xF2A3, 0xF2A4, 0xF2AA, 0xF2A9, 0xF2A7, 0xF2A8, 0xF2AE, 0xF2AD, 0xF2AB, 0xF2AC, 0xF2B2, 0xF2B1, 0xF2AF, 0xF2B0, 0xF2B6, 0xF2B5, 0xF2B3, 0xF2B4, 0xF2BA, 0xF2B9, 0xF2B7, 0xF2B8, 0xF2BE, 0xF2BD, 0xF2BB, 0xF2BC, 0xF2C2, 0xF2C1, 0xF2BF, 0xF2C0, 0xF2C6, 0xF2C5, 0xF2C3, 0xF2C4, 0xF2CA, 0xF2C9, 0xF2C7, 0xF2C8, 0xF2CB, 0xF2CC, 0xF2D4, 0xF2D3, 0xF2D0, 0xF2CF, 0xF2CD, 0xF2CE, 0xF2E0, 0xF2E1, 0xF2DE, 0xF2DF, 0xF2E2, 0xF2E3, 0xF2DC, 0xF2DD]
}
