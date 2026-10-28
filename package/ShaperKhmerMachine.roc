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

## Exact pinned Khmer Ragel machine. A transition and each emitted item
## charge one unit; the caller shares this counter with all shaping stages.
ShaperKhmerMachine :: {}.{
	run : List(LayoutGsub.Item), U64 -> { items : List(LayoutGsub.Item), operations : U64, stopped : U64 }
	run = |items, budget| {
		n = items.len()
		var $items = items
		var $p = 0
		var $ts = 0
		var $te = 0
		var $act = 0
		var $cs = ShaperIndicData.khmer_start
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
					eof = ShaperIndicData.khmer_eof_trans.get($cs) ?? 0
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
					if (ShaperIndicData.khmer_from_state_actions.get($cs) ?? 0) == 7 {
						$ts = $p
					}
					item = $items.get($p) ?? LayoutGsub.no_item
					category = item.mask.shr_zf_wrap(39).bitwise_and(63)
					lo = ShaperIndicData.khmer_trans_keys.get($cs * 2) ?? 0
					hi = ShaperIndicData.khmer_trans_keys.get($cs * 2 + 1) ?? 0
					span = ShaperIndicData.khmer_key_spans.get($cs) ?? 0
					index = if span > 0 and category >= lo and category <= hi {
						category - lo
					} else {
						span
					}
					offset = ShaperIndicData.khmer_index_offsets.get($cs) ?? 0
					$trans = ShaperIndicData.khmer_indicies.get(offset + index) ?? 0
				}
				if !$done {
					$cs = ShaperIndicData.khmer_trans_targs.get($trans) ?? 0
					action = ShaperIndicData.khmer_trans_actions.get($trans) ?? 0
					var $next = $p + 1
					var $kind = 3
					if action == 2 {
						$te = $p + 1
					}
					else if action == 8 {
						$te = $p + 1
						$kind = 2
					} else if action == 10 or action == 11 or action == 12 {
						$te = $p
						$next = $p
						$kind = match action {
							10 => 0
							11 => 1
							_ => 2
						}
					} else if action == 1 or action == 3 {
						$next = $te
						$kind = if action == 1 {
							0
						} else {
							1
						}
					} else if action == 5 {
						$next = $te
						$kind = if $act == 2 {
							1
						} else {
							2
						}
					} else if action == 4 or action == 9 {
						$te = $p + 1
						$act = if action == 4 {
							2
						} else {
							3
						}
					}
					if $kind != 3 {
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
							$serial = if $serial == 15 {
								1
							} else {
								$serial + 1
							}
						}
					}
					if (ShaperIndicData.khmer_to_state_actions.get($cs) ?? 0) == 6 {
						$ts = 0
					}
					$p = $next
				}
			}
		}
		# HB foreach_syllable splits a raw DFA id into at most64 items.
		# Keep DFA ids unchanged, but mark each bounded callback span.
		var $start = 0
		while $start < n and $stopped == 0 {
			id = ($items.get($start) ?? LayoutGsub.no_item).mask.shr_zf_wrap(49).bitwise_and(255)
			var $end = $start + 1
			while $end < n and $end - $start < 64 and ($items.get($end) ?? LayoutGsub.no_item).mask.shr_zf_wrap(49).bitwise_and(255) == id {
				$end = $end + 1
			}
			count = $end - $start
			if count > budget - $ops {
				$stopped = 2
			}
			else {
				$ops = $ops + count
				if count >= 2 {
					cluster = LayoutGsub.end_cluster($items, $start, $end, 0xFFFFFFFFFFFFFFFF)
					$items = LayoutGsub.flag_range($items, $start, $end, cluster)
				}
			}
			$start = $end
		}
		{ items: $items, operations: $ops, stopped: $stopped }
	}
}

expect {
	items = [1, 4, 15, 22].map(|category| { ..LayoutGsub.no_item, mask: category.shl_wrap(39) })
	result = ShaperKhmerMachine.run(items, 100)
	result.stopped == 0 and result.items.map(|item| item.mask.shr_zf_wrap(49).bitwise_and(255)) == [16, 16, 16, 16]
}
expect {
	items = [22, 0, 1].map(|category| { ..LayoutGsub.no_item, mask: category.shl_wrap(39) })
	result = ShaperKhmerMachine.run(items, 100)
	result.stopped == 0 and result.items.map(|item| item.mask.shr_zf_wrap(49).bitwise_and(255)) == [17, 34, 48]
}
expect ShaperKhmerMachine.run([], 0).stopped == 0

expect {
	var $items = List.with_capacity(130)
	for i in 0..<130 {
		$items = $items.append({
			..LayoutGsub.no_item,
			glyph: i,
			cluster: i,
			mask: (
				if i % 2 == 0 {
					1.U64
				} else {
					4.U64
				}
			).shl_wrap(39),
		})
	}
	result = ShaperKhmerMachine.run($items, 10000)
	flags = result.items.map(|item| item.mask.bitwise_and(LayoutGsub.unsafe) != 0)
	result.stopped == 0 and flags.get(0) == Ok(False) and flags.get(63) == Ok(True) and flags.get(64) == Ok(False) and flags.get(65) == Ok(True) and flags.get(128) == Ok(False) and flags.get(129) == Ok(True)
}
