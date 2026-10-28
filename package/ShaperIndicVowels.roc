# HarfBuzz is licensed under the so-called "Old MIT" license.  Details follow.
# For parts of HarfBuzz that are licensed under different licenses see individual
# files names COPYING in subdirectories where applicable.
#
# Copyright © 2010-2022  Google, Inc.
# Copyright © 2015-2020  Ebrahim Byagowi
# Copyright © 2019,2020  Facebook, Inc.
# Copyright © 2012,2015  Mozilla Foundation
# Copyright © 2011  Codethink Limited
# Copyright © 2008,2010  Nokia Corporation and/or its subsidiary(-ies)
# Copyright © 2009  Keith Stribley
# Copyright © 2011  Martin Hosken and SIL International
# Copyright © 2007  Chris Wilson
# Copyright © 2005,2006,2020,2021,2022,2023  Behdad Esfahbod
# Copyright © 2004,2007,2008,2009,2010,2013,2021,2022,2023  Red Hat, Inc.
# Copyright © 1998-2005  David Turner and Werner Lemberg
# Copyright © 2016  Igalia S.L.
# Copyright © 2022  Matthias Clasen
# Copyright © 2018,2021  Khaled Hosny
# Copyright © 2018,2019,2020  Adobe, Inc
# Copyright © 2013-2015  Alexei Podtelezhnikov
#
# For full copyright notices consult the individual files in the package.
#
#
# Permission is hereby granted, without written agreement and without
# license or royalty fees, to use, copy, modify, and distribute this
# software and its documentation for any purpose, provided that the
# above copyright notice and the following two paragraphs appear in
# all copies of this software.
#
# IN NO EVENT SHALL THE COPYRIGHT HOLDER BE LIABLE TO ANY PARTY FOR
# DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES
# ARISING OUT OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN
# IF THE COPYRIGHT HOLDER HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH
# DAMAGE.
#
# THE COPYRIGHT HOLDER SPECIFICALLY DISCLAIMS ANY WARRANTIES, INCLUDING,
# BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
# FITNESS FOR A PARTICULAR PURPOSE.  THE SOFTWARE PROVIDED HEREUNDER IS
# ON AN "AS IS" BASIS, AND THE COPYRIGHT HOLDER HAS NO OBLIGATION TO
# PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS.
# Indic stage and category contracts adapted from HarfBuzz 14.6.0.
# hb-ot-shaper-indic.cc, hb-ot-shaper-indic.hh.

import ShaperNormalize
import ShaperIndicVowelData

## Invalid-vowel preprocessing shared by Indic and USE. This inserts the
## U+25CC character before normalization, as the pinned shaper specifies;
## it is separate from inserting a mapped dot into broken syllables.
ShaperIndicVowels :: {}.{
	Result : { chars : List(ShaperNormalize.Char), operations : U64, stopped : U64 }
	preprocess : U64, List(ShaperNormalize.Char), U64, U64 -> Result
	preprocess = |script, chars, limit, budget| {
		if chars.is_empty() or !ShaperIndicVowelData.has_script(script) {
			{ chars, operations: 0, stopped: 0 }
		} else {
			n = chars.len()
			var $i = 0
			var $count = 0
			var $operations = 0
			var $stopped = 0
			while $i < n and $stopped == 0 {
				if $operations >= budget {
					$stopped = 2
				}
				else {
					$operations = $operations + 1
					length = ShaperIndicVowels.match_at(script, chars, $i)
					if length == 0 {
						$i = $i + 1
					}
					else {
						$count = $count + 1
						$i = $i + length
					}
				}
			}
			if $stopped != 0 or $count == 0 {
				{ chars, operations: $operations, stopped: $stopped }
			}
			else if n > limit or $count > limit - n {
				{ chars, operations: $operations, stopped: 1 }
			}
			else if n + $count > budget - $operations {
				{ chars, operations: $operations, stopped: 2 }
			}
			else {
				# The first pass proved the exact final length before any
				# allocation sized by the selected output. Every matched
				# pair/triple is consumed once, matching upstream's cursor.
				var $out = List.with_capacity(n + $count)
				var $cursor = 0
				while $cursor < n {
					length = ShaperIndicVowels.match_at(script, chars, $cursor)
					if length == 0 {
						$out = $out.append(chars.get($cursor) ?? ShaperNormalize.no_char)
						$cursor = $cursor + 1
					} else {
						for j in $cursor..<$cursor + length - 1 {
							$out = $out.append(chars.get(j) ?? ShaperNormalize.no_char)
						}
						following = chars.get($cursor + length - 1) ?? ShaperNormalize.no_char
						# HB output_glyph inherits the following character's
						# Unicode props; only continuation is explicitly
						# cleared. Recomputing dot properties here differs.
						$out = $out.append({ ..following, cp: 0x25CC, props: following.props.bitwise_and(0xFFFFFFFFFFFFFF7F) })
						$out = $out.append(following)
						$cursor = $cursor + length
					}
				}
				{ chars: $out, operations: $operations + n + $count, stopped: 0 }
			}
		}
	}
	match_at : U64, List(ShaperNormalize.Char), U64 -> U64
	match_at = |script, chars, i| {
		if i + 1 >= chars.len() {
			0
		}
		else {
			a = (chars.get(i) ?? ShaperNormalize.no_char).cp
			b = (chars.get(i + 1) ?? ShaperNormalize.no_char).cp
			c = (chars.get(i + 2) ?? ShaperNormalize.no_char).cp
			ShaperIndicVowelData.length(script, a, b, c)
		}
	}
}

expect {
	chars = [0x0905, 0x093E].map(|cp| { ..ShaperNormalize.no_char, cp, props: 0x80 })
	result = ShaperIndicVowels.preprocess(0x44657661, chars, 10, 100)
	result.stopped == 0 and result.chars.map(|ch| ch.cp) == [0x0905, 0x25CC, 0x093E] and (result.chars.get(1) ?? ShaperNormalize.no_char).props == 0
}
expect {
	chars = [0x0930, 0x094D, 0x0907].map(|cp| { ..ShaperNormalize.no_char, cp })
	result = ShaperIndicVowels.preprocess(0x44657661, chars, 10, 100)
	result.stopped == 0 and result.chars.map(|ch| ch.cp) == [0x0930, 0x094D, 0x25CC, 0x0907]
}
expect {
	# Upstream's shorter prohibited prefix takes precedence.
	chars = [0x0A85, 0x0ABE, 0x0AC5].map(|cp| { ..ShaperNormalize.no_char, cp })
	result = ShaperIndicVowels.preprocess(0x47756A72, chars, 10, 100)
	result.stopped == 0 and result.chars.map(|ch| ch.cp) == [0x0A85, 0x25CC, 0x0ABE, 0x0AC5]
}
expect {
	chars = [0x0905, 0x093E].map(|cp| { ..ShaperNormalize.no_char, cp })
	result = ShaperIndicVowels.preprocess(0x44657661, chars, 2, 100)
	result.stopped == 1 and result.chars.len() == 2
}
expect {
	chars = [0x0905, 0x093E].map(|cp| { ..ShaperNormalize.no_char, cp })
	result = ShaperIndicVowels.preprocess(0x44657661, chars, 10, 0)
	result.stopped == 2 and result.operations == 0 and result.chars.len() == 2
}
expect ShaperIndicVowels.preprocess(0x44657661, [], 0, 0).stopped == 0
