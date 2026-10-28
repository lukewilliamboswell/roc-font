app [target] {
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}
import fuzz.Fuzz
import font.Font
import "../tests/fonts/shaping/tibetan/Jomolhari-Regular.ttf" as tibt_bytes : List(U8)
import "../tests/fonts/shaping/tibetan/NotoSerifTibetan[wght].ttf" as tibt_serif_bytes : List(U8)
import "../tests/fonts/shaping/use-sinhala/UseSinhSans.ttf" as sinh_bytes : List(U8)
import "../tests/fonts/shaping/use-sinhala/UseSinhSerif.ttf" as sinh_serif_bytes : List(U8)
import "../tests/fonts/shaping/use-joining/UseNKoSans.ttf" as nko_bytes : List(U8)
import "../tests/fonts/shaping/use-joining/UseNKoUnjoined.ttf" as nko_unjoined_bytes : List(U8)
import "../tests/fonts/shaping/use-joining/UseMongolianSans.ttf" as mong_bytes : List(U8)
import "../tests/fonts/shaping/use-joining/UseAdlamSans.ttf" as adlm_bytes : List(U8)
import "../tests/fonts/shaping/use-joining/UseAdlamDisplay.ttf" as adlm_display_bytes : List(U8)

# Actual USE model contracts in five scripts and nine real OFL families.
# First byte chooses script/family and literal-vs-category-stream input.
# Covers filtering, joining, syllables, reordering, per-call context,
# flags, hard budgets and isolated two-size query allocations.
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	selector = (bytes.first() ?? 0).to_u64()
	profile = selector % 5
	family = (selector // 5) % 2
	font = font_for(profile, family)
	script = ["Tibt", "Sinh", "Nkoo", "Mong", "Adlm"].get(profile) ?? "Tibt"
	parts = parts_for(profile)
	text = if (selector // 10) % 2 == 0 {
		Str.from_utf8_lossy(bytes.drop_first(1))
	} else {
		Str.join_with(bytes.drop_first(1).take_first(512).map(|b| parts.get(b.to_u64() % parts.len()) ?? ""), "")
	}
	for rtl in [False, True] {
		direction = if rtl {
			RightToLeft
		} else {
			LeftToRight
		}
		features = if selector.bitwise_and(64) == 0 {
			[]
		} else {
			[Font.Feature.{ tag: "rphf", value: 0 }, Font.Feature.{ tag: "init", value: 0 }, Font.Feature.{ tag: "medi", value: 0 }]
		}
		options = Font.ShapeOptions.{ script, direction, features }
		plan = Font.plan(font, options)
		run = Font.shape_planned(font, plan, text)
		check_run!(font, text, run, rtl)
		if Str.inspect(run) != Str.inspect(Font.shape(font, text, options)) or Str.inspect(run) != Str.inspect(Font.shape_planned(font, plan, text)) {
			crash "USE planned/direct output is not deterministic"
		}
		match Font.shape_checked(font, plan, text) {
			Ok(value) => if Str.inspect(value) != Str.inspect(run) {
				crash "USE checked result differs"
			}
			Err(OverBudget(value)) => if value.budgets.is_empty() or Str.inspect(value.run) != Str.inspect(run) {
				crash "USE budget result differs"
			}
		}
		traced = match Font.shape_traced(font, plan, text) {
			Ok(value) => { run: value.run, origins: value.origins }
			Err(OverBudget(value)) => { run: value.run, origins: value.origins }
		}
		if Str.inspect(traced.run) != Str.inspect(run) or traced.origins.len() != run.glyphs.len() {
			crash "USE trace is not aligned"
		}
		n = text.to_utf8().len()
		range = Font.TextRange.{ start: n // 3, end: n - n // 3 }
		selected = Font.shape_range(font, plan, text, range)
		if Str.inspect(selected) != Str.inspect(Font.shape_range(font, plan, text, range)) {
			crash "USE paragraph context is not deterministic"
		}
		check_run!(font, text, selected, rtl)
		if !selected.clusters.all(|cluster| cluster >= n // 3 and cluster < n - n // 3) {
			crash "USE emitted paragraph context glyphs"
		}
		limited_plan = Font.plan(font, Font.ShapeOptions.{ script, direction, limits: Font.ShapeLimits.{ operations: 0, growth: 0 } })
		result = Font.shape_checked(font, limited_plan, text)
		if Str.inspect(result) != Str.inspect(Font.shape_checked(font, limited_plan, text)) {
			crash "USE tight budget is not deterministic"
		}
		limited = match result {
			Ok(value) => value
			Err(OverBudget(value)) => value.run
		}
		check_run!(font, text, limited, rtl)
	}
	# Runtime input keeps both generated sizes from being precomputed.
	fragment = Str.from_utf8_lossy(text.to_utf8().take_first(12))
	piece = (sample_for(profile)).concat(fragment)
	small = Str.join_with(List.repeat(piece, 16), "")
	large = Str.join_with(List.repeat(piece, 128), "")
	plan = Font.plan(font, Font.ShapeOptions.{ script })
	small_cost = Fuzz.measure_allocs!(|{}| checksum(Font.shape_planned(font, plan, small)))
	large_cost = Fuzz.measure_allocs!(|{}| checksum(Font.shape_planned(font, plan, large)))
	Fuzz.expect_no_leaks!(|{}| checksum(Font.shape_planned(font, plan, large)))
	if large_cost.allocations > 10 * small_cost.allocations + 256 {
		crash "USE allocation scaling exceeds input growth"
	}
	Fuzz.keep
}

read : List(U8) -> Font
read = |bytes| match Font.from_bytes(bytes, Font.ReadOptions.{}) {
	Ok(font) => font
	Err(problems) => crash Str.inspect(problems)
}

tibt : Font
tibt = read(tibt_bytes)

tibt_serif : Font
tibt_serif = read(tibt_serif_bytes)

sinh : Font
sinh = read(sinh_bytes)

sinh_serif : Font
sinh_serif = read(sinh_serif_bytes)

nko : Font
nko = read(nko_bytes)

nko_unjoined : Font
nko_unjoined = read(nko_unjoined_bytes)

mong : Font
mong = read(mong_bytes)

adlm : Font
adlm = read(adlm_bytes)

adlm_display : Font
adlm_display = read(adlm_display_bytes)

font_for : U64, U64 -> Font
font_for = |profile, family| match profile {
	0 => if family == 0 {
		tibt
	} else {
		tibt_serif
	}
	1 => if family == 0 {
		sinh
	} else {
		sinh_serif
	}
	2 => if family == 0 {
		nko
	} else {
		nko_unjoined
	}
	3 => mong
	_ => if family == 0 {
		adlm
	} else {
		adlm_display
	}
}

sample_for : U64 -> Str
sample_for = |profile| match profile {
	0 => "བོད་སྐད་"
	1 => "ශ්‍රී ලංකා "
	2 => "ߒߞߏ "
	3 => "ᠮᠣᠩᠭᠣᠯ "
	_ => "𞤀𞤣𞤤𞤢𞤥 "
}

parts_for : U64 -> List(Str)
parts_for = |profile| match profile {
	0 => ["ཀ", "ཁ", "ག", "བ", "མ", "ཡ", "ར", "ྐ", "ྑ", "ྒ", "ྱ", "ྲ", "ྭ", "ཱ", "ི", "ུ", "ེ", "ོ", "ྀ", "྄", "ཾ", "ཿ", "་", "།", "͏", "‌", "‍", "◌", " "]
	1 => ["අ", "ආ", "ඇ", "ක", "ග", "න", "ම", "ර", "ය", "්", "ා", "ි", "ී", "ු", "ූ", "ෙ", "ේ", "ෛ", "ො", "ෝ", "ෞ", "ං", "ඃ", "ෟ", "ෲ", "͏", "‌", "‍", "◌", " "]
	2 => ["ߊ", "ߋ", "ߌ", "ߍ", "ߎ", "ߏ", "ߒ", "ߞ", "߳", "߫", "߬", "߭", "߮", "߯", "߰", "߱", "߲", "ߺ", "͏", "‌", "‍", "◌", " "]
	3 => ["ᠠ", "ᠡ", "ᠢ", "ᠣ", "ᠤ", "ᠥ", "ᠦ", "ᠨ", "ᠮ", "ᠭ", "ᠷ", "ᠰ", "᠋", "᠌", "᠍", "᠏", "᠎", " ", "͏", "‌", "‍", "◌", " "]
	_ => ["𞤀", "𞤢", "𞤣", "𞤤", "𞤥", "𞥄", "𞥅", "𞥆", "𞥇", "𞥈", "𞥉", "𞥊", "͏", "‌", "‍", "◌", " "]
}

checksum : Font.Run -> U64
checksum = |run| {
	var $sum = 0.U64
	for i in 0..<run.glyphs.len() {
		advance = run.advances.get(i) ?? { x: 0, y: 0 }
		offset = run.offsets.get(i) ?? { x: 0, y: 0 }
		$sum = $sum.plus_wrap((run.glyphs.get(i) ?? 0).to_u64()).plus_wrap(run.clusters.get(i) ?? 0).plus_wrap((run.flags.get(i) ?? 0).to_u64()).plus_wrap(advance.x.to_i64().to_u64_wrap()).plus_wrap(advance.y.to_i64().to_u64_wrap()).plus_wrap(offset.x.to_i64().to_u64_wrap()).plus_wrap(offset.y.to_i64().to_u64_wrap())
	}
	$sum
}

check_run! : Font, Str, Font.Run, Bool => {}
check_run! = |font, text, run, rtl| {
	bytes = text.to_utf8()
	scalar_count = bytes.keep_if(|byte| byte.bitwise_and(0xC0) != 0x80).len()
	n = run.glyphs.len()
	if run.advances.len() != n or run.offsets.len() != n or run.clusters.len() != n or run.flags.len() != n {
		crash "USE output is not index aligned"
	}
	if n > (64 * scalar_count).max(16384) {
		crash "USE growth exceeds the scalar budget"
	}
	if !run.glyphs.all(|glyph| glyph < Font.glyph_count(font)) {
		crash "USE output references a glyph outside the font"
	}
	if !run.clusters.all(|cluster| cluster < bytes.len()) {
		crash "USE cluster escaped original text"
	}
	var $i = 1
	while $i < n {
		a = run.clusters.get($i - 1) ?? 0
		b = run.clusters.get($i) ?? 0
		if if rtl {
			a < b
		} else {
			a > b
		} {
			crash "USE clusters are not monotone"
		}
		$i = $i + 1
	}
	if !run.flags.all(|flag| flag <= 3) {
		crash "USE flags expose private metadata"
	}
}

target = Fuzz.target_with!({ name: "font-use", generator: Fuzz.raw_bytes, test!, show: Str.inspect })
