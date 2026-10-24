import LayoutKerning
import LayoutVar

## In-package tests of `LayoutKerning` for what the public API cannot
## observe: how much reading keeps. The kerning callers see is tested
## through the public API in `tests/api/`. Test-only: `main.roc` does not
## import this module. Run with `roc test package/LayoutKerningTests.roc`.
LayoutKerningTests :: {}.{}

be16 : U64 -> List(U8)
be16 = |v| [v.shr_zf_wrap(8).bitwise_and(0xFF).to_u8_wrap(), v.bitwise_and(0xFF).to_u8_wrap()]

# A pair set shared by many first glyphs is not copied: reading keeps one
# subtable, whose sets are read in place. The `GPOS` table has one script
# (`DFLT`), one feature (`kern`) and one pair adjustment lookup whose one
# subtable (at byte 56) points all `n` of its pair sets at one set of `n`
# pairs, each kerning by -1.
expect {
	n = 300
	header = [0, 1, 0, 0].concat(be16(10)).concat(be16(30)).concat(be16(44))
	scripts = be16(1).concat("DFLT".to_utf8()).concat(be16(8)).concat(be16(4)).concat(be16(0))
	language = be16(0).concat(be16(0xFFFF)).concat(be16(1)).concat(be16(0))
	features = be16(1).concat("kern".to_utf8()).concat(be16(8)).concat(be16(0)).concat(be16(1)).concat(be16(0))
	lookups = be16(1).concat(be16(4)).concat(be16(2)).concat(be16(0)).concat(be16(1)).concat(be16(8))
	# Format 1, coverage after the set offsets, x advance of the first glyph.
	fields = be16(1).concat(be16(10 + 2 * n)).concat(be16(4)).concat(be16(0)).concat(be16(n))
	offsets = List.repeat(be16(20 + 2 * n), n).join_map(|o| o)
	coverage = be16(2).concat(be16(1)).concat(be16(0)).concat(be16(n - 1)).concat(be16(0))
	var $set = be16(n)
	for g in 0..<n {
		$set = $set.concat(be16(g)).concat(be16(65535))
	}
	gpos = header.concat(scripts).concat(language).concat(features).concat(lookups).concat(fields).concat(offsets).concat(coverage).concat($set)
	match LayoutKerning.read_gpos(gpos, n, LayoutVar.none(0)) {
		Ok(read) => {
			kerning = LayoutKerning.combine(Present(read), Absent, LayoutVar.none(0))
			items = [5, 7, 299, 0].map_with_index(|glyph, i| { glyph, cluster: i, mask: 1, props: 0 })
			done = LayoutKerning.position(kerning, [{ index: 0, mask: 1 }], NoKern, items, n)
			LayoutKerning.stored_size(kerning) == 1 and done.ax == [-1, -1, -1, 0]
		}
		Err(_) => False
	}
}
