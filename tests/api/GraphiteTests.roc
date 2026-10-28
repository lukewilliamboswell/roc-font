import font.Font
import "../fonts/graphite/replace.ttf" as replace_bytes : List(U8)
import "../fonts/graphite/divide-feature.ttf" as feature_bytes : List(U8)
import "../fonts/graphite/stack-1024.ttf" as stack_bytes : List(U8)

## Public font-program selection, results and text-dependent diagnostics.
GraphiteTests :: {}.{}

read = |bytes| Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "original valid Graphite fixture rejected"

expect {
	font = read(replace_bytes)
	plan = Font.plan(font, Font.ShapeOptions.{ script: "Latn" })
	Font.shaping_engine(plan) == Graphite and match Font.shape_checked(font, plan, "ab") {
		Ok(run) => run.glyphs == [2, 2] and run.advances == [{ x: 602, y: 0 }, { x: 602, y: 0 }] and run.clusters == [0, 1]
		Err(_) => False
	}
}
expect {
	font = read(replace_bytes)
	plan = Font.plan(font, Font.ShapeOptions.{ script: "Latn", use_font_programs: False })
	Font.shaping_engine(plan) == OpenType and match Font.shape_checked(font, plan, "ab") {
		Ok(run) => run.glyphs == [1, 2] and run.advances == [{ x: 601, y: 0 }, { x: 602, y: 0 }]
		Err(_) => False
	}
}
expect {
	font = read(feature_bytes)
	zero = Font.plan(font, Font.ShapeOptions.{ script: "Latn", graphite_features: [Font.GraphiteFeature.{ id: 100, value: 0 }] })
	one = Font.plan(font, Font.ShapeOptions.{ script: "Latn", graphite_features: [Font.GraphiteFeature.{ id: 100, value: 1 }] })
	aborted = match Font.shape_checked(font, zero, "a") {
		Err(ProgramAborted({ run })) => run.glyphs.is_empty()
		_ => False
	}
	control = match Font.shape_checked(font, zero, "b") {
		Ok(run) => run.glyphs == [2] and run.advances == [{ x: 602, y: 0 }]
		_ => False
	}
	success = match Font.shape_checked(font, one, "a") {
		Ok(run) => run.glyphs == [1] and run.advances == [{ x: 5, y: 0 }]
		_ => False
	}
	aborted and control and success and Font.shape(font, "a", Font.ShapeOptions.{ script: "Latn" }).glyphs.is_empty()
}
expect {
	font = read(stack_bytes)
	plan = Font.plan(font, Font.ShapeOptions.{ script: "Latn" })
	match Font.shape_checked(font, plan, "a") {
		Err(ProgramAborted({ run })) => run.glyphs.is_empty()
		_ => False
	} and match Font.shape_checked(font, plan, "b") {
		Ok(run) => run.glyphs == [2]
		_ => False
	}
}
expect {
	font = read(replace_bytes)
	plan = Font.plan(font, Font.ShapeOptions.{ script: "Latn" })
	match Font.shape_traced(font, plan, "ab") {
		Ok(result) => result.origins == [Substituted({ feature: "" }), Mapped] and result.origins.len() == result.run.glyphs.len()
		Err(_) => False
	}
}
expect {
	font = read(feature_bytes)
	plan = Font.plan(font, Font.ShapeOptions.{ script: "Latn" })
	match Font.shape_traced(font, plan, "a") {
		Err(ProgramAborted({ run, origins })) => run.glyphs.is_empty() and origins.is_empty()
		_ => False
	}
}
expect {
	font = read(replace_bytes)
	plan = Font.plan(font, Font.ShapeOptions.{ script: "Latn" })
	match Font.shape_range_checked(font, plan, "ba", Font.TextRange.{ start: 1, end: 2 }) {
		Ok(run) => run.glyphs == [2] and run.clusters == [1]
		_ => False
	}
}
expect {
	font = read(replace_bytes)
	plan = Font.plan(font, Font.ShapeOptions.{ script: "Latn", direction: BottomToTop })
	match Font.shape_checked(font, plan, "ab") {
		Ok(run) => run.glyphs == [2, 2] and run.clusters == [1, 0] and run.advances == [{ x: 602, y: 0 }, { x: 602, y: 0 }]
		_ => False
	}
}
expect {
	font = read(replace_bytes)
	run = Font.shape(font, "😀", Font.ShapeOptions.{ script: "Latn" })
	run.glyphs == [0] and run.flags.len() == 1 and Font.is_missing(run.flags.first() ?? 0)
}
expect {
	font = read(replace_bytes)
	plan = Font.plan(font, Font.ShapeOptions.{ script: "Latn" })
	match Font.shape_checked(font, plan, "") {
		Ok(run) => run.glyphs.is_empty() and run.advances.is_empty() and run.offsets.is_empty() and run.clusters.is_empty() and run.flags.is_empty()
		_ => False
	}
}
