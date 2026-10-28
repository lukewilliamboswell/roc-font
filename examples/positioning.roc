app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	font: "../package/main.roc",
}

import cli.Stdout
import font.Font

## Combining marks are positioned by the font, including marks above a
## ligature. A renderer adds each offset to its pen position before drawing
## the glyph, then moves the pen by the advance. Values are font units.
main! = |_args| {
	run = Font.shape(Font.serif, "x\u(0304)\u(0307) fi\u(035C)", Font.ShapeOptions.{})
	var $pen = 0.I64
	for i in 0..<run.glyphs.len() {
		offset = run.offsets.get(i) ?? { x: 0, y: 0 }
		advance = run.advances.get(i) ?? { x: 0, y: 0 }
		glyph = run.glyphs.get(i) ?? 0
		Stdout.line!("glyph ${glyph.to_str()} at ${($pen + offset.x.to_i64()).to_str()},${offset.y.to_str()}")?
		$pen = $pen + advance.x.to_i64()
	}
	Ok({})
}
