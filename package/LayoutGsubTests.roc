import LayoutGsub
import ShaperUnicode

## In-package tests of `LayoutGsub` for what `Font` never lets reach it. The
## behaviour callers see is tested through the public API in `tests/api/`.
## Test-only: `main.roc` does not import this module. Run with
## `roc test package/LayoutGsubTests.roc`.
LayoutGsubTests :: {}.{}

# A table too short for its header is refused by the reader itself; `Font`
# refuses such a table before reading it, so only a direct call reaches
# this check.
expect LayoutGsub.read([]).is_err()
expect LayoutGsub.read(List.repeat(0, 9)).is_err()

# ------------------------------------------------------------ ligature sets

# A big-endian 16-bit value.
be16 : U64 -> List(U8)
be16 = |v| [v.shr_zf_wrap(8).to_u8_wrap(), v.to_u8_wrap()]

# A `GSUB` with one `liga` lookup (lookup flag `flag`) of one ligature
# subtable for glyph 10, whose set holds, in order: 10 12 -> 100, 10 11 11
# -> 101, 10 11 -> 102 and 10 -> 103.
liga_gsub : U64 -> List(U8)
liga_gsub = |flag| {
	ligatures : List(List(U64))
	ligatures = [[100, 12], [101, 11, 11], [102, 11], [103]]
	# Ligature tables after the set's count and offsets.
	set_head = 2 + 2 * ligatures.len()
	{ offsets, tables } = ligatures.fold(
		{ offsets: [], tables: [] },
		|acc, lig| {
			at = set_head + acc.tables.len()
			table = be16(lig.first() ?? 0).concat(be16(lig.len())).concat(lig.drop_first(1).fold([], |b, g| b.concat(be16(g))))
			{ offsets: acc.offsets.concat(be16(at)), tables: acc.tables.concat(table) }
		},
	)
	set = be16(ligatures.len()).concat(offsets).concat(tables)
	# Format 1, coverage at 8, one set at 14; coverage of glyph 10.
	subtable = be16(1).concat(be16(8)).concat(be16(1)).concat(be16(14)).concat(be16(1)).concat(be16(1)).concat(be16(10)).concat(set)
	lookup = be16(4).concat(be16(flag)).concat(be16(1)).concat(be16(8)).concat(subtable)
	# Header, empty script list at 10, feature list at 12 (`liga` at 20),
	# lookup list at 26 (the lookup at 30).
	[0, 1, 0, 0].concat(be16(10)).concat(be16(12)).concat(be16(26))
		.concat(be16(0))
		.concat(be16(1)).concat(['l', 'i', 'g', 'a']).concat(be16(8)).concat(be16(0)).concat(be16(1)).concat(be16(0))
		.concat(be16(1)).concat(be16(4))
		.concat(lookup)
}

zwj_props : U64
zwj_props = ShaperUnicode.props(0x200D)

# A mark, by its glyph properties.
mark_props : U64
mark_props = LayoutGsub.mark.shl_wrap(16)

# Glyphs and clusters after applying the lookup to glyphs given with their
# property words, one cluster each.
ligated : U64, Bool, List({ glyph : U64, props : U64 }) -> { glyphs : List(U64), clusters : List(U64) }
ligated = |flag, auto_zwj, input| match LayoutGsub.read(liga_gsub(flag)) {
	Ok(gsub) => {
		items = input.map_with_index(|g, i| { glyph: g.glyph, cluster: i, mask: 1, props: g.props })
		plan = [{ index: 0, mask: 1, auto_zwnj: True, auto_zwj, random: False }]
		applied = LayoutGsub.apply(gsub, plan, items, { limit: 64, budget: 64, depth: 8 })
		{ glyphs: applied.items.map(|item| item.glyph), clusters: applied.items.map(|item| item.cluster) }
	}
	Err(_) => { glyphs: [], clusters: [] }
}

letters : List(U64) -> List({ glyph : U64, props : U64 })
letters = |glyphs| glyphs.map(|glyph| { glyph, props: ShaperUnicode.lowercase_letter })

# The first ligature of the set whose components follow, ligatures whose
# second component is another glyph passed over, clusters merged.
expect ligated(0, True, letters([10, 11])) == { glyphs: [102], clusters: [0] }
expect ligated(0, True, letters([10, 11, 11])) == { glyphs: [101], clusters: [0] }
expect ligated(0, True, letters([10, 12, 11])) == { glyphs: [100, 11], clusters: [0, 2] }
expect ligated(0, True, letters([10, 11, 10, 12])) == { glyphs: [102, 100], clusters: [0, 2] }

# At the end of the run, or before a glyph no ligature continues with, only
# the one-glyph ligature applies.
expect ligated(0, True, letters([10])) == { glyphs: [103], clusters: [0] }
expect ligated(0, True, letters([11, 10])) == { glyphs: [11, 103], clusters: [0, 1] }
expect ligated(0, True, letters([10, 13])) == { glyphs: [103, 13], clusters: [0, 1] }

# A mark the lookup flag ignores is passed over, and stays after the
# ligature; a mark it does not ignore stops the match.
expect ligated(0x08, True, [{ glyph: 10, props: 0 }, { glyph: 30, props: mark_props }, { glyph: 11, props: 0 }]).glyphs == [102, 30]
expect ligated(0x08, True, [{ glyph: 10, props: 0 }, { glyph: 30, props: mark_props }, { glyph: 30, props: mark_props }, { glyph: 11, props: 0 }, { glyph: 11, props: 0 }]).glyphs == [101, 30, 30]
expect ligated(0, True, [{ glyph: 10, props: 0 }, { glyph: 30, props: mark_props }, { glyph: 11, props: 0 }]).glyphs == [103, 30, 11]

# A ZWJ between components is skipped when the feature skips joiners, and
# stops the match when it does not; a ZWJ at the end leaves the
# one-glyph ligature.
expect ligated(0, True, [{ glyph: 10, props: 0 }, { glyph: 20, props: zwj_props }, { glyph: 11, props: 0 }]).glyphs == [102, 20]
expect ligated(0, False, [{ glyph: 10, props: 0 }, { glyph: 20, props: zwj_props }, { glyph: 11, props: 0 }]).glyphs == [103, 20, 11]
expect ligated(0, True, [{ glyph: 10, props: 0 }, { glyph: 20, props: zwj_props }]).glyphs == [103, 20]
