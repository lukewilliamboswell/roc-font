import font.Font
import build.FontBuild
import "../fonts/aat-position/kerx0.ttf" as pair_file : List(U8)
import "../fonts/aat-position/kerx1.ttf" as state_file : List(U8)
import "../fonts/aat-position/kerx1-tuple.ttf" as tuple_file : List(U8)
import "../fonts/aat-position/kerx1-cross.ttf" as cross_file : List(U8)
import "../fonts/aat-position/kerx2.ttf" as matrix_file : List(U8)
import "../fonts/aat-position/kerx6-long.ttf" as long_file : List(U8)
import "../fonts/aat-position/kerx4-coordinate.ttf" as coordinate_file : List(U8)
import "../fonts/aat-position/kerx4-anchor.ttf" as anchor_file : List(U8)
import "../fonts/aat-position/kerx4-point.ttf" as point_file : List(U8)
import "../fonts/aat-position/kerx4-point-variable.ttf" as variable_file : List(U8)
import "../fonts/aat-position/kerx4-vertical.ttf" as vertical_file : List(U8)
import "../fonts/aat-position/kerx-empty.ttf" as empty_file : List(U8)
import "../fonts/aat-position/apple-kern2.ttf" as apple_file : List(U8)
import "../fonts/aat-position/apple-variation-skipped.ttf" as skipped_file : List(U8)

import "../fonts/aat-position/kerx1-cycle.ttf" as cycle_file : List(U8)
import "../fonts/aat-position/kerx4-point-wide-positive-1.ttf" as wide_one : List(U8)
import "../fonts/aat-position/kerx4-point-wide-positive-2.ttf" as wide_two : List(U8)

## AAT positioning through the public bundle. Full numeric coverage and
## actual reference provenance live in aat-position/cases.jsonc.
AatPositionTests :: {}.{}

read : List(U8) -> Font
read = |bytes| match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
	Ok(f) => f
	Err(ps) => crash Str.inspect(ps)
}

summary : List(U8) -> { advances : List({ x : I32, y : I32 }), offsets : List({ x : I32, y : I32 }) }
summary = |bytes| {
	run = Font.shape(read(bytes), "ab", Font.ShapeOptions.{ script: "Latn", language: "en" })
	{ advances: run.advances, offsets: run.offsets }
}
expect [pair_file, matrix_file, long_file, apple_file].all(|bytes| summary(bytes) == { advances: [{ x: 484, y: 0 }, { x: 495, y: 0 }], offsets: [{ x: 0, y: 0 }, { x: -25, y: 0 }] })
expect [state_file, tuple_file].all(|bytes| summary(bytes) == { advances: [{ x: 470, y: 0 }, { x: 500, y: 0 }], offsets: [{ x: -40, y: 0 }, { x: -20, y: 0 }] })
expect summary(cross_file) == { advances: [{ x: 510, y: 0 }, { x: 520, y: 0 }], offsets: [{ x: 0, y: -40 }, { x: 0, y: -60 }] }
expect [coordinate_file, anchor_file].all(|bytes| summary(bytes) == { advances: [{ x: 510, y: 0 }, { x: 520, y: 0 }], offsets: [{ x: 0, y: 0 }, { x: -160, y: 500 }] })
expect summary(point_file).offsets == [{ x: 0, y: 0 }, { x: -110, y: 700 }]
expect {
	f = Font.at(read(variable_file), Font.Variation.{ axes: [{ tag: "wght", value: 1 }] })
	run = Font.shape(f, "ab", Font.ShapeOptions.{ script: "Latn" })
	run.offsets == [{ x: 0, y: 0 }, { x: -10, y: 750 }]
}
expect {
	run = Font.shape(read(vertical_file), "ab", Font.ShapeOptions.{ script: "Latn", direction: TopToBottom })
	run.advances == [{ x: 0, y: -710 }, { x: 0, y: -720 }] and run.offsets == [{ x: -255, y: -800 }, { x: 350, y: 410 }]
}
expect summary(skipped_file) == { advances: [{ x: 510, y: 0 }, { x: 520, y: 0 }], offsets: [{ x: 0, y: 0 }, { x: 0, y: 0 }] }
expect {
	run = Font.shape(read(empty_file), "a\u(0301)b", Font.ShapeOptions.{ script: "Latn" })
	run.advances == [{ x: 510, y: 0 }, { x: 540, y: 0 }, { x: 520, y: 0 }] and run.offsets == [{ x: 0, y: 0 }, { x: 0, y: 0 }, { x: 0, y: 0 }]
}
expect {
	f = read(pair_file)
	disabled = Font.shape(f, "ab", Font.ShapeOptions.{ features: [Font.Feature.{ tag: "kern", value: 0 }] })
	disabled.advances == [{ x: 510, y: 0 }, { x: 520, y: 0 }] and disabled.offsets == [{ x: 0, y: 0 }, { x: 0, y: 0 }]
}
expect [pair_file, state_file, anchor_file, point_file].all(|bytes| Font.dropped(read(bytes)).is_empty())

source : Font
source = read(anchor_file)

table : Str -> List(U8)
table = |tag| match Font.table_bytes(source, tag) {
	Present(b) => b
	Absent => []
}

source_tables : List({ tag : Str, data : List(U8) })
source_tables = ["head", "hhea", "maxp", "hmtx", "cmap", "loca", "glyf", "name", "OS/2", "post", "GDEF", "vhea", "vmtx", "ankr", "kerx"].keep_oks(
	|tag| match Font.table_bytes(source, tag) {
		Present(data) => Ok({ tag, data })
		Absent => Err({})
	},
)

broken : Str, List(U8) -> Bool
broken = |tag, data| {
	bytes = FontBuild.file(FontBuild.replace(source_tables, tag, data))
	match (Font.from_bytes(bytes, Font.ReadOptions.{}), Font.from_bytes(bytes, Font.ReadOptions.{ strict: True })) {
		(Ok(f), Err(ps)) => !ps.is_empty() and !Font.dropped(f).is_empty() and Font.dropped(f).all(
			|p| match p {
				BadTable(b) => b.table == tag
				_ => False
			},
		)
		_ => False
	}
}
expect [1.U64, 7, 8, 19, table("kerx").len() - 1].all(|n| broken("kerx", table("kerx").take_first(n)))
expect broken("kerx", FontBuild.patch(table("kerx"), 0, [0, 5]))
expect broken("kerx", FontBuild.patch(table("kerx"), 12, [0, 0, 1, 4]))
expect broken("kerx", FontBuild.patch(table("kerx"), 4, [255, 255, 255, 255]))
expect broken("kerx", FontBuild.patch(table("kerx"), 8, [255, 255, 255, 255]))
expect [1.U64, 11, table("ankr").len() - 1].all(|n| broken("ankr", table("ankr").take_first(n)))
expect broken("ankr", FontBuild.patch(table("ankr"), 0, [0, 1]))
expect broken("ankr", FontBuild.patch(table("ankr"), 8, [255, 255, 255, 255]))
expect {
	data = FontBuild.patch(FontBuild.patch(table("ankr"), 0, [0, 1]), 2, [0, 1])
	bytes = FontBuild.file(FontBuild.replace(source_tables, "ankr", data))
	match Font.from_bytes(bytes, Font.ReadOptions.{}) {
		Ok(f) => Font.dropped(f).len() == 2
		Err(_) => False
	}
}
# Missing dynamic anchor points abort the action, retaining defined
# output; an absent reference never becomes a point from glyph0.
expect {
	bytes = FontBuild.file(FontBuild.replace(source_tables, "ankr", table("ankr").take_first(11)))
	match Font.from_bytes(bytes, Font.ReadOptions.{}) {
		Ok(f) => Font.shape(f, "ab", Font.ShapeOptions.{ script: "Latn" }).offsets == [{ x: 0, y: 0 }, { x: 0, y: 0 }]
		Err(_) => False
	}
}

# Numeric gvar materialization oracle: FreeType 2.13.2 ignores these
# newer 32-bit packed runs, so these numbers explicitly use fontTools
# direct coordinates, binary32 rounding and signed I32 wrap instead.
expect {
	f = Font.at(read(wide_one), Font.Variation.{ axes: [{ tag: "wght", value: 1 }] })
	Font.shape(f, "ab", Font.ShapeOptions.{ script: "Latn" }).offsets == [{ x: 0, y: 0 }, { x: -2147483648, y: 700 }]
}
expect {
	f = Font.at(read(wide_two), Font.Variation.{ axes: [{ tag: "wght", value: 1 }] })
	Font.shape(f, "ab", Font.ShapeOptions.{ script: "Latn" }).offsets == [{ x: 0, y: 0 }, { x: -48, y: 700 }]
}
expect {
	f = read(cycle_file)
	match Font.shape_checked(f, Font.plan(f, Font.ShapeOptions.{ script: "Latn" }), "ab") {
		Err(OverBudget(r)) => r.run.glyphs.len() == 2 and r.budgets.contains(Operations)
		_ => False
	}
}
expect {
	run = Font.shape(read(state_file), "ab", Font.ShapeOptions.{ script: "Latn", features: [Font.Feature.{ tag: "kern", value: 0, start: 0, end: 1 }] })
	run.advances == [{ x: 510, y: 0 }, { x: 500, y: 0 }] and run.offsets == [{ x: 0, y: 0 }, { x: -20, y: 0 }]
}
