import font.Font
import "../fonts/shaping/arabic/NotoSansArabic-Regular.ttf" as sans_file : List(U8)
import "../fonts/shaping/arabic/NotoNaskhArabic-Regular.ttf" as naskh_file : List(U8)

## Arabic behaviour with real, unmodified fonts, through the bundle API.
## Exact positions are recorded independently in cases/arabic.jsonc.
ArabicTests :: {}.{}

expect {
	match Font.from_bytes(naskh_file, Font.ReadOptions.{}) {
		Ok(font) => {
			run = Font.shape(font, "ب\u(064E)\u(0654)", Font.ShapeOptions.{ script: "Arab" })
			run.glyphs == [380, 305, 323, 14] and run.offsets == [{ x: 259, y: -225 }, { x: 291, y: -429 }, { x: 308, y: -31 }, { x: 0, y: 0 }]
		}
		Err(_) => False
	}
}

expect {
	match Font.from_bytes(sans_file, Font.ReadOptions.{}) {
		Ok(font) => {
			run = Font.shape(font, "سلام", Font.ShapeOptions.{ script: "Arab", language: "ar" })
			run.glyphs == [74, 11, 71, 37] and run.clusters == [6, 4, 2, 0] and run.advances == [{ x: 484, y: 0 }, { x: 379, y: 0 }, { x: 220, y: 0 }, { x: 784, y: 0 }]
		}
		Err(_) => False
	}
}

expect {
	match Font.from_bytes(naskh_file, Font.ReadOptions.{}) {
		Ok(font) => {
			run = Font.shape(font, "سلام", Font.ShapeOptions.{ script: "Arab", language: "ar" })
			run.glyphs == [72, 11, 69, 35] and run.clusters == [6, 4, 2, 0]
		}
		Err(_) => False
	}
}

expect {
	match Font.from_bytes(naskh_file, Font.ReadOptions.{}) {
		Ok(font) => {
			run = Font.shape(font, "ببب", Font.ShapeOptions.{ script: "Arab" })
			run.glyphs == [323, 15, 323, 16, 323, 19] and run.offsets == [{ x: 338, y: -31 }, { x: 0, y: 0 }, { x: 90, y: -31 }, { x: 0, y: 0 }, { x: 70, y: -31 }, { x: 0, y: 0 }]
		}
		Err(_) => False
	}
}

expect {
	match Font.from_bytes(naskh_file, Font.ReadOptions.{}) {
		Ok(font) => {
			run = Font.shape(font, "ب\u(200C)ب", Font.ShapeOptions.{ script: "Arab" })
			run.glyphs == [323, 14, 3, 323, 14] and run.clusters == [5, 5, 2, 0, 0]
		}
		Err(_) => False
	}
}

expect {
	match Font.from_bytes(naskh_file, Font.ReadOptions.{}) {
		Ok(font) => {
			run = Font.shape(font, "ب\u(200D)ب", Font.ShapeOptions.{ script: "Arab" })
			run.glyphs == [323, 15, 3, 323, 19] and run.clusters == [5, 5, 0, 0, 0]
		}
		Err(_) => False
	}
}

expect {
	[sans_file, naskh_file].all(
		|file| match Font.from_bytes(file, Font.ReadOptions.{}) {
			Ok(font) => {
				plan = Font.plan(font, Font.ShapeOptions.{ script: "Arab" })
				text = "بِسْمِ اللَّهِ"
				a = Font.shape_planned(font, plan, text)
				b = Font.shape_planned(font, plan, text)
				a.glyphs == b.glyphs and a.advances == b.advances and a.offsets == b.offsets and a.clusters == b.clusters and a.glyphs.len() == a.advances.len() and a.glyphs.len() == a.offsets.len() and a.glyphs.len() == a.clusters.len()
			}
			Err(_) => False
		},
	)
}

expect {
	match Font.from_bytes(naskh_file, Font.ReadOptions.{}) {
		Ok(font) => {
			plan = Font.plan(font, Font.ShapeOptions.{ script: "Arab" })
			match Font.shape_checked(font, plan, "") {
				Ok(run) => run.glyphs.is_empty() and run.clusters.is_empty()
				Err(_) => False
			}
		}
		Err(_) => False
	}
}
