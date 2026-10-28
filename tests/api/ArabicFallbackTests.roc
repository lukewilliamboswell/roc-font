import font.Font
import "../fonts/shaping/arabic-fallback/presentation.ttf" as presentation : List(U8)
import "../fonts/shaping/arabic-fallback/partial-isol.ttf" as partial : List(U8)
import "../fonts/shaping/arabic-fallback/win1256.ttf" as windows : List(U8)
import "../fonts/shaping/arabic-fallback/wrong-alef.ttf" as no_fallback : List(U8)
import "../fonts/shaping/arabic-stretch/normal.ttf" as normal : List(U8)
import "../fonts/shaping/arabic-stretch/small.ttf" as small_tiles : List(U8)
import "../fonts/shaping/arabic-extra/NotoSansSyriac[wght].ttf" as syriac : List(U8)

## Presentation forms, fallback ligatures and stretch tiles through the
## bundled public API, including tracing, original offsets and budgets.
ArabicFallbackTests :: {}.{}

expect {
	font = Font.from_bytes(presentation, Font.ReadOptions.{}) ?? crash "valid presentation fixture"
	run = Font.shape(font, "ببب", Font.ShapeOptions.{ script: "Arab" })
	run.glyphs == [288, 290, 289] and run.clusters == [4, 2, 0] and run.flags.map(Font.is_unsafe_to_break) == [True, True, False]
}

expect {
	font = Font.from_bytes(presentation, Font.ReadOptions.{}) ?? crash "valid presentation fixture"
	plan = Font.plan(font, Font.ShapeOptions.{ script: "Arab" })
	match Font.shape_traced(font, plan, "لاب") {
		Ok(result) => result.run.glyphs == [287, 395] and result.run.clusters == [4, 0] and result.origins == [Substituted({ feature: "isol" }), Ligature({ feature: "rlig", components: 2 })]
		Err(_) => False
	}
}

expect {
	font = Font.from_bytes(partial, Font.ReadOptions.{}) ?? crash "valid partial fixture"
	Font.shape(font, "ببب", Font.ShapeOptions.{ script: "Arab" }).glyphs == [10, 10, 10]
}

expect {
	font = Font.from_bytes(normal, Font.ReadOptions.{}) ?? crash "valid stretch fixture"
	plan = Font.plan(font, Font.ShapeOptions.{ script: "Syrc" })
	match Font.shape_traced(font, plan, "\u(070F)ܐܒ") {
		Ok(result) => {
			run = result.run
			run.glyphs.len() == 17 and run.clusters.take_first(2) == [4, 2] and run.clusters.drop_first(2).all(|c| c == 0) and run.advances.take_first(2) == [{ x: 600, y: 0 }, { x: 600, y: 0 }] and run.advances.drop_first(2).all(|a| a.x == 0 and a.y == 0) and run.offsets.get(2) == Ok({ x: -1200, y: 0 }) and run.offsets.last() == Ok({ x: -50, y: 0 }) and run.glyphs.len() == result.origins.len() and result.origins.drop_first(2).all(
				|origin| match origin {
					Multiple({ feature }) => feature == "stch"
					Inserted({ feature }) => feature == "stch"
					_ => False
				},
			) and Font.shape_checked(font, plan, "\u(070F)ܐܒ") == Ok(run)
		}
		Err(_) => False
	}
}

expect {
	font = Font.from_bytes(syriac, Font.ReadOptions.{}) ?? crash "valid Syriac font"
	run = Font.shape(font, "ܒܐ", Font.ShapeOptions.{ script: "Syrc" })
	run.glyphs == [260, 18] and run.clusters == [2, 0] and run.advances == [{ x: 986, y: 0 }, { x: 655, y: 0 }] and run.offsets == [{ x: 0, y: 0 }, { x: -75, y: 0 }]
}

expect {
	font = Font.from_bytes(small_tiles, Font.ReadOptions.{}) ?? crash "valid small tile fixture"
	text = Str.join_with(List.repeat("\u(070F)ܐܒܕܪ", 600), "")
	plan = Font.plan(font, Font.ShapeOptions.{ script: "Syrc", limits: Font.ShapeLimits.{ growth: 0 } })
	match Font.shape_checked(font, plan, text) {
		Err(OverBudget(result)) => result.budgets.contains(Growth) and result.run == Font.shape_planned(font, plan, text) and result.run.glyphs.len() == result.run.clusters.len() and result.run.glyphs.len() <= 65536
		Ok(_) => False
	}
}

expect {
	font = Font.from_bytes(small_tiles, Font.ReadOptions.{}) ?? crash "valid small tile fixture"
	text = Str.join_with(List.repeat("\u(070F)ܐܒܕܪ", 600), "")
	plan = Font.plan(font, Font.ShapeOptions.{ script: "Syrc", limits: Font.ShapeLimits.{ operations: 0 } })
	match Font.shape_traced(font, plan, text) {
		Err(OverBudget(result)) => result.budgets.contains(Operations) and result.run == Font.shape_planned(font, plan, text) and result.run.glyphs.len() == result.origins.len()
		Ok(_) => False
	}
}

expect {
	font = Font.from_bytes(windows, Font.ReadOptions.{}) ?? crash "valid Windows fallback fixture"
	plan = Font.plan(font, Font.ShapeOptions.{ script: "Arab" })
	match Font.shape_traced(font, plan, "بلا") {
		Ok(result) => {
			result.run.glyphs == [170, 4] and result.run.clusters == [2, 0] and result.run.advances == [{ x: 470, y: 0 }, { x: 304, y: 0 }] and result.origins == [Ligature({ feature: "medi", components: 2 }), Substituted({ feature: "init" })]
		}
		Err(_) => False
	}
}

expect {
	font = Font.from_bytes(no_fallback, Font.ReadOptions.{}) ?? crash "valid no-layout fixture"
	damma = Font.shape(font, "شُّ", Font.ShapeOptions.{ script: "Arab" })
	kasra = Font.shape(font, "شِّ", Font.ShapeOptions.{ script: "Arab" })
	damma.offsets == [{ x: 206, y: 724 }, { x: 206, y: 362 }, { x: 0, y: 0 }] and kasra.offsets == [{ x: 206, y: -362 }, { x: 206, y: 362 }, { x: 0, y: 0 }]
}
