app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	font: "../../../package/main.roc",
}

import cli.Monotonic
import cli.OsStr
import cli.Stderr
import cli.Stdin
import cli.Stdout
import ComplexBench

## Benchmark driver for scripts/bench.py. It reads one case file (see
## ComplexBench) from stdin, prepares it, then runs the operation `iterations`
## times (the last argument) inside the timed region and prints one JSON line:
## {"iterations", "elapsed_ns", "successes", "checksum"}.
main! : List(OsStr) => Try({}, _)
main! = |args| {
	iterations = match args.last() {
		Ok(arg) => U64.from_str(OsStr.display(arg)) ?? 1
		Err(_) => 1
	}
	input = Stdin.read_to_end!()?
	match ComplexBench.prepare(input) {
		Err(message) => {
			Stderr.line!("bench case: ${message}")?
			Err(Exit(2))
		}
		Ok(prepared) => {
			repetitions = List.repeat({}, iterations)
			start = Monotonic.now!()
			var $checksum = 0.U64
			var $successes = 0.U64
			for _ in repetitions {
				match ComplexBench.run(prepared) {
					Ok(sum) => {
						$checksum = $checksum.plus_wrap(sum)
						$successes = $successes + 1
					}
					Err(sum) => {
						$checksum = $checksum.plus_wrap(sum)
					}
				}
			}
			elapsed = start.elapsed!().to_nanos()
			Stdout.line!("{\"script\":\"${prepared.script}\",\"utf8_bytes\":${prepared.text.to_utf8().len().to_str()},\"input_checksum\":${ComplexBench.input_checksum(prepared).to_str()},\"iterations\":${iterations.to_str()},\"elapsed_ns\":${elapsed.to_str()},\"successes\":${$successes.to_str()},\"checksum\":${$checksum.to_str()}}")?
			Ok({})
		}
	}
}
