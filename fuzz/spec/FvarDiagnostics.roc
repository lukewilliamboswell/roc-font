import build.FontBuild
import font.Font

# An out-of-range fvar default prevents selecting a location. The axis
# record count can still validate independent variation references, and
# valid tables can still supply their stored values at the default design.
# The fixture’s healthy values agree with HarfBuzz 14.6.0 for advances
# and the fontTools variation store evaluator for the MATH axis height.
FvarDiagnostics := {}.{
	check : {} -> Bool
	check = |_| [Clean, BadDefault, BadDefaultAndLayout, BadDefaultAndMath].all(check_case)
}

Case : [Clean, BadDefault, BadDefaultAndLayout, BadDefaultAndMath]

bad_axis : List(U8)
bad_axis = "wght".to_utf8().concat([100, 900, 800].join_map(|value| FontBuild.u32(value * 65536)))

fixture : Case -> List(U8)
fixture = |case| {
	good_fvar = FontBuild.fvar([{ tag: "wght", min: 100, default: 400, max: 800 }])
	fvar = if (case == Clean) good_fvar else FontBuild.patch(good_fvar, 24, FontBuild.u32(900 * 65536))
	regions = [[{ start: 0, peak: 16384, end: 16384 }]]
	store = |rows| FontBuild.variation_store(1, regions, [{ regions: [0], rows }])
	good_hvar = FontBuild.hvar(store([[0], [0], [50], [0]]), [])
	hvar = if (case == BadDefaultAndLayout) FontBuild.patch(good_hvar, 0, FontBuild.u16(2)) else good_hvar
	gdef = FontBuild.gdef_store(store([[20]]))
	pair_row = if (case == BadDefaultAndLayout) 1 else 0
	pair = FontBuild.pair1_devices(0x44, [{ glyph: 1, pairs: [{ second: 2, value: 10, device: Index(0, pair_row) }] }])
	gpos = FontBuild.layout("latn", [{ tag: "kern", lookups: [0] }], [{ kind: 2, subtables: [pair] }])
	math_row = if (case == BadDefaultAndMath) 1 else 0
	device = FontBuild.device_field(Index(0, math_row))
	constants = FontBuild.pack([I16(80), I16(60), U16(1000), U16(1100), I16(0), U16(0), I16(250), device, Raw(List.repeat(0, 198))])
	math = FontBuild.pack([U32(0x00010000), Ref(constants), Ref(List.repeat(0, 8)), Ref(List.repeat(0, 10))])
	FontBuild.file(FontBuild.basic.concat([{ tag: "fvar", data: fvar }, { tag: "HVAR", data: hvar }, { tag: "GDEF", data: gdef }, { tag: "GPOS", data: gpos }, { tag: "MATH", data: math }]))
}

check_case : Case -> Bool
check_case = |case| {
	bytes = fixture(case)
	font = Font.from_bytes(bytes, Font.ReadOptions.{}) ?? crash "lenient fvar default fixture rejected"
	strict = Font.from_bytes(bytes, Font.ReadOptions.{ strict: True })
	bad_index = [0, 0, 0, 1, 0x80, 0]
	bad_default = [("fvar", bad_axis)]
	issues = match case {
		Clean => []
		BadDefault => bad_default
		BadDefaultAndLayout => bad_default.concat([("HVAR", [0, 2, 0, 0]), ("GPOS", bad_index)])
		BadDefaultAndMath => bad_default.append(("MATH", bad_index))
	}
	problems = Font.dropped(font)
	matches = problems.len() == issues.len() and issues.all(
		|(tag, wire)| problems.any(
			|problem| match problem {
				BadTable({ table, offset }) => table == tag and bytes.sublist({ start: offset.to_u64(), len: wire.len() }) == wire
				_ => False
			},
		),
	)
	read_ok = match strict {
		Ok(_) => case == Clean and problems.is_empty()
		Err(found) => case != Clean and found == problems and matches
	}
	peak = Font.at(font, Font.Variation.{ weight: Weight(800) })
	advances = |at| Font.shape(at, "AB", Font.ShapeOptions.{ script: "Latn" }).advances.map(|advance| advance.x)
	math_axis = match Font.math_constants(peak) {
		Present(c) => Present(c.axis_height)
		Absent => Absent
	}
	want_peak = if (case == Clean) [630, 750] else [610, 700]
	want_math = match case {
		Clean => Present(270)
		BadDefaultAndMath => Absent
		_ => Present(250)
	}
	if read_ok and Font.axes(peak).len() == (if (case == Clean) 1 else 0) and advances(font) == [610, 700] and advances(peak) == want_peak and math_axis == want_math {
		True
	} else {
		crash "fvar diagnostics ${Str.inspect(case)}: ${Str.inspect(problems)}, advances ${Str.inspect(advances(peak))}, MATH axis ${Str.inspect(math_axis)}"
	}
}
