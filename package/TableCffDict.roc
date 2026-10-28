import Bytes
import TableVar
import TableCffIndex
import TableCffNumber
import TableCffBlend

## DICTs are preparation-only flat operand/entry pools. Unknown operators
## clear the operand stack as the CFF formats prescribe. Query-relevant
## keys are converted by TableCff into scalar prepared records.
TableCffDict :: {}.{
	Kind : [Top1, Top2, Font1, Font2, Private1, Private2]
	Entry : { op : U64, start : U64, count : U64, at : U64 }
	Parsed : { entries : List(Entry), args : List(TableCffBlend.Arg) }

	read : List(U8), TableCffIndex.Span, Kind, TableVar.Store -> Try(Parsed, [Bad(U64), OverLimit(Str)])
	read = |data, span, kind, store| {
		if span.end < span.start or span.end > data.len() {
			return Err(Bad(span.start))
		}
		cff2 = kind == Top2 or kind == Font2 or kind == Private2
		stack_limit = if (cff2) 513 else 48
		var $cursor = span.start
		var $stack = []
		var $entries = []
		var $args = []
		var $ivs = 0
		while $cursor < span.end {
			at = $cursor
			byte = Bytes.u8(data, at)
			if TableCffNumber.is_number(byte, True) {
				if $stack.len() >= stack_limit {
					return Err(OverLimit("CFF DICT operand stack"))
				}
				number = match TableCffNumber.read(data, at, span.end, True) {
					Ok(n) => n
					Err(Bad(p)) => return Err(Bad(p))
					Err(OverLimit) => return Err(OverLimit("CFF numeric operand"))
				}
				$stack = $stack.append(TableCffBlend.arg(number.value))
				$cursor = number.next
			} else {
				var $op = byte
				$cursor = $cursor + 1
				if byte == 12 {
					if $cursor == span.end {
						return Err(Bad(at))
					}
					$op = 256 + Bytes.u8(data, $cursor)
					$cursor = $cursor + 1
				}
				if kind == Private2 and $op == 23 {
					$stack = match TableCffBlend.apply($stack, store, $ivs, []) {
						Ok(args) => args
						Err(Bad) => return Err(Bad(at))
						Err(OverLimit) => return Err(OverLimit("CFF blend operand envelope"))
					}
				} else {
					if TableCffDict.known(kind, $op) {
						if !TableCffDict.count_valid($op, $stack.len()) {
							return Err(Bad(at))
						}
						if cff2 and !TableCffDict.blendable($op) and $stack.any(|a| a.variable) {
							return Err(Bad(at))
						}
						if kind == Private2 and $op == 22 {
							v = $stack.first() ?? return Err(Bad(at))
							$ivs = TableCffDict.natural(v.value, store.item_counts.len(), at)?
							if $ivs >= store.item_counts.len() {
								return Err(Bad(at))
							}
						}
						start = $args.len()
						for arg in $stack {
							$args = $args.append(arg)
						}
						$entries = $entries.append({ op: $op, start, count: $stack.len(), at })
					}
					$stack = $stack.clear()
				}
			}
		}
		if !$stack.is_empty() {
			return Err(Bad(span.end))
		}
		Ok({ entries: $entries, args: $args })
	}

	known : Kind, U64 -> Bool
	known = |kind, op| match kind {
		Top2 => op == 17 or op == 24 or op == 263 or op == 292 or op == 293
		Font2 => op == 18
		Top1 | Font1 => op <= 5 or (op >= 13 and op <= 18) or (op >= 256 and op <= 264) or (op >= 276 and op <= 279) or (op >= 286 and op <= 294)
		Private1 => (op >= 6 and op <= 11) or (op >= 19 and op <= 21) or (op >= 265 and op <= 270) or (op >= 273 and op <= 275)
		Private2 => (op >= 6 and op <= 11) or op == 19 or op == 22 or (op >= 265 and op <= 269) or op == 273 or op == 274
	}

	count_valid : U64, U64 -> Bool
	count_valid = |op, count| {
		if op == 5 {
			count == 4
		} else if op == 18 {
			count == 2
		} else if op == 263 {
			count == 6
		} else if op == 286 {
			count == 3
		} else if op == 6 or op == 8 {
			count <= 14 and count % 2 == 0
		} else if op == 7 or op == 9 {
			count <= 10 and count % 2 == 0
		} else if op == 268 or op == 269 {
			count <= 12
		} else if op == 14 or op == 279 {
			count >= 1
		} else {
			count == 1
		}
	}

	blendable : U64 -> Bool
	blendable = |op| op == 6 or op == 7 or op == 10 or op == 11 or op == 268 or op == 269

	## DICT lookup follows decoding order; a later occurrence has the value
	## the reference decoders retain. Every occurrence still has checked syntax.
	find : Parsed, U64 -> [Present(Entry), Absent]
	find = |parsed, op| {
		var $i = parsed.entries.len()
		while $i > 0 {
			$i = $i - 1
			entry = parsed.entries.get($i) ?? { op: 0, start: 0, count: 0, at: 0 }
			if entry.op == op {
				return Present(entry)
			}
		}
		Absent
	}

	natural : F64, U64, U64 -> Try(U64, [Bad(U64)])
	natural = |v, maximum, at| {
		if v < 0 or v > maximum.to_f64() {
			return Err(Bad(at))
		}
		n = v.to_u64_try() ?? return Err(Bad(at))
		if n.to_f64() != v or n > maximum {
			Err(Bad(at))
		} else {
			Ok(n)
		}
	}

	nat : Parsed, Entry, U64, U64 -> Try(U64, [Bad(U64)])
	nat = |parsed, entry, index, maximum| {
		if index >= entry.count {
			return Err(Bad(entry.at))
		}
		arg = parsed.args.get(entry.start + index) ?? return Err(Bad(entry.at))
		if arg.variable {
			Err(Bad(entry.at))
		} else {
			TableCffDict.natural(arg.value, maximum, entry.at)
		}
	}
}

empty_store : TableVar.Store
empty_store = { axis_count: 0, region_count: 0, regions: [], item_counts: [], word_counts: [], long_words: [], index_starts: [], region_indexes: [], row_starts: [], row_sizes: [], bytes: [] }

expect {
	# Unknown op2 clears its operand; only the final CharStrings operand
	# enters the flat pool. Unknown operators are a defined format fallback.
	match TableCffDict.read([140, 2, 141, 17], { start: 0, end: 4 }, Top2, empty_store) {
		Ok(parsed) => match TableCffDict.find(parsed, 17) {
			Present(entry) => parsed.args.len() == 1 and TableCffDict.nat(parsed, entry, 0, 10) == Ok(2)
			Absent => False
		}
		Err(_) => False
	}
}
expect TableCffDict.read([140, 141, 17], { start: 0, end: 3 }, Top2, empty_store) == Err(Bad(2))
expect TableCffDict.read([12], { start: 0, end: 1 }, Top1, empty_store) == Err(Bad(0))
expect TableCffDict.read([140], { start: 0, end: 1 }, Top1, empty_store) == Err(Bad(1))
expect TableCffDict.read(List.repeat(139, 49), { start: 0, end: 49 }, Top1, empty_store) == Err(OverLimit("CFF DICT operand stack"))
expect {
	store = { ..empty_store, axis_count: 1, region_count: 1, regions: [0, 16384, 16384], item_counts: [0], word_counts: [0], long_words: [False], index_starts: [0, 1], region_indexes: [0], row_starts: [0], row_sizes: [0] }
	# A blended Subrs offset cannot change the executed program by location.
	TableCffDict.read([139, 140, 140, 23, 19], { start: 0, end: 5 }, Private2, store) == Err(Bad(4))
}
