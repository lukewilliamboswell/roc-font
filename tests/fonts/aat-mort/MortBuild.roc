import build.FontBuild

## Original test-only byte recipes. This package imports no roc-font
## implementation module and never enters the shipped package bundle.
MortBuild :: {}.{
	table : U64, List(U8) -> List(U8)
	table = |kind, body| {
		padded = body.concat(List.repeat(0, (4 - body.len() % 4) % 4))
		sub = FontBuild.u16(8 + padded.len()).concat(FontBuild.u16(0x3000 + kind)).concat(FontBuild.u32(1)).concat(padded)
		FontBuild.u32(0x10000).concat(FontBuild.u32(1)).concat(FontBuild.u32(1)).concat(FontBuild.u32(12 + sub.len())).concat(FontBuild.u16(0)).concat(FontBuild.u16(1)).concat(sub)
	}
	contextual : U64, U64 -> List(U8)
	contextual = |states, choice| {
		# At most192actions+one no-op fit the original byte entry indices.
		state_at = 16
		entry_at = state_at + states * 6
		pool_at = entry_at + (states + 1) * 8
		var $body = FontBuild.u16(6).concat(FontBuild.u16(10)).concat(FontBuild.u16(state_at)).concat(FontBuild.u16(entry_at)).concat(FontBuild.u16(pool_at)).concat(FontBuild.u16(1)).concat(FontBuild.u16(2)).concat([4, 5])
		for i in 0..<states {
			$body = $body.concat([0, 0, 0, 0, (i + 1).to_u8_wrap(), 0])
		}
		$body = $body.concat(FontBuild.u16(state_at)).concat(FontBuild.u16(0)).concat(FontBuild.u16(0)).concat(FontBuild.u16(0))
		for i in 0..<states {
			# Visit the highest row first, bounding the reference sanitizer's
			# reachability sweeps as well as this package's preparation.
			next = if i == 0 {
				states - 1
			} else if i == states - 1 {
				1
			} else if i == states - 2 {
				0
			} else {
				i + 1
			}
			$body = $body.concat(FontBuild.u16(state_at + next * 6)).concat(FontBuild.u16(0)).concat(FontBuild.u16(0)).concat(FontBuild.u16(pool_at // 2 - 1 + i))
		}
		for i in 0..<states {
			phase = if i == 0 {
				0
			} else if i == states - 1 {
				1
			} else {
				(i + 1) % 2
			}
			$body = $body.concat(FontBuild.u16(2 + (phase + choice) % 2))
		}
		MortBuild.table(1, $body)
	}
	file : U64, U64 -> List(U8)
	file = |states, choice| {
		characters = FontBuild.cmap([{ system: 3, encoding: 1, subtable: FontBuild.cmap4([{ first: 65, last: 67, delta: 65536 - 64, glyphs: [] }]) }])
		# Keep unrelated font facts constant while only the state/pool size grows.
		FontBuild.glyphs_font(List.repeat(600, 257), characters, [{ tag: "mort", data: MortBuild.contextual(states, choice) }])
	}
}
