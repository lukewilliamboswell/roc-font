app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	font: "../../../package/main.roc",
}

import cli.OsStr
import cli.Path
import cli.Stdin
import cli.Stdout
import font.Font

# Native cached-oracle harness; requests are data, never generated Roc.
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	input = Str.from_utf8(Stdin.read_to_end!()?) ?? ""
	var $cached_file = ""
	var $cached_font = Font.sans
	for line in input.split_on("\n") {
		if !line.is_empty() {
			match line.split_on("\t") {
				[id, file, glyph_text, axis_text] => {
					if file != $cached_file {
						bytes = Path.read_bytes!(Path.utf8(file))?
						$cached_font = match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
							Ok(font) => font
							Err(problems) => crash Str.inspect(problems)
						}
						$cached_file = file
					}
					read = $cached_font
					var $axes = Font.axes(read).map(|axis| { tag: axis.tag, value: axis.default })
					for setting in axis_text.split_on(",") {
						match setting.split_on("=") {
							[tag, value] => {
								$axes = $axes.append({ tag, value: Dec.from_str(value) ?? 0 })
							}
							_ => {}
						}
					}
					font = Font.at(read, Font.Variation.{ axes: $axes })
					glyph_id = U32.from_str(glyph_text) ?? 4294967295
					path_json = match Font.outline(font, glyph_id) {
						Unknown => "null"
						Outline(commands) => "[${Str.join_with(commands.map(command_json), ",")}]"
					}
					extents = match Font.extents(font, glyph_id) {
						Extents(box) => "[${box.x_min.to_str()},${box.y_min.to_str()},${box.x_max.to_str()},${box.y_max.to_str()}]"
						Empty => "null"
						Unknown => "\"unknown\""
					}
					Stdout.line!("${id}\t{\"path\":${path_json},\"extents\":${extents}}")?
				}
				_ => crash "CFF request needs id, font path, glyph and axes"
			}
		}
	}
	Ok({})
}

point_json : Font.OutlinePoint -> Str
point_json = |p| "[${p.x.to_str()},${p.y.to_str()}]"

command_json : Font.OutlineCommand -> Str
command_json = |command| match command {
	MoveTo(p) => "[\"moveTo\",[${point_json(p)}]]"
	LineTo(p) => "[\"lineTo\",[${point_json(p)}]]"
	QuadraticTo(q) => "[\"qCurveTo\",[${point_json(q.control)},${point_json(q.end)}]]"
	CubicTo(c) => "[\"curveTo\",[${point_json(c.control1)},${point_json(c.control2)},${point_json(c.end)}]]"
	Close => "[\"closePath\",[]]"
}
