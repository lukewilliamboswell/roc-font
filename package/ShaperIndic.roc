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
}

expect ShaperIndic.category(ShaperIndic.set_category(0xFFFFFFFFFFFFFFFF, 57)) == 57
expect ShaperIndic.position(ShaperIndic.set_position(0xFFFFFFFFFFFFFFFF, 14)) == 14
expect ShaperIndic.syllable(ShaperIndic.set_syllable(0xFFFFFFFFFFFFFFFF, 0xF4)) == 0xF4
expect ShaperIndic.category(ShaperIndic.set_syllable(ShaperIndic.set_category(0, 57), 0xF4)) == 57
