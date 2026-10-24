import ShaperUnicode
import ShaperUnicodeData

## In-package tests of `ShaperUnicode`: the generated tables are sorted
## (lookups are binary searches) and give the Unicode 18.0.0 properties
## HarfBuzz 14.6.0 uses. Test-only: `main.roc` does not import this
## module. Run with `roc test package/ShaperUnicodeTests.roc`.
ShaperUnicodeTests :: {}.{}

increasing : List(U32) -> Bool
increasing = |list| {
	var $ok = True
	for i in 1..<list.len() {
		if (list.get(i - 1) ?? 0) >= (list.get(i) ?? 0) {
			$ok = False
		}
	}
	$ok
}

expect increasing(ShaperUnicode.gc_starts)
expect increasing(ShaperUnicode.cc_starts)
expect increasing(ShaperUnicode.decomposed)
expect increasing(ShaperUnicode.mirror_from)
expect increasing(ShaperUnicode.pictographic_first)
expect ShaperUnicodeData.general_categories.len() % 8 == 0
expect ShaperUnicodeData.decompositions.len() % 18 == 0
expect ShaperUnicodeData.compositions.len() % 18 == 0

expect {
	keys = ShaperUnicode.composition_keys
	var $ok = True
	for i in 1..<keys.len() {
		if (keys.get(i - 1) ?? 0) >= (keys.get(i) ?? 0) {
			$ok = False
		}
	}
	$ok
}

# General categories in HarfBuzz's numbering.
expect ShaperUnicode.general_category('a') == ShaperUnicode.lowercase_letter
expect ShaperUnicode.general_category('A') == ShaperUnicode.uppercase_letter
expect ShaperUnicode.general_category('5') == ShaperUnicode.decimal_number
expect ShaperUnicode.general_category(0x0301) == ShaperUnicode.non_spacing_mark
expect ShaperUnicode.general_category(0x0903) == ShaperUnicode.spacing_mark
expect ShaperUnicode.general_category(0x20DD) == ShaperUnicode.enclosing_mark
expect ShaperUnicode.general_category(0x2003) == ShaperUnicode.space_separator
expect ShaperUnicode.general_category(0x200D) == ShaperUnicode.format
expect ShaperUnicode.general_category(0x0378) == ShaperUnicode.unassigned
expect ShaperUnicode.general_category(0xAC01) == ShaperUnicode.other_letter
expect ShaperUnicode.general_category(0x4E00) == ShaperUnicode.other_letter
expect ShaperUnicode.general_category(0x1F3FB) == ShaperUnicode.modifier_symbol
expect ShaperUnicode.general_category(0xFF9E) == ShaperUnicode.modifier_letter
expect ShaperUnicode.general_category(0x10FFFD) == 3
expect ShaperUnicode.general_category(0x110000) == ShaperUnicode.unassigned
expect ShaperUnicode.general_category(0) == ShaperUnicode.control

# Combining classes, plain and as HarfBuzz modifies them.
expect ShaperUnicode.combining_class(0x0301) == 230
expect ShaperUnicode.combining_class(0x0327) == 202
expect ShaperUnicode.combining_class('a') == 0
expect ShaperUnicode.combining_class(0x05B0) == 10
expect ShaperUnicode.modified_combining_class(0x05B0) == 22
expect ShaperUnicode.modified_combining_class(0x0E38) == 3
expect ShaperUnicode.modified_combining_class(0x1A60) == 254

# Canonical decompositions, one step at a time, and compositions.
expect ShaperUnicode.decompose(0x00E9) == Two(0x65, 0x301)
expect ShaperUnicode.decompose(0x1EC7) == Two(0x1EB9, 0x302)
expect ShaperUnicode.decompose(0x2126) == One(0x3A9)
expect ShaperUnicode.decompose('a') == Unchanged
expect ShaperUnicode.decompose(0xAC00) == Two(0x1100, 0x1161)
expect ShaperUnicode.decompose(0xAC01) == Two(0xAC00, 0x11A8)
expect ShaperUnicode.compose(0x65, 0x301) == Ok(0xE9)
expect ShaperUnicode.compose(0x1100, 0x1161) == Ok(0xAC00)
expect ShaperUnicode.compose(0xAC00, 0x11A8) == Ok(0xAC01)
# Excluded from composition: DEVANAGARI LETTER QA.
expect ShaperUnicode.compose(0x0915, 0x093C).is_err()
expect ShaperUnicode.compose(0, 0x301).is_err()

# Mirroring and pictographs.
expect ShaperUnicode.mirroring('(') == ')'
expect ShaperUnicode.mirroring('>') == '<'
expect ShaperUnicode.mirroring('a') == 'a'
expect ShaperUnicode.is_pictographic(0x1F600)
expect ShaperUnicode.is_pictographic(0x2764)
expect !ShaperUnicode.is_pictographic('a')

# HarfBuzz's property words.
expect ShaperUnicode.props('a') == ShaperUnicode.lowercase_letter
expect ShaperUnicode.class_of(ShaperUnicode.props(0x0301)) == 230
expect ShaperUnicode.props(0x0301).bitwise_and(ShaperUnicode.continuation) != 0
expect ShaperUnicode.is_zwj(ShaperUnicode.props(0x200D))
expect ShaperUnicode.is_zwnj(ShaperUnicode.props(0x200C))
expect ShaperUnicode.props(0x034F).bitwise_and(ShaperUnicode.hidden) != 0
expect ShaperUnicode.props(0x00AD).bitwise_and(ShaperUnicode.ignorable) != 0
expect ShaperUnicode.props(0x3164).bitwise_and(ShaperUnicode.ignorable) == 0
expect ShaperUnicode.space_type(0x2003) == 1
expect ShaperUnicode.space_type('a') == 0
