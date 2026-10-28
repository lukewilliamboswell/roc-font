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
# Hangul preprocessing adapted from HarfBuzz14.6.0 hb-ot-shaper-hangul.cc.

import Face
import ShaperNormalize
import LayoutGsub

## Font-dependent Hangul composition, Jamo feature assignment and tone
## reordering. Preprocessing grows each input scalar to at most three.
ShaperHangul :: {}.{
	Masks : { ljmo : U64, vjmo : U64, tjmo : U64, calt : U64 }
	no_masks : Masks
	no_masks = { ljmo: 0, vjmo: 0, tjmo: 0, calt: 0 }

	is_l : U64 -> Bool
	is_l = |u| (u >= 0x1100 and u <= 0x115F) or (u >= 0xA960 and u <= 0xA97C)
	is_v : U64 -> Bool
	is_v = |u| (u >= 0x1160 and u <= 0x11A7) or (u >= 0xD7B0 and u <= 0xD7C6)
	is_t : U64 -> Bool
	is_t = |u| (u >= 0x11A8 and u <= 0x11FF) or (u >= 0xD7CB and u <= 0xD7FB)
	has_glyph : Face, U64 -> Bool
	has_glyph = |face, cp| Face.glyph(face, cp.to_u32_wrap()).is_ok()
	zero_width : Face, Face.Location, U64 -> Bool
	zero_width = |face, location, cp| match Face.glyph(face, cp.to_u32_wrap()) {
		Ok(glyph) => Face.advance(face, location, glyph) == 0
		Err(_) => False
	}

	span : List(ShaperNormalize.Char), U64, U64, Bool -> List(ShaperNormalize.Char)
	span = |chars, start, end, merge| {
		var $chars = chars
		var $minimum = 0xFFFFFFFFFFFFFFFF.U64
		for i in start..<end {
			$minimum = $minimum.min(($chars.get(i) ?? ShaperNormalize.no_char).cluster)
		}
		for i in start..<end {
			c = $chars.get(i) ?? ShaperNormalize.no_char
			if c.cluster != $minimum {
				$chars = $chars.set(i, { ..c, mask: c.mask.bitwise_or(LayoutGsub.unsafe) }) ?? []
			}
		}
		if (merge) ShaperNormalize.merge_clusters($chars, start, end) else $chars
	}

	setup : List(ShaperNormalize.Char), Masks -> List(ShaperNormalize.Char)
	setup = |chars, masks| chars.map(
		|c| if ShaperHangul.is_l(c.cp) or ShaperHangul.is_v(c.cp) or ShaperHangul.is_t(c.cp) {
			{ ..c, mask: c.mask.bitwise_and(0xFFFFFFFFFFFFFFFF - masks.calt) }
		} else c,
	)

	preprocess : Face, Face.Location, List(ShaperNormalize.Char), Bool, Masks -> List(ShaperNormalize.Char)
	preprocess = |face, location, input, characters, masks| {
		var $chars = input
		var $out = List.with_capacity($chars.len())
		var $unsafe_at = $chars.len()
		var $i = 0
		var $start = 0
		var $end = 0
		while $i < $chars.len() {
			original = $chars.get($i) ?? ShaperNormalize.no_char
			c = if ($i == $unsafe_at) { ..original, mask: original.mask.bitwise_or(LayoutGsub.unsafe) } else original
			u = c.cp
			if u == 0x302E or u == 0x302F {
				if $start < $end and $end == $out.len() {
					$out = $out.append(c)
					$out = ShaperHangul.span($out, $start, $end, False)
					if !ShaperHangul.zero_width(face, location, u) {
						$out = ShaperNormalize.merge_clusters($out, $start, $end + 1)
						tone = $out.get($end) ?? ShaperNormalize.no_char
						var $j = $end
						while $j > $start {
							previous = $out.get($j - 1) ?? ShaperNormalize.no_char
							$out = $out.set($j, previous) ?? []
							$j = $j - 1
						}
						$out = $out.set($start, tone) ?? []
					}
				} else if ShaperHangul.has_glyph(face, 0x25CC) {
					circle = { ..c, cp: 0x25CC }
					if ShaperHangul.zero_width(face, location, u) {
						$out = $out.append(circle).append(c)
					}
					else {
						$out = $out.append(c).append(circle)
					}
				} else {
					$out = $out.append(c)
				}
				$start = $out.len()
				$end = $start
				$i = $i + 1
			} else {
				$start = $out.len()
				following = $chars.get($i + 1) ?? ShaperNormalize.no_char
				if ShaperHangul.is_l(u) and $i + 1 < $chars.len() and ShaperHangul.is_v(following.cp) {
					v = following.cp
					last = $chars.get($i + 2) ?? ShaperNormalize.no_char
					has_t = $i + 2 < $chars.len() and ShaperHangul.is_t(last.cp)
					t = if (has_t) last.cp else 0
					length = if (has_t) 3 else 2
					modern = u >= 0x1100 and u < 0x1113 and v >= 0x1161 and v < 0x1176 and (!has_t or (t >= 0x11A8 and t < 0x11C3))
					if modern {
						syllable = 0xAC00 + (u - 0x1100) * 588 + (v - 0x1161) * 28 + (if (has_t) t - 0x11A7 else 0)
						if ShaperHangul.has_glyph(face, syllable) {
							$chars = ShaperNormalize.merge_clusters($chars, $i, $i + length)
							# The consumed characters merge even at Characters level.
							var $cluster = c.cluster.min(following.cluster)
							if has_t {
								$cluster = $cluster.min(last.cluster)
							}
							$out = $out.append({ ..c, cp: syllable, cluster: $cluster })
							$end = $out.len()
							$i = $i + length
						} else {
							$out = $out.append({ ..c, mask: c.mask.bitwise_or(masks.ljmo) }).append({ ..following, mask: following.mask.bitwise_or(masks.vjmo) })
							if has_t {
								$out = $out.append({ ..last, mask: last.mask.bitwise_or(masks.tjmo) })
							}
							$end = $out.len()
							$out = ShaperHangul.span($out, $start, $end, !characters)
							$i = $i + length
						}
					} else {
						$out = $out.append({ ..c, mask: c.mask.bitwise_or(masks.ljmo) }).append({ ..following, mask: following.mask.bitwise_or(masks.vjmo) })
						if has_t {
							$out = $out.append({ ..last, mask: last.mask.bitwise_or(masks.tjmo) })
						}
						$end = $out.len()
						$out = ShaperHangul.span($out, $start, $end, !characters)
						$i = $i + length
					}
				} else if u >= 0xAC00 and u < 0xD7A4 {
					has_s = ShaperHangul.has_glyph(face, u)
					n = (u - 0xAC00) % 588
					tindex = n % 28
					following_t = $i + 1 < $chars.len() and ShaperHangul.is_t(following.cp)
					can_combine = tindex == 0 and following_t and following.cp < 0x11C3
					var $combined = False
					if can_combine {
						syllable = u + following.cp - 0x11A7
						if ShaperHangul.has_glyph(face, syllable) {
							$chars = ShaperNormalize.merge_clusters($chars, $i, $i + 2)
							$out = $out.append({ ..c, cp: syllable, cluster: c.cluster.min(following.cluster) })
							$end = $out.len()
							$i = $i + 2
							$combined = True
						}
					}
					if !$combined {
						if can_combine and following.cluster != c.cluster.min(following.cluster) {
							$unsafe_at = $i + 1
						}
						l = 0x1100 + (u - 0xAC00) // 588
						v = 0x1161 + n // 28
						t = 0x11A7 + tindex
						decompose = (!has_s or (tindex == 0 and following_t)) and ShaperHangul.has_glyph(face, l) and ShaperHangul.has_glyph(face, v) and (tindex == 0 or ShaperHangul.has_glyph(face, t))
						if decompose {
							$out = $out.append({ ..c, cp: l, mask: c.mask.bitwise_or(masks.ljmo) }).append({ ..c, cp: v, mask: c.mask.bitwise_or(masks.vjmo) })
							if tindex != 0 {
								$out = $out.append({ ..c, cp: t, mask: c.mask.bitwise_or(masks.tjmo) })
							}
							if has_s and tindex == 0 {
								if !characters {
									$chars = ShaperNormalize.merge_clusters($chars, $i, $i + 2)
								}
								$out = $out.append({ ..following, mask: following.mask.bitwise_or(masks.tjmo) })
								$i = $i + 1
							}
							$end = $out.len()
							$out = if (characters) $out else ShaperNormalize.merge_clusters($out, $start, $end)
						} else {
							if tindex == 0 and following_t and following.cluster != c.cluster.min(following.cluster) {
								$unsafe_at = $i + 1
							}
							$out = $out.append(c)
							if has_s {
								$end = $out.len()
							}
						}
						$i = $i + 1
					}
				} else {
					$out = $out.append(c)
					$i = $i + 1
				}
			}
		}
		$out
	}
}
