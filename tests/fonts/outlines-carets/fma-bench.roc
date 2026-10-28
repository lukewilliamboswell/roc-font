app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	font: "../../../package/main.roc",
}
import cli.OsStr
import cli.Path
import cli.Stdout
import font.Font

# Native timing harness, without fuzz instrumentation. Input font and
# query count are runtime arguments, so no geometry is precomputed by
# the compiler. Preparation and process startup are included in timings.
main! = |args| {
	path = match args.get(0) {
		Ok(arg) => OsStr.display(arg)
		Err(_) => return Err(Exit(2))
	}
	count = match args.get(1) {
		Ok(arg) => U64.from_str(OsStr.display(arg)) ?? 0
		Err(_) => 0
	}
	if count > 1000000 {
		return Err(Exit(2))
	}
	bytes = Path.read_bytes!(Path.utf8(path))?
	read = match Font.from_bytes(bytes, Font.ReadOptions.{}) {
		Ok(font) => font
		Err(problems) => crash Str.inspect(problems)
	}
	font = Font.at(read, Font.Variation.{ weight: Weight(650), width: Percent(87.5) })
	var $sum = 0.I64
	for _ in 0..<count {
		match Font.extents(font, 4) {
			Extents(box) => {
				$sum = $sum + box.x_min.to_i64() + box.x_max.to_i64() + box.y_min.to_i64() + box.y_max.to_i64()
			}
			_ => {}
		}
	}
	Stdout.line!($sum.to_str())?
	Ok({})
}
