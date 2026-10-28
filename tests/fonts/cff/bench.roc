app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	font: "../../../package/main.roc",
}
import cli.OsStr
import cli.Path
import cli.Stdout
import font.Font
import CffBench

main! = |args| {
	file = OsStr.display(args.get(0) ?? return Err(Exit(2)))
	count = U64.from_str(OsStr.display(args.get(1) ?? return Err(Exit(2)))) ?? 0
	mode = U8.from_str(OsStr.display(args.get(2) ?? return Err(Exit(2)))) ?? 0
	if count > 1000000 {
		return Err(Exit(2))
	}
	bytes = Path.read_bytes!(Path.utf8(file))?
	read = CffBench.read(bytes) ?? crash "CFF benchmark font rejected"
	font = if (mode == 2) Font.at(read, Font.Variation.{ weight: Weight(500) }) else read
	var $sum = 0.F64
	for _ in 0..<count {
		$sum = $sum + CffBench.query(font, mode)
	}
	Stdout.line!($sum.to_str())?
	Ok({})
}
