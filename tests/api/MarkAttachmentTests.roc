import font.Font
import "../../tests/fonts/mark-attachment/DavidLibre-Regular.ttf" as david : List(U8)

MarkAttachmentTests :: {}.{}

# HarfBuzz 14.6.0, David Libre Regular 1.100, Hebrew language and RTL.
# Hebrew vowels use mark; the accent stack in the same run uses mkmk.
expect {
	font = Font.from_bytes(david, Font.ReadOptions.{ strict: True }) ?? crash "David Libre did not read strictly"
	text = "הֲבֵל א̀́"
	rows = [
		{ disabled: "", xs: [110, 0, 0, 0, 0, 144, 0, 307, 0], ys: [360, 0, 0, 0, 0, 0, 0, 0, 0] },
		{ disabled: "mark", xs: [110, 0, 0, 0, 0, 0, 0, 0, 0], ys: [360, 0, 0, 0, 0, 0, 0, 0, 0] },
		{ disabled: "mkmk", xs: [0, 0, 0, 0, 0, 144, 0, 307, 0], ys: [0, 0, 0, 0, 0, 0, 0, 0, 0] },
	]
	rows.all(
		|row| {
			features = if (row.disabled.is_empty()) [] else [Font.Feature.{ tag: row.disabled, value: 0 }]
			run = Font.shape(font, text, Font.ShapeOptions.{ script: "Hebr", language: "he", direction: RightToLeft, features })
			ok = run.glyphs == [786, 785, 570, 666, 598, 770, 574, 767, 581] and run.clusters == [11, 11, 11, 10, 8, 4, 4, 0, 0]
				and run.advances == [0, 0, 1307, 420, 1020, 0, 1013, 0, 1299].map(|x| { x, y: 0 }) and run.offsets == row.xs.map2(row.ys, |x, y| { x, y })
				and run.flags == List.repeat(0, 9)
			if ok {
				True
			} else {
				crash "David Libre with ${Str.inspect(row.disabled)} disabled: ${Str.inspect(run)}"
			}
		},
	)
}
