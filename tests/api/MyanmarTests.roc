import font.Font
import "../fonts/shaping/myanmar/NotoSansMyanmar-Regular.ttf" as sans_file : List(U8)
import "../fonts/shaping/myanmar/NotoSerifMyanmar-Regular.ttf" as serif_file : List(U8)
import "../fonts/shaping/myanmar/modern.ttf" as modern_file : List(U8)
import "../fonts/shaping/myanmar/legacy.ttf" as legacy_file : List(U8)
import "../fonts/shaping/myanmar/no-circle.ttf" as no_circle_file : List(U8)

## Modern Myanmar through the public package. Exact glyphs, positions and
## flags for the full two-family matrix replay through the native driver.
MyanmarTests :: {}.{}

read = |bytes| match Font.from_bytes(bytes, Font.ReadOptions.{}) {
	Ok(font) => font
	Err(ps) => crash Str.inspect(ps)
}

modern = read(modern_file)

legacy = read(legacy_file)

no_circle = read(no_circle_file)

options = Font.ShapeOptions.{ script: "Mymr", language: "my" }
expect {
	run = Font.shape(modern, "ကေ", options)
	run.glyphs == [5, 19] and run.advances == [{ x: 0, y: 0 }, { x: 500, y: 0 }] and run.offsets == [{ x: -500, y: 0 }, { x: 0, y: 0 }] and run.clusters == [0, 0]
}
expect {
	# A legacy mymr-selected font uses the default model, preserving order
	# and leaving the modern-only feature chain disabled.
	run = Font.shape(legacy, "ကေ", options)
	run.glyphs == [1, 5] and run.advances == [{ x: 500, y: 0 }, { x: 0, y: 0 }] and run.offsets == [{ x: 0, y: 0 }, { x: -500, y: 0 }]
}
expect {
	run = Font.shape(modern, "ကေ", Font.ShapeOptions.{ script: "Mymr", features: [Font.Feature.{ tag: "pref", value: 0 }] })
	run.glyphs == [5, 12]
}
expect Font.shape(modern, "ြ", options).glyphs == [7, 10]
expect Font.shape(no_circle, "ြ", options).glyphs == [7]
expect {
	font = read(sans_file)
	run = Font.shape(font, "မြန်မာ", options)
	run.glyphs == [47, 29, 24, 381, 29, 368] and run.clusters == [0, 0, 6, 6, 12, 12] and run.advances == [{ x: 229, y: 0 }, { x: 676, y: 0 }, { x: 570, y: 0 }, { x: 0, y: 0 }, { x: 676, y: 0 }, { x: 455, y: 0 }] and run.offsets == [{ x: 0, y: 0 }, { x: 0, y: 0 }, { x: 0, y: 0 }, { x: 43, y: 0 }, { x: 0, y: 0 }, { x: 0, y: 0 }]
}
expect {
	font = read(sans_file)
	run = Font.shape(font, "င်္က", options)
	run.glyphs == [4, 189] and run.clusters == [0, 0] and run.offsets == [{ x: 0, y: 0 }, { x: -1, y: 0 }]
}

expect {
	[read(sans_file), read(serif_file), modern, legacy, no_circle].all(
		|font| {
			["", "င်္ကြေ", "ေ", "ကေ\u(FE00)ေ\u(FE01)", "က္\u(200D)က", "က္\u(200C)က"].all(
				|text| {
					[LeftToRight, RightToLeft].all(
						|direction| {
							settings = Font.ShapeOptions.{ script: "Mymr", direction }
							run = Font.shape(font, text, settings)
							again = Font.shape(font, text, settings)
							n = run.glyphs.len()
							run == again and n == run.advances.len() and n == run.offsets.len() and n == run.clusters.len() and n == run.flags.len() and run.clusters.all(|at| at < text.to_utf8().len())
						},
					)
				},
			)
		},
	)
}
