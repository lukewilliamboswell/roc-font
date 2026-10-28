app [target] {
	font: "../../../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}
import MortBench
import fuzz.Fuzz
test! = |bytes| {
	mode = bytes.first() ?? 0
	length = (bytes.get(1) ?? 0).to_u64() * 256 + (bytes.get(2) ?? 0).to_u64()
	if length > 1024 {
		crash "invalid mort benchmark length"
	}
	file = bytes.drop_first(3)
	prepared = MortBench.prepare(file, length) ?? crash "mort allocation font rejected"
	before = Fuzz.live_alloc_count!()
	measured = Fuzz.measure_allocs!(|{}| if (mode == 0) MortBench.reading(file) else MortBench.run(prepared))
	after = Fuzz.live_alloc_count!()
	if after > before {
		crash "mort allocation measurement leaked"
	}
	crash "ALLOCATION_DIAGNOSTIC allocations=${measured.allocations.to_str()} checksum=${measured.value.to_str()}"
}

target = Fuzz.target_with!({ name: "mort-alloc", generator: Fuzz.raw_bytes, test!, show: |bytes| Str.inspect(bytes.take_first(8)) })
