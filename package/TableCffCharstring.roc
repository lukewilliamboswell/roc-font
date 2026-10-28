import Bytes
import TableCffIndex
import TableCffNumber
import TableCffBlend
import TableCffCalc
import TableCffPath
import TableCffDraw

## Iterative Type 2 interpreter. The reader executes it with interval proofs;
## a query reuses the proven instruction and output bounds.
TableCffCharstring :: {}.{
	Seac : [Absent, Present({ dx : F64, dy : F64, base : U64, accent : U64 })]
	Result : { path : TableCffPath.State, operations : U64, stack : U64, calls : U64, seac : Seac }
	Config : { cff2 : Bool, globals : TableCffIndex.Index, locals : TableCffIndex.Index, ivs : U64, seed : U32, operation_limit : U64, command_limit : U64 }
	bias : U64 -> I64
	bias = |count| if (count < 1240) 107 else if (count < 33900) 1131 else 32768
	natural : TableCffBlend.Arg, U64 -> Try(U64, [Bad])
	natural = |a, maximum| {
		if a.variable or a.value < 0 or a.value > maximum.to_f64() {
			return Err(Bad)
		}
		i = a.value.to_u64_try() ?? return Err(Bad)
		if i.to_f64() != a.value {
			Err(Bad)
		} else {
			Ok(i)
		}
	}
	run : List(U8), TableCffIndex.Span, Config, TableCffBlend.Regions, List(U32), Bool, Bool, U64 -> Try(Result, [Bad(U64), OverLimit(Str)])
	run = |data, span, config, regions, scalars, checking, draw, capacity| {
		if span.start > span.end or span.end > data.len() {
			return Err(Bad(span.start))
		}
		var $cursor = span.start
		var $end = span.end
		var $frames = []
		var $calc = TableCffCalc.init(config.seed)
		var $path = TableCffPath.init(draw, checking, capacity, config.command_limit)
		var $operations = 0
		var $max_stack = 0
		var $max_calls = 0
		var $stems = 0
		var $width_seen = config.cff2
		var $ivs = config.ivs
		var $vs_seen = False
		var $blend_seen = False
		var $finished = False
		var $seac = Absent
		for _ in 0..<config.operation_limit {
			if $finished {
				break
			}
			$operations = $operations + 1
			if $cursor == $end {
				if !config.cff2 {
					return Err(Bad($cursor))
				}
				match $frames.last() {
					Ok(frame) => {
						$frames = $frames.take_first($frames.len() - 1)
						$cursor = frame.start
						$end = frame.end
					}
					Err(_) => {
						$finished = True
					}
				}
			} else {
				at = $cursor
				byte = Bytes.u8(data, at)
				if TableCffNumber.is_number(byte, False) {
					number = match TableCffNumber.read(data, at, $end, False) {
						Ok(v) => v
						Err(Bad(offset)) => return Err(Bad(offset))
						Err(OverLimit) => return Err(OverLimit("CFF operand magnitude"))
					}
					$cursor = number.next
					if $calc.args.len() >= (if (config.cff2) 513 else 48) {
						return Err(OverLimit("CFF operand stack"))
					}
					$calc = { ..$calc, args: $calc.args.append(TableCffBlend.arg(number.value)) }
					$max_stack = $max_stack.max($calc.args.len())
				} else {
					$cursor = $cursor + 1
					var $op = byte
					if byte == 12 {
						if $cursor == $end {
							return Err(Bad(at))
						}
						$op = 256 + Bytes.u8(data, $cursor)
						$cursor = $cursor + 1
					}
					if $op == 10 or $op == 29 {
						last = $calc.args.last() ?? return Err(Bad(at))
						if last.variable {
							return Err(Bad(at))
						}
						operand = TableCffCalc.integer(last.value) ?? return Err(Bad(at))
						index = if ($op == 10) config.locals else config.globals
						# Encoded subroutine operands are I16/fixed or checked
						# calculator values; avoid overflowing the bias addition.
						if operand < 0 - TableCffCharstring.bias(index.count) or operand >= index.count.to_i64_wrap() - TableCffCharstring.bias(index.count) {
							return Err(Bad(at))
						}
						selected = (operand + TableCffCharstring.bias(index.count)).to_u64_wrap()
						if $frames.len() >= 10 {
							return Err(OverLimit("CFF subroutine call depth"))
						}
						$frames = $frames.append({ start: $cursor, end: $end })
						$max_calls = $max_calls.max($frames.len())
						$calc = { ..$calc, args: $calc.args.take_first($calc.args.len() - 1) }
						called = TableCffIndex.span(data, index, selected)
						$cursor = called.start
						$end = called.end
					} else if $op == 11 {
						if config.cff2 {
							return Err(Bad(at))
						}
						frame = $frames.last() ?? return Err(Bad(at))
						$frames = $frames.take_first($frames.len() - 1)
						$cursor = frame.start
						$end = frame.end
					} else if $op == 14 {
						if config.cff2 {
							return Err(Bad(at))
						}
						var $args = $calc.args
						if !$width_seen and ($args.len() == 1 or $args.len() == 5) {
							$args = $args.drop_first(1)
						}
						if $args.len() == 4 {
							base = TableCffCharstring.natural(TableCffDraw.at($args, 2), 255) ?? return Err(Bad(at))
							accent = TableCffCharstring.natural(TableCffDraw.at($args, 3), 255) ?? return Err(Bad(at))
							$seac = Present({ dx: TableCffDraw.at($args, 0).value, dy: TableCffDraw.at($args, 1).value, base, accent })
						} else if !$args.is_empty() {
							return Err(Bad(at))
						}
						$finished = True
					} else if $op == 1 or $op == 3 or $op == 18 or $op == 23 or $op == 19 or $op == 20 {
						var $n = $calc.args.len()
						if !$width_seen and $n % 2 == 1 {
							$n = $n - 1
						}
						if $n % 2 != 0 {
							return Err(Bad(at))
						}
						$width_seen = True
						$stems = $stems + $n / 2
						if $stems > 96 {
							return Err(OverLimit("CFF stem hint count"))
						}
						if $op == 19 or $op == 20 {
							length = ($stems + 7) / 8
							if !Bytes.fits($cursor, length, $end) {
								return Err(Bad($cursor))
							}
							$cursor = $cursor + length
						}
						$calc = { ..$calc, args: $calc.args.clear() }
					} else if config.cff2 and $op == 15 {
						if $vs_seen or $blend_seen or $calc.args.len() != 1 {
							return Err(Bad(at))
						}
						selected = TableCffCharstring.natural(TableCffDraw.at($calc.args, 0), 65535) ?? return Err(Bad(at))
						_ = TableCffBlend.region_count(regions, selected) ?? return Err(Bad(at))
						$ivs = selected
						$vs_seen = True
						$calc = { ..$calc, args: $calc.args.clear() }
					} else if config.cff2 and $op == 16 {
						blended = match TableCffBlend.apply($calc.args, regions, $ivs, scalars, checking) {
							Ok(v) => v
							Err(Bad) => return Err(Bad(at))
							Err(OverLimit) => return Err(OverLimit("CFF blend magnitude"))
						}
						$calc = { ..$calc, args: blended }
						$blend_seen = True
					} else if ($op >= 4 and $op <= 8) or $op == 21 or $op == 22 or ($op >= 24 and $op <= 27) or $op == 30 or $op == 31 or ($op >= 290 and $op <= 293) {
						var $args = $calc.args
						if $op == 4 or $op == 21 or $op == 22 {
							expected = if ($op == 21) 2 else 1
							if !$width_seen and $args.len() == expected + 1 {
								$args = $args.drop_first(1)
							}
							$width_seen = True
						}
						$path = match TableCffDraw.apply($path, $args, $op) {
							Ok(v) => v
							Err(Bad) => return Err(Bad(at))
							Err(OverLimit(reason)) => return Err(OverLimit(reason))
						}
						$calc = { ..$calc, args: $args.clear() }
					} else if !config.cff2 and (($op >= 259 and $op <= 261) or $op == 265 or ($op >= 266 and $op <= 268) or $op == 270 or $op == 271 or $op == 274 or ($op >= 276 and $op <= 280) or ($op >= 282 and $op <= 286)) {
						$calc = match TableCffCalc.apply($calc, $op) {
							Ok(v) => v
							Err(Bad) => return Err(Bad(at))
							Err(OverLimit) => return Err(OverLimit("CFF calculator magnitude or stack"))
						}
						$max_stack = $max_stack.max($calc.args.len())
					} else {
						# Both CFF specifications define unknown operators as
						# clearing the operand stack, including future escapes.
						$calc = { ..$calc, args: $calc.args.clear() }
					}
				}
			}
		}
		if !$finished {
			return Err(OverLimit("CFF glyph instruction count"))
		}
		closed = TableCffPath.close($path)?
		Ok({ path: closed, operations: $operations, stack: $max_stack, calls: $max_calls, seac: $seac })
	}
}

test_config : TableCffCharstring.Config
test_config = { cff2: False, globals: TableCffIndex.empty, locals: TableCffIndex.empty, ivs: 0, seed: 987654321, operation_limit: 100, command_limit: 100 }

test_regions : TableCffBlend.Regions
test_regions = { starts: [], indexes: [] }

expect {
	# width500, move10,20; line30,40; endchar.
	data = [248, 136, 149, 159, 21, 169, 179, 5, 14]
	match TableCffCharstring.run(data, { start: 0, end: data.len() }, test_config, test_regions, [], True, True, 4) {
		Ok(result) => result.path.commands == [MoveTo({ x: 10, y: 20 }), LineTo({ x: 40, y: 60 }), Close] and result.seac == Absent
		Err(_) => False
	}
}
expect {
	# CFF2 EOF ends a glyph; unknown escaped operators clear operands.
	data = [149, 12, 255, 159, 169, 21]
	match TableCffCharstring.run(data, { start: 0, end: data.len() }, { ..test_config, cff2: True }, test_regions, [], True, True, 4) {
		Ok(result) => result.path.commands == [MoveTo({ x: 20, y: 30 }), Close]
		Err(_) => False
	}
}
expect TableCffCharstring.run([32, 10, 14], { start: 0, end: 3 }, test_config, test_regions, [], True, False, 0) == Err(Bad(1))
expect TableCffCharstring.run([139, 139, 1, 19], { start: 0, end: 4 }, test_config, test_regions, [], True, False, 0) == Err(Bad(4))
