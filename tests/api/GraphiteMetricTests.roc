import font.Font
import "../fonts/graphite-metrics/cache-edge-padding0-metric1.otf" as short_bearing : List(U8)
import "../fonts/graphite-metrics/cache-edge-padding1-metric1.otf" as padded_bearing : List(U8)
import "../fonts/graphite-metrics/cache-edge-padding0-metric8.otf" as short_advance : List(U8)
import "../fonts/graphite-metrics/cache-edge-padding1-metric8.otf" as padded_advance : List(U8)

GraphiteMetricTests :: {}.{}

## The font's final short metric takes the last long advance. An unused
## padding byte must not change this fact. The padded files also provide
## independent Graphite2 oracle answers; its exact-end read bug is retained
## separately from these format-defined expectations.
check = |bytes, y| match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
	Err(_) => False
	Ok(font) => {
		plan = Font.plan(font, Font.ShapeOptions.{ script: "Latn", direction: LeftToRight })
		Font.shaping_engine(plan) == Graphite and Font.advance(font, 3) == 600 and match Font.shape_checked(font, plan, "\u(E003)") {
			Err(_) => False
			Ok(run) => run.glyphs == [3] and run.advances == [{ x: 600, y: 0 }] and run.offsets == [{ x: 0, y }] and run.clusters == [0] and run.flags == [0]
		}
	}
}

expect check(short_bearing, 300) and check(padded_bearing, 300)
expect check(short_advance, 600) and check(padded_advance, 600)
