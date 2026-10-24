import ShaperTags
import ShaperLanguages

## In-package tests of `ShaperTags`: the language tables are sorted (their
## lookups are binary searches) and map as HarfBuzz's `hb-ot-tag` maps.
## Test-only: `main.roc` does not import this module. Run with
## `roc test package/ShaperTagsTests.roc`.
ShaperTagsTests :: {}.{}

sorted : List(U8), U64, Bool -> Bool
sorted = |table, stride, strict| {
	count = table.len() // stride
	var $ok = table.len() % stride == 0
	for i in 1..<count {
		a = ShaperTags.tag_at(table, stride * (i - 1))
		b = ShaperTags.tag_at(table, stride * i)
		if if (strict) a >= b else a > b {
			$ok = False
		}
	}
	$ok
}

expect sorted(ShaperLanguages.two, 8, False)
expect sorted(ShaperLanguages.three, 8, True)
expect sorted(ShaperLanguages.multi, 16, True)
expect sorted(ShaperLanguages.blocked, 4, True)

t : Str -> U64
t = |name| ShaperTags.tag_of(name)

expect ShaperTags.language_tags("en").languages == [t("ENG ")]
expect ShaperTags.language_tags("tr").languages == [t("TRK ")]
expect ShaperTags.language_tags("de-CH").languages == [t("DEU ")]
expect ShaperTags.language_tags("EN_us").languages == [t("ENG ")]
# Several tags, best first.
expect ShaperTags.language_tags("ms").languages.first() == Ok(t("MLY "))
# Three letters: listed, several tags, blocked, or upper-cased.
expect ShaperTags.language_tags("aae").languages == [t("SQI ")]
expect ShaperTags.language_tags("acr").languages == [t("ACR "), t("MYN ")]
expect ShaperTags.language_tags("aba").languages == []
expect ShaperTags.language_tags("qqq").languages == [t("QQQ ")]
# An extended language subtag replaces the primary one.
expect ShaperTags.language_tags("zh-yue").languages == ShaperTags.language_tags("yue").languages
expect ShaperTags.language_tags("").languages == []
expect ShaperTags.language_tags("x-hbotABC").languages == [t("ABC ")]
expect ShaperTags.language_tags("fr-x-hbscgrek").scripts == Given(t("grek"))
expect ShaperTags.language_tags("x-hbsc-6c61746e").scripts == Given(t("latn"))

expect ShaperTags.script_tags("Latn") == [t("latn")]
expect ShaperTags.script_tags("latn") == [t("latn")]
expect ShaperTags.script_tags("") == [t("latn")]
expect ShaperTags.script_tags("Deva") == [t("dev3"), t("dev2"), t("deva")]
expect ShaperTags.script_tags("Mymr") == [t("mym2"), t("mymr")]
expect ShaperTags.script_tags("Hira") == [t("kana")]
expect ShaperTags.script_tags("Laoo") == [t("lao ")]
expect ShaperTags.script_tags("Hant") == [t("hani")]
expect ShaperTags.script_tags("12") == [t("zzzz")]

expect ShaperTags.script_direction("Arab") == Rtl
expect ShaperTags.script_direction("Hebr") == Rtl
expect ShaperTags.script_direction("Latn") == Ltr
expect ShaperTags.script_direction("Runr") == Either
expect ShaperTags.script_direction("") == Either
