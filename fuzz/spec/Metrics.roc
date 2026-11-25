import build.FontBuild
import font.Font
import fuzz.Solve

# OpenType hmtx, hhea and maxp: a long metric stores an advance and a
# bearing, and each remaining glyph stores only its own bearing. The last
# long advance also serves every remaining glyph.
# https://learn.microsoft.com/en-us/typography/opentype/spec/hmtx
# https://learn.microsoft.com/en-us/typography/opentype/spec/hhea
# https://learn.microsoft.com/en-us/typography/opentype/spec/maxp
Metrics := [].{
	# The nonzero counts come from uint16 fields. Use 18 bits for
	# byte arithmetic, enough for 4 * 65535 (the largest long array).
	# This claim covers conforming counts, where the reader's clamp of
	# numberOfHMetrics to numGlyphs leaves the count unchanged.
	advance_offsets_fit : {} -> Bool
	advance_offsets_fit = |{}| {
		verdict = Solve.prove_within(
			{ long: Solve.u16, glyphs: Solve.u16, glyph: Solve.u16 }.Solve,
			|v| {
				long = v.long.to_width(18)
				glyphs = v.glyphs.to_width(18)
				glyph = v.glyph.to_width(18)
				has_advance = glyph.lt(long)
				# TableHmtx.from_tables: 4 * glyph.min(long - 1).
				row = Solve.if_else(has_advance, glyph, long - 1)
				at = 4 * row
				Solve.all([long.neq(0), long.lte(glyphs), glyph.lt(glyphs)]).implies(
					Solve.all([
						has_advance.implies(row.eq(glyph)),
						has_advance.not().implies((row + 1).eq(long)),
						(at + 2).lte(4 * long),
					]),
				)
			},
			512,
		)
		match verdict {
			Ok(Proved) => True
			other => crash "horizontal advance offset proof: ${Str.inspect(other)}"
		}
	}

	# The proof models arithmetic. Check that the compiled readers and
	# public queries assign the distinct advances and signed bearings to
	# the right glyphs at every split of this four-glyph table.
	read_at_split : U64 -> Bool
	read_at_split = |long| {
		advances = [65535, 0, 257, 32768]
		bearings = [-32768, 32767, -1, 256]
		outline = FontBuild.simple_glyph([
			[
				{ x: -4, y: -5, on: True },
				{ x: 16, y: -5, on: True },
				{ x: 16, y: 15, on: True },
			],
		])
		cmap = FontBuild.cmap([{ system: 3, encoding: 1, subtable: FontBuild.cmap4([]) }])
		bytes = FontBuild.outline_font(List.repeat(outline, 4), advances, bearings, long, False, cmap, [])
		font = match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
			Ok(value) => value
			Err(_) => return False
		}
		prefix = advances.take_first(long)
		widths = prefix.concat(List.repeat(prefix.last() ?? 0, 4 - long))
		boxes = bearings.map(
			|bearing| Extents({ x_min: bearing.to_i32_wrap(), x_max: (bearing + 20).to_i32_wrap(), y_min: -5, y_max: 15 }),
		)
		ids = [0, 1, 2, 3, 4, U32.highest]
		ids.map(|g| Font.advance(font, g)) == widths.map(|w| w.to_i32_wrap()).concat([0, 0])
			and ids.map(|g| Font.extents(font, g)) == boxes.concat([Empty, Empty])
	}

	# The last long row starts at 65536. An index narrowed to uint16
	# would see glyph zero's advance, and an out-of-range glyph must return 0.
	read_above_u16_offset : {} -> Bool
	read_above_u16_offset = |{}| {
		long = 16385
		glyphs = 65535
		metrics = List.repeat(0, 65536)
			.concat(FontBuild.hmtx([65000]))
			.concat(List.repeat(0, 2 * (glyphs - long)))
		tables = FontBuild.basic.map(
			|table| match table.tag {
				"hhea" => { tag: "hhea", data: FontBuild.hhea(800, -200, long) }
				"maxp" => { tag: "maxp", data: FontBuild.maxp(glyphs) }
				"hmtx" => { tag: "hmtx", data: metrics }
				_ => table
			},
		)
		match Font.from_bytes(FontBuild.file(tables), Font.ReadOptions.{ strict: True }) {
			Ok(font) => [16383, 16384, 16385, 65534, 65535].map(|g| Font.advance(font, g)) == [0, 65000, 65000, 65000, 0]
			Err(_) => False
		}
	}

	check : {} -> Bool
	check = |{}| Metrics.advance_offsets_fit({}) and [1, 2, 3, 4].all(Metrics.read_at_split) and Metrics.read_above_u16_offset({})
}
