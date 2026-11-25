import LayoutGsub
import ShaperIndicData
import ShaperUnicode

## Horizontal Hindi syllables for a modern Devanagari layout.
ShaperIndic := {}.{
	Plan : { ends : List(U64), reph : U64, half : U64, below : U64, above : U64, post : U64, init : U64, ra_below : Bool, dotted : [Present(LayoutGsub.Item), Absent] }

	## RVRN, early composition and localization, eleven basic form stages,
	## then presentation forms. Empty pauses use the same end index.
	final_stage : U64
	final_stage = 13

	# Categories use bits 50–53. Positions use bits 54–57. Both fields
	# survive GSUB along with the syllable identity and original cluster.
	category : LayoutGsub.Item -> U64
	category = |item| item.mask.shr_zf_wrap(50).bitwise_and(15)

	position : LayoutGsub.Item -> U64
	position = |item| item.mask.shr_zf_wrap(54).bitwise_and(15)

	with_position : LayoutGsub.Item, U64 -> LayoutGsub.Item
	with_position = |item, which| { ..item, mask: item.mask.bitwise_and(0xFC3FFFFFFFFFFFFF).bitwise_or(which.shl_wrap(54)) }

	## Assign the roles carried through GSUB. In Devanagari all matras
	## except the left matras follow subjoined consonants. RA, avagraha,
	## the Vedic accents in the block and digits have Indic-specific roles.
	set_properties : LayoutGsub.Item, U64 -> LayoutGsub.Item
	set_properties = |item, cp| {
		data = ShaperIndicData.properties(cp.to_u32_wrap()).to_u64()
		cat = match cp {
			0x0930 => 8
			0x093D => 7
			0x0951 | 0x0952 => 9
			0x0953 | 0x0954 => 6
			_ => match data.bitwise_and(15) {
				6 | 7 => 6
				13 => 10
				other => other
			}
		}
		pos = match cat {
			1 | 2 | 8 | 10 => 4
			3 => if (data.shr_zf_wrap(4) == 1) 2 else 9
			6 | 7 | 9 => 13
			_ => 14
		}
		ShaperIndic.with_position({ ..item, mask: item.mask.bitwise_or(cat.shl_wrap(50)) }, pos)
	}

	at : List(LayoutGsub.Item), U64 -> LayoutGsub.Item
	at = |items, index| items.get(index) ?? LayoutGsub.no_item

	cat_at : List(LayoutGsub.Item), U64 -> U64
	cat_at = |items, index| ShaperIndic.category(ShaperIndic.at(items, index))

	is_consonant : U64 -> Bool
	is_consonant = |cat| cat == 1 or cat == 8

	is_base : U64 -> Bool
	is_base = |cat| ShaperIndic.is_consonant(cat) or cat == 2 or cat == 10

	is_joiner : U64 -> Bool
	is_joiner = |cat| cat == 11 or cat == 12

	is_halant : LayoutGsub.Item -> Bool
	is_halant = |item| ShaperIndic.category(item) == 4 and LayoutGsub.gprops(item).bitwise_and(LayoutGsub.ligated) == 0

	# Optional immediately following nukta(s).
	nukta_end : List(LayoutGsub.Item), U64, U64 -> U64
	nukta_end = |items, start, count| {
		var $end = start
		while $end < start + count and ShaperIndic.cat_at(items, $end) == 5 {
			$end = $end + 1
		}
		$end
	}

	consonant_end : List(LayoutGsub.Item), U64 -> U64
	consonant_end = |items, start| {
		next = start + 1
		after_joiner = if (ShaperIndic.cat_at(items, next) == 11) next + 1 else next
		ShaperIndic.nukta_end(items, after_joiner, 2)
	}

	# A single syllable modifier group and any following accents.
	modifiers_end : List(LayoutGsub.Item), U64 -> U64
	modifiers_end = |items, start| {
		var $end = start
		sign = if (ShaperIndic.is_joiner(ShaperIndic.cat_at(items, $end))) $end + 1 else $end
		if ShaperIndic.cat_at(items, sign) == 6 {
			next = sign + 1
			after_signs = if (ShaperIndic.cat_at(items, next) == 6) next + 1 else next
			$end = if (ShaperIndic.cat_at(items, after_signs) == 12) after_signs + 1 else after_signs
		}
		while ShaperIndic.cat_at(items, $end) == 9 {
			$end = $end + 1
		}
		$end
	}

	# A halant links another consonant, or ends the consonant chain.
	# ZWNJ after a halant does not link the following consonant.
	tail_end : List(LayoutGsub.Item), U64 -> U64
	tail_end = |items, start| {
		var $end = start
		var $going = True
		while $going {
			halant = if (ShaperIndic.is_joiner(ShaperIndic.cat_at(items, $end))) $end + 1 else $end
			if ShaperIndic.cat_at(items, halant) != 4 {
				$going = False
			} else {
				next = halant + 1
				join = ShaperIndic.cat_at(items, next)
				if join == 12 {
					return ShaperIndic.modifiers_end(items, next + 1)
				}
				after_joiner = if (join == 11) ShaperIndic.nukta_end(items, next + 1, 1) else next
				if ShaperIndic.is_consonant(ShaperIndic.cat_at(items, after_joiner)) {
					$end = ShaperIndic.consonant_end(items, after_joiner)
				} else {
					return ShaperIndic.modifiers_end(items, after_joiner)
				}
			}
		}
		$going = True
		while $going {
			var $matra = $end
			while ShaperIndic.is_joiner(ShaperIndic.cat_at(items, $matra)) {
				$matra = $matra + 1
			}
			if ShaperIndic.cat_at(items, $matra) == 3 {
				next = ShaperIndic.nukta_end(items, $matra + 1, 1)
				$end = if (ShaperIndic.cat_at(items, next) == 4) next + 1 else next
			} else {
				$going = False
			}
		}
		ShaperIndic.modifiers_end(items, $end)
	}

	syllable_end : List(LayoutGsub.Item), U64 -> { end : U64, kind : U64 }
	syllable_end = |items, start| {
		first = ShaperIndic.cat_at(items, start)
		# In a vowel or standalone syllable, initial Ra–halant is a
		# prefix and cannot be the base.
		has_prefix = first == 8 and ShaperIndic.cat_at(items, start + 1) == 4
		candidate = if (has_prefix) ShaperIndic.cat_at(items, start + 2) else 0
		head = if (candidate == 2 or candidate == 10) start + 2 else start
		cat = ShaperIndic.cat_at(items, head)
		if ShaperIndic.is_consonant(cat) {
			{ end: ShaperIndic.tail_end(items, ShaperIndic.consonant_end(items, head)), kind: 1 }
		} else if cat == 2 or cat == 10 {
			next = ShaperIndic.nukta_end(items, head + 1, 2)
			end = if (cat == 2 and ShaperIndic.cat_at(items, next) == 11) next + 1 else ShaperIndic.tail_end(items, next)
			{ end, kind: 1 }
		} else if cat == 7 {
			{ end: ShaperIndic.modifiers_end(items, ShaperIndic.nukta_end(items, head + 1, 1)), kind: 3 }
		} else if cat != 0 {
			end = ShaperIndic.tail_end(items, ShaperIndic.nukta_end(items, start, 2))
			if (end > start) { end, kind: 2 } else { end: start + 1, kind: 0 }
		} else {
			{ end: start + 1, kind: 0 }
		}
	}

	## Use serials 1 through 15 as in HarfBuzz. Adjacent syllables have
	## different serials, which stops a lookup at the first boundary.
	syllables : List(LayoutGsub.Item) -> List(LayoutGsub.Item)
	syllables = |items| {
		count = items.len()
		var $items = items
		var $start = 0
		var $serial = 1
		while $start < count {
			{ end, kind } = ShaperIndic.syllable_end($items, $start)
			id = $serial * 16 + kind
			for i in $start..<end {
				item = ShaperIndic.at($items, i)
				$items = $items.set(i, LayoutGsub.with_syllable(item, id)) ?? []
			}
			if end > $start + 1 {
				$items = LayoutGsub.flag_range($items, $start, end, LayoutGsub.end_cluster($items, $start, end, U64.highest))
			}
			$serial = if ($serial == 15) 1 else $serial + 1
			$start = end
		}
		$items
	}

	end_of : List(LayoutGsub.Item), U64, U64, U64 -> U64
	end_of = |items, start, id, len| {
		var $end = start + 1
		while $end < len and LayoutGsub.syllable(ShaperIndic.at(items, $end)) == id {
			$end = $end + 1
		}
		$end
	}

	# The last ordinary consonant is the main base. For this modern face
	# Ra may have a below-base form. A ZWJ after the halant keeps explicit
	# half-form requests from forcing a base on the left.
	base_of : List(LayoutGsub.Item), U64, U64, Bool -> U64
	base_of = |items, start, end, ra_below| {
		var $base = end
		var $i = end
		while $i > start {
			$i = $i - 1
			cat = ShaperIndic.cat_at(items, $i)
			if ShaperIndic.is_base(cat) {
				$base = $i
				if !ra_below or cat != 8 {
					return $i
				}
			} else if cat == 11 and $i > start and ShaperIndic.cat_at(items, $i - 1) == 4 {
				return $base
			}
		}
		$base
	}

	# A missing dotted-circle glyph leaves broken clusters intact.
	# Reserve room for the original glyphs before inserting anything.
	dotted_circles : List(LayoutGsub.Item), U64, [Present(LayoutGsub.Item), Absent] -> { items : List(LayoutGsub.Item), stopped : U64 }
	dotted_circles = |items, limit, dotted| {
		circle = match dotted {
			Absent => return { items, stopped: 0 }
			Present(glyph) => ShaperIndic.set_properties(glyph, 0x25CC)
		}
		if !items.any(|item| LayoutGsub.syllable(item) % 16 == 2) {
			return { items, stopped: 0 }
		}
		n = items.len()
		var $out = List.with_capacity(n)
		var $prev = 0
		var $added = 0
		var $stopped = 0
		for item in items {
			id = LayoutGsub.syllable(item)
			if id != $prev and id % 16 == 2 {
				if n + $added < limit {
					mask = circle.mask.bitwise_or(item.mask.bitwise_and(LayoutGsub.unsafe))
					$out = $out.append(LayoutGsub.with_syllable({ ..circle, cluster: item.cluster, mask }, id))
					$added = $added + 1
				} else {
					$stopped = LayoutGsub.stopped_growth
				}
			}
			$out = $out.append(item)
			$prev = id
		}
		{ items: $out, stopped: $stopped }
	}

	# Set positions and basic-form masks, then emit in stable position
	# order. A fixed number of position classes bounds the sorting work.
	initial : List(LayoutGsub.Item), Plan -> List(LayoutGsub.Item)
	initial = |items, p| {
		n = items.len()
		var $info = items
		var $out = List.with_capacity(n)
		var $start = 0
		while $start < n {
			first = ShaperIndic.at($info, $start)
			id = LayoutGsub.syllable(first)
			kind = id % 16
			end = ShaperIndic.end_of($info, $start, id, n)
			if end > $start + 1 and (kind == 1 or (kind == 2 and ShaperIndic.category(first) == 10)) {
				reph_candidate = p.reph != 0 and end - $start >= 3 and ShaperIndic.category(first) == 8
					and ShaperIndic.cat_at($info, $start + 1) == 4 and !ShaperIndic.is_joiner(ShaperIndic.cat_at($info, $start + 2))
				search = if (reph_candidate) $start + 2 else $start
				picked = ShaperIndic.base_of($info, search, end, p.ra_below)
				reph = reph_candidate and picked < end
				base = if (reph_candidate and !reph) $start else picked
				var $pos = 0
				var $not_matra = 0
				var $previous_base = base
				for i in $start..<end {
					item = ShaperIndic.at($info, i)
					cat = ShaperIndic.category(item)
					pos = if reph and i < $start + 2 {
						1
					} else if cat == 4 and $pos == 2 {
						$not_matra
					} else if cat == 4 or cat == 5 or ShaperIndic.is_joiner(cat) {
						$pos
					} else if i == base {
						4
					} else if i < base {
						ShaperIndic.position(item).min(3)
					} else if cat == 8 and p.ra_below {
						8
					} else {
						ShaperIndic.position(item)
					}
					if i > base and (ShaperIndic.is_base(cat) or cat == 3) {
						if ShaperIndic.is_base(cat) {
							for j in ($previous_base + 1)..<i {
								prior = ShaperIndic.at($info, j)
								if ShaperIndic.position(prior) < 13 {
									$info = $info.set(j, ShaperIndic.with_position(prior, pos)) ?? []
								}
							}
						}
						$previous_base = i
					}
					if pos != 13 {
						$pos = pos
						if pos != 2 {
							$not_matra = pos
						}
					}
					$info = $info.set(i, ShaperIndic.with_position(item, pos)) ?? []
				}
				for pos in 0..<15 {
					for i in $start..<end {
						item = ShaperIndic.at($info, i)
						if ShaperIndic.position(item) == pos {
							masks = if pos == 1 {
								p.reph.bitwise_or(p.half).bitwise_or(p.below)
							} else if pos < 4 {
								p.half.bitwise_or(p.below)
							} else if pos > 4 {
								p.below.bitwise_or(p.above).bitwise_or(p.post)
							} else {
								0
							}
							$out = $out.append({ ..item, mask: item.mask.bitwise_or(masks) })
						}
					}
				}
			} else {
				for i in $start..<end {
					$out = $out.append(ShaperIndic.at($info, i))
				}
			}
			$start = end
		}
		$out
	}

	merge_clusters : List(LayoutGsub.Item), U64, U64 -> List(LayoutGsub.Item)
	merge_clusters = |items, start, end| {
		var $items = items
		cluster = LayoutGsub.min_cluster($items, start, end, U64.highest)
		for i in start..<end {
			item = ShaperIndic.at($items, i)
			$items = $items.set(i, LayoutGsub.set_cluster(item, cluster)) ?? []
		}
		$items
	}

	# Move the left-matra block after an explicit halant before the main
	# base, when no ZWJ follows that halant. Otherwise it stays at the left.
	final_syllable : List(LayoutGsub.Item), U64, U64 -> List(LayoutGsub.Item)
	final_syllable = |items, start, end| {
		var $items = items
		var $base = start
		while $base < end and ShaperIndic.position(ShaperIndic.at($items, $base)) < 4 {
			$base = $base + 1
		}
		if $base < end and $base > start and ShaperIndic.position(ShaperIndic.at($items, $base)) > 4 {
			$base = $base - 1
		}
		var $first_matra = start
		while $first_matra < $base and ShaperIndic.position(ShaperIndic.at($items, $first_matra)) != 2 {
			$first_matra = $first_matra + 1
		}
		if $first_matra < $base {
			var $last_matra = $first_matra + 1
			while $last_matra < $base and ShaperIndic.position(ShaperIndic.at($items, $last_matra)) == 2 {
				$last_matra = $last_matra + 1
			}
			var $target = $base
			while $target > $last_matra and !ShaperIndic.is_halant(ShaperIndic.at($items, $target - 1)) {
				$target = $target - 1
			}
			if $target > $last_matra and ShaperIndic.cat_at($items, $target) != 11 {
				if ShaperIndic.cat_at($items, $target) == 12 {
					$target = $target + 1
				}
				$items = ShaperIndic.rotate($items, $first_matra, $last_matra, $target)
				$first_matra = $target - ($last_matra - $first_matra)
			}
			$items = ShaperIndic.merge_clusters($items, $first_matra, ($base + 1).min(end))
		}
		first = ShaperIndic.at($items, start)
		if end > start + 1 and ShaperIndic.position(first) == 1 and LayoutGsub.gprops(first).bitwise_and(LayoutGsub.ligated.bitwise_or(LayoutGsub.multiplied)) == LayoutGsub.ligated {
			# Use the first standalone halant before the base, else the
			# last non-modifier position, as for Devanagari reph.
			var $target = start + 1
			while $target < $base and !ShaperIndic.is_halant(ShaperIndic.at($items, $target)) {
				$target = $target + 1
			}
			if $target < $base {
				if $target + 1 < $base and ShaperIndic.is_joiner(ShaperIndic.cat_at($items, $target + 1)) {
					$target = $target + 1
				}
			} else {
				$target = end - 1
				while $target > start and ShaperIndic.position(ShaperIndic.at($items, $target)) == 13 {
					$target = $target - 1
				}
			}
			$items = ShaperIndic.merge_clusters($items, start, $target + 1)
			$items = ShaperIndic.rotate($items, start, start + 1, $target + 1)
		}
		$items
	}

	rotate : List(LayoutGsub.Item), U64, U64, U64 -> List(LayoutGsub.Item)
	rotate = |items, start, middle, end| {
		with_first = ShaperIndic.reverse(items, start, middle)
		with_both = ShaperIndic.reverse(with_first, middle, end)
		ShaperIndic.reverse(with_both, start, end)
	}

	reverse : List(LayoutGsub.Item), U64, U64 -> List(LayoutGsub.Item)
	reverse = |items, start, end| {
		var $items = items
		for i in 0..<((end - start) // 2) {
			left = start + i
			right = end - 1 - i
			a = ShaperIndic.at($items, left)
			b = ShaperIndic.at($items, right)
			$items = $items.set(left, b) ?? []
			$items = $items.set(right, a) ?? []
		}
		$items
	}

	## Final ordering sees which half and reph forms GSUB actually made.
	## Keep the same syllable identity until presentation lookups finish.
	finish : List(LayoutGsub.Item), Plan -> List(LayoutGsub.Item)
	finish = |items, p| {
		n = items.len()
		var $items = items
		var $start = 0
		while $start < n {
			id = LayoutGsub.syllable(ShaperIndic.at($items, $start))
			end = ShaperIndic.end_of($items, $start, id, n)
			if end > $start + 1 and (id % 16 == 1 or id % 16 == 2) {
				$items = ShaperIndic.final_syllable($items, $start, end)
			}
			first = ShaperIndic.at($items, $start)
			if ShaperIndic.position(first) == 2 {
				prior = if ($start > 0) ShaperUnicode.general_category_of(ShaperIndic.at($items, $start - 1).props) else ShaperUnicode.control
				if prior >= ShaperUnicode.format and prior <= ShaperUnicode.non_spacing_mark {
					$items = LayoutGsub.flag_range($items, $start - 1, $start + 1, LayoutGsub.end_cluster($items, $start - 1, $start + 1, U64.highest))
				} else if p.init != 0 {
					$items = $items.set($start, { ..first, mask: first.mask.bitwise_or(p.init) }) ?? []
				}
			}
			$start = end
		}
		$items
	}

	apply : LayoutGsub, List(LayoutGsub.Step), List(LayoutGsub.Item), LayoutGsub.Limits, Plan -> { items : List(LayoutGsub.Item), stopped : U64 }
	apply = |gsub, steps, items, limits, plan| {
		rvrn_end = plan.ends.get(0) ?? 0
		locl_end = plan.ends.get(1) ?? rvrn_end
		basic_end = plan.ends.get(ShaperIndic.final_stage - 1) ?? locl_end
		rvrn = LayoutGsub.apply_steps(gsub, steps, 0, rvrn_end, items, limits, LayoutGsub.initial_progress)
		syllabified = ShaperIndic.syllables(rvrn.items)
		localized = LayoutGsub.apply_steps(gsub, steps, rvrn_end, locl_end, syllabified, limits, rvrn.progress)
		repaired = ShaperIndic.dotted_circles(localized.items, limits.limit, plan.dotted)
		reordered = ShaperIndic.initial(repaired.items, plan)
		basic = LayoutGsub.apply_steps(gsub, steps, locl_end, basic_end, reordered, limits, localized.progress)
		ordered = ShaperIndic.finish(basic.items, plan)
		presented = LayoutGsub.apply_steps(gsub, steps, basic_end, steps.len(), ordered, limits, basic.progress)
		{ items: presented.items, stopped: presented.progress.stopped.bitwise_or(repaired.stopped) }
	}
}
