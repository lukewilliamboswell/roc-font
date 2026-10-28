## Ordered saturating sums of positioning advances. A flat segment tree
## composes clamp(x + sum, low, high) transformations, preserving the order
## of mixed positive/negative advances without rescanning long spans.
## Internal: callers use the cheaper prefix-sum path for monotone advances.
PositionSum := { count : U64, nodes : List({ sum : I128, low : I64, high : I64 }) }.{
	Transform : { sum : I128, low : I64, high : I64 }
	identity : Transform
	identity = { sum: 0, low: -2147483648, high: 2147483647 }

	clamp : I128, I64, I64 -> I64
	clamp = |value, low, high| value.max(low.to_i128()).min(high.to_i128()).to_i64_wrap()

	then : Transform, Transform -> Transform
	then = |first, second| {
		sum: first.sum + second.sum,
		low: PositionSum.clamp(first.low.to_i128() + second.sum, second.low, second.high),
		high: PositionSum.clamp(first.high.to_i128() + second.sum, second.low, second.high),
	}

	make : List(I64) -> PositionSum
	make = |advances| {
		count = advances.len()
		# An I64 list's storage bounds its length below U64MAX/8; twice its
		# length cannot overflow. Index zero is unused; leaves occupy[n,2n).
		var $nodes = List.repeat(PositionSum.identity, 2 * count)
		for i in 0..<count {
			delta = advances.get(i) ?? crash "position sum input bounds"
			$nodes = $nodes.set(count + i, { sum: delta.to_i128(), low: -2147483648, high: 2147483647 }) ?? []
		}
		var $at = count
		while $at > 1 {
			$at = $at - 1
			left = $nodes.get(2 * $at) ?? crash "position sum left-child bounds"
			right = $nodes.get(2 * $at + 1) ?? crash "position sum right-child bounds"
			$nodes = $nodes.set($at, PositionSum.then(left, right)) ?? []
		}
		{ count, nodes: $nodes }
	}

	## Apply additions, or subtractions in the same input order. Empty
	## ranges return value unchanged. Bounds are an internal caller invariant.
	## I128 sums make even extreme accepted I64 advances safe to compose.
	apply : PositionSum, U64, U64, I64, Bool -> I64
	apply = |tree, start, end, value, subtract| {
		if start > end or end > tree.count {
			crash "position sum range bounds"
		}
		if start == end {
			return value
		}
		var $left = start + tree.count
		var $right = end + tree.count
		var $before = PositionSum.identity
		var $after = PositionSum.identity
		var $has_before = False
		var $has_after = False
		# Separate accumulators preserve left-to-right order in the compact2n
		# tree, including non-power-of-two lengths. No identity clamp is inserted
		# before the first real element, so all I64 starting values are defined.
		while $left < $right {
			if $left % 2 == 1 {
				node = tree.nodes.get($left) ?? crash "position sum query-left bounds"
				$before = if ($has_before) PositionSum.then($before, node) else node
				$has_before = True
				$left = $left + 1
			}
			if $right % 2 == 1 {
				$right = $right - 1
				node = tree.nodes.get($right) ?? crash "position sum query-right bounds"
				$after = if ($has_after) PositionSum.then(node, $after) else node
				$has_after = True
			}
			$left = $left // 2
			$right = $right // 2
		}
		transformation = if ($has_before and $has_after) PositionSum.then($before, $after) else if ($has_before) $before else if ($has_after) $after else crash "nonempty position sum lost all nodes"
		initial = if (subtract) -1 - value else value
		result = PositionSum.clamp(initial.to_i128() + transformation.sum, transformation.low, transformation.high)
		if (subtract) -1 - result else result
	}
}

naive_position_sum = |advances, start, end, value, subtract| {
	var $total = value.to_i128()
	for i in start..<end {
		delta = (advances.get(i) ?? 0.I64).to_i128()
		$total = (if (subtract) $total - delta else $total + delta).max(-2147483648).min(2147483647)
	}
	$total.to_i64_wrap()
}

# Exhaust every sequence up to four elements over five signed extremes,
# every range, both operations, and nine ordinary/extreme starting values.
expect {
	alphabet = [-2147483648.I64, -1, 0, 1, 2147483647]
	starts = [-9223372036854775808.I64, -2147483648, -2147483647, -1, 0, 1, 2147483646, 2147483647, 9223372036854775807]
	var $patterns = 1
	var $ok = True
	for count in 0..=4 {
		for code in 0..<$patterns {
			var $digits = code
			var $advances = List.with_capacity(count)
			for _ in 0..<count {
				$advances = $advances.append(alphabet.get($digits % alphabet.len()) ?? 0)
				$digits = $digits // alphabet.len()
			}
			tree = PositionSum.make($advances)
			for start in 0..=count {
				for end in start..=count {
					for value in starts {
						for subtract in [False, True] {
							if PositionSum.apply(tree, start, end, value, subtract) != naive_position_sum($advances, start, end, value, subtract) {
								$ok = False
							}
						}
					}
				}
			}
		}
		$patterns = $patterns * alphabet.len()
	}
	$ok
}

# Uneven tree lengths, noncommutative cancellation and full-I64 leaves.
expect {
	alphabet = [-9223372036854775808.I64, 9223372036854775807, -2147483648, 2147483647, -7, 3, 0]
	var $ok = True
	for count in 0..=33 {
		advances = List.repeat(0.I64, count).map_with_index(|_value, i| alphabet.get((i * 5 + count) % alphabet.len()) ?? 0)
		tree = PositionSum.make(advances)
		for start in 0..=count {
			for end in start..=count {
				for value in [-2147483648.I64, -1, 0, 1, 2147483647] {
					for subtract in [False, True] {
						if PositionSum.apply(tree, start, end, value, subtract) != naive_position_sum(advances, start, end, value, subtract) {
							$ok = False
						}
					}
				}
			}
		}
	}
	$ok
}
