import build.FontBuild
import font.Font

# A bad version 1 axis map leaves a linear variation space. Unsupported
# avar version 2 or an invalid variation metrics table drops all variations.
# Both read modes report every independent problem at its table offset.
VariationReading := {}.{
	check : {} -> Bool
	check = |_| [
		{ map: Bend, bad_hvar: False, bad_mvar: False, expected: Retained(12288) },
		{ map: MissingEndpoint, bad_hvar: False, bad_mvar: False, expected: Retained(8192) },
		{ map: Version2, bad_hvar: False, bad_mvar: False, expected: Disabled },
		{ map: Bend, bad_hvar: True, bad_mvar: False, expected: Disabled },
		{ map: Bend, bad_hvar: False, bad_mvar: True, expected: Disabled },
		{ map: MissingEndpoint, bad_hvar: True, bad_mvar: True, expected: Disabled },
	].all(check_case)
}

Map : [Bend, MissingEndpoint, Version2]

Expected : [Retained(I16), Disabled]

Case : { map : Map, bad_hvar : Bool, bad_mvar : Bool, expected : Expected }

aligned_length : List(U8) -> U64
aligned_length = |bytes| (bytes.len() + 3) // 4 * 4

fixture : Case -> { bytes : List(U8), problems : List(Font.Problem) }
fixture = |case| {
	fvar = FontBuild.fvar([{ tag: "wght", min: 200, default: 400, max: 800 }])
	knots = [{ from: -16384, to: -16384 }, { from: 0, to: 0 }, { from: 8192, to: 12288 }, { from: 16384, to: 16384 }]
	good_map = FontBuild.avar([knots])
	avar = match case.map {
		Bend => good_map
		MissingEndpoint => FontBuild.avar([knots.drop_last(1)])
		# Version 2 adds optional delta-set map and store offsets.
		Version2 => FontBuild.patch(good_map, 0, FontBuild.u16(2)).concat(List.repeat(0, 8))
	}
	store = |rows| FontBuild.variation_store(1, [[{ start: 0, peak: 16384, end: 16384 }]], [{ regions: [0], rows }])
	good_hvar = FontBuild.hvar(store([[0], [120], [0], [0]]), [])
	good_mvar = FontBuild.mvar(store([[-60]]), [{ tag: "hasc", outer: 0, inner: 0 }])
	wrong_version = |bytes| FontBuild.patch(bytes, 0, FontBuild.u16(2))
	hvar = if (case.bad_hvar) wrong_version(good_hvar) else good_hvar
	mvar = if (case.bad_mvar) wrong_version(good_mvar) else good_mvar
	tables = [{ tag: "fvar", data: fvar }, { tag: "avar", data: avar }, { tag: "HVAR", data: hvar }, { tag: "MVAR", data: mvar }].concat(FontBuild.basic)
	# FontBuild stores these tables first, after the directory, in the
	# given order and aligned to four bytes.
	avar_at = 12 + 16 * tables.len() + aligned_length(fvar)
	hvar_at = avar_at + aligned_length(avar)
	mvar_at = hvar_at + aligned_length(hvar)
	bad : Str, U64 -> Font.Problem
	bad = |table, offset| BadTable({ table, offset: offset.to_u32_wrap() })
	avar_problems = match case.map {
		Bend => []
		MissingEndpoint => [bad("avar", avar_at + 8)]
		Version2 => [bad("avar", avar_at)]
	}
	hvar_problems = if (case.bad_hvar) [bad("HVAR", hvar_at)] else []
	mvar_problems = if (case.bad_mvar) [bad("MVAR", mvar_at)] else []
	{ bytes: FontBuild.file(tables), problems: avar_problems.concat(hvar_problems).concat(mvar_problems) }
}

observe : Font, List(Font.Problem) -> (List(I16), I32, I32, Bool)
observe = |font, problems| (Font.coordinates(font).map(|axis| axis.value), Font.advance(font, 1), Font.metrics(font).ascent, Font.dropped(font) == problems)

check_case : Case -> Bool
check_case = |case| {
	{ bytes, problems } = fixture(case)
	strict = match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
		Ok(font) => problems.is_empty() and Font.dropped(font).is_empty()
		Err(found) => !problems.is_empty() and found == problems
	}
	font = Font.from_bytes(bytes, Font.ReadOptions.{}) ?? crash "lenient variation fixture rejected"
	half = Font.at(font, Font.Variation.{ weight: Weight(600) })
	peak = Font.at(half, Font.Variation.{ weight: Weight(800) })
	home = Font.at(peak, Font.Variation.{})
	actual = [font, half, peak, home].map(|face| observe(face, problems))
	(expected_axes, expected) = match case.expected {
		Retained(coordinate) => {
			# Advance 600 + 120 × scalar, ascent 800 − 60 × scalar.
			scaled : I32 -> I32
			scaled = |delta| delta * coordinate.to_i32() // 16384
			default = ([0], 600, 800, True)
			([{ tag: "wght", min: 200, default: 400, max: 800 }], [default, ([coordinate], 600 + scaled(120), 800 - scaled(60), True), ([16384], 720, 740, True), default])
		}
		Disabled => ([], List.repeat(([], 600, 800, True), 4))
	}
	if strict and Font.axes(font) == expected_axes and actual == expected {
		True
	} else {
		crash "variation reading ${Str.inspect(case)} gave ${Str.inspect(actual)} and ${Str.inspect(Font.dropped(font))}. Strict diagnostics matched ${Str.inspect(strict)}"
	}
}
