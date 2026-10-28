import font.Font
import "../fonts/color-images/images.ttf" as fixture : List(U8)
import "../fonts/color-images/vertical.ttf" as vertical_fixture : List(U8)
import "../fonts/color-images/emoji-subset.ttf" as real_fixture : List(U8)
import "../fonts/color-images/bad-svg-range.ttf" as bad_svg_range : List(U8)
import "../fonts/color-images/bad-svg-offset.ttf" as bad_svg_offset : List(U8)
import "../fonts/color-images/bad-sbix-reference.ttf" as bad_sbix_reference : List(U8)
import "../fonts/color-images/bad-sbix-cycle.ttf" as bad_sbix_cycle : List(U8)
import "../fonts/color-images/bad-cblc-offset.ttf" as bad_cblc_offset : List(U8)
import "../fonts/color-images/bad-cbdt-length.ttf" as bad_cbdt_length : List(U8)
import "../fonts/color-images/multiple-bad.ttf" as multiple_bad : List(U8)
import "../fonts/color-images/cbdt-alone.ttf" as cbdt_alone : List(U8)
import "../fonts/color-images/cblc-alone.ttf" as cblc_alone : List(U8)

## Structural font-data access only. Full encoded payloads, native pixel
## metrics and actual emoji shape results are independently replayed by
## tests/fonts/color-images/verify.py against cached fontTools/HB records.
ColorImageTests :: {}.{}

read_or_crash = |bytes| match Font.from_bytes(bytes, Font.ReadOptions.{}) {
	Ok(font) => font
	Err(problems) => crash Str.inspect(problems)
}

font : Font
font = read_or_crash(fixture)
expect Font.dropped(font) == [] and Font.bitmap_strikes(font).len() == 7
expect Font.bitmap_strikes(font).take_first(2) == [Sbix({ ppem: 16, ppi: 72, draw_outlines: True }), Sbix({ ppem: 32, ppi: 72, draw_outlines: True })]
expect match Font.svg_glyph(font, 1) {
	Present(doc) => doc.encoding == Utf8 and doc.first_glyph == 1 and doc.last_glyph == 2 and Str.from_utf8(doc.bytes) == Ok("<svg xmlns=\"http://www.w3.org/2000/svg\"><rect id=\"glyph1\" width=\"10\" height=\"20\" fill=\"red\"/></svg>")
	Absent => False
}
expect match Font.svg_glyph(font, 3) {
	Present(doc) => doc.encoding == Gzip and doc.bytes.take_first(3) == [0x1F, 0x8B, 8]
	Absent => False
}
expect match (Font.svg_glyph(font, 1), Font.svg_glyph(font, 6)) {
	(Present(a), Present(b)) => a.bytes == b.bytes and b.first_glyph == 6 and b.last_glyph == 6
	_ => False
}
expect Font.svg_glyph(font, 0) == Absent and Font.svg_glyph(font, 0xFFFFFFFF) == Absent
expect match (Font.bitmap_glyph(font, 1, 0), Font.bitmap_glyph(font, 2, 0), Font.bitmap_glyph(font, 3, 0)) {
	(Present(a), Present(b), Present(c)) => a == b and b == c and a.format == Png and a.placement == Sbix({ origin_x: 2, origin_y: -3, source_glyph: 1 })
	_ => False
}
expect [4.U32, 5, 6, 7].map(
	|g| match Font.bitmap_glyph(font, g, 0) {
		Present(image) => image.format
		Absent => Other(0)
	},
) == [Jpeg, Tiff, Pdf, Mask]
expect Font.bitmap_glyph(font, 0, 0) == Absent and Font.bitmap_glyph(font, 1, 1000) == Absent and Font.bitmap_glyph(font, 0xFFFFFFFF, 0) == Absent
expect match Font.bitmap_glyph(font, 1, 2) {
	Present(image) => image.format == Png and image.placement == Bitmap({ width: 1, height: 1, horizontal: Present({ bearing_x: -2, bearing_y: 4, advance: 7 }), vertical: Absent }) and Font.advance(font, 1) == 600
	Absent => False
}
expect match (Font.bitmap_glyph(font, 1, 3), Font.bitmap_glyph(font, 1, 4), Font.bitmap_glyph(font, 1, 6)) {
	(Present(a), Present(b), Present(c)) => a == b and b == c and a.placement == Bitmap({ width: 1, height: 1, horizontal: Present({ bearing_x: -2, bearing_y: 4, advance: 7 }), vertical: Present({ bearing_x: -3, bearing_y: 5, advance: 8 }) })
	_ => False
}
expect Font.bitmap_glyph(font, 2, 5) == Absent and Font.bitmap_glyph(font, 2, 6) == Absent
expect match Font.bitmap_glyph(read_or_crash(vertical_fixture), 1, 2) {
	Present(image) => image.placement == Bitmap({ width: 1, height: 1, horizontal: Absent, vertical: Present({ bearing_x: 4, bearing_y: -2, advance: 7 }) })
	Absent => False
}

# Missing optional image tables are ordinary absence, without changing
# the three built-in fonts or inventing a fallback image.
expect [Font.sans, Font.serif, Font.mono].all(|plain| Font.bitmap_strikes(plain) == [] and Font.svg_glyph(plain, 1) == Absent and Font.bitmap_glyph(plain, 1, 0) == Absent)

# Lenient reading drops the whole broken optional table (or bitmap pair)
# and reports it. Independent problems aggregate; strict reading rejects.
check_bad = |bytes, tag| match Font.from_bytes(bytes, Font.ReadOptions.{}) {
	Ok(read) => Font.dropped(read).any(
		|problem| match problem {
			BadTable({ table, .. }) => table == tag
			_ => False
		},
	) and match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
		Err(_) => True
		Ok(_) => False
	}
	Err(_) => False
}
expect check_bad(bad_svg_range, "SVG ") and check_bad(bad_svg_offset, "SVG ")
expect check_bad(bad_sbix_reference, "sbix") and check_bad(bad_sbix_cycle, "sbix")
expect check_bad(bad_cblc_offset, "CBLC") and check_bad(bad_cbdt_length, "CBDT")
expect check_bad(cbdt_alone, "CBDT") and check_bad(cblc_alone, "CBLC")
expect match Font.from_bytes(multiple_bad, Font.ReadOptions.{}) {
	Ok(read) => Font.dropped(read).len() == 2 and Font.bitmap_strikes(read).len() == 5
	Err(_) => False
}

# Actual freely licensed bitmap emoji: shaping chooses the ligature or
# variation glyph, then its image comes from the caller-selected strike.
# These IDs/advances are cached HarfBuzz14.6 results, not guesses by Unicode.
expect {
	emoji = read_or_crash(real_fixture)
	[("👩‍💻", 15.U32), ("❤️", 2), ("👍🏽", 13), ("🇦🇺", 11), ("😀", 9)].all(
		|(text, wanted)| {
			run = Font.shape(emoji, text, Font.ShapeOptions.{})
			run.glyphs == [wanted] and run.clusters == [0] and run.advances == [{ x: 2550, y: 0 }] and match Font.bitmap_glyph(emoji, wanted, 0) {
				Present(image) => image.format == Png and image.bytes.take_first(8) == [0x89, 80, 78, 71, 13, 10, 26, 10]
				Absent => False
			}
		},
	)
}
