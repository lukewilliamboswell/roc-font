import build.FontBuild
import font.Font

# OpenType 1.9.1 defines each table as an aligned file-relative start
# and its actual data length. This fixture puts a private table at EOF
# and can move its directory record without moving any table data.
# https://learn.microsoft.com/en-us/typography/opentype/spec/otff#table-directory
TableDirectory := {}.{
	check : {} -> Bool
	check = |_| {
		[Early, Late].all(
			|order| [ExactEnd, Spills, StartsAtEnd, Empty, InDirectory, Unaligned].all(
				|boundary| [False, True].all(
					|bad_metrics| [False, True].all(|bad_axes| agrees(order, boundary, bad_metrics, bad_axes)),
				),
			),
		)
	}
}

Order : [Early, Late]

Boundary : [ExactEnd, Spills, StartsAtEnd, Empty, InDirectory, Unaligned]

bad : Str, U64 -> Font.Problem
bad = |table, offset| BadTable({ table, offset: offset.to_u32_wrap() })

record_size : U64
record_size = 16

read_u32 : List(U8), U64 -> U64
read_u32 = |bytes, at| bytes.sublist({ start: at, len: 4 }).fold(0, |word, byte| 256 * word + byte.to_u64())

agrees : Order, Boundary, Bool, Bool -> Bool
agrees = |order, boundary, bad_metrics, bad_axes| {
	axes = FontBuild.fvar([{ tag: "wght", min: 100, default: 400, max: 900 }])
	tables = FontBuild.basic.concat([
		{ tag: "fvar", data: if (bad_axes) FontBuild.patch(axes, 10, FontBuild.u16(19)) else axes },
		{ tag: "ZZZZ", data: [81, 82, 83, 84] },
	])
	raw = FontBuild.file(tables)
	size = raw.len()
	tail = size - 4
	first_table = 12 + record_size * tables.len()
	(offset, length, private_problems) = match boundary {
		ExactEnd => (tail, 4, [])
		Spills => (tail, 5, [bad("ZZZZ", tail)])
		StartsAtEnd => (size, 4, [bad("ZZZZ", size)])
		Empty => (tail, 0, [bad("ZZZZ", tail)])
		InDirectory => (first_table - 4, 4, [bad("ZZZZ", first_table - 4)])
		Unaligned => (tail + 1, 3, [bad("ZZZZ", tail + 1)])
	}
	# The basic fixture puts hmtx at record 3. Pointing it at EOF
	# produces one problem even though both checks discover it.
	metrics_field = 12 + record_size * 3 + 8
	metrics_problems = if (bad_metrics) [bad("hmtx", size)] else []
	patched = if (bad_metrics) FontBuild.patch(raw, metrics_field, FontBuild.u32(size)) else raw

	# The record before the private record describes fvar. Its axis size
	# field is ten bytes from the table's start.
	last_record = first_table - record_size
	axes_offset = read_u32(raw, last_record - record_size + 8)
	dropped = if (bad_axes) [bad("fvar", axes_offset + 10)] else []
	changed = FontBuild.patch(patched, last_record + 8, FontBuild.u32(offset).concat(FontBuild.u32(length)))
	(bytes, required) = match order {
		Early => {
			header = changed.take_first(12)
			last = changed.sublist({ start: last_record, len: record_size })
			rest = changed.sublist({ start: 12, len: last_record - 12 })
			(header.concat(last).concat(rest).concat(changed.drop_first(first_table)), private_problems.concat(metrics_problems))
		}
		Late => (changed, metrics_problems.concat(private_problems))
	}
	all_problems = required.concat(dropped)
	if Font.face_count(bytes) != Ok(1)
		or !read_agrees(bytes, False, required, dropped)
		or !read_agrees(bytes, True, required, dropped) {
		crash "directory ${Str.inspect((order, boundary, bad_metrics, bad_axes))} expected ${Str.inspect(all_problems)}"
	}
	True
}

read_agrees : List(U8), Bool, List(Font.Problem), List(Font.Problem) -> Bool
read_agrees = |bytes, strict, required, dropped| {
	rejects = !required.is_empty() or (strict and !dropped.is_empty())
	match Font.from_bytes(bytes, Font.ReadOptions.{ strict }) {
		Err(problems) => rejects and problems == required.concat(dropped)
		Ok(font) => !rejects and Font.dropped(font) == dropped and Font.glyph(font, 'A') == Ok(1) and Font.advance(font, 1) == 600
	}
}
