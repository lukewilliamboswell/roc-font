import font.Font
import "../fonts/aat/direct-logical.ttf" as direct : List(U8)
import "../fonts/aat/rearrange-logical.ttf" as rearrange : List(U8)
import "../fonts/aat/context-logical.ttf" as context : List(U8)
import "../fonts/aat/ligature-logical.ttf" as ligature : List(U8)
import "../fonts/aat/insertion-logical.ttf" as insertion : List(U8)
import "../fonts/aat/direct-features.ttf" as feature_direct : List(U8)
import "../fonts/aat/ligature-features.ttf" as feature_ligature : List(U8)
import "../fonts/aat/language.ttf" as languages : List(U8)
import "../fonts/aat/tracking-1-0.ttf" as tracking : List(U8)
import "../fonts/aat/tracking-0-0.ttf" as old_tracking : List(U8)
import "../fonts/aat/gdef-classes.ttf" as gdef_replacements : List(U8)
import "../fonts/aat/eot-only.ttf" as inactive : List(U8)

## Apple font programs through the public served package.
AatTests :: {}.{}

expect {
	font = Font.from_bytes(gdef_replacements, Font.ReadOptions.{ strict: True }) ?? crash "valid Apple replacement classes"
	run = Font.shape(font, "ab", Font.ShapeOptions.{})
	run.glyphs == [5, 6] and run.advances == [{ x: 0, y: 0 }, { x: 0, y: 0 }] and run.offsets == [{ x: 0, y: 0 }, { x: 0, y: 0 }]
}
expect {
	font = Font.from_bytes(inactive, Font.ReadOptions.{ strict: True }) ?? crash "valid inactive Apple program"
	Font.shape(font, "ab", Font.ShapeOptions.{}).glyphs == [1, 2]
}

expect {
	font = Font.from_bytes(tracking, Font.ReadOptions.{ strict: True }) ?? crash "valid modern tracking fixture"
	old = Font.from_bytes(old_tracking, Font.ReadOptions.{ strict: True }) ?? crash "valid old tracking fixture"
	advance = |size| Font.shape(font, "ab", Font.ShapeOptions.{ point_size: size }).advances.map(|p| p.x)
	advance(0) == [110, 120] and advance(6) == [100, 110] and advance(18) == [120, 130] and advance(24) == [130, 140] and Font.shape(old, "ab", Font.ShapeOptions.{ point_size: 24 }).advances.map(|p| p.x) == [110, 120]
}

expect {
	font = Font.from_bytes(languages, Font.ReadOptions.{ strict: True }) ?? crash "valid AAT language fixture"
	shape = |language| Font.shape(font, "ab", Font.ShapeOptions.{ language }).glyphs
	shape("en") == [5, 6] and shape("en-US") == [6, 7] and shape("EN_us.utf8") == [6, 7] and shape("eng") == [1, 2] and shape("fr-CA") == [7, 8]
}

expect {
	font = Font.from_bytes(direct, Font.ReadOptions.{ strict: True }) ?? crash "valid AAT direct fixture"
	Font.shape(font, "ab", Font.ShapeOptions.{}).glyphs == [5, 6]
}
expect {
	font = Font.from_bytes(rearrange, Font.ReadOptions.{ strict: True }) ?? crash "valid AAT rearrangement fixture"
	run = Font.shape(font, "ab", Font.ShapeOptions.{})
	run.glyphs == [2, 1] and run.clusters == [0, 0]
}
expect {
	font = Font.from_bytes(context, Font.ReadOptions.{ strict: True }) ?? crash "valid AAT contextual fixture"
	Font.shape(font, "ab", Font.ShapeOptions.{}).glyphs == [5, 6]
}
expect {
	font = Font.from_bytes(ligature, Font.ReadOptions.{ strict: True }) ?? crash "valid AAT ligature fixture"
	run = Font.shape(font, "ab", Font.ShapeOptions.{})
	run.glyphs == [5] and run.clusters == [0]
}
expect {
	font = Font.from_bytes(insertion, Font.ReadOptions.{ strict: True }) ?? crash "valid AAT insertion fixture"
	run = Font.shape(font, "a", Font.ShapeOptions.{})
	run.glyphs == [5, 1] and run.clusters == [0, 0]
}

expect {
	font = Font.from_bytes(feature_direct, Font.ReadOptions.{ strict: True }) ?? crash "valid AAT feature fixture"
	Font.shape(font, "abc", Font.ShapeOptions.{ features: [Font.Feature.{ tag: "liga", value: 0 }] }).glyphs == [1, 2, 3]
}

expect {
	font = Font.from_bytes(feature_direct, Font.ReadOptions.{ strict: True }) ?? crash "valid AAT feature fixture"
	run = Font.shape(font, "abc", Font.ShapeOptions.{ features: [Font.Feature.{ tag: "liga", value: 0, start: 1, end: 2 }] })
	run.glyphs == [5, 2, 0] and run.clusters == [0, 1, 2] and !Font.is_missing(run.flags.get(2) ?? 0)
}

expect {
	font = Font.from_bytes(feature_ligature, Font.ReadOptions.{ strict: True }) ?? crash "valid AAT ligature feature fixture"
	Font.shape(font, "ab", Font.ShapeOptions.{ features: [Font.Feature.{ tag: "liga", value: 0 }] }).glyphs == [1, 2]
}

expect {
	font = Font.from_bytes(feature_direct, Font.ReadOptions.{ strict: True }) ?? crash "valid AAT feature fixture"
	# Apple selectors retain the first active setting for an on/off pair.
	run = Font.shape(font, "abc", Font.ShapeOptions.{ features: [Font.Feature.{ tag: "liga", value: 0, start: 1, end: 2 }, Font.Feature.{ tag: "liga", value: 1 }] })
	run.glyphs == [5, 2, 0]
}
