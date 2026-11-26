import Bytes
import LayoutAnchor
import LayoutCoverage
import LayoutGdef
import LayoutVar

## GPOS mark-to-base, mark-to-ligature and mark-to-mark format 1 subtables. Read validates
## the coverage, class and anchor references once. The prepared subtable
## decodes the validated offsets only after a coverage hit.
LayoutMark := {
	target_coverage : U64,
	classes : U64,
	marks : U64,
	target_array : U64,
}.{

	read : List(U8), U64, U64, U64, Bool, LayoutVar, List(U64) -> Try({ steps : U64, deltas : List(U64) }, [Bad(U64)])
	read = |data, at, glyph_count, steps, ligatures, lv, deltas| {
		if !Bytes.fits(at, 12, data.len()) or Bytes.u16(data, at) != 1 {
			return Err(Bad(at))
		}
		mark_coverage = LayoutMark.required(data, at, at + 2, 4)?
		target_coverage = LayoutMark.required(data, at, at + 4, 4)?
		classes = Bytes.u16(data, at + 6)
		marks = LayoutMark.required(data, at, at + 8, 2)?
		target_array = LayoutMark.required(data, at, at + 10, 2)?
		mark_coverage_info = LayoutCoverage.check(data, mark_coverage, glyph_count, steps)?
		target_index = LayoutCoverage.check(data, target_coverage, glyph_count, mark_coverage_info.steps)?
		if Bytes.u16(data, marks) != mark_coverage_info.count or !Bytes.fits(marks + 2, 4 * mark_coverage_info.count, data.len()) {
			return Err(Bad(marks))
		}
		if Bytes.u16(data, target_array) != target_index.count {
			return Err(Bad(target_array))
		}
		spent = LayoutVar.spend(data, target_index.steps, mark_coverage_info.count).map_err(|_| Bad(marks))?
		var $deltas = deltas
		for i in 0..<mark_coverage_info.count {
			record = marks + 2 + 4 * i
			if Bytes.u16(data, record) >= classes {
				return Err(Bad(record))
			}
			anchor = LayoutMark.required(data, marks, record + 2, 6)?
			$deltas = LayoutAnchor.check(data, anchor, lv, $deltas)?
		}
		checked = if ligatures {
			LayoutMark.check_ligatures(data, target_array, target_index.count, classes, spent, lv, $deltas)?
		} else {
			LayoutMark.check_matrix(data, target_array, target_index.count, classes, spent, lv, $deltas)?
		}
		Ok(checked)
	}

	required : List(U8), U64, U64, U64 -> Try(U64, [Bad(U64)])
	required = |data, base, field, size| {
		offset = Bytes.u16(data, field)
		target = base + offset
		if (offset != 0 and Bytes.fits(target, size, data.len())) Ok(target) else Err(Bad(field))
	}

	check_ligatures : List(U8), U64, U64, U64, U64, LayoutVar, List(U64) -> Try({ steps : U64, deltas : List(U64) }, [Bad(U64)])
	check_ligatures = |data, at, count, classes, steps, lv, deltas| {
		if !Bytes.fits(at + 2, 2 * count, data.len()) {
			return Err(Bad(at))
		}
		var $spent = LayoutVar.spend(data, steps, count).map_err(|_| Bad(at))?
		var $deltas = deltas
		for index in 0..<count {
			attach = LayoutMark.required(data, at, at + 2 + 2 * index, 2)?
			checked = LayoutMark.check_matrix(data, attach, Bytes.u16(data, attach), classes, $spent, lv, $deltas)?
			$spent = checked.steps
			$deltas = checked.deltas
		}
		Ok({ steps: $spent, deltas: $deltas })
	}

	## A base, mark2, or ligature component anchor matrix, with nullable
	## offsets relative to the matrix and a row count in its first word.
	check_matrix : List(U8), U64, U64, U64, U64, LayoutVar, List(U64) -> Try({ steps : U64, deltas : List(U64) }, [Bad(U64)])
	check_matrix = |data, at, rows, classes, steps, lv, deltas| {
		n = rows * classes
		if !Bytes.fits(at + 2, 2 * n, data.len()) {
			return Err(Bad(at))
		}
		spent = LayoutVar.spend(data, steps, n).map_err(|_| Bad(at))?
		var $deltas = deltas
		for index in 0..<n {
			field = at + 2 + 2 * index
			offset = Bytes.u16(data, field)
			if offset != 0 {
				if !Bytes.fits(at + offset, 6, data.len()) {
					return Err(Bad(field))
				}
				$deltas = LayoutAnchor.check(data, at + offset, lv, $deltas)?
			}
		}
		Ok({ steps: spent, deltas: $deltas })
	}

	## These references were checked by `read`.
	table_at : List(U8), U64 -> LayoutMark
	table_at = |data, at| {
		target_coverage: at + Bytes.u16(data, at + 4),
		classes: Bytes.u16(data, at + 6),
		marks: at + Bytes.u16(data, at + 8),
		target_array: at + Bytes.u16(data, at + 10),
	}

	## A checked lookup's input coverage contains only explicit GDEF marks.
	## A disagreement leaves the lookup eligible for any glyph.
	gdef_marks : List(U8), U64, LayoutGdef -> Bool
	gdef_marks = |data, at, gdef| {
		if !LayoutGdef.has_glyph_classes(gdef) {
			return False
		}
		coverage = at + Bytes.u16(data, at + 2)
		LayoutCoverage.every(data, coverage, |glyph| LayoutGdef.glyph_props(gdef, glyph).bitwise_and(LayoutGdef.mark) != 0)
	}

	## The mark's stored record or a coverage miss.
	mark_index : List(U8), U64, U64 -> Try(U64, [NotCovered])
	mark_index = |data, at, glyph| LayoutCoverage.index(data, at + Bytes.u16(data, at + 2), glyph)

	covers_target : LayoutMark, List(U8), U64 -> Bool
	covers_target = |shape, data, glyph| LayoutCoverage.index(data, shape.target_coverage, glyph).is_ok()

	## The two anchors selected by the mark class and target glyph.
	anchors : LayoutMark, List(U8), U64, U64, [Flat, Ligature(U64)] -> Try({ mark : U64, target : U64 }, [NotCovered])
	anchors = |shape, data, mark_number, glyph, rows| {
		index = LayoutCoverage.index(data, shape.target_coverage, glyph)?
		record = shape.marks + 2 + 4 * mark_number
		class = Bytes.u16(data, record)
		(matrix, row) = match rows {
			Flat => (shape.target_array, index)
			Ligature(component) => {
				attach = shape.target_array + Bytes.u16(data, shape.target_array + 2 + 2 * index)
				count = Bytes.u16(data, attach)
				if count == 0 {
					return Err(NotCovered)
				}
				# A component number from GSUB is one-based. A mark without
				# matching provenance belongs to the last component.
				selected = if (component == 0 or component > count) count else component
				(attach, selected - 1)
			}
		}
		target_offset = Bytes.u16(data, matrix + 2 + 2 * (row * shape.classes + class))
		if target_offset == 0 {
			Err(NotCovered)
		} else {
			Ok({ mark: shape.marks + Bytes.u16(data, record + 2), target: matrix + target_offset })
		}
	}
}
