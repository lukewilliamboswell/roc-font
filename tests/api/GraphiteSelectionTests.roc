import font.Font
import "../fonts/graphite-metrics/cff-only-metric0.otf" as metric0 : List(U8)
import "../fonts/graphite-metrics/cff-only-metric4.otf" as metric4 : List(U8)
import "../fonts/graphite-metrics/cff-only-metric5.otf" as metric5 : List(U8)
import "../fonts/graphite-metrics/cff-only-metric7.otf" as metric7 : List(U8)
import "../fonts/graphite-metrics/cff-only-metric8.otf" as metric8 : List(U8)

GraphiteSelectionTests :: {}.{}

## Valid CFF fonts keep shaping when their optional Graphite programs
## cannot create a reference face. Cached independent default-HB answers
## select OpenType for all five original maxp0.5 controls.
expect {
	[metric0, metric4, metric5, metric7, metric8].all(
		|bytes| match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
			Err(_) => False
			Ok(font) => {
				plan = Font.plan(font, Font.ShapeOptions.{ script: "Latn" })
				Font.shaping_engine(plan) == OpenType and match Font.shape_checked(font, plan, "ab") {
					Err(_) => False
					Ok(run) => run.glyphs == [1, 2] and run.advances == [{ x: 600, y: 0 }, { x: 600, y: 0 }] and run.offsets == [{ x: 0, y: 0 }, { x: 0, y: 0 }] and run.clusters == [0, 1] and run.flags == [0, 0]
				}
			}
		},
	)
}
