import GraphiteSlots

## Complete character associations after font-program execution. Deleted
## characters already covered by an explicit association need no change.
## An uncovered character extends the first slot of each adjacent covered
## character. A scalar heap chooses the first output slot for overlapping
## ranges without expanding every glyph/character Cartesian product.
GraphiteAssociations :: {}.{
	Applied : { state : GraphiteSlots, operations : U64, stopped : U64, aborted : Bool }
	Row : { id : U64, before : U64, after : U64 }
	complete : GraphiteSlots, U64, U64 -> Applied
	complete = |state, count, budget| {
		if state.active == 0 or count == 0 {
			return { state, operations: 0, stopped: 0, aborted: False }
		}
		if count > budget {
			return { state, operations: 0, stopped: 2, aborted: False }
		}
		var $operations = count
		var $heads = List.repeat(0.U64, count)
		var $rows = List.with_capacity(state.active)
		var $next = List.with_capacity(state.active)
		var $id = state.first
		while $id != 0 {
			if $operations >= budget {
				return { state, operations: $operations, stopped: 2, aborted: False }
			}
			$operations = $operations + 1
			slot = GraphiteSlots.get(state, $id)
			if slot.before < 0 or slot.after < slot.before or slot.after.to_u64_wrap() >= count {
				return { state, operations: $operations, stopped: 0, aborted: True }
			}
			before = slot.before.to_u64_wrap()
			$rows = $rows.append({ id: $id, before, after: slot.after.to_u64_wrap() })
			$next = $next.append($heads.get(before) ?? crash "checked association start")
			$heads = $heads.set(before, $rows.len()) ?? []
			$id = slot.next
		}
		var $heap = List.with_capacity($rows.len())
		var $owners = List.with_capacity(count)
		for character in 0..<count {
			if $operations >= budget {
				return { state, operations: $operations, stopped: 2, aborted: False }
			}
			$operations = $operations + 1
			var $row = $heads.get(character) ?? crash "character head span"
			while $row != 0 {
				added = GraphiteAssociations.push($heap, $row, budget - $operations)
				$operations = $operations + added.operations
				if added.stopped {
					return { state, operations: $operations, stopped: 2, aborted: False }
				}
				$heap = added.heap
				$row = $next.get($row - 1) ?? crash "bounded association row"
			}
			while !$heap.is_empty() {
				first = $heap.first() ?? crash "nonempty association heap"
				if ($rows.get(first - 1) ?? crash "bounded heap row").after >= character {
					break
				}
				removed = GraphiteAssociations.pop($heap, budget - $operations)
				$operations = $operations + removed.operations
				if removed.stopped {
					return { state, operations: $operations, stopped: 2, aborted: False }
				}
				$heap = removed.heap
			}
			$owners = $owners.append($heap.first() ?? 0)
		}
		var $state = state
		var $left = 0
		for character in 0..<count {
			if $operations >= budget {
				return { state: $state, operations: $operations, stopped: 2, aborted: False }
			}
			$operations = $operations + 1
			owner = $owners.get(character) ?? crash "complete character owners"
			if owner != 0 {
				$left = owner
			} else if $left != 0 {
				id = ($rows.get($left - 1) ?? crash "left character owner").id
				slot = GraphiteSlots.get($state, id)
				$state = GraphiteSlots.set($state, id, { ..slot, after: character.to_i64_wrap() })
			}
		}
		var $right = 0
		var $character = count
		while $character != 0 {
			if $operations >= budget {
				return { state: $state, operations: $operations, stopped: 2, aborted: False }
			}
			$operations = $operations + 1
			$character = $character - 1
			owner = $owners.get($character) ?? crash "complete reverse owners"
			if owner != 0 {
				$right = owner
			} else if $right != 0 {
				id = ($rows.get($right - 1) ?? crash "right character owner").id
				slot = GraphiteSlots.get($state, id)
				$state = GraphiteSlots.set($state, id, { ..slot, before: $character.to_i64_wrap() })
			}
		}
		{ state: $state, operations: $operations, stopped: 0, aborted: False }
	}

	Heap : { heap : List(U64), operations : U64, stopped : Bool }
	push : List(U64), U64, U64 -> Heap
	push = |heap, value, budget| {
		if budget == 0 {
			return { heap, operations: 0, stopped: True }
		}
		var $heap = heap.append(value)
		var $at = $heap.len() - 1
		var $operations = 1
		while $at != 0 {
			if $operations >= budget {
				return { heap: $heap, operations: $operations, stopped: True }
			}
			$operations = $operations + 1
			parent = ($at - 1) // 2
			prior = $heap.get(parent) ?? crash "bounded heap parent"
			if prior <= value {
				break
			}
			$heap = $heap.set($at, prior) ?? []
			$heap = $heap.set(parent, value) ?? []
			$at = parent
		}
		{ heap: $heap, operations: $operations, stopped: False }
	}

	pop : List(U64), U64 -> Heap
	pop = |heap, budget| {
		if budget == 0 {
			return { heap, operations: 0, stopped: True }
		}
		last = heap.last() ?? crash "nonempty heap removal"
		var $heap = heap.drop_last(1)
		var $operations = 1
		if $heap.is_empty() {
			return { heap: $heap, operations: 1, stopped: False }
		}
		$heap = $heap.set(0, last) ?? []
		var $at = 0
		while $at < $heap.len() // 2 {
			if $operations >= budget {
				return { heap: $heap, operations: $operations, stopped: True }
			}
			$operations = $operations + 1
			left = 2 * $at + 1
			right = left + 1
			child = if (right < $heap.len() and ($heap.get(right) ?? 0) < ($heap.get(left) ?? 0)) right else left
			value = $heap.get(child) ?? crash "bounded heap child"
			if value >= last {
				break
			}
			$heap = $heap.set($at, value) ?? []
			$heap = $heap.set(child, last) ?? []
			$at = child
		}
		{ heap: $heap, operations: $operations, stopped: False }
	}
}

expect {
	# Overlapping ranges choose the first physical output, including when
	# stable IDs differ from their current order after an insertion.
	a = GraphiteSlots.append(GraphiteSlots.make(0, 3), { ..GraphiteSlots.no_slot, before: 0, after: 0 })
	b = GraphiteSlots.append(a.state, { ..GraphiteSlots.no_slot, before: 2, after: 2 })
	c = GraphiteSlots.insert(b.state, a.id, { ..GraphiteSlots.no_slot, before: 0, after: 0 })
	r = GraphiteAssociations.complete(c.state, 3, 100)
	r.stopped == 0 and !r.aborted and GraphiteSlots.get(r.state, c.id).after == 1 and GraphiteSlots.get(r.state, a.id).after == 0 and GraphiteSlots.get(r.state, b.id).before == 1
}

expect {
	a = GraphiteSlots.append(GraphiteSlots.make(0, 2), { ..GraphiteSlots.no_slot, before: 0, after: 1 })
	b = GraphiteSlots.append(a.state, { ..GraphiteSlots.no_slot, before: 2, after: 2 })
	r = GraphiteAssociations.complete(b.state, 3, 100)
	r.stopped == 0 and GraphiteSlots.get(r.state, b.id).before == 2
}

expect {
	# Exhaust every two-range combination over four source characters.
	# A simple expanded owner scan independently checks the pooled sweep.
	var $ok = True
	for a in 0..<4.U64 {
		for b in a..<4.U64 {
			for c in 0..<4.U64 {
				for d in c..<4.U64 {
					x = GraphiteSlots.append(GraphiteSlots.make(0, 2), { ..GraphiteSlots.no_slot, before: a.to_i64_wrap(), after: b.to_i64_wrap() })
					y = GraphiteSlots.append(x.state, { ..GraphiteSlots.no_slot, before: c.to_i64_wrap(), after: d.to_i64_wrap() })
					original = [GraphiteSlots.get(y.state, x.id), GraphiteSlots.get(y.state, y.id)]
					owners = List.map(
						[0.U64, 1, 2, 3],
						|character| {
							var $owner = 0.U64
							for i in 0..<original.len() {
								s = original.get(i) ?? crash "two original rows"
								if $owner == 0 and s.before <= character.to_i64_wrap() and s.after >= character.to_i64_wrap() {
									$owner = i + 1
								}
							}
							$owner
						},
					)
					result = GraphiteAssociations.complete(y.state, 4, 100)
					$ok = $ok and result.stopped == 0 and !result.aborted
					for i in 0..<2.U64 {
						var $before = (original.get(i) ?? crash "two rows").before
						var $after = (original.get(i) ?? crash "two rows").after
						for character in 0..<4.U64 {
							if owners.get(character) == Ok(0) {
								left = owners.take_first(character).fold(0.U64, |last, value| if (value != 0) value else last)
								right = owners.drop_first(character + 1).find_first(|v| v != 0) ?? 0
								if left == i + 1 {
									$after = $after.max(character.to_i64_wrap())
								}
								if right == i + 1 {
									$before = $before.min(character.to_i64_wrap())
								}
							}
						}
						s = GraphiteSlots.get(result.state, i + 1)
						$ok = $ok and s.before == $before and s.after == $after
					}
				}
			}
		}
	}
	$ok
}
