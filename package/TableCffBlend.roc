import TableVar
import TableOutline
import TableCffNumber

## CFF2 blends share the same operand convention in DICTs/CharStrings.
## A bound encloses every legal variation location, not only the default.
## `variable` prevents blended values selecting a subroutine or vsindex.
TableCffBlend :: {}.{
	Arg : { value : F64, bound : F64, variable : Bool }
	arg : F64 -> Arg
	arg = |v| { value: v, bound: if (v < 0) 0 - v else v, variable: False }

	region_count : TableVar.Store, U64 -> Try(U64, [Bad])
	region_count = |store, index| {
		if index >= store.item_counts.len() {
			Err(Bad)
		} else {
			Ok((store.index_starts.get(index + 1) ?? 0) - (store.index_starts.get(index) ?? 0))
		}
	}

	## No encoded-data allocation: values replace their defaults in the
	## flat stack before its consumed delta suffix is removed.
	apply : List(Arg), TableVar.Store, U64, List(U32) -> Try(List(Arg), [Bad, OverLimit])
	apply = |args, store, index, scalars| {
		if args.len() > 513 {
			return Err(OverLimit)
		}
		last = args.last() ?? return Err(Bad)
		if last.variable or last.value < 1 or last.value > args.len().to_f64() {
			return Err(Bad)
		}
		n = last.value.to_u64_try() ?? return Err(Bad)
		if n.to_f64() != last.value {
			return Err(Bad)
		}
		regions = TableCffBlend.region_count(store, index)?
		# regions is bounded by a checked U16 count. n <= stack length <=513.
		consumed = n * (regions + 1) + 1
		if consumed > args.len() {
			return Err(Bad)
		}
		start = args.len() - consumed
		first = store.index_starts.get(index) ?? 0
		var $args = args
		for i in 0..<n {
			original = $args.get(start + i) ?? TableCffBlend.arg(0)
			var $sum = 0.F64
			var $bound = original.bound
			for r in 0..<regions {
				delta = $args.get(start + n + i * regions + r) ?? TableCffBlend.arg(0)
				region = store.region_indexes.get(first + r) ?? 0
				scalar = if (scalars.is_empty()) 0 else TableOutline.widen(scalars.get(region) ?? 0)
				$sum = $sum + scalar * delta.value
				$bound = TableCffNumber.add_bound($bound, delta.bound)
			}
			v = original.value + $sum
			if !TableCffNumber.within_limit(v) or $bound > TableCffNumber.limit {
				return Err(OverLimit)
			}
			# All default/delta indices were checked against consumed above.
			$args = $args.set(start + i, { value: v, bound: $bound, variable: original.variable or regions != 0 }) ?? []
		}
		Ok($args.take_first(start + n))
	}
}

# A checked-store shape with two region references and no item rows:
# CFF2 uses the region references, not the HVAR-style encoded delta rows.
test_store : TableVar.Store
test_store = { axis_count: 1, region_count: 2, regions: [0, 16384, 16384, 0, 16384, 16384], item_counts: [0], word_counts: [0], long_words: [False], index_starts: [0, 2], region_indexes: [0, 1], row_starts: [0], row_sizes: [0], bytes: [] }

expect {
	args = [99, 10, 20, 2, 4, 6, 8, 2].map(|v| TableCffBlend.arg(v))
	match TableCffBlend.apply(args, test_store, 0, [0x3F000000, 0x3F800000]) {
		Ok(out) => out.map(|a| a.value) == [99, 15, 31] and !(out.first() ?? TableCffBlend.arg(0)).variable and (out.get(1) ?? TableCffBlend.arg(0)).variable and (out.get(1) ?? TableCffBlend.arg(0)).bound >= 16 and (out.get(2) ?? TableCffBlend.arg(0)).bound >= 34
		Err(_) => False
	}
}
expect {
	match TableCffBlend.apply([10, 2, 4, 1].map(TableCffBlend.arg), test_store, 0, [0x3F000000, 0x3F800000]) {
		Ok(inner) => match TableCffBlend.apply(inner.concat([3, 5, 1].map(TableCffBlend.arg)), test_store, 0, [0x3F000000, 0x3F800000]) {
			Ok(out) => out.map(|a| a.value) == [21.5] and (out.first() ?? TableCffBlend.arg(0)).variable
			Err(_) => False
		}
		Err(_) => False
	}
}
expect TableCffBlend.apply([10, 2, 1].map(TableCffBlend.arg), test_store, 0, []) == Err(Bad)
expect TableCffBlend.apply([10, 2, 4, 1].map(TableCffBlend.arg), test_store, 1, []) == Err(Bad)
