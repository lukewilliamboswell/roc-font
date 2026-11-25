import build.FontBuild
import font.Font
import fuzz.Model

# OpenType 1.9.1, Font Collection File Structure and TTC Header.
# https://learn.microsoft.com/en-us/typography/opentype/spec/otff#font-collections
# The header offset array names the faces. Each face uses its own
# cmap, and a shared metrics table can be before or after its directory.
Collection := {}.{
	check : {} -> Bool
	check = |_| {
		result = Model.explore(machine, { depth: 6, key: |world| (world.order, world.shared), verify: EveryStep })
		if result.verdict == Holds(Exhausted) and result.states == 24 and result.reached.len() == 4 {
			True
		} else {
			crash "collection model: ${Str.inspect(result)}"
		}
	}
}

World : { bytes : List(U8), order : List(U64), shared : U8 }

Action : [SwapFront, SwapBack, ShareFromLater, ShareFromEarlier]

faces : List(U64)
faces = [0, 1, 2]

fixture : List(U8)
fixture = FontBuild.collection(
	faces.map(
		|face| {
			cmap = FontBuild.cmap([{ system: 3, encoding: 1, subtable: FontBuild.cmap4([{ first: 'A', last: 'A', delta: 65536 - 64 + face, glyphs: [] }]) }])
			FontBuild.basic.map(
				|table| match table.tag {
					"cmap" => { tag: table.tag, data: cmap }
					"hmtx" => { tag: table.tag, data: FontBuild.hmtx([0, 1, 2, 3].map(|glyph| 500 + 100 * glyph + 10 * face)) }
					_ => table
				},
			)
		},
	),
)

offset_at : List(U8), U64 -> U64
offset_at = |bytes, at| bytes.sublist({ start: at, len: 4 }).fold(0, |offset, byte| 256 * offset + byte.to_u64())

metric_field : U64 -> U64
metric_field = |physical| {
	# The layout of FontBuild.basic puts hmtx in record 3. Its offset
	# is 8 bytes into that record, after the directory's 12-byte header.
	directory = offset_at(fixture, 12 + 4 * physical)
	directory + 12 + 16 * 3 + 8
}

swap : World, U64 -> World
swap = |world, first| {
	at = 12 + 4 * first
	left = offset_at(world.bytes, at)
	right = offset_at(world.bytes, at + 4)
	bytes = FontBuild.patch(FontBuild.patch(world.bytes, at, FontBuild.u32(right)), at + 4, FontBuild.u32(left))
	order = world.order.swap(first, first + 1) ?? crash "three face labels are always present"
	{ ..world, bytes, order }
}

share : World, U64, U8 -> World
share = |world, physical, flag| {
	# Both other directories can point to the middle face's hmtx. The
	# original tables stay in the file to expose accidental private reads.
	middle = offset_at(fixture, metric_field(1))
	bytes = FontBuild.patch(world.bytes, metric_field(physical), FontBuild.u32(middle))
	{ ..world, bytes, shared: world.shared.bitwise_or(flag) }
}

agrees : World -> Bool
agrees = |world| {
	Font.face_count(world.bytes) == Ok(3)
		and world.order.map_with_index(
			|physical, face| {
				options = Font.ReadOptions.{ face: face.to_u32_wrap(), strict: True }
				match Font.from_bytes(world.bytes, options) {
					Ok(font) => {
						glyph = (physical + 1).to_u32_wrap()
						uses_shared = (physical == 0 and world.shared.bitwise_and(1) != 0) or (physical == 2 and world.shared.bitwise_and(2) != 0)
						provider = if (uses_shared) 1 else physical
						advance = (500 + 100 * (physical + 1) + 10 * provider).to_i32_wrap()
						Font.glyph(font, 'A') == Ok(glyph) and Font.advance(font, glyph) == advance
					}
					Err(problems) => crash "collection face ${face.to_str()}: ${Str.inspect(problems)}"
				}
			},
		).all(|agree| agree)
}

machine : Model.Machine(World, Action)
machine = {
	init: { bytes: fixture, order: faces, shared: 0 },
	actions: |_| [SwapFront, SwapBack, ShareFromLater, ShareFromEarlier],
	step: |world, action| match action {
		SwapFront => swap(world, 0)
		SwapBack => swap(world, 1)
		ShareFromLater => share(world, 0, 1)
		ShareFromEarlier => share(world, 2, 2)
	},
	rules: [
		Model.always("face selection follows the header and each absolute table offset", agrees),
		Model.sometimes("a directory uses a later face's table", |world| world.shared == 1),
		Model.sometimes("a directory uses an earlier face's table", |world| world.shared == 2),
		Model.sometimes("the logical face order reverses the physical directory order", |world| world.order == [2, 1, 0]),
		Model.sometimes("reversing the face order preserves table sharing", |world| world.order == [2, 1, 0] and world.shared == 3),
	],
}
