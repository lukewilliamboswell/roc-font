app [target] {
	font: "../../../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}
import CffBench
import fuzz.Fuzz

# Prefix0 measures reading;1 extents;2 outlines. Crash is the deliberate
# diagnostic transport used by the repository's allocation harness.
test! = |bytes| {
	mode = bytes.first() ?? 0
	data = bytes.drop_first(1)
	font = CffBench.read(data) ?? crash "CFF allocation font rejected"
	before = Fuzz.live_alloc_count!()
	measured = Fuzz.measure_allocs!(|{}| if (mode == 0) CffBench.reading(data) else CffBench.query(font, mode))
	after = Fuzz.live_alloc_count!()
	if after > before {
		crash "CFF allocation measurement leaked"
	}
	crash "ALLOCATION_DIAGNOSTIC allocations=${measured.allocations.to_str()} checksum=${measured.value.to_str()}"
}

target = Fuzz.target_with!({ name: "cff-alloc", generator: Fuzz.raw_bytes, test!, show: |bytes| Str.inspect(bytes.take_first(8)) })
