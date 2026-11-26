## Horizontal GPOS attachment links. A mark points to an earlier item
## and takes its target's y offset at lookup time. A cursive link points
## either way and takes its target's final y offset. The high bit marks
## cursive links without a second allocation per run.
LayoutAttachment := {}.{
	none : U64
	none = 0xFFFFFFFFFFFFFFFF

	cursive_bit : U64
	cursive_bit = 0x8000000000000000

	max_chain : U64
	max_chain = 64

	is_cursive : U64 -> Bool
	is_cursive = |edge| edge >= LayoutAttachment.cursive_bit and edge != LayoutAttachment.none

	## Mark attachment takes the cursive chain's current cross offset.
	cross_at : List(U64), List(I64), U64 -> I64
	cross_at = |parents, offsets, target| {
		var $at = target
		var $y = offsets.get(target) ?? 0
		var $remaining = parents.len()
		while $remaining > 0 {
			edge = parents.get($at) ?? LayoutAttachment.none
			if !LayoutAttachment.is_cursive(edge) {
				return $y
			}
			$at = edge - LayoutAttachment.cursive_bit
			$y = $y + (offsets.get($at) ?? 0)
			$remaining = $remaining - 1
		}
		$y
	}

	## Change the root of the child's existing cursive path before joining
	## it to a new parent. On the way forward each old edge is read once,
	## before the new incoming edge replaces it. Stop at the new parent.
	link : List(U64), List(I64), U64, U64, I64 -> { parents : List(U64), dy : List(I64) }
	link = |parents, offsets, child, parent, y| {
		count = parents.len()
		var $parents = parents
		var $dy = offsets
		var $at = child
		var $incoming = LayoutAttachment.none
		var $incoming_y = 0
		var $depth = 0
		while $at < count {
			edge = $parents.get($at) ?? LayoutAttachment.none
			old_y = $dy.get($at) ?? 0
			$parents = $parents.set($at, $incoming) ?? []
			if $incoming != LayoutAttachment.none {
				$dy = $dy.set($at, $incoming_y) ?? []
			}
			if $depth > LayoutAttachment.max_chain or !LayoutAttachment.is_cursive(edge) {
				break
			}
			next = edge - LayoutAttachment.cursive_bit
			# Reversing a distance of -32768 cannot fit an int16.
			if next >= count or next == parent or $at == next + 32768 {
				break
			}
			$incoming = LayoutAttachment.cursive_bit + $at
			$incoming_y = -old_y
			$at = next
			$depth = $depth + 1
		}
		if parent > child + 32767 or child > parent + 32768 {
			return { parents: $parents, dy: $dy }
		}
		$parents = $parents.set(child, LayoutAttachment.cursive_bit + parent) ?? []
		$dy = $dy.set(child, y) ?? []
		other = $parents.get(parent) ?? LayoutAttachment.none
		if other == LayoutAttachment.cursive_bit + child or other == child {
			$parents = $parents.set(parent, LayoutAttachment.none) ?? []
			$dy = $dy.set(parent, 0) ?? []
		}
		{ parents: $parents, dy: $dy }
	}

	## Resolve cursive y offsets in visual traversal order, using the same
	## bounded path as HarfBuzz. Detaching an edge when it is visited also
	## ensures a path can never walk an edge twice.
	cursive_y : List(U64), List(I64), Bool -> List(I64)
	cursive_y = |parents, offsets, backward| {
		if !parents.any(LayoutAttachment.is_cursive) {
			return offsets
		}
		count = parents.len()
		var $edges = parents
		var $offsets = offsets
		var $path = List.repeat({ child: 0, parent: 0, cursive: False }, LayoutAttachment.max_chain)
		for index in 0..<count {
			var $at = if (backward) count - 1 - index else index
			var $depth = 0
			while $at < count {
				edge = $edges.get($at) ?? LayoutAttachment.none
				if edge == LayoutAttachment.none {
					break
				}
				$edges = $edges.set($at, LayoutAttachment.none) ?? []
				cursive = LayoutAttachment.is_cursive(edge)
				parent = if (cursive) edge - LayoutAttachment.cursive_bit else edge
				if parent >= count or $depth == LayoutAttachment.max_chain {
					break
				}
				$path = $path.set($depth, { child: $at, parent, cursive }) ?? []
				$at = parent
				$depth = $depth + 1
			}
			while $depth > 0 {
				$depth = $depth - 1
				{ child, parent, cursive } = $path.get($depth) ?? { child: 0, parent: 0, cursive: False }
				if cursive {
					y = ($offsets.get(child) ?? 0) + ($offsets.get(parent) ?? 0)
					$offsets = $offsets.set(child, y) ?? []
				}
			}
		}
		$offsets
	}

	## Move from a mark's pen to the target's pen and include its final
	## x offset. In a backward run the distance includes the mark's
	## advance and excludes the target's. The lists are index-aligned.
	mark_x : List(U64), List(I64), List(I64), Bool -> List(I64)
	mark_x = |parents, advances, offsets, backward| {
		if !parents.any(|edge| edge < LayoutAttachment.cursive_bit) {
			return offsets
		}
		var $pens = List.with_capacity(parents.len())
		var $pen = 0
		for advance in advances {
			next = $pen + advance
			$pens = $pens.append(if (backward) next else $pen)
			$pen = next
		}
		var $offsets = offsets
		for i in 0..<parents.len() {
			parent = parents.get(i) ?? LayoutAttachment.none
			if parent < i {
				distance = ($pens.get(i) ?? 0) - ($pens.get(parent) ?? 0)
				from_parent = if (backward) distance else -distance
				x = ($offsets.get(i) ?? 0) + ($offsets.get(parent) ?? 0) + from_parent
				# Both indexes refer to items in the run.
				$offsets = $offsets.set(i, x) ?? []
			}
		}
		$offsets
	}
}
