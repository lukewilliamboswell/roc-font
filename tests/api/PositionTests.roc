import font.Font
import "../fonts/positioning/single.ttf" as single : List(U8)
import "../fonts/positioning/single-extension.ttf" as single_extension : List(U8)
import "../fonts/positioning/mark-base.ttf" as mark_base : List(U8)
import "../fonts/positioning/mark-mark.ttf" as mark_mark : List(U8)
import "../fonts/positioning/mark-ligature.ttf" as mark_ligature : List(U8)
import "../fonts/positioning/mark-propagation.ttf" as mark_propagation : List(U8)
import "../fonts/positioning/cursive.ttf" as cursive : List(U8)
import "../fonts/positioning/context-1.ttf" as context1 : List(U8)
import "../fonts/positioning/context-2.ttf" as context2 : List(U8)
import "../fonts/positioning/context-3.ttf" as context3 : List(U8)
import "../fonts/positioning/chained.ttf" as chained : List(U8)
import "../fonts/positioning/variable-anchor.ttf" as variable_anchor : List(U8)
import "../fonts/positioning/recursive.ttf" as recursive : List(U8)

## Positioning contracts through the shipped package API. Numeric oracle
## coverage (both directions and lookup flags) lives in positioning.jsonc;
## these expects exercise options, totality, clusters and checked budgets.
PositionTests :: {}.{}

expect {
	match Font.from_bytes(recursive, Font.ReadOptions.{ limits: Font.Limits.{ max_depth: 1 } }) {
		Ok(font) => {
			plan = Font.plan(font, Font.ShapeOptions.{})
			match Font.shape_checked(font, plan, "ab") {
				Err(OverBudget({ run, budgets })) => budgets.contains(Depth) and run.glyphs == [2, 3]
				Ok(_) => False
			}
		}
		Err(_) => False
	}
}

expect {
	match Font.from_bytes(single, Font.ReadOptions.{}) {
		Ok(font) => {
			run = Font.shape(font, "ab", Font.ShapeOptions.{})
			run.glyphs == [2, 3] and run.advances == [{ x: 623, y: 0 }, { x: 641, y: 0 }] and run.offsets == [{ x: 11, y: 17 }, { x: 31, y: 37 }]
		}
		Err(_) => False
	}
}

expect {
	match Font.from_bytes(single_extension, Font.ReadOptions.{}) {
		Ok(font) => Font.shape(font, "a", Font.ShapeOptions.{}).offsets == [{ x: 11, y: 17 }]
		Err(_) => False
	}
}

expect {
	match Font.from_bytes(single, Font.ReadOptions.{}) {
		Ok(font) => Font.shape(font, "ab", Font.ShapeOptions.{ features: [Font.Feature.{ tag: "dist", value: 0 }] }).offsets == [{ x: 0, y: 0 }, { x: 0, y: 0 }]
		Err(_) => False
	}
}

expect {
	match Font.from_bytes(single, Font.ReadOptions.{}) {
		Ok(font) => Font.shape(font, "ab", Font.ShapeOptions.{ features: [Font.Feature.{ tag: "dist", value: 0, start: 0, end: 1 }] }).offsets == [{ x: 0, y: 0 }, { x: 31, y: 37 }]
		Err(_) => False
	}
}

expect {
	match Font.from_bytes(mark_base, Font.ReadOptions.{}) {
		Ok(font) => {
			run = Font.shape(font, "a\u(0301)", Font.ShapeOptions.{})
			run.glyphs == [2, 6] and run.offsets == [{ x: 0, y: 0 }, { x: -400, y: 500 }] and run.clusters == [0, 0] and run.advances == [{ x: 600, y: 0 }, { x: 0, y: 0 }]
		}
		Err(_) => False
	}
}

expect {
	match Font.from_bytes(mark_mark, Font.ReadOptions.{}) {
		Ok(font) => {
			run = Font.shape(font, "a\u(0301)\u(0300)", Font.ShapeOptions.{})
			run.offsets == [{ x: 0, y: 0 }, { x: -400, y: 500 }, { x: -360, y: 670 }]
		}
		Err(_) => False
	}
}

expect {
	match Font.from_bytes(mark_ligature, Font.ReadOptions.{}) {
		Ok(font) => {
			run = Font.shape(font, "f\u(0301)i\u(0300)", Font.ShapeOptions.{})
			run.glyphs == [10, 6, 7] and run.offsets == [{ x: 0, y: 0 }, { x: -500, y: 400 }, { x: -180, y: 620 }]
		}
		Err(_) => False
	}
}

expect {
	match Font.from_bytes(mark_propagation, Font.ReadOptions.{}) {
		Ok(font) => Font.shape(font, "a\u(0301)", Font.ShapeOptions.{}).offsets == [{ x: 13, y: 29 }, { x: -434, y: 500 }]
		Err(_) => False
	}
}

expect {
	[context1, context2, context3].all(
		|file| match Font.from_bytes(file, Font.ReadOptions.{}) {
			Ok(font) => Font.shape(font, "abac", Font.ShapeOptions.{}).offsets == [{ x: 11, y: 17 }, { x: 0, y: 0 }, { x: 0, y: 0 }, { x: 0, y: 0 }]
			Err(_) => False
		},
	)
}

expect {
	match Font.from_bytes(chained, Font.ReadOptions.{}) {
		Ok(font) => Font.shape(font, "cabdab", Font.ShapeOptions.{}).offsets == [{ x: 0, y: 0 }, { x: 11, y: 17 }, { x: 0, y: 0 }, { x: 0, y: 0 }, { x: 0, y: 0 }, { x: 0, y: 0 }]
		Err(_) => False
	}
}

expect {
	match Font.from_bytes(variable_anchor, Font.ReadOptions.{}) {
		Ok(font) => Font.shape(Font.at(font, Font.Variation.{ weight: Black }), "a\u(0301)", Font.ShapeOptions.{}).offsets == [{ x: 0, y: 0 }, { x: -320, y: 620 }]
		Err(_) => False
	}
}

expect {
	[single, mark_base, mark_mark, mark_ligature, cursive, context1, context2, context3, chained, variable_anchor].all(
		|file| match Font.from_bytes(file, Font.ReadOptions.{}) {
			Ok(font) => {
				plan = Font.plan(font, Font.ShapeOptions.{})
				match Font.shape_checked(font, plan, "") {
					Ok(run) => run.glyphs.is_empty() and run.advances.is_empty() and run.offsets.is_empty() and run.clusters.is_empty() and run.flags.is_empty()
					Err(_) => False
				}
			}
			Err(_) => False
		},
	)
}

expect {
	# All truncated prefixes reject or provide a font whose queries stay total.
	[0, 1, 11, 64, 128, 256].all(
		|length| match Font.from_bytes(mark_mark.take_first(length), Font.ReadOptions.{}) {
			Err(_) => True
			Ok(font) => {
				run = Font.shape(font, "a\u(0301)\u(0300)", Font.ShapeOptions.{})
				run.glyphs.len() == run.offsets.len() and run.glyphs.len() == run.advances.len()
			}
		},
	)
}
