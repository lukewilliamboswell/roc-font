import font.Font
import "../fonts/aat/fallback-marks.ttf" as hebrew : List(U8)
import "../fonts/aat/fallback-script-marks.ttf" as scripts : List(U8)
import "../fonts/aat/fallback-nonzero-marks.ttf" as nonzero : List(U8)
import "../fonts/aat/fallback-dflt-marks.ttf" as dflt : List(U8)
import "../fonts/aat/fallback-gdef-dflt-marks.ttf" as gdef_dflt : List(U8)
import "../fonts/aat/fallback-gpos-dflt-marks.ttf" as gpos_dflt : List(U8)

## Original script mark-positioning policy survives Apple substitutions.
AatFallbackTests :: {}.{}

expect {
	font = Font.from_bytes(hebrew, Font.ReadOptions.{ strict: True }) ?? crash "valid original Apple fallback fixture"
	run = Font.shape(font, "סְ", Font.ShapeOptions.{ script: "Hebr", direction: RightToLeft })
	run.glyphs == [7, 1] and run.advances == [{ x: 0, y: 0 }, { x: 700, y: 0 }] and run.offsets == [{ x: 300, y: -162 }, { x: 0, y: 0 }]
}

expect {
	font = Font.from_bytes(scripts, Font.ReadOptions.{ strict: True }) ?? crash "valid script-policy fixture"
	run = Font.shape(font, "بَ", Font.ShapeOptions.{ script: "Arab", direction: RightToLeft })
	run.glyphs == [7, 1] and run.advances == [{ x: 0, y: 0 }, { x: 700, y: 0 }] and run.offsets == [{ x: 300, y: 662 }, { x: 0, y: 0 }]
}

expect {
	font = Font.from_bytes(scripts, Font.ReadOptions.{ strict: True }) ?? crash "valid script-policy fixture"
	run = Font.shape(font, "가〮", Font.ShapeOptions.{ script: "Hang", direction: LeftToRight })
	run.glyphs == [1, 7] and run.offsets == [{ x: 0, y: 0 }, { x: -400, y: 0 }]
}

expect {
	font = Font.from_bytes(scripts, Font.ReadOptions.{ strict: True }) ?? crash "valid script-policy fixture"
	run = Font.shape(font, "ก่", Font.ShapeOptions.{ script: "Thai", direction: LeftToRight })
	run.glyphs == [1, 7] and run.offsets == [{ x: 0, y: 0 }, { x: 0, y: 0 }]
}

expect {
	font = Font.from_bytes(scripts, Font.ReadOptions.{ strict: True }) ?? crash "valid script-policy fixture"
	run = Font.shape(font, "ກ່", Font.ShapeOptions.{ script: "Laoo", direction: LeftToRight })
	run.glyphs == [1, 7] and run.offsets == [{ x: 0, y: 0 }, { x: 0, y: 0 }]
}

expect {
	font = Font.from_bytes(scripts, Font.ReadOptions.{ strict: True }) ?? crash "valid script-policy fixture"
	run = Font.shape(font, "क़", Font.ShapeOptions.{ script: "Deva", direction: LeftToRight })
	run.glyphs == [1, 7] and run.offsets == [{ x: 0, y: 0 }, { x: 0, y: 0 }]
}

expect {
	font = Font.from_bytes(scripts, Font.ReadOptions.{ strict: True }) ?? crash "valid script-policy fixture"
	run = Font.shape(font, "ក៉", Font.ShapeOptions.{ script: "Khmr", direction: LeftToRight })
	run.glyphs == [1, 7] and run.offsets == [{ x: 0, y: 0 }, { x: 0, y: 0 }]
}

expect {
	font = Font.from_bytes(scripts, Font.ReadOptions.{ strict: True }) ?? crash "valid script-policy fixture"
	run = Font.shape(font, "က့", Font.ShapeOptions.{ script: "Mymr", direction: LeftToRight })
	run.glyphs == [1, 7] and run.offsets == [{ x: 0, y: 0 }, { x: 0, y: 0 }]
}

expect {
	font = Font.from_bytes(scripts, Font.ReadOptions.{ strict: True }) ?? crash "valid script-policy fixture"
	run = Font.shape(font, "ཀཱ", Font.ShapeOptions.{ script: "Tibt", direction: LeftToRight })
	run.glyphs == [1, 7] and run.offsets == [{ x: 0, y: 0 }, { x: 0, y: 0 }]
}

expect {
	font = Font.from_bytes(scripts, Font.ReadOptions.{ strict: True }) ?? crash "valid script-policy fixture"
	run = Font.shape(font, "סְ", Font.ShapeOptions.{ script: "Hebr", direction: TopToBottom })
	run.glyphs == [1, 7] and run.advances == [{ x: 0, y: -1000 }, { x: 0, y: 0 }] and run.offsets == [{ x: -350, y: -800 }, { x: 300, y: 38 }]
}

expect {
	font = Font.from_bytes(nonzero, Font.ReadOptions.{ strict: True }) ?? crash "valid nonzero mark-advance fixture"
	run = Font.shape(font, "क़", Font.ShapeOptions.{ script: "Deva", direction: LeftToRight })
	run.glyphs == [1, 7] and run.advances == [{ x: 700, y: 0 }, { x: 230, y: 0 }] and run.offsets == [{ x: 0, y: 0 }, { x: 0, y: 0 }]
}

expect {
	font = Font.from_bytes(nonzero, Font.ReadOptions.{ strict: True }) ?? crash "valid nonzero mark-advance fixture"
	run = Font.shape(font, "က့", Font.ShapeOptions.{ script: "Mymr", direction: LeftToRight })
	run.glyphs == [1, 7] and run.advances == [{ x: 700, y: 0 }, { x: 230, y: 0 }] and run.offsets == [{ x: 0, y: 0 }, { x: 0, y: 0 }]
}

expect {
	font = Font.from_bytes(nonzero, Font.ReadOptions.{ strict: True }) ?? crash "valid nonzero mark-advance fixture"
	run = Font.shape(font, "بَ", Font.ShapeOptions.{ script: "Arab", direction: TopToBottom })
	run.glyphs == [1, 7] and run.advances == [{ x: 0, y: -1000 }, { x: 0, y: 0 }] and run.offsets == [{ x: -350, y: -800 }, { x: 300, y: 931 }]
}

expect {
	font = Font.from_bytes(dflt, Font.ReadOptions.{ strict: True }) ?? crash "valid DFLT script-selection fixture"
	run = Font.shape(font, "क़", Font.ShapeOptions.{ script: "Deva", direction: LeftToRight })
	run.glyphs == [1, 7] and run.advances == [{ x: 700, y: 0 }, { x: 0, y: 0 }] and run.offsets == [{ x: 0, y: 0 }, { x: -400, y: 0 }]
}

expect {
	font = Font.from_bytes(gdef_dflt, Font.ReadOptions.{ strict: True }) ?? crash "valid DFLT script-selection fixture"
	run = Font.shape(font, "က့", Font.ShapeOptions.{ script: "Mymr", direction: LeftToRight })
	run.glyphs == [1, 7] and run.advances == [{ x: 700, y: 0 }, { x: 0, y: 0 }] and run.offsets == [{ x: 0, y: 0 }, { x: -400, y: 0 }]
}

expect {
	font = Font.from_bytes(gpos_dflt, Font.ReadOptions.{ strict: True }) ?? crash "valid Apple/GPOS default-model mark fixture"
	run = Font.shape(font, "क़", Font.ShapeOptions.{ script: "Deva", direction: LeftToRight })
	run.glyphs == [1, 7] and run.advances == [{ x: 700, y: 0 }, { x: 0, y: 0 }] and run.offsets == [{ x: 0, y: 0 }, { x: 0, y: 0 }]
}

expect {
	font = Font.from_bytes(gpos_dflt, Font.ReadOptions.{ strict: True }) ?? crash "valid Apple/GPOS default-model mark fixture"
	run = Font.shape(font, "က့", Font.ShapeOptions.{ script: "Mymr", direction: LeftToRight })
	run.glyphs == [1, 7] and run.advances == [{ x: 700, y: 0 }, { x: 0, y: 0 }] and run.offsets == [{ x: 0, y: 0 }, { x: 0, y: 0 }]
}

expect {
	font = Font.from_bytes(gpos_dflt, Font.ReadOptions.{ strict: True }) ?? crash "valid Apple/GPOS default-model mark fixture"
	run = Font.shape(font, "ܒܰ", Font.ShapeOptions.{ script: "Syrc", direction: LeftToRight })
	run.glyphs == [7, 1] and run.advances == [{ x: 0, y: 0 }, { x: 700, y: 0 }] and run.offsets == [{ x: 0, y: 0 }, { x: 0, y: 0 }]
}
