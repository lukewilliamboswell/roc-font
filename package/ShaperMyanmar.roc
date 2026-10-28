# HarfBuzz is licensed under the so - called "Old MIT" license.  Details follow.
# For parts of HarfBuzz that are licensed under different licenses see individual
# files names COPYING in subdirectories where applicable.
#
# Copyright © 2010 - 2022  Google, Inc.
# Copyright © 2015 - 2020  Ebrahim Byagowi
# Copyright © 2019,2020  Facebook, Inc.
# Copyright © 2012,2015  Mozilla Foundation
# Copyright © 2011  Codethink Limited
# Copyright © 2008,2010  Nokia Corporation and/or its subsidiary(-ies)
# Copyright © 2009  Keith Stribley
# Copyright © 2011  Martin Hosken and SIL International
# Copyright © 2007  Chris Wilson
# Copyright © 2005,2006,2020,2021,2022,2023  Behdad Esfahbod
# Copyright © 2004,2007,2008,2009,2010,2013,2021,2022,2023  Red Hat, Inc.
# Copyright © 1998 - 2005  David Turner and Werner Lemberg
# Copyright © 2016  Igalia S.L.
# Copyright © 2022  Matthias Clasen
# Copyright © 2018,2021  Khaled Hosny
# Copyright © 2018,2019,2020  Adobe, Inc
# Copyright © 2013 - 2015  Alexei Podtelezhnikov
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
# Myanmar reordering adapted from HarfBuzz 14.6.0.
# hb - ot - shaper - myanmar - machine.hh, hb - ot - shaper - myanmar - machine.rl.

import ShaperTags
import ShaperNormalize
import ShaperIndicData
import ShaperIndic
import ShaperMyanmarMachine
import LayoutGsub

## Myanmar syllables, kinzi/base selection and visual reordering from
## HarfBuzz14.6.0. The orchestrator chooses this model only for the modern
## Myanmar script tag (mym2), compiles its stages and owns GSUB sessions.
ShaperMyanmar := {}.{
	Feature : ShaperIndic.Feature
	Event : [SetupSyllables, Reorder, ClearSyllables]
	Context : ShaperIndic.Context
	make : {} -> ShaperMyanmar
	make = |_facts| ShaperMyanmar.{}
	pauses : List({ stage : U64, event : Event })
	pauses = [{ stage: 2, event: SetupSyllables }, { stage: 3, event: Reorder }, { stage: 7, event: ClearSyllables }]
	features : List(Feature)
	features = {
		var $out = List.with_capacity(10)
		for name in ["locl", "ccmp", "rphf", "pref", "blwf", "pstf", "pres", "abvs", "blws", "psts"] {
			tag = ShaperTags.tag_of(name)
			early = name == "locl" or name == "ccmp"
			basic = name == "rphf" or name == "pref" or name == "blwf" or name == "pstf"
			$out = $out.append({ tag, stage: ShaperMyanmar.stage(tag), default: 1, global: True, manual_zwj: !early, manual_zwnj: False, per_syllable: early or basic })
		}
		$out
	}
	stage : U64 -> U64
	stage = |tag| match tag {
		0x7276726E => 0 # rvrn
		0x6C6F636C | 0x63636D70 => 2 # locl,ccmp
		0x72706866 => 3 # rphf
		0x70726566 => 4 # pref
		0x626C7766 => 5 # blwf
		0x70737466 => 6 # pstf
		0x6C747261 | 0x6C74726D | 0x72746C61 | 0x72746C6D | 0x66726163 | 0x6E756D72 | 0x646E6F6D | 0x72616E64 | 0x48617266 => 1
		_ => 7
	}
	setup : List(ShaperNormalize.Char) -> List(ShaperNormalize.Char)
	setup = |chars| {
		var $chars = chars
		for i in 0..<$chars.len() {
			ch = $chars.get(i) ?? ShaperNormalize.no_char
			category = ShaperIndicData.get(ch.cp).category
			$chars = $chars.set(i, { ..ch, mask: ShaperIndic.set_category(ch.mask, category) }) ?? []
		}
		$chars
	}
	pause : ShaperMyanmar, Event, LayoutGsub, List(LayoutGsub.Item), Context -> { items : List(LayoutGsub.Item), operations : U64, stopped : U64 }
	pause = |_plan, event, _shape, items, context| match event {
		SetupSyllables => ShaperMyanmarMachine.run(items, context.budget)
		Reorder => ShaperMyanmar.reorder(items, context)
		ClearSyllables => { items: ShaperIndic.clear_syllables(items), operations: 0, stopped: 0 }
	}
	consonant : LayoutGsub.Item -> Bool
	consonant = |item| {
		category = ShaperIndic.cat(item)
		!ShaperIndic.ligated(item) and (category == 1 or category == 18 or category == 15 or category == 2 or category == 10 or category == 11)
	}
	# Broken clusters (kind1) receive the caller's real dotted - circle glyph.
	# No encoded Repha is skipped, unlike the Indic insertion helper.
	dotted_circles : ShaperIndic.Work, ShaperIndic.Dotted, U64 -> ShaperIndic.Work
	dotted_circles = |work, dotted, limit| match dotted {
		Absent => work
		Present(dot) => {
			var $work = work
			var $count = 0
			var $last = 0
			for item in $work.items {
				$work = ShaperIndic.charge($work, 1)
				if $work.stopped != 0 {
					return $work
				}
				id = ShaperIndic.syllable(item.mask)
				if id != $last and id.bitwise_and(15) == 1 {
					$count = $count + 1
					$last = id
				}
			}
			if $work.stopped != 0 or $count == 0 {
				return $work
			}
			if $work.items.len() > limit or $count > limit - $work.items.len() {
				return { ..$work, stopped: 1 }
			}

			$work = ShaperIndic.charge($work, $work.items.len() + $count)
			if $work.stopped != 0 {
				return $work
			}
			{ items, operations, stopped, budget } = $work
			var $out = List.with_capacity(items.len() + $count)
			var $previous = 0
			for item in items {
				id = ShaperIndic.syllable(item.mask)
				if id != $previous and id.bitwise_and(15) == 1 {
					mask = ShaperIndic.set_position(ShaperIndic.set_category(item.mask, 11), 0)
					inserted = LayoutGsub.with_origin({ glyph: dot.glyph, cluster: item.cluster, mask, props: dot.props }, LayoutGsub.origin_inserted, 0, 0)
					$out = $out.append(inserted)
					$previous = id
				}
				$out = $out.append(item)
			}
			{ items: $out, operations, stopped, budget }
		}
	}

	# Stable counting sort over the finite visual - position alphabet. The
	# smallest permutation - closed intervals are exactly the overlapping
	# ranges merged by HarfBuzz's stable insertion sort. Merge those ranges
	# before applying the permutation, including equal - cluster neighbours.
	# Flat origins/ranks avoid temporary 8 - bit provenance and length limits.
	sort : ShaperIndic.Work, U64, U64 -> ShaperIndic.Work
	sort = |work, start, end| {
		if end <= start + 1 or work.stopped != 0 {
			return work
		}
		var $work = work
		n = end - start
		var $buckets = List.repeat({ count: 0.U64, cursor: 0.U64 }, 15)
		for i in start..<end {
			$work = ShaperIndic.charge($work, 1)
			pos = ShaperIndic.pos(ShaperIndic.at($work.items, i))
			bucket = $buckets.get(pos) ?? { count: 0, cursor: 0 }
			$buckets = $buckets.set(pos, { ..bucket, count: bucket.count + 1 }) ?? []
		}
		var $cursor = 0
		for i in 0..<15 {
			bucket = $buckets.get(i) ?? { count: 0, cursor: 0 }
			$buckets = $buckets.set(i, { ..bucket, cursor: $cursor }) ?? []
			$cursor = $cursor + bucket.count
		}
		if $work.stopped != 0 {
			return $work
		}
		var $origins = List.repeat(0.U64, n)
		var $ranks = List.repeat(0.U64, n)
		for i in start..<end {
			$work = ShaperIndic.charge($work, 1)
			pos = ShaperIndic.pos(ShaperIndic.at($work.items, i))
			bucket = $buckets.get(pos) ?? { count: 0, cursor: 0 }
			$origins = $origins.set(bucket.cursor, i) ?? []
			$ranks = $ranks.set(i - start, bucket.cursor) ?? []
			$buckets = $buckets.set(pos, { ..bucket, cursor: bucket.cursor + 1 }) ?? []
		}
		var $far = 0
		var $first = start
		for i in 0..<n {
			$work = ShaperIndic.charge($work, 1)
			$far = $far.max($ranks.get(i) ?? 0)
			if $far == i {
				if start + i + 1 > $first + 1 {
					$work = ShaperIndic.merge($work, $first, start + i + 1)
				}
				$first = start + i + 1
			}
		}
		if $work.stopped != 0 {
			return $work
		}
		var $sorted = List.with_capacity(n)
		for i in $origins {
			$work = ShaperIndic.charge($work, 1)
			$sorted = $sorted.append(ShaperIndic.at($work.items, i))
		}

		# Reserve the complete replacement before touching glyph order;
		# an exhausted budget must never leave half a permutation.
		$work = ShaperIndic.charge($work, n)
		if $work.stopped != 0 {
			return $work
		}
		{ items, operations, stopped, budget } = $work
		var $items = items
		for i in start..<end {
			$items = $items.set(i, ShaperIndic.at($sorted, i - start)) ?? []
		}
		{ items: $items, operations, stopped, budget }
	}

	reorder_syllable : ShaperIndic.Work, U64, U64 -> ShaperIndic.Work
	reorder_syllable = |work, start, end| {
		var $work = work
		kinzi = start + 3 <= end and ShaperIndic.cat(ShaperIndic.at($work.items, start)) == 15 and ShaperIndic.cat(ShaperIndic.at($work.items, start + 1)) == 32 and ShaperIndic.cat(ShaperIndic.at($work.items, start + 2)) == 4
		limit = start + (if (kinzi) 3 else 0)
		var $base = start
		var $found = False
		var $search = limit
		while $search < end and !$found and $work.stopped == 0 {
			$work = ShaperIndic.charge($work, 1)
			if ShaperMyanmar.consonant(ShaperIndic.at($work.items, $search)) {
				$base = $search
				$found = True
			}
			$search = $search + 1
		}
		var $i = start
		while $i < limit and $work.stopped == 0 {
			item = ShaperIndic.at($work.items, $i)
			$work = ShaperIndic.put($work, $i, ShaperIndic.with_pos(item, 5))
			$i = $i + 1
		}
		while $i < $base and $work.stopped == 0 {
			item = ShaperIndic.at($work.items, $i)
			$work = ShaperIndic.put($work, $i, ShaperIndic.with_pos(item, 3))
			$i = $i + 1
		}
		if $i < end {
			item = ShaperIndic.at($work.items, $i)
			$work = ShaperIndic.put($work, $i, ShaperIndic.with_pos(item, 4))
			$i = $i + 1
		}
		var $position = 5
		while $i < end and $work.stopped == 0 {
			item = ShaperIndic.at($work.items, $i)
			category = ShaperIndic.cat(item)
			pos = if category == 36 {
				3
			}
			else if category == 22 {
				2
			}
			else if category == 40 {
				ShaperIndic.pos(ShaperIndic.at($work.items, $i - 1))
			}
			else if $position == 5 and category == 21 {
				$position = 8
				$position
			}
			else if $position == 8 and category == 9 {
				7
			}
			else if $position == 8 and category == 21 {
				$position
			}
			else if $position == 8 and category != 9 {
				$position = 9
				$position
			}
			else {
				$position
			}
			$work = ShaperIndic.put($work, $i, ShaperIndic.with_pos(item, pos))
			$i = $i + 1
		}
		$work = ShaperMyanmar.sort($work, start, end)
		var $first = end
		var $last = end
		for i in start..<end {
			$work = ShaperIndic.charge($work, 1)
			if ShaperIndic.pos(ShaperIndic.at($work.items, i)) == 2 {
				if $first == end {
					$first = i
				}
				$last = i
			}
		}
		if $first < $last {
			$work = ShaperIndic.reverse($work, $first, $last + 1)
			var $group = $first
			for i in $first..<$last + 1 {
				$work = ShaperIndic.charge($work, 1)
				if ShaperIndic.cat(ShaperIndic.at($work.items, i)) == 22 {
					$work = ShaperIndic.reverse($work, $group, i + 1)
					$group = i + 1
				}
			}
		}
		$work
	}
	reorder : List(LayoutGsub.Item), Context -> { items : List(LayoutGsub.Item), operations : U64, stopped : U64 }
	reorder = |items, context| {
		var $work = ShaperMyanmar.dotted_circles({ items, operations: 0, stopped: 0, budget: context.budget }, context.dotted_circle, context.limit)
		var $start = 0
		while $start < $work.items.len() and $work.stopped == 0 {
			id = ShaperIndic.syllable(ShaperIndic.at($work.items, $start).mask)
			var $end = $start + 1
			while $end < $work.items.len() and $end - $start < 64 and ShaperIndic.syllable(ShaperIndic.at($work.items, $end).mask) == id and $work.stopped == 0 {
				$work = ShaperIndic.charge($work, 1)
				$end = $end + 1
			}
			if id.bitwise_and(15) <= 1 {
				$work = ShaperMyanmar.reorder_syllable($work, $start, $end)
			}
			$start = $end
		}
		{ items: $work.items, operations: $work.operations, stopped: $work.stopped }
	}
}

# This independent slow reference is HarfBuzz's buffer insertion sort,
# including cluster merges before each move. Only the private linear
# permutation algorithm uses it as an oracle; it is never called in use.
myanmar_reference_sort : List(LayoutGsub.Item) -> List(LayoutGsub.Item)
myanmar_reference_sort = |items| {
	var $work = { items, operations: 0, stopped: 0, budget: 1000000 }
	for i in 1..<items.len() {
		item = ShaperIndic.at($work.items, i)
		var $j = i
		while $j > 0 and ShaperIndic.pos(ShaperIndic.at($work.items, $j - 1)) > ShaperIndic.pos(item) {
			$j = $j - 1
		}
		if $j != i {
			$work = ShaperIndic.merge($work, $j, i + 1)
			$work = ShaperIndic.move($work, i, $j)
		}
	}
	$work.items
}

expect {
	# Exhaust every ternary position permutation at six items and four
	# monotone cluster patterns, including shared clusters and unsafe flags.
	var $same = True
	for encoded in 0.U64..<729 {
		for group in 1.U64..=4 {
			var $items = List.with_capacity(6)
			var $code = encoded
			for i in 0.U64..<6 {
				mask = ShaperIndic.set_position((i % 2).shl_wrap(63), [2, 4, 8].get($code % 3) ?? 2)
				$code = $code // 3
				$items = $items.append({ glyph: i + 1, cluster: i // group, mask, props: 0 })
			}
			result = ShaperMyanmar.sort({ items: $items, operations: 0, stopped: 0, budget: 1000000 }, 0, 6)
			if result.stopped != 0 or result.items != myanmar_reference_sort($items) {
				$same = False
			}
		}
	}
	$same
}
expect {
	# Below vowel -> anusvara -> trailing marks use distinct visual classes;
	# medial Ra and pre-vowel precede the base, preserving source clusters.
	categories = [1.U64, 21, 9, 20, 36, 22]
	items = categories.map_with_index(|category, i| { ..LayoutGsub.no_item, glyph: i + 1, cluster: i, mask: ShaperIndic.set_syllable(ShaperIndic.set_category(0, category), 16) })
	result = ShaperMyanmar.reorder_syllable({ items, operations: 0, stopped: 0, budget: 100000 }, 0, 6)
	result.stopped == 0 and result.items.map(|item| item.glyph) == [6, 5, 1, 3, 2, 4] and result.items.all(|item| item.cluster == 0)
}
expect {
	# VS follows its pre-vowel when the left-matra groups reverse.
	categories = [1.U64, 22, 40, 22, 40]
	items = categories.map_with_index(|category, i| { ..LayoutGsub.no_item, glyph: i + 1, cluster: 0, mask: ShaperIndic.set_syllable(ShaperIndic.set_category(0, category), 16) })
	result = ShaperMyanmar.reorder_syllable({ items, operations: 0, stopped: 0, budget: 100000 }, 0, 5)
	result.stopped == 0 and result.items.map(|item| item.glyph) == [4, 5, 2, 3, 1]
}

## fuzz regression: HarfBuzz's foreach_syllable visits at most64glyphs.
## The DFA serial remains one, so long left-vowel runs reorder in chunks
## and the original base lands atindex63 rather than at the far edge.
expect {
	items = [1.U64].concat(List.repeat(22, 256)).map_with_index(|category, i| { glyph: i + 1, cluster: i, mask: ShaperIndic.set_syllable(ShaperIndic.set_category(0, category), 16), props: 0 })
	result = ShaperMyanmar.reorder(items, { dotted_circle: Absent, limit: 1000, budget: 100000 })
	result.stopped == 0 and (result.items.get(63) ?? LayoutGsub.no_item).glyph == 1 and result.items.len() == 257
}

## fuzz regression: dotted insertion remembers the last inserted broken
## serial, including across intervening ordinary syllables and serialwrap.
## Its counting pass must use exactly the same rule as output/growth.
expect {
	first = { ..LayoutGsub.no_item, glyph: 1, mask: ShaperIndic.set_syllable(0, 17) }
	middle = List.repeat(LayoutGsub.no_item, 14).map_with_index(|item, i| { ..item, glyph: 2, mask: ShaperIndic.set_syllable(0, (i + 2) * 16 + 2) })
	items = [first].concat(middle).append(first)
	result = ShaperMyanmar.dotted_circles({ items, operations: 0, stopped: 0, budget: 1000 }, Present({ glyph: 99, props: 0 }), 17)
	result.stopped == 0 and result.items.len() == 17 and result.items.keep_if(|item| item.glyph == 99).len() == 1
}

## fuzz regression: budget exhaustion cannot leave a partly copied
## permutation with a duplicated glyph and another original glyph lost.
expect {
	items = [{ ..LayoutGsub.no_item, glyph: 1, mask: ShaperIndic.set_position(0, 4) }, { ..LayoutGsub.no_item, glyph: 2, mask: ShaperIndic.set_position(0, 2) }]
	var $valid = True
	for budget in 0.U64..=40 {
		result = ShaperMyanmar.sort({ items, operations: 0, stopped: 0, budget }, 0, 2)
		if result.items.len() != 2 or !result.items.any(|item| item.glyph == 1) or !result.items.any(|item| item.glyph == 2) {
			$valid = False
		}
	}
	$valid
}
