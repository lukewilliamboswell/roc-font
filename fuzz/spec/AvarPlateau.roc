import build.FontBuild
import font.Font
import fuzz.Model

# avar targets can repeat at different input knots. The plateau holds
# the same signed coordinate and advance, and its adjacent segments
# retain their individual slopes. HarfBuzz 14.6.0 agrees at each point.
# https://learn.microsoft.com/en-us/typography/opentype/spec/avar
AvarPlateau := {}.{
	check : {} -> Bool
	check = |_| {
		font = fixture({})
		machine : Model.Machine(World, Place)
		machine = {
			init: { font, place: Default },
			actions: |_| [Limit, Before, Start, Inside, End, After, Default],
			step: |world, place| {
				(design, _) = coordinates(place)
				{ place, font: Font.at(world.font, Font.Variation.{ axes: [{ tag: "XPLT", value: design }] }) }
			},
			rules: [
				Model.always("the signed mapped coordinate determines the glyph advance", agrees),
				Model.sometimes_step("cross the plateau entry from the sloped segment", |{ before, action, after: _ }| before.place == Before and action == Start),
				Model.sometimes_step("move between the equal-valued plateau knots", |{ before, action, after: _ }| before.place == End and action == Start),
				Model.sometimes_step("leave the plateau across the adjacent design step", |{ before, action, after: _ }| before.place == End and action == After),
			],
		}
		result = Model.explore(machine, { depth: 2, key: |world| world.place, verify: EveryStep })
		if result.verdict == Holds(Exhausted) and result.states == 7 and result.reached.len() == 3 {
			True
		} else {
			crash "avar plateau model: ${Str.inspect(result)}"
		}
	}
}

Place : [Limit, Before, Start, Inside, End, After, Default]

World : { font : Font, place : Place }

# Below the plateau, the slope is 3/2. One input step before its start
# gives -4097.5, which rounds toward positive infinity on the final tie.
# Above the plateau the map has slope one.
coordinates : Place -> (Dec, I16)
coordinates = |place| match place {
	Limit => (-17000, -16384)
	Before => (-8193, -4097)
	Start => (-8192, -4096)
	Inside => (-6000, -4096)
	End => (-4096, -4096)
	After => (-4095, -4095)
	Default => (0, 0)
}

agrees : World -> Bool
agrees = |world| {
	(_, mapped) = coordinates(world.place)
	Font.coordinates(world.font) == [{ tag: "XPLT", value: mapped }] and Font.advance(world.font, 1) == 20000 + mapped.to_i32()
}

fixture : {} -> Font
fixture = |_| {
	fvar = FontBuild.fvar([{ tag: "XPLT", min: -16384, default: 0, max: 16384 }])
	avar = FontBuild.avar([[{ from: -16384, to: -16384 }, { from: -8192, to: -4096 }, { from: -4096, to: -4096 }, { from: 0, to: 0 }, { from: 16384, to: 16384 }]])
	regions = [[{ start: -16384, peak: -16384, end: 0 }], [{ start: 0, peak: 16384, end: 16384 }]]
	store = FontBuild.variation_store(1, regions, [{ regions: [0, 1], rows: [[0, 0], [-16384, 16384]] }])
	cmap = FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 'A', last: 'A', glyph: 1 }]) }])
	bytes = FontBuild.glyphs_font([500, 20000], cmap, [{ tag: "fvar", data: fvar }, { tag: "avar", data: avar }, { tag: "HVAR", data: FontBuild.hvar(store, []) }])
	Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "valid avar plateau rejected"
}
