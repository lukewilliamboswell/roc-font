import font.Font
import "../fonts/shaping/thai/NotoSansThai-Regular.ttf" as thai_file : List(U8)
import "../fonts/shaping/lao/NotoSansLao-Regular.ttf" as lao_file : List(U8)

## Sara Am behaviour through the bundled public API. Cached real-font
## oracles separately enforce every advance, offset and cluster.
ThaiLaoTests :: {}.{}

expect {
	match Font.from_bytes(thai_file, Font.ReadOptions.{}) {
		Ok(font) => {
			run = Font.shape(font, "ก้ำ", Font.ShapeOptions.{ script: "Thai", clusters: Characters })
			run.glyphs == [29, 59, 49, 86] and run.clusters == [0, 3, 3, 3] and run.offsets == [{ x: 0, y: 0 }, { x: -2, y: 0 }, { x: -31, y: 0 }, { x: 0, y: 0 }]
		}
		Err(_) => False
	}
}

expect {
	match Font.from_bytes(lao_file, Font.ReadOptions.{}) {
		Ok(font) => {
			run = Font.shape(font, "ກ່ຳ", Font.ShapeOptions.{ script: "Laoo" })
			run.glyphs == [9, 109, 60] and run.clusters == [0, 0, 0] and run.advances == [{ x: 614, y: 0 }, { x: 0, y: 0 }, { x: 324, y: 0 }]
		}
		Err(_) => False
	}
}

expect {
	[thai_file, lao_file].all(
		|bytes| match Font.from_bytes(bytes, Font.ReadOptions.{}) {
			Ok(font) => {
				plan = Font.plan(font, Font.ShapeOptions.{ script: "Thai" })
				match Font.shape_checked(font, plan, "") {
					Ok(run) => run.glyphs.is_empty() and run.clusters.is_empty()
					Err(_) => False
				}
			}
			Err(_) => False
		},
	)
}
