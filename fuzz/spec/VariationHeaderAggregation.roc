import build.FontBuild
import font.Font

# avar has one map per fvar axis. An
# implicit HVAR mapping needs a store row per glyph from maxp.
VariationHeaderAggregation := {}.{
	check : {} -> Bool
	check = |_| [Healthy, BadHead, MissingMaxp].all(agrees)
}

Header : [Healthy, BadHead, MissingMaxp]

agrees : Header -> Bool
agrees = |header| {
	fvar = FontBuild.fvar([{ tag: "wght", min: 100, default: 400, max: 800 }])
	# Two empty maps are structurally present, but fvar names one axis.
	avar = FontBuild.avar([[], []])
	# Three implicit HVAR rows, with four glyphs in the healthy face.
	region = { start: 0, peak: 16384, end: 16384 }
	store = FontBuild.variation_store(1, [[region]], [{ regions: [0], rows: [[0], [20], [0]] }])
	hvar = FontBuild.hvar(store, [])
	(body, required) = match header {
		Healthy => (FontBuild.basic, [])
		BadHead => (FontBuild.replace(FontBuild.basic, "head", FontBuild.head(5, False)), [BadUnitsPerEm])
		MissingMaxp => (FontBuild.basic.drop_if(|t| t.tag == "maxp"), [MissingTable("maxp")])
	}
	tables = [{ tag: "avar", data: avar }, { tag: "HVAR", data: hvar }, { tag: "fvar", data: fvar }].concat(body)
	avar_at = 12 + 16 * tables.len()
	hvar_at = avar_at + (avar.len() + 3) // 4 * 4
	bad = |table, offset| BadTable({ table, offset: offset.to_u32_wrap() })
	# The avar count is at byte 6. The implicit HVAR row check names
	# the start of the variation store, after the 20-byte HVAR header.
	issues = [bad("avar", avar_at + 6)].concat(if (header == MissingMaxp) [] else [bad("HVAR", hvar_at + 20)])
	bytes = FontBuild.file(tables)
	[False, True].all(
		|strict| match Font.from_bytes(bytes, Font.ReadOptions.{ strict }) {
			Ok(font) => header == Healthy and !strict and Font.dropped(font) == issues
			Err(problems) => (header != Healthy or strict) and problems == required.concat(issues)
		},
	)
}
