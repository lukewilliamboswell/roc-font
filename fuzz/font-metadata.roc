app [target] {
	build: "../tests/support/main.roc",
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}

import fuzz.Fuzz
import font.Font
import build.FontBuild

## Original table and PDF metadata queries at 4, 32 and 256 glyphs.
## The complete long/trailing metrics arrays are independently generated;
## queries retain stored signed bearings and original table bytes, are
## deterministic past glyph bounds, allocate independently of unrelated
## glyph count, and never leak. Arbitrary real fonts seed byte mutation.
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	value = (bytes.first() ?? 0).to_i64() - 128
	small_bytes = generated(4, value)
	middle_bytes = generated(32, value)
	large_bytes = generated(256, value)
	small = check(small_bytes, 4, value)
	middle = check(middle_bytes, 32, value)
	large = check(large_bytes, 256, value)
	a = Fuzz.measure_allocs!(|{}| Font.from_bytes(small_bytes, Font.ReadOptions.{}))
	b = Fuzz.measure_allocs!(|{}| Font.from_bytes(middle_bytes, Font.ReadOptions.{}))
	c = Fuzz.measure_allocs!(|{}| Font.from_bytes(large_bytes, Font.ReadOptions.{}))
	if b.allocations > 10 * a.allocations + 128 or c.allocations > 10 * b.allocations + 128 {
		crash "metadata reading allocations grew faster than glyph count"
	}
	x = Fuzz.measure_allocs!(|{}| query(small, 1))
	y = Fuzz.measure_allocs!(|{}| query(middle, 1))
	z = Fuzz.measure_allocs!(|{}| query(large, 1))
	if y.allocations > x.allocations or z.allocations > x.allocations {
		crash "metadata query allocates with unrelated glyph count"
	}
	Fuzz.expect_no_leaks!(|{}| Font.from_bytes(large_bytes, Font.ReadOptions.{}))
	Fuzz.expect_no_leaks!(|{}| query(large, 1))
	candidate = if (bytes.len() > 1) FontBuild.mutate(Font.sans_bytes, bytes) else bytes
	match Font.from_bytes(candidate, Font.ReadOptions.{}) {
		Ok(font) => {
			for id in [0.U32, Font.glyph_count(font), 4294967295] {
				if query(font, id) != query(font, id) {
					crash "metadata query is nondeterministic"
				}
			}
			if !Font.tables(font).all(|entry| entry.offset.to_u64() + entry.length.to_u64() <= candidate.len()) {
				crash "raw table directory escapes original bytes"
			}
		}
		Err(_) => {}
	}
	Fuzz.keep
}

query : Font, U32 -> { name : Try(Str, [Missing]), flags : [Present(U16), Absent], bearing : [Present(I32), Absent], bounds : Font.Extents, header : Font.HeaderMetrics, table : [Present(List(U8)), Absent] }
query = |font, id| { name: Font.full_name(font), flags: Font.embedding_flags(font), bearing: Font.stored_left_side_bearing(font, id), bounds: Font.stored_bounds(font), header: Font.stored_header_metrics(font), table: Font.table_bytes(font, "TEST") }

generated : U64, I64 -> List(U8)
generated = |count, value| {
	metrics = FontBuild.hmtx([500]).concat(FontBuild.counting(count - 1).join_map(|_| FontBuild.i16(value)))
	tables = FontBuild.replace(FontBuild.replace(FontBuild.replace(FontBuild.basic, "maxp", FontBuild.maxp(count)), "hhea", FontBuild.hhea(800, -200, 1)), "hmtx", metrics)
	FontBuild.file(tables.append({ tag: "TEST", data: [1, 2, 3, 4] }))
}

check : List(U8), U64, I64 -> Font
check = |bytes, count, value| {
	font = match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
		Ok(ready) => ready
		Err(problems) => crash Str.inspect(problems)
	}
	if Font.stored_left_side_bearing(font, (count - 1).to_u32_wrap()) != Present(value.to_i32_wrap()) or Font.stored_left_side_bearing(font, count.to_u32_wrap()) != Absent or Font.table_bytes(font, "TEST") != Present([1, 2, 3, 4]) {
		crash "stored metadata differs from original font"
	}
	font
}

target = Fuzz.target_with!({ name: "font-metadata", generator: Fuzz.raw_bytes, test!, show: |bytes| Str.inspect(bytes.take_first(32)) })
