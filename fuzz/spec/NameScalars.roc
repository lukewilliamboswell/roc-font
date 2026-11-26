import build.FontBuild
import font.Font
import fuzz.Solve

# Unicode 18.0.0, D91 and Table 3-5, UTF-16 bit distribution.
# https://www.unicode.org/versions/Unicode18.0.0/core-spec/chapter-3/
NameScalars := {}.{
	check : {} -> Bool
	check = |_| proof({}) and cases.all(agrees)
}

proof : {} -> Bool
proof = |_| {
	result = Solve.prove_within(
		{ high: Solve.uint(10), low: Solve.uint(10) }.Solve,
		|fields| {
			# Twenty bits hold the two payloads. Use 21 for the scalar,
			# since adding the supplementary base can carry into bit 20.
			high = fields.high.to_width(21)
			low = fields.low.to_width(21)
			lead = 0xD800 + high
			trail = 0xDC00 + low
			decoded = 0x10000 + (lead - 0xD800) * 1024 + (trail - 0xDC00)

			# Table 3-5 adds one to the upper four payload bits.
			upper = (high.shr_wrap(6) + 1).shl_wrap(16)
			lower = high.bitwise_and(63).shl_wrap(10).bitwise_or(low)
			Solve.all([decoded.eq(upper.bitwise_or(lower)), decoded.gte(0x10000), decoded.lte(0x10FFFF)])
		},
		512,
	)
	match result {
		Ok(Proved) => True
		other => crash "supplementary scalar proof: ${Str.inspect(other)}"
	}
}

Case : { label : Str, units : List(U64), selected : List(U8) }

fallback : List(U8)
fallback = [0xF0, 0x90, 0x80, 0x80]

cases : List(Case)
cases = [
	{ label: "lowest pair", units: [0xD800, 0xDC00], selected: [0x41, 0xF0, 0x90, 0x80, 0x80, 0x5A] },
	{ label: "last trail with first lead", units: [0xD800, 0xDFFF], selected: [0x41, 0xF0, 0x90, 0x8F, 0xBF, 0x5A] },
	{ label: "first trail with last lead", units: [0xDBFF, 0xDC00], selected: [0x41, 0xF4, 0x8F, 0xB0, 0x80, 0x5A] },
	{ label: "highest pair", units: [0xDBFF, 0xDFFF], selected: [0x41, 0xF4, 0x8F, 0xBF, 0xBF, 0x5A] },
	{ label: "two leads before the low range", units: [0xD800, 0xDBFF], selected: fallback },
	{ label: "lead followed by first BMP unit after the low range", units: [0xDBFF, 0xE000], selected: fallback },
	{ label: "valid pair followed by an extra trail", units: [0xD800, 0xDC00, 0xDFFF], selected: fallback },
]

agrees : Case -> Bool
agrees = |case| {
	# Both records use the typographic family ID. The Windows US English
	# record outranks the Unicode record only when its entire string is
	# usable. The ASCII guards also check resuming after a decoded pair.
	records = [
		{ system: 0, encoding: 4, language: 0, id: 16, text: [0xD8, 0, 0xDC, 0] },
		{ system: 3, encoding: 10, language: 0x409, id: 16, text: [0, 0x41].concat(case.units.join_map(FontBuild.u16)).concat([0, 0x5A]) },
	]
	bytes = FontBuild.file(FontBuild.basic.append({ tag: "name", data: FontBuild.naming(records, []) }))
	match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
		Ok(font) =>
			match Font.family_name(font) {
				Ok(name) if name.to_utf8() == case.selected => True
				got => crash "${case.label}: selected ${Str.inspect(got)}"
			}
		Err(problems) => crash "${case.label}: strict reader rejected the name table ${Str.inspect(problems)}"
	}
}
