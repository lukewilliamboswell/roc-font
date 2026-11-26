import font.Font
import fuzz.Fuzz
import MarkFixture
import "../../tests/fonts/mark-attachment/DavidLibre-Regular.ttf" as david : List(U8)

## Mark subtables with a class beyond the anchor matrix, a coverage
## count mismatch, an unknown anchor format, or a truncated anchor.
## The valid recipe also scales the number of rows without changing the
## glyphs a query touches.
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	choice = bytes.first() ?? 0
	if choice == 255 {
		Fuzz.expect_no_leaks!(|| read(david))
	} else {
		kind = 4 + choice.to_u64() % 3
		extended = choice.bitwise_and(0x04) != 0
		x = (bytes.get(1) ?? 100).to_i64() - 128
		y = (bytes.get(2) ?? 150).to_i64() - 128
		count = 1 + (bytes.get(3) ?? 16).to_u64()
		fault = match choice.shr_zf_wrap(3) % 4 {
			0 => BadClass
			1 => BadCoverage
			2 => BadAnchor
			_ => ShortAnchor
		}
		valid = MarkFixture.bytes(kind, extended, x, y, count, Valid)
		ok = read(valid)
		if !Font.dropped(ok).is_empty() {
			crash "a valid attachment recipe reported damaged tables"
		}
		Fuzz.expect_no_leaks!(|| Font.from_bytes(valid, Font.ReadOptions.{ strict: True }))
		damaged = MarkFixture.bytes(kind, extended, x, y, count, fault)
		lenient = Font.from_bytes(damaged, Font.ReadOptions.{})
		strict = Font.from_bytes(damaged, Font.ReadOptions.{ strict: True })
		match (lenient, strict) {
			(Err([BadTable({ table: "GPOS", offset: a })]), Err([BadTable({ table: "GPOS", offset: b })])) if a == b => {}
			_ => crash "reading failed to report damaged mark positioning"
		}
	}
	Fuzz.keep
}

read : List(U8) -> Font
read = |bytes| match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
	Ok(font) => font
	Err(problems) => crash "a valid attachment font failed to read: ${Str.inspect(problems)}"
}

FontMarkRead := {}.{
	target = Fuzz.target_with!({
		examples: [],
		name: "font-mark-read",
		generator: Fuzz.raw_bytes,
		test!,
		show: |bytes| Str.inspect(bytes.take_first(32)),
	})
}
