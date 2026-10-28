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
# Joining transition table adapted from HarfBuzz14.6.0 hb-ot-shaper-arabic.cc.

import ShaperJoiningData
import ShaperNormalize
import LayoutGsub
import ShaperTags

## Arabic joining actions over logical characters, including transparent
## marks and join controls. Context participates in joining but is never
## emitted. The same machine also describes the Syriac joining groups;
## enabling another script still requires its own conformance evidence.
ShaperArabic :: {}.{
	Masks : { isol : U64, fina : U64, fin2 : U64, fin3 : U64, medi : U64, med2 : U64, init : U64 }
	no_masks : Masks
	no_masks = { isol: 0, fina: 0, fin2: 0, fin3: 0, medi: 0, med2: 0, init: 0 }

	form_names : List(Str)
	form_names = ["isol", "fina", "fin2", "fin3", "medi", "med2", "init"]

	stage : U64 -> U64
	stage = |tag| {
		if tag == ShaperTags.tag_of("rvrn") {
			0
		}
		else if tag == ShaperTags.tag_of("isol") {
			2
		}
		else if tag == ShaperTags.tag_of("fina") {
			3
		}
		else if tag == ShaperTags.tag_of("fin2") {
			4
		}
		else if tag == ShaperTags.tag_of("fin3") {
			5
		}
		else if tag == ShaperTags.tag_of("medi") {
			6
		}
		else if tag == ShaperTags.tag_of("med2") {
			7
		}
		else if tag == ShaperTags.tag_of("init") {
			8
		}
		else if tag == ShaperTags.tag_of("rlig") {
			9
		}
		else if tag == ShaperTags.tag_of("calt") or tag == ShaperTags.tag_of("rclt") {
			10
		}
		else if tag == ShaperTags.tag_of("liga") or tag == ShaperTags.tag_of("clig") or tag == ShaperTags.tag_of("mset") {
			11
		}
		else {
			1
		}
	}

	manual_tags : List(Str)
	manual_tags = ShaperArabic.form_names.concat(["ccmp", "locl", "rlig", "calt", "rclt", "liga", "clig", "mset"])
	manual_zwj : U64 -> Bool
	manual_zwj = |tag| ShaperArabic.manual_tags.any(|name| ShaperTags.tag_of(name) == tag)
	Entry : { previous : U8, current : U8, state : U8 }

	## State/action numbering follows HarfBuzz 14.6.0's Arabic shaper.
	## Actions: isol, fina, fin2, fin3, medi, med2, init, none (0..7).
	## Columns: non-joining, left, right, dual, Alaph, Dalath/Rish.
	transitions : List(Entry)
	transitions = [
		{ previous: 7, current: 7, state: 0 },
		{ previous: 7, current: 0, state: 2 },
		{ previous: 7, current: 0, state: 1 },
		{ previous: 7, current: 0, state: 2 },
		{ previous: 7, current: 0, state: 1 },
		{ previous: 7, current: 0, state: 6 },
		{ previous: 7, current: 7, state: 0 },
		{ previous: 7, current: 0, state: 2 },
		{ previous: 7, current: 0, state: 1 },
		{ previous: 7, current: 0, state: 2 },
		{ previous: 7, current: 2, state: 5 },
		{ previous: 7, current: 0, state: 6 },
		{ previous: 7, current: 7, state: 0 },
		{ previous: 7, current: 0, state: 2 },
		{ previous: 6, current: 1, state: 1 },
		{ previous: 6, current: 1, state: 3 },
		{ previous: 6, current: 1, state: 4 },
		{ previous: 6, current: 1, state: 6 },
		{ previous: 7, current: 7, state: 0 },
		{ previous: 7, current: 0, state: 2 },
		{ previous: 4, current: 1, state: 1 },
		{ previous: 4, current: 1, state: 3 },
		{ previous: 4, current: 1, state: 4 },
		{ previous: 4, current: 1, state: 6 },
		{ previous: 7, current: 7, state: 0 },
		{ previous: 7, current: 0, state: 2 },
		{ previous: 5, current: 0, state: 1 },
		{ previous: 5, current: 0, state: 2 },
		{ previous: 5, current: 2, state: 5 },
		{ previous: 5, current: 0, state: 6 },
		{ previous: 7, current: 7, state: 0 },
		{ previous: 7, current: 0, state: 2 },
		{ previous: 0, current: 0, state: 1 },
		{ previous: 0, current: 0, state: 2 },
		{ previous: 0, current: 2, state: 5 },
		{ previous: 0, current: 0, state: 6 },
		{ previous: 7, current: 7, state: 0 },
		{ previous: 7, current: 0, state: 2 },
		{ previous: 7, current: 0, state: 1 },
		{ previous: 7, current: 0, state: 2 },
		{ previous: 7, current: 3, state: 5 },
		{ previous: 7, current: 0, state: 6 },
	]

	joining_type : U64 -> U64
	joining_type = |cp| {
		var $low = 0
		var $high = ShaperJoiningData.ranges.len()
		while $low < $high {
			mid = ($low + $high) // 2
			r = ShaperJoiningData.ranges.get(mid) ?? { first: 0, last: 0, kind: 0 }
			if cp < r.first.to_u64() {
				$high = mid
			}
			else if cp > r.last.to_u64() {
				$low = mid + 1
			}
			else {
				return r.kind.to_u64()
			}
		}
		0
	}

	transition : U64, U64 -> Entry
	transition = |state, kind| ShaperArabic.transitions.get(6 * state + kind) ?? { previous: 7, current: 7, state: 0 }

	mask : Masks, U64 -> U64
	mask = |m, action| match action {
		0 => m.isol
		1 => m.fina
		2 => m.fin2
		3 => m.fin3
		4 => m.medi
		5 => m.med2
		6 => m.init
		_ => 0
	}

	setup : List(ShaperNormalize.Char), Masks, { before : List(U32), after : List(U32) } -> List(ShaperNormalize.Char)
	setup = |chars, masks, context| {
		count = chars.len()
		var $actions = List.repeat(7.U64, count)
		var $unsafe = List.repeat(False, count)
		var $state = 0.U64
		var $previous = count
		var $before = context.before.len()
		var $search = True
		while $search and $before > 0 {
			$before = $before - 1
			kind = ShaperArabic.joining_type((context.before.get($before) ?? 0).to_u64())
			if kind != 6 {
				$state = ShaperArabic.transition(0, kind).state.to_u64()
				$search = False
			}
		}
		for i in 0..<count {
			current = chars.get(i) ?? ShaperNormalize.no_char
			kind = ShaperArabic.joining_type(current.cp)
			if kind != 6 {
				entry = ShaperArabic.transition($state, kind)
				if entry.previous != 7 and $previous < count {
					# The previous nontransparent character is in this run.
					$actions = $actions.set($previous, entry.previous.to_u64()) ?? []
					minimum = (chars.get($previous) ?? ShaperNormalize.no_char).cluster.min(current.cluster)
					for j in $previous..=i {
						if (chars.get(j) ?? ShaperNormalize.no_char).cluster != minimum {
							$unsafe = $unsafe.set(j, True) ?? []
						}
					}
				}
				$actions = $actions.set(i, entry.current.to_u64()) ?? []
				$previous = i
				$state = entry.state.to_u64()
			}
		}
		var $after = 0
		var $looking = True
		while $looking and $after < context.after.len() {
			kind = ShaperArabic.joining_type((context.after.get($after) ?? 0).to_u64())
			if kind != 6 {
				entry = ShaperArabic.transition($state, kind)
				if entry.previous != 7 and $previous < count {
					$actions = $actions.set($previous, entry.previous.to_u64()) ?? []
				}
				$looking = False
			}
			$after = $after + 1
		}
		var $out = List.with_capacity(count)
		for i in 0..<count {
			c = chars.get(i) ?? ShaperNormalize.no_char
			action = $actions.get(i) ?? 7
			flags = if ($unsafe.get(i) ?? False) LayoutGsub.unsafe else 0
			$out = $out.append({ ..c, mask: c.mask.bitwise_or(ShaperArabic.mask(masks, action)).bitwise_or(flags) })
		}
		$out
	}
}

expect ShaperArabic.joining_type(0x200D) == 3 and ShaperArabic.joining_type(0x200C) == 0 and ShaperArabic.joining_type(0x064E) == 6

expect ShaperJoiningData.ranges.all(|r| r.first <= r.last and r.last <= 0x10FFFF and r.kind > 0 and r.kind <= 6)
