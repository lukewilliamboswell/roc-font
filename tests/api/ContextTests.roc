import font.Font
import "../fonts/shaping/arabic/NotoSansArabic-Regular.ttf" as arabic_file : List(U8)

## Selected text keeps original offsets and receives unshaped paragraph
## context. Cached HarfBuzz range cases are replayed by the native driver.
ContextTests :: {}.{}

expect {
	plan = Font.plan(Font.sans, Font.ShapeOptions.{})
	text = "office AV"
	Font.shape_range(Font.sans, plan, text, Font.TextRange.{}) == Font.shape_planned(Font.sans, plan, text)
}

expect {
	plan = Font.plan(Font.sans, Font.ShapeOptions.{})
	run = Font.shape_range(Font.sans, plan, "éA", Font.TextRange.{ start: 1, end: 3 })
	run.glyphs == [Font.glyph(Font.sans, 'A') ?? 0] and run.clusters == [2]
}

expect {
	plan = Font.plan(Font.sans, Font.ShapeOptions.{})
	[Font.TextRange.{ start: 9, end: 1 }, Font.TextRange.{ start: 99 }, Font.TextRange.{ end: 0 }].all(|range|
		Font.shape_range(Font.sans, plan, "éA", range).glyphs.is_empty())
}

expect {
	font = match Font.from_bytes(arabic_file, Font.ReadOptions.{}) {
		Ok(value) => value
		Err(problems) => crash Str.inspect(problems)
	}
	plan = Font.plan(font, Font.ShapeOptions.{ script: "Arab", direction: RightToLeft })
	middle = Font.shape_range(font, plan, "ببب", Font.TextRange.{ start: 2, end: 4 })
	isolated = Font.shape_planned(font, plan, "ب")
	# Noto separates the dot from the letter; both glyphs retain the
	# selected letter's original paragraph cluster (HB 14.6 cached oracle).
	middle.glyphs == [316, 16] and middle.glyphs != isolated.glyphs and middle.clusters == [2, 2] and middle.advances == [{ x: 0, y: 0 }, { x: 343, y: 0 }] and middle.offsets == [{ x: 94, y: -3 }, { x: 0, y: 0 }] and Font.shape_range_checked(font, plan, "ببب", Font.TextRange.{ start: 2, end: 4 }) == Ok(middle)
}
