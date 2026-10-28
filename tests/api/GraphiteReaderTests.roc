import font.Font
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
