import ShaperLanguages

## From the plain-language names callers give (ISO 15924 script codes and
## BCP 47 language tags) to the OpenType script and language system tags a
## font's layout tables use, as HarfBuzz maps them (`hb-ot-tag.cc`,
## `hb-common.cc`), and each script's natural direction.
##
## Internal. Tags are big-endian four-byte numbers. Language tags whose
## meaning depends on a region, script or variant subtag (`zh-HK`,
## `zh-Hant`, `el-polyton`) map first through HarfBuzz's multi-subtag rules
## (`ShaperLanguages.complex`), then by their primary subtag.
ShaperTags :: {}.{

	tag_of : Str -> U64
	tag_of = |name| name.to_utf8().fold(0, |acc, b| acc * 256 + b.to_u64())

	## Up to four bytes as a tag, padded with spaces (HarfBuzz's
	## `hb_tag_from_string`).
	tag_from_bytes : List(U8) -> U64
	tag_from_bytes = |bytes| {
		var $t = 0
		for k in 0..<4 {
			$t = $t * 256 + (bytes.get(k) ?? ' ').to_u64()
		}
		$t
	}

	## HarfBuzz's script aliases, as tags: made once, when the program is
	## compiled.
	script_aliases : List((U64, U64))
	script_aliases = [
		("Qaai", "Zinh"),
		("Qaac", "Copt"),
		("Aran", "Arab"),
		("Cyrs", "Cyrl"),
		("Geok", "Geor"),
		("Hans", "Hani"),
		("Hant", "Hani"),
		("Jamo", "Hang"),
		("Latf", "Latn"),
		("Latg", "Latn"),
		("Syre", "Syrc"),
		("Syrj", "Syrc"),
		("Syrn", "Syrc"),
	].map(|(from, to)| (ShaperTags.tag_of(from), ShaperTags.tag_of(to)))

	unknown_script : U64
	unknown_script = ShaperTags.tag_of("Zzzz")

	## The ISO 15924 script a code names, normalised to one capital and
	## three small letters, with HarfBuzz's aliases; `Zzzz` (unknown) for
	## anything that does not look like a script code.
	script_of : Str -> U64
	script_of = |code| {
		raw = ShaperTags.tag_from_bytes(code.to_utf8())
		tag = raw.bitwise_and(0xDFDFDFDF).bitwise_or(0x00202020)
		match ShaperTags.script_aliases.find_first(|(from, _)| from == tag) {
			Ok((_, to)) => to
			Err(_) =>
				if tag.bitwise_and(0xE0E0E0E0) == 0x40606060 {
					tag
				} else {
					ShaperTags.unknown_script
				}
		}
	}

	## Scripts with newer OpenType tags (the Indic `2` versions, to which
	## the `3` versions are tried first) and with old tags not spelt as the
	## script code, as tags made when the program is compiled.
	new_script_tags : List((U64, U64))
	new_script_tags = [
		("Beng", "bng2"),
		("Deva", "dev2"),
		("Gujr", "gjr2"),
		("Guru", "gur2"),
		("Knda", "knd2"),
		("Mlym", "mlm2"),
		("Orya", "ory2"),
		("Taml", "tml2"),
		("Telu", "tel2"),
		("Mymr", "mym2"),
	].map(|(iso, t)| (ShaperTags.tag_of(iso), ShaperTags.tag_of(t)))

	old_script_tags : List((U64, U64))
	old_script_tags = [("Zmth", "math"), ("Hira", "kana"), ("Hrkt", "kana"), ("Laoo", "lao "), ("Yiii", "yi  "), ("Nkoo", "nko "), ("Vaii", "vai ")].map(|(iso, t)| (ShaperTags.tag_of(iso), ShaperTags.tag_of(t)))

	myanmar : U64
	myanmar = ShaperTags.tag_of("Mymr")

	latin_tags : List(U64)
	latin_tags = [ShaperTags.tag_of("latn")]

	## The OpenType script tags to try for an ISO 15924 code, best first.
	## An empty code is Latin (`latn`), as a browser shapes Latin text whose
	## script it is not told.
	script_tags : Str -> List(U64)
	script_tags = |code|
		if code.is_empty() {
			ShaperTags.latin_tags
		} else {
			script = ShaperTags.script_of(code)
			newer = match ShaperTags.new_script_tags.find_first(|(iso, _)| iso == script) {
				Ok((iso, two)) if iso == ShaperTags.myanmar => [two]
				# The `3` versions replace the last byte.
				Ok((_, two)) => [two.bitwise_and(0xFFFFFF00).bitwise_or('3'.to_u64()), two]
				Err(_) => []
			}
			old = match ShaperTags.old_script_tags.find_first(|(iso, _)| iso == script) {
				Ok((_, t)) => t
				Err(_) => script.bitwise_or(0x20000000)
			}
			newer.append(old)
		}

	## Scripts written right to left, and scripts written both ways, as
	## tags made when the program is compiled.
	rtl_scripts : List(U64)
	rtl_scripts = ["Arab", "Hebr", "Syrc", "Thaa", "Cprt", "Khar", "Phnx", "Nkoo", "Lydi", "Avst", "Armi", "Phli", "Prti", "Sarb", "Orkh", "Samr", "Mand", "Merc", "Mero", "Mani", "Mend", "Nbat", "Narb", "Palm", "Phlp", "Hatr", "Adlm", "Rohg", "Sogo", "Sogd", "Elym", "Chrs", "Yezi", "Ougr", "Gara", "Sidt"].map(ShaperTags.tag_of)

	either_scripts : List(U64)
	either_scripts = ["Hung", "Ital", "Runr", "Tfng"].map(ShaperTags.tag_of)

	## A script's natural horizontal direction: `Rtl`, `Ltr`, or `Either`
	## for scripts written both ways and for an empty code.
	script_direction : Str -> [Ltr, Rtl, Either]
	script_direction = |code|
		if code.is_empty() {
			Either
		} else {
			script = ShaperTags.script_of(code)
			if ShaperTags.rtl_scripts.contains(script) {
				Rtl
			} else if ShaperTags.either_scripts.contains(script) {
				Either
			} else {
				Ltr
			}
		}

	## A language tag in lower case with `_` as `-`, as HarfBuzz keeps one.
	normalize : Str -> List(U8)
	normalize = |language| language.to_utf8().map(|b| if (b == '_') '-' else if (b >= 'A' and b <= 'Z') b + 32 else b)

	## The OpenType tags a language and script string give: language system
	## tags to try, best first, and script tags when the language carries a
	## private-use `-x-hbsc` subtag (HarfBuzz's way to give a raw script
	## tag; `-x-hbot` gives a raw language system tag).
	language_tags : Str -> { languages : List(U64), scripts : [Given(U64), NotGiven] }
	language_tags = |language| {
		lang = ShaperTags.normalize(language)
		if lang.is_empty() {
			return { languages: [], scripts: NotGiven }
		}
		# The private-use part, and where the plain part ends.
		split =
			if lang.starts_with(['x', '-']) {
				{ limit: 0, private: lang }
			} else {
				var $limit = lang.len()
				var $private = []
				var $s = 1
				while $s + 1 < lang.len() {
					if (lang.get($s - 1) ?? 0) == '-' and (lang.get($s + 1) ?? 0) == '-' {
						if (lang.get($s) ?? 0) == 'x' {
							$private = lang.drop_first($s)
							$limit = $limit.min($s - 1)
							$s = lang.len()
						} else {
							$limit = $limit.min($s - 1)
							$s = $s + 1
						}
					} else {
						$s = $s + 1
					}
				}
				{ limit: $limit, private: $private }
			}
		scripts = match ShaperTags.private_tag(split.private, ShaperTags.hbsc, Lower) {
			Ok(t) => Given(t)
			Err(_) => NotGiven
		}
		languages = match ShaperTags.private_tag(split.private, ShaperTags.hbot, Upper) {
			Ok(t) => [t]
			Err(_) =>
				match ShaperTags.complex_tags(lang, split.limit) {
					Ok(tags) => tags
					Err(_) => ShaperTags.from_language(lang.take_first(split.limit))
				}
		}
		{ languages, scripts }
	}

	## The tags of HarfBuzz's multi-subtag rules for a language tag (lower
	## case) whose plain part ends at `limit`, as
	## `hb_ot_tags_from_complex_language` tests them.
	complex_tags : List(U8), U64 -> Try(List(U64), [NoRule])
	complex_tags = |lang, limit| {
		first = lang.first() ?? 0
		dash = lang.find_first_index(|b| b == '-')
		variant_ok = match dash {
			Ok(p) => limit >= 7 and p < limit and limit - p >= 5
			Err(_) => False
		}
		after = lang.drop_first(1)
		matched = ShaperTags.complex_rules.find_first(
			|rule| {
				a = rule.a
				b = rule.b
				if rule.kind == 0 {
					match dash {
						Ok(p) => variant_ok and ShaperTags.subtag_matches(lang, p, limit, b)
						Err(_) => False
					}
				} else if rule.first != first {
					False
				} else if rule.kind == 1 {
					after == a
				} else if rule.kind == 2 {
					next = after.get(a.len())
					limit >= 1 + a.len() and after.take_first(a.len()) == a and (next == Err(OutOfBounds) or next == Ok('-'))
				} else {
					after.take_first(a.len()) == a and ShaperTags.subtag_matches(lang, 0, limit, b)
				}
			},
		)
		match matched {
			Ok(rule) => Ok(rule.tags)
			Err(_) => Err(NoRule)
		}
	}

	## `ShaperLanguages.complex` as bytes and tags, made once when the
	## program is compiled, so matching a language tag allocates nothing.
	complex_rules : List({ first : U8, kind : U8, a : List(U8), b : List(U8), tags : List(U64) })
	complex_rules = ShaperLanguages.complex.map(
		|rule| {
			t = rule.tags.to_utf8()
			{ first: rule.first.to_utf8().first() ?? 0, kind: rule.kind, a: rule.a.to_utf8(), b: rule.b.to_utf8(), tags: ShaperTags.indices(t.len() // 4).map(|k| ShaperTags.tag_at(t, 4 * k)) }
		},
	)

	indices : U64 -> List(U64)
	indices = |n| {
		var $out = List.with_capacity(n)
		for k in 0..<n {
			$out = $out.append(k)
		}
		$out
	}

	## HarfBuzz's `subtag_matches`: `subtag` occurs in `lang` from `from`,
	## starts before `limit`, and is not followed by a letter or digit.
	subtag_matches : List(U8), U64, U64, List(U8) -> Bool
	subtag_matches = |lang, from, limit, subtag| {
		n = subtag.len()
		if limit < from + n {
			False
		} else {
			var $at = from
			var $result = False
			var $going = True
			while $going {
				# The next occurrence from `$at`.
				var $k = $at
				var $found = Err(NotFound)
				while $k + n <= lang.len() {
					if lang.sublist({ start: $k, len: n }) == subtag {
						$found = Ok($k)
						$k = lang.len()
					} else {
						$k = $k + 1
					}
				}
				match $found {
					Ok(s) if s < limit => {
						c = lang.get(s + n) ?? 0
						alnum = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9')
						if alnum {
							$at = s + n
						} else {
							$result = True
							$going = False
						}
					}
					_ => {
						$going = False
					}
				}
			}
			$result
		}
	}

	hbsc : List(U8)
	hbsc = "-hbsc".to_utf8()

	hbot : List(U8)
	hbot = "-hbot".to_utf8()

	default_script : U64
	default_script = ShaperTags.tag_of("DFLT")

	## A raw tag after `pre` in a private-use subtag: eight hexadecimal
	## digits after a `-`, or up to four letters and digits (padded).
	private_tag : List(U8), List(U8), [Lower, Upper] -> Try(U64, [NotGiven])
	private_tag = |private, pre, case| {
		var $at = Err(NotFound)
		var $k = 0
		while $k + pre.len() <= private.len() {
			if private.sublist({ start: $k, len: pre.len() }) == pre {
				$at = Ok($k + pre.len())
				$k = private.len()
			} else {
				$k = $k + 1
			}
		}
		match $at {
			Err(_) => Err(NotGiven)
			Ok(start) => {
				rest = private.drop_first(start)
				alnum = |b| (b >= 'a' and b <= 'z') or (b >= '0' and b <= '9')
				hex = |b| (b >= 'a' and b <= 'f') or (b >= '0' and b <= '9')
				if rest.first() == Ok('-') {
					digits = rest.drop_first(1).take_first(8)
					if digits.len() == 8 and digits.all(hex) {
						Ok(digits.fold(0, |acc, b| acc * 16 + (if (b <= '9') (b - '0').to_u64() else (b - 'a').to_u64() + 10)))
					} else {
						Err(NotGiven)
					}
				} else {
					upper = match case {
						Upper => True
						Lower => False
					}
					var $chars = []
					var $i = 0
					while $i < 4 and alnum(rest.get($i) ?? 0) {
						b = rest.get($i) ?? 0
						$chars = $chars.append(if (upper and b >= 'a' and b <= 'z') b - 32 else b)
						$i = $i + 1
					}
					if $chars.is_empty() {
						Err(NotGiven)
					} else {
						t = ShaperTags.tag_from_bytes($chars)
						# `DFLT` in any case is the default script tag.
						Ok(if (t.bitwise_and(0xDFDFDFDF) == ShaperTags.default_script) t.bitwise_xor((0xFFFFFFFF).bitwise_xor(0xDFDFDFDF)) else t)
					}
				}
			}
		}
	}

	## Language system tags for the plain part of a language tag, by its
	## primary (or extended) language subtag.
	from_language : List(U8) -> List(U64)
	from_language = |plain| {
		dash = plain.find_first_index(|b| b == '-')
		# An extended language subtag (three letters) replaces the primary.
		subtag = match dash {
			Ok(d) if plain.len() >= 6 => {
				rest = plain.drop_first(d + 1)
				ext = match rest.find_first_index(|b| b == '-') {
					Ok(e) => rest.take_first(e)
					Err(_) => rest
				}
				if (ext.len() == 3 and ext.all(|b| b >= 'a' and b <= 'z')) ext else ShaperTags.first_subtag(plain)
			}
			_ => ShaperTags.first_subtag(plain)
		}
		key = ShaperTags.tag_from_bytes(subtag)
		if subtag.len() == 2 {
			ShaperTags.lookup_two(key)
		} else if subtag.len() == 3 {
			match ShaperTags.search(ShaperLanguages.three, 8, key) {
				Ok(i) => [ShaperTags.tag_at(ShaperLanguages.three, 8 * i + 4)]
				Err(_) =>
					match ShaperTags.search(ShaperLanguages.multi, 16, key) {
						Ok(i) => [4, 8, 12].map(|k| ShaperTags.tag_at(ShaperLanguages.multi, 16 * i + k)).drop_if(|t| t == 0x20202020)
						Err(_) =>
							if ShaperTags.search(ShaperLanguages.blocked, 4, key).is_ok() {
								[]
							} else {
								# Assumed to be ISO 639-3, upper-cased.
								[key.bitwise_and((0xFFFFFFFF).bitwise_xor(0x20202000))]
							}
					}
			}
		} else {
			[]
		}
	}

	## The four-byte tag at `at` of a table.
	tag_at : List(U8), U64 -> U64
	tag_at = |table, at| {
		var $t = 0
		for k in 0..<4 {
			$t = $t * 256 + (table.get(at + k) ?? 0).to_u64()
		}
		$t
	}

	first_subtag : List(U8) -> List(U8)
	first_subtag = |plain|
		match plain.find_first_index(|b| b == '-') {
			Ok(d) => plain.take_first(d)
			Err(_) => plain
		}

	# Up to three tags of a two-letter subtag, in table order.
	lookup_two : U64 -> List(U64)
	lookup_two = |key| {
		table = ShaperLanguages.two
		match ShaperTags.search(table, 8, key) {
			Err(_) => []
			Ok(found) => {
				var $i = found
				while $i > 0 and ShaperTags.tag_at(table, 8 * ($i - 1)) == key {
					$i = $i - 1
				}
				var $out = []
				while $out.len() < 3 and 8 * $i < table.len() and ShaperTags.tag_at(table, 8 * $i) == key {
					$out = $out.append(ShaperTags.tag_at(table, 8 * $i + 4))
					$i = $i + 1
				}
				$out
			}
		}
	}

	## Binary search of a table of `stride`-byte records keyed by their
	## first four bytes: the index of a record with the key.
	search : List(U8), U64, U64 -> Try(U64, [NotFound])
	search = |table, stride, key| {
		var $low = 0
		var $high = table.len() // stride
		while $low < $high {
			mid = ($low + $high) // 2
			probe = ShaperTags.tag_at(table, stride * mid)
			if key < probe {
				$high = mid
			} else if key > probe {
				$low = mid + 1
			} else {
				return Ok(mid)
			}
		}
		Err(NotFound)
	}
}

# ----------------------------------------------------------------------

# Tests: the language tables are sorted (their lookups are binary
# searches) and map as HarfBuzz's `hb-ot-tag` maps. Top-level expects and
# helpers are not part of the module's API. Run with
# `roc test package/ShaperTags.roc`.

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

# Tags HarfBuzz maps by a region, script or variant subtag.
expect ShaperTags.language_tags("zh-HK").languages == [t("ZHH ")]
expect ShaperTags.language_tags("zh-tw").languages == [t("ZHT ")]
expect ShaperTags.language_tags("zh-Hant").languages == [t("ZHT ")]
expect ShaperTags.language_tags("zh-Hant-HK").languages == [t("ZHH ")]
expect ShaperTags.language_tags("zh-mo").languages == [t("ZHTM"), t("ZHH ")]
expect ShaperTags.language_tags("zh-cn").languages == [t("ZHS ")]
expect ShaperTags.language_tags("el-polyton").languages == [t("PGR ")]
expect ShaperTags.language_tags("en-fonipa").languages == [t("IPPH")]
expect ShaperTags.language_tags("art-lojban").languages == [t("JBO ")]
expect ShaperTags.language_tags("ro-MD").languages == [t("MOL "), t("ROM ")]
