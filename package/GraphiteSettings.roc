import Bytes
import Sorted

## Shared Graphite setting arrays may overlap. Merge their source spans by
## byte alignment before parsing, so preparation visits each source position
## once and never expands repeated language/feature records quadratically.
GraphiteSettings := { ranges : List(PoolSpan), count : U64, stride : U64, length : U64 }.{
	Span : { start : U32, count : U16 }
	PoolSpan : { start : U64, end : U64, pool : U64 }
	Maximum : { nodes : List(U16), leaves : U64, length : U64 }

	make : List(Span), U64, [Feature, Language] -> Try(GraphiteSettings, [Bad(U64)])
	make = |spans, length, kind| {
		stride = if (kind == Feature) 4 else 8
		var $keys = List.with_capacity(spans.len())
		for span in spans {
			start = span.start.to_u64()
			if !Bytes.fits(start, span.count.to_u64() * stride, length) {
				return Err(Bad(start))
			}
			if span.count != 0 {
				$keys = $keys.append((start % stride).shl_wrap(60).bitwise_or(start.shl_wrap(16)).bitwise_or(span.count.to_u64()))
			}
		}
		var $ranges = []
		for key in Sorted.unique($keys) {
			start = key.shr_zf_wrap(16).bitwise_and(0xFFFFFFFF)
			end = start + key.bitwise_and(65535) * stride
			last = $ranges.last() ?? { start: 0, end: 0, pool: 0 }
			if !$ranges.is_empty() and last.start % stride == start % stride and start <= last.end {
				$ranges = $ranges.set($ranges.len() - 1, { ..last, end: last.end.max(end) }) ?? []
			} else {
				$ranges = $ranges.append({ start, end, pool: 0 })
			}
		}
		var $count = 0
		for i in 0..<$ranges.len() {
			range = $ranges.get(i) ?? crash "prepared range index"
			$ranges = $ranges.set(i, { ..range, pool: $count }) ?? []
			$count = $count + (range.end - range.start) // stride
		}
		# Ranges of one residue are disjoint, and residues name distinct byte
		# positions. Thus even overlapping records allocate at most length cells.
		if $count > length {
			return Err(Bad(length))
		}
		Ok({ ranges: $ranges, count: $count, stride, length })
	}

	locate : GraphiteSettings, Span -> [Found({ start : U64, end : U64 }), Missing]
	locate = |map, span| {
		start = span.start.to_u64()
		if !Bytes.fits(start, span.count.to_u64() * map.stride, map.length) {
			return Missing
		}
		if span.count == 0 {
			return Found({ start: 0, end: 0 })
		}
		key = (start % map.stride).shl_wrap(32).bitwise_or(start)
		var $lo = 0
		var $hi = map.ranges.len()
		while $lo < $hi {
			mid = $lo + ($hi - $lo) // 2
			range = map.ranges.get(mid) ?? crash "bounded range search"
			there = (range.start % map.stride).shl_wrap(32).bitwise_or(range.start)
			if there <= key {
				$lo = mid + 1
			} else {
				$hi = mid
			}
		}
		if $lo == 0 {
			return Missing
		}
		range = map.ranges.get($lo - 1) ?? crash "bounded preceding range"
		if range.start % map.stride != start % map.stride or start < range.start or start + span.count.to_u64() * map.stride > range.end {
			return Missing
		}
		first = range.pool + (start - range.start) // map.stride
		Found({ start: first, end: first + span.count.to_u64() })
	}

	make_maximum : List(I16) -> Maximum
	make_maximum = |values| {
		if values.is_empty() {
			return { nodes: [], leaves: 0, length: 0 }
		}
		# Font offsets/counts bound this input to checked source positions.
		var $leaves = 1
		while $leaves < values.len() {
			$leaves = $leaves * 2
		}
		var $nodes = List.repeat(0.U16, 2 * $leaves)
		for i in 0..<values.len() {
			$nodes = $nodes.set($leaves + i, (values.get(i) ?? 0).to_u16_wrap()) ?? []
		}
		var $i = $leaves
		while $i > 1 {
			$i = $i - 1
			$nodes = $nodes.set($i, ($nodes.get(2 * $i) ?? 0).max($nodes.get(2 * $i + 1) ?? 0)) ?? []
		}
		{ nodes: $nodes, leaves: $leaves, length: values.len() }
	}

	maximum : Maximum, U64, U64 -> U16
	maximum = |tree, start, end| {
		if start > end or end > tree.length {
			crash "maximum query uses a checked setting span"
		}
		var $left = tree.leaves + start
		var $right = tree.leaves + end
		var $value = 0.U16
		while $left < $right {
			if $left % 2 == 1 {
				$value = $value.max(tree.nodes.get($left) ?? 0)
				$left = $left + 1
			}
			if $right % 2 == 1 {
				$right = $right - 1
				$value = $value.max(tree.nodes.get($right) ?? 0)
			}
			$left = $left // 2
			$right = $right // 2
		}
		$value
	}
}

expect {
	map = GraphiteSettings.make([{ start: 0, count: 3 }, { start: 0, count: 3 }, { start: 8, count: 2 }, { start: 1, count: 2 }], 16, Feature) ?? crash "original bounded spans"
	map.count == 6 and GraphiteSettings.locate(map, { start: 0, count: 3 }) == Found({ start: 0, end: 3 }) and GraphiteSettings.locate(map, { start: 8, count: 2 }) == Found({ start: 2, end: 4 }) and GraphiteSettings.locate(map, { start: 1, count: 2 }) == Found({ start: 4, end: 6 }) and GraphiteSettings.locate(map, { start: 12, count: 2 }) == Missing
}
expect GraphiteSettings.make([{ start: 2, count: 1 }], 5, Feature).is_err()
expect {
	values = [-1.I16, 0, 32767, -32768, 42, 7, -5]
	tree = GraphiteSettings.make_maximum(values)
	var $valid = True
	for start in 0..<(values.len() + 1) {
		for end in start..<(values.len() + 1) {
			var $expected = 0.U16
			for i in start..<end {
				$expected = $expected.max((values.get(i) ?? 0).to_u16_wrap())
			}
			$valid = $valid and GraphiteSettings.maximum(tree, start, end) == $expected
		}
	}
	$valid
}
