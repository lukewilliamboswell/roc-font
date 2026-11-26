import build.FontBuild
import font.Font

# HVAR's explicit advance map must point to rows in its own store.
# Its implicit mapping instead requires a row for each glyph in maxp.
# https://learn.microsoft.com/en-us/typography/opentype/spec/hvar
HvarHeaderDiagnostics := {}.{
	check : {} -> Bool
	check = |_| [False, True].all(
		|has_maxp| [Valid, BadVersion, WrongAxes, BadRow, ShortImplicit].all(|hvar| agrees(has_maxp, hvar)),
	)
}

Hvar : [Valid, BadVersion, WrongAxes, BadRow, ShortImplicit]

agrees : Bool, Hvar -> Bool
agrees = |has_maxp, hvar| {
	peak = { start: 0, peak: 16384, end: 16384 }
	neutral = { start: 0, peak: 0, end: 0 }
	regions = if (hvar == WrongAxes) [[peak, neutral]] else [[peak]]
	store = FontBuild.variation_store(if (hvar == WrongAxes) 2 else 1, regions, [{ regions: [0], rows: [[0], [60]] }])
	mapping = if (hvar == ShortImplicit) [] else [{ outer: 0, inner: if (hvar == BadRow) 2 else 1 }]
	encoded = FontBuild.hvar(store, mapping)
	data = if (hvar == BadVersion) FontBuild.patch(encoded, 0, FontBuild.u16(2)) else encoded
	fvar = FontBuild.fvar([{ tag: "wght", min: 100, default: 400, max: 800 }])
	(body, required) =
		if has_maxp {
			(FontBuild.basic, [])
		} else {
			(FontBuild.basic.drop_if(|t| t.tag == "maxp"), [MissingTable("maxp")])
		}
	tables = [{ tag: "HVAR", data }, { tag: "fvar", data: fvar }].concat(body)
	at = 12 + 16 * tables.len()
	problem = |relative| BadTable({ table: "HVAR", offset: (at + relative).to_u32_wrap() })
	optional = match hvar {
		Valid => []
		BadVersion => [problem(0)]
		# A 20-byte HVAR header and a 12-byte store prefix with one
		# data offset precede the region list's axis count.
		WrongAxes => [problem(32)]
		# The first entry follows the store and the four-byte map header.
		BadRow => [problem(20 + store.len() + 4)]
		ShortImplicit => if (has_maxp) [problem(20)] else []
	}
	bytes = FontBuild.file(tables)
	[False, True].all(
		|strict| {
			rejected = !has_maxp or (strict and !optional.is_empty())
			match Font.from_bytes(bytes, Font.ReadOptions.{ strict }) {
				Err(problems) => rejected and problems == required.concat(optional)
				Ok(font) => {
					peak_face = Font.at(font, Font.Variation.{ weight: Weight(800) })
					!rejected and Font.dropped(font) == optional and Font.advance(peak_face, 1) == (if (hvar == Valid) 660 else 600)
				}
			}
		},
	)
}
