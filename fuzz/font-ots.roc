app [target] {
	build: "../tests/support/main.roc",
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}

import fuzz.Fuzz
import font.Font
import build.FontBuild

## The checks reading shares with OTS 9.3.0 (the font header, the
## character map, glyph substitutions, the PostScript table and the naming
## table), one damaged table at a time. A valid font with all five tables
## is built at two sizes, 2 and 16 copies of its contents (character map
## ranges, substitution lookups, stored glyph names, name records), and the
## same damage is done to one table of each.
##
## The first input byte chooses: the damaged table (`head`, `cmap`, `GSUB`,
## `post` or `name`, by its low three bits modulo 5), the `post` version
## (bits 3 and 4: 2.0, 1.0, 3.0 or 2.0), a format 1 naming table with a
## language tag (bit 5), and whether the damaged table is cut short (bit 6,
## to a length the next byte chooses, as a fraction of 256). The rest are
## patches of three bytes, a position in the table (two bytes, wrapped to
## its length) and its new value.
##
## Contract: both undamaged fonts read, strictly, with nothing dropped.
## Reading each damaged font is deterministic (two reads give identical
## results); strict reading succeeds exactly when lenient reading succeeds
## with nothing dropped; every problem, whether it refuses the font or
## drops a table, names exactly the damaged table. An accepted font's
## queries and shaping calls are total: character lookups give glyphs the
## font has, the code point listing is ascending and maps, advances are
## non-negative, boxes are ordered, glyphs past the font have no name,
## ASCII feature tags are listed in increasing order, and shaping keeps
## its lists index-aligned and its clusters inside the text and in order. Reading the larger damaged font takes at most
## `10 × small + 256` allocations, against reading the smaller undamaged
## one in full (linear), and leaks nothing.
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	choice = bytes.first() ?? 0
	rest = bytes.drop_first(1)
	small_clean = tables(choice, 2)
	large_clean = tables(choice, 16)
	clean!(small_clean)
	clean!(large_clean)
	tag = damaged_tag(choice)
	small = damage(small_clean, choice, rest)
	large = damage(large_clean, choice, rest)
	check_damaged!(small, tag)
	check_damaged!(large, tag)
	small_file = FontBuild.file(small_clean)
	large_file = FontBuild.file(large)
	small_read = Fuzz.measure_allocs!(|{}| Font.from_bytes(small_file, Font.ReadOptions.{}))
	large_read = Fuzz.measure_allocs!(|{}| Font.from_bytes(large_file, Font.ReadOptions.{}))
	Fuzz.expect_no_leaks!(|{}| Font.from_bytes(large_file, Font.ReadOptions.{}))
	if large_read.allocations > 10 * small_read.allocations + 256 {
		crash "reading a damaged font 8 times larger took ${large_read.allocations.to_str()} allocations, against ${small_read.allocations.to_str()} for the smaller font undamaged"
	}
	Fuzz.keep
}

Tables : List({ tag : Str, data : List(U8) })

## The table the choice byte damages.
damaged_tag : U8 -> Str
damaged_tag = |choice|
	match choice.bitwise_and(7).to_u64() % 5 {
		0 => "head"
		1 => "cmap"
		2 => "GSUB"
		3 => "post"
		_ => "name"
	}

## A valid font of `16 × copies` glyphs whose tables grow with `copies`.
tables : U8, U64 -> Tables
tables = |choice, copies| {
	glyphs = 16 * copies
	# Character map: `copies` ranges of three characters from U+0041, in a
	# format 4 map and a format 12 map, with a Macintosh map beside them.
	ranges = FontBuild.counting(copies).map(|k| { first: 0x41 + 4 * k, last: 0x43 + 4 * k, glyph: 1 + 3 * k })
	characters = FontBuild.cmap([
		{ system: 0, encoding: 3, subtable: FontBuild.cmap4(ranges.map(|r| { first: r.first, last: r.last, delta: (r.glyph + 65536 - r.first) % 65536, glyphs: [] })) },
		{ system: 1, encoding: 0, subtable: FontBuild.cmap0(List.repeat(0, 0x41).concat([1, 2, 3])) },
		{ system: 3, encoding: 10, subtable: FontBuild.cmap12(ranges) },
	])
	# Substitutions: `copies` single substitutions and ligatures, every
	# glyph inside the font.
	lookups = FontBuild.counting(copies).join_map(
		|k| [
			{ kind: 1, subtables: [FontBuild.single1([1 + 3 * k], 1)] },
			{ kind: 4, subtables: [FontBuild.ligature([2 + 3 * k], [[{ glyph: glyphs - 1, rest: [3 + 3 * k] }]])] },
		],
	)
	gsub = FontBuild.layout("latn", [{ tag: "liga", lookups: FontBuild.counting(lookups.len()) }], lookups)
	# Glyph names: standard names and one stored name for every third glyph.
	indices = FontBuild.counting(glyphs).map(|g| if (g % 3 == 2) 258 + g // 3 else g % 258)
	stored = FontBuild.counting(glyphs).keep_if(|g| g % 3 == 2).map(|g| "glyph${g.to_str()}")
	version = match choice.shr_zf_wrap(3).bitwise_and(3) {
		1 => 0x00010000
		2 => 0x00030000
		_ => 0x00020000
	}
	tagged = choice.bitwise_and(0x20) != 0
	records = [
		{ system: 0, encoding: 3, language: if (tagged) 0x8000 else 0, id: 1, text: FontBuild.utf16("Unicode Fuzz") },
		{ system: 1, encoding: 0, language: 0, id: 1, text: "Mac Fuzz".to_utf8() },
		{ system: 3, encoding: 1, language: 0x409, id: 1, text: FontBuild.utf16("Fuzz Sans") },
		{ system: 3, encoding: 1, language: 0x409, id: 2, text: FontBuild.utf16("Regular") },
		{ system: 3, encoding: 1, language: 0x409, id: 6, text: FontBuild.utf16("FuzzSans-Regular") },
	].concat(FontBuild.counting(copies).map(|k| { system: 3, encoding: 1, language: 0x409, id: 256 + k, text: FontBuild.utf16("Instance ${k.to_str()}") }))
	[
		{ tag: "head", data: FontBuild.head(1000, False) },
		{ tag: "hhea", data: FontBuild.hhea(800, -200, glyphs) },
		{ tag: "maxp", data: FontBuild.maxp(glyphs) },
		{ tag: "hmtx", data: FontBuild.hmtx(FontBuild.counting(glyphs).map(|g| 100 + g % 400)) },
		{ tag: "cmap", data: characters },
		{ tag: "GSUB", data: gsub },
		{ tag: "post", data: FontBuild.post(version, indices, stored) },
		{ tag: "name", data: FontBuild.naming(records, if (tagged) [FontBuild.utf16("en-GB")] else []) },
	]
}

## The tables with the damaged one cut short and patched.
damage : Tables, U8, List(U8) -> Tables
damage = |all, choice, rest| {
	tag = damaged_tag(choice)
	cut = choice.bitwise_and(0x40) != 0
	patches = if (cut) rest.drop_first(1) else rest
	all.map(
		|t|
			if t.tag != tag {
				t
			} else {
				kept = if (cut) t.data.take_first(t.data.len() * (rest.first() ?? 0).to_u64() // 256) else t.data
				{ tag: t.tag, data: patch(kept, patches) }
			},
	)
}

## Bytes with each three-byte patch (position wrapped to the length, then
## value) applied.
patch : List(U8), List(U8) -> List(U8)
patch = |data, patches| {
	var $out = data
	var $k = 0
	while $k + 3 <= patches.len() and !$out.is_empty() {
		at = (patches.get($k) ?? 0).to_u64() * 256 + (patches.get($k + 1) ?? 0).to_u64()
		# The position is wrapped to the length, so it is in bounds.
		$out = $out.set(at % $out.len(), patches.get($k + 2) ?? 0) ?? []
		$k = $k + 3
	}
	$out
}

## An undamaged font reads, strictly, with nothing dropped.
clean! : Tables => {}
clean! = |all| {
	file = FontBuild.file(all)
	match (Font.from_bytes(file, Font.ReadOptions.{}), Font.from_bytes(file, Font.ReadOptions.{ strict: True })) {
		(Ok(font), Ok(_)) if Font.dropped(font).is_empty() => check!(font)
		(lenient, strict) => crash "an undamaged font did not read in full: ${Str.inspect(problems_of(lenient))} ${Str.inspect(problems_of(strict))}"
	}
}

problems_of : Try(Font, List(Font.Problem)) -> List(Font.Problem)
problems_of = |result|
	match result {
		Ok(font) => Font.dropped(font)
		Err(problems) => problems
	}

## The table a problem names, as reading reports it.
named : Font.Problem -> Str
named = |problem|
	match problem {
		BadTable({ table, offset: _ }) => table
		MissingTable(table) => table
		BadUnitsPerEm => "head"
		NoUnicodeMapping => "cmap"
		OverLimit("max_lookups") => "GSUB"
		OverLimit(which) => which
		NotAFont => "the file"
		NoSuchFace(_) => "the file"
	}

check_damaged! : Tables, Str => {}
check_damaged! = |all, tag| {
	file = FontBuild.file(all)
	first = Font.from_bytes(file, Font.ReadOptions.{})
	if summary(first) != summary(Font.from_bytes(file, Font.ReadOptions.{})) {
		crash "reading the same damaged font twice gave different results"
	}
	strict = Font.from_bytes(file, Font.ReadOptions.{ strict: True })
	for problem in problems_of(first).concat(problems_of(strict)) {
		if named(problem) != tag {
			crash "damage to ${tag} was reported against ${named(problem)}: ${Str.inspect(problem)}"
		}
	}
	match (first, strict) {
		(Err([]), _) => crash "a damaged font was rejected without a problem"
		(_, Err([])) => crash "strict reading rejected a damaged font without a problem"
		(Err(_), Ok(_)) => crash "strict reading accepted a font lenient reading rejected"
		(Ok(font), Ok(_)) if !Font.dropped(font).is_empty() => crash "strict reading accepted a font with dropped tables"
		(Ok(font), Err(_)) if Font.dropped(font).is_empty() => crash "strict reading rejected a font lenient reading read whole"
		(Ok(font), _) => check!(font)
		(Err(_), Err(_)) => {}
	}
}

## Code points worth asking about: the mapped ranges, their neighbours and
## the edges of the planes.
code_points : List(U32)
code_points = [0, 0x20, 0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x61, 0x7F, 0xFF, 0x100, 0xFFFF, 0x10000, 0x10FFFF, 0x110000, 0xFFFFFFFF]

## Glyph ids worth asking about, beyond the font's own.
probe_glyphs : Font -> List(U32)
probe_glyphs = |font| {
	total = Font.glyph_count(font)
	[0, 1, 2, 3, 4, 5, 257, 258, 259, total - 1, total, total + 1, 65535, 0xFFFFFFFF]
}

## Texts worth shaping: empty, the mapped letters (ligature candidates),
## and characters the font lacks.
texts : List(Str)
texts = ["", "A", "ABC", "BCBC DEFGHIJ", "αβγ €100", Str.join_with(List.repeat("ABCD", 20), "")]

## Everything observable about a read, for comparing two reads.
summary : Try(Font, List(Font.Problem)) -> Str
summary = |result|
	match result {
		Err(problems) => Str.inspect(problems)
		Ok(font) => {
			glyphs = probe_glyphs(font)
			Str.inspect((
				Font.units_per_em(font),
				Font.metrics(font),
				Font.glyph_count(font),
				Font.dropped(font),
				code_points.map(|cp| Font.glyph(font, cp) ?? 0xFFFFFFFF),
				glyphs.map(|g| Font.advance(font, g)),
				glyphs.map(|g| Font.glyph_name(font, g)),
				Font.family_name(font),
				Font.code_points(font).take_first(64),
				Font.features(font),
				texts.map(|t| Font.shape(font, t, Font.ShapeOptions.{})),
			))
		}
	}

## Every query and shaping call on an accepted font is total and keeps its
## promises.
check! : Font => {}
check! = |font| {
	total = Font.glyph_count(font)
	units = Font.units_per_em(font)
	if total == 0 or units < 16 or units > 16384 {
		crash "a font's units per em or glyph count is out of range"
	}
	for cp in code_points {
		match Font.glyph(font, cp) {
			Ok(g) if g >= total => crash "a character maps to a glyph the font does not have"
			_ => {}
		}
	}
	var $previous = Err(None)
	for cp in Font.code_points(font).take_first(4096) {
		match $previous {
			Ok(p) if cp <= p => crash "the code point listing is not ascending"
			_ => {}
		}
		if Font.glyph(font, cp).is_err() {
			crash "a listed code point does not map to a glyph"
		}
		$previous = Ok(cp)
	}
	for g in probe_glyphs(font) {
		if Font.advance(font, g) < 0 {
			crash "an advance is negative"
		}
		match Font.extents(font, g) {
			Extents(box) if box.x_min > box.x_max or box.y_min > box.y_max => crash "a glyph box is not ordered"
			_ => {}
		}
		match Font.glyph_name(font, g) {
			Ok(_) if g >= total => crash "a glyph past the font has a name"
			_ => {}
		}
	}
	# Feature tags OTS does not check: a damaged tag may hold bytes past
	# ASCII, which `Font.features` decodes lossily (several raw tags can
	# then give the same string). Only ASCII tags are checked for order.
	var $tag = []
	for tag in Font.features(font) {
		b = tag.to_utf8()
		if b.len() == 4 and b.all(|x| x < 0x80) {
			if !$tag.is_empty() and !before($tag, b) {
				crash "the feature listing is not tags in increasing order without repeats"
			}
			$tag = b
		}
	}
	for text in texts {
		check_run!(text, Font.shape(font, text, Font.ShapeOptions.{}), False)
		check_run!(text, Font.shape(font, text, Font.ShapeOptions.{ direction: RightToLeft }), True)
	}
}

## Whether bytes `a` come before bytes `b` in byte order.
before : List(U8), List(U8) -> Bool
before = |a, b| {
	var $k = 0
	var $result = a.len() < b.len()
	var $going = True
	while $going and $k < a.len() and $k < b.len() {
		x = a.get($k) ?? 0
		y = b.get($k) ?? 0
		if x != y {
			$result = x < y
			$going = False
		}
		$k = $k + 1
	}
	$result
}

## A run's lists are index-aligned, its glyphs are the font's, its clusters
## lie inside the text and run in order (backwards for right-to-left), and
## it grew within HarfBuzz's bound.
check_run! : Str, Font.Run, Bool => {}
check_run! = |text, run, rtl| {
	n = run.glyphs.len()
	if run.advances.len() != n or run.offsets.len() != n or run.clusters.len() != n or run.flags.len() != n {
		crash "a run's lists are not index-aligned"
	}
	bytes = text.to_utf8().len()
	if n > (256 * bytes).max(65536) {
		crash "shaping grew ${bytes.to_str()} bytes of text to ${n.to_str()} glyphs"
	}
	if !run.clusters.all(|c| c.to_u64() < bytes) {
		crash "a cluster lies outside the text"
	}
	var $k = 1
	while $k < n {
		a = run.clusters.get($k - 1) ?? 0
		b = run.clusters.get($k) ?? 0
		if if (rtl) a < b else a > b {
			crash "clusters are out of order"
		}
		$k = $k + 1
	}
}

target = Fuzz.target_with!({
	name: "font-ots",
	generator: Fuzz.raw_bytes,
	test!,
	show: |bytes| Str.inspect(bytes.take_first(64)),
})
