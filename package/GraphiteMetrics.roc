import Face
import TableGlyf

## Graphite2's unscaled glyph metrics from the font's ordinary default
## glyph cache. The documented metrics are distinct from OpenType mark
## positioning, vertical origins and variation-instance metrics.
GraphiteMetrics := { advances : List(U16), boxes : List(TableGlyf.Bounds) }.{
	make : Face -> GraphiteMetrics
	make = |face| { advances: face.advances, boxes: face.graphite_boxes }

	get : GraphiteMetrics, U64, U64, I32 -> I32
	get = |font, glyph, metric, _level| {
		advance = (font.advances.get(glyph) ?? 0).to_i32()
		box = font.boxes.get(glyph) ?? { x_min: 0, y_min: 0, x_max: 0, y_max: 0 }
		valid = box.x_min <= box.x_max and box.y_min <= box.y_max
		x_min = if (valid) box.x_min else 0
		x_max = if (valid) box.x_max else 0
		y_min = if (valid) box.y_min else 0
		y_max = if (valid) box.y_max else 0
		match metric {
			0 => x_min
			1 => advance - x_max
			2 => y_max
			3 => y_min
			4 => x_min
			5 => x_max
			6 => y_max - y_min
			7 => x_max - x_min
			8 => advance
			# The reference cache has no vertical advance or ascent metric.
			_ => 0
		}
	}
}

expect {
	font = { advances: [601], boxes: [{ x_min: 30, y_min: -20, x_max: 330, y_max: 600 }] }
	values = {
		var $values = []
		for metric in 0..<11 {
			$values = $values.append(GraphiteMetrics.get(font, 0, metric, 0))
		}
		$values
	}
	values == [30, 271, 600, -20, 30, 330, 620, 300, 601, 0, 0] and GraphiteMetrics.get(font, 9, 8, 0) == 0
}
