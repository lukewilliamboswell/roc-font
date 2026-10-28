import TableCffPath
import TableCffBlend

## Checked Type 2 drawing operators, shared by the eager proof and queries.
TableCffDraw :: {}.{
	at : List(TableCffBlend.Arg), U64 -> TableCffBlend.Arg
	at = |args, i| args.get(i) ?? TableCffBlend.arg(0)
	apply : TableCffPath.State, List(TableCffBlend.Arg), U64 -> Try(TableCffPath.State, [Bad, OverLimit(Str)])
	apply = |path, args, op| {
		n = args.len()
		zero = TableCffBlend.arg(0)
		var $path = path
		if op == 4 or op == 21 or op == 22 {
			if op == 21 {
				if n != 2 {
					return Err(Bad)
				}
				$path = TableCffPath.move($path, TableCffDraw.at(args, 0), TableCffDraw.at(args, 1))?
			} else {
				if n != 1 {
					return Err(Bad)
				}
				$path = TableCffPath.move($path, if (op == 22) TableCffDraw.at(args, 0) else zero, if (op == 4) TableCffDraw.at(args, 0) else zero)?
			}
		} else if op == 5 {
			if n < 2 or n % 2 != 0 {
				return Err(Bad)
			}
			for i in 0..<(n / 2) {
				$path = TableCffPath.line($path, TableCffDraw.at(args, i * 2), TableCffDraw.at(args, i * 2 + 1))?
			}
		} else if op == 6 or op == 7 {
			if n == 0 {
				return Err(Bad)
			}
			for i in 0..<n {
				horizontal = (i % 2 == 0) == (op == 6)
				$path = TableCffPath.line($path, if (horizontal) TableCffDraw.at(args, i) else zero, if (horizontal) zero else TableCffDraw.at(args, i))?
			}
		} else if op == 8 or op == 24 or op == 25 {
			if op == 8 {
				if n < 6 or n % 6 != 0 {
					return Err(Bad)
				}
			} else if op == 24 {
				if n < 8 or (n - 2) % 6 != 0 {
					return Err(Bad)
				}
			} else if n < 8 or (n - 6) % 2 != 0 {
				return Err(Bad)
			}
			line_count = if (op == 25) (n - 6) / 2 else 0
			for i in 0..<line_count {
				$path = TableCffPath.line($path, TableCffDraw.at(args, i * 2), TableCffDraw.at(args, i * 2 + 1))?
			}
			curve_count = if (op == 24) (n - 2) / 6 else if (op == 25) 1 else n / 6
			for i in 0..<curve_count {
				start = line_count * 2 + i * 6
				$path = TableCffPath.curve($path, TableCffDraw.at(args, start), TableCffDraw.at(args, start + 1), TableCffDraw.at(args, start + 2), TableCffDraw.at(args, start + 3), TableCffDraw.at(args, start + 4), TableCffDraw.at(args, start + 5))?
			}
			if op == 24 {
				$path = TableCffPath.line($path, TableCffDraw.at(args, n - 2), TableCffDraw.at(args, n - 1))?
			}
		} else if op == 26 or op == 27 {
			if n < 4 or (n % 4 != 0 and n % 4 != 1) {
				return Err(Bad)
			}
			extra = n % 4
			for i in 0..<(n / 4) {
				start = extra + i * 4
				first = if (extra == 1 and i == 0) TableCffDraw.at(args, 0) else zero
				if op == 26 {
					$path = TableCffPath.curve($path, first, TableCffDraw.at(args, start), TableCffDraw.at(args, start + 1), TableCffDraw.at(args, start + 2), zero, TableCffDraw.at(args, start + 3))?
				} else {
					$path = TableCffPath.curve($path, TableCffDraw.at(args, start), first, TableCffDraw.at(args, start + 1), TableCffDraw.at(args, start + 2), TableCffDraw.at(args, start + 3), zero)?
				}
			}
		} else if op == 30 or op == 31 {
			if n < 4 or (n % 4 != 0 and n % 4 != 1) {
				return Err(Bad)
			}
			curves = n / 4
			for i in 0..<curves {
				start = i * 4
				extra = if (n % 4 == 1 and i + 1 == curves) TableCffDraw.at(args, n - 1) else zero
				horizontal = (i % 2 == 0) == (op == 31)
				if horizontal {
					$path = TableCffPath.curve($path, TableCffDraw.at(args, start), zero, TableCffDraw.at(args, start + 1), TableCffDraw.at(args, start + 2), extra, TableCffDraw.at(args, start + 3))?
				} else {
					$path = TableCffPath.curve($path, zero, TableCffDraw.at(args, start), TableCffDraw.at(args, start + 1), TableCffDraw.at(args, start + 2), TableCffDraw.at(args, start + 3), extra)?
				}
			}
		} else if op == 290 {
			if n != 7 {
				return Err(Bad)
			}
			$path = TableCffPath.curve($path, TableCffDraw.at(args, 0), zero, TableCffDraw.at(args, 1), TableCffDraw.at(args, 2), TableCffDraw.at(args, 3), zero)?
			$path = TableCffPath.curve($path, TableCffDraw.at(args, 4), zero, TableCffDraw.at(args, 5), TableCffPath.neg(TableCffDraw.at(args, 2)), TableCffDraw.at(args, 6), zero)?
		} else if op == 291 {
			if n != 13 {
				return Err(Bad)
			}
			for i in 0..<2 {
				start = i * 6
				$path = TableCffPath.curve($path, TableCffDraw.at(args, start), TableCffDraw.at(args, start + 1), TableCffDraw.at(args, start + 2), TableCffDraw.at(args, start + 3), TableCffDraw.at(args, start + 4), TableCffDraw.at(args, start + 5))?
			}
		} else if op == 292 {
			if n != 9 {
				return Err(Bad)
			}
			dy = TableCffPath.neg(TableCffPath.add(TableCffPath.add(TableCffDraw.at(args, 1), TableCffDraw.at(args, 3), path.checking), TableCffDraw.at(args, 7), path.checking))
			$path = TableCffPath.curve($path, TableCffDraw.at(args, 0), TableCffDraw.at(args, 1), TableCffDraw.at(args, 2), TableCffDraw.at(args, 3), TableCffDraw.at(args, 4), zero)?
			$path = TableCffPath.curve($path, TableCffDraw.at(args, 5), zero, TableCffDraw.at(args, 6), TableCffDraw.at(args, 7), TableCffDraw.at(args, 8), dy)?
		} else if op == 293 {
			if n != 11 {
				return Err(Bad)
			}
			var $sx = zero
			var $sy = zero
			for i in 0..<5 {
				$sx = TableCffPath.add($sx, TableCffDraw.at(args, i * 2), path.checking)
				$sy = TableCffPath.add($sy, TableCffDraw.at(args, i * 2 + 1), path.checking)
			}
			d6 = TableCffDraw.at(args, 10)
			abs_x = if ($sx.value < 0) 0 - $sx.value else $sx.value
			abs_y = if ($sy.value < 0) 0 - $sy.value else $sy.value
			var $last_x = if (abs_x > abs_y) d6 else TableCffPath.neg($sx)
			var $last_y = if (abs_x > abs_y) TableCffPath.neg($sy) else d6
			if path.checking and ($sx.variable or $sy.variable) {
				# Either branch can be selected at a different variation location.
				$last_x = { ..$last_x, variable: True, bound: d6.bound.max($sx.bound) }
				$last_y = { ..$last_y, variable: True, bound: d6.bound.max($sy.bound) }
			}
			$path = TableCffPath.curve($path, TableCffDraw.at(args, 0), TableCffDraw.at(args, 1), TableCffDraw.at(args, 2), TableCffDraw.at(args, 3), TableCffDraw.at(args, 4), TableCffDraw.at(args, 5))?
			$path = TableCffPath.curve($path, TableCffDraw.at(args, 6), TableCffDraw.at(args, 7), TableCffDraw.at(args, 8), TableCffDraw.at(args, 9), $last_x, $last_y)?
		} else {
			return Err(Bad)
		}
		Ok($path)
	}
}

expect {
	match TableCffDraw.apply(TableCffPath.init(True, True, 3, 3), [10, 20, 30, 40, 50].map(TableCffBlend.arg), 31) {
		Ok(path) => path.commands == [MoveTo({ x: 0, y: 0 }), CubicTo({ control1: { x: 10, y: 0 }, control2: { x: 30, y: 30 }, end: { x: 80, y: 70 } })]
		Err(_) => False
	}
}
expect TableCffDraw.apply(TableCffPath.init(False, True, 0, 3), [1, 2, 3].map(TableCffBlend.arg), 26) == Err(Bad)
