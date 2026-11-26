app [target] {
	font: "../../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.8.0/BUNcJDHxCd7xLVSe3WBioyXqR6tm1MqXwzwGgtnmqK43.tar.zst",
}

import fuzz.Fuzz
import FontBench

## Allocation counter for scripts/bench.py; never a fuzz target. The input is
## one case file (see FontBench). The target prepares it, runs the operation
## once inside Fuzz.measure!, and then crashes on purpose to report
## the counts. The harness uses the native runner's raw single-input mode
## (no exploration), so large benchmark fonts are not limited by the quality
## supervisor's 1 MiB corpus bound. Exit 77 and this exact marker are required.
##
## `allocations` counts every roc_alloc and roc_realloc the operation made.
## `leaked` is how many of them were still live after the operation's result
## (a checksum, which holds no allocation) was produced.
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	match FontBench.prepare(bytes) {
		Err(message) => crash "ALLOCATION_DIAGNOSTIC error=${message}"
		Ok(prepared) => {
			live_before = Fuzz.live_alloc_count!()
			measured = Fuzz.measure!("measured", || FontBench.run(prepared))
			live_after = Fuzz.live_alloc_count!()
			leaked = if (live_after > live_before) live_after - live_before else 0
			result = match measured.value {
				Ok(sum) => "ok checksum=${sum.to_str()}"
				Err(sum) => "rejected checksum=${sum.to_str()}"
			}
			crash "ALLOCATION_DIAGNOSTIC allocations=${(measured.stats.allocs + measured.stats.reallocs).to_str()} leaked=${leaked.to_str()} requested_bytes=${measured.stats.requested_bytes.to_str()} peak_live_bytes=${measured.stats.peak_live_bytes.to_str()} result=${result}"
		}
	}
}

target = Fuzz.target_with!({
	examples: [],
	name: "bench-alloc-diagnostic",
	generator: Fuzz.raw_bytes,
	test!,
	show: |bytes| Str.inspect(bytes.take_first(64)),
})
