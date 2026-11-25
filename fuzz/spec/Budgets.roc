import build.FontBuild
import font.Font

Budgets := [].{
	check : {} -> Bool
	check = |{}| {
		font = fixture({})
		plan = Font.plan(font, Font.ShapeOptions.{ limits: Font.ShapeLimits.{ operations: 1, growth: 1 } })
		# `A` spends 129 calls per glyph, even though none of its nested
		# lookups match. `D` spends one call before its child hits the
		# depth bound. For 127 As, B therefore takes the last slot
		# without D and is the first refused call with D.
		[
			{ prefix: "", count: 126, b: 3, expansion: 16256, budgets: [] },
			{ prefix: "", count: 127, b: 3, expansion: 16256, budgets: [] },
			{ prefix: "D", count: 126, b: 3, expansion: 16256, budgets: [Depth] },
			{ prefix: "D", count: 127, b: 2, expansion: 1, budgets: [Growth, Operations, Depth] },
			{ prefix: "", count: 128, b: 2, expansion: 1, budgets: [Growth, Operations] },
		].all(
			|c| {
				input = c.prefix.concat("A".repeat(c.count)).concat("BG")
				want = (if (c.prefix.is_empty()) [] else [4])
					.concat(List.repeat(1, c.count))
					.append(c.b)
					.concat(List.repeat(5, c.expansion))
				{ glyphs, budgets, complete } = match Font.shape_checked(font, plan, input) {
					Ok(run) => { glyphs: run.glyphs, budgets: [], complete: True }
					Err(OverBudget({ run, budgets: reasons })) => { glyphs: run.glyphs, budgets: reasons, complete: False }
				}
				if glyphs == want and budgets == c.budgets and complete == c.budgets.is_empty() {
					True
				} else {
					crash "budget case with prefix ${Str.inspect(c.prefix)} and ${c.count.to_str()} As: expected ${want.len().to_str()} glyphs and ${Str.inspect(c.budgets)}, got ${glyphs.len().to_str()} glyphs and ${Str.inspect(budgets)}, complete ${Str.inspect(complete)} (B became ${Str.inspect(glyphs.get(c.count + c.prefix.to_utf8().len()))})"
				}
			},
		)
	}
}

# Architecture §6.3 and Font.shape_checked specify the budget floor
# and a partial run with the bounds hit. Each of the four active
# lookups sees the current run. Consequently the earlier outcomes
# stay observable even when the last lookup reaches its own limit.
fixture : {} -> Font
fixture = |{}| {
	context = |glyph, child, calls|
		{ kind: 5, subtables: [FontBuild.context3([[glyph]], List.repeat({ at: 0, lookup: child }, calls))] }
	gsub = FontBuild.layout(
		"DFLT",
		[{ tag: "calt", lookups: [0, 1, 2, 3] }],
		[
			context(4, 4, 1),
			context(1, 5, 129),
			context(2, 6, 1),
			# G is glyph 5. In a 129-character run it expands exactly
			# to the 16384-glyph ceiling. A longer input must keep G.
			{ kind: 2, subtables: [FontBuild.multiple([5], [List.repeat(5, 16256)])] },
			context(4, 5, 1),
			{ kind: 1, subtables: [FontBuild.single2([4], [3])] },
			{ kind: 1, subtables: [FontBuild.single2([2], [3])] },
		],
	)
	cmap = FontBuild.cmap([
		{
			system: 3,
			encoding: 1,
			subtable: FontBuild.cmap4([{ first: 'A', last: 'D', delta: 65536 - 64, glyphs: [] }, { first: 'G', last: 'G', delta: 65536 + 5 - 'G', glyphs: [] }]),
		},
	])
	file = FontBuild.glyphs_font(List.repeat(500, 6), cmap, [{ tag: "GSUB", data: gsub }])
	Font.from_bytes(file, Font.ReadOptions.{ strict: True, limits: Font.Limits.{ max_depth: 1 } }) ?? crash "the shaping budget fixture did not read strictly"
}
