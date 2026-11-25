import font.Font

ScalarShapingTests := {}.{}

base : U64
base = 4294967419

# HarfBuzz 14.6.0 and Inter-Regular.ttf
# SHA-256 40d692fce188e4471e2b3cba937be967878f631ad3ebbbdcd587687c7ebe0c82.
# HarfBuzz uses UTF-8 byte clusters. The scalar path shifts each start and
# the feature range by the same amount, which keeps the font facts aligned.
expect {
	font = Font.sans
	text = "AV AV"
	options = |start| Font.ShapeOptions.{ features: [Font.Feature.{ tag: "kern", value: 0, start, end: start + 2 }] }
	string_plan = Font.plan(font, options(0))
	scalar_plan = Font.plan(font, options(base))
	scalars = text.to_utf8().map_with_index(|byte, index| { scalar: byte.to_u32(), offset: base + index })
	match (Font.shape_checked(font, string_plan, text), Font.shape_traced(font, string_plan, text), Font.shape_scalars_checked(font, scalar_plan, scalars), Font.shape_scalars_traced(font, scalar_plan, scalars)) {
		(Ok(source), Ok(source_traced), Ok(run), Ok(traced)) =>
			run == { ..source, clusters: source.clusters.map(|offset| base + offset) }
				and run == traced.run
				and traced.origins == source_traced.origins
				and run.glyphs == [2, 456, 1777, 2, 456]
				and run.clusters == [0, 1, 2, 3, 4].map(|offset| base + offset)
				and run.advances == [1413, 1413, 576, 1273, 1413].map(|x| { x, y: 0 })
				and run.offsets == List.repeat({ x: 0, y: 0 }, 5)
				and run.flags.map(Font.is_unsafe_to_break) == [False, False, False, False, True]
		_ => False
	}
}

# HarfBuzz 14.6.0 on the same font with Latn, RTL and default features.
# U+0378 is missing in the font. The original brackets are mirrored by
# shaping and the exclusive end is the end of this run, in source units.
expect {
	font = Font.sans
	plan = Font.plan(font, Font.ShapeOptions.{ script: "Latn", direction: RightToLeft })
	starts = [0, 1, 2, 3, 5].map(|i| base + i)
	scalars = ['(', 'A', 'V', 0x0378, ')'].map2(starts, |scalar, offset| { scalar, offset })
	match (Font.shape_scalars_traced(font, plan, scalars), Font.shape_traced(font, plan, "(AV\u(0378))")) {
		(Ok({ run, origins }), Ok(source)) => {
			ranges = Font.cluster_ranges(run, base + 6)
			run == { ..source.run, clusters: source.run.clusters.map(|i| base + i) }
				and origins == source.origins
				and run.glyphs == [1437, 0, 456, 2, 1447]
				and run.clusters == [5, 3, 2, 1, 0].map(|i| base + i)
				and run.advances == [747, 1344, 1273, 1413, 747].map(|x| { x, y: 0 })
				and run.offsets == List.repeat({ x: 0, y: 0 }, 5)
				and run.flags.map(Font.is_missing) == [False, True, False, False, False]
				and run.flags.map(Font.is_unsafe_to_break) == [False, False, True, True, False]
				and ranges == [(5, 6), (3, 5), (2, 3), (1, 2), (0, 1)].map(|(start, end)| { start: base + start, end: base + end })
		}
		_ => False
	}
}

expect {
	font = Font.sans
	plan = Font.plan(font, Font.ShapeOptions.{})
	[
		([], { index: 0, reason: InvalidScalar(0) }),
		([{ scalar: 0xD800, offset: base }], { index: 0, reason: InvalidScalar(0xD800) }),
		([{ scalar: 'A', offset: base }, { scalar: 0x110000, offset: 0 }], { index: 1, reason: InvalidScalar(0x110000) }),
		([{ scalar: 'A', offset: base }, { scalar: 'B', offset: 0 }, { scalar: 0xDFFF, offset: 0 }], { index: 1, reason: DecreasingOffset({ previous: base, offset: 0 }) }),
	].all(
		|(input, problem)|
			match (Font.shape_scalars_checked(font, plan, input), Font.shape_scalars_traced(font, plan, input)) {
				(Ok(run), Ok(traced)) => input.is_empty() and run.glyphs.is_empty() and run == traced.run and traced.origins.is_empty()
				(Err(InvalidInput(a)), Err(InvalidInput(b))) => a == problem and b == problem
				_ => False
			},
	)
}

expect {
	font = Font.sans
	plan = Font.plan(font, Font.ShapeOptions.{})
	input = [0xD7FF, 0xE000, 0x10FFFF, 0xFFFD].map(|scalar| { scalar, offset: U64.highest })
	match Font.shape_scalars_checked(font, plan, input) {
		Ok(run) => !run.glyphs.is_empty() and run.clusters.all(|offset| offset == U64.highest)
		Err(_) => False
	}
}
