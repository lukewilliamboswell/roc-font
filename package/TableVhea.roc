import Sfnt
import Bytes

## Checked optional vertical header, including both specified versions.
TableVhea :: {}.{

	Header : { ascent : I32, descent : I32, line_gap : I32, metric_count : U64 }

	from_tables : List(U8), List(Sfnt.Table) -> Try([Present(Header), Absent], Sfnt.Bad)
	from_tables = |bytes, tables|
		match Sfnt.located(bytes, tables, "vhea", 36) {
			Missing => Ok(Absent)
			Bad(at) => Err(Sfnt.bad("vhea", at))
			Found({ data, offset }) => {
				version = Bytes.u32(data, 0)
				if version != 0x00010000 and version != 0x00011000 {
					Err(Sfnt.bad("vhea", offset))
				} else if Bytes.u16(data, 32) != 0 {
					Err(Sfnt.bad("vhea", offset + 32))
				} else if Bytes.u16(data, 34) == 0 {
					Err(Sfnt.bad("vhea", offset + 34))
				} else {
					Ok(Present({ ascent: Bytes.i16(data, 4).to_i32_wrap(), descent: Bytes.i16(data, 6).to_i32_wrap(), line_gap: Bytes.i16(data, 8).to_i32_wrap(), metric_count: Bytes.u16(data, 34) }))
				}
			}
		}
}

header = [0, 1, 16, 0, 3, 32, 255, 56, 0, 0].concat(List.repeat(0.U8, 24)).concat([0, 2])

tables = [{ tag: Sfnt.tag_of("vhea"), offset: 0, length: 36 }]
expect TableVhea.from_tables([], []) == Ok(Absent)
expect TableVhea.from_tables(header, tables) == Ok(Present({ ascent: 800, descent: -200, line_gap: 0, metric_count: 2 }))
expect TableVhea.from_tables(header.drop_last(1), tables) == Err(Sfnt.bad("vhea", 0))
expect TableVhea.from_tables(header.set(1, 2) ?? [], tables) == Err(Sfnt.bad("vhea", 0))
expect TableVhea.from_tables(header.set(35, 0) ?? [], tables) == Err(Sfnt.bad("vhea", 34))
