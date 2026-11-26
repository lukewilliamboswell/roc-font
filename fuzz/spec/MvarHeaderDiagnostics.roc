import build.FontBuild
import font.Font

# MVAR uses a variation region list whose axis count must match fvar.
# The same store is usable with two axes and invalid with just one.
# That comparison needs neither a prepared face nor any glyph data.
# https://learn.microsoft.com/en-us/typography/opentype/spec/mvar
# https://learn.microsoft.com/en-us/typography/opentype/spec/otvarcommonformats#variation-regions
MvarHeaderDiagnostics := {}.{
	check : {} -> Bool
	check = |_| [Healthy, BadHead, MissingHhea].all(
		|header| [TwoAxes, OneAxis, NoAxes].all(|axes| agrees(header, axes)),
	)
}

Header : [Healthy, BadHead, MissingHhea]

Space : [TwoAxes, OneAxis, NoAxes]

agrees : Header, Space -> Bool
agrees = |header, space| {
	weight = { tag: "wght", min: 100, default: 400, max: 800 }
	width = { tag: "wdth", min: 50, default: 100, max: 200 }
	axes = match space {
		TwoAxes => [weight, width]
		OneAxis => [weight]
		NoAxes => []
	}
	peak = { start: 0, peak: 16384, end: 16384 }
	neutral = { start: 0, peak: 0, end: 0 }
	store = FontBuild.variation_store(2, [[peak, neutral]], [{ regions: [0], rows: [[60]] }])
	mvar = FontBuild.mvar(store, [{ tag: "hasc", outer: 0, inner: 0 }])
	os2 = FontBuild.os2({ use_typo: True, typo_ascent: 800, typo_descent: -200, win_ascent: 900, win_descent: 300 })
	(body, required) = match header {
		Healthy => (FontBuild.basic, [])
		BadHead => (FontBuild.replace(FontBuild.basic, "head", FontBuild.head(5, False)), [BadUnitsPerEm])
		MissingHhea => (FontBuild.basic.drop_if(|table| table.tag == "hhea"), [MissingTable("hhea")])
	}
	fvar = if (space == NoAxes) [] else [{ tag: "fvar", data: FontBuild.fvar(axes) }]
	tables = [{ tag: "MVAR", data: mvar }, { tag: "OS/2", data: os2 }].concat(fvar).concat(body)
	# The 12-byte MVAR header and one 8-byte value record precede the
	# store. Its 8-byte header and one 4-byte data offset precede the
	# VariationRegionList, whose first word is the offending axis count.
	mvar_at = 12 + 16 * tables.len()
	axis_count_at = mvar_at + 12 + 8 + 8 + 4
	optional = if (space == OneAxis) [BadTable({ table: "MVAR", offset: axis_count_at.to_u32_wrap() })] else []
	expected = required.concat(optional)
	bytes = FontBuild.file(tables)
	[False, True].all(
		|strict| {
			rejected = !required.is_empty() or (strict and !optional.is_empty())
			match Font.from_bytes(bytes, Font.ReadOptions.{ strict }) {
				Err(problems) => rejected and problems == expected
				Ok(font) => {
					at_peak = Font.at(font, Font.Variation.{ weight: Weight(800) })
					!rejected and Font.dropped(font) == optional
						and Font.metrics(font).ascent == 800
						and Font.metrics(at_peak).ascent == (if (space == TwoAxes) 860 else 800)
				}
			}
		},
	)
}
