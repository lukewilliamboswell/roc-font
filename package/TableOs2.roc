import Sfnt
import Bytes

## The OS/2 and Windows metrics table (`OS/2`): the typographic and Windows
## ascent and descent, and whether the font asks for the typographic ones
## (`USE_TYPO_METRICS`). The table is optional.
##
## Internal.
TableOs2 :: {}.{

	Metrics : { use_typo : Bool, typo_ascent : F64, typo_descent : F64, win_ascent : F64, win_descent : F64 }

	from_tables : List(U8), List(Sfnt.Table) -> Try([Present(Metrics), Absent], [BadTable(Str)])
	from_tables = |bytes, tables|
		match Sfnt.table(bytes, tables, "OS/2", 78) {
			Missing => Ok(Absent)
			Bad => Err(BadTable("OS/2"))
			Found(os2) =>
				Ok(
					Present({
						use_typo: Bytes.u16(os2, 62).bitwise_and(0x80) != 0,
						typo_ascent: Bytes.i16(os2, 68).to_f64(),
						typo_descent: Bytes.i16(os2, 70).to_f64(),
						win_ascent: Bytes.u16(os2, 74).to_f64(),
						win_descent: Bytes.u16(os2, 76).to_f64(),
					}),
				)
		}

	## The Windows 3.1 font page of a version 0 table (the high byte of
	## `fsSelection`), or 0 for any other table or none. It selects how a
	## symbol character map is encoded.
	font_page : List(U8), List(Sfnt.Table) -> U64
	font_page = |bytes, tables|
		match Sfnt.table(bytes, tables, "OS/2", 78) {
			Found(os2) if Bytes.u16(os2, 0) == 0 => Bytes.u16(os2, 62).bitwise_and(0xFF00)
			_ => 0
		}

	## Ascent and descent as a browser takes them: the typographic values when
	## the font asks for them (`USE_TYPO_METRICS`), else `hhea`, else the
	## typographic values, else the Windows ones. Descent is positive below
	## the baseline.
	vertical : { ascent : F64, descent : F64, metric_count : U64 }, [Present(Metrics), Absent] -> { ascent : F64, descent : F64 }
	vertical = |hhea, os2|
		match os2 {
			Present(o) if o.use_typo => { ascent: o.typo_ascent, descent: -o.typo_descent }
			_ if hhea.ascent != 0.0 or hhea.descent != 0.0 => { ascent: hhea.ascent, descent: -hhea.descent }
			Present(o) if o.typo_ascent != 0.0 or o.typo_descent != 0.0 => { ascent: o.typo_ascent, descent: -o.typo_descent }
			Present(o) => { ascent: o.win_ascent, descent: o.win_descent }
			Absent => { ascent: 0.0, descent: 0.0 }
		}
}
