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

import Face
import LayoutGsub
import ShaperArabic
import ShaperArabicFallbackData
import ShaperTags
import Sorted

## Font-specific synthesized Arabic presentation substitutions. These are
## prepared from nominal mappings, never reparsed or synthesized per run.
ShaperArabicFallback := {
	shape : LayoutGsub,
	steps : List(LayoutGsub.StageStep),
	tags : List(U64),
}.{
	none : ShaperArabicFallback
	none = { shape: LayoutGsub.none, steps: [], tags: [] }

	make : Face, ShaperArabic.Masks, U64 -> ShaperArabicFallback
	make = |face, masks, rlig_mask| {
		var $built = { subtables: [], ranges: [], values: [], rules: [], steps: 0 }
		var $lookups = []
		var $steps = []
		var $tags = []
		for form in 0..<4 {
			mask = if (form == 0) masks.init else if (form == 1) masks.medi else if (form == 2) masks.fina else masks.isol
			name = if (form == 0) "init" else if (form == 1) "medi" else if (form == 2) "fina" else "isol"
			var $rows = []
			for row in ShaperArabicFallbackData.forms {
				cp = if (form == 0) row.init else if (form == 1) row.medi else if (form == 2) row.fina else row.isol
				if cp != 0 {
					source = Face.glyph(face, row.cp.to_u32_wrap()) ?? 0
					target = Face.glyph(face, cp.to_u32_wrap()) ?? 0
					if source != 0 and target != 0 and source != target {
						$rows = $rows.append({ source, target })
					}
				}
			}
			keys = Sorted.unique($rows.map_with_index(|row, i| row.source.shl_wrap(32).bitwise_or(i)))
			if mask != 0 and !keys.is_empty() {
				{ subtables, ranges, values, rules, steps: work } = $built
				coverage = ranges.len()
				data = values.len()
				var $ranges = ranges
				var $values = values
				var $digest = { d0: 0, d1: 0, d2: 0 }
				for i in 0..<keys.len() {
					row = $rows.get((keys.get(i) ?? 0).bitwise_and(0xFFFFFFFF)) ?? { source: 0, target: 0 }
					$ranges = $ranges.append({ first: row.source, last: row.source, index: i })
					$values = $values.append(row.target)
					$digest = ShaperArabicFallback.add_digest($digest, row.source)
				}
				sub = { ..LayoutGsub.no_sub, kind: 1, coverage, coverage_len: keys.len(), data, data_len: keys.len() }
				index = $lookups.len()
				$lookups = $lookups.append({ ..LayoutGsub.no_lookup, start: subtables.len(), count: 1, props: 8, d0: $digest.d0, d1: $digest.d1, d2: $digest.d2 })
				$built = { subtables: subtables.append(sub), ranges: $ranges, values: $values, rules, steps: work }
				$steps = $steps.append({ step: { index, mask, auto_zwnj: True, auto_zwj: True, random: False }, per_syllable: False })
				$tags = $tags.append(ShaperTags.tag_of(name))
			}
		}
		for group in 0..<3 {
			var $rows = []
			for row in ShaperArabicFallbackData.ligatures {
				if row.group == group {
					first = Face.glyph(face, row.first.to_u32_wrap()) ?? 0
					second = Face.glyph(face, row.second.to_u32_wrap()) ?? 0
					third = if (group == 0) Face.glyph(face, row.third.to_u32_wrap()) ?? 0 else 0
					target = Face.glyph(face, row.substitute.to_u32_wrap()) ?? 0
					if first != 0 and second != 0 and target != 0 and (group != 0 or third != 0) {
						$rows = $rows.append({ first, second, third, target })
					}
				}
			}
			keys = Sorted.unique($rows.map_with_index(|row, i| row.first.shl_wrap(32).bitwise_or(i)))
			if rlig_mask != 0 and !keys.is_empty() {
				{ subtables, ranges, values, rules, steps: work } = $built
				var $firsts = []
				var $previous = 0xFFFFFFFFFFFFFFFF
				for key in keys {
					first = key.shr_zf_wrap(32)
					if first != $previous {
						$firsts = $firsts.append(first)
						$previous = first
					}
				}
				coverage = ranges.len()
				data = values.len()
				var $ranges = ranges
				var $values = values.concat(List.repeat(0, $firsts.len() + 1))
				var $at = 0
				var $digest = { d0: 0, d1: 0, d2: 0 }
				for i in 0..<$firsts.len() {
					first = $firsts.get(i) ?? 0
					$ranges = $ranges.append({ first, last: first, index: i })
					$values = $values.set(data + i, $values.len()) ?? []
					$digest = ShaperArabicFallback.add_digest($digest, first)
					while $at < keys.len() and (keys.get($at) ?? 0).shr_zf_wrap(32) == first {
						row = $rows.get((keys.get($at) ?? 0).bitwise_and(0xFFFFFFFF)) ?? { first: 0, second: 0, third: 0, target: 0 }
						$values = $values.append(row.target).append(if (group == 0) 2 else 1).append(row.second)
						if group == 0 {
							$values = $values.append(row.third)
						}
						$at = $at + 1
					}
				}
				$values = $values.set(data + $firsts.len(), $values.len()) ?? []
				sub = { ..LayoutGsub.no_sub, kind: 4, coverage, coverage_len: $firsts.len(), data, data_len: $firsts.len() }
				index = $lookups.len()
				$lookups = $lookups.append({ ..LayoutGsub.no_lookup, start: subtables.len(), count: 1, mode: 2, props: if (group == 2) 0 else 8, d0: $digest.d0, d1: $digest.d1, d2: $digest.d2 })
				$built = { subtables: subtables.append(sub), ranges: $ranges, values: $values, rules, steps: work }
				$steps = $steps.append({ step: { index, mask: rlig_mask, auto_zwnj: True, auto_zwj: True, random: False }, per_syllable: False })
				$tags = $tags.append(ShaperTags.tag_of("rlig"))
			}
		}
		if $steps.is_empty() and [[0x0627.U64, 199], [0x0644, 225], [0x0649, 236], [0x064A, 237], [0x0652, 250]].all(|pair| (Face.glyph(face, (pair.get(0) ?? 0).to_u32_wrap()) ?? 0) == (pair.get(1) ?? 0)) {
			ShaperArabicFallback.win1256(face, masks, rlig_mask)
		} else { shape: LayoutGsub.from_synthesized($lookups, $built, Face.gdef(face)), steps: $steps, tags: $tags }
	}

	win1256 : Face, ShaperArabic.Masks, U64 -> ShaperArabicFallback
	win1256 = |face, masks, rlig_mask| {
		var $steps = []
		var $tags = []
		for i in 0..<ShaperArabicFallbackData.win_tags.len() {
			tag = ShaperArabicFallbackData.win_tags.get(i) ?? 0
			mask = if (tag == ShaperTags.tag_of("init")) masks.init else if (tag == ShaperTags.tag_of("medi")) masks.medi else if (tag == ShaperTags.tag_of("fina")) masks.fina else rlig_mask
			if mask != 0 {
				$steps = $steps.append({ step: { index: i, mask, auto_zwnj: True, auto_zwj: True, random: False }, per_syllable: False })
				$tags = $tags.append(tag)
			}
		}
		{ shape: LayoutGsub.from_synthesized(ShaperArabicFallbackData.win_lookups, ShaperArabicFallbackData.win_built, Face.gdef(face)), steps: $steps, tags: $tags }
	}

	add_digest : { d0 : U64, d1 : U64, d2 : U64 }, U64 -> { d0 : U64, d1 : U64, d2 : U64 }
	add_digest = |d, glyph| {
		d0: LayoutGsub.digest_range(d.d0, 0, glyph, glyph),
		d1: LayoutGsub.digest_range(d.d1, 4, glyph, glyph),
		d2: LayoutGsub.digest_range(d.d2, 9, glyph, glyph),
	}

	apply : ShaperArabicFallback, LayoutGsub.Session, LayoutGsub.Limits -> LayoutGsub.Session
	apply = |fallback, session, limits| LayoutGsub.resume(fallback.shape, fallback.steps, session, limits)

	credits : ShaperArabicFallback -> List({ tag : U64, mask : U64 })
	credits = |fallback| fallback.tags.map_with_index(|tag, i| { tag, mask: (fallback.steps.get(i) ?? { step: { index: 0, mask: 0, auto_zwnj: True, auto_zwj: True, random: False }, per_syllable: False }).step.mask })
}
