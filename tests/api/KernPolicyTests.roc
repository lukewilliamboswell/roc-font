import font.Font
import "../fonts/shaping/kern-policy/legacy-only.ttf" as legacy : List(U8)
import "../fonts/shaping/kern-policy/gpos-dist.ttf" as distance : List(U8)
import "../fonts/shaping/kern-policy/gpos-kern.ttf" as positioning : List(U8)

## A script can suppress legacy kerning while retaining font positioning.
KernPolicyTests :: {}.{}

expect {
	font = Font.from_bytes(legacy, Font.ReadOptions.{}) ?? crash "valid legacy fixture"
	run = Font.shape(font, "..", Font.ShapeOptions.{ script: "Deva" })
	run.glyphs == [1, 1] and run.clusters == [0, 1] and run.advances == [{ x: 100, y: 0 }, { x: 100, y: 0 }] and run.offsets == [{ x: 0, y: 0 }, { x: 0, y: 0 }]
}

expect {
	font = Font.from_bytes(legacy, Font.ReadOptions.{}) ?? crash "valid legacy fixture"
	run = Font.shape(font, "..", Font.ShapeOptions.{ script: "Latn" })
	run.advances == [{ x: 350, y: 0 }, { x: 350, y: 0 }] and run.offsets == [{ x: 0, y: 0 }, { x: 250, y: 0 }]
}

expect {
	font = Font.from_bytes(distance, Font.ReadOptions.{}) ?? crash "valid distance fixture"
	run = Font.shape(font, "..", Font.ShapeOptions.{ script: "Deva" })
	run.advances == [{ x: 600, y: 0 }, { x: 100, y: 0 }] and run.offsets == [{ x: 0, y: 0 }, { x: 0, y: 0 }]
}

expect {
	font = Font.from_bytes(positioning, Font.ReadOptions.{}) ?? crash "valid GPOS kern fixture"
	run = Font.shape(font, "..", Font.ShapeOptions.{ script: "Deva" })
	run.advances == [{ x: 300, y: 0 }, { x: 100, y: 0 }] and run.offsets == [{ x: 0, y: 0 }, { x: 0, y: 0 }]
}

expect {
	font = Font.from_bytes(distance, Font.ReadOptions.{}) ?? crash "valid distance fixture"
	run = Font.shape(font, "..", Font.ShapeOptions.{ script: "Latn" })
	run.advances == [{ x: 850, y: 0 }, { x: 350, y: 0 }] and run.offsets == [{ x: 0, y: 0 }, { x: 250, y: 0 }]
}
