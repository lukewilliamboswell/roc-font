import font.Font
import "../../tests/fonts/complex/ComplexDevaSans.ttf" as sans_file : List(U8)
import "../../tests/fonts/complex/ComplexDevaSerif.ttf" as serif_file : List(U8)

# Focused public consumer contracts. The complete two-family cached
# matrix lives in tests/fonts/complex; these checks make the use cases
# and original UTF-8 cluster offsets easy to review.
IndicTests :: {}.{}

sans : Font
sans = match Font.from_bytes(sans_file, Font.ReadOptions.{}) {
	Ok(font) => font
	Err(problems) => crash Str.inspect(problems)
}

serif : Font
serif = match Font.from_bytes(serif_file, Font.ReadOptions.{}) {
	Ok(font) => font
	Err(problems) => crash Str.inspect(problems)
}

options : Font.ShapeOptions
options = Font.ShapeOptions.{ script: "Deva", language: "hi" }

# Pre-base matra and conjunct, rather than independently mapped letters.
expect {
	run = Font.shape(sans, "क्षि", options)
	run.glyphs == [526, 88] and run.clusters == [0, 0] and run.advances.map(|a| a.x) == [259, 717] and run.flags == [0, 0]
}
# Reph formed at the start moves after the base and pre-base matra.
expect {
	run = Font.shape(sans, "र्कि", options)
	run.glyphs == [565, 54, 737] and run.clusters == [0, 0, 0] and run.advances.map(|a| a.x) == [259, 768, 0] and run.flags == [0, 0, 0]
}
# Join controls have different effects on half forms and safe boundaries.
expect {
	run = Font.shape(sans, "क्‍ष", options)
	run.glyphs == [210, 1, 84] and run.clusters == [0, 0, 9] and run.advances.map(|a| a.x) == [550, 0, 578] and run.flags == [0, 0, 1]
}
expect {
	run = Font.shape(sans, "क्‌ष", options)
	run.glyphs == [54, 101, 1, 84] and run.clusters == [0, 0, 6, 9] and run.advances.map(|a| a.x) == [768, 0, 0, 578] and run.offsets.map(|a| a.x) == [0, -221, 0, 0] and run.flags == [0, 0, 1, 0]
}
# A broken cluster receives the font's dotted circle and retains its text.
expect {
	run = Font.shape(sans, "ि", options)
	run.glyphs == [30, 740] and run.clusters == [0, 0] and run.advances.map(|a| a.x) == [259, 510] and run.flags == [0, 0]
}
# A second independent family follows original byte offsets across syllables.
expect {
	run = Font.shape(serif, "हिन्दी", options)
	run.glyphs == [532, 88, 226, 73, 31] and run.clusters == [0, 0, 6, 12, 12] and run.advances.map(|a| a.x) == [246, 471, 283, 464, 246] and run.flags == [0, 0, 0, 1, 1]
}
expect Font.shape(sans, "", options).glyphs.is_empty()
expect {
	plan = Font.plan(sans, options)
	text = "र्कि क्षिं हिन्दी"
	match Font.shape_checked(sans, plan, text) {
		Ok(run) => Str.inspect(run) == Str.inspect(Font.shape(sans, text, options))
		Err(_) => False
	}
}
expect {
	plan = Font.plan(sans, options)
	text = "र्कि क्षिं हिन्दी"
	match Font.shape_traced(sans, plan, text) {
		Ok(traced) => traced.origins.len() == traced.run.glyphs.len() and Str.inspect(traced.run) == Str.inspect(Font.shape_planned(sans, plan, text))
		Err(_) => False
	}
}
expect {
	text = Str.join_with(List.repeat("क्", 1500), "")
	plan = Font.plan(sans, Font.ShapeOptions.{ script: "Deva", limits: Font.ShapeLimits.{ operations: 0 } })
	match Font.shape_checked(sans, plan, text) {
		Ok(_) => False
		Err(OverBudget(result)) => !result.budgets.is_empty() and result.run.glyphs.len() <= 16384
	}
}
