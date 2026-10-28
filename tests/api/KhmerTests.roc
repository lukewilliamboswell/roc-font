import font.Font
import "../../tests/fonts/complex/ComplexKhmerSans.ttf" as sans_file : List(U8)
import "../../tests/fonts/complex/ComplexKhmerSerif.ttf" as serif_file : List(U8)

# Exact HB14.6 consumer facts; full280case replay is separate.
KhmerTests :: {}.{}

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
options = Font.ShapeOptions.{ script: "Khmr", language: "km" }
expect {
	run = Font.shape(sans, "ខ្មែរ", options)
	run.glyphs == [86, 4, 170, 32] and run.clusters == [0, 0, 0, 12] and run.advances.map(|a| a.x) == [288, 635, 0, 288] and run.offsets == [{ x: 0, y: 0 }, { x: 0, y: 0 }, { x: 22, y: -26 }, { x: 0, y: 0 }] and run.flags == [0, 0, 0, 0]
}
expect {
	run = Font.shape(sans, "ក្រ", options)
	run.glyphs == [174, 3] and run.clusters == [0, 0] and run.advances.map(|a| a.x) == [287, 636]
}
expect {
	run = Font.shape(sans, "កើ", options)
	run.glyphs == [85, 3, 63] and run.clusters == [0, 0, 0] and run.advances.map(|a| a.x) == [288, 636, 0] and run.offsets.map(|a| a.x) == [0, 0, -23]
}
expect {
	run = Font.shape(sans, "ើ", options)
	run.glyphs == [85, 338, 63] and run.clusters == [0, 0, 0] and run.advances.map(|a| a.x) == [288, 635, 0]
}
expect {
	run = Font.shape(sans, "ក្‍រ", options)
	run.glyphs == [3, 113, 1, 32] and run.clusters == [0, 0, 0, 9] and run.flags == [0, 0, 0, 0]
}
expect {
	run = Font.shape(sans, "ក្‌រ", options)
	run.glyphs == [3, 113, 1, 32] and run.clusters == [0, 0, 6, 9] and run.flags == [0, 0, 0, 0]
}
expect {
	run = Font.shape(serif, "ញ្ញូ", options)
	run.glyphs == [12, 146, 70] and run.clusters == [0, 0, 0] and run.advances.map(|a| a.x) == [1005, 0, 0] and run.offsets == [{ x: 0, y: 0 }, { x: 41, y: -16 }, { x: -288, y: -455 }]
}
expect Font.shape(sans, "", options).glyphs.is_empty()
expect {
	plan = Font.plan(sans, options)
	text = "ខ្មែរ ក្រុម ក្រិ"
	match Font.shape_traced(sans, plan, text) {
		Ok(traced) => traced.origins.len() == traced.run.glyphs.len() and Str.inspect(traced.run) == Str.inspect(Font.shape_planned(sans, plan, text))
		Err(_) => False
	}
}
