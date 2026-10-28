import font.Font
import "../fonts/graphite/pass-conditions/false.ttf" as false_bytes : List(U8)
import "../fonts/graphite/pass-conditions/true.ttf" as true_bytes : List(U8)
import "../fonts/graphite/pass-conditions/absent.ttf" as absent_bytes : List(U8)
import "../fonts/graphite/pass-conditions/feature.ttf" as feature_bytes : List(U8)

import "../fonts/graphite/pass-conditions/zero-feature.ttf" as zero_feature_bytes : List(U8)
import "../fonts/graphite/pass-conditions/invalid-reference-before.ttf" as invalid_before_bytes : List(U8)
import "../fonts/graphite/pass-conditions/invalid-reference-after.ttf" as invalid_after_bytes : List(U8)

GraphitePassConditionsTests :: {}.{}

read = |bytes| Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "valid conditional collision font rejected"

options = Font.ShapeOptions.{ script: "Latn", direction: LeftToRight }

## A false pass condition disables its collision stage too.
expect {
	font = read(false_bytes)
	plan = Font.plan(font, options)
	Font.shaping_engine(plan) == Graphite and match Font.shape_checked(font, plan, "ab") {
		Ok(run) => run.glyphs == [1, 2] and run.advances == [{ x: 100, y: 0 }, { x: 602, y: 0 }] and run.offsets == [{ x: 0, y: 0 }, { x: 0, y: 0 }] and run.clusters == [0, 1]
		Err(_) => False
	}
}
expect {
	font = read(true_bytes)
	other = read(absent_bytes)
	active = Font.shape(font, "ab", options)
	active.offsets == [{ x: -200, y: 0 }, { x: 0, y: 0 }] and active == Font.shape(other, "ab", options)
}
expect {
	font = read(feature_bytes)
	off = Font.plan(font, Font.ShapeOptions.{ script: "Latn", graphite_features: [Font.GraphiteFeature.{ id: 100, value: 0 }] })
	on = Font.plan(font, Font.ShapeOptions.{ script: "Latn", graphite_features: [Font.GraphiteFeature.{ id: 100, value: 1 }] })
	before = Font.shape_planned(font, off, "ab")
	active = Font.shape_planned(font, on, "ab")
	before.offsets == [{ x: 0, y: 0 }, { x: 0, y: 0 }] and active.offsets == [{ x: -200, y: 0 }, { x: 0, y: 0 }] and Font.shape_planned(font, off, "ab") == before
}
expect {
	font = read(feature_bytes)
	plan = Font.plan(font, options)
	match Font.shape_traced(font, plan, "ab") {
		Ok(result) => result.origins == [Mapped, Mapped] and result.run.offsets == [{ x: 0, y: 0 }, { x: 0, y: 0 }]
		Err(_) => False
	} and match Font.shape_range_checked(font, plan, "ab", Font.TextRange.{ start: 1, end: 2 }) {
		Ok(run) => run.glyphs == [2] and run.clusters == [1] and run.advances == [{ x: 602, y: 0 }]
		Err(_) => False
	}
}
expect {
	font = read(feature_bytes)
	plan = Font.plan(font, Font.ShapeOptions.{ script: "Latn", graphite_features: [Font.GraphiteFeature.{ id: 100, value: 1 }] })
	match Font.shape_traced(font, plan, "") {
		Ok(result) => result.run.glyphs.is_empty() and result.origins.is_empty()
		Err(_) => False
	}
}

## A rule-free pass still evaluates its feature against the current slot.
expect {
	font = read(zero_feature_bytes)
	off = Font.shape(font, "ab", Font.ShapeOptions.{ script: "Latn", graphite_features: [Font.GraphiteFeature.{ id: 100, value: 0 }] })
	on = Font.shape(font, "ab", Font.ShapeOptions.{ script: "Latn", graphite_features: [Font.GraphiteFeature.{ id: 100, value: 1 }] })
	off.offsets == [{ x: 0, y: 0 }, { x: 0, y: 0 }] and on.offsets == [{ x: -200, y: 0 }, { x: 0, y: 0 }]
}

## A pass condition cannot address a preceding or following slot.
expect {
	var $rejected = True
	for bytes in [invalid_before_bytes, invalid_after_bytes] {
		$rejected = $rejected and match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
			Err(_) => True
			Ok(_) => False
		}
		$rejected = $rejected and match Font.from_bytes(bytes, Font.ReadOptions.{}) {
			Ok(font) => Font.shaping_engine(Font.plan(font, Font.ShapeOptions.{})) == OpenType
			Err(_) => False
		}
	}
	$rejected
}
