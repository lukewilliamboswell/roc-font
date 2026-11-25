app [target] {
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.8.0/BUNcJDHxCd7xLVSe3WBioyXqR6tm1MqXwzwGgtnmqK43.tar.zst",
}

import font.Font
import fuzz.Fuzz

Scalar : { scalar : U32, offset : U64 }

input : List(U8) -> List(Scalar)
input = |bytes| {
	alphabet = ['A', 'V', '(', ')', 'f', 'i', 0x0301, 0x05D0, 0x05D1, 0x200D, 0xD7FF, 0xD800, 0xDFFF, 0xE000, 0x10FFFF, 0x110000]
	mode = bytes.first() ?? 0
	base = if (mode % 4 == 0) 0 else 4294967552
	valid = mode.bitwise_and(4) != 0
	var $offset = base
	var $scalars = []
	for byte in bytes.drop_first(1).take_first(64) {
		selection = byte.to_u64() // 4
		generated = if (selection < 48) alphabet.get(selection % alphabet.len()) ?? 0 else (1048576 * selection).to_u32_wrap()
		scalar = if (valid and (generated > 0x10FFFF or (generated >= 0xD800 and generated <= 0xDFFF))) 0xFFFD else generated
		$offset = match byte % 4 {
			0 => $offset
			1 => $offset + 1
			2 => $offset + 4
			_ => if (valid) $offset + 2 else base
		}
		$scalars = $scalars.append({ scalar, offset: $offset })
	}
	$scalars
}

first_problem : List(Scalar) -> Try({}, { index : U64, reason : Font.ScalarInputProblem })
first_problem = |scalars| {
	for index in 0..<scalars.len() {
		{ scalar, offset } = scalars.get(index) ?? crash "valid index expected"
		valid_scalar = scalar < 0xD800 or (0xE000 <= scalar and scalar < 0x110000)
		if !valid_scalar {
			return Err({ index, reason: InvalidScalar(scalar) })
		}
		if index > 0 {
			previous = (scalars.get(index - 1) ?? crash "valid preceding index expected").offset
			if previous > offset {
				return Err({ index, reason: DecreasingOffset({ previous, offset }) })
			}
		}
	}
	Ok({})
}

aligned : Font.Run, List(Font.GlyphOrigin), List(Scalar), Bool -> Bool
aligned = |run, origins, scalars, rtl| {
	n = run.glyphs.len()
	run.clusters.len() == n and run.offsets.len() == n and run.advances.len() == n and run.flags.len() == n and origins.len() == n
		and run.clusters.all(|offset| scalars.any(|entry| entry.offset == offset))
		and (run.clusters.drop_first(1).map2(run.clusters, |after, before| if (rtl) after <= before else before <= after)).all(|ordered| ordered)
}

target = Fuzz.target_with!({
	name: "font-scalars",
	examples: [],
	generator: Fuzz.raw_bytes,
	test!: |bytes| {
		font = Font.sans
		rtl = (bytes.first() ?? 0) % 2 == 1
		plan = Font.plan(font, Font.ShapeOptions.{ direction: if (rtl) RightToLeft else LeftToRight })
		scalars = input(bytes)
		checked = Font.shape_scalars_checked(font, plan, scalars)
		traced = Font.shape_scalars_traced(font, plan, scalars)
		good = match (first_problem(scalars), checked, traced) {
			(Err(want), Err(InvalidInput(a)), Err(InvalidInput(b))) => a == want and b == want
			(Ok(_), Ok(run), Ok(trace)) => run == trace.run and run == Font.shape_scalars(font, plan, scalars) and aligned(run, trace.origins, scalars, rtl)
			(Ok(_), Err(OverBudget({ run, budgets })), Err(OverBudget(trace))) =>
				budgets == trace.budgets and run == trace.run and run == Font.shape_scalars(font, plan, scalars) and aligned(run, trace.origins, scalars, rtl)
			_ => False
		}
		if !good {
			crash "scalar shaping disagreed for ${Str.inspect(scalars)}"
		}
		Fuzz.keep
	},
	show: Str.inspect,
})
