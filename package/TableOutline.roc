import TableGlyfPoints
import TableGvar
import TableVar

## Font-unit TrueType paths. Coordinates retain the binary32 evaluation
## used by HarfBuzz for variations and composites, widened exactly to F64.
## No hinting, scaling or pixel rounding is applied. Reading bounded each
## glyph to 200000 points and 16385 component visits, so traversal and path
## output are bounded. Each point emits at most one drawing command, plus
## one move and close per contour (at most three commands per point).
TableOutline :: {}.{
	Point : { x : F64, y : F64 }
	Command : [MoveTo(Point), LineTo(Point), QuadraticTo({ control : Point, end : Point }), CubicTo({ control1 : Point, control2 : Point, end : Point }), Close]

	## Expand only contour topology; component transforms preserve it.
	topology : TableGlyfPoints, U64 -> List({ on_curve : Bool, end : Bool })
	topology = |points, glyph| {
		var $work = [glyph]
		var $out = []
		var $visits = 0
		while !$work.is_empty() and $visits < TableGlyfPoints.visit_limit {
			$visits = $visits + 1
			g = $work.last() ?? glyph
			$work = $work.drop_last(1)
			kind = TableGlyfPoints.kind(points, g)
			if kind == 1 {
				$out = $out.concat(TableGlyfPoints.topology(points, g))
			} else if kind == 2 {
				var $children = []
				var $at = TableGlyfPoints.first_component(points, g)
				for _ in 0..<TableGlyfPoints.point_count(points, g) {
					component = TableGlyfPoints.component(points.glyf, $at)
					$children = $children.append(component.glyph)
					$at = component.next
				}
				for i in 0..<$children.len() {
					$work = $work.append($children.get($children.len() - i - 1) ?? glyph)
				}
			}
		}
		$out
	}

	point_count : TableGlyfPoints, U64 -> U64
	point_count = |points, glyph| TableOutline.topology(points, glyph).len()

	## Exact widening of a finite IEEE binary32 coordinate. Multiplication
	## by powers of two is exact in binary64, including binary32 subnormals.
	widen : U32 -> F64
	widen = |bits| {
		var $value = TableVar.f32_sig(bits).to_u64_wrap().to_f64()
		exponent = TableVar.f32_exp(bits)
		var $remaining = (if (exponent < 0) 0 - exponent else exponent).to_u64_wrap()
		var $factor = if (exponent < 0) 0.5 else 2.F64
		# At most eight iterations; every multiplication is exact.
		while $remaining != 0 {
			if $remaining.bitwise_and(1) != 0 {
				$value = $value * $factor
			}
			$remaining = $remaining.shr_zf_wrap(1)
			$factor = $factor * $factor
		}
		if (TableVar.f32_negative(bits)) 0 - $value else $value
	}

	## Explicit contour point numbering excludes implied on-curve points
	## and the four phantom points, and includes expanded component points.
	point : TableGlyfPoints, TableGvar, TableGvar.Location, U64, U64 -> [Point(Point), Missing]
	point = |points, variations, location, glyph, index| {
		if glyph >= TableGlyfPoints.glyph_total(points) {
			return Missing
		}
		placed = TableGvar.points(points, variations, location, glyph)
		count = placed.xs.len() - 4
		if index >= count {
			Missing
		} else {
			shift = placed.xs.get(count) ?? 0
			x = TableVar.f32_sub(placed.xs.get(index) ?? 0, shift)
			Point({ x: TableOutline.widen(x), y: TableOutline.widen(placed.ys.get(index) ?? 0) })
		}
	}

	commands : TableGlyfPoints, TableGvar, TableGvar.Location, U64 -> List(Command)
	commands = |points, variations, location, glyph| {
		contour_flags = TableOutline.topology(points, glyph)
		if contour_flags.is_empty() {
			return []
		}
		placed = TableGvar.points(points, variations, location, glyph)
		shift = placed.xs.get(contour_flags.len()) ?? 0
		var $coordinates = List.with_capacity(contour_flags.len())
		for index in 0..<contour_flags.len() {
			$coordinates = $coordinates.append({ x: TableVar.f32_sub(placed.xs.get(index) ?? 0, shift), y: placed.ys.get(index) ?? 0 })
		}
		var $out = []
		var $start = 0
		for index in 0..<contour_flags.len() {
			if (contour_flags.get(index) ?? { on_curve: False, end: False }).end {
				$out = TableOutline.contour($coordinates, contour_flags, $start, index + 1, $out)
				$start = index + 1
			}
		}
		$out
	}

	coordinate : { x : U32, y : U32 } -> Point
	coordinate = |p| { x: TableOutline.widen(p.x), y: TableOutline.widen(p.y) }

	midpoint : { x : U32, y : U32 }, { x : U32, y : U32 } -> { x : U32, y : U32 }
	midpoint = |a, b| { x: TableVar.f32_mul(TableVar.f32_add(a.x, b.x), TableVar.f32_half), y: TableVar.f32_mul(TableVar.f32_add(a.y, b.y), TableVar.f32_half) }

	contour : List({ x : U32, y : U32 }), List({ on_curve : Bool, end : Bool }), U64, U64, List(Command) -> List(Command)
	contour = |coordinates, flags, start, end, previous| {
		first = coordinates.get(start) ?? { x: 0, y: 0 }
		last = coordinates.get(end - 1) ?? { x: 0, y: 0 }
		first_on = (flags.get(start) ?? { on_curve: False, end: False }).on_curve
		last_on = (flags.get(end - 1) ?? { on_curve: False, end: False }).on_curve
		origin = if (first_on) first else if (last_on) last else TableOutline.midpoint(last, first)
		from = if (first_on) start + 1 else start
		until = if (!first_on and last_on) end - 1 else end
		var $out = previous.append(MoveTo(TableOutline.coordinate(origin)))
		var $control = origin
		var $pending = False
		for index in from..<until {
			p = coordinates.get(index) ?? { x: 0, y: 0 }
			on_curve = (flags.get(index) ?? { on_curve: False, end: False }).on_curve
			if on_curve {
				$out = if ($pending) $out.append(QuadraticTo({ control: TableOutline.coordinate($control), end: TableOutline.coordinate(p) })) else $out.append(LineTo(TableOutline.coordinate(p)))
				$pending = False
			} else {
				if $pending {
					$out = $out.append(QuadraticTo({ control: TableOutline.coordinate($control), end: TableOutline.coordinate(TableOutline.midpoint($control, p)) }))
				}
				$control = p
				$pending = True
			}
		}
		if $pending {
			$out = $out.append(QuadraticTo({ control: TableOutline.coordinate($control), end: TableOutline.coordinate(origin) }))
		}
		$out.append(Close)
	}
}

expect TableOutline.widen(0x3FC00000) == 1.5 and TableOutline.widen(0xBFC00000) == -1.5
expect TableOutline.widen(0x3F800001) == 1.00000011920928955078125
