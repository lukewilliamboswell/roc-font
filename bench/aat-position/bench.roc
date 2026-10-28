app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	font: "../../package/main.roc",
}
import cli.Monotonic
import cli.OsStr
import cli.Stdin
import cli.Stdout
import AatPositionBench
main! : List(OsStr) => Try({}, _)
main! = |args| {
	iterations = match args.last() {
		Ok(a) => U64.from_str(OsStr.display(a)) ?? 1
		Err(_) => 1
	}
	prepared = AatPositionBench.prepare(Stdin.read_to_end!()?)
	start = Monotonic.now!()
	var $checksum = 0.U64
	for _ in 0..<iterations {
		$checksum = $checksum.plus_wrap(AatPositionBench.run(prepared))
	}
	elapsed = start.elapsed!().to_nanos()
	Stdout.line!("{\"iterations\":${iterations.to_str()},\"elapsed_ns\":${elapsed.to_str()},\"checksum\":${$checksum.to_str()}}")?
	Ok({})
}
