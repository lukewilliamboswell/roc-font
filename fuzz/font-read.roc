app [target] {
	build: "../tests/support/main.roc",
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}

import fuzz.Fuzz
import font.Font
import build.FontBuild
import "../tests/fonts/Inter-Regular-metrics.ttf" as inter_file : List(U8)

## The font reading contract on untrusted bytes: reading never crashes, is
## deterministic, and either succeeds or reports at least one problem;
## strict reading succeeds exactly when lenient reading succeeds with
## nothing dropped. On success every query is total: character lookups give
## glyphs the font has, the code point listing is ascending and agrees with
## lookups, advances are non-negative, boxes are ordered, and shaping keeps
## its lists index-aligned, its clusters inside the text and in order, and
## its growth within HarfBuzz's bound (256 glyphs per character, at least
## 65536). The feature listing is four-byte tags in increasing order
## without repeats, a planned width is the sum of the planned run's
## advances, and each glyph's text range starts at its cluster and ends
## after it, inside the text.
##
## Inputs are fonts or recipes for nearly valid fonts (see
## `FontBuild.fuzz_font`): real font files, or Inter or the synthetic
## `FontBuild.sample` with bytes patched or cut short.
##
## Reading cost also grows linearly: the input's bytes choose the contents
## of `FontBuild.scaled` fonts, read at 2 and 16 copies; the larger must not
## take more than about 8 times the allocations, and reading must free what
## it allocates.
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	font_bytes = FontBuild.fuzz_font(bytes, inter_file)
	first = Font.from_bytes(font_bytes, Font.ReadOptions.{})
	if summary(first) != summary(Font.from_bytes(font_bytes, Font.ReadOptions.{})) {
		crash "reading the same bytes twice gave different results"
	}
	strict = Font.from_bytes(font_bytes, Font.ReadOptions.{ strict: True })
	match (first, strict) {
		(Err([]), _) => crash "bytes were rejected without a problem"
		(_, Err([])) => crash "strict reading rejected bytes without a problem"
		(Err(_), Ok(_)) => crash "strict reading accepted bytes lenient reading rejected"
		(Ok(font), Ok(_)) if !Font.dropped(font).is_empty() => crash "strict reading accepted a font with dropped tables"
		(Ok(font), Err(_)) if Font.dropped(font).is_empty() => crash "strict reading rejected a font lenient reading read whole"
		(Ok(font), _) => check!(font)
		(Err(_), Err(_)) => {}
	}
	small = FontBuild.scaled(bytes, 2)
	large = FontBuild.scaled(bytes, 16)
	small_cost = Fuzz.measure_allocs!(|{}| Font.from_bytes(small, Font.ReadOptions.{}))
	large_cost = Fuzz.measure_allocs!(|{}| Font.from_bytes(large, Font.ReadOptions.{}))
	Fuzz.expect_no_leaks!(|{}| Font.from_bytes(large, Font.ReadOptions.{}))
	if large_cost.allocations > 10 * small_cost.allocations + 256 {
		crash "reading a font 8 times larger took ${large_cost.allocations.to_str()} allocations, against ${small_cost.allocations.to_str()}"
	}
	match large_cost.value {
		Ok(_) => Fuzz.keep
		Err(_) => crash "a scaled font was not read"
	}
}

## Code points worth asking about: the edges of the planes and of ranges
## fonts commonly map, and the characters the synthetic fonts map.
code_points : List(U32)
code_points = [0, 1, 0x20, 0x41, 0x5A, 0x61, 0x7E, 0x7F, 0xA0, 0xFF, 0x100, 0x400, 0x401, 0x2192, 0xD800, 0xFFFD, 0xFFFE, 0xFFFF, 0x10000, 0x1F600, 0x1F852, 0x10FFFF, 0x110000, 0xFFFFFFFF]

## Glyph ids worth asking about, beyond the font's own.
probe_glyphs : Font -> List(U32)
probe_glyphs = |font| {
	total = Font.glyph_count(font)
	[0, 1, 2, 3, 7, 9, 11, 30, 1805, 2936, total - 1, total, total + 1, 65535, 65536, 0xFFFFFFFF]
}

## Texts worth shaping: empty, the sample fonts' letters, ligature and
## arrow candidates, and a mix of scripts.
texts : List(Str)
texts = ["", "A", "GABC", "office ->> <-> fi", "AVATAR Tomorrow", "αβγ Привет €100", Str.join_with(List.repeat("AB", 40), "")]

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
				glyphs.map(|g| Font.extents(font, g)),
				Font.code_points(font).take_first(64),
				Font.axes(font),
				Font.features(font),
				texts.map(|t| Font.shape(font, t, Font.ShapeOptions.{})),
			))
		}
	}

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
	# The listing is ascending and every listed code point maps.
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
	}
	for text in texts {
		check_run!(text, Font.shape(font, text, Font.ShapeOptions.{}), False)
		check_run!(text, Font.shape(font, text, Font.ShapeOptions.{ direction: RightToLeft }), True)
	}
	var $tag = []
	for tag in Font.features(font) {
		bytes = tag.to_utf8()
		# Four ISO 8859-1 characters: at most eight bytes of UTF-8 (UTF-8
		# keeps code point order, so the order check below still holds).
		if bytes.len() > 8 {
			crash "a feature tag is longer than four characters"
		}
		if !$tag.is_empty() and !before($tag, bytes) {
			crash "the feature listing is not in increasing order without repeats"
		}
		$tag = bytes
	}
	plan = Font.plan(font, Font.ShapeOptions.{ features: [Font.Feature.{ tag: "liga", value: 0 }] })
	for text in texts {
		run = Font.shape_planned(font, plan, text)
		sum = run.advances.fold(0.I64, |acc, a| acc + a.x.to_i64()).max(-2147483648).min(2147483647)
		if Font.width_planned(font, plan, text).to_i64() != sum {
			crash "a planned width is not the sum of the planned run's advances"
		}
	}
	bold = Font.at(font, Font.Variation.{ weight: Bold, axes: [{ tag: "opsz", value: 36 }] })
	for g in probe_glyphs(font) {
		if Font.advance(bold, g) < 0 {
			crash "an advance at another location is negative"
		}
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

## A run's lists are index-aligned, its clusters lie inside the text and
## run in order (backwards for right-to-left), and it grew within bounds.
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
	# Bit 0 is unsafe to break; bit 1 marks glyph 0 drawn for a character
	# the font does not map.
	if !run.flags.all(|f| f <= 3) or run.flags.map2(run.glyphs, |f, g| Font.is_missing(f) and g != 0).any(|bad| bad) {
		crash "a flag other than unsafe-to-break or missing is set, or missing on a real glyph"
	}
	ranges = Font.cluster_ranges(run, bytes)
	if ranges.len() != n or !ranges.map2(run.clusters, |r, c| r.start == c and r.end > r.start and r.end <= bytes).all(|ok| ok) {
		crash "a glyph's text range is not aligned with its cluster or leaves the text"
	}
}

target = Fuzz.target_with!({
	name: "font-read",
	generator: Fuzz.raw_bytes,
	test!,
	show: |bytes| Str.inspect(bytes.take_first(64)),
})
