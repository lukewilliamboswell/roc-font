import font.Font
import "../fonts/shaping/hangul/NanumGothic-Regular.ttf" as gothic_file : List(U8)
import "../fonts/shaping/hangul-fixtures/decomposed.ttf" as decomposed_file : List(U8)
import "../fonts/shaping/hangul-fixtures/all.ttf" as all_file : List(U8)
import "../fonts/shaping/hangul-fixtures/zero-tone.ttf" as zero_tone_file : List(U8)

## Composition, Jamo masks, tone marks and source clusters through the
## bundled API. Exact matching reference records cover both real families.
HangulTests :: {}.{}

expect {
	match Font.from_bytes(gothic_file, Font.ReadOptions.{}) {
		Ok(font) => {
			options = Font.ShapeOptions.{ script: "Hang" }
			run = Font.shape(font, "한글", options)
			composed = Font.shape(font, "각", options)
			precomposed = Font.shape(font, "각", options)
			run.glyphs == [2705, 647] and run.clusters == [0, 3] and composed.glyphs == precomposed.glyphs and composed.advances == precomposed.advances
		}
		Err(_) => False
	}
}

expect {
	match Font.from_bytes(decomposed_file, Font.ReadOptions.{}) {
		Ok(font) => {
			run = Font.shape(font, "각", Font.ShapeOptions.{ script: "Hang", clusters: Characters })
			run.glyphs == [14, 15, 16] and run.clusters == [0, 3, 6] and run.flags.map(Font.is_unsafe_to_break) == [False, True, True]
		}
		Err(_) => False
	}
}

expect {
	match Font.from_bytes(all_file, Font.ReadOptions.{}) {
		Ok(font) => {
			run = Font.shape(font, "가\u(302E)", Font.ShapeOptions.{ script: "Hang", clusters: Characters })
			run.glyphs == [11, 9] and run.clusters == [0, 0] and run.flags.map(Font.is_unsafe_to_break) == [False, False]
		}
		Err(_) => False
	}
}

expect {
	match Font.from_bytes(zero_tone_file, Font.ReadOptions.{}) {
		Ok(font) => {
			run = Font.shape(font, "가\u(302E)", Font.ShapeOptions.{ script: "Hang", clusters: Characters })
			run.glyphs == [9, 11] and run.clusters == [0, 6] and run.advances == [{ x: 409, y: 0 }, { x: 0, y: 0 }]
		}
		Err(_) => False
	}
}

expect {
	match Font.from_bytes(all_file, Font.ReadOptions.{}) {
		Ok(font) => Font.shape(font, "\u(302E)", Font.ShapeOptions.{ script: "Hang" }).glyphs == [11, 13]
		Err(_) => False
	}
}

expect {
	match Font.from_bytes(gothic_file, Font.ReadOptions.{}) {
		Ok(font) => {
			run = Font.shape(font, "가\u(034F)ᆨ", Font.ShapeOptions.{ script: "Hang" })
			run.glyphs == [495, 13296, 0] and run.clusters == [0, 0, 8]
		}
		Err(_) => False
	}
}

expect {
	match Font.from_bytes(decomposed_file, Font.ReadOptions.{}) {
		Ok(font) => {
			run = Font.shape(font, "가\u(D7CB)", Font.ShapeOptions.{ script: "Hang", clusters: Characters })
			run.glyphs == [14, 15, 8] and run.clusters == [0, 0, 3] and run.flags.map(Font.is_unsafe_to_break) == [False, False, False]
		}
		Err(_) => False
	}
}
