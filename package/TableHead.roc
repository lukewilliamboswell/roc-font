import Sfnt
import Bytes

## The font header (`head`): the size of the em square in font units, and
## whether `loca` holds long (32-bit) or short (16-bit) offsets.
##
## Internal. The table is checked as OTS 9.3.0 checks it
## (`ots/src/head.cc`, `OpenTypeHEAD::Parse`), and refused for the first
## problem in OTS's order:
##
## - a major version other than 1 (offset 0, head.cc lines 23-25);
## - a magic number other than `0x5F0F3CF5` (offset 12, lines 32-35);
## - units per em outside 16 to 16384 (`BadUnitsPerEm`, lines 48-52);
## - a bounding box whose minimum x or y lies past its maximum (offsets 36
##   and 38, lines 66-73);
## - an `indexToLocFormat` other than 0 or 1 (offset 50, lines 91-97);
## - a `glyphDataFormat` other than 0 (offset 52, lines 99-103).
##
## OTS masks the flags and `macStyle` to their defined bits rather than
## refusing other bits, so they are not checked here.
TableHead :: {}.{

	from_tables : List(U8), List(Sfnt.Table) -> Try({ units_per_em : U16, long_offsets : Bool }, [MissingTable(Str), BadTable({ table : Str, offset : U32 }), BadUnitsPerEm])
	from_tables = |bytes, tables| {
		found = Sfnt.required(bytes, tables, "head", 54)?
		head = found.data
		bad = |at| Err(Sfnt.bad("head", found.offset + at))
		units = Bytes.u16(head, 18)
		index_to_loc = Bytes.i16(head, 50)
		if Bytes.u16(head, 0) != 1 {
			bad(0)
		} else if Bytes.u32(head, 12) != 0x5F0F3CF5 {
			bad(12)
		} else if units < 16 or units > 16384 {
			Err(BadUnitsPerEm)
		} else if Bytes.i16(head, 36) > Bytes.i16(head, 40) {
			bad(36)
		} else if Bytes.i16(head, 38) > Bytes.i16(head, 42) {
			bad(38)
		} else if index_to_loc < 0 or index_to_loc > 1 {
			bad(50)
		} else if Bytes.i16(head, 52) != 0 {
			bad(52)
		} else {
			Ok({ units_per_em: units.to_u16_wrap(), long_offsets: index_to_loc == 1 })
		}
	}
}
