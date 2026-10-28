app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	font: "../../../package/main.roc",
}
import cli.OsStr
import cli.Path
import cli.Stdout
import MortBench
main! = |args| {
	file = OsStr.display(args.get(0) ?? return Err(Exit(2)))
	count = U64.from_str(OsStr.display(args.get(1) ?? return Err(Exit(2)))) ?? 0
	length = U64.from_str(OsStr.display(args.get(2) ?? return Err(Exit(2)))) ?? 0
	if count > 1000000 or length > 1024 {
		return Err(Exit(2))
	}
	prepared = MortBench.prepare(Path.read_bytes!(Path.utf8(file))?, length) ?? crash "mort benchmark font rejected"
	var $sum = 0.I64
	for _ in 0..<count {
		$sum = $sum + MortBench.run(prepared)
	}
	Stdout.line!($sum.to_str())?
	Ok({})
}
