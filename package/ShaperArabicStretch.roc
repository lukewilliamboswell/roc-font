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

import Face
import LayoutGsub
import ShaperUnicode

## The Arabic/Syriac stch postprocessor: fixed and repeating font tiles
## fill the preceding word. All measurements stay in font units.
ShaperArabicStretch :: {}.{
	Placed : { items : List(LayoutGsub.Item), ax : List(I64), dx : List(I64), dy : List(I64) }
	Segment : { start : U64, end : U64, context : U64, copies : U64, remaining : I64, overlap : I64 }
	action : LayoutGsub.Item -> U64
	action = |item| item.mask.shr_zf_wrap(57).bitwise_and(3)

	record : List(LayoutGsub.Item) -> List(LayoutGsub.Item)
	record = |items| {
		var $items = items
		for i in 0..<$items.len() {
			item = $items.get(i) ?? LayoutGsub.no_item
			if LayoutGsub.gprops(item).bitwise_and(LayoutGsub.multiplied) != 0 {
				tile_action = if (LayoutGsub.lig_comp(item).bitwise_and(1) == 0) 1 else 2
				$items = $items.set(i, { ..item, mask: item.mask.bitwise_and(0xF9FFFFFFFFFFFFFF).bitwise_or(tile_action.shl_wrap(57)) }) ?? []
			}
		}
		$items
	}

	word : LayoutGsub.Item -> Bool
	word = |item| {
		gc = ShaperUnicode.general_category_of(item.props)
		LayoutGsub.is_default_ignorable(item) or gc == 2 or gc == 3 or gc == 6 or gc == 7 or (gc >= 10 and gc <= 15) or (gc >= 23 and gc <= 26)
	}

	sat : I64 -> I64
	sat = |n| n.max(-2147483648).min(2147483647)

	reverse : Placed -> Placed
	reverse = |p| { items: ShaperArabicStretch.reversed(p.items), ax: ShaperArabicStretch.reversed(p.ax), dx: ShaperArabicStretch.reversed(p.dx), dy: ShaperArabicStretch.reversed(p.dy) }

	reversed : List(a) -> List(a)
	reversed = |list| {
		n = list.len()
		var $out = List.with_capacity(n)
		for i in 0..<n {
			$out = $out.append(list.get(n - 1 - i) ?? crash "reverse bounds")
		}
		$out
	}

	apply : Face, Face.Location, Placed, Bool, U64, U64 -> { placed : Placed, operations : U64, stopped : U64 }
	apply = |face, location, placed, rtl, limit, budget| {
		if !placed.items.any(|item| ShaperArabicStretch.action(item) != 0) {
			return { placed, operations: 0, stopped: 0 }
		}
		run = if (rtl) placed else ShaperArabicStretch.reverse(placed)
		count = run.items.len()
		var $segments = []
		var $extra = 0
		var $operations = 0
		var $at = count
		var $stopped = 0
		while $at > 0 and $stopped == 0 {
			if $operations >= budget {
				$stopped = 2
			} else {
				$operations = $operations + 1
				item = run.items.get($at - 1) ?? LayoutGsub.no_item
				if ShaperArabicStretch.action(item) == 0 {
					$at = $at - 1
				} else {
					end = $at
					var $fixed = 0.I64
					var $repeating = 0.I64
					var $n_repeating = 0.U64
					while $at > 0 and ShaperArabicStretch.action(run.items.get($at - 1) ?? LayoutGsub.no_item) != 0 and $stopped == 0 {
						if $operations >= budget {
							$stopped = 2
						} else {
							$operations = $operations + 1
							$at = $at - 1
							tile = run.items.get($at) ?? LayoutGsub.no_item
							width = Face.advance(face, location, tile.glyph).to_i64()
							if ShaperArabicStretch.action(tile) == 1 {
								$fixed = ShaperArabicStretch.sat($fixed + width)
							} else {
								$repeating = ShaperArabicStretch.sat($repeating + width)
								$n_repeating = $n_repeating + 1
							}
						}
					}
					start = $at
					var $context = start
					var $total = 0.I64
					while $context > 0 and ShaperArabicStretch.action(run.items.get($context - 1) ?? LayoutGsub.no_item) == 0 and ShaperArabicStretch.word(run.items.get($context - 1) ?? LayoutGsub.no_item) and $stopped == 0 {
						if $operations >= budget {
							$stopped = 2
						} else {
							$operations = $operations + 1
							$context = $context - 1
							$total = ShaperArabicStretch.sat($total + (run.ax.get($context) ?? 0))
						}
					}
					signed_remaining = $total - $fixed
					var $remaining = ShaperArabicStretch.sat(signed_remaining)
					var $copies = 0.U64
					if signed_remaining > $repeating and $repeating > 0 {
						$copies = (signed_remaining // $repeating).to_u64_wrap() - 1
					}
					var $overlap = 0.I64
					shortfall = signed_remaining - $repeating * ($copies + 1).to_i64_wrap()
					if shortfall > 0 and $n_repeating > 0 {
						$copies = $copies + 1
						excess = ($copies + 1).to_i64_wrap() * $repeating - signed_remaining
						if excess > 0 {
							$overlap = ShaperArabicStretch.sat(excess // ($copies * $n_repeating).to_i64_wrap())
							$remaining = 0
						}
					}
					base_count = end - start
					max_copies = if ($n_repeating > 0 and base_count < 256) (256 - base_count) // $n_repeating else 0
					$copies = $copies.min(max_copies)
					added = $copies * $n_repeating
					if added > limit or count + $extra > limit - added {
						$stopped = $stopped.bitwise_or(1)
					} else {
						$extra = $extra + added
						$segments = $segments.append({ start, end, context: $context, copies: $copies, remaining: $remaining, overlap: $overlap })
					}
				}
			}
		}
		# Preflight the entire emission and flagging work before allocating or
		# mutating: budget exhaustion leaves an index-aligned original run.
		var $flag_work = 0
		for segment in $segments {
			if segment.end - segment.context <= 255 {
				$flag_work = $flag_work + segment.end - segment.context
			}
		}
		needed = count + $extra + $flag_work
		if $stopped != 0 or needed > budget - $operations {
			return { placed, operations: $operations, stopped: $stopped.bitwise_or(if (needed > budget - $operations) 2 else 0) }
		}
		{ items, ax, dx, dy } = run
		var $items = items
		var $out_items = List.repeat(LayoutGsub.no_item, count + $extra)
		var $out_ax = List.repeat(0.I64, count + $extra)
		var $out_dx = List.repeat(0.I64, count + $extra)
		var $out_dy = List.repeat(0.I64, count + $extra)
		var $i = count
		var $j = count + $extra
		var $segment = 0
		while $i > 0 {
			seg = $segments.get($segment) ?? { start: 0, end: 0, context: 0, copies: 0, remaining: 0, overlap: 0 }
			if $segment < $segments.len() and $i == seg.end {
				if seg.end - seg.context <= 255 {
					var $minimum = 0xFFFFFFFFFFFFFFFF
					for k in seg.context..<seg.end {
						$minimum = $minimum.min(($items.get(k) ?? LayoutGsub.no_item).cluster)
					}
					for k in seg.context..<seg.end {
						info = $items.get(k) ?? LayoutGsub.no_item
						if info.cluster != $minimum {
							$items = $items.set(k, { ..info, mask: info.mask.bitwise_or(LayoutGsub.unsafe) }) ?? []
						}
					}
				}
				var $offset = seg.remaining // 2
				var $k = seg.end
				while $k > seg.start {
					$k = $k - 1
					tile = $items.get($k) ?? LayoutGsub.no_item
					width = Face.advance(face, location, tile.glyph).to_i64()
					repeat = if (ShaperArabicStretch.action(tile) == 2) 1 + seg.copies else 1
					for n in 0..<repeat {
						if rtl {
							$offset = ShaperArabicStretch.sat($offset - width)
							if n > 0 {
								$offset = ShaperArabicStretch.sat($offset + seg.overlap)
							}
						}
						$j = $j - 1
						$out_items = $out_items.set($j, tile) ?? []
						$out_dx = $out_dx.set($j, $offset) ?? []
						$out_dy = $out_dy.set($j, dy.get($k) ?? 0) ?? []
						if !rtl {
							$offset = ShaperArabicStretch.sat($offset + width)
							if n > 0 {
								$offset = ShaperArabicStretch.sat($offset - seg.overlap)
							}
						}
					}
				}
				$i = seg.start
				$segment = $segment + 1
			} else {
				$i = $i - 1
				$j = $j - 1
				$out_items = $out_items.set($j, $items.get($i) ?? LayoutGsub.no_item) ?? []
				$out_ax = $out_ax.set($j, ax.get($i) ?? 0) ?? []
				$out_dx = $out_dx.set($j, dx.get($i) ?? 0) ?? []
				$out_dy = $out_dy.set($j, dy.get($i) ?? 0) ?? []
			}
		}
		output = { items: $out_items, ax: $out_ax, dx: $out_dx, dy: $out_dy }
		{ placed: if (rtl) output else ShaperArabicStretch.reverse(output), operations: $operations + needed, stopped: 0 }
	}
}

# Tile metadata is independent of feature masks and trace origins.
expect {
	items = [0.U64, 1, 2, 3, 4].map(|component| { glyph: 20 + component, cluster: 7, mask: 0x401, props: LayoutGsub.multiplied.shl_wrap(16).bitwise_or(component.shl_wrap(32)).bitwise_or((13.U64).shl_wrap(44)) })
	recorded = ShaperArabicStretch.record(items)
	recorded.map(ShaperArabicStretch.action) == [1, 2, 1, 2, 1] and recorded.map(|i| i.mask.bitwise_and(0xFFFFFFFF)) == List.repeat(0x401, 5) and recorded.map(|i| i.props) == items.map(|i| i.props)
}
expect ShaperArabicStretch.sat(2147483648) == 2147483647 and ShaperArabicStretch.sat(-2147483649) == -2147483648

# Integer centering truncates negative halves, as
# hb_position_t division does. Stretch tiles may exceed a short word.
expect (-3.I64 // 2) == -1
