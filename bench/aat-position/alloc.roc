app [target] {
	font: "../../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}
import fuzz.Fuzz
import AatPositionBench
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	prepared = AatPositionBench.prepare(bytes)
	before = Fuzz.live_alloc_count!()
	measured = Fuzz.measure_allocs!(|{}| AatPositionBench.run(prepared))
	after = Fuzz.live_alloc_count!()
	leaked = if (after > before) after - before else 0
	crash "ALLOCATION_DIAGNOSTIC allocations=${measured.allocations.to_str()} leaked=${leaked.to_str()} checksum=${measured.value.to_str()}"
}

target = Fuzz.target_with!({ name: "variation-alloc", generator: Fuzz.raw_bytes, test!, show: |bytes| Str.inspect(bytes.take_first(32)) })
