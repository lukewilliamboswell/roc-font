app [target] {
	build: "../tests/support/main.roc",
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}

import fuzz.Fuzz
import font.Font
import build.FontBuild
import "../tests/fonts/Inter-Regular-metrics.ttf" as inter_file : List(U8)

## The shaping contract on arbitrary text. The input is the text's bytes
## (read as UTF-8, invalid sequences replaced), then optionally a 0xFF byte
## (never part of UTF-8) and a font: a real font file or a recipe for a
## nearly valid one, as the font reading target takes them (see
## `FontBuild.fuzz_font`). Without a font, or with one that cannot be read,
## the text is shaped with Inter.
##
## Shaping is deterministic; a run's lists are index-aligned; its clusters
## lie inside the text, in order for left-to-right text and in reverse for
## right-to-left; it never has more than 256 glyphs per byte of text (or
## 65536 in all), HarfBuzz's bound; only the unsafe-to-break flag is set;
## the same with features turned off over part of the text, and with
## script and language tags (real ones, and the text's first bytes as a
## language tag), deterministically; shaping with a
## plan agrees with shaping directly, and so does shaping scalars with
## their offsets, tracing them (with one origin per glyph, the same twice)
## and checking the budgets (complete, or over budget with that same run
## and at least one bound named, the bounds tracing names); the width is
## the sum of the advances.
## Shaping 8 times the
## text (16 against 2 copies) must not take more than about 8 times the
## allocations, and must free what it allocates.
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	split = split_at_marker(bytes)
	read = if (split.font.is_empty()) Err([]) else Font.from_bytes(FontBuild.fuzz_font(split.font, inter_file), Font.ReadOptions.{})
	font = read ?? inter
	text = Str.from_utf8_lossy(split.text)
	n = text.to_utf8().len()
	ltr = Font.shape(font, text, Font.ShapeOptions.{})
	if Str.inspect(ltr) != Str.inspect(Font.shape(font, text, Font.ShapeOptions.{})) {
		crash "shaping the same text twice gave different runs"
	}
	check_run!(n, ltr, False)
	plan = Font.plan(font, Font.ShapeOptions.{})
	if Str.inspect(Font.shape_planned(font, plan, text)) != Str.inspect(ltr) {
		crash "shaping with a plan differs from shaping directly"
	}
	scalars = decode(text.to_utf8())
	if Str.inspect(Font.shape_scalars(font, plan, scalars)) != Str.inspect(ltr) {
		crash "shaping scalars with their offsets differs from shaping the text"
	}
	traced_result = Font.shape_traced(font, plan, text)
	traced = match traced_result {
		Ok(t) => { run: t.run, origins: t.origins, budgets: [] }
		Err(OverBudget(t)) => t
	}
	if Str.inspect(traced.run) != Str.inspect(ltr) or traced.origins.len() != ltr.glyphs.len() {
		crash "a traced run differs from the run, or its origins are not index-aligned"
	}
	if Str.inspect(Font.shape_traced(font, plan, text)) != Str.inspect(traced_result) {
		crash "tracing the same text twice gave different results"
	}
	checked_budgets = match Font.shape_checked(font, plan, text) {
		Ok(run) => {
			if Str.inspect(run) != Str.inspect(ltr) {
				crash "a checked run differs from the run"
			}
			[]
		}
		Err(OverBudget({ run, budgets })) => {
			if Str.inspect(run) != Str.inspect(ltr) or budgets.is_empty() {
				crash "an over-budget run differs from the run, or names no bound"
			}
			budgets
		}
	}
	if Str.inspect(checked_budgets) != Str.inspect(traced.budgets) {
		crash "traced and checked shaping name different bounds"
	}
	rtl = Font.shape(font, text, Font.ShapeOptions.{ direction: RightToLeft, script: "Hebr" })
	check_run!(n, rtl, True)
	latin_rtl = Font.shape(font, text, Font.ShapeOptions.{ direction: RightToLeft })
	check_run!(n, latin_rtl, True)
	# Script and language tags: one of a few real ones, and the text's
	# first bytes as a language tag, so arbitrary tags plan totally and
	# deterministically.
	scripts = ["", "Latn", "Arab", "Deva", "Mymr", "Hant", "Zzzz", "12"]
	languages = ["", "en", "tr", "zh-Hant-HK", "sr-Latn", "x-hbotABC", "fr-x-hbscgrek", "el-polyton"]
	script = scripts.get(n % scripts.len()) ?? ""
	language = languages.get((n // 8) % languages.len()) ?? ""
	raw_language = Str.from_utf8_lossy(split.text.take_first(16))
	for chosen in [language, raw_language] {
		tagged = Font.ShapeOptions.{ script, language: chosen, direction: LeftToRight }
		tagged_run = Font.shape(font, text, tagged)
		check_run!(n, tagged_run, False)
		if Str.inspect(tagged_run) != Str.inspect(Font.shape_planned(font, Font.plan(font, tagged), text)) {
			crash "shaping with a script and language is not deterministic"
		}
	}
	half = n // 2
	ranged = Font.shape(font, text, Font.ShapeOptions.{ features: [Font.Feature.{ tag: "liga", value: 0, end: half }, Font.Feature.{ tag: "kern", value: 0, start: half }, Font.Feature.{ tag: "smcp" }] })
	check_run!(n, ranged, False)
	measured = Font.width(font, text)
	total = ltr.advances.fold(0.I64, |sum, a| sum + a.x.to_i64())
	if measured.to_i64() != total.max(-2147483648).min(2147483647) {
		crash "the width is not the sum of the advances"
	}
	scaling!(font, repeated(text, 2), repeated(text, 16))
	Fuzz.keep
}

## Inter Regular as a metrics-only file (a test fixture, SIL Open Font
## License 1.1).
inter : Font
inter = Font.from_bytes(inter_file, Font.ReadOptions.{}) ?? crash "the Inter test font could not be read"

## A run's lists are index-aligned, its clusters lie inside the text and
## run in order (backwards for right-to-left), and it grew within bounds.
check_run! : U64, Font.Run, Bool => {}
check_run! = |bytes, run, rtl| {
	n = run.glyphs.len()
	if run.advances.len() != n or run.offsets.len() != n or run.clusters.len() != n or run.flags.len() != n {
		crash "a run's lists are not index-aligned"
	}
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
	# the font does not map, so it is never set on another glyph.
	if !run.flags.all(|f| f <= 3) or run.flags.map2(run.glyphs, |f, g| f.bitwise_and(2) != 0 and g != 0).any(|bad| bad) {
		crash "a flag other than unsafe-to-break or missing is set, or missing on a real glyph"
	}
}

split_at_marker : List(U8) -> { text : List(U8), font : List(U8) }
split_at_marker = |bytes| {
	var $i = 0
	while $i < bytes.len() and (bytes.get($i) ?? 0) != 0xFF {
		$i = $i + 1
	}
	{ text: bytes.take_first($i), font: bytes.drop_first($i + 1) }
}

## Scalars of valid UTF-8 with the byte offset each starts at.
decode : List(U8) -> List({ scalar : U32, offset : U64 })
decode = |bytes| {
	var $out = []
	var $i = 0
	while $i < bytes.len() {
		b = (bytes.get($i) ?? 0).to_u32()
		len = if (b < 0x80) 1 else if (b < 0xE0) 2 else if (b < 0xF0) 3 else 4
		var $cp = if (len == 1) b else if (len == 2) b.bitwise_and(0x1F) else if (len == 3) b.bitwise_and(0x0F) else b.bitwise_and(0x07)
		for k in 1..<len {
			$cp = $cp.shl_wrap(6).bitwise_or((bytes.get($i + k) ?? 0).to_u32().bitwise_and(0x3F))
		}
		$out = $out.append({ scalar: $cp, offset: $i })
		$i = $i + len
	}
	$out
}

## Up to 64 bytes' worth of the text, repeated.
repeated : Str, U64 -> Str
repeated = |text, copies| {
	piece = Str.from_utf8_lossy(text.to_utf8().take_first(64))
	Str.join_with(List.repeat(piece, copies), " ")
}

## Shaping 8 times the text costs about 8 times the allocations, and frees
## them all.
scaling! : Font, Str, Str => {}
scaling! = |font, small, large| {
	small_cost = Fuzz.measure_allocs!(|{}| Font.width(font, small))
	large_cost = Fuzz.measure_allocs!(|{}| Font.width(font, large))
	Fuzz.expect_no_leaks!(|{}| Font.width(font, large))
	if large_cost.allocations > 10 * small_cost.allocations + 256 {
		crash "shaping 8 times the text took ${large_cost.allocations.to_str()} allocations, against ${small_cost.allocations.to_str()}"
	}
}

target = Fuzz.target_with!({
	name: "font-shape",
	generator: Fuzz.raw_bytes,
	test!,
	show: |bytes| Str.inspect(Str.from_utf8_lossy(split_at_marker(bytes).text)),
})
