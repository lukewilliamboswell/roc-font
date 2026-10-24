import Sfnt
import Bytes

## The maximum profile (`maxp`): how many glyphs the font has.
##
## Internal. A font with no glyphs is refused.
TableMaxp :: {}.{

	from_tables : List(U8), List(Sfnt.Table) -> Try(U64, [MissingTable(Str), BadTable(Str)])
	from_tables = |bytes, tables| {
		maxp = Sfnt.required(bytes, tables, "maxp", 6)?
		count = Bytes.u16(maxp, 4)
		if (count == 0) Err(BadTable("maxp")) else Ok(count)
	}
}
