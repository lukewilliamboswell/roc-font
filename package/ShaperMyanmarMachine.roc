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
# Myanmar syllable machine adapted from HarfBuzz 14.6.0.
# hb-ot-shaper-myanmar-machine.hh, hb-ot-shaper-myanmar-machine.rl.

import LayoutGsub
import ShaperIndicData

## Exact pinned Myanmar Ragel machine. A transition and each emitted item
## charge one unit; the caller shares this counter with all shaping stages.
ShaperMyanmarMachine :: {}.{
	at : List(U64), U64 -> U64
	at = |values, index| match values.get(index) {
		Ok(value) => value
		Err(_) => crash "pinned Myanmar machine index became unavailable"
	}

	run : List(LayoutGsub.Item), U64 -> { items : List(LayoutGsub.Item), operations : U64, stopped : U64 }
	run = |items, budget| {
		n = items.len()
		var $items = items
		var $p = 0
		var $ts = 0
		var $te = 0
		var $act = 0
		var $cs = ShaperIndicData.myanmar_start
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
					eof = ShaperMyanmarMachine.at(ShaperIndicData.myanmar_eof_trans, $cs)
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
					if (ShaperMyanmarMachine.at(ShaperIndicData.myanmar_from_state_actions, $cs)) == 2 {
						$ts = $p
					}
					item = $items.get($p) ?? LayoutGsub.no_item
					category = item.mask.shr_zf_wrap(39).bitwise_and(63)
					lo = ShaperMyanmarMachine.at(ShaperIndicData.myanmar_trans_keys, $cs * 2)
					hi = ShaperMyanmarMachine.at(ShaperIndicData.myanmar_trans_keys, $cs * 2 + 1)
					span = ShaperMyanmarMachine.at(ShaperIndicData.myanmar_key_spans, $cs)
					index = if span > 0 and category >= lo and category <= hi {
						category - lo
					} else {
						span
					}
					offset = ShaperMyanmarMachine.at(ShaperIndicData.myanmar_index_offsets, $cs)
					$trans = ShaperMyanmarMachine.at(ShaperIndicData.myanmar_indicies, offset + index)
				}
				if !$done {
					$cs = ShaperMyanmarMachine.at(ShaperIndicData.myanmar_trans_targs, $trans)
					action = ShaperMyanmarMachine.at(ShaperIndicData.myanmar_trans_actions, $trans)
					var $next = $p + 1
					var $kind = 3
					if action == 8 or action == 4 or action == 10 or action == 3 {
						$te = $p + 1
						$kind = if action == 8 {
							0
						} else if action == 10 {
							1
						} else {
							2
						}
					} else if action == 7 or action == 9 or action == 12 {
						$te = $p
						$next = $p
						$kind = if action == 7 {
							0
						} else if action == 9 {
							1
						} else {
							2
						}
					} else if action == 11 {
						$next = $te
						$kind = if $act == 2 {
							2
						} else if $act == 3 {
							1
						} else {
							3
						}
					} else if action == 6 or action == 5 {
						$te = $p + 1
						$act = if action == 6 {
							2
						} else {
							3
						}
					}
					if $kind != 3 {
						# Ragel emits disjoint nonempty spans inside the input.
						# Check defensively before any list index or subtraction.
						if $ts >= $te or $te > n {
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

							# HB's foreach_syllable caps each visit at64,
							# even when Ragel assigned one serial to a
							# longer span. This also bounds unsafe flags.
							var $first = $ts
							while $first < $te and $stopped == 0 {
								last = $first + ($te - $first).min(64)
								if last - $first >= 2 {
									cost = 2 * (last - $first)
									if cost > budget - $ops {
										$stopped = 2
									} else {
										$ops = $ops + cost
										cluster = LayoutGsub.end_cluster($items, $first, last, 0xFFFFFFFFFFFFFFFF)
										$items = LayoutGsub.flag_range($items, $first, last, cluster)
									}
								}
								$first = last
							}
							$serial = if $serial == 15 {
								1
							} else {
								$serial + 1
							}
						}
					}
					if (ShaperMyanmarMachine.at(ShaperIndicData.myanmar_to_state_actions, $cs)) == 1 {
						$ts = 0
					}
					$p = $next
				}
			}
		}
		{ items: $items, operations: $ops, stopped: $stopped }
	}
}

expect {
	items = [1, 22, 20, 21].map(|category| { ..LayoutGsub.no_item, mask: category.shl_wrap(39) })
	result = ShaperMyanmarMachine.run(items, 100)
	result.stopped == 0 and result.items.map(|item| item.mask.shr_zf_wrap(49).bitwise_and(255)) == [16, 16, 16, 16]
}
expect {
	items = [22, 0, 1].map(|category| { ..LayoutGsub.no_item, mask: category.shl_wrap(39) })
	result = ShaperMyanmarMachine.run(items, 100)
	result.stopped == 0 and result.items.map(|item| item.mask.shr_zf_wrap(49).bitwise_and(255)) == [17, 34, 48]
}
expect ShaperMyanmarMachine.run([], 0).stopped == 0
expect ShaperMyanmarMachine.run([{ ..LayoutGsub.no_item, mask: (1.U64).shl_wrap(39) }], 0).stopped == 2
