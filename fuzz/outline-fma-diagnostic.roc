app [target] {
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}
import font.Font
import fuzz.Fuzz
import "../tests/fonts/variable/var-outlines.ttf" as fixture : List(U8)

# Native diagnostic for the matrix multiply-add path, at three increasing
# query counts. Runtime font bytes prevent compile-time evaluation. It
# intentionally crashes after reporting allocation counts and a checksum.
test! = |bytes| {
	read = match Font.from_bytes(fixture.concat(bytes), Font.ReadOptions.{}) {
		Ok(font) => font
		Err(problems) => crash Str.inspect(problems)
	}
	font = Font.at(read, Font.Variation.{ weight: Weight(650), width: Percent(87.5) })
	count : U64
	count = if (bytes.first() ?? 0) == 0 {
		1000
	} else if (bytes.first() ?? 0) == 1 {
		4000
	} else {
		16000
	}
	before = Fuzz.live_alloc_count!()
	measured = Fuzz.measure_allocs!(
		|{}| {
			var $sum = 0.I64
			for _ in 0..<count {
				match Font.extents(font, 4) {
					Extents(box) => {
						$sum = $sum + box.x_min.to_i64() + box.x_max.to_i64() + box.y_min.to_i64() + box.y_max.to_i64()
					}
					_ => {}
				}
			}
			$sum
		},
	)
	after = Fuzz.live_alloc_count!()
	leaked = if after > before {
		after - before
	} else {
		0
	}
	crash "FMA_DIAGNOSTIC n=${count.to_str()} allocations=${measured.allocations.to_str()} leaked=${leaked.to_str()} checksum=${measured.value.to_str()}"
}

target = Fuzz.target_with!({ name: "outline-fma-diagnostic", generator: Fuzz.raw_bytes, test!, show: |bytes| Str.inspect(bytes) })
