## Final along-run offset propagation for GPOS mark attachments.
## A mark points to an earlier item in shaping order. Its across-run
## offset already includes the target's across-run offset at lookup time.
LayoutAttachment := {}.{
	none : U64
	none = 0xFFFFFFFFFFFFFFFF

	## Move from a mark's pen to the target's pen and include its final
	## x offset. In a backward run the distance includes the mark's
	## advance and excludes the target's. The lists are index-aligned.
	mark_x : List(U64), List(I64), List(I64), Bool -> List(I64)
	mark_x = |parents, advances, offsets, backward| {
		if parents.is_empty() {
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
