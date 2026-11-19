app [target] {
	font: "../../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.6.2/3kyiehxxzwAsjM23uCQGJ3Hx7dAAdzSGtK3k9Jq7Egtu.tar.zst",
}

import fuzz.Fuzz
import FontBench

## Allocation counter for scripts/bench.py; never a fuzz target. The input is
## one case file (see FontBench). The target prepares it, runs the operation
## once inside Fuzz.measure!, and then crashes on purpose to report
## the counts, so exit code 77 is the expected result.
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
			measured = Fuzz.measure!("allocations", || FontBench.run(prepared))
			live_after = Fuzz.live_alloc_count!()
			leaked = if (live_after > live_before) live_after - live_before else 0
			result = match measured.value {
				Ok(sum) => "ok checksum=${sum.to_str()}"
				Err(sum) => "rejected checksum=${sum.to_str()}"
			}
			crash "ALLOCATION_DIAGNOSTIC allocations=${allocation_calls(measured.stats).to_str()} leaked=${leaked.to_str()} result=${result}"
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

# The previous counter included both allocation and reallocation calls.
# Keep the existing growth bounds on that same quantity.
allocation_calls : Fuzz.Stats -> U64
allocation_calls = |stats| stats.allocs + stats.reallocs
