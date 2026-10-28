import font.Font
import "../fonts/graphite/delete-leaf/getter-ltr.ttf" as getter : List(U8)
import "../fonts/graphite/delete-leaf/getter-detached-ltr.ttf" as detached : List(U8)
import "../fonts/graphite/delete-leaf/constant-ltr.ttf" as constant : List(U8)
import "../fonts/graphite/delete-leaf/getter-rtl.ttf" as rtl_getter : List(U8)
import "../fonts/graphite/delete-leaf/star-delete-d-ltr.ttf" as later_sibling : List(U8)
import "../fonts/graphite/delete-leaf/next-delete.ttf" as next_delete : List(U8)
import "../fonts/graphite-geometry/deleted-leaf-audit/collision-deleted-leaf-delete-da-ltr.ttf" as parent_first : List(U8)
import "../fonts/graphite-geometry/deleted-leaf-audit/collision-deleted-leaf-delete-ad-ltr.ttf" as leaf_first : List(U8)

GraphiteDeletionTests :: {}.{}

read = |bytes| Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "valid original deletion fixture rejected"

options = Font.ShapeOptions.{ script: "Latn", direction: LeftToRight, clusters: Characters }

## Deleting a parent before its child retains the inactive intermediate.
expect {
	font = read(parent_first)
	run = Font.shape(font, "abcd", options)
	run.glyphs == [3, 4] and run.advances == [{ x: 5080, y: 0 }, { x: 604, y: 0 }] and run.clusters == [0, 3]
}

## Deleting the child first makes its parent a leaf at deletion time.
expect {
	font = read(leaf_first)
	run = Font.shape(font, "abcd", options)
	run.glyphs == [3, 4] and run.advances == [{ x: 603, y: 0 }, { x: 604, y: 0 }] and run.clusters == [0, 3]
}

## The unlinked leaf retains its observable attachment reference.
expect {
	run = Font.shape(read(getter), "abcd", options)
	other = Font.shape(read(detached), "abcd", options)
	run.glyphs == [2, 3, 4] and run.offsets == [{ x: 0, y: 1 }, { x: 0, y: 0 }, { x: 0, y: 0 }] and other.offsets == [{ x: 0, y: 0 }, { x: 0, y: 0 }, { x: 0, y: 0 }]
}

## The constant proves that the post-deletion write reaches the same survivor.
expect {
	run = Font.shape(read(constant), "abcd", options)
	run.glyphs == [2, 3, 4] and run.offsets == [{ x: 0, y: 123 }, { x: 0, y: 0 }, { x: 0, y: 0 }]
}

expect {
	font = read(rtl_getter)
	plan = Font.plan(font, Font.ShapeOptions.{ script: "Arab", direction: RightToLeft, clusters: Characters })
	Font.shaping_engine(plan) == Graphite and match Font.shape_traced(font, plan, "abcd") {
		Ok(result) => result.run.glyphs == [4, 3, 2] and result.run.offsets == [{ x: 0, y: 0 }, { x: 0, y: 0 }, { x: 0, y: 1 }] and result.origins == [Mapped, Mapped, Mapped]
		Err(_) => False
	}
}

## A deleted non-first attachment remains in the parent's geometry.
expect {
	run = Font.shape(read(later_sibling), "abcd", options)
	run.glyphs == [1, 3, 4] and run.advances == [{ x: 5080, y: 0 }, { x: 0, y: 0 }, { x: 604, y: 0 }] and run.offsets == [{ x: 80, y: 170 }, { x: -5080, y: 0 }, { x: 0, y: 0 }]
}

## A legal NEXT/DELETE program depends on the text supplying its next slot.
expect {
	font = read(next_delete)
	plan = Font.plan(font, options)
	match Font.shape_checked(font, plan, "a") {
		Err(ProgramAborted(aborted)) => aborted.run.glyphs.is_empty() and aborted.run.clusters.is_empty()
		_ => False
	} and match Font.shape_checked(font, plan, "ab") {
		Ok(run) => run.glyphs == [1] and run.advances == [{ x: 601, y: 0 }] and run.clusters == [0]
		Err(_) => False
	}
}

expect {
	font = read(next_delete)
	plan = Font.plan(font, options)
	match Font.shape_traced(font, plan, "a") {
		Err(ProgramAborted({ run, origins })) => run.glyphs.is_empty() and origins.is_empty()
		_ => False
	} and match Font.shape_range_checked(font, plan, "ab", Font.TextRange.{ end: 1 }) {
		Err(ProgramAborted({ run })) => run.glyphs.is_empty()
		_ => False
	}
}
