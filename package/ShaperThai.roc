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
# Thai preprocessing and fallback tables adapted from HarfBuzz14.6.0 hb-ot-shaper-thai.cc.

import Face
import ShaperNormalize
import ShaperUnicode
import LayoutGsub

## Thai and Lao Sara Am decomposition and reordering. The legacy Thai
## fallback only selects a font's own Windows or Macintosh PUA glyphs.
ShaperThai :: {}.{
	above : U64 -> Bool
	above = |cp| {
		u = cp.bitwise_and(0xFFFFFFFFFFFFFF7F)
		(u >= 0xE34 and u <= 0xE37) or (u >= 0xE47 and u <= 0xE4E) or u == 0xE31 or u == 0xE3B
	}

	preprocess : List(ShaperNormalize.Char), Bool -> List(ShaperNormalize.Char)
	preprocess = |chars, characters| {
		var $out = List.with_capacity(chars.len())
		for c in chars {
			if c.cp.bitwise_and(0xFFFFFFFFFFFFFF7F) != 0xE33 {
				$out = $out.append(c)
			} else {
				props = ShaperUnicode.with_category(c.props, ShaperUnicode.non_spacing_mark).bitwise_or(ShaperUnicode.continuation)
				$out = $out.append({ ..c, cp: c.cp + 0x1A, props }).append({ ..c, cp: c.cp - 1 })
				end = $out.len()
				var $start = end - 2
				while $start > 0 and ShaperThai.above(($out.get($start - 1) ?? ShaperNormalize.no_char).cp) {
					$start = $start - 1
				}
				if $start + 2 < end {
					$out = ShaperNormalize.merge_clusters($out, $start, end)
					nikhahit = $out.get(end - 2) ?? ShaperNormalize.no_char
					var $i = end - 2
					while $i > $start {
						previous = $out.get($i - 1) ?? ShaperNormalize.no_char
						$out = $out.set($i, previous) ?? []
						$i = $i - 1
					}
					$out = $out.set($start, nikhahit) ?? []
				}
				if $start > 0 and !characters {
					$out = ShaperNormalize.merge_clusters($out, $start - 1, end)
				}
			}
		}
		$out
	}

	consonant : U64 -> U64
	consonant = |cp| {
		if cp == 0xE1B or cp == 0xE1D or cp == 0xE1F {
			1
		}
		else if cp == 0xE0D or cp == 0xE10 {
			2
		}
		else if cp == 0xE0E or cp == 0xE0F {
			3
		}
		else if cp >= 0xE01 and cp <= 0xE2E {
			0
		}
		else {
			4
		}
	}

	mark : U64 -> U64
	mark = |cp| {
		if cp == 0xE31 or (cp >= 0xE34 and cp <= 0xE37) or cp == 0xE47 or cp == 0xE4D or cp == 0xE4E {
			0
		}
		else if cp >= 0xE38 and cp <= 0xE3A {
			1
		}
		else if cp >= 0xE48 and cp <= 0xE4C {
			2
		}
		else {
			3
		}
	}

	Edge : { action : U64, next : U64 }
	above_edges : List(Edge)
	above_edges = [{ action: 0, next: 3 }, { action: 0, next: 0 }, { action: 1, next: 3 }, { action: 2, next: 2 }, { action: 0, next: 1 }, { action: 3, next: 2 }, { action: 0, next: 3 }, { action: 0, next: 2 }, { action: 2, next: 3 }, { action: 0, next: 3 }, { action: 0, next: 3 }, { action: 0, next: 3 }]
	below_edges : List(Edge)
	below_edges = [{ action: 0, next: 0 }, { action: 0, next: 2 }, { action: 0, next: 0 }, { action: 0, next: 1 }, { action: 4, next: 2 }, { action: 0, next: 1 }, { action: 0, next: 2 }, { action: 1, next: 2 }, { action: 0, next: 2 }]

	Pua : { action : U64, cp : U64, win : U64, mac : U64 }
	pua : List(Pua)
	pua = [{ action: 1, cp: 3656, win: 63242, mac: 63627 }, { action: 1, cp: 3657, win: 63243, mac: 63630 }, { action: 1, cp: 3658, win: 63244, mac: 63633 }, { action: 1, cp: 3659, win: 63245, mac: 63636 }, { action: 1, cp: 3660, win: 63246, mac: 63639 }, { action: 1, cp: 3640, win: 63256, mac: 63643 }, { action: 1, cp: 3641, win: 63257, mac: 63644 }, { action: 1, cp: 3642, win: 63258, mac: 63645 }, { action: 3, cp: 3656, win: 63237, mac: 63628 }, { action: 3, cp: 3657, win: 63238, mac: 63631 }, { action: 3, cp: 3658, win: 63239, mac: 63634 }, { action: 3, cp: 3659, win: 63240, mac: 63637 }, { action: 3, cp: 3660, win: 63241, mac: 63640 }, { action: 2, cp: 3656, win: 63251, mac: 63626 }, { action: 2, cp: 3657, win: 63252, mac: 63629 }, { action: 2, cp: 3658, win: 63253, mac: 63632 }, { action: 2, cp: 3659, win: 63254, mac: 63635 }, { action: 2, cp: 3660, win: 63255, mac: 63638 }, { action: 2, cp: 3633, win: 63248, mac: 63620 }, { action: 2, cp: 3636, win: 63233, mac: 63621 }, { action: 2, cp: 3637, win: 63234, mac: 63622 }, { action: 2, cp: 3638, win: 63235, mac: 63623 }, { action: 2, cp: 3639, win: 63236, mac: 63624 }, { action: 2, cp: 3655, win: 63250, mac: 63625 }, { action: 2, cp: 3661, win: 63249, mac: 63641 }, { action: 4, cp: 3597, win: 63247, mac: 63642 }, { action: 4, cp: 3600, win: 63232, mac: 63646 }]

	mapped : Face, U64, U64 -> U64
	mapped = |face, cp, action| {
		var $result = cp
		for entry in ShaperThai.pua {
			if entry.action == action and entry.cp == cp {
				if Face.glyph(face, entry.win.to_u32_wrap()).is_ok() {
					$result = entry.win
				}
				else if Face.glyph(face, entry.mac.to_u32_wrap()).is_ok() {
					$result = entry.mac
				}
			}
		}
		$result
	}

	legacy : Face, List(ShaperNormalize.Char) -> List(ShaperNormalize.Char)
	legacy = |face, chars| {
		var $chars = chars
		var $above = 3
		var $below = 2
		var $base = 0
		for i in 0..<chars.len() {
			c = $chars.get(i) ?? ShaperNormalize.no_char
			kind_mark = ShaperThai.mark(c.cp)
			if kind_mark == 3 {
				kind = ShaperThai.consonant(c.cp)
				$above = [0.U64, 1, 0, 0, 3].get(kind) ?? 3
				$below = [0.U64, 0, 1, 2, 2].get(kind) ?? 2
				$base = i
			} else {
				a = ShaperThai.above_edges.get($above * 3 + kind_mark) ?? { action: 0, next: 3 }
				b = ShaperThai.below_edges.get($below * 3 + kind_mark) ?? { action: 0, next: 2 }
				$above = a.next
				$below = b.next
				action = if (a.action != 0) a.action else b.action
				# HarfBuzz marks the half-open span [base, i) unsafe.
				minimum = ($chars.get($base) ?? ShaperNormalize.no_char).cluster
				# Earlier marks were already flagged by the preceding iteration.
				# Extending the unsafe span once keeps long mark sequences linear.
				if i > $base + 1 {
					prior = $chars.get(i - 1) ?? ShaperNormalize.no_char
					if prior.cluster != minimum {
						$chars = $chars.set(i - 1, { ..prior, mask: prior.mask.bitwise_or(LayoutGsub.unsafe) }) ?? []
					}
				}
				index = if (action == 4) $base else i
				prior = $chars.get(index) ?? ShaperNormalize.no_char
				$chars = $chars.set(index, { ..prior, cp: ShaperThai.mapped(face, prior.cp, action) }) ?? []
			}
		}
		$chars
	}
}
