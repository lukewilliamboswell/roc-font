app [target] {
	build: "../tests/support/main.roc",
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}
import fuzz.Fuzz
import font.Font
import build.FontBuild
import "../tests/fonts/outlines-carets/outlines-carets.ttf" as fixture : List(U8)

## Narrow native diagnostic. Replay one byte 0,1,2 for 32,128,512
## queries of a nested, point-attached composite. Intentional crash reports
## deterministic allocation counts, and retains only a scalar checksum.
test! = |bytes| {
	font = match Font.from_bytes(fixture.concat(bytes), Font.ReadOptions.{}) {
		Ok(value) => Font.at(value, Font.Variation.{ weight: Bold })
		Err(_) => crash "fixture rejected"
	}
	count : U64
	count = if (bytes.first() ?? 0) == 0 {
		32
	} else if (bytes.first() ?? 0) == 1 {
		128
	} else {
		512
	}
	if (bytes.get(1) ?? 0) == 1 {
		glyph = FontBuild.simple_glyph([[{ x: 0, y: 0, on: True }, { x: 400, y: 0, on: True }, { x: 400, y: 700, on: True }, { x: 0, y: 700, on: True }]])
		cmap = FontBuild.cmap([{ system: 3, encoding: 1, subtable: FontBuild.cmap4([{ first: 65, last: 65, delta: 65472, glyphs: [] }]) }])
		file = FontBuild.outline_font(List.repeat(glyph, count), List.repeat(600, count), List.repeat(0, count), count, True, cmap, [])
		read = Fuzz.measure_allocs!(
			|{}| match Font.from_bytes(file, Font.ReadOptions.{}) {
				Ok(prepared) => Font.glyph_count(prepared)
				Err(_) => 0
			},
		)
		crash "OUTLINE_READ_DIAGNOSTIC n=${count.to_str()} allocations=${read.allocations.to_str()} checksum=${read.value.to_str()}"
	}
	before = Fuzz.live_alloc_count!()
	measured = Fuzz.measure_allocs!(
		|{}| {
			var $sum = 0.I64
			for _ in 0..<count {
				match Font.extents(font, 5) {
					Extents(box) => {
						$sum = $sum + box.x_min.to_i64() + box.x_max.to_i64()
					}
					_ => {}
				}
			}
			$sum
		},
	)
	after = Fuzz.live_alloc_count!()
	leaked = if (after > before) after - before else 0
	crash "OUTLINE_DIAGNOSTIC n=${count.to_str()} allocations=${measured.allocations.to_str()} leaked=${leaked.to_str()} checksum=${measured.value.to_str()}"
}

target = Fuzz.target_with!({ name: "outline-diagnostic", generator: Fuzz.raw_bytes, test!, show: |bytes| Str.inspect(bytes) })
