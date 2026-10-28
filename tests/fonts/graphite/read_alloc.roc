app [target] {
	font: "../../../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}
import font.Font
import fuzz.Fuzz

test! = |bytes| {
	live_before = Fuzz.live_alloc_count!()
	measured = Fuzz.measure_allocs!(
		|{}| {
			font = Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "valid shared-span font rejected"
			Font.glyph_count(font)
		},
	)
	live_after = Fuzz.live_alloc_count!()
	leaked = if (live_after > live_before) live_after - live_before else 0
	crash "ALLOCATION_DIAGNOSTIC allocations=${measured.allocations.to_str()} leaked=${leaked.to_str()} checksum=${measured.value.to_str()}"
}

target = Fuzz.target_with!({ name: "graphite-read-alloc", generator: Fuzz.raw_bytes, test!, show: |bytes| Str.inspect(bytes.take_first(64)) })
