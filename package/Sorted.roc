## Sorting small lists of numbers deterministically, without the builtin
## sort.
##
## Internal. `List.sort_with` takes the first item as its pivot, so sorted
## and equal-key input, which fonts and shaped runs mostly give, costs
## quadratic time. This module checks order first (one pass), so increasing
## and decreasing input costs one pass and one list, and otherwise sorts by
## bottom-up merging: at most about 2 n log2 n comparisons and two lists of
## n numbers, whatever the input.
Sorted :: {}.{

	## The distinct values of a list, in increasing order.
	unique : List(U64) -> List(U64)
	unique = |values| {
		n = values.len()
		var $increasing = True
		var $decreasing = True
		var $k = 1
		while $k < n and ($increasing or $decreasing) {
			a = values.get($k - 1) ?? 0
			b = values.get($k) ?? 0
			if b < a {
				$increasing = False
			}
			if b > a {
				$decreasing = False
			}
			$k = $k + 1
		}
		if $increasing {
			Sorted.dedupe(values, False)
		} else if $decreasing {
			Sorted.dedupe(values, True)
		} else {
			Sorted.dedupe(Sorted.merge_sort(values), False)
		}
	}

	## Drop repeats from a list in order (increasing, or decreasing read
	## backwards when `backwards`), giving them in increasing order.
	dedupe : List(U64), Bool -> List(U64)
	dedupe = |values, backwards| {
		n = values.len()
		var $out = List.with_capacity(n)
		for i in 0..<n {
			v = values.get(if (backwards) n - 1 - i else i) ?? 0
			match $out.last() {
				Ok(last) if last == v => {}
				_ => {
					$out = $out.append(v)
				}
			}
		}
		$out
	}

	## The values in increasing order: runs of width 1, 2, 4, ... merged
	## from one list into the other until one run holds everything. Ties
	## keep their order (it does not matter for numbers).
	merge_sort : List(U64) -> List(U64)
	merge_sort = |values| {
		n = values.len()
		var $from = values
		var $width = 1
		while $width < n {
			var $to = List.with_capacity(n)
			var $start = 0
			while $start < n {
				middle = ($start + $width).min(n)
				end = ($start + 2 * $width).min(n)
				var $i = $start
				var $j = middle
				while $i < middle or $j < end {
					a = $from.get($i) ?? 0
					b = $from.get($j) ?? 0
					if $j >= end or ($i < middle and a <= b) {
						$to = $to.append(a)
						$i = $i + 1
					} else {
						$to = $to.append(b)
						$j = $j + 1
					}
				}
				$start = end
			}
			$from = $to
			$width = 2 * $width
		}
		$from
	}
}
