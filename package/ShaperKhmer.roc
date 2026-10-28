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
# Khmer syllable and reorder phases adapted from HarfBuzz 14.6.0.
# hb-ot-shaper-indic.cc, hb-ot-shaper-indic.hh.

import ShaperTags
import ShaperNormalize
import ShaperIndicData
import ShaperIndic
import ShaperKhmerMachine
import LayoutGsub

## Khmer shaping phases from HarfBuzz14.6.0. Categories are shared pinned
## Indic shaping data; syllables and visual reordering follow Khmer's own
## state machine and feature ordering.
ShaperKhmer := { masks : ShaperKhmer.Masks }.{
	Masks : { pref : U64, blwf : U64, abvf : U64, pstf : U64, cfar : U64 }
	Feature : ShaperIndic.Feature
	Event : [SetupSyllables, Reorder, ClearSyllables]
	Context : ShaperIndic.Context
	make = |facts| ShaperKhmer.{ masks: facts.masks }

	pauses : List({ stage : U64, event : Event })
	pauses = [{ stage: 2, event: SetupSyllables }, { stage: 2, event: Reorder }, { stage: 3, event: ClearSyllables }]
	features : List(Feature)
	features = {
		var $features = List.with_capacity(11)
		for name in ["locl", "ccmp", "pref", "blwf", "abvf", "pstf", "cfar", "pres", "abvs", "blws", "psts"] {
			tag = ShaperTags.tag_of(name)
			early = name == "locl" or name == "ccmp"
			basic = name == "pref" or name == "blwf" or name == "abvf" or name == "pstf" or name == "cfar"
			$features = $features.append({
				tag,
				stage: if early or basic {
					2
				} else {
					3
				},
				default: 1,
				global: !basic,
				manual_zwj: !early,
				manual_zwnj: !early,
				per_syllable: early or basic,
			})
		}
		$features
	}
	stage : U64 -> U64
	stage = |tag| {
		if tag == ShaperTags.tag_of("rvrn") {
			0
		}
		else if tag == ShaperTags.tag_of("ltra") or tag == ShaperTags.tag_of("ltrm") or tag == ShaperTags.tag_of("rtla") or tag == ShaperTags.tag_of("rtlm") or tag == ShaperTags.tag_of("frac") or tag == ShaperTags.tag_of("numr") or tag == ShaperTags.tag_of("dnom") or tag == ShaperTags.tag_of("rand") or tag == ShaperTags.tag_of("Harf") {
			1
		}
		else if tag == ShaperTags.tag_of("locl") or tag == ShaperTags.tag_of("ccmp") or tag == ShaperTags.tag_of("pref") or tag == ShaperTags.tag_of("blwf") or tag == ShaperTags.tag_of("abvf") or tag == ShaperTags.tag_of("pstf") or tag == ShaperTags.tag_of("cfar") {
			2
		}
		else {
			3
		}
	}
	setup : List(ShaperNormalize.Char) -> List(ShaperNormalize.Char)
	setup = |chars| {
		var $chars = chars
		for i in 0..<$chars.len() {
			ch = $chars.get(i) ?? ShaperNormalize.no_char
			property = ShaperIndicData.get(ch.cp)
			$chars = $chars.set(i, { ..ch, mask: ShaperIndic.set_category(ch.mask, property.category) }) ?? []
		}
		$chars
	}
	pause : ShaperKhmer, Event, LayoutGsub, List(LayoutGsub.Item), Context -> { items : List(LayoutGsub.Item), operations : U64, stopped : U64 }
	pause = |plan, event, _shape, items, context| {
		match event {
			SetupSyllables => ShaperKhmerMachine.run(items, context.budget)
			Reorder => ShaperKhmer.reorder(plan, items, context)
			ClearSyllables => { items: ShaperIndic.clear_syllables(items), operations: 0, stopped: 0 }
		}
	}

	# Broken Khmer clusters have kind1. The font's dotted circle is
	# inserted at the syllable start; there is no encoded Repha skip.
	dotted_circles : ShaperIndic.Work, ShaperIndic.Dotted, U64 -> ShaperIndic.Work
	dotted_circles = |work, dotted, limit| {
		match dotted {
			Absent => work
			Present(dot) => {
				var $work = work
				var $count = 0
				var $last = 0
				for item in $work.items {
					$work = ShaperIndic.charge($work, 1)
					syllable_id = ShaperIndic.syllable(item.mask)
					if syllable_id != $last and syllable_id.bitwise_and(15) == 1 {
						$count = $count + 1
					}
					$last = syllable_id
				}
				if $work.stopped != 0 or $count == 0 {
					$work
				}
				else if $work.items.len() > limit or $count > limit - $work.items.len() {
					{ ..$work, stopped: 1 }
				}
				else if $work.items.len() + $count > $work.budget - $work.operations {
					{ ..$work, stopped: 2 }
				}
				else {
					{ items, operations: before_ops, stopped, budget } = $work
					operations = before_ops + items.len() + $count
					var $out = List.with_capacity(items.len() + $count)
					var $last_id = 0
					for item in items {
						syllable_id = ShaperIndic.syllable(item.mask)
						if syllable_id != $last_id and syllable_id.bitwise_and(15) == 1 {
							mask = ShaperIndic.set_position(ShaperIndic.set_category(item.mask, 11), 0)
							inserted = LayoutGsub.with_origin({ glyph: dot.glyph, cluster: item.cluster, mask, props: dot.props }, LayoutGsub.origin_inserted, 0, 0)
							$out = $out.append(inserted)
						}
						$last_id = syllable_id
						$out = $out.append(item)
					}
					{ items: $out, operations, stopped, budget }
				}
			}
		}
	}

	reorder_syllable : ShaperKhmer, ShaperIndic.Work, U64, U64 -> ShaperIndic.Work
	reorder_syllable = |plan, work, start, end| {
		var $work = work
		post_mask = plan.masks.blwf.bitwise_or(plan.masks.abvf).bitwise_or(plan.masks.pstf)
		for i in (start + 1)..<end {
			item = ShaperIndic.at($work.items, i)
			$work = ShaperIndic.put($work, i, { ..item, mask: item.mask.bitwise_or(post_mask) })
		}
		var $coengs = 0
		var $i = start + 1
		while $i < end and $work.stopped == 0 {
			$work = ShaperIndic.charge($work, 1)
			category = ShaperIndic.cat(ShaperIndic.at($work.items, $i))
			if category == 4 and $coengs <= 2 and $i + 1 < end {
				$coengs = $coengs + 1
				if ShaperIndic.cat(ShaperIndic.at($work.items, $i + 1)) == 15 {
					for j in $i..<$i + 2 {
						item = ShaperIndic.at($work.items, j)
						$work = ShaperIndic.put($work, j, { ..item, mask: item.mask.bitwise_or(plan.masks.pref) })
					}
					$work = ShaperIndic.merge($work, start, $i + 2)
					$work = ShaperIndic.move($work, $i, start)
					$work = ShaperIndic.move($work, $i + 1, start + 1)
					if plan.masks.cfar != 0 {
						for j in ($i + 2)..<end {
							item = ShaperIndic.at($work.items, j)
							$work = ShaperIndic.put($work, j, { ..item, mask: item.mask.bitwise_or(plan.masks.cfar) })
						}
					}
					$coengs = 2
				}
			} else if category == 22 {
				$work = ShaperIndic.merge($work, start, $i + 1)
				$work = ShaperIndic.move($work, $i, start)
			}
			$i = $i + 1
		}
		$work
	}

	reorder : ShaperKhmer, List(LayoutGsub.Item), Context -> { items : List(LayoutGsub.Item), operations : U64, stopped : U64 }
	reorder = |plan, items, context| {
		var $work = ShaperKhmer.dotted_circles({ items, operations: 0, stopped: 0, budget: context.budget }, context.dotted_circle, context.limit)
		var $start = 0
		while $start < $work.items.len() and $work.stopped == 0 {
			syllable_id = ShaperIndic.syllable(ShaperIndic.at($work.items, $start).mask)
			var $end = $start + 1
			while $end < $work.items.len() and $end - $start < 64 and ShaperIndic.syllable(ShaperIndic.at($work.items, $end).mask) == syllable_id and $work.stopped == 0 {
				$work = ShaperIndic.charge($work, 1)
				$end = $end + 1
			}
			if syllable_id.bitwise_and(15) <= 1 {
				$work = ShaperKhmer.reorder_syllable(plan, $work, $start, $end)
			}
			$start = $end
		}
		{ items: $work.items, operations: $work.operations, stopped: $work.stopped }
	}
}
