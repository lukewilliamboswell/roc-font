import font.Font
import "../fonts/positioning/flags/zero-first.ttf" as zero_first : List(U8)
import "../fonts/positioning/flags/zero-second.ttf" as zero_second : List(U8)
import "../fonts/positioning/flags/zero-class.ttf" as zero_class : List(U8)
import "../fonts/positioning/flags/vertical-only.ttf" as vertical_only : List(U8)

import "../fonts/positioning/flags/variable-cancellation.ttf" as cancellation : List(U8)

## Zero positioning values still match, without introducing unsafe breaks;
## a second value record also consumes the following boundary.
PositionFlagTests :: {}.{}

expect {
	[zero_first, zero_class].all(
		|bytes| match Font.from_bytes(bytes, Font.ReadOptions.{}) {
			Ok(font) => {
				run = Font.shape(font, "abcd", Font.ShapeOptions.{})
				run.flags.map(Font.is_unsafe_to_break) == [False, False, False, True] and run.advances == [{ x: 600, y: 0 }, { x: 600, y: 0 }, { x: 580, y: 0 }, { x: 600, y: 0 }]
			}
			Err(_) => False
		},
	)
}

expect {
	match Font.from_bytes(zero_second, Font.ReadOptions.{}) {
		Ok(font) => Font.shape(font, "abcd", Font.ShapeOptions.{}).flags.map(Font.is_unsafe_to_break) == [False, True, True, True]
		Err(_) => False
	}
}

expect {
	match Font.from_bytes(vertical_only, Font.ReadOptions.{}) {
		Ok(font) => Font.shape(font, "abcd", Font.ShapeOptions.{}).flags.map(Font.is_unsafe_to_break) == [False, False, False, False]
		Err(_) => False
	}
}

expect {
	match Font.from_bytes(cancellation, Font.ReadOptions.{}) {
		Ok(font) => {
			varied = Font.at(font, Font.Variation.{ axes: [{ tag: "wght", value: 900 }] })
			general = Font.shape(varied, "ab", Font.ShapeOptions.{})
			pair = Font.shape(varied, "ab", Font.ShapeOptions.{ features: [Font.Feature.{ tag: "dist", value: 0 }] })
			general.advances == [{ x: 600, y: 0 }, { x: 600, y: 0 }] and pair.advances == general.advances and pair.flags.map(Font.is_unsafe_to_break) == [False, True] and general.flags == pair.flags
		}
		Err(_) => False
	}
}
