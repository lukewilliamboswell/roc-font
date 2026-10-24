import Bytes

## The sfnt container: the table directory at the start of a TrueType or
## OpenType font file, and checked access to the tables it lists.
##
## Internal. Every table module reads its table through `table` or
## `required`, which check that the table lies inside the file and holds at
## least the bytes its fixed header needs, and return a view of those bytes
## without copying them.
Sfnt :: {}.{

	## One table directory record: the table's tag as a big-endian number,
	## and its offset and length in the file.
	Table : { tag : U64, offset : U64, length : U64 }

	## The table records of a font file with a TrueType (`0x00010000` or
	## `true`) or OpenType (`OTTO`) signature. Collections are not a font.
	directory : List(U8) -> Try(List(Table), [NotAFont])
	directory = |bytes| {
		version = Bytes.u32(bytes, 0)
		count = Bytes.u16(bytes, 4)
		if bytes.len() < 12 or (version != 0x00010000 and version != 0x74727565 and version != 0x4F54544F) {
			Err(NotAFont)
		} else if !Bytes.fits(12, 16 * count, bytes.len()) {
			Err(NotAFont)
		} else {
			var $tables = List.with_capacity(count)
			for i in 0..<count {
				at = 12 + 16 * i
				$tables = $tables.append({ tag: Bytes.u32(bytes, at), offset: Bytes.u32(bytes, at + 8), length: Bytes.u32(bytes, at + 12) })
			}
			Ok($tables)
		}
	}

	## A table's bytes, checked to lie inside the file and to hold at least
	## `minimum` bytes. The first record with the tag wins.
	table : List(U8), List(Table), Str, U64 -> [Found(List(U8)), Missing, Bad]
	table = |bytes, tables, name, minimum| {
		tag = Sfnt.tag_of(name)
		match tables.find_first(|t| t.tag == tag) {
			Err(_) => Missing
			Ok(t) =>
				if Bytes.fits(t.offset, t.length, bytes.len()) and t.length >= minimum {
					Found(bytes.sublist({ start: t.offset, len: t.length }))
				} else {
					Bad
				}
		}
	}

	## A four-character table tag as the number the directory stores.
	tag_of : Str -> U64
	tag_of = |name| name.to_utf8().fold(0, |acc, b| acc * 256 + b.to_u64())

	## A table the font cannot be read without, as `table` checks it.
	required : List(U8), List(Table), Str, U64 -> Try(List(U8), [MissingTable(Str), BadTable(Str)])
	required = |bytes, tables, name, minimum|
		match Sfnt.table(bytes, tables, name, minimum) {
			Found(data) => Ok(data)
			Missing => Err(MissingTable(name))
			Bad => Err(BadTable(name))
		}

	## Add a reading result's problem, if it has one, to a list of problems.
	collect : List(p), Try(a, p) -> List(p)
	collect = |problems, result|
		match result {
			Ok(_) => problems
			Err(problem) => problems.append(problem)
		}
}
