import font.Font
import build.FontBuild
import "../fonts/outlines-carets/outlines-carets.ttf" as fixture : List(U8)

## Font-defined carets preserve their table order and cardinality. The
## format2 expectation is checked against fontTools contour coordinates;
## HarfBuzz's ot backend does not implement contour-point callbacks.
CaretTests :: {}.{}

font : Font
font = match Font.from_bytes(fixture, Font.ReadOptions.{}) {
	Ok(value) => value
	Err(problems) => crash Str.inspect(problems)
}
expect Font.ligature_carets(font, 1) == [Position(150), Position(500), Position(250)]
expect Font.ligature_carets(Font.at(font, Font.Variation.{ weight: Black }), 1) == [Position(150), Position(543), Position(330)]
expect Font.ligature_carets(Font.at(font, Font.Variation.{ weight: Weight(650) }), 1) == [Position(150), Position(521.5), Position(290)]
expect Font.ligature_carets(font, 0) == [] and Font.ligature_carets(font, 0xFFFFFFFF) == []
expect Font.ligature_carets(font, 1) == Font.ligature_carets(font, 1)

# Outline data may be unavailable while explicit caret positions remain
# useful. Preserve a missing point caret instead of substituting zero.
expect {
	ligature = FontBuild.pack([U16(3), Ref(FontBuild.pack([U16(1), I16(150)])), Ref(FontBuild.pack([U16(2), U16(1)])), Ref(FontBuild.pack([U16(3), I16(250), Ref(FontBuild.pack([U16(9), U16(9), U16(1), U16(0)]))]))])
	carets = FontBuild.pack([Ref(FontBuild.coverage1([1])), U16(1), Ref(ligature)])
	gdef = FontBuild.pack([U32(0x10000), U16(0), U16(0), Ref(carets), U16(0)])
	match Font.from_bytes(FontBuild.file(FontBuild.replace(FontBuild.basic, "GDEF", gdef)), Font.ReadOptions.{}) {
		Ok(metrics_only) => Font.ligature_carets(metrics_only, 1) == [Position(150), Unavailable, Position(250)]
		Err(_) => False
	}
}

import "../fonts/outlines-carets/bad-point.ttf" as bad_point : List(U8)
import "../fonts/outlines-carets/bad-index.ttf" as bad_index : List(U8)
import "../fonts/outlines-carets/bad-coverage.ttf" as bad_coverage : List(U8)
expect [bad_point, bad_index, bad_coverage].all(
	|bytes| match Font.from_bytes(bytes, Font.ReadOptions.{}) {
		Err(problems) => problems.any(
			|problem| match problem {
				BadTable({ table, .. }) => table == "GDEF"
				_ => False
			},
		)
		Ok(_) => False
	},
)
