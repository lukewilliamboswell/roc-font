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
# USE phases and machine adapted from HarfBuzz 14.6.0.
# hb-ot-shaper-use.cc, hb-ot-shaper-use-machine.rl/.hh.

import ShaperTags
import ShaperNormalize
import ShaperArabic
import ShaperIndic
import ShaperUseData
import ShaperUseMachine
import LayoutGsub

## The Universal Shaping Engine's exact syllable, feature-mask and
## reorder phases. The script/font selection remains the orchestrator's
## responsibility; supports/selected expose the pinned selection facts.
ShaperUse := {
	script : U64,
	rphf_mask : U64,
	joining_masks : ShaperArabic.Masks,
	arabic_joining : Bool,
	global_mask : U64,
}.{
	Feature : ShaperIndic.Feature
	Context : ShaperIndic.Context
	Event : [SetupSyllables, ClearSubstitutionFlags, RecordRphf, RecordPref, Reorder, ClearSyllables]
	make = |facts| ShaperUse.{ script: facts.script, rphf_mask: facts.rphf_mask, joining_masks: facts.joining_masks, arabic_joining: facts.arabic_joining, global_mask: facts.global_mask }
	supports : U64 -> Bool
	supports = |script| ShaperUseData.scripts.any(|value| value == script)
	has_arabic_joining : U64 -> Bool
	has_arabic_joining = |script| ShaperUseData.joining_scripts.any(|value| value == script)
	selected : U64, U64 -> Bool
	selected = |script, gsub_script| {
		gsub_script != ShaperTags.tag_of("DFLT") and gsub_script != ShaperTags.tag_of("latn") and (ShaperUse.supports(script) or (ShaperIndic.virama(script) != 0 and gsub_script.bitwise_and(255) == 51))
	}
	pauses : List({ stage : U64, event : Event })
	pauses = [
		{ stage: 2, event: SetupSyllables },
		{ stage: 3, event: ClearSubstitutionFlags },
		{ stage: 4, event: RecordRphf },
		{ stage: 4, event: ClearSubstitutionFlags },
		{ stage: 5, event: RecordPref },
		{ stage: 6, event: Reorder },
		{ stage: 6, event: ClearSyllables },
	]
	features : List(Feature)
	features = {
		names = ["locl", "ccmp", "nukt", "akhn", "rphf", "pref", "rkrf", "abvf", "blwf", "half", "pstf", "vatu", "cjct", "isol", "init", "medi", "fina", "abvs", "blws", "haln", "pres", "psts"]
		var $features = List.with_capacity(names.len())
		for name in names {
			tag = ShaperTags.tag_of(name)
			early = name == "locl" or name == "ccmp" or name == "nukt"
			topographical = name == "isol" or name == "init" or name == "medi" or name == "fina"
			feature_stage = ShaperUse.stage(tag)
			$features = $features.append({ tag, stage: feature_stage, default: 1, global: name != "rphf" and !topographical, manual_zwj: !early and !topographical, manual_zwnj: False, per_syllable: feature_stage < 6 })
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
		else if tag == ShaperTags.tag_of("locl") or tag == ShaperTags.tag_of("ccmp") or tag == ShaperTags.tag_of("nukt") or tag == ShaperTags.tag_of("akhn") {
			2
		}
		else if tag == ShaperTags.tag_of("rphf") {
			3
		}
		else if tag == ShaperTags.tag_of("pref") {
			4
		}
		else if tag == ShaperTags.tag_of("rkrf") or tag == ShaperTags.tag_of("abvf") or tag == ShaperTags.tag_of("blwf") or tag == ShaperTags.tag_of("half") or tag == ShaperTags.tag_of("pstf") or tag == ShaperTags.tag_of("vatu") or tag == ShaperTags.tag_of("cjct") {
			5
		}
		else if tag == ShaperTags.tag_of("isol") or tag == ShaperTags.tag_of("init") or tag == ShaperTags.tag_of("medi") or tag == ShaperTags.tag_of("fina") {
			6
		}
		else {
			7
		}
	}
	setup : ShaperUse, List(ShaperNormalize.Char), { before : List(U32), after : List(U32) } -> List(ShaperNormalize.Char)
	setup = |plan, chars, context| {
		joined = if !plan.arabic_joining {
			chars
		}
		else if plan.script == ShaperTags.tag_of("Mong") {
			ShaperArabic.setup_mongolian(chars, plan.joining_masks, context)
		}
		else {
			ShaperArabic.setup(chars, plan.joining_masks, context)
		}
		var $chars = joined
		for i in 0..<$chars.len() {
			ch = $chars.get(i) ?? ShaperNormalize.no_char
			$chars = $chars.set(i, { ..ch, mask: ShaperIndic.set_category(ch.mask, ShaperUseData.get(ch.cp)) }) ?? []
		}
		$chars
	}
	pause : ShaperUse, Event, LayoutGsub, List(LayoutGsub.Item), Context -> { items : List(LayoutGsub.Item), operations : U64, stopped : U64 }
	pause = |plan, event, _shape, items, context| {
		work = { items, operations: 0, stopped: 0, budget: context.budget }
		result = match event {
			SetupSyllables => {
				found = ShaperUseMachine.run(work.items, work.budget)
				ShaperUse.topography(plan, ShaperUse.rphf_masks(plan, { items: found.items, operations: found.operations, stopped: found.stopped, budget: work.budget }))
			}
			ClearSubstitutionFlags => {
				checked = ShaperIndic.charge(work, work.items.len())
				if checked.stopped != 0 {
					checked
				}
				else {
					{ ..checked, items: LayoutGsub.clear_substitution_flags(checked.items) }
				}
			}
			RecordRphf => ShaperUse.record(plan, work, True)
			RecordPref => ShaperUse.record(plan, work, False)
			Reorder => ShaperUse.reorder(ShaperUse.dotted_circles(work, context.dotted_circle, context.limit))
			ClearSyllables => {
				checked = ShaperIndic.charge(work, work.items.len())
				if checked.stopped != 0 {
					checked
				}
				else {
					{ ..checked, items: ShaperIndic.clear_syllables(checked.items) }
				}
			}
		}
		{ items: result.items, operations: result.operations, stopped: result.stopped }
	}
	syllable_end : List(LayoutGsub.Item), U64 -> U64
	syllable_end = |items, start| {
		id = ShaperIndic.syllable(ShaperIndic.at(items, start).mask)
		var $end = start + 1
		while $end < items.len() and $end - start < 64 and ShaperIndic.syllable(ShaperIndic.at(items, $end).mask) == id {
			$end = $end + 1
		}
		$end
	}
	rphf_masks : ShaperUse, ShaperIndic.Work -> ShaperIndic.Work
	rphf_masks = |plan, work| {
		if plan.rphf_mask == 0 {
			work
		}
		else {
			var $work = work
			var $start = 0
			while $start < $work.items.len() and $work.stopped == 0 {
				end = ShaperUse.syllable_end($work.items, $start)
				limit = if ShaperIndic.cat(ShaperIndic.at($work.items, $start)) == 18 {
					1
				} else {
					(end - $start).min(3)
				}
				for i in $start..<$start + limit {
					item = ShaperIndic.at($work.items, i)
					$work = ShaperIndic.put($work, i, { ..item, mask: item.mask.bitwise_or(plan.rphf_mask) })
				}
				$work = ShaperIndic.charge($work, end - $start)
				$start = end
			}
			$work
		}
	}
	form_mask : ShaperUse, U64 -> U64
	form_mask = |plan, form| {
		mask = match form {
			0 => plan.joining_masks.isol
			1 => plan.joining_masks.init
			2 => plan.joining_masks.medi
			3 => plan.joining_masks.fina
			_ => 0
		}
		if mask == plan.global_mask {
			0
		} else {
			mask
		}
	}
	topography : ShaperUse, ShaperIndic.Work -> ShaperIndic.Work
	topography = |plan, work| {
		all_masks = ShaperUse.form_mask(plan, 0).bitwise_or(ShaperUse.form_mask(plan, 1)).bitwise_or(ShaperUse.form_mask(plan, 2)).bitwise_or(ShaperUse.form_mask(plan, 3))
		if plan.arabic_joining or all_masks == 0 {
			work
		}
		else {
			var $work = work
			var $last_start = 0
			var $last_form = 4
			var $start = 0
			while $start < $work.items.len() and $work.stopped == 0 {
				end = ShaperUse.syllable_end($work.items, $start)
				kind = ShaperIndic.syllable(ShaperIndic.at($work.items, $start).mask).bitwise_and(15)
				if kind == 6 or kind == 8 {
					$last_form = 4
				}
				else {
					join = $last_form == 3 or $last_form == 0
					if join {
						$last_form = if $last_form == 3 {
							2
						} else {
							1
						}
						mask = ShaperUse.form_mask(plan, $last_form)
						for i in $last_start..<$start {
							item = ShaperIndic.at($work.items, i)
							$work = ShaperIndic.put($work, i, { ..item, mask: item.mask.bitwise_and(all_masks.bitwise_not()).bitwise_or(mask) })
						}
					}
					$last_form = if join {
						3
					} else {
						0
					}
					mask = ShaperUse.form_mask(plan, $last_form)
					for i in $start..<end {
						item = ShaperIndic.at($work.items, i)
						$work = ShaperIndic.put($work, i, { ..item, mask: item.mask.bitwise_and(all_masks.bitwise_not()).bitwise_or(mask) })
					}
				}
				$work = ShaperIndic.charge($work, end - $start)
				$last_start = $start
				$start = end
			}
			$work
		}
	}
	record : ShaperUse, ShaperIndic.Work, Bool -> ShaperIndic.Work
	record = |plan, work, reph| {
		if reph and plan.rphf_mask == 0 {
			work
		}
		else {
			var $work = work
			var $start = 0
			while $start < $work.items.len() and $work.stopped == 0 {
				end = ShaperUse.syllable_end($work.items, $start)
				var $i = $start
				var $search = True
				while $i < end and $search and $work.stopped == 0 {
					item = ShaperIndic.at($work.items, $i)
					$work = ShaperIndic.charge($work, 1)
					if reph and item.mask.bitwise_and(plan.rphf_mask) == 0 {
						$search = False
					}
					else if item.props.shr_zf_wrap(16).bitwise_and(0x10) != 0 {
						$work = ShaperIndic.put(
							$work,
							$i,
							{
								..item,
								mask: ShaperIndic.set_category(
									item.mask,
									if reph {
										18
									} else {
										22
									},
								),
							},
						)
						$search = False
					}
					$i = $i + 1
				}
				$start = end
			}
			$work
		}
	}

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
					if syllable_id != $last and syllable_id.bitwise_and(15) == 7 {
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
						if syllable_id != $last_syllable and syllable_id.bitwise_and(15) == 7 {
							$last_syllable = syllable_id
							mask = ShaperIndic.set_position(ShaperIndic.set_category(item.mask, 1), 0)
							while $i < items.len() and ShaperIndic.syllable(ShaperIndic.at(items, $i).mask) == syllable_id and ShaperIndic.cat(ShaperIndic.at(items, $i)) == 18 {
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

	is_halant : LayoutGsub.Item -> Bool
	is_halant = |item| {
		category = ShaperIndic.cat(item)
		!ShaperIndic.ligated(item) and (category == 12 or category == 53 or category == 44)
	}
	reorder_syllable : ShaperIndic.Work, U64, U64 -> ShaperIndic.Work
	reorder_syllable = |work, start, end| {
		kind = ShaperIndic.syllable(ShaperIndic.at(work.items, start).mask).bitwise_and(15)
		if kind != 0 and kind != 1 and kind != 2 and kind != 5 and kind != 7 {
			work
		}
		else {
			var $work = work
			if ShaperIndic.cat(ShaperIndic.at($work.items, start)) == 18 and end - start > 1 {
				var $forward = start + 1
				var $found = False
				while $forward < end and !$found and $work.stopped == 0 {
					$work = ShaperIndic.charge($work, 1)
					item = ShaperIndic.at($work.items, $forward)
					category = ShaperIndic.cat(item)
					post_base = (0xE0EE7FC00000.U64).bitwise_and((1.U64).shl_wrap(category.to_u8_wrap())) != 0 or ShaperUse.is_halant(item)
					if post_base or $forward == end - 1 {
						target = if post_base {
							$forward - 1
						} else {
							$forward
						}
						$work = ShaperIndic.merge($work, start, target + 1)
						$work = ShaperIndic.move($work, start, target)
						$found = True
					}
					$forward = $forward + 1
				}
			}
			var $j = start
			var $i = start
			while $i < end and $work.stopped == 0 {
				$work = ShaperIndic.charge($work, 1)
				item = ShaperIndic.at($work.items, $i)
				category = ShaperIndic.cat(item)
				if ShaperUse.is_halant(item) {
					$j = $i + 1
				}
				else if (category == 22 or category == 23) and LayoutGsub.lig_comp(item) == 0 and $j < $i {
					$work = ShaperIndic.merge($work, $j, $i + 1)
					$work = ShaperIndic.move($work, $i, $j)
				}
				$i = $i + 1
			}
			$work
		}
	}
	reorder : ShaperIndic.Work -> ShaperIndic.Work
	reorder = |work| {
		var $work = work
		var $start = 0
		while $start < $work.items.len() and $work.stopped == 0 {
			end = ShaperUse.syllable_end($work.items, $start)
			$work = ShaperUse.reorder_syllable($work, $start, end)
			$start = end
		}
		$work
	}
}

expect ShaperUse.supports(ShaperTags.tag_of("Tibt"))
expect ShaperUse.has_arabic_joining(ShaperTags.tag_of("Nkoo"))
expect !ShaperUse.has_arabic_joining(ShaperTags.tag_of("Tibt"))
expect !ShaperUse.selected(ShaperTags.tag_of("Tibt"), ShaperTags.tag_of("DFLT"))
expect ShaperUse.selected(ShaperTags.tag_of("Tibt"), 0)
expect ShaperUse.selected(ShaperTags.tag_of("Deva"), ShaperTags.tag_of("dev3"))
expect !ShaperUse.selected(ShaperTags.tag_of("Deva"), ShaperTags.tag_of("dev2"))
