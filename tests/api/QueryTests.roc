import font.Font
import build.FontBuild

## Tests of measuring with a plan (`width_planned`), listing a font's
## features (`features`), reading run flags (`unsafe_to_break`,
## `missing`), the text each glyph draws (`cluster_ranges`), problems in
## words (`describe_problem`) and glyph boxes a font's outlines cannot
## give (`extents` with `Unknown`), through the public `Font` API. Run
## with `roc test tests/api/main.roc`.
QueryTests :: {}.{}

# ------------------------------------------------------------ width_planned

# With the default plan, `width_planned` is `width`.
expect {
	plan = Font.plan(Font.sans, Font.ShapeOptions.{})
	["", "Hello, world!", "office -> home", "AVATAR"].all(|text| Font.width_planned(Font.sans, plan, text) == Font.width(Font.sans, text))
}

# The total of the planned run's advances.
expect {
	plan = Font.plan(Font.serif, Font.ShapeOptions.{ features: [Font.Feature.{ tag: "liga", value: 0 }] })
	run = Font.shape_planned(Font.serif, plan, "office fit")
	Font.width_planned(Font.serif, plan, "office fit") == run.advances.fold(0, |sum, a| sum + a.x)
}

# Tabular figures make every digit as wide as every other in Inter; by
# default "1111" is narrower than "0000".
expect {
	tabular = Font.plan(Font.sans, Font.ShapeOptions.{ features: [Font.Feature.{ tag: "tnum" }] })
	Font.width_planned(Font.sans, tabular, "1111") == Font.width_planned(Font.sans, tabular, "0000")
		and Font.width(Font.sans, "1111") < Font.width(Font.sans, "0000")
}

# Empty text has no width.
expect Font.width_planned(Font.mono, Font.plan(Font.mono, Font.ShapeOptions.{ direction: RightToLeft }), "") == 0

# ------------------------------------------------------------ features

# The built-in fonts' features, as fontTools 4.61.1 lists the feature
# records of `GSUB` and `GPOS` (with `kern` for a `kern` table), sorted.
expect Font.features(Font.sans) == ["aalt", "calt", "case", "ccmp", "cpsp", "cv01", "cv02", "cv03", "cv04", "cv05", "cv06", "cv07", "cv08", "cv09", "cv10", "cv11", "cv12", "cv13", "cv14", "dlig", "dnom", "frac", "kern", "locl", "mark", "mkmk", "numr", "ordn", "pnum", "salt", "sinf", "ss01", "ss02", "ss03", "ss04", "ss05", "ss06", "ss07", "ss08", "subs", "sups", "tnum", "zero"]
expect Font.features(Font.serif) == ["aalt", "c2sc", "calt", "case", "ccmp", "dlig", "dnom", "frac", "kern", "liga", "lnum", "locl", "mark", "mkmk", "numr", "onum", "ordn", "pnum", "sinf", "smcp", "ss01", "ss02", "ss03", "ss04", "subs", "sups", "tnum", "zero"]
expect {
	listed = Font.features(Font.mono)
	listed.len() == 61 and listed.contains("calt") and !listed.contains("liga") and !listed.contains("kern") and listed.first() == Ok("aalt") and listed.last() == Ok("zero")
}

# A font without layout tables offers none; a `kern` table offers `kern`.
expect
	match Font.from_bytes(FontBuild.file(FontBuild.basic), Font.ReadOptions.{}) {
		Ok(font) => Font.features(font) == []
		Err(_) => False
	}
expect
	match Font.from_bytes(FontBuild.file(FontBuild.basic.append({ tag: "kern", data: FontBuild.kern([{ coverage: 1, pairs: [{ left: 1, right: 2, value: -50 }] }]) })), Font.ReadOptions.{}) {
		Ok(font) => Font.features(font) == ["kern"]
		Err(_) => False
	}

# Features of both tables, merged in tag order without repeats, whatever
# order and how many times the tables list them.
expect {
	single = [{ kind: 1, subtables: [FontBuild.single1([1], 1)] }]
	gsub = FontBuild.layout("GSUB", [{ tag: "liga", lookups: [0] }, { tag: "ccmp", lookups: [0] }, { tag: "liga", lookups: [0] }], single)
	gpos = FontBuild.layout("GPOS", [{ tag: "mark", lookups: [0] }, { tag: "kern", lookups: [0] }], [{ kind: 2, subtables: [FontBuild.pair1(4, 0, [{ glyph: 1, pairs: [{ second: 2, values: [-50] }] }])] }])
	match Font.from_bytes(FontBuild.file(FontBuild.basic.concat([{ tag: "GSUB", data: gsub }, { tag: "GPOS", data: gpos }])), Font.ReadOptions.{}) {
		Ok(font) => Font.features(font) == ["ccmp", "kern", "liga", "mark"]
		Err(_) => False
	}
}

# A layout table left out for listing too many lookups offers nothing.
expect {
	single = [{ kind: 1, subtables: [FontBuild.single1([1], 1)] }, { kind: 1, subtables: [FontBuild.single1([2], 1)] }]
	gsub = FontBuild.layout("GSUB", [{ tag: "smcp", lookups: [0, 1] }], single)
	match Font.from_bytes(FontBuild.file(FontBuild.basic.append({ tag: "GSUB", data: gsub })), Font.ReadOptions.{ limits: Font.Limits.{ max_lookups: 1 } }) {
		Ok(font) => Font.features(font) == [] and Font.dropped(font) == [OverLimit("max_lookups")]
		Err(_) => False
	}
}

# ------------------------------------------------------------ flags

expect [0, 1, 2, 3].map(Font.unsafe_to_break) == [False, True, False, True]
expect [0, 1, 2, 3].map(Font.missing) == [False, False, True, True]

# Inter has no Hebrew: every letter is missing, the brackets and the space
# are not.
expect {
	run = Font.shape(Font.sans, "שלום (עולם)", Font.ShapeOptions.{ script: "Hebr" })
	run.flags.count_if(Font.missing) == 8 and run.glyphs.len() == 11 and run.flags.map2(run.glyphs, |f, g| Font.missing(f) == (g == 0)).all(|ok| ok)
}

# Merriweather joins "fi" into one glyph, one cluster, so there is no
# break inside it to flag; breaking before the "t" after it would change
# the glyphs, so its cluster is unsafe to break. As HarfBuzz 14.6.0 flags
# it (uharfbuzz 0.56.3, wght 400).
expect {
	run = Font.shape(Font.serif, "a fit", Font.ShapeOptions.{})
	run.clusters == [0, 1, 2, 4] and run.flags.map(Font.unsafe_to_break) == [False, False, False, True]
}

# ------------------------------------------------------------ cluster_ranges

# Merriweather's "Office fit": each glyph draws its cluster up to the next
# larger one; the ligatures draw two characters each.
expect {
	text = "Office fit"
	run = Font.shape(Font.serif, text, Font.ShapeOptions.{})
	Font.cluster_ranges(run, text.count_utf8_bytes()) == [{ start: 0, end: 1 }, { start: 1, end: 2 }, { start: 2, end: 4 }, { start: 4, end: 5 }, { start: 5, end: 6 }, { start: 6, end: 7 }, { start: 7, end: 9 }, { start: 9, end: 10 }]
}

# Right to left: the run is in visual order and its clusters count down,
# and each range is still its own glyph's. Hebrew letters are two bytes.
expect {
	text = "שלום"
	run = Font.shape(Font.sans, text, Font.ShapeOptions.{ script: "Hebr" })
	run.clusters == [6, 4, 2, 0] and Font.cluster_ranges(run, text.count_utf8_bytes()) == [{ start: 6, end: 8 }, { start: 4, end: 6 }, { start: 2, end: 4 }, { start: 0, end: 2 }]
}

# Glyphs sharing a cluster share its range; any order of clusters has the
# next larger cluster; a cluster at or past the length is empty there.
expect {
	run = { glyphs: [1, 2, 3, 4, 5, 6], advances: List.repeat({ x: 0, y: 0 }, 6), offsets: List.repeat({ x: 0, y: 0 }, 6), clusters: [9, 7, 7, 0, 4, 12], flags: List.repeat(0, 6) }
	Font.cluster_ranges(run, 12) == [{ start: 9, end: 12 }, { start: 7, end: 9 }, { start: 7, end: 9 }, { start: 0, end: 4 }, { start: 4, end: 7 }, { start: 12, end: 12 }]
}
expect {
	run = { glyphs: [1, 2], advances: List.repeat({ x: 0, y: 0 }, 2), offsets: List.repeat({ x: 0, y: 0 }, 2), clusters: [3, 8], flags: [0, 0] }
	Font.cluster_ranges(run, 5) == [{ start: 3, end: 5 }, { start: 8, end: 8 }] and Font.cluster_ranges(run, 0) == [{ start: 3, end: 3 }, { start: 8, end: 8 }]
}

# An empty run has no ranges.
expect Font.cluster_ranges(Font.shape(Font.sans, "", Font.ShapeOptions.{}), 0) == []

# Ranges for text shaped from scalars use the offsets given.
expect {
	plan = Font.plan(Font.serif, Font.ShapeOptions.{})
	run = Font.shape_scalars(Font.serif, plan, [{ scalar: 'f', offset: 100 }, { scalar: 'i', offset: 101 }, { scalar: 't', offset: 102 }])
	run.clusters == [100, 102] and Font.cluster_ranges(run, 103) == [{ start: 100, end: 102 }, { start: 102, end: 103 }]
}

# ------------------------------------------------------------ describe_problem

expect Font.describe_problem(NotAFont) == "not a TrueType or OpenType font file"
expect Font.describe_problem(NoSuchFace({ face: 3, count: 2 })) == "there is no font 3 in a collection of 2 (fonts are numbered from 0)"
expect Font.describe_problem(OverLimit("max_lookups")) == "the file asks for more than the max_lookups reading limit allows"
expect Font.describe_problem(MissingTable("hmtx")) == "the hmtx table, which every font needs, is missing"
expect Font.describe_problem(BadTable({ table: "GSUB", offset: 1234 })) == "the GSUB table is damaged at byte 1234 of the file"
expect Font.describe_problem(BadUnitsPerEm) == "the font's units per em (in the head table) are outside 16 to 16384"
expect Font.describe_problem(NoUnicodeMapping) == "the font has no character map for Unicode text (cmap table)"

# Every problem of a read in words, in order.
expect
	match Font.from_bytes([0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], Font.ReadOptions.{}) {
		Err(problems) => problems.map(Font.describe_problem) == ["the head table, which every font needs, is missing", "the hhea table, which every font needs, is missing", "the maxp table, which every font needs, is missing", "the cmap table, which every font needs, is missing"]
		Ok(_) => False
	}

# ------------------------------------------------------------ extents

# A font whose outlines are not TrueType (here a `CFF ` table and no
# `glyf`) cannot measure its glyphs: `Unknown`, unlike a glyph that draws
# nothing. A glyph id past the font is `Empty`.
expect
	match Font.from_bytes(FontBuild.file(FontBuild.basic.append({ tag: "CFF ", data: [1, 0, 4, 4] })), Font.ReadOptions.{}) {
		Ok(font) => [0, 1, 3].all(|g| Font.extents(font, g) == Unknown) and Font.extents(font, 4) == Empty and Font.extents(font, 0xFFFFFFFF) == Empty
		Err(_) => False
	}

# The built-in fonts have TrueType outlines: a space is `Empty`, never
# `Unknown`.
expect {
	space = Font.glyph(Font.serif, ' ') ?? 0
	Font.extents(Font.serif, space) == Empty
}
