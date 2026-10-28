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

import LayoutGsub
import ShaperIndicData
import ShaperIndic
import ShaperUnicode

## Exact pinned USE Ragel machine. A transition and each emitted item
## charge one unit; the caller shares this counter with all shaping stages.
ShaperUseMachine :: {}.{
	run : List(LayoutGsub.Item), U64 -> { items : List(LayoutGsub.Item), operations : U64, stopped : U64 }
	run = |items, budget| {
		original_n = items.len()
		if original_n > budget {
			return { items, operations: 0, stopped: 2 }
		}
		filtered = ShaperUseMachine.indices(items, budget)
		if filtered.stopped != 0 {
			return { items, operations: filtered.operations, stopped: filtered.stopped }
		}
		view = filtered.view
		n = view.count
		var $items = items
		var $p = 0
		var $ts = 0
		var $te = 0
		var $act = 0
		var $cs = ShaperIndicData.use_start
		var $serial = 1
		var $ops = filtered.operations
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
					eof = ShaperIndicData.use_eof_trans.get($cs) ?? 0
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
					if (ShaperIndicData.use_from_state_actions.get($cs) ?? 0) == 3 {
						$ts = $p
					}
					item = $items.get(ShaperUseMachine.raw_index(view, $p)) ?? LayoutGsub.no_item
					category = item.mask.shr_zf_wrap(39).bitwise_and(63)
					lo = ShaperIndicData.use_trans_keys.get($cs * 2) ?? 0
					hi = ShaperIndicData.use_trans_keys.get($cs * 2 + 1) ?? 0
					span = ShaperIndicData.use_key_spans.get($cs) ?? 0
					index = if span > 0 and category >= lo and category <= hi {
						category - lo
					} else {
						span
					}
					offset = ShaperIndicData.use_index_offsets.get($cs) ?? 0
					$trans = ShaperIndicData.use_indicies.get(offset + index) ?? 0
				}
				if !$done {
					$cs = ShaperIndicData.use_trans_targs.get($trans) ?? 0
					action = ShaperIndicData.use_trans_actions.get($trans) ?? 0
					var $next = $p + 1
					var $kind = 9
					if action == 7 {
						$te = $p + 1
					}
					else if action == 16 or action == 14 or action == 12 or action == 20 or action == 18 or action == 10 or action == 25 or action == 5 or action == 4 {
						$te = $p + 1
						$kind = match action {
							16 => 0
							14 => 1
							12 => 2
							20 => 3
							18 => 4
							10 => 5
							25 => 6
							5 => 7
							_ => 8
						}
					} else if action == 15 or action == 13 or action == 11 or action == 19 or action == 17 or action == 9 or action == 24 or action == 21 or action == 23 {
						$te = $p
						$next = $p
						$kind = match action {
							15 => 0
							13 => 1
							11 => 2
							19 => 3
							17 => 4
							9 => 5
							24 => 6
							21 => 7
							_ => 8
						}
					} else if action == 1 {
						$next = $te
						$kind = 5
					} else if action == 22 {
						$next = $te
						$kind = if $act == 8 {
							8
						} else {
							7
						}
					} else if action == 6 or action == 8 {
						$te = $p + 1
						$act = if action == 6 {
							8
						} else {
							9
						}
					}
					if $kind != 9 {
						# Ragel emits disjoint nonempty spans inside the input.
						# Check defensively before any list index or subtraction.
						raw_start = ShaperUseMachine.raw_index(view, $ts)
						raw_end = ShaperUseMachine.raw_index(view, $te)
						if $ts > $te or $te > n or raw_start > raw_end or raw_end > original_n {
							$stopped = 2
						}
						else if raw_end - raw_start > budget - $ops {
							$stopped = 2
						}
						else {
							$ops = $ops + (raw_end - raw_start)
							syllable = ($serial * 16 + $kind).shl_wrap(49)
							for i in raw_start..<raw_end {
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
					if (ShaperIndicData.use_to_state_actions.get($cs) ?? 0) == 2 {
						$ts = 0
					}
					$p = $next
				}
			}
		}
		# Mark every contiguous original span, including any leading/all
		# filtered CGJs with syllable0, as upstream foreach_syllable does.
		var $start = 0
		while $start < original_n and $stopped == 0 {
			id = ShaperIndic.syllable(($items.get($start) ?? LayoutGsub.no_item).mask)
			var $end = $start + 1
			while $end < original_n and $end - $start < 64 and ShaperIndic.syllable(($items.get($end) ?? LayoutGsub.no_item).mask) == id {
				$end = $end + 1
			}
			count = $end - $start
			if count > budget - $ops {
				$stopped = 2
			}
			else {
				$ops = $ops + count
				if count >= 2 and count <= 255 {
					cluster = LayoutGsub.end_cluster($items, $start, $end, 0xFFFFFFFFFFFFFFFF)
					$items = LayoutGsub.flag_range($items, $start, $end, cluster)
				}
			}
			$start = $end
		}
		{ items: $items, operations: $ops, stopped: $stopped }
	}
	View : { indices : List(U64), offset : U64, count : U64, filtered : Bool }
	raw_index : View, U64 -> U64
	raw_index = |view, i| if view.filtered {
		view.indices.get(view.offset + i) ?? 0
	} else {
		i
	}

	# CGJ is ignored by the syllable machine. ZWNJ is additionally
	# ignored when the next non-CGJ character is a Unicode mark. A single
	# reverse pass preserves that predicate without repeated lookahead.
	indices : List(LayoutGsub.Item), U64 -> { view : View, operations : U64, stopped : U64 }
	indices = |items, budget| {
		n = items.len()
		identity = { indices: [], offset: 0, count: n, filtered: False }
		if n > budget {
			{ view: identity, operations: 0, stopped: 2 }
		}
		else if !items.any(|item| ShaperIndic.cat(item) == 6 or ShaperIndic.cat(item) == 14) {
			{ view: identity, operations: n, stopped: 0 }
		}
		else if n > budget - n {
			{ view: identity, operations: n, stopped: 2 }
		}
		else {
			# n comes from the already allocated original Item list;
			# n+1 scalar indices are bounded before sizing allocation.
			var $indices = List.repeat(n, n + 1)
			var $cursor = n
			var $i = n
			var $next_mark = False
			while $i > 0 {
				$i = $i - 1
				item = items.get($i) ?? LayoutGsub.no_item
				category = ShaperIndic.cat(item)
				if category != 6 {
					if category != 14 or !$next_mark {
						$cursor = $cursor - 1
						$indices = $indices.set($cursor, $i) ?? []
					}
					$next_mark = ShaperUnicode.is_mark(item.props)
				}
			}
			{ view: { indices: $indices, offset: $cursor, count: n - $cursor, filtered: True }, operations: n + n, stopped: 0 }
		}
	}

}

expect {
	items = [1, 44].map(|category| { ..LayoutGsub.no_item, mask: category.shl_wrap(39) })
	result = ShaperUseMachine.run(items, 100)
	result.stopped == 0 and result.items.map(|item| ShaperIndic.syllable(item.mask)) == [16, 16]
}
expect {
	items = [33, 0, 1].map(|category| { ..LayoutGsub.no_item, mask: category.shl_wrap(39) })
	result = ShaperUseMachine.run(items, 100)
	result.stopped == 0 and result.items.map(|item| ShaperIndic.syllable(item.mask)) == [23, 37, 50]
}
expect {
	# CGJ filtering maps spans back to original item indices.
	items = [6, 1, 6, 44, 6].map(|category| { ..LayoutGsub.no_item, mask: category.shl_wrap(39) })
	result = ShaperUseMachine.run(items, 100)
	result.stopped == 0 and result.items.map(|item| ShaperIndic.syllable(item.mask)) == [0, 16, 16, 16, 16]
}
expect ShaperUseMachine.run([], 0).stopped == 0
