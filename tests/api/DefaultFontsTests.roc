import font.Font

DefaultFontsTests :: {}.{}

expect {
	font = Font.sans
	match Font.from_bytes(Font.sans_bytes, Font.ReadOptions.{}) {
		Err(_) => False
		Ok(read) => Font.dropped(font).is_empty() and Font.dropped(read).is_empty()
			and Font.axes(font).is_empty()
			and Font.metrics(font) == Font.metrics(read)
			and Font.code_points(font) == Font.code_points(read)
			and ["", "Hello, world!", "AVATAR office", "⌘K", "café — Привет"].all(|text| Font.shape(font, text, Font.ShapeOptions.{}) == Font.shape(read, text, Font.ShapeOptions.{}))
	}
}
expect (
	match Font.glyph(Font.sans, 0x2318) {
		Ok(_) => True
		Err(_) => False
	}
) == True

expect {
	font = Font.sans_bold
	match Font.from_bytes(Font.sans_bold_bytes, Font.ReadOptions.{}) {
		Err(_) => False
		Ok(read) => Font.dropped(font).is_empty() and Font.dropped(read).is_empty()
			and Font.axes(font).is_empty()
			and Font.metrics(font) == Font.metrics(read)
			and Font.code_points(font) == Font.code_points(read)
			and ["", "Hello, world!", "AVATAR office", "⌘K", "café — Привет"].all(|text| Font.shape(font, text, Font.ShapeOptions.{}) == Font.shape(read, text, Font.ShapeOptions.{}))
	}
}
expect (
	match Font.glyph(Font.sans_bold, 0x2318) {
		Ok(_) => True
		Err(_) => False
	}
) == True

expect {
	font = Font.sans_italic
	match Font.from_bytes(Font.sans_italic_bytes, Font.ReadOptions.{}) {
		Err(_) => False
		Ok(read) => Font.dropped(font).is_empty() and Font.dropped(read).is_empty()
			and Font.axes(font).is_empty()
			and Font.metrics(font) == Font.metrics(read)
			and Font.code_points(font) == Font.code_points(read)
			and ["", "Hello, world!", "AVATAR office", "⌘K", "café — Привет"].all(|text| Font.shape(font, text, Font.ShapeOptions.{}) == Font.shape(read, text, Font.ShapeOptions.{}))
	}
}
expect (
	match Font.glyph(Font.sans_italic, 0x2318) {
		Ok(_) => True
		Err(_) => False
	}
) == True

expect {
	font = Font.sans_bold_italic
	match Font.from_bytes(Font.sans_bold_italic_bytes, Font.ReadOptions.{}) {
		Err(_) => False
		Ok(read) => Font.dropped(font).is_empty() and Font.dropped(read).is_empty()
			and Font.axes(font).is_empty()
			and Font.metrics(font) == Font.metrics(read)
			and Font.code_points(font) == Font.code_points(read)
			and ["", "Hello, world!", "AVATAR office", "⌘K", "café — Привет"].all(|text| Font.shape(font, text, Font.ShapeOptions.{}) == Font.shape(read, text, Font.ShapeOptions.{}))
	}
}
expect (
	match Font.glyph(Font.sans_bold_italic, 0x2318) {
		Ok(_) => True
		Err(_) => False
	}
) == True

expect {
	font = Font.serif
	match Font.from_bytes(Font.serif_bytes, Font.ReadOptions.{}) {
		Err(_) => False
		Ok(read) => Font.dropped(font).is_empty() and Font.dropped(read).is_empty()
			and Font.axes(font).is_empty()
			and Font.metrics(font) == Font.metrics(read)
			and Font.code_points(font) == Font.code_points(read)
			and ["", "Hello, world!", "AVATAR office", "⌘K", "café — Привет"].all(|text| Font.shape(font, text, Font.ShapeOptions.{}) == Font.shape(read, text, Font.ShapeOptions.{}))
	}
}
expect (
	match Font.glyph(Font.serif, 0x2318) {
		Ok(_) => True
		Err(_) => False
	}
) == False

expect {
	font = Font.serif_bold
	match Font.from_bytes(Font.serif_bold_bytes, Font.ReadOptions.{}) {
		Err(_) => False
		Ok(read) => Font.dropped(font).is_empty() and Font.dropped(read).is_empty()
			and Font.axes(font).is_empty()
			and Font.metrics(font) == Font.metrics(read)
			and Font.code_points(font) == Font.code_points(read)
			and ["", "Hello, world!", "AVATAR office", "⌘K", "café — Привет"].all(|text| Font.shape(font, text, Font.ShapeOptions.{}) == Font.shape(read, text, Font.ShapeOptions.{}))
	}
}
expect (
	match Font.glyph(Font.serif_bold, 0x2318) {
		Ok(_) => True
		Err(_) => False
	}
) == False

expect {
	font = Font.serif_italic
	match Font.from_bytes(Font.serif_italic_bytes, Font.ReadOptions.{}) {
		Err(_) => False
		Ok(read) => Font.dropped(font).is_empty() and Font.dropped(read).is_empty()
			and Font.axes(font).is_empty()
			and Font.metrics(font) == Font.metrics(read)
			and Font.code_points(font) == Font.code_points(read)
			and ["", "Hello, world!", "AVATAR office", "⌘K", "café — Привет"].all(|text| Font.shape(font, text, Font.ShapeOptions.{}) == Font.shape(read, text, Font.ShapeOptions.{}))
	}
}
expect (
	match Font.glyph(Font.serif_italic, 0x2318) {
		Ok(_) => True
		Err(_) => False
	}
) == False

expect {
	font = Font.serif_bold_italic
	match Font.from_bytes(Font.serif_bold_italic_bytes, Font.ReadOptions.{}) {
		Err(_) => False
		Ok(read) => Font.dropped(font).is_empty() and Font.dropped(read).is_empty()
			and Font.axes(font).is_empty()
			and Font.metrics(font) == Font.metrics(read)
			and Font.code_points(font) == Font.code_points(read)
			and ["", "Hello, world!", "AVATAR office", "⌘K", "café — Привет"].all(|text| Font.shape(font, text, Font.ShapeOptions.{}) == Font.shape(read, text, Font.ShapeOptions.{}))
	}
}
expect (
	match Font.glyph(Font.serif_bold_italic, 0x2318) {
		Ok(_) => True
		Err(_) => False
	}
) == False

expect {
	font = Font.mono
	match Font.from_bytes(Font.mono_bytes, Font.ReadOptions.{}) {
		Err(_) => False
		Ok(read) => Font.dropped(font).is_empty() and Font.dropped(read).is_empty()
			and Font.axes(font).is_empty()
			and Font.metrics(font) == Font.metrics(read)
			and Font.code_points(font) == Font.code_points(read)
			and ["", "Hello, world!", "AVATAR office", "⌘K", "café — Привет"].all(|text| Font.shape(font, text, Font.ShapeOptions.{}) == Font.shape(read, text, Font.ShapeOptions.{}))
	}
}
expect (
	match Font.glyph(Font.mono, 0x2318) {
		Ok(_) => True
		Err(_) => False
	}
) == True

expect {
	font = Font.mono_bold
	match Font.from_bytes(Font.mono_bold_bytes, Font.ReadOptions.{}) {
		Err(_) => False
		Ok(read) => Font.dropped(font).is_empty() and Font.dropped(read).is_empty()
			and Font.axes(font).is_empty()
			and Font.metrics(font) == Font.metrics(read)
			and Font.code_points(font) == Font.code_points(read)
			and ["", "Hello, world!", "AVATAR office", "⌘K", "café — Привет"].all(|text| Font.shape(font, text, Font.ShapeOptions.{}) == Font.shape(read, text, Font.ShapeOptions.{}))
	}
}
expect (
	match Font.glyph(Font.mono_bold, 0x2318) {
		Ok(_) => True
		Err(_) => False
	}
) == True

expect Font.code_points(Font.sans).len() == 2852

expect Font.code_points(Font.sans_bold).len() == 2852

expect Font.code_points(Font.sans_italic).len() == 2816

expect Font.code_points(Font.sans_bold_italic).len() == 2816

expect Font.code_points(Font.serif).len() == 1423

expect Font.code_points(Font.serif_bold).len() == 1423

expect Font.code_points(Font.serif_italic).len() == 1422

expect Font.code_points(Font.serif_bold_italic).len() == 1422

expect Font.code_points(Font.mono).len() == 1586

expect Font.code_points(Font.mono_bold).len() == 1586

expect Font.glyph(Font.serif, 0xA69C) != Err(Missing)
expect Font.glyph(Font.serif_italic, 0xA69C) == Err(Missing)
expect Font.glyph(Font.serif, 0x03A0) == Err(Missing)
expect Font.glyph(Font.serif_italic, 0x03A0) != Err(Missing)
expect Font.shape(Font.serif, "⌘K", Font.ShapeOptions.{}).flags.any(Font.is_missing)
expect !Font.shape(Font.sans, "⌘K", Font.ShapeOptions.{}).flags.any(Font.is_missing)
