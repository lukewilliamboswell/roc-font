app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	font: "../package/main.roc",
}

import cli.Stdout
import font.Font

# A complete vector consumer of the public outline API. Save stdout as
# glyph.svg; no host font, rasterizer or installed font is needed.
main! = |_args| render!(Font.sans, Font.glyph(Font.sans, 'A') ?? 0)

render! : Font, U32 => Try({}, _)
render! = |font, id| {
	match (Font.outline(font, id), Font.extents(font, id)) {
		(Outline(commands), Extents(bounds)) => {
			path = Str.join_with(commands.map(svg_command), " ")
			width = bounds.x_max - bounds.x_min
			height = bounds.y_max - bounds.y_min
			Stdout.line!("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"${bounds.x_min.to_str()} ${(-bounds.y_max).to_str()} ${width.to_str()} ${height.to_str()}\"><path fill=\"currentColor\" transform=\"scale(1 -1)\" d=\"${path}\"/></svg>")?
		}
		_ => Stdout.line!("The selected glyph has no available outline.")?
	}
	Ok({})
}

svg_point : Font.OutlinePoint -> Str
svg_point = |point| "${point.x.to_str()} ${point.y.to_str()}"

svg_command : Font.OutlineCommand -> Str
svg_command = |command| match command {
	MoveTo(point) => "M ${svg_point(point)}"
	LineTo(point) => "L ${svg_point(point)}"
	QuadraticTo(curve) => "Q ${svg_point(curve.control)} ${svg_point(curve.end)}"
	CubicTo(curve) => "C ${svg_point(curve.control1)} ${svg_point(curve.control2)} ${svg_point(curve.end)}"
	Close => "Z"
}
