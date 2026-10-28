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
				[id, path, settings, ids, mode, direction, text] => {
					bytes = Path.read_bytes!(Path.utf8(path))?
					original = match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
						Ok(f) => f
						Err(ps) => crash Str.inspect(ps)
					}
					axes = settings.split_on(";").keep_oks(
						|setting| match setting.split_on("=") {
							[tag, value] => Ok({ tag, value: Dec.from_str(value) ?? 0 })
							_ => Err({})
						},
					)
					font = Font.at(original, Font.Variation.{ axes })
					glyphs = ids.split_on(",").keep_oks(|g| U32.from_str(g))
					nums = |xs| "[${Str.join_with(xs.map(|n| n.to_str()), ",")}]"
					points = |xs| "[${Str.join_with(xs.map(|p| "[${p.x.to_str()},${p.y.to_str()}]"), ",")}]"
					coords = nums(Font.coordinates(font).map(|c| c.value))
					advances = nums(glyphs.map(|g| Font.advance(font, g)))
					vertical = if mode == "v" {
						",\"vertical\":${nums(glyphs.map(|g| Font.vertical_advance(font, g)))},\"origins\":${points(glyphs.map(|g| Font.vertical_origin(font, g)))}"
					} else ""
					plan = Font.plan(
						font,
						Font.ShapeOptions.{
							script: "Latn",
							language: "en",
							direction: match direction {
								"rtl" => RightToLeft
								"ttb" => TopToBottom
								"btt" => BottomToTop
								_ => LeftToRight
							},
						},
					)
					run = Font.shape_planned(font, plan, text)
					Stdout.line!("${id}\t{\"coords\":${coords},\"metrics\":${advances}${vertical},\"glyphs\":${nums(run.glyphs)},\"advances\":${points(run.advances)},\"offsets\":${points(run.offsets)},\"clusters\":${nums(run.clusters)}}")?
				}
				_ => crash "variation query: id/path/settings/glyphs/mode/direction/text"
			}
		}
	}
	Ok({})
}
