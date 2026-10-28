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
main! = |_| {
	for line in Str.from_utf8_lossy(Stdin.read_to_end!()?).split_on("\n") {
		if !line.is_empty() {
			match line.split_on("\t") {
				[id, path, direction, kern, weight, text] => {
					bytes = Path.read_bytes!(Path.utf8(path))?
					original = match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
						Ok(f) => f
						Err(ps) => crash "${id} ${Str.inspect(ps)}"
					}
					font = Font.at(original, Font.Variation.{ axes: [{ tag: "wght", value: Dec.from_str(weight) ?? 0 }] })
					options = Font.ShapeOptions.{
						script: "Latn",
						language: "en",
						direction: match direction {
							"rtl" => RightToLeft
							"ttb" => TopToBottom
							"btt" => BottomToTop
							_ => LeftToRight
						},
						features: [Font.Feature.{ tag: "kern", value: U32.from_str(kern) ?? 1 }, Font.Feature.{ tag: "vkrn", value: U32.from_str(kern) ?? 1 }],
					}
					run = Font.shape(font, text, options)
					nums = |xs| "[${Str.join_with(xs.map(|n| n.to_str()), ",")}]"
					points = |xs| "[${Str.join_with(xs.map(|p| "[${p.x.to_str()},${p.y.to_str()}]"), ",")}]"
					Stdout.line!("${id}\t{\"glyphs\":${nums(run.glyphs)},\"clusters\":${nums(run.clusters)},\"advances\":${points(run.advances)},\"offsets\":${points(run.offsets)}}")?
				}
				_ => crash "AAT query: id/path/direction/kern/weight/text"
			}
		}
	}
	Ok({})
}
