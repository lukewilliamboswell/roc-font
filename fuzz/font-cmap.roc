app [target] {
	build: "../tests/support/main.roc",
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}

import fuzz.Fuzz
import font.Font
import build.FontBuild

## Character maps, one subtable format at a time. The first input byte
## picks the format (0, 4, 6, 10, 12 or 13, by its value modulo 6; for
## format 4 its bit 3 picks glyph arrays over deltas, for formats 10 and 12
## its bit 4 moves the map past U+FFFF, and for formats 4, 12 and 13 its
## bit 5 adds a final range drawn by a glyph past the font); every further
## byte chooses a range of the map: its distance from the last one, its
## length and its first glyph. The same choices build a font at two sizes,
## 2 and 16 copies of the ranges.
##
## The fonts follow what OTS 9.3.0 accepts, as reading does. A browser
## needs a format 4, 12 or 13 map it can pass on, so formats 0, 6 and 10
## sit beside an empty format 4 map (platform 0, encoding 0), which they
## outrank when a map is chosen; their glyphs may be glyph 0 or past the
## font, which OTS does not check. Formats 4, 12 and 13 name only glyphs
## the font has (OTS refuses any other), and their groups are never empty.
##
## Contract: both fonts read (or, with a glyph past the font, both are
## refused with exactly one problem, a bad `cmap`); every character lookup
## agrees with the map the recipe describes (a character the map lacks, or
## that maps to glyph 0 or a glyph past the font, is missing); the code
## point listing is that map, ascending; reading and lookups are
## deterministic. Reading the larger font takes at most `10 × small + 256`
## allocations (linear), looking up the same characters costs no more
## allocations in the larger font (constant per call), listing the code
## points is linear, and nothing leaks.
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	choice = bytes.first() ?? 0
	picks = bytes.drop_first(1).take_first(32)
	small = recipe(choice, picks, 2)
	large = recipe(choice, picks, 16)
	small_read = Fuzz.measure_allocs!(|{}| Font.from_bytes(small.file, Font.ReadOptions.{}))
	large_read = Fuzz.measure_allocs!(|{}| Font.from_bytes(large.file, Font.ReadOptions.{}))
	Fuzz.expect_no_leaks!(|{}| Font.from_bytes(large.file, Font.ReadOptions.{}))
	if large_read.allocations > 10 * small_read.allocations + 256 {
		crash "reading a character map 8 times larger took ${large_read.allocations.to_str()} allocations, against ${small_read.allocations.to_str()}"
	}
	if small.past {
		refused!(small)
		refused!(large)
		return Fuzz.keep
	}
	small_font = check!(small)
	large_font = check!(large)
	small_look = Fuzz.measure_allocs!(|{}| lookups(small_font))
	large_look = Fuzz.measure_allocs!(|{}| lookups(large_font))
	Fuzz.expect_no_leaks!(|{}| lookups(large_font))
	if large_look.allocations > small_look.allocations + 8 {
		crash "looking up ${probes.len().to_str()} characters took ${large_look.allocations.to_str()} allocations in a map 8 times larger, against ${small_look.allocations.to_str()}"
	}
	small_list = Fuzz.measure_allocs!(|{}| Font.code_points(small_font))
	large_list = Fuzz.measure_allocs!(|{}| Font.code_points(large_font))
	Fuzz.expect_no_leaks!(|{}| Font.code_points(large_font))
	if large_list.allocations > 10 * small_list.allocations + 64 {
		crash "listing code points of a map 8 times larger took ${large_list.allocations.to_str()} allocations, against ${small_list.allocations.to_str()}"
	}
	Fuzz.keep
}

## A range of the map: `first ..= last` drawn by consecutive glyphs from
## `glyph`, or all by `glyph` when `same`.
MapRange : { first : U64, last : U64, glyph : U64, same : Bool }

## The font a recipe builds, the map it describes, and whether that map
## names a glyph past the font (so the font must be refused).
Built : { file : List(U8), ranges : List(MapRange), glyphs : U64, past : Bool }

pick : List(U8), U64 -> U64
pick = |bytes, i| if (bytes.is_empty()) 0 else (bytes.get(i % bytes.len()) ?? 0).to_u64()

recipe : U8, List(U8), U64 -> Built
recipe = |choice, picks, copies| {
	format = choice.to_u64() % 6
	glyphs = 32 * copies
	count = picks.len().max(1) * copies
	start = if (format == 0) 0 else if ((format == 3 or format == 4) and choice.bitwise_and(0x10) != 0) 0x10000 else 0x20
	# Formats 4, 12 and 13 are checked by OTS: every glyph below the count.
	checked = format == 1 or format == 4 or format == 5
	past = checked and choice.bitwise_and(0x20) != 0
	var $ranges = []
	var $next = start
	for j in 0..<count {
		b = pick(picks, j)
		first = $next + b % 4
		len = 1 + b.shr_zf_wrap(2) % 8
		glyph =
			if b % 11 == 0 {
				0
			} else if checked {
				# A range of up to 8 glyphs ends below the count.
				(b * 7 + 3 * j) % (glyphs - 8)
			} else {
				# Unchecked formats sometimes name glyphs past the font.
				(b * 7 + 3 * j) % (glyphs + 16)
			}
		# Format 0 holds byte-sized glyph ids for 256 characters.
		fits = format != 0 or (first + len <= 256 and glyph + len <= 256)
		if fits {
			$ranges = $ranges.append({ first, last: first + len - 1, glyph, same: format == 5 })
		}
		$next = first + len
	}
	# The refused branch: a final range whose last glyph is past the font
	# (format 13's one glyph is the count itself).
	ranges = if (past) $ranges.append({ first: $next + 1, last: $next + 2, glyph: if (format == 5) glyphs else glyphs - 1, same: format == 5 }) else $ranges
	groups = ranges.map(|r| { first: r.first, last: r.last, glyph: r.glyph })
	subtable =
		match format {
			0 => FontBuild.cmap0(dense(ranges, 0))
			1 =>
				if choice.bitwise_and(0x08) != 0 {
					FontBuild.cmap4(ranges.map(|r| { first: r.first, last: r.last, delta: 0, glyphs: FontBuild.counting(r.last - r.first + 1).map(|t| r.glyph + t) }))
				} else {
					FontBuild.cmap4(ranges.map(|r| { first: r.first, last: r.last, delta: (r.glyph + 65536 - r.first % 65536) % 65536, glyphs: [] }))
				}
			2 => FontBuild.cmap6(start, dense(ranges, start))
			3 => FontBuild.cmap10(start, dense(ranges, start))
			4 => FontBuild.cmap12(groups)
			_ => FontBuild.cmap13(groups)
		}
	full = format >= 3
	own = { system: 3, encoding: if (full) 10 else 1, subtable }
	# A browser needs a map it passes on: an empty format 4 map beside the
	# formats OTS does not pass on, which outrank it.
	records = if (checked) [own] else [{ system: 0, encoding: 0, subtable: FontBuild.cmap4([]) }, own]
	file = FontBuild.glyphs_font(FontBuild.counting(glyphs).map(|g| 100 + g % 400), FontBuild.cmap(records), [])
	{ file, ranges, glyphs, past }
}

## A font whose map names a glyph past the font is refused, strictly or
## not, with exactly one problem: a bad `cmap`.
refused! : Built => {}
refused! = |built| {
	for options in [Font.ReadOptions.{}, Font.ReadOptions.{ strict: True }] {
		match Font.from_bytes(built.file, options) {
			Err([BadTable({ table: "cmap", offset: _ })]) => {}
			other => crash "a map naming a glyph past the font was not refused as a bad cmap: ${Str.inspect(other.map_ok(|_| {}))}"
		}
	}
}

## The glyphs of consecutive characters from `start` (0 between ranges).
dense : List(MapRange), U64 -> List(U64)
dense = |ranges, start| {
	end = (ranges.last() ?? { first: start, last: start, glyph: 0, same: False }).last + 1
	var $out = List.repeat(0, end - start)
	for r in ranges {
		for c in r.first..=r.last {
			# Ranges lie inside `start ..< end`.
			$out = $out.set(c - start, r.glyph + c - r.first) ?? []
		}
	}
	$out
}

## The glyph the recipe gives a character, if it is in the font: a
## binary search of the ranges, which are ascending and disjoint.
expected : Built, U64 -> Try(U32, [Missing])
expected = |built, cp| {
	var $low = 0
	var $high = built.ranges.len()
	while $low < $high {
		mid = ($low + $high) // 2
		r = built.ranges.get(mid) ?? { first: 0, last: 0, glyph: 0, same: False }
		if cp < r.first {
			$high = mid
		} else if cp > r.last {
			$low = mid + 1
		} else {
			return in_font(built, if (r.same) r.glyph else r.glyph + cp - r.first)
		}
	}
	Err(Missing)
}

in_font : Built, U64 -> Try(U32, [Missing])
in_font = |built, g| if (g != 0 and g < built.glyphs) Ok(g.to_u32_wrap()) else Err(Missing)

## Characters worth asking about whatever the map holds.
probes : List(U32)
probes = [0, 0x1F, 0x20, 0x21, 0x41, 0x7F, 0xFF, 0x100, 0x1FF, 0x400, 0xFFFE, 0xFFFF, 0x10000, 0x10020, 0x10021, 0x10FFFF, 0x110000, 0xFFFFFFFF].concat(FontBuild.counting(46).map(|k| (0x20 + 7 * k).to_u32_wrap()))

## Look up the probes, keeping only a sum (no list of results).
lookups : Font -> U64
lookups = |font| probes.fold(0, |sum, cp| sum + (Font.glyph(font, cp) ?? 0).to_u64())

check! : Built => Font
check! = |built| {
	font = match Font.from_bytes(built.file, Font.ReadOptions.{ strict: True }) {
		Ok(f) => f
		Err(problems) => crash "a valid character map was rejected: ${Str.inspect(problems)}"
	}
	again = Font.from_bytes(built.file, Font.ReadOptions.{}) ?? crash "a font read once failed to read again"
	if Font.glyph_count(font).to_u64() != built.glyphs {
		crash "the glyph count is not the recipe's"
	}
	# Every character of every range, its neighbours, and the probes.
	var $asked = probes.map(|p| p.to_u64())
	for r in built.ranges.take_first(512) {
		$asked = $asked.concat([r.first - r.first.min(1), r.first, r.last, r.last + 1, (r.first + r.last) // 2])
	}
	for cp in $asked {
		got = Font.glyph(font, cp.to_u32_wrap())
		want = if (cp > 0xFFFFFFFF) Err(Missing) else expected(built, cp)
		if got != want {
			crash "U+${cp.to_str()} maps to ${Str.inspect(got)}, but the map gives ${Str.inspect(want)}"
		}
		if got != Font.glyph(again, cp.to_u32_wrap()) {
			crash "two reads of one font map a character differently"
		}
	}
	listed = Font.code_points(font)
	var $want = []
	for r in built.ranges {
		for c in r.first..=r.last {
			if in_font(built, if (r.same) r.glyph else r.glyph + c - r.first).is_ok() {
				$want = $want.append(c.to_u32_wrap())
			}
		}
	}
	if listed != $want {
		crash "the code point listing is not the map: ${Str.inspect(listed.take_first(16))} against ${Str.inspect($want.take_first(16))}"
	}
	if listed != Font.code_points(again) {
		crash "two reads of one font list different code points"
	}
	font
}

target = Fuzz.target_with!({
	name: "font-cmap",
	generator: Fuzz.raw_bytes,
	test!,
	show: |bytes| Str.inspect(bytes.take_first(33)),
})
