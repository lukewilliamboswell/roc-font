import font.Font
import "../fonts/vertical/metrics.ttf" as metrics : List(U8)
import "../fonts/vertical/fallback.ttf" as fallback : List(U8)
import "../fonts/vertical/gpos.ttf" as positioning : List(U8)
import "../fonts/vertical/variable.ttf" as variable : List(U8)
import "../fonts/vertical/cff2-vvar.otf" as cff_variable : List(U8)
import "../fonts/vertical/ttf-vorg.ttf" as ignored_vorg : List(U8)
import "../fonts/vertical/lang-vert.ttf" as language_vert : List(U8)
import "../fonts/vertical/gpos-selected-vert.ttf" as gpos_vert : List(U8)

## Vertical font facts and positioned runs through the served public package.
VerticalTests :: {}.{}

expect {
	font = Font.from_bytes(metrics, Font.ReadOptions.{}) ?? crash "valid vertical fixture"
	Font.vertical_advance(font, 2) == 1200 and Font.vertical_origin(font, 2) == { x: 300, y: 750 } and Font.vertical_advance(font, 999) == 0
}

expect {
	font = Font.from_bytes(metrics, Font.ReadOptions.{}) ?? crash "valid vertical fixture"
	run = Font.shape(font, "ab", Font.ShapeOptions.{ script: "Latn", direction: TopToBottom })
	run.glyphs == [2, 3] and run.clusters == [0, 1] and run.advances == [{ x: 0, y: -1200 }, { x: 0, y: -1000 }] and run.offsets == [{ x: -300, y: -750 }, { x: -250, y: -700 }]
}

expect {
	font = Font.from_bytes(metrics, Font.ReadOptions.{}) ?? crash "valid vertical fixture"
	run = Font.shape(font, "ab", Font.ShapeOptions.{ script: "Latn", direction: BottomToTop })
	run.glyphs == [3, 2] and run.clusters == [1, 0] and run.advances == [{ x: 0, y: -1000 }, { x: 0, y: -1200 }] and run.offsets == [{ x: -250, y: -700 }, { x: -300, y: -750 }]
}

expect {
	font = Font.from_bytes(fallback, Font.ReadOptions.{}) ?? crash "valid synthetic metrics fixture"
	run = Font.shape(font, "ab", Font.ShapeOptions.{ script: "Latn", direction: TopToBottom })
	run.advances == [{ x: 0, y: -1000 }, { x: 0, y: -1000 }] and run.offsets == [{ x: -300, y: -850 }, { x: -250, y: -850 }]
}

expect {
	font = Font.from_bytes(positioning, Font.ReadOptions.{}) ?? crash "valid vertical positioning fixture"
	run = Font.shape(font, "ab", Font.ShapeOptions.{ script: "Hani", direction: TopToBottom })
	run.glyphs == [23, 24] and run.advances == [{ x: 0, y: -1000 }, { x: 0, y: -1000 }]
}

expect {
	font = Font.from_bytes(variable, Font.ReadOptions.{}) ?? crash "valid vertical variation fixture"
	bold = Font.at(font, Font.Variation.{ axes: [{ tag: "wght", value: 900 }] })
	run = Font.shape(bold, "abca", Font.ShapeOptions.{ script: "Latn", direction: TopToBottom })
	Font.vertical_advance(bold, 2) == 1320 and run.advances == [{ x: 0, y: -1320 }, { x: 0, y: -1130 }, { x: 0, y: -1140 }, { x: 0, y: -1320 }]
}

expect {
	font = Font.from_bytes(positioning, Font.ReadOptions.{}) ?? crash "valid vertical positioning fixture"
	run = Font.shape(font, "ab", Font.ShapeOptions.{ script: "Hani", direction: TopToBottom, features: [Font.Feature.{ tag: "vkrn" }] })
	run.advances == [{ x: 0, y: -1090 }, { x: 0, y: -1000 }] and run.offsets == [{ x: -239, y: -687 }, { x: -250, y: -700 }]
}

expect {
	font = Font.from_bytes(fallback, Font.ReadOptions.{}) ?? crash "valid empty glyph fallback fixture"
	Font.vertical_origin(font, 1) == { x: 250, y: 500 }
}

expect {
	font = Font.from_bytes(cff_variable, Font.ReadOptions.{}) ?? crash "valid CFF vertical origin variation fixture"
	bold = Font.at(font, Font.Variation.{ axes: [{ tag: "wght", value: 900 }] })
	Font.vertical_origin(bold, 2) == { x: 300, y: 970 } and Font.vertical_advance(bold, 2) == 1320
}

expect {
	font = Font.from_bytes(ignored_vorg, Font.ReadOptions.{}) ?? crash "valid TrueType VORG policy fixture"
	# The specification requires ignoring VORG with TrueType outlines.
	Font.vertical_origin(font, 2) == { x: 300, y: 750 }
}

expect {
	font = Font.from_bytes(positioning, Font.ReadOptions.{}) ?? crash "valid vertical trace fixture"
	plan = Font.plan(font, Font.ShapeOptions.{ script: "Hani", direction: BottomToTop })
	match Font.shape_traced(font, plan, "ab") {
		Ok(result) => result.run.glyphs == [24, 23] and result.run.clusters == [1, 0] and result.origins == [Substituted({ feature: "vert" }), Substituted({ feature: "vert" })] and Font.shape_checked(font, plan, "ab") == Ok(result.run)
		Err(_) => False
	}
}

expect {
	font = Font.from_bytes(language_vert, Font.ReadOptions.{}) ?? crash "valid duplicate vertical feature fixture"
	Font.shape(font, "a", Font.ShapeOptions.{ script: "Hani", direction: TopToBottom }).glyphs == [24] and Font.shape(font, "a", Font.ShapeOptions.{ script: "Latn", direction: TopToBottom }).glyphs == [23]
}

expect {
	font = Font.from_bytes(gpos_vert, Font.ReadOptions.{}) ?? crash "valid GPOS vertical feature fixture"
	run = Font.shape(font, "a", Font.ShapeOptions.{ script: "Hani", direction: TopToBottom })
	run.glyphs == [2] and run.offsets == [{ x: -289, y: -737 }] and run.advances == [{ x: 0, y: -1200 }] and Font.shape(font, "a（）", Font.ShapeOptions.{ script: "Hani", direction: TopToBottom }).glyphs == [2, 14, 15]
}
