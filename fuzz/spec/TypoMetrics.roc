import build.FontBuild
import font.Font

# OpenType defines the OS/2 fields and introduces USE_TYPO_METRICS in
# version 4. Font.metrics selects one complete line-metric tuple. An
# unrequested tuple with one zero extent is usable, with the zero kept.
# FreeType 2.13.2 returns the same tuples for independently built fonts.
# https://learn.microsoft.com/en-us/typography/opentype/spec/os2#fsselection
TypoMetrics := {}.{
	check : {} -> Bool
	check = |_| [
		{ version: 0, use_typo: False, header: (800, 0, 31), typo: (900, -310, 63), expected: (800, 0, 31) },
		{ version: 1, use_typo: False, header: (0, -220, 32), typo: (900, -310, 63), expected: (0, 220, 32) },
		{ version: 2, use_typo: False, header: (0, 0, 33), typo: (900, 0, 64), expected: (900, 0, 64) },
		{ version: 2, use_typo: False, header: (0, 0, 33), typo: (0, -310, 64), expected: (0, 310, 64) },
		{ version: 4, use_typo: False, header: (800, -220, 35), typo: (0, -310, 65), expected: (800, 220, 35) },
		{ version: 4, use_typo: True, header: (800, -220, 35), typo: (0, -310, 65), expected: (0, 310, 65) },
	].all(check_case)
}

Case : { version : U64, use_typo : Bool, header : (I64, I64, I64), typo : (I64, I64, I64), expected : (I32, I32, I32) }

check_case : Case -> Bool
check_case = |case| {
	(header_ascent, header_descent, header_gap) = case.header
	(typo_ascent, typo_descent, typo_gap) = case.typo
	header = FontBuild.patch(FontBuild.hhea(header_ascent, header_descent, 4), 8, FontBuild.i16(header_gap))
	base = FontBuild.replace(FontBuild.basic, "hhea", header)
	os2 = FontBuild.os2({ use_typo: case.use_typo, typo_ascent, typo_descent, win_ascent: 1050, win_descent: 380 })
	# Each table has the length defined for its version. Keep the
	# Regular bit set while toggling USE_TYPO_METRICS.
	full = os2.concat(List.repeat(0, 10))
	versioned = FontBuild.patch(full, 0, FontBuild.u16(case.version))
	selection = if (case.use_typo) 0xC0 else 0x40
	selected = FontBuild.patch(FontBuild.patch(versioned, 62, FontBuild.u16(selection)), 72, FontBuild.i16(typo_gap))
	length = if (case.version == 0) 78 else if (case.version == 1) 86 else 96
	bytes = FontBuild.file(base.append({ tag: "OS/2", data: selected.take_first(length) }))
	font = Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) ?? crash "vertical metrics fixture rejected"
	metrics = Font.metrics(font)
	observed = (metrics.ascent, metrics.descent, metrics.line_gap)
	if observed == case.expected {
		True
	} else {
		crash "vertical metrics tuple for ${Str.inspect(case)}: ${Str.inspect(observed)}"
	}
}
