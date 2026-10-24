import font.Font
import build.FontBuild

## Failures found by the narrow fuzz targets (`fuzz/font-cmap.roc`,
## `font-coverage.roc`, `font-gsub.roc`, `font-gpos.roc`, `font-var.roc`,
## `font-gvar.roc`, `font-layout-var.roc`, `font-ots.roc`),
## each distilled into the smallest font that shows it, through the public
## `Font` API exactly as the package ships it. Run with
## `roc test tests/api/main.roc`.
FuzzRegressionTests :: {}.{}

## fuzz regression: font-gpos. A `kern` table with more than one pair must
## give `entrySelector` as the format defines it (log2 of the largest power
## of two not above the pair count), or OTS, and so lenient reading, refuses
## it; the target's fonts were refused once the reader followed OTS, because
## `FontBuild.kern` writes zeros there. `FontBuild.kern_searchable` fills the
## search fields in; a table built with it reads in full and kerns every
## adjacent pair (`A` 600, `B` 700, `C` 800 units; `AB` -50, `BC` -20).
expect {
	kern = FontBuild.kern_searchable([{ left: 1, right: 2, value: -50 }, { left: 1, right: 3, value: -30 }, { left: 2, right: 3, value: -20 }])
	match Font.from_bytes(FontBuild.file(FontBuild.basic.append({ tag: "kern", data: kern })), Font.ReadOptions.{ strict: True }) {
		Ok(font) => Font.dropped(font).is_empty() and Font.width(font, "ABC") == 2030 and Font.width(font, "CBA") == 2100
		Err(_) => False
	}
}

## fuzz regression: font-var. A variation region whose range crosses zero
## while its peak does not (or whose start is past its peak) drops the
## variations, as OTS drops them; the target's regions did, so its
## "valid" fonts read as static ones. A region kept on one side of zero
## (start 0, peak and end 1.0) reads in full, and the advance and ascent
## deltas apply in full at the axis maximum and not at all at the default.
expect {
	axes = [{ tag: "wght", min: 100, default: 400, max: 900 }]
	region = [[{ start: 0, peak: 16384, end: 16384 }]]
	advances = FontBuild.variation_store(1, region, [{ regions: [0], rows: [[0], [100], [0], [-40]] }])
	ascent = FontBuild.variation_store(1, region, [{ regions: [0], rows: [[50]] }])
	tables = FontBuild.basic.concat([
		{ tag: "fvar", data: FontBuild.fvar(axes) },
		{ tag: "HVAR", data: FontBuild.hvar(advances, []) },
		{ tag: "MVAR", data: FontBuild.mvar(ascent, [{ tag: "hasc", outer: 0, inner: 0 }]) },
	])
	match Font.from_bytes(FontBuild.file(tables), Font.ReadOptions.{ strict: True }) {
		Ok(font) => {
			heavy = Font.at(font, Font.Variation.{ axes: [{ tag: "wght", value: 900 }] })
			home = Font.at(font, Font.Variation.{ axes: [{ tag: "wght", value: 400 }] })
			Font.dropped(font).is_empty()
				and [1, 2, 3].map(|g| Font.advance(heavy, g)) == [700, 700, 760]
				and [1, 2, 3].map(|g| Font.advance(home, g)) == [600, 700, 800]
				and Font.metrics(heavy).ascent == 850
				and Font.metrics(home).ascent == 800
		}
		Err(_) => False
	}
}

## fuzz regression: font-read and font-ots. OTS does not check feature
## tags, so a font whose `GSUB` names a feature with a byte past ASCII
## reads; `Font.features` must still list four-character tags in increasing
## order without repeats. Two tags that differ only in such a byte (0xAC
## and 0xAD) were both listed as `lig` and U+FFFD, six bytes each.
expect {
	gsub = FontBuild.layout("latn", [{ tag: "liga", lookups: [0] }, { tag: "ligb", lookups: [0] }], [{ kind: 1, subtables: [FontBuild.single1([1], 1)] }])
	list = (gsub.get(6) ?? 0).to_u64() * 256 + (gsub.get(7) ?? 0).to_u64()
	patched = FontBuild.patch(FontBuild.patch(gsub, list + 5, [0xAC]), list + 11, [0xAD])
	match Font.from_bytes(FontBuild.file(FontBuild.replace(FontBuild.basic, "GSUB", patched)), Font.ReadOptions.{}) {
		Ok(font) => {
			tags = Font.features(font)
			tags.len() == 2 and tags.all(|t| t.to_utf8().len() <= 8) and tags.get(0) != tags.get(1)
		}
		Err(_) => False
	}
}
