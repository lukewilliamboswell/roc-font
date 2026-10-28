app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	font: "../../../package/main.roc",
}
import cli.OsStr
import cli.Path
import cli.Stdin
import cli.Stdout
import font.Font

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	for line in Str.from_utf8_lossy(Stdin.read_to_end!()?).split_on("\n") {
		if !line.is_empty() {
			match line.split_on("\t") {
				[id, path, size, direction, text] => {
					bytes = Path.read_bytes!(Path.utf8(path))?
					font = Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "tracking fixture rejected"
					options = Font.ShapeOptions.{
						point_size: Dec.from_str(size) ?? 0,
						script: "Latn",
						direction: match direction {
							"rtl" => RightToLeft
							"ttb" => TopToBottom
							"btt" => BottomToTop
							_ => LeftToRight
						},
					}
					run = Font.shape(font, text, options)
					nums = |xs| "[${Str.join_with(xs.map(|n| n.to_str()), ",")}]"
					points = |xs| "[${Str.join_with(xs.map(|p| "[${p.x.to_str()},${p.y.to_str()}]"), ",")}]"
					Stdout.line!("${id}\t{\"glyphs\":${nums(run.glyphs)},\"advances\":${points(run.advances)},\"offsets\":${points(run.offsets)},\"clusters\":${nums(run.clusters)}}")?
				}
				_ => crash "tracking query: id/path/size/direction/text"
			}
		}
	}
	Ok({})
}
