import build.FontBuild
import font.Font
import fuzz.Fuzz

## The input is UTF-8 text, a 0xFF separator, and optionally a font.
## The runner supplies the pinned Noto Sans Devanagari when the corpus is
## installed. Text-only inputs use a small dev2 face so every smoke run
## can still exercise syllable detection, dotted circles and reordering.
run! : List(U8) => Fuzz.Outcome
run! = |input| {
	var $marker = 0
	while $marker < input.len() and (input.get($marker) ?? 0) != 0xFF {
		$marker = $marker + 1
	}
	if $marker >= input.len() {
		return Fuzz.reject
	}
	text = Str.from_utf8_lossy(input.take_first($marker).take_first(1024))
	font_bytes = input.drop_first($marker + 1)
	face = if font_bytes.is_empty() {
		fixture({})
	} else {
		match Font.from_bytes(font_bytes, Font.ReadOptions.{ strict: True }) {
			Err(_) => return Fuzz.reject
			Ok(font) => {
				if !Font.features(font).contains("rphf") {
					return Fuzz.reject
				}
				font
			}
		}
	}
	bytes = text.to_utf8()
	scalars = bytes.fold(0.U64, |count, byte| if (scalar_start(byte)) count + 1 else count)
	for clusters in [Graphemes, Characters] {
		options = Font.ShapeOptions.{ script: "Deva", language: "hi", clusters }
		plan = Font.plan(face, options)
		run = Font.shape_planned(face, plan, text)
		n = run.glyphs.len()
		if n > (scalars * 64).max(16_384) or n != run.clusters.len() or n != run.flags.len() or n != run.advances.len() or n != run.offsets.len() {
			crash "Hindi shaping exceeded its growth limit or lost parallel run entries"
		}
		var $previous = 0
		for offset in run.clusters {
			if offset < $previous or !scalar_start(bytes.get(offset) ?? 0x80) {
				crash "Hindi shaping returned a cluster outside the ordered UTF-8 boundaries"
			}
			$previous = offset
		}
		if !run.flags.all(|flag| flag <= 3) or run != Font.shape(face, text, options) {
			crash "Hindi flags were out of bounds or a direct run differed from the planned run"
		}
		checked = match Font.shape_checked(face, plan, text) {
			Ok(result) => { run: result, budgets: [] }
			Err(OverBudget(result)) => result
		}
		traced = match Font.shape_traced(face, plan, text) {
			Ok(result) => { run: result.run, origins: result.origins, budgets: [] }
			Err(OverBudget(result)) => result
		}
		if traced.run != run or traced.origins.len() != n or checked.run != run or checked.budgets != traced.budgets {
			crash "Hindi shaping routes disagreed on the run, budgets or origin alignment"
		}
	}
	Fuzz.keep
}

scalar_start : U8 -> Bool
scalar_start = |byte| byte.bitwise_and(0xC0) != 0x80

fixture : {} -> Font
fixture = |_| {
	cmap = FontBuild.cmap([
		{
			system: 3,
			encoding: 10,
			subtable: FontBuild.cmap12([
				{ first: 0x0915, last: 0x0915, glyph: 1 },
				{ first: 0x0930, last: 0x0930, glyph: 2 },
				{ first: 0x093F, last: 0x093F, glyph: 3 },
				{ first: 0x094D, last: 0x094D, glyph: 4 },
				{ first: 0x25CC, last: 0x25CC, glyph: 5 },
			]),
		},
	])
	gsub = FontBuild.layout("dev2", [{ tag: "rphf", lookups: [0] }], [{ kind: 4, subtables: [FontBuild.ligature([2], [[{ glyph: 6, rest: [4] }]])] }])
	Font.from_bytes(FontBuild.glyphs_font(List.repeat(500, 7), cmap, [{ tag: "GSUB", data: gsub }]), Font.ReadOptions.{ strict: True }) ?? crash "Hindi shaping fixture did not read strictly"
}

FontIndic := {}.{
	target = Fuzz.target_with!({
		name: "font-indic",
		generator: Fuzz.raw_bytes,
		test!: run!,
		show: |bytes| Str.inspect(bytes.take_first(64)),
		examples: [Fuzz.saved({ name: "broken and joined syllables", revision: "1", bytes: "ि। कि र्कि र्\u(200C)क".to_utf8().append(0xFF) })],
	})
}
