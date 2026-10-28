import font.Font
import "../fonts/graphite-geometry/child-advance/child-advance-x1000-a0-ltr.ttf" as zero_file : List(U8)
import "../fonts/graphite-geometry/child-advance/child-advance-x1000-a1-ltr.ttf" as positive_file : List(U8)
import "../fonts/graphite-geometry/child-advance/child-advance-x-1000-a0-ltr.ttf" as left_file : List(U8)
import "../fonts/graphite-geometry/glat-flags/glat3-flag0-header0.ttf" as no_boxes_file : List(U8)
import "../fonts/graphite/Charis5_eursub.ttf" as charis_file : List(U8)

## Public regression cases independently pinned by original Graphite2
## programs, real Charis and direct HarfBuzz glyph-run oracle records.
GraphiteGeometryTests :: {}.{}

read = |bytes| match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
	Ok(font) => font
	Err(problems) => crash Str.inspect(problems)
}

shape = |bytes, text| Font.shape(read(bytes), text, Font.ShapeOptions.{ script: "Latn", direction: LeftToRight })

expect {
	run = shape(zero_file, "ab")
	run.advances == [{ x: 0, y: 0 }, { x: 602, y: 0 }] and run.offsets == [{ x: 1000, y: 170 }, { x: 0, y: 0 }]
}
expect {
	run = shape(positive_file, "ab")
	run.advances == [{ x: 0, y: 0 }, { x: 1001, y: 0 }] and run.offsets == [{ x: 1000, y: 170 }, { x: 0, y: 0 }]
}
expect {
	run = shape(left_file, "ab")
	run.advances == [{ x: 1000, y: 0 }, { x: 602, y: 0 }] and run.offsets == [{ x: 0, y: 170 }, { x: 0, y: 0 }]
}
expect {
	run = shape(charis_file, "a\u(0301)")
	run.glyphs == [68, 634] and run.advances == [{ x: 1042, y: 0 }, { x: 0, y: 0 }] and run.offsets == [{ x: 0, y: 0 }, { x: 25, y: 0 }] and run.clusters == [0, 0]
}
expect {
	# The documented Glat3 flag0 layout has no octabox prefix. fontTools
	# independently decodes attribute1=1. This valid font deliberately
	# differs from Graphite2 1.3.14's unconditional-header interpretation.
	font = read(no_boxes_file)
	plan = Font.plan(font, Font.ShapeOptions.{ script: "Latn", direction: LeftToRight })
	run = Font.shape_planned(font, plan, "ab")
	Font.shaping_engine(plan) == Graphite and run.advances == [{ x: 1, y: 0 }, { x: 602, y: 0 }]
}
