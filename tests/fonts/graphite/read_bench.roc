app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	font: "../../../package/main.roc",
}
import cli.OsStr
import cli.Path
import cli.Monotonic
import cli.Stdout
import font.Font

main! = |args| {
	path = OsStr.display(args.first() ?? crash "caller font path required")
	iterations = U64.from_str(OsStr.display(args.last() ?? crash "iterations required")) ?? 1
	bytes = Path.read_bytes!(Path.utf8(path))?
	repetitions = List.repeat({}, iterations)
	var $sum = 0.U64
	start = Monotonic.now!()
	for _ in repetitions {
		font = Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "accepted Graphite read fixture rejected"
		$sum = $sum + Font.glyph_count(font).to_u64()
	}
	elapsed = start.elapsed!().to_nanos()
	Stdout.line!("{\"iterations\":${iterations.to_str()},\"elapsed_ns\":${elapsed.to_str()},\"checksum\":${$sum.to_str()}}")?
	Ok({})
}
