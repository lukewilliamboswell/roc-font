import TableOutline
import TableCffBlend
import TableCffNumber

## Cubic geometry shared by checked execution and queries. Bounds include
## control points, matching HarfBuzz's CFF extents rather than a tight
## analytical Bézier box. Closing a contour does not reset the current point.
TableCffPath :: {}.{
	Bounds : { empty : Bool, x_min : F64, y_min : F64, x_max : F64, y_max : F64 }
	State : { x : TableCffBlend.Arg, y : TableCffBlend.Arg, open : Bool, draw : Bool, checking : Bool, commands : List(TableOutline.Command), count : U64, limit : U64, bounds : Bounds, envelope : F64 }
	coordinate_limit : F64
	coordinate_limit = 1073741823
	empty_bounds : Bounds
	empty_bounds = { empty: True, x_min: 0, y_min: 0, x_max: 0, y_max: 0 }

	init : Bool, Bool, U64, U64 -> State
	init = |draw, checking, capacity, limit| { x: TableCffBlend.arg(0), y: TableCffBlend.arg(0), open: False, draw, checking, commands: if (draw) List.with_capacity(capacity) else [], count: 0, limit, bounds: TableCffPath.empty_bounds, envelope: 0 }

	include : Bounds, TableOutline.Point -> Bounds
	include = |bounds, point| {
		if bounds.empty {
			{ empty: False, x_min: point.x, y_min: point.y, x_max: point.x, y_max: point.y }
		} else {
			{ empty: False, x_min: bounds.x_min.min(point.x), y_min: bounds.y_min.min(point.y), x_max: bounds.x_max.max(point.x), y_max: bounds.y_max.max(point.y) }
		}
	}

	point : State -> TableOutline.Point
	point = |path| { x: path.x.value, y: path.y.value }

	add : TableCffBlend.Arg, TableCffBlend.Arg, Bool -> TableCffBlend.Arg
	add = |a, b, checking| {
		v = a.value + b.value
		variable = a.variable or b.variable
		bound = if !checking {
			0
		} else if variable {
			TableCffNumber.add_bound(a.bound, b.bound)
		} else {
			if (v < 0) 0 - v else v
		}
		{ value: v, bound, variable }
	}

	neg : TableCffBlend.Arg -> TableCffBlend.Arg
	neg = |a| { ..a, value: 0 - a.value }

	step : State, TableCffBlend.Arg, TableCffBlend.Arg -> Try(State, [OverLimit(Str)])
	step = |path, dx, dy| {
		x = TableCffPath.add(path.x, dx, path.checking)
		y = TableCffPath.add(path.y, dy, path.checking)
		envelope = path.envelope.max(x.bound).max(y.bound)
		if path.checking and envelope > TableCffPath.coordinate_limit {
			Err(OverLimit("CFF glyph coordinate envelope"))
		} else {
			Ok({ ..path, x, y, envelope })
		}
	}

	append : State, TableOutline.Command -> Try(State, [OverLimit(Str)])
	append = |path, command| {
		# Consume the command list before rebuilding the scalar state, so
		# each path operation retains its unique output buffer.
		{ x, y, open, draw, checking, commands, count, limit, bounds, envelope } = path
		if count >= limit {
			Err(OverLimit("CFF glyph command count"))
		} else {
			Ok({ x, y, open, draw, checking, commands: if (draw) commands.append(command) else commands, count: count + 1, limit, bounds, envelope })
		}
	}

	close : State -> Try(State, [OverLimit(Str)])
	close = |path| {
		if path.open {
			TableCffPath.append({ ..path, open: False }, Close)
		} else {
			Ok(path)
		}
	}

	move : State, TableCffBlend.Arg, TableCffBlend.Arg -> Try(State, [OverLimit(Str)])
	move = |path, dx, dy| {
		closed = TableCffPath.close(path)?
		moved = TableCffPath.step(closed, dx, dy)?
		TableCffPath.append({ ..moved, open: True }, MoveTo(TableCffPath.point(moved)))
	}

	start_drawing : State -> Try(State, [OverLimit(Str)])
	start_drawing = |path| {
		origin = TableCffPath.point(path)
		started = if path.open {
			path
		} else {
			TableCffPath.append({ ..path, open: True }, MoveTo(origin))?
		}
		Ok({ ..started, bounds: TableCffPath.include(started.bounds, origin) })
	}

	line : State, TableCffBlend.Arg, TableCffBlend.Arg -> Try(State, [OverLimit(Str)])
	line = |path, dx, dy| {
		started = TableCffPath.start_drawing(path)?
		moved = TableCffPath.step(started, dx, dy)?
		end = TableCffPath.point(moved)
		TableCffPath.append({ ..moved, bounds: TableCffPath.include(moved.bounds, end) }, LineTo(end))
	}

	curve : State, TableCffBlend.Arg, TableCffBlend.Arg, TableCffBlend.Arg, TableCffBlend.Arg, TableCffBlend.Arg, TableCffBlend.Arg -> Try(State, [OverLimit(Str)])
	curve = |path, dx1, dy1, dx2, dy2, dx3, dy3| {
		started = TableCffPath.start_drawing(path)?
		first = TableCffPath.step(started, dx1, dy1)?
		control1 = TableCffPath.point(first)
		second = TableCffPath.step(first, dx2, dy2)?
		control2 = TableCffPath.point(second)
		last = TableCffPath.step(second, dx3, dy3)?
		end = TableCffPath.point(last)
		bounds = TableCffPath.include(TableCffPath.include(TableCffPath.include(last.bounds, control1), control2), end)
		TableCffPath.append({ ..last, bounds }, CubicTo({ control1, control2, end }))
	}
}

expect {
	start = TableCffPath.init(True, True, 4, 4)
	match TableCffPath.move(start, TableCffBlend.arg(10), TableCffBlend.arg(20)) {
		Ok(moved) => match TableCffPath.curve(moved, TableCffBlend.arg(20), TableCffBlend.arg(50), TableCffBlend.arg(30), TableCffBlend.arg(-100), TableCffBlend.arg(40), TableCffBlend.arg(50)) {
			Ok(curved) => match TableCffPath.close(curved) {
				Ok(closed) => closed.commands == [MoveTo({ x: 10, y: 20 }), CubicTo({ control1: { x: 30, y: 70 }, control2: { x: 60, y: -30 }, end: { x: 100, y: 20 } }), Close] and closed.bounds == { empty: False, x_min: 10, y_min: -30, x_max: 100, y_max: 70 } and closed.x.value == 100
				Err(_) => False
			}
			Err(_) => False
		}
		Err(_) => False
	}
}
expect TableCffPath.step(TableCffPath.init(False, True, 0, 10), TableCffBlend.arg(1073741824), TableCffBlend.arg(0)) == Err(OverLimit("CFF glyph coordinate envelope"))
