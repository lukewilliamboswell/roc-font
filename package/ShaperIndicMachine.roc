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

import LayoutGsub
import ShaperIndicData

## Exact pinned Indic Ragel machine. A transition and each emitted item
## charge one unit; the caller shares this counter with all shaping stages.
ShaperIndicMachine :: {}.{
	run : List(LayoutGsub.Item), U64 -> { items : List(LayoutGsub.Item), operations : U64, stopped : U64 }
	run = |items, budget| {
		n = items.len()
		var $items = items
		var $p = 0
		var $ts = 0
		var $te = 0
		var $act = 0
		var $cs = ShaperIndicData.indic_start
		var $serial = 1
		var $ops = 0
		var $stopped = 0
		var $done = n == 0
		while !$done and $stopped == 0 {
			if $ops >= budget {
				$stopped = 2
			}
			else {
				$ops = $ops + 1
				var $trans = 0
				if $p == n {
					eof = ShaperIndicData.indic_eof_trans.get($cs) ?? 0
					if eof == 0 {
						$done = True
					}
					else {
						$trans = eof - 1
					}
				} else if $p > n {
					$done = True
				}
				else {
					if (ShaperIndicData.indic_from_state_actions.get($cs) ?? 0) == 10 {
						$ts = $p
					}
					item = $items.get($p) ?? LayoutGsub.no_item
					category = item.mask.shr_zf_wrap(39).bitwise_and(63)
					lo = ShaperIndicData.indic_trans_keys.get($cs * 2) ?? 0
					hi = ShaperIndicData.indic_trans_keys.get($cs * 2 + 1) ?? 0
					span = ShaperIndicData.indic_key_spans.get($cs) ?? 0
					index = if span > 0 and category >= lo and category <= hi {
						category - lo
					} else {
						span
					}
					offset = ShaperIndicData.indic_index_offsets.get($cs) ?? 0
					$trans = ShaperIndicData.indic_indicies.get(offset + index) ?? 0
				}
				if !$done {
					$cs = ShaperIndicData.indic_trans_targs.get($trans) ?? 0
					action = ShaperIndicData.indic_trans_actions.get($trans) ?? 0
					var $next = $p + 1
					var $kind = 6
					if action == 2 {
						$te = $p + 1
					}
					else if action == 11 {
						$te = $p + 1
						$kind = 5
					} else if action == 14 or action == 15 or action == 18 or action == 20 or action == 16 or action == 17 {
						$te = $p
						$next = $p
						$kind = match action {
							14 => 0
							15 => 1
							18 => 2
							20 => 3
							16 => 4
							_ => 5
						}
					} else if action == 1 or action == 3 or action == 7 or action == 8 or action == 4 {
						$next = $te
						$kind = match action {
							1 => 0
							3 => 1
							7 => 2
							8 => 3
							_ => 4
						}
					} else if action == 6 {
						$next = $te
						$kind = if $act == 1 {
							0
						} else if $act == 6 {
							4
						} else {
							5
						}
					} else if action == 19 or action == 13 or action == 5 or action == 12 {
						$te = $p + 1
						$act = match action {
							19 => 1
							13 => 5
							5 => 6
							_ => 7
						}
					}
					if $kind != 6 {
						# Ragel emits disjoint nonempty spans inside the input.
						# Check defensively before any list index or subtraction.
						if $ts > $te or $te > n {
							$stopped = 2
						}
						else if $te - $ts > budget - $ops {
							$stopped = 2
						}
						else {
							$ops = $ops + ($te - $ts)
							syllable = ($serial * 16 + $kind).shl_wrap(49)
							for i in $ts..<$te {
								item = $items.get(i) ?? LayoutGsub.no_item
								$items = $items.set(i, { ..item, mask: item.mask.bitwise_and(0xFE01FFFFFFFFFFFF).bitwise_or(syllable) }) ?? []
							}
							if $te - $ts >= 2 and $te - $ts <= 255 {
								cluster = LayoutGsub.end_cluster($items, $ts, $te, 0xFFFFFFFFFFFFFFFF)
								$items = LayoutGsub.flag_range($items, $ts, $te, cluster)
							}
							$serial = if $serial == 15 {
								1
							} else {
								$serial + 1
							}
						}
					}
					if (ShaperIndicData.indic_to_state_actions.get($cs) ?? 0) == 9 {
						$ts = 0
					}
					$p = $next
				}
			}
		}
		{ items: $items, operations: $ops, stopped: $stopped }
	}
}

# These category streams isolate state-machine behavior from font shaping.
expect {
	items = [1, 4, 1, 7].map(|category| { ..LayoutGsub.no_item, mask: category.shl_wrap(39) })
	result = ShaperIndicMachine.run(items, 100)
	result.stopped == 0 and result.items.map(|item| item.mask.shr_zf_wrap(49).bitwise_and(255)) == [16, 16, 16, 16]
}
expect {
	items = [7, 0, 1].map(|category| { ..LayoutGsub.no_item, mask: category.shl_wrap(39) })
	result = ShaperIndicMachine.run(items, 100)
	result.stopped == 0 and result.items.map(|item| item.mask.shr_zf_wrap(49).bitwise_and(255)) == [20, 37, 48]
}
expect {
	result = ShaperIndicMachine.run([LayoutGsub.no_item], 0)
	result.stopped == 2 and result.operations == 0 and result.items.len() == 1
}
expect ShaperIndicMachine.run([], 0).stopped == 0
