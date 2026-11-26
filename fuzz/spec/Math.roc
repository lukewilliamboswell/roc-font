import build.FontBuild
import font.Font
import fuzz.Solve

# OpenType 1.9.1 §MATH, MathKern table.
# https://learn.microsoft.com/en-us/typography/opentype/spec/math#mathkern-table
Math := [].{
	# TableMath.kern uses slot lo on a miss and mid + 1 on equality.
	# A slot in 0..=heightCount must name a full four-byte MathValueRecord
	# inside the prepared subtable. A 19-bit term
	# can hold the largest end offset, 8 * 65535 + 6.
	rows_fit : {} -> Bool
	rows_fit = |{}| {
		verdict = Solve.prove_within(
			{ count: Solve.u16, slot: Solve.u16 }.Solve,
			|v| {
				n = v.count.to_width(19)
				slot = v.slot.to_width(19)
				# The query's value offset and the reader's checked end,
				# both relative to the start of the MathKern table.
				record = 2 + 4 * (n + slot)
				end = 2 + 4 * (2 * n + 1)
				slot.lte(n).implies(
					Solve.all([
						(2 + 4 * n).lte(record),
						(record + 4).lte(end),
					]),
				)
			},
			3000,
		)
		match verdict {
			Ok(Proved) => True
			other => crash "MathKern row proof: ${Str.inspect(other)}"
		}
	}

	kern_value : U64 -> I64
	kern_value = |index| (index % 251).to_i64_wrap() - 125

	# The count field is uint16, but the two record arrays together can
	# exceed that many records. The strict reader accepts their maximum
	# length, and lookups must reach the final value on either path.
	maximum_table : {} -> List(U8)
	maximum_table = |{}| {
		n = 65535
		heights = FontBuild.counting(n).join_map(|i| FontBuild.i16(i.to_i64_wrap() - 32768).concat([0, 0]))
		values = FontBuild.counting(n + 1).join_map(|i| FontBuild.i16(Math.kern_value(i)).concat([0, 0]))
		kern = FontBuild.u16(n).concat(heights).concat(values)
		info = FontBuild.pack([
			U16(0),
			U16(0),
			U16(0),
			Ref(FontBuild.pack([Ref(FontBuild.coverage1([1])), U16(1), Ref(kern), U16(0), U16(0), U16(0)])),
		])
		constants = List.repeat(0, 214)
		variants = List.repeat(0, 10)
		# Put the large glyph info last so every relative offset fits uint16.
		header = FontBuild.pack([U16(1), U16(0), U16(10), U16(10 + constants.len() + variants.len()), U16(10 + constants.len())])
		header.concat(constants).concat(variants).concat(info)
	}

	maximum_queries : List(U8) -> Bool
	maximum_queries = |bytes| {
		font = match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
			Ok(value) => value
			Err(problems) => crash "maximum MathKern count was refused: ${Str.inspect(problems)}"
		}
		heights = [I64.lowest, -32769, -32768, -32767, -2, -1, 0, 1, 32765, 32766, 32767, I64.highest]
		slots = [0, 0, 1, 2, 32767, 32768, 32769, 32770, 65534, 65535, 65535, 65535]
		expected = slots.map(Math.kern_value)
		selected = heights.map(|h| Font.math_kern(font, 1, TopRight, h))
		if selected != expected {
			crash "MathKern selected ${Str.inspect(selected)} for heights ${Str.inspect(heights)}, expected ${Str.inspect(expected)}"
		}
		table = Font.math_kern_table(font, 1, TopRight)
		table.heights.len() == 65535
			and table.values.len() == 65536
			and slots.map(|slot| table.values.get(slot)) == expected.map(|value| Ok(value))
	}

	check : {} -> Bool
	check = |{}| Math.rows_fit({}) and Math.maximum_queries(FontBuild.parity_font([{ tag: "MATH", data: Math.maximum_table({}) }]))
}
