import ShaperUnicodeData

## The Unicode character properties shaping uses, as HarfBuzz 14.6.0 uses
## them (`hb-unicode.hh`, `hb-ucd.cc`, `hb-ot-layout.hh`): general
## category, combining class (with HarfBuzz's modified classes for
## reordering), canonical decomposition and composition, bidi mirroring,
## Extended_Pictographic, HarfBuzz's default-ignorable set, variation
## selectors and space fallback types, and the per-character property
## word HarfBuzz keeps (`unicode_props`).
##
## Internal. The tables come from `ShaperUnicodeData` (generated from the
## Unicode Character Database 18.0.0, the version HarfBuzz 14.6.0 embeds)
## and are decoded once into flat lists, at compile time; every query is a
## binary search over them, total for every `U32`.
ShaperUnicode :: {}.{

	# ------------------------------------------------------------ general category

	## HarfBuzz's general category numbers (`hb_unicode_general_category_t`).
	control : U64
	control = 0

	format : U64
	format = 1

	unassigned : U64
	unassigned = 2

	lowercase_letter : U64
	lowercase_letter = 5

	modifier_letter : U64
	modifier_letter = 6

	other_letter : U64
	other_letter = 7

	titlecase_letter : U64
	titlecase_letter = 8

	uppercase_letter : U64
	uppercase_letter = 9

	spacing_mark : U64
	spacing_mark = 10

	enclosing_mark : U64
	enclosing_mark = 11

	non_spacing_mark : U64
	non_spacing_mark = 12

	decimal_number : U64
	decimal_number = 13

	modifier_symbol : U64
	modifier_symbol = 24

	space_separator : U64
	space_separator = 29

	is_mark_category : U64 -> Bool
	is_mark_category = |gc| gc == ShaperUnicode.spacing_mark or gc == ShaperUnicode.enclosing_mark or gc == ShaperUnicode.non_spacing_mark

	is_letter_category : U64 -> Bool
	is_letter_category = |gc| gc >= ShaperUnicode.lowercase_letter and gc <= ShaperUnicode.uppercase_letter

	## Hexadecimal digits at `at` of a table, as a number.
	hex : List(U8), U64, U64 -> U64
	hex = |table, at, width| {
		var $n = 0
		for k in 0..<width {
			b = (table.get(at + k) ?? '0').to_u64()
			digit = if (b >= 'A'.to_u64()) b - 'A'.to_u64() + 10 else b - '0'.to_u64()
			$n = $n * 16 + digit
		}
		$n
	}

	## The `field` of every record of `width` bytes, `digits` long at
	## `offset`, as a list.
	column : List(U8), U64, U64, U64 -> List(U32)
	column = |table, width, offset, digits| {
		count = table.len() // width
		var $out = List.with_capacity(count)
		for i in 0..<count {
			$out = $out.append(ShaperUnicode.hex(table, width * i + offset, digits).to_u32_wrap())
		}
		$out
	}

	gc_starts : List(U32)
	gc_starts = ShaperUnicode.column(ShaperUnicodeData.general_categories, 8, 0, 6)

	gc_values : List(U32)
	gc_values = ShaperUnicode.column(ShaperUnicodeData.general_categories, 8, 6, 2)

	cc_starts : List(U32)
	cc_starts = ShaperUnicode.column(ShaperUnicodeData.combining_classes, 8, 0, 6)

	cc_values : List(U32)
	cc_values = ShaperUnicode.column(ShaperUnicodeData.combining_classes, 8, 6, 2)

	decomposed : List(U32)
	decomposed = ShaperUnicode.column(ShaperUnicodeData.decompositions, 18, 0, 6)

	decomposed_first : List(U32)
	decomposed_first = ShaperUnicode.column(ShaperUnicodeData.decompositions, 18, 6, 6)

	decomposed_second : List(U32)
	decomposed_second = ShaperUnicode.column(ShaperUnicodeData.decompositions, 18, 12, 6)

	## Composition keys: the first character times 2^21 plus the second.
	composition_keys : List(U64)
	composition_keys = {
		table = ShaperUnicodeData.compositions
		count = table.len() // 18
		var $out = List.with_capacity(count)
		for i in 0..<count {
			$out = $out.append(ShaperUnicode.hex(table, 18 * i, 6) * 0x200000 + ShaperUnicode.hex(table, 18 * i + 6, 6))
		}
		$out
	}

	composed : List(U32)
	composed = ShaperUnicode.column(ShaperUnicodeData.compositions, 18, 12, 6)

	mirror_from : List(U32)
	mirror_from = ShaperUnicode.column(ShaperUnicodeData.mirrors, 12, 0, 6)

	mirror_to : List(U32)
	mirror_to = ShaperUnicode.column(ShaperUnicodeData.mirrors, 12, 6, 6)

	pictographic_first : List(U32)
	pictographic_first = ShaperUnicode.column(ShaperUnicodeData.pictographic, 12, 0, 6)

	pictographic_last : List(U32)
	pictographic_last = ShaperUnicode.column(ShaperUnicodeData.pictographic, 12, 6, 6)

	## The index of the last entry of an increasing list that is at most
	## `key`, or `Err` when every entry is greater.
	floor_index : List(U32), U64 -> Try(U64, [Below])
	floor_index = |list, key| {
		var $low = 0
		var $high = list.len()
		while $low < $high {
			mid = ($low + $high) // 2
			if (list.get(mid) ?? 0).to_u64() <= key {
				$low = mid + 1
			} else {
				$high = mid
			}
		}
		if ($low == 0) Err(Below) else Ok($low - 1)
	}

	## The index of `key` in an increasing list.
	exact_index : List(U32), U64 -> Try(U64, [NotFound])
	exact_index = |list, key|
		match ShaperUnicode.floor_index(list, key) {
			Ok(i) if (list.get(i) ?? 0).to_u64() == key => Ok(i)
			_ => Err(NotFound)
		}

	## A code point's general category (HarfBuzz's numbering); `Cn` past
	## Unicode.
	general_category : U64 -> U64
	general_category = |cp|
		if cp >= 0x110000 {
			ShaperUnicode.unassigned
		} else {
			match ShaperUnicode.floor_index(ShaperUnicode.gc_starts, cp) {
				Ok(i) => (ShaperUnicode.gc_values.get(i) ?? 2).to_u64()
				Err(_) => ShaperUnicode.control
			}
		}

	## A code point's canonical combining class.
	combining_class : U64 -> U64
	combining_class = |cp|
		if cp >= 0x110000 {
			0
		} else {
			match ShaperUnicode.floor_index(ShaperUnicode.cc_starts, cp) {
				Ok(i) => (ShaperUnicode.cc_values.get(i) ?? 0).to_u64()
				Err(_) => 0
			}
		}

	## HarfBuzz's permutation of combining classes (`hb-unicode.cc`): Hebrew
	## and Arabic classes in the order fonts expect, and a few Thai, Lao,
	## Telugu and Tibetan classes moved.
	modified_classes : List(U8)
	modified_classes = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 22, 15, 16, 17, 23, 18, 19, 20, 21, 14, 24, 12, 25, 13, 10, 11, 26, 28, 29, 30, 31, 32, 33, 27, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 4, 85, 86, 87, 88, 89, 90, 5, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 3, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 132, 131, 131, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255]

	## HarfBuzz's modified combining class of a code point.
	modified_combining_class : U64 -> U64
	modified_combining_class = |cp|
		if cp == 0x1A60 {
			254
		} else if cp == 0x0FC6 {
			254
		} else if cp == 0x0F39 {
			127
		} else {
			(ShaperUnicode.modified_classes.get(ShaperUnicode.combining_class(cp)) ?? 0).to_u64()
		}

	## The character that mirrors a code point in right-to-left text, or the
	## code point itself.
	mirroring : U64 -> U64
	mirroring = |cp|
		match ShaperUnicode.exact_index(ShaperUnicode.mirror_from, cp) {
			Ok(i) => (ShaperUnicode.mirror_to.get(i) ?? 0).to_u64()
			Err(_) => cp
		}

	is_pictographic : U64 -> Bool
	is_pictographic = |cp|
		match ShaperUnicode.floor_index(ShaperUnicode.pictographic_first, cp) {
			Ok(i) => cp <= (ShaperUnicode.pictographic_last.get(i) ?? 0).to_u64()
			Err(_) => False
		}

	is_regional_indicator : U64 -> Bool
	is_regional_indicator = |cp| cp >= 0x1F1E6 and cp <= 0x1F1FF

	# ------------------------------------------------------------ normalisation

	hangul_s : U64
	hangul_s = 0xAC00

	hangul_l : U64
	hangul_l = 0x1100

	hangul_v : U64
	hangul_v = 0x1161

	hangul_t : U64
	hangul_t = 0x11A7

	## One step of a canonical decomposition: two characters, one, or none.
	## Hangul syllables decompose algorithmically.
	decompose : U64 -> [Two(U64, U64), One(U64), Unchanged]
	decompose = |cp| {
		s = ShaperUnicode.hangul_s
		if cp >= s and cp < s + 11172 {
			si = cp - s
			if si % 28 != 0 {
				Two(s + (si // 28) * 28, ShaperUnicode.hangul_t + si % 28)
			} else {
				Two(ShaperUnicode.hangul_l + si // 588, ShaperUnicode.hangul_v + (si % 588) // 28)
			}
		} else {
			match ShaperUnicode.exact_index(ShaperUnicode.decomposed, cp) {
				Ok(i) => {
					a = (ShaperUnicode.decomposed_first.get(i) ?? 0).to_u64()
					b = (ShaperUnicode.decomposed_second.get(i) ?? 0).to_u64()
					if (b == 0) One(a) else Two(a, b)
				}
				Err(_) => Unchanged
			}
		}
	}

	## The character two characters compose to, as HarfBuzz composes them.
	compose : U64, U64 -> Try(U64, [NoComposition])
	compose = |a, b| {
		s = ShaperUnicode.hangul_s
		t = ShaperUnicode.hangul_t
		l = ShaperUnicode.hangul_l
		v = ShaperUnicode.hangul_v
		if a == 0 or b == 0 {
			Err(NoComposition)
		} else if a >= s and a < s + 11172 and b > t and b < t + 28 and (a - s) % 28 == 0 {
			Ok(a + (b - t))
		} else if a >= l and a < l + 19 and b >= v and b < v + 21 {
			Ok(s + (a - l) * 588 + (b - v) * 28)
		} else if a >= 0x200000 or b >= 0x200000 {
			Err(NoComposition)
		} else {
			key = a * 0x200000 + b
			keys = ShaperUnicode.composition_keys
			var $low = 0
			var $high = keys.len()
			var $found = Err(NoComposition)
			while $low < $high {
				mid = ($low + $high) // 2
				probe = keys.get(mid) ?? 0
				if probe < key {
					$low = mid + 1
				} else if probe > key {
					$high = mid
				} else {
					$found = Ok((ShaperUnicode.composed.get(mid) ?? 0).to_u64())
					$low = $high
				}
			}
			$found
		}
	}

	# ------------------------------------------------------------ HarfBuzz's sets

	## HarfBuzz's Default_Ignorable set (`hb-unicode.hh`): Unicode's, less the
	## Hangul fillers and U+1BCA0 to U+1BCA3, which fonts draw.
	is_default_ignorable : U64 -> Bool
	is_default_ignorable = |ch| {
		plane = ch.shr_zf_wrap(16)
		if plane == 0 {
			page = ch.shr_zf_wrap(8)
			if page == 0x00 {
				ch == 0x00AD
			} else if page == 0x03 {
				ch == 0x034F
			} else if page == 0x06 {
				ch == 0x061C
			} else if page == 0x17 {
				ch >= 0x17B4 and ch <= 0x17B5
			} else if page == 0x18 {
				ch >= 0x180B and ch <= 0x180F
			} else if page == 0x20 {
				(ch >= 0x200B and ch <= 0x200F) or (ch >= 0x202A and ch <= 0x202E) or (ch >= 0x2060 and ch <= 0x206F)
			} else if page == 0xFE {
				(ch >= 0xFE00 and ch <= 0xFE0F) or ch == 0xFEFF
			} else if page == 0xFF {
				ch >= 0xFFF0 and ch <= 0xFFF8
			} else {
				False
			}
		} else if plane == 0x01 {
			ch >= 0x1D173 and ch <= 0x1D17A
		} else if plane == 0x0E {
			ch >= 0xE0000 and ch <= 0xE0FFF
		} else {
			False
		}
	}

	## Variation selectors 1 to 256 (the Mongolian free variation selectors
	## are not among them, as in HarfBuzz).
	is_variation_selector : U64 -> Bool
	is_variation_selector = |cp| (cp >= 0xFE00 and cp <= 0xFE0F) or (cp >= 0xE0100 and cp <= 0xE01EF)

	## HarfBuzz's space fallback types (`space_t`): 0 not a space, then
	## em divisors 1 to 6 and 16, and 17 four-eighteenths of an em, 18 space,
	## 19 figure, 20 punctuation and 21 narrow.
	space_type : U64 -> U64
	space_type = |u|
		if u == 0x0020 or u == 0x00A0 {
			18
		} else if u == 0x2000 or u == 0x2002 {
			2
		} else if u == 0x2001 or u == 0x2003 or u == 0x3000 {
			1
		} else if u == 0x2004 {
			3
		} else if u == 0x2005 {
			4
		} else if u == 0x2006 {
			6
		} else if u == 0x2007 {
			19
		} else if u == 0x2008 {
			20
		} else if u == 0x2009 {
			5
		} else if u == 0x200A {
			16
		} else if u == 0x202F {
			21
		} else if u == 0x205F {
			17
		} else {
			0
		}

	# ------------------------------------------------------------ property words

	## HarfBuzz's 16-bit `unicode_props` word (`hb-ot-layout.hh`): the
	## general category in bits 0-4, then default ignorable (0x20), hidden
	## (0x40) and grapheme continuation (0x80); for marks the modified
	## combining class in the high byte, for format characters ZWJ (0x100)
	## and ZWNJ (0x200).
	gen_cat_bits : U64
	gen_cat_bits = 0x1F

	ignorable : U64
	ignorable = 0x20

	hidden : U64
	hidden = 0x40

	continuation : U64
	continuation = 0x80

	zwj : U64
	zwj = 0x100

	zwnj : U64
	zwnj = 0x200

	## Set on a variation selector whose sequence the cmap does not have.
	variation_selector : U64
	variation_selector = 0x400

	## The property word of a code point.
	props : U64 -> U64
	props = |u| {
		gc = ShaperUnicode.general_category(u)
		if u < 0x80 {
			gc
		} else {
			var $p = gc
			if ShaperUnicode.is_default_ignorable(u) {
				$p = $p.bitwise_or(ShaperUnicode.ignorable)
				if u == 0x200C {
					$p = $p.bitwise_or(ShaperUnicode.zwnj)
				} else if u == 0x200D {
					$p = $p.bitwise_or(ShaperUnicode.zwj)
				} else if (u >= 0x180B and u <= 0x180D) or u == 0x180F or (u >= 0xE0020 and u <= 0xE007F) or u == 0x034F {
					$p = $p.bitwise_or(ShaperUnicode.hidden)
				}
			}
			if ShaperUnicode.is_mark_category(gc) {
				$p = $p.bitwise_or(ShaperUnicode.continuation).bitwise_or(ShaperUnicode.modified_combining_class(u).shl_wrap(8))
			}
			$p
		}
	}

	general_category_of : U64 -> U64
	general_category_of = |p| p.bitwise_and(ShaperUnicode.gen_cat_bits)

	is_mark : U64 -> Bool
	is_mark = |p| ShaperUnicode.is_mark_category(p.bitwise_and(ShaperUnicode.gen_cat_bits))

	## The modified combining class in a property word (0 for a non-mark).
	class_of : U64 -> U64
	class_of = |p| if (ShaperUnicode.is_mark(p)) p.shr_zf_wrap(8).bitwise_and(0xFF) else 0

	## A property word with another general category, its high byte cleared.
	with_category : U64, U64 -> U64
	with_category = |p, gc| p.bitwise_and(0xE0).bitwise_or(gc).bitwise_or(p.bitwise_and(0xFFFFFFFFFFFF0000))

	## A property word with another value in its high byte (only for a mark's
	## class or a space's fallback type).
	with_high : U64, U64 -> U64
	with_high = |p, high| p.bitwise_and(0xFFFFFFFFFFFF00FF).bitwise_or(high.bitwise_and(0xFF).shl_wrap(8))

	is_zwj : U64 -> Bool
	is_zwj = |p| p.bitwise_and(ShaperUnicode.gen_cat_bits) == ShaperUnicode.format and p.bitwise_and(ShaperUnicode.zwj) != 0

	is_zwnj : U64 -> Bool
	is_zwnj = |p| p.bitwise_and(ShaperUnicode.gen_cat_bits) == ShaperUnicode.format and p.bitwise_and(ShaperUnicode.zwnj) != 0

	is_space : U64 -> Bool
	is_space = |p| p.bitwise_and(ShaperUnicode.gen_cat_bits) == ShaperUnicode.space_separator
}
