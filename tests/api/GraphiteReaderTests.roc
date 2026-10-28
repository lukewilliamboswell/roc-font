import font.Font
import "../fonts/graphite/bounds-unknown-gloc-flags.ttf" as unknown_gloc : List(U8)
import "../fonts/graphite/phase-legacy/phase-2-255-32.ttf" as legacy_flags : List(U8)
import "../fonts/graphite/bounds-valid.ttf" as valid_bounds : List(U8)
import "../fonts/graphite/bounds-equal.ttf" as equal_bounds : List(U8)
import "../fonts/graphite/bounds-inverted-y.ttf" as inverted_y : List(U8)
import "../fonts/graphite/bounds-inverted-many.ttf" as inverted_many : List(U8)
import "../fonts/graphite/overlap-1024.ttf" as shared_settings : List(U8)
import "../fonts/graphite/stack-1024.ttf" as deep_stack : List(U8)
import "../fonts/graphite/stack-unbalanced.ttf" as unbalanced_stack : List(U8)
import "../fonts/graphite/Charis5_eursub.ttf" as charis : List(U8)
import "../fonts/graphite/Padauk.ttf" as padauk : List(U8)
import "../fonts/graphite/Scheherazadegr.ttf" as scheherazade : List(U8)
import "../fonts/graphite/AwamiNastaliq-Regular.ttf" as awami : List(U8)

## Reading real Graphite program groups. Dispatch is gated separately by
## runtime conformance; this consumer proves only the prepared reader.
GraphiteReaderTests :: {}.{}

retained : List(U8) -> Bool
retained = |bytes| {
	font = Font.from_bytes(bytes, Font.ReadOptions.{}) ?? crash "real Graphite font rejected"
	problems = Font.dropped(font).keep_if(
		|problem| match problem {
			BadTable({ table, offset: _ }) => ["Silf", "Gloc", "Glat", "Feat", "Sill"].contains(table)
			OverLimit(table) => ["Silf", "Gloc", "Glat", "Feat", "Sill"].contains(table)
			_ => False
		},
	)
	if !problems.is_empty() {
		crash Str.inspect(problems)
	}
	True
}

expect retained(charis)
expect retained(padauk)
expect retained(scheherazade)
expect retained(awami)

expect retained(deep_stack)
expect retained(unbalanced_stack)

expect retained(shared_settings)

expect {
	retained(valid_bounds) and retained(equal_bounds) and Font.from_bytes(valid_bounds, Font.ReadOptions.{ strict: True }).is_ok() and Font.from_bytes(equal_bounds, Font.ReadOptions.{ strict: True }).is_ok()
}

bad_bounds = |bytes, offsets| {
	font = Font.from_bytes(bytes, Font.ReadOptions.{}) ?? crash "broken optional geometry rejected the font"
	entry = Font.tables(font).find_first(|table| table.tag == 0x476C6174) ?? crash "original Glat directory entry"
	expected = offsets.map(|relative| BadTable({ table: "Glat", offset: entry.offset + relative }))
	strict = match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
		Err(problems) => problems == expected
		Ok(_) => False
	}
	plan = Font.plan(font, Font.ShapeOptions.{})
	strict and Font.dropped(font) == expected and Font.shaping_engine(plan) == OpenType and Font.shape_planned(font, plan, "ab").glyphs == [1, 2]
}

## fuzz regression: the second part has reversed Y endpoints. Lenient
## reading drops the entire program, and strict reading names its offset.
expect bad_bounds(inverted_y, [24.U32])
expect bad_bounds(inverted_many, [10.U32, 12, 22, 24, 26, 28])

## fuzz regression: later pass flags remain compatible with older tables,
## as permitted by GTF's explicit reserved-field compatibility note.
expect {
	font = Font.from_bytes(legacy_flags, Font.ReadOptions.{ strict: True }) ?? crash "compatible legacy flags rejected"
	retained(legacy_flags) and Font.shaping_engine(Font.plan(font, Font.ShapeOptions.{})) == Graphite
}

expect {
	font = Font.from_bytes(unknown_gloc, Font.ReadOptions.{ strict: True }) ?? crash "unassigned Gloc flag rejected defined layout"
	retained(unknown_gloc) and Font.shaping_engine(Font.plan(font, Font.ShapeOptions.{})) == Graphite
}
