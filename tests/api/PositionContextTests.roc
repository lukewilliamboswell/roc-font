import font.Font
import "../fonts/positioning/context-budget/many-256.ttf" as many_file : List(U8)
import "../fonts/positioning/context-budget/ignored-8192.ttf" as ignored_file : List(U8)
import "../fonts/positioning/context-budget/cycle-8192.ttf" as cycle_file : List(U8)
import "../fonts/positioning/context-budget/fanout-8192.ttf" as fanout_file : List(U8)
import "../fonts/positioning/context-budget/nested-order.ttf" as nested_file : List(U8)
import "../fonts/positioning/context-budget/attach-shift.ttf" as attach_file : List(U8)
import "../fonts/positioning/context-budget/shift-attach.ttf" as shift_file : List(U8)
import "../fonts/positioning/context-budget/context-1.ttf" as format1 : List(U8)
import "../fonts/positioning/context-budget/context-2.ttf" as format2 : List(U8)
import "../fonts/positioning/context-budget/context-3.ttf" as format3 : List(U8)
import "../fonts/positioning/context-budget/chain-1.ttf" as chain1 : List(U8)
import "../fonts/positioning/context-budget/chain-2.ttf" as chain2 : List(U8)
import "../fonts/positioning/context-budget/chain-3.ttf" as chain3 : List(U8)
import "../fonts/positioning/context-budget/wide-16383.ttf" as invalid_file : List(U8)

PositionContextTests :: {}.{}

read = |bytes, depth| match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True, limits: Font.Limits.{ max_depth: depth } }) {
	Ok(f) => f
	Err(ps) => crash Str.inspect(ps)
}

options = Font.ShapeOptions.{ script: "Latn", language: "en" }

checked = |bytes, depth, text| {
	f = read(bytes, depth)
	Font.shape_checked(f, Font.plan(f, options), text)
}
expect Font.shape(read(many_file, 64), "a", options).advances == [{ x: 766, y: 0 }]
expect match checked(many_file, 0, "a") {
	Err(OverBudget(r)) => r.budgets == [Depth] and r.run.advances == [{ x: 510, y: 0 }]
	_ => False
}
expect match checked(many_file, 1, "a") {
	Ok(r) => r.advances == [{ x: 766, y: 0 }]
	_ => False
}
expect match checked(ignored_file, 0, "a") {
	Ok(r) => r.advances == [{ x: 510, y: 0 }]
	_ => False
}
expect match checked(cycle_file, 3, "a") {
	Err(OverBudget(r)) => r.budgets.contains(Depth) and r.budgets.contains(Operations) and r.run.advances == [{ x: 510, y: 0 }]
	_ => False
}
expect match checked(fanout_file, 2, "a") {
	Err(OverBudget(r)) => r.budgets == [Operations] and r.run.advances == [{ x: 66038, y: 0 }]
	_ => False
}
expect {
	run = Font.shape(read(nested_file, 64), "a\u(301)", options)
	run.offsets == [{ x: 0, y: 0 }, { x: -396, y: 700 }]
}
expect {
	run = Font.shape(read(attach_file, 64), "a\u(301)", options)
	run.offsets == [{ x: 0, y: 0 }, { x: -403, y: 700 }]
}
expect {
	run = Font.shape(read(shift_file, 64), "a\u(301)", options)
	run.offsets == [{ x: 0, y: 0 }, { x: -410, y: 700 }]
}
expect [format1, format2, format3, chain1, chain2, chain3].all(
	|bytes| {
		run = Font.shape(read(bytes, 64), "a\u(301)b", options)
		run.glyphs == [1, 3, 2] and run.advances == [{ x: 510, y: 0 }, { x: 0, y: 0 }, { x: 537, y: 0 }] and run.clusters == [0, 0, 3]
	},
)
expect match Font.from_bytes(invalid_file, Font.ReadOptions.{ strict: True }) {
	Err(_) => True
	Ok(_) => False
}
expect match Font.from_bytes(invalid_file, Font.ReadOptions.{}) {
	Err(ps) => ps.any(
		|p| match p {
			BadTable(b) => b.table == "GPOS"
			_ => False
		},
	)
	Ok(_) => False
}
