import build.FontBuild
import font.Font
import fuzz.Solve

# OpenType 1.9.1, DeltaSetIndexMap and horizontal metrics variations.
# https://learn.microsoft.com/en-us/typography/opentype/spec/otvarcommonformats#associating-target-items-to-variation-data
# https://learn.microsoft.com/en-us/typography/opentype/spec/hvar
DeltaMap := [].{
	# Solve takes a fixed shift operand. Prove the split for every inner
	# width and every packed U32, which includes the shorter entries.
	# As in TableVar.map_entry, the decoded arithmetic is on U64s.
	split : U8 -> Bool
	split = |bits| {
		radix = Solve.Uint.from_u64((1.U64).shl_wrap(bits))
		verdict = Solve.prove_within(
			Solve.u32,
			|entry| {
				packed = entry.to_width(64)
				outer = packed.shr_wrap(bits)
				inner = packed.bitwise_and(radix - 1)
				Solve.all([outer.eq(packed // radix), inner.eq(packed % radix)])
			},
			64,
		)
		match verdict {
			Ok(Proved) => True
			other => crash "DeltaSetIndexMap split at ${bits.to_str()} bits: ${Str.inspect(other)}"
		}
	}

	Index : { outer : U64, inner : U64 }

	index_map : U64, U64, U8, List(Index) -> List(U8)
	index_map = |format, size, bits, entries| {
		span = (1.U64).shl_wrap(bits)
		entry_format = 16 * (size - 1) + bits.to_u64() - 1
		count = if (format == 0) FontBuild.u16(entries.len()) else FontBuild.u32(entries.len())
		packed = entries.join_map(|e| FontBuild.u32(e.outer * span + e.inner).take_last(size))
		[format.to_u8_wrap(), entry_format.to_u8_wrap()].concat(count).concat(packed)
	}

	# One region with full weight at the Black master so the observable
	# advance uses exactly the chosen variation sum.
	variation_store : List(List(I64)), List(List(I64)) -> List(U8)
	variation_store = |first, second| FontBuild.variation_store(
		1,
		[[{ start: 0, peak: 16384, end: 16384 }]],
		[
			{ regions: [0], rows: first },
			{ regions: [0], rows: second },
		],
	)

	advances : List(U8), List(U8) -> List(I32)
	advances = |store, mapping| {
		hvar = FontBuild.pack([U16(1), U16(0), Ref32(store), Ref32(mapping), U32(0), U32(0)])
		fvar = FontBuild.fvar([{ tag: "wght", min: 100, default: 400, max: 900 }])
		file = FontBuild.file(FontBuild.basic.concat([{ tag: "fvar", data: fvar }, { tag: "HVAR", data: hvar }]))
		font = match Font.from_bytes(file, Font.ReadOptions.{ strict: True }) {
			Ok(value) => value
			Err(problems) => crash "valid HVAR map was refused: ${Str.inspect(problems)}"
		}
		master = Font.at(font, Font.Variation.{ weight: Black })
		[0, 1, 2, 3, 4].map(|g| Font.advance(master, g))
	}

	# Both count formats and each entry size/inner width with enough
	# space for the inner field. When room remains, the last entry selects
	# outer subtable 1. Glyph 3 repeats this entry and glyph 4 is absent.
	encodings : {} -> Bool
	encodings = |{}| {
		store = DeltaMap.variation_store([[11], [-23]], [[37], [89]])
		for format in [0, 1] {
			for size in 1..=4 {
				for bits in 1.U8..=(8 * size).min(16).to_u8_wrap() {
					outer = if (bits.to_u64() < 8 * size) 1 else 0
					mapping = DeltaMap.index_map(format, size, bits, [{ outer: 0, inner: 1 }, { outer: 0, inner: 0 }, { outer, inner: 1 }])
					actual = DeltaMap.advances(store, mapping)
					expected = if (outer == 0) [477, 611, 677, 777, 0] else [477, 611, 789, 889, 0]
					if actual != expected {
						crash "HVAR format ${format.to_str()}, ${size.to_str()} bytes, ${bits.to_str()} inner bits gave advances ${Str.inspect(actual)}, expected ${Str.inspect(expected)}"
					}
				}
			}
		}
		True
	}

	# The last entry is 01 80 00. Both the leading byte and the high inner
	# bit are significant. Neither row zero can give the correct answer.
	high_row : U64 -> Bool
	high_row = |row| {
		store = DeltaMap.variation_store([[-11]], List.repeat([37], row).append([113]))
		mapping = DeltaMap.index_map(1, 3, 16, [{ outer: 0, inner: 0 }, { outer: 1, inner: row }])
		actual = DeltaMap.advances(store, mapping)
		if actual != [489, 713, 813, 913, 0] {
			crash "Three-byte HVAR entry did not select subtable 1, row ${row.to_str()}. Advances were ${Str.inspect(actual)}"
		}
		True
	}

	check : {} -> Bool
	check = |{}| FontBuild.counting(16).all(|i| DeltaMap.split((i + 1).to_u8_wrap())) and DeltaMap.encodings({}) and DeltaMap.high_row(32768)
}
