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

import ShaperTags
import ShaperNormalize
import ShaperIndicData
import ShaperIndicMachine
import LayoutGsub

## Prepared Indic script facts. The orchestrator owns font selection and
## feature lookup compilation; this module owns syllables and reordering.
ShaperIndic := {
	script : U64,
	old_spec : Bool,
	virama_glyph : U64,
	masks : ShaperIndic.Masks,
	probe_lookups : List(U64),
	probe_spans : List({ start : U64, end : U64 }),
}.{
	Masks : { rphf : U64, pref : U64, blwf : U64, abvf : U64, half : U64, pstf : U64, init : U64 }
	Feature : { tag : U64, stage : U64, default : U64, global : Bool, manual_zwj : Bool, manual_zwnj : Bool, per_syllable : Bool }
	Event : [SetupSyllables, InitialReorder, FinalReorder, ClearSyllables]

	make = |facts| ShaperIndic.{ script: facts.script, old_spec: facts.old_spec, virama_glyph: facts.virama_glyph, masks: facts.masks, probe_lookups: facts.probe_lookups, probe_spans: facts.probe_spans }

	pauses : List({ stage : U64, event : Event })
	pauses = [
		{ stage: 2, event: SetupSyllables },
		{ stage: 3, event: InitialReorder },
		{ stage: 14, event: FinalReorder },
		{ stage: 15, event: ClearSyllables },
	]

	features : List(Feature)
	features = {
		names = ["nukt", "akhn", "rphf", "rkrf", "pref", "blwf", "abvf", "half", "pstf", "vatu", "cjct", "init", "pres", "abvs", "blws", "psts", "haln"]
		var $out = List.with_capacity(names.len())
		for name in names {
			tag = ShaperTags.tag_of(name)
			global = name != "rphf" and name != "pref" and name != "blwf" and name != "abvf" and name != "half" and name != "pstf" and name != "init"
			$out = $out.append({ tag, stage: ShaperIndic.stage(tag), default: 1, global, manual_zwj: True, manual_zwnj: True, per_syllable: True })
		}
		$out
	}

	stage : U64 -> U64
	stage = |tag| {
		basic = ["nukt", "akhn", "rphf", "rkrf", "pref", "blwf", "abvf", "half", "pstf", "vatu", "cjct"]
		var $stage = 14
		var $i = 0
		for name in basic {
			if tag == ShaperTags.tag_of(name) {
				$stage = $i + 3
			}
			$i = $i + 1
		}
		if tag == ShaperTags.tag_of("rvrn") {
			0
		}
		else if tag == ShaperTags.tag_of("locl") or tag == ShaperTags.tag_of("ccmp") {
			2
		}
		else if tag == ShaperTags.tag_of("ltra") or tag == ShaperTags.tag_of("ltrm") or tag == ShaperTags.tag_of("rtla") or tag == ShaperTags.tag_of("rtlm") or tag == ShaperTags.tag_of("frac") or tag == ShaperTags.tag_of("numr") or tag == ShaperTags.tag_of("dnom") or tag == ShaperTags.tag_of("rand") or tag == ShaperTags.tag_of("Harf") {
			1
		}
		else {
			$stage
		}
	}

	## Save shaping properties after normalization, before mapping drops cp.
	setup : List(ShaperNormalize.Char) -> List(ShaperNormalize.Char)
	setup = |chars| {
		var $chars = chars
		for i in 0..<$chars.len() {
			ch = $chars.get(i) ?? ShaperNormalize.no_char
			property = ShaperIndicData.get(ch.cp)
			mask = ShaperIndic.set_category(ShaperIndic.set_position(ch.mask, property.position), property.category)
			$chars = $chars.set(i, { ..ch, mask }) ?? []
		}
		$chars
	}

	setup_syllables : List(LayoutGsub.Item), U64 -> { items : List(LayoutGsub.Item), operations : U64, stopped : U64 }
	setup_syllables = ShaperIndicMachine.run

	clear_syllables : List(LayoutGsub.Item) -> List(LayoutGsub.Item)
	clear_syllables = |items| {
		var $items = items
		for i in 0..<$items.len() {
			item = $items.get(i) ?? LayoutGsub.no_item
			$items = $items.set(i, { ..item, mask: ShaperIndic.set_syllable(item.mask, 0) }) ?? []
		}
		$items
	}

	# Bits 39..44 category, 45..48 visual position, 49..56 syllable.
	# These fields survive substitution; component provenance uses 32..38.
	category : U64 -> U64
	category = |mask| mask.shr_zf_wrap(39).bitwise_and(63)
	position : U64 -> U64
	position = |mask| mask.shr_zf_wrap(45).bitwise_and(15)
	syllable : U64 -> U64
	syllable = |mask| mask.shr_zf_wrap(49).bitwise_and(255)
	set_category : U64, U64 -> U64
	set_category = |mask, value| mask.bitwise_and(0xFFFFE07FFFFFFFFF).bitwise_or(value.bitwise_and(63).shl_wrap(39))
	set_position : U64, U64 -> U64
	set_position = |mask, value| mask.bitwise_and(0xFFFE1FFFFFFFFFFF).bitwise_or(value.bitwise_and(15).shl_wrap(45))
	set_syllable : U64, U64 -> U64
	set_syllable = |mask, value| mask.bitwise_and(0xFE01FFFFFFFFFFFF).bitwise_or(value.bitwise_and(255).shl_wrap(49))
	Context : { dotted_circle : Dotted, limit : U64, budget : U64 }
	pause : ShaperIndic, Event, LayoutGsub, List(LayoutGsub.Item), Context -> { items : List(LayoutGsub.Item), operations : U64, stopped : U64 }
	pause = |plan, event, shape, items, context| {
		match event {
			SetupSyllables => ShaperIndic.setup_syllables(items, context.budget)
			InitialReorder => {
				oracle = |feature, glyphs, budget| {
					span = plan.probe_spans.get(feature) ?? { start: 0, end: 0 }
					indices = plan.probe_lookups.sublist({ start: span.start, len: span.end - span.start })
					zero_context = !plan.old_spec and plan.script != ShaperTags.tag_of("Mlym")
					LayoutGsub.would_substitute(shape, indices, glyphs, zero_context, budget)
				}
				ShaperIndic.initial(plan, items, oracle, context.dotted_circle, context.limit, context.budget)
			}
			FinalReorder => ShaperIndic.final_reorder(plan, items, context.budget)
			ClearSyllables => { items: ShaperIndic.clear_syllables(items), operations: 0, stopped: 0 }
		}
	}

	virama : U64 -> U64
	virama = |script| {
		if script == ShaperTags.tag_of("Deva") {
			0x094D
		}
		else if script == ShaperTags.tag_of("Beng") {
			0x09CD
		}
		else if script == ShaperTags.tag_of("Guru") {
			0x0A4D
		}
		else if script == ShaperTags.tag_of("Gujr") {
			0x0ACD
		}
		else if script == ShaperTags.tag_of("Orya") {
			0x0B4D
		}
		else if script == ShaperTags.tag_of("Taml") {
			0x0BCD
		}
		else if script == ShaperTags.tag_of("Telu") {
			0x0C4D
		}
		else if script == ShaperTags.tag_of("Knda") {
			0x0CCD
		}
		else if script == ShaperTags.tag_of("Mlym") {
			0x0D4D
		}
		else {
			0
		}
	}

	Work : { items : List(LayoutGsub.Item), operations : U64, stopped : U64, budget : U64 }
	Probe : U64, List(U64), U64 -> { matches : Bool, operations : U64, stopped : U64 }
	Config : { reph_pos : U64, reph_mode : U64, post_only : Bool }

	config : U64 -> Config
	config = |script| {
		if script == ShaperTags.tag_of("Beng") {
			{ reph_pos: 9, reph_mode: 0, post_only: False }
		}
		else if script == ShaperTags.tag_of("Guru") {
			{ reph_pos: 7, reph_mode: 0, post_only: False }
		}
		else if script == ShaperTags.tag_of("Orya") {
			{ reph_pos: 5, reph_mode: 0, post_only: False }
		}
		else if script == ShaperTags.tag_of("Taml") {
			{ reph_pos: 12, reph_mode: 0, post_only: False }
		}
		else if script == ShaperTags.tag_of("Telu") {
			{ reph_pos: 12, reph_mode: 1, post_only: True }
		}
		else if script == ShaperTags.tag_of("Knda") {
			{ reph_pos: 12, reph_mode: 0, post_only: True }
		}
		else if script == ShaperTags.tag_of("Mlym") {
			{ reph_pos: 5, reph_mode: 2, post_only: False }
		}
		else {
			{ reph_pos: 10, reph_mode: 0, post_only: False }
		}
	}

	at : List(LayoutGsub.Item), U64 -> LayoutGsub.Item
	at = |items, i| items.get(i) ?? LayoutGsub.no_item
	cat : LayoutGsub.Item -> U64
	cat = |item| ShaperIndic.category(item.mask)
	pos : LayoutGsub.Item -> U64
	pos = |item| ShaperIndic.position(item.mask)
	with_pos : LayoutGsub.Item, U64 -> LayoutGsub.Item
	with_pos = |item, pos_value| { ..item, mask: ShaperIndic.set_position(item.mask, pos_value) }
	ligated : LayoutGsub.Item -> Bool
	ligated = |item| item.props.shr_zf_wrap(16).bitwise_and(0x20) != 0
	ligated_single : LayoutGsub.Item -> Bool
	ligated_single = |item| item.props.shr_zf_wrap(16).bitwise_and(0x60) == 0x20
	consonant : LayoutGsub.Item -> Bool
	consonant = |item| {
		c = ShaperIndic.cat(item)
		!ShaperIndic.ligated(item) and (c == 1 or c == 18 or c == 15 or c == 16 or c == 2 or c == 10 or c == 11)
	}
	joiner : LayoutGsub.Item -> Bool
	joiner = |item| !ShaperIndic.ligated(item) and (ShaperIndic.cat(item) == 5 or ShaperIndic.cat(item) == 6)
	halant : LayoutGsub.Item -> Bool
	halant = |item| !ShaperIndic.ligated(item) and ShaperIndic.cat(item) == 4
	matra : LayoutGsub.Item -> Bool
	matra = |item| !ShaperIndic.ligated(item) and (ShaperIndic.cat(item) == 7 or ShaperIndic.cat(item) == 13)

	charge : Work, U64 -> Work
	charge = |work, count| {
		if work.stopped != 0 {
			work
		}
		else if count > work.budget - work.operations {
			{ ..work, stopped: 2 }
		}
		else {
			{ ..work, operations: work.operations + count }
		}
	}
	put : Work, U64, LayoutGsub.Item -> Work
	put = |work, i, item| {
		{ items, operations, stopped, budget } = ShaperIndic.charge(work, 1)
		if stopped != 0 {
			{ items, operations, stopped, budget }
		}
		else {
			# Every caller establishes i < the unchanged item count.
			{ items: items.set(i, item) ?? [], operations, stopped, budget }
		}
	}
	move : Work, U64, U64 -> Work
	move = |work, from, to| {
		count = if from >= to {
			from - to + 1
		} else {
			to - from + 1
		}
		checked = ShaperIndic.charge(work, count)
		if checked.stopped != 0 {
			checked
		}
		else {
			{ items, operations, stopped, budget } = checked
			value = ShaperIndic.at(items, from)
			var $items = items
			var $i = from
			while $i < to {
				item = ShaperIndic.at($items, $i + 1)
				$items = $items.set($i, item) ?? []
				$i = $i + 1
			}
			while $i > to {
				item = ShaperIndic.at($items, $i - 1)
				$items = $items.set($i, item) ?? []
				$i = $i - 1
			}
			{ items: $items.set(to, value) ?? [], operations, stopped, budget }
		}
	}
	reverse : Work, U64, U64 -> Work
	reverse = |work, start, end| {
		checked = ShaperIndic.charge(work, (end - start) // 2 * 2)
		if checked.stopped != 0 {
			checked
		}
		else {
			{ items, operations, stopped, budget } = checked
			var $items = items
			var $i = start
			var $j = end
			while $i + 1 < $j {
				$j = $j - 1
				a = ShaperIndic.at($items, $i)
				b = ShaperIndic.at($items, $j)
				$items = $items.set($i, b) ?? []
				$items = $items.set($j, a) ?? []
				$i = $i + 1
			}
			{ items: $items, operations, stopped, budget }
		}
	}

	replace_span : Work, U64, List(LayoutGsub.Item), U64 -> Work
	replace_span = |work, start, replacement, count| {
		checked = ShaperIndic.charge(work, count)
		if checked.stopped != 0 {
			checked
		}
		else {
			{ items, operations, stopped, budget } = checked
			var $items = items
			for i in 0..<count {
				$items = $items.set(start + i, ShaperIndic.at(replacement, i)) ?? []
			}
			{ items: $items, operations, stopped, budget }
		}
	}

	# Input-only equivalent of HB merge_clusters, including equal-cluster
	# neighbours. Every visited item is charged; no caller-controlled scan
	# can consume unbounded work between GSUB stages.
	merge : Work, U64, U64 -> Work
	merge = |work, start, end| {
		if end <= start + 1 {
			work
		}
		else {
			var $work = work
			var $cluster = ShaperIndic.at($work.items, start).cluster
			var $i = start
			while $i < end and $work.stopped == 0 {
				$work = ShaperIndic.charge($work, 1)
				$cluster = $cluster.min(ShaperIndic.at($work.items, $i).cluster)
				$i = $i + 1
			}
			var $end = end
			if $cluster != ShaperIndic.at($work.items, $end - 1).cluster {
				while $end < $work.items.len() and ShaperIndic.at($work.items, $end - 1).cluster == ShaperIndic.at($work.items, $end).cluster and $work.stopped == 0 {
					$work = ShaperIndic.charge($work, 1)
					$end = $end + 1
				}
			}
			var $start = start
			if $cluster != ShaperIndic.at($work.items, $start).cluster {
				while $start > 0 and ShaperIndic.at($work.items, $start - 1).cluster == ShaperIndic.at($work.items, $start).cluster and $work.stopped == 0 {
					$work = ShaperIndic.charge($work, 1)
					$start = $start - 1
				}
			}
			checked = ShaperIndic.charge($work, $end - $start)
			if checked.stopped != 0 {
				checked
			}
			else {
				{ items, operations, stopped, budget } = checked
				var $items = items
				for j in $start..<$end {
					item = ShaperIndic.at($items, j)
					$items = $items.set(j, LayoutGsub.set_cluster(item, $cluster)) ?? []
				}
				{ items: $items, operations, stopped, budget }
			}
		}
	}

	probe : Work, Probe, U64, List(U64) -> { work : Work, matches : Bool }
	probe = |work, oracle, feature, glyphs| {
		if work.stopped != 0 {
			{ work, matches: False }
		}
		else {
			result = oracle(feature, glyphs, work.budget - work.operations)
			{ work: { ..work, operations: work.operations + result.operations, stopped: result.stopped }, matches: result.matches }
		}
	}

	Dotted : [Present({ glyph : U64, props : U64 }), Absent]
	dotted_circles : Work, Dotted, U64 -> Work
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
					if syllable_id != $last and syllable_id.bitwise_and(15) == 4 {
						$count = $count + 1
						$last = syllable_id
					}
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
					var $i = 0
					var $last_syllable = 0
					while $i < items.len() {
						item = ShaperIndic.at(items, $i)
						syllable_id = ShaperIndic.syllable(item.mask)
						if syllable_id != $last_syllable and syllable_id.bitwise_and(15) == 4 {
							$last_syllable = syllable_id
							mask = ShaperIndic.set_position(ShaperIndic.set_category(item.mask, 11), 14)
							while $i < items.len() and ShaperIndic.syllable(ShaperIndic.at(items, $i).mask) == syllable_id and ShaperIndic.cat(ShaperIndic.at(items, $i)) == 14 {
								$out = $out.append(ShaperIndic.at(items, $i))
								$i = $i + 1
							}
							inserted = LayoutGsub.with_origin({ glyph: dot.glyph, cluster: item.cluster, mask, props: dot.props }, LayoutGsub.origin_inserted, 0, 0)
							$out = $out.append(inserted)
						} else {
							$out = $out.append(item)
							$i = $i + 1
						}
					}
					{ items: $out, operations, stopped, budget }
				}
			}
		}
	}

	update_positions : ShaperIndic, Work, Probe -> Work
	update_positions = |plan, work, oracle| {
		if plan.virama_glyph == 0 {
			work
		}
		else {
			var $work = work
			var $i = 0
			while $i < $work.items.len() and $work.stopped == 0 {
				$work = ShaperIndic.charge($work, 1)
				item = ShaperIndic.at($work.items, $i)
				if ShaperIndic.pos(item) == 4 {
					var $pos_value = 4
					var $probe_index = 0
					front = [plan.virama_glyph, item.glyph]
					back = [item.glyph, plan.virama_glyph]
					while $probe_index < 8 and $pos_value == 4 and $work.stopped == 0 {
						feature = if $probe_index < 2 {
							2
						} else if $probe_index < 4 {
							4
						} else if $probe_index < 6 {
							3
						} else {
							1
						}
						glyphs = if $probe_index % 2 == 0 {
							front
						} else {
							back
						}
						result = ShaperIndic.probe($work, oracle, feature, glyphs)
						$work = result.work
						if result.matches {
							$pos_value = if $probe_index < 4 {
								8
							} else {
								11
							}
						}
						$probe_index = $probe_index + 1
					}
					$work = ShaperIndic.put($work, $i, ShaperIndic.with_pos(item, $pos_value))
				}
				$i = $i + 1
			}
			$work
		}
	}

	Scratch : { sorted : List(LayoutGsub.Item), buckets : List({ count : U64, cursor : U64 }) }

	initial_syllable : ShaperIndic, Work, U64, U64, Probe, Scratch -> { work : Work, scratch : Scratch }
	initial_syllable = |plan, work, start, end, oracle, scratch| {
		cfg = ShaperIndic.config(plan.script)
		var $work = work
		if plan.script == ShaperTags.tag_of("Knda") and end - start >= 3 and ShaperIndic.cat(ShaperIndic.at($work.items, start)) == 15 and ShaperIndic.cat(ShaperIndic.at($work.items, start + 1)) == 4 and ShaperIndic.cat(ShaperIndic.at($work.items, start + 2)) == 6 {
			$work = ShaperIndic.merge($work, start + 1, start + 3)
			$work = ShaperIndic.move($work, start + 1, start + 2)
		}
		var $base = end
		var $reph = False
		var $limit = start
		if plan.masks.rphf != 0 and end - start >= 3 and ((cfg.reph_mode == 0 and !ShaperIndic.joiner(ShaperIndic.at($work.items, start + 2))) or (cfg.reph_mode == 1 and ShaperIndic.cat(ShaperIndic.at($work.items, start + 2)) == 6)) {
			pair = [ShaperIndic.at($work.items, start).glyph, ShaperIndic.at($work.items, start + 1).glyph]
			result = ShaperIndic.probe($work, oracle, 0, pair)
			$work = result.work
			var $matches = result.matches
			if !$matches and cfg.reph_mode == 1 {
				triple = pair.append(ShaperIndic.at($work.items, start + 2).glyph)
				result3 = ShaperIndic.probe($work, oracle, 0, triple)
				$work = result3.work
				$matches = result3.matches
			}
			if $matches {
				$limit = start + 2
				while $limit < end and ShaperIndic.joiner(ShaperIndic.at($work.items, $limit)) and $work.stopped == 0 {
					$work = ShaperIndic.charge($work, 1)
					$limit = $limit + 1
				}
				$base = start
				$reph = True
			}
		} else if cfg.reph_mode == 2 and ShaperIndic.cat(ShaperIndic.at($work.items, start)) == 14 {
			$limit = start + 1
			while $limit < end and ShaperIndic.joiner(ShaperIndic.at($work.items, $limit)) and $work.stopped == 0 {
				$work = ShaperIndic.charge($work, 1)
				$limit = $limit + 1
			}
			$base = start
			$reph = True
		}
		var $base_i = end
		var $seen_below = False
		var $base_search = True
		while $base_i > $limit and $base_search and $work.stopped == 0 {
			$base_i = $base_i - 1
			$work = ShaperIndic.charge($work, 1)
			item = ShaperIndic.at($work.items, $base_i)
			if ShaperIndic.consonant(item) {
				pos_value = ShaperIndic.pos(item)
				$base = $base_i
				if pos_value != 8 and (pos_value != 11 or $seen_below) {
					$base_search = False
				}
				if pos_value == 8 {
					$seen_below = True
				}
			} else if $base_i > start and ShaperIndic.cat(item) == 6 and ShaperIndic.cat(ShaperIndic.at($work.items, $base_i - 1)) == 4 {
				$base_search = False
			}
		}
		if $reph and $base == start and $limit - $base <= 2 {
			$reph = False
		}
		for i in start..<$base {
			item = ShaperIndic.at($work.items, i)
			$work = ShaperIndic.put($work, i, ShaperIndic.with_pos(item, ShaperIndic.pos(item).min(3)))
		}
		if $base < end {
			$work = ShaperIndic.put($work, $base, ShaperIndic.with_pos(ShaperIndic.at($work.items, $base), 4))
		}
		if $reph {
			$work = ShaperIndic.put($work, start, ShaperIndic.with_pos(ShaperIndic.at($work.items, start), 1))
		}
		if plan.old_spec and $base < end {
			var $old_i = $base + 1
			var $found = False
			while $old_i < end and !$found and $work.stopped == 0 {
				$work = ShaperIndic.charge($work, 1)
				if ShaperIndic.cat(ShaperIndic.at($work.items, $old_i)) == 4 {
					$found = True
					var $j = end - 1
					var $old_search = True
					while $j > $old_i and $old_search and $work.stopped == 0 {
						$work = ShaperIndic.charge($work, 1)
						item = ShaperIndic.at($work.items, $j)
						if ShaperIndic.consonant(item) or (plan.script == ShaperTags.tag_of("Knda") and ShaperIndic.cat(item) == 4) {
							$old_search = False
						}
						else {
							$j = $j - 1
						}
					}
					if $j > $old_i and ShaperIndic.cat(ShaperIndic.at($work.items, $j)) != 4 {
						$work = ShaperIndic.move($work, $old_i, $j)
					}
				}
				$old_i = $old_i + 1
			}
		}
		var $last_position = 0
		for i in start..<end {
			item = ShaperIndic.at($work.items, i)
			cat_value = ShaperIndic.cat(item)
			if cat_value == 5 or cat_value == 6 or cat_value == 3 or cat_value == 12 or cat_value == 16 or cat_value == 4 {
				var $pos_value = $last_position
				if cat_value == 4 and $pos_value == 2 {
					var $j = i
					while $j > start and $pos_value == 2 and $work.stopped == 0 {
						$j = $j - 1
						$work = ShaperIndic.charge($work, 1)
						$pos_value = ShaperIndic.pos(ShaperIndic.at($work.items, $j))
					}
				}
				$work = ShaperIndic.put($work, i, ShaperIndic.with_pos(item, $pos_value))
			} else if ShaperIndic.pos(item) != 13 {
				if cat_value == 13 and i > start and ShaperIndic.cat(ShaperIndic.at($work.items, i - 1)) == 8 {
					$work = ShaperIndic.put($work, i - 1, ShaperIndic.with_pos(ShaperIndic.at($work.items, i - 1), ShaperIndic.pos(item)))
				}
				$last_position = ShaperIndic.pos(item)
			}
		}
		var $last = $base
		if $base < end {
			for i in ($base + 1)..<end {
				item = ShaperIndic.at($work.items, i)
				if ShaperIndic.consonant(item) {
					for j in ($last + 1)..<i {
						previous = ShaperIndic.at($work.items, j)
						if ShaperIndic.pos(previous) < 13 {
							$work = ShaperIndic.put($work, j, ShaperIndic.with_pos(previous, ShaperIndic.pos(item)))
						}
					}
					$last = i
				} else if ShaperIndic.cat(item) == 7 or ShaperIndic.cat(item) == 13 {
					$last = i
				}
			}
		}
		# Stable counting sort over the fifteen defined visual positions.
		# Scalar counts/cursors and one flat output replace comparison sort.
		saved_syllable = ShaperIndic.syllable(ShaperIndic.at($work.items, start).mask)
		{ sorted, buckets } = scratch
		var $buckets = buckets
		for i in 0..<15 {
			$buckets = $buckets.set(i, { count: 0, cursor: 0 }) ?? []
		}
		for i in start..<end {
			pos_value = ShaperIndic.pos(ShaperIndic.at($work.items, i))
			bucket = $buckets.get(pos_value) ?? { count: 0, cursor: 0 }
			$buckets = $buckets.set(pos_value, { ..bucket, count: bucket.count + 1 }) ?? []
		}
		var $cursor = 0
		for i in 0..<15 {
			bucket = $buckets.get(i) ?? { count: 0, cursor: 0 }
			$buckets = $buckets.set(i, { ..bucket, cursor: $cursor }) ?? []
			$cursor = $cursor + bucket.count
		}
		var $sorted = sorted
		while $sorted.len() < end - start {
			$sorted = $sorted.append(LayoutGsub.no_item)
		}
		for i in start..<end {
			item = ShaperIndic.at($work.items, i)
			pos_value = ShaperIndic.pos(item)
			bucket = $buckets.get(pos_value) ?? { count: 0, cursor: 0 }
			$sorted = $sorted.set(bucket.cursor, { ..item, mask: ShaperIndic.set_syllable(item.mask, (i - start) % 256) }) ?? []
			$buckets = $buckets.set(pos_value, { ..bucket, cursor: bucket.cursor + 1 }) ?? []
		}
		$work = ShaperIndic.replace_span($work, start, $sorted, end - start)
		var $first_matra = end
		var $last_matra = end
		$base = end
		var $find_i = start
		while $find_i < end and $base == end and $work.stopped == 0 {
			$work = ShaperIndic.charge($work, 1)
			pos_value = ShaperIndic.pos(ShaperIndic.at($work.items, $find_i))
			if pos_value == 4 {
				$base = $find_i
			}
			else if pos_value == 2 {
				if $first_matra == end {
					$first_matra = $find_i
				}
				$last_matra = $find_i
			}
			$find_i = $find_i + 1
		}
		if $first_matra < $last_matra {
			$work = ShaperIndic.reverse($work, $first_matra, $last_matra + 1)
			var $reverse_i = $first_matra
			for j in $first_matra..<$last_matra + 1 {
				cat_value = ShaperIndic.cat(ShaperIndic.at($work.items, j))
				if cat_value == 7 or cat_value == 13 {
					$work = ShaperIndic.reverse($work, $reverse_i, j + 1)
					$reverse_i = j + 1
				}
			}
		}
		if plan.old_spec or end - start > 127 {
			$work = ShaperIndic.merge($work, $base, end)
		}
		else {
			for i in $base..<end {
				item = ShaperIndic.at($work.items, i)
				if ShaperIndic.syllable(item.mask) != 255 {
					var $lo = i
					var $hi = i
					var $j = start + ShaperIndic.syllable(item.mask)
					var $visits = 0
					while $j != i and $visits < end - start and $work.stopped == 0 {
						$lo = $lo.min($j)
						$hi = $hi.max($j)
						previous = ShaperIndic.at($work.items, $j)
						next = start + ShaperIndic.syllable(previous.mask)
						$work = ShaperIndic.put($work, $j, { ..previous, mask: ShaperIndic.set_syllable(previous.mask, 255) })
						$j = next
						$visits = $visits + 1
					}
					$work = ShaperIndic.merge($work, $base.max($lo), $hi + 1)
				}
			}
		}
		for i in start..<end {
			item = ShaperIndic.at($work.items, i)
			$work = ShaperIndic.put($work, i, { ..item, mask: ShaperIndic.set_syllable(item.mask, saved_syllable) })
		}
		var $reph_i = start
		while $reph_i < end and ShaperIndic.pos(ShaperIndic.at($work.items, $reph_i)) == 1 and $work.stopped == 0 {
			item = ShaperIndic.at($work.items, $reph_i)
			$work = ShaperIndic.put($work, $reph_i, { ..item, mask: item.mask.bitwise_or(plan.masks.rphf) })
			$reph_i = $reph_i + 1
		}
		pre_mask = if !plan.old_spec and !cfg.post_only {
			plan.masks.half.bitwise_or(plan.masks.blwf)
		} else {
			plan.masks.half
		}
		for i in start..<$base {
			item = ShaperIndic.at($work.items, i)
			$work = ShaperIndic.put($work, i, { ..item, mask: item.mask.bitwise_or(pre_mask) })
		}
		if $base < end {
			post_mask = plan.masks.blwf.bitwise_or(plan.masks.abvf).bitwise_or(plan.masks.pstf)
			for i in ($base + 1)..<end {
				item = ShaperIndic.at($work.items, i)
				$work = ShaperIndic.put($work, i, { ..item, mask: item.mask.bitwise_or(post_mask) })
			}
		}
		if plan.old_spec and plan.script == ShaperTags.tag_of("Deva") {
			var $eye_i = start
			while $eye_i + 1 < $base and $work.stopped == 0 {
				$work = ShaperIndic.charge($work, 1)
				if ShaperIndic.cat(ShaperIndic.at($work.items, $eye_i)) == 15 and ShaperIndic.cat(ShaperIndic.at($work.items, $eye_i + 1)) == 4 and ($eye_i + 2 == $base or ShaperIndic.cat(ShaperIndic.at($work.items, $eye_i + 2)) != 6) {
					for j in $eye_i..<$eye_i + 2 {
						item = ShaperIndic.at($work.items, j)
						$work = ShaperIndic.put($work, j, { ..item, mask: item.mask.bitwise_or(plan.masks.blwf) })
					}
				}
				$eye_i = $eye_i + 1
			}
		}
		if plan.masks.pref != 0 and end - $base > 2 {
			var $pref_i = $base + 1
			var $found = False
			while $pref_i + 1 < end and !$found and $work.stopped == 0 {
				result = ShaperIndic.probe($work, oracle, 1, [ShaperIndic.at($work.items, $pref_i).glyph, ShaperIndic.at($work.items, $pref_i + 1).glyph])
				$work = result.work
				if result.matches {
					$found = True
					for j in $pref_i..<$pref_i + 2 {
						item = ShaperIndic.at($work.items, j)
						$work = ShaperIndic.put($work, j, { ..item, mask: item.mask.bitwise_or(plan.masks.pref) })
					}
				}
				$pref_i = $pref_i + 1
			}
		}
		for i in (start + 1)..<end {
			item = ShaperIndic.at($work.items, i)
			if ShaperIndic.joiner(item) {
				non_joiner = ShaperIndic.cat(item) == 5
				var $j = i
				var $join_search = True
				while $j > start and $join_search and $work.stopped == 0 {
					$j = $j - 1
					previous = ShaperIndic.at($work.items, $j)
					$work = ShaperIndic.charge($work, 1)
					if non_joiner {
						$work = ShaperIndic.put($work, $j, { ..previous, mask: previous.mask.bitwise_and(plan.masks.half.bitwise_not()) })
					}
					if ShaperIndic.consonant(previous) {
						$join_search = False
					}
				}
			}
		}
		{ work: $work, scratch: { sorted: $sorted, buckets: $buckets } }
	}

	initial : ShaperIndic, List(LayoutGsub.Item), Probe, Dotted, U64, U64 -> { items : List(LayoutGsub.Item), operations : U64, stopped : U64 }
	initial = |plan, items, oracle, dotted, limit, budget| {
		var $work = ShaperIndic.update_positions(plan, { items, operations: 0, stopped: 0, budget }, oracle)
		$work = ShaperIndic.dotted_circles($work, dotted, limit)
		if $work.stopped != 0 or $work.items.is_empty() {
			return { items: $work.items, operations: $work.operations, stopped: $work.stopped }
		}
		var $scratch = { sorted: [], buckets: List.repeat({ count: 0, cursor: 0 }, 15) }
		var $start = 0
		while $start < $work.items.len() and $work.stopped == 0 {
			syllable_id = ShaperIndic.syllable(ShaperIndic.at($work.items, $start).mask)
			var $end = $start + 1
			while $end < $work.items.len() and $end - $start < 64 and ShaperIndic.syllable(ShaperIndic.at($work.items, $end).mask) == syllable_id and $work.stopped == 0 {
				$work = ShaperIndic.charge($work, 1)
				$end = $end + 1
			}
			kind = syllable_id.bitwise_and(15)
			if kind <= 2 or kind == 4 {
				reordered = ShaperIndic.initial_syllable(plan, $work, $start, $end, oracle, $scratch)
				$work = reordered.work
				$scratch = reordered.scratch
			}
			$start = $end
		}
		{ items: $work.items, operations: $work.operations, stopped: $work.stopped }
	}

	final_syllable : ShaperIndic, Work, U64, U64 -> Work
	final_syllable = |plan, work, start, end| {
		var $work = work
		if plan.virama_glyph != 0 {
			for i in start..<end {
				item = ShaperIndic.at($work.items, i)
				if item.glyph == plan.virama_glyph and item.props.shr_zf_wrap(16).bitwise_and(0x60) == 0x60 {
					$work = ShaperIndic.put($work, i, { ..item, mask: ShaperIndic.set_category(item.mask, 4), props: item.props.bitwise_and(0xFFFFFFFFFF9FFFFF) })
				}
			}
		}
		var $try_pref = plan.masks.pref != 0
		var $base = start
		var $find = True
		while $base < end and $find and $work.stopped == 0 {
			$work = ShaperIndic.charge($work, 1)
			if ShaperIndic.pos(ShaperIndic.at($work.items, $base)) < 4 {
				$base = $base + 1
			}
			else {
				$find = False
				if $try_pref and $base + 1 < end {
					var $candidate_i = $base + 1
					var $candidate_found = False
					while $candidate_i < end and !$candidate_found and $work.stopped == 0 {
						$work = ShaperIndic.charge($work, 1)
						item = ShaperIndic.at($work.items, $candidate_i)
						if item.mask.bitwise_and(plan.masks.pref) != 0 {
							$candidate_found = True
							if !(item.props.shr_zf_wrap(16).bitwise_and(0x10) != 0 and ShaperIndic.ligated_single(item)) {
								$base = $candidate_i
								while $base < end and ShaperIndic.halant(ShaperIndic.at($work.items, $base)) and $work.stopped == 0 {
									$work = ShaperIndic.charge($work, 1)
									$base = $base + 1
								}
								if $base < end {
									$work = ShaperIndic.put($work, $base, ShaperIndic.with_pos(ShaperIndic.at($work.items, $base), 4))
								}
								$try_pref = False
							}
						}
						$candidate_i = $candidate_i + 1
					}
				}
				if $base < end and plan.script == ShaperTags.tag_of("Mlym") {
					var $mal_i = $base + 1
					var $mal_search = True
					while $mal_i < end and $mal_search and $work.stopped == 0 {
						while $mal_i < end and ShaperIndic.joiner(ShaperIndic.at($work.items, $mal_i)) and $work.stopped == 0 {
							$work = ShaperIndic.charge($work, 1)
							$mal_i = $mal_i + 1
						}
						if $mal_i == end or !ShaperIndic.halant(ShaperIndic.at($work.items, $mal_i)) {
							$mal_search = False
						}
						else {
							$mal_i = $mal_i + 1
							while $mal_i < end and ShaperIndic.joiner(ShaperIndic.at($work.items, $mal_i)) and $work.stopped == 0 {
								$work = ShaperIndic.charge($work, 1)
								$mal_i = $mal_i + 1
							}
							if $mal_i < end and ShaperIndic.consonant(ShaperIndic.at($work.items, $mal_i)) and ShaperIndic.pos(ShaperIndic.at($work.items, $mal_i)) == 8 {
								$base = $mal_i
								$work = ShaperIndic.put($work, $base, ShaperIndic.with_pos(ShaperIndic.at($work.items, $base), 4))
							}
							$mal_i = $mal_i + 1
						}
					}
				}
				if $base < end and $base > start and ShaperIndic.pos(ShaperIndic.at($work.items, $base)) > 4 {
					$base = $base - 1
				}
			}
		}
		if $base == end and $base > start and !ShaperIndic.ligated(ShaperIndic.at($work.items, $base - 1)) and ShaperIndic.cat(ShaperIndic.at($work.items, $base - 1)) == 6 {
			$base = $base - 1
		}
		if $base < end {
			while $base > start and !ShaperIndic.ligated(ShaperIndic.at($work.items, $base)) and (ShaperIndic.cat(ShaperIndic.at($work.items, $base)) == 3 or ShaperIndic.cat(ShaperIndic.at($work.items, $base)) == 4) and $work.stopped == 0 {
				$work = ShaperIndic.charge($work, 1)
				$base = $base - 1
			}
		}
		# Reposition pre-base matras after the last standalone halant.
		if start + 1 < end and start < $base {
			var $matra_pos = if $base == end {
				$base - 2
			} else {
				$base - 1
			}
			if plan.script != ShaperTags.tag_of("Mlym") and plan.script != ShaperTags.tag_of("Taml") {
				var $matra_search = True
				while $matra_search and $work.stopped == 0 {
					while $matra_pos > start and !ShaperIndic.matra(ShaperIndic.at($work.items, $matra_pos)) and !ShaperIndic.halant(ShaperIndic.at($work.items, $matra_pos)) and $work.stopped == 0 {
						$work = ShaperIndic.charge($work, 1)
						$matra_pos = $matra_pos - 1
					}
					if ShaperIndic.halant(ShaperIndic.at($work.items, $matra_pos)) and ShaperIndic.pos(ShaperIndic.at($work.items, $matra_pos)) != 2 {
						if $matra_pos + 1 < end and ShaperIndic.cat(ShaperIndic.at($work.items, $matra_pos + 1)) == 6 and $matra_pos > start {
							$matra_pos = $matra_pos - 1
						}
						else {
							$matra_search = False
						}
					} else {
						$matra_pos = start
						$matra_search = False
					}
				}
			}
			if start < $matra_pos and ShaperIndic.pos(ShaperIndic.at($work.items, $matra_pos)) != 2 {
				var $matra_i = $matra_pos
				while $matra_i > start and $work.stopped == 0 {
					$work = ShaperIndic.charge($work, 1)
					if ShaperIndic.pos(ShaperIndic.at($work.items, $matra_i - 1)) == 2 {
						old = $matra_i - 1
						if old < $base and $base <= $matra_pos {
							$base = $base - 1
						}
						$work = ShaperIndic.move($work, old, $matra_pos)
						$work = ShaperIndic.merge($work, $matra_pos, end.min($base + 1))
						$matra_pos = $matra_pos - 1
					}
					$matra_i = $matra_i - 1
				}
			} else {
				var $merge_i = start
				var $merged = False
				while $merge_i < $base and !$merged and $work.stopped == 0 {
					$work = ShaperIndic.charge($work, 1)
					if ShaperIndic.pos(ShaperIndic.at($work.items, $merge_i)) == 2 {
						$work = ShaperIndic.merge($work, $merge_i, end.min($base + 1))
						$merged = True
					}
					$merge_i = $merge_i + 1
				}
			}
		}
		first = ShaperIndic.at($work.items, start)
		if start + 1 < end and ShaperIndic.pos(first) == 1 and ((ShaperIndic.cat(first) == 14) != ShaperIndic.ligated_single(first)) {
			reph_position = ShaperIndic.config(plan.script).reph_pos
			var $reph_pos = start + 1
			var $reph_found = False
			if reph_position != 12 {
				while $reph_pos < $base and !ShaperIndic.halant(ShaperIndic.at($work.items, $reph_pos)) and $work.stopped == 0 {
					$work = ShaperIndic.charge($work, 1)
					$reph_pos = $reph_pos + 1
				}
				if $reph_pos < $base and ShaperIndic.halant(ShaperIndic.at($work.items, $reph_pos)) {
					if $reph_pos + 1 < $base and ShaperIndic.joiner(ShaperIndic.at($work.items, $reph_pos + 1)) {
						$reph_pos = $reph_pos + 1
					}
					$reph_found = True
				}
				if !$reph_found and reph_position == 5 {
					$reph_pos = $base
					while $reph_pos + 1 < end and ShaperIndic.pos(ShaperIndic.at($work.items, $reph_pos + 1)) <= 5 and $work.stopped == 0 {
						$work = ShaperIndic.charge($work, 1)
						$reph_pos = $reph_pos + 1
					}
					$reph_found = $reph_pos < end
				}
				if !$reph_found and reph_position == 9 {
					$reph_pos = $base
					var $post_search = True
					while $reph_pos + 1 < end and $post_search and $work.stopped == 0 {
						$work = ShaperIndic.charge($work, 1)
						p = ShaperIndic.pos(ShaperIndic.at($work.items, $reph_pos + 1))
						if p == 11 or p == 12 or p == 13 {
							$post_search = False
						}
						else {
							$reph_pos = $reph_pos + 1
						}
					}
					$reph_found = $reph_pos < end
				}
			}
			if !$reph_found {
				$reph_pos = start + 1
				while $reph_pos < $base and !ShaperIndic.halant(ShaperIndic.at($work.items, $reph_pos)) and $work.stopped == 0 {
					$work = ShaperIndic.charge($work, 1)
					$reph_pos = $reph_pos + 1
				}
				if $reph_pos < $base and ShaperIndic.halant(ShaperIndic.at($work.items, $reph_pos)) {
					if $reph_pos + 1 < $base and ShaperIndic.joiner(ShaperIndic.at($work.items, $reph_pos + 1)) {
						$reph_pos = $reph_pos + 1
					}
					$reph_found = True
				}
			}
			if !$reph_found {
				$reph_pos = end - 1
				while $reph_pos > start and ShaperIndic.pos(ShaperIndic.at($work.items, $reph_pos)) == 13 and $work.stopped == 0 {
					$work = ShaperIndic.charge($work, 1)
					$reph_pos = $reph_pos - 1
				}
				if ShaperIndic.halant(ShaperIndic.at($work.items, $reph_pos)) {
					var $tail_i = $base + 1
					while $tail_i < $reph_pos and $work.stopped == 0 {
						$work = ShaperIndic.charge($work, 1)
						c = ShaperIndic.cat(ShaperIndic.at($work.items, $tail_i))
						if c == 7 or c == 13 {
							$reph_pos = $reph_pos - 1
						}
						$tail_i = $tail_i + 1
					}
				}
			}
			$work = ShaperIndic.merge($work, start, $reph_pos + 1)
			$work = ShaperIndic.move($work, start, $reph_pos)
			if start < $base and $base <= $reph_pos {
				$base = $base - 1
			}
		}
		if $try_pref and $base + 1 < end {
			var $pref_i = $base + 1
			var $pref_found = False
			while $pref_i < end and !$pref_found and $work.stopped == 0 {
				$work = ShaperIndic.charge($work, 1)
				item = ShaperIndic.at($work.items, $pref_i)
				if item.mask.bitwise_and(plan.masks.pref) != 0 {
					$pref_found = True
					if ShaperIndic.ligated_single(item) {
						var $pref_pos = $base
						if plan.script != ShaperTags.tag_of("Mlym") and plan.script != ShaperTags.tag_of("Taml") {
							while $pref_pos > start and !ShaperIndic.matra(ShaperIndic.at($work.items, $pref_pos - 1)) and !ShaperIndic.halant(ShaperIndic.at($work.items, $pref_pos - 1)) and $work.stopped == 0 {
								$work = ShaperIndic.charge($work, 1)
								$pref_pos = $pref_pos - 1
							}
						}
						if $pref_pos > start and ShaperIndic.halant(ShaperIndic.at($work.items, $pref_pos - 1)) and $pref_pos < end and ShaperIndic.joiner(ShaperIndic.at($work.items, $pref_pos)) {
							$pref_pos = $pref_pos + 1
						}
						$work = ShaperIndic.merge($work, $pref_pos, $pref_i + 1)
						$work = ShaperIndic.move($work, $pref_i, $pref_pos)
						if $pref_pos <= $base and $base < $pref_i {
							$base = $base + 1
						}
					}
				}
				$pref_i = $pref_i + 1
			}
		}
		if ShaperIndic.pos(ShaperIndic.at($work.items, start)) == 2 {
			gc = if start == 0 {
				0
			} else {
				ShaperIndic.at($work.items, start - 1).props.bitwise_and(31)
			}
			if start == 0 or gc < 1 or gc > 12 {
				item = ShaperIndic.at($work.items, start)
				$work = ShaperIndic.put($work, start, { ..item, mask: item.mask.bitwise_or(plan.masks.init) })
			}
			else {
				cluster = LayoutGsub.end_cluster($work.items, start - 1, start + 1, 0xFFFFFFFFFFFFFFFF)
				{ items, operations, stopped, budget } = $work
				$work = ShaperIndic.charge({ items: LayoutGsub.flag_range(items, start - 1, start + 1, cluster), operations, stopped, budget }, 2)
			}
		}
		$work
	}

	final_reorder : ShaperIndic, List(LayoutGsub.Item), U64 -> { items : List(LayoutGsub.Item), operations : U64, stopped : U64 }
	final_reorder = |plan, items, budget| {
		var $work = { items, operations: 0, stopped: 0, budget }
		var $start = 0
		while $start < $work.items.len() and $work.stopped == 0 {
			syllable_id = ShaperIndic.syllable(ShaperIndic.at($work.items, $start).mask)
			var $end = $start + 1
			while $end < $work.items.len() and $end - $start < 64 and ShaperIndic.syllable(ShaperIndic.at($work.items, $end).mask) == syllable_id and $work.stopped == 0 {
				$work = ShaperIndic.charge($work, 1)
				$end = $end + 1
			}
			$work = ShaperIndic.final_syllable(plan, $work, $start, $end)
			$start = $end
		}
		{ items: $work.items, operations: $work.operations, stopped: $work.stopped }
	}

}

expect ShaperIndic.category(ShaperIndic.set_category(0xFFFFFFFFFFFFFFFF, 57)) == 57
expect ShaperIndic.position(ShaperIndic.set_position(0xFFFFFFFFFFFFFFFF, 14)) == 14
expect ShaperIndic.syllable(ShaperIndic.set_syllable(0xFFFFFFFFFFFFFFFF, 0xF4)) == 0xF4
expect ShaperIndic.category(ShaperIndic.set_syllable(ShaperIndic.set_category(0, 57), 0xF4)) == 57

## regression: a spent budget must not stop halfway through a move
## and duplicate one glyph while losing another.
expect {
	items = [1, 2, 3].map(|glyph| { ..LayoutGsub.no_item, glyph })
	work = { items, operations: 0, stopped: 0, budget: 1 }
	result = ShaperIndic.move(work, 0, 2)
	result.stopped == 2 and result.items.map(|item| item.glyph) == [1, 2, 3]
}
expect {
	items = [1, 2, 3].map(|glyph| { ..LayoutGsub.no_item, glyph })
	work = { items, operations: 0, stopped: 0, budget: 2 }
	result = ShaperIndic.reverse(work, 0, 3)
	result.stopped == 0 and result.items.map(|item| item.glyph) == [3, 2, 1]
}
expect {
	items = [30, 20, 10].map(|cluster| { ..LayoutGsub.no_item, cluster })
	work = { items, operations: 0, stopped: 0, budget: 4 }
	result = ShaperIndic.merge(work, 0, 3)
	result.stopped == 2 and result.items.map(|item| item.cluster) == [30, 20, 10]
}

# A raw syllable serial wraps after15. Upstream tracks the last broken
# id on insertion only; the preallocation count must match that output.
expect {
	var $items = []
	for i in 0..<16 {
		serial = if i == 15 {
			1
		} else {
			i + 1
		}
		kind = if i == 0 or i == 15 {
			4.U64
		} else {
			0
		}
		$items = $items.append({ ..LayoutGsub.no_item, glyph: i + 1, cluster: i, mask: (serial * 16 + kind).shl_wrap(49) })
	}
	work = { items: $items, operations: 0, stopped: 0, budget: 100 }
	result = ShaperIndic.dotted_circles(work, Present({ glyph: 99, props: 0 }), 17)
	result.stopped == 0 and result.items.len() == 17 and result.items.keep_if(|item| item.glyph == 99).len() == 1
}
