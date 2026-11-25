import build.FontBuild
import font.Font
import fuzz.Model

ScalarShaping := {}.{
	check : {} -> Bool
	check = |_| {
		[Ltr, Rtl].all(
			|direction| {
				result = Model.explore(machine(direction), { depth: 4, key: |state| state, verify: EveryStep })
				if result.verdict == Holds(Exhausted) and result.states == 85 and result.reached.len() == 2 {
					True
				} else {
					crash "source cluster model ${Str.inspect(result)}"
				}
			},
		) and [16382, 16383].all(growth_edge)
	}
}

Direction : [Ltr, Rtl]

# The first two source entries share an absolute cluster start above U32.
# The third is separate, so a ligature can merge distinct source starts.
base : U64
base = 4294967396

fixture : U64 -> Font
fixture = |expansion| {
	lookup = |kind, data| { kind, subtables: [data] }
	ligature = lookup(4, FontBuild.ligature([1], [[{ glyph: 4, rest: [2] }]]))
	multiple = if (expansion == 2) lookup(2, FontBuild.multiple([3], [[5, 6]])) else lookup(2, FontBuild.multiple([1], [List.repeat(5, expansion)]))
	gsub = FontBuild.layout("DFLT", [{ tag: "ccmp", lookups: [0, 1] }], [ligature, multiple])
	cmap = FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 0x05D0, last: 0x05D2, glyph: 1 }]) }])
	result = FontBuild.glyphs_font([500, 501, 502, 503, 504, 505, 506], cmap, [{ tag: "GSUB", data: gsub }])
	Font.from_bytes(result, Font.ReadOptions.{ strict: True }) ?? crash "scalar fixture did not read strictly"
}

offset : U64 -> U64
offset = |index| if (index < 2) base else base + 4

input : List(U32) -> List({ scalar : U32, offset : U64 })
input = |letters| letters.map_with_index(|scalar, index| { scalar, offset: offset(index) })

Row : { glyph : U32, cluster : U64, origin : Font.GlyphOrigin }

# The disjoint rules join adjacent alef + bet and expand gimel. Track
# original clusters through those changes before placing rows in visual order.
expected : List(U32) -> List(Row)
expected = |letters| {
	var $rows = []
	var $index = 0
	while $index < letters.len() {
		cp = letters.get($index) ?? 0
		cluster = offset($index)
		if cp == 0x05D0 and letters.get($index + 1) == Ok(0x05D1) {
			$rows = $rows.append({ glyph: 4, cluster, origin: Ligature({ feature: "ccmp", components: 2 }) })
			$index = $index + 2
		} else {
			$rows = if cp == 0x05D2 {
				$rows.append({ glyph: 5, cluster, origin: Multiple({ feature: "ccmp" }) }).append({ glyph: 6, cluster, origin: Inserted({ feature: "ccmp" }) })
			} else {
				glyph = if (cp == 0x05D0) 1 else if (cp == 0x05D1) 2 else 0
				$rows.append({ glyph, cluster, origin: Mapped })
			}
			$index = $index + 1
		}
	}
	$rows
}

agrees : Font, Font.ShapePlan, Direction, List(U32) -> Bool
agrees = |font, plan, direction, letters| {
	logical = expected(letters)
	want = if (direction == Rtl) logical.fold([], |rows, row| rows.prepend(row)) else logical
	scalars = input(letters)
	match (Font.shape_scalars_checked(font, plan, scalars), Font.shape_scalars_traced(font, plan, scalars)) {
		(Ok(run), Ok(traced)) => {
			origins = want.map(|row| row.origin)
			run == traced.run
				and run == Font.shape_scalars(font, plan, scalars)
				and run.glyphs == want.map(|row| row.glyph)
				and run.clusters == want.map(|row| row.cluster)
				and run.advances == want.map(|row| { x: 500 + row.glyph.to_i32_wrap(), y: 0 })
				and run.offsets == List.repeat({ x: 0, y: 0 }, want.len())
				and run.flags.map(Font.is_missing) == want.map(|row| row.glyph == 0)
				and traced.origins == origins
		}
		_ => False
	}
}

machine : Direction -> Model.Machine(List(U32), U32)
machine = |direction| {
	font = fixture(2)
	plan = Font.plan(font, Font.ShapeOptions.{ script: if (direction == Rtl) "Hebr" else "Latn", direction: if (direction == Rtl) RightToLeft else LeftToRight })
	{
		init: [],
		actions: |letters| if (letters.len() < 3) [0x05D0, 0x05D1, 0x05D2, 'X'] else [],
		step: |letters, cp| letters.append(cp),
		rules: [
			Model.always("glyph fields and origins agree with source slots", |letters| agrees(font, plan, direction, letters)),
			Model.sometimes("a ligature coalesces different source starts", |letters| letters == ['X', 0x05D0, 0x05D1]),
			Model.sometimes("a multiple replacement adds a glyph to a shared cluster", |letters| letters == [0x05D0, 0x05D2]),
		],
	}
}

growth_edge : U64 -> Bool
growth_edge = |expansion| {
	font = fixture(expansion)
	plan = Font.plan(font, Font.ShapeOptions.{ script: "Hebr", direction: RightToLeft, limits: Font.ShapeLimits.{ growth: 1 } })
	scalars = input([0x05D0, 0x05D2, 'X'])
	switch = expansion == 16382
	want = if (switch) [0, 3].concat(List.repeat(5, expansion)) else [0, 3, 1]
	clusters = [base + 4].concat(List.repeat(base, want.len() - 1))
	projection = |run| run.glyphs == want and run.clusters == clusters and run == Font.shape_scalars(font, plan, scalars)
	match (Font.shape_scalars_checked(font, plan, scalars), Font.shape_scalars_traced(font, plan, scalars), Font.shape_checked(font, plan, "אגX")) {
		(Ok(run), Ok(traced), Ok(text)) => switch and projection(run) and run.glyphs == text.glyphs and traced.run == run and traced.origins.len() == want.len()
		(Err(OverBudget({ run, budgets: [Growth] })), Err(OverBudget({ run: traced, budgets: [Growth], origins: [Mapped, Mapped, Mapped] })), Err(OverBudget({ run: text, budgets: [Growth] }))) =>
			!switch and projection(run) and run.glyphs == text.glyphs and traced == run
		_ => False
	}
}
