import build.FontBuild
import font.Font

# OpenType treats newer minor versions as compatible extensions and
# unrecognized major versions as absent. A damaged known header still
# reports its file offset even when a required face table fails.
# https://learn.microsoft.com/en-us/typography/opentype/spec/math
MathHeaderDiagnostics := {}.{
	check : {} -> Bool
	check = |_| [Healthy, BadHead, MissingHhea].all(
		|header| cases({}).all(|case| agrees(header, case)),
	)
}

Header : [Healthy, BadHead, MissingHhea]

Case : { math : List(U8), offsets : List(U64), has_math : Bool }

cases : {} -> List(Case)
cases = |_| {
	base = |minor| FontBuild.pack([
		U16(1),
		U16(minor),
		Ref(List.repeat(0, 214)),
		Ref(List.repeat(0, 8)),
		Ref(FontBuild.pack([U16(23), Raw(List.repeat(0, 8))])),
		Raw(if (minor == 0) [] else [255, 255, 255, 255]),
	])
	newer = base(1)
	[
		{ math: base(0), offsets: [], has_math: True },
		{ math: newer, offsets: [], has_math: True },
		{ math: FontBuild.u16(2).concat(FontBuild.u16(0)), offsets: [], has_math: False },
		{ math: [0, 2, 0], offsets: [0], has_math: False },
		{ math: newer.take_first(9), offsets: [0], has_math: False },
		{ math: FontBuild.patch(newer, 4, FontBuild.pack([U16(0), U16(2), U16(newer.len())])), offsets: [4, 6, 8], has_math: False },
	]
}

agrees : Header, Case -> Bool
agrees = |header, { math, offsets, has_math }| {
	(body, required) = match header {
		Healthy => (FontBuild.basic, [])
		BadHead => (FontBuild.replace(FontBuild.basic, "head", FontBuild.head(5, False)), [BadUnitsPerEm])
		MissingHhea => (FontBuild.basic.drop_if(|table| table.tag == "hhea"), [MissingTable("hhea")])
	}
	tables = [{ tag: "MATH", data: math }].concat(body)
	math_at = 12 + 16 * tables.len()
	optional = offsets.map(|at| BadTable({ table: "MATH", offset: (math_at + at).to_u32_wrap() }))
	expected = required.concat(optional)
	bytes = FontBuild.file(tables)
	[False, True].all(
		|strict| {
			rejected = !required.is_empty() or (strict and !optional.is_empty())
			match Font.from_bytes(bytes, Font.ReadOptions.{ strict }) {
				Err(problems) => rejected and problems == expected
				Ok(font) => !rejected and Font.dropped(font) == optional and Font.has_math(font) == has_math
					and Font.math_min_connector_overlap(font) == (if (has_math) 23 else 0)
			}
		},
	)
}
