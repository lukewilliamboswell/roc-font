import font.Font
import build.FontBuild

## The tests of traced and checked shaping: which substitution produced
## each glyph (`Font.shape_traced`, `Font.GlyphOrigin`) and whether a
## budget stopped shaping (`Font.shape_checked`, `Font.Budget`), through
## the public `Font` API. Run with `roc test tests/api/main.roc`.
TraceTests :: {}.{}

# ------------------------------------------------------------ test helpers
#
# As in SubstituteTests: a font of 65535 glyphs whose character map draws
# U+10000 + g with glyph g, so text can name any glyph; each character
# takes four bytes of UTF-8, so glyph i of the input has offset 4 i.

many_glyphs : List({ tag : Str, data : List(U8) })
many_glyphs = [
	{ tag: "head", data: FontBuild.head(1000, False) },
	{ tag: "hhea", data: FontBuild.hhea(800, -200, 1) },
	{ tag: "maxp", data: FontBuild.maxp(65535) },
	{ tag: "hmtx", data: FontBuild.hmtx([500]) },
	{ tag: "cmap", data: FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 0x10001, last: 0x1FFFE, glyph: 1 }]) }]) },
]

font_with : List(U8) -> Font
font_with = |gsub|
	match Font.from_bytes(FontBuild.file(FontBuild.replace(many_glyphs, "GSUB", gsub)), Font.ReadOptions.{}) {
		Ok(font) => font
		Err(_) => crash "a trace test font could not be read"
	}

text_of : List(U64) -> Str
text_of = |glyphs| {
	var $bytes = []
	for g in glyphs {
		c = 0x10000 + g
		$bytes = $bytes.concat([0xF0 + c.shr_zf_wrap(18), 0x80 + c.shr_zf_wrap(12).bitwise_and(0x3F), 0x80 + c.shr_zf_wrap(6).bitwise_and(0x3F), 0x80 + c.bitwise_and(0x3F)].map(|b| b.to_u8_wrap()))
	}
	Str.from_utf8($bytes) ?? ""
}

# Glyphs and origins of a traced run with these options.
traced : List(U8), List(U64), Font.ShapeOptions -> { glyphs : List(U32), origins : List(Font.GlyphOrigin) }
traced = |gsub, glyphs, options| {
	font = font_with(gsub)
	t = run_and_origins(Font.shape_traced(font, Font.plan(font, options), text_of(glyphs)))
	{ glyphs: t.run.glyphs, origins: t.origins }
}

# The run and origins of a traced result, finished or not.
run_and_origins : Try({ run : Font.Run, origins : List(Font.GlyphOrigin) }, [OverBudget({ run : Font.Run, origins : List(Font.GlyphOrigin), budgets : List(Font.Budget) })]) -> { run : Font.Run, origins : List(Font.GlyphOrigin) }
run_and_origins = |result|
	match result {
		Ok(t) => t
		Err(OverBudget({ run, origins, budgets: _ })) => { run, origins }
	}

# A `GSUB` table whose features (tag, lookups) list the lookups given.
table : List({ tag : Str, lookups : List(U64) }), List({ kind : U64, subtables : List(List(U8)) }) -> List(U8)
table = |features, lookups| FontBuild.layout("latn", features, lookups)

# ------------------------------------------------------------ origins

# Without substitutions every glyph is mapped.
expect traced(table([], []), [1, 2], Font.ShapeOptions.{}) == { glyphs: [1, 2], origins: [Mapped, Mapped] }
expect traced(table([], []), [], Font.ShapeOptions.{}) == { glyphs: [], origins: [] }

# One for one, by the feature that listed the lookup.
expect {
	gsub = table([{ tag: "liga", lookups: [0] }], [{ kind: 1, subtables: [FontBuild.single1([5], 10)] }])
	traced(gsub, [5, 6], Font.ShapeOptions.{}) == { glyphs: [15, 6], origins: [Substituted({ feature: "liga" }), Mapped] }
}

# A ligature counts the glyphs it joined.
expect {
	gsub = table([{ tag: "liga", lookups: [0] }], [{ kind: 4, subtables: [FontBuild.ligature([1], [[{ glyph: 9, rest: [2, 3] }]])] }])
	traced(gsub, [4, 1, 2, 3, 4], Font.ShapeOptions.{}) == { glyphs: [4, 9, 4], origins: [Mapped, Ligature({ feature: "liga", components: 3 }), Mapped] }
}

# A multiple substitution: the first glyph stands for the character, the
# others are inserted.
expect {
	gsub = table([{ tag: "ccmp", lookups: [0] }], [{ kind: 2, subtables: [FontBuild.multiple([5], [[1, 2, 3]])] }])
	traced(gsub, [4, 5], Font.ShapeOptions.{}) == { glyphs: [4, 1, 2, 3], origins: [Mapped, Multiple({ feature: "ccmp" }), Inserted({ feature: "ccmp" }), Inserted({ feature: "ccmp" })] }
}

# A substitution a contextual rule calls is credited to the rule's
# feature, although no feature lists the called lookup.
expect {
	gsub = table([{ tag: "calt", lookups: [0] }], [{ kind: 6, subtables: [FontBuild.chain3([[7]], [[1]], [], [{ at: 0, lookup: 1 }])] }, { kind: 1, subtables: [FontBuild.single1([1], 10)] }])
	traced(gsub, [7, 1, 1], Font.ShapeOptions.{}) == { glyphs: [7, 11, 1], origins: [Mapped, Substituted({ feature: "calt" }), Mapped] }
}

# A later one-for-one substitution keeps a ligature a ligature, with the
# later feature.
expect {
	gsub = table(
		[{ tag: "liga", lookups: [0] }, { tag: "smcp", lookups: [1] }],
		[{ kind: 4, subtables: [FontBuild.ligature([1], [[{ glyph: 9, rest: [2] }]])] }, { kind: 1, subtables: [FontBuild.single1([9], 10)] }],
	)
	off = traced(gsub, [1, 2], Font.ShapeOptions.{})
	on = traced(gsub, [1, 2], Font.ShapeOptions.{ features: [Font.Feature.{ tag: "smcp" }] })
	off == { glyphs: [9], origins: [Ligature({ feature: "liga", components: 2 })] } and on == { glyphs: [19], origins: [Ligature({ feature: "smcp", components: 2 })] }
}

# A lookup two features list is credited to one that is on for the
# glyph: `liga` before `clig`, although `clig` comes first in tag order.
expect {
	gsub = table([{ tag: "liga", lookups: [0] }, { tag: "clig", lookups: [0] }], [{ kind: 1, subtables: [FontBuild.single1([5], 1)] }])
	both = traced(gsub, [5], Font.ShapeOptions.{})
	clig_only = traced(gsub, [5, 5], Font.ShapeOptions.{ features: [Font.Feature.{ tag: "liga", value: 0, start: 4 }] })
	both.origins == [Substituted({ feature: "liga" })] and clig_only.origins == [Substituted({ feature: "liga" }), Substituted({ feature: "clig" })]
}

# A feature shaping applies by default is credited before one the
# options turned on, whatever their tag order.
expect {
	gsub = table([{ tag: "afrc", lookups: [0] }, { tag: "ccmp", lookups: [0] }], [{ kind: 1, subtables: [FontBuild.single1([5], 1)] }])
	traced(gsub, [5], Font.ShapeOptions.{ features: [Font.Feature.{ tag: "afrc" }] }).origins == [Substituted({ feature: "ccmp" })]
}

# Among features the options turned on, tag order decides.
expect {
	gsub = table([{ tag: "smcp", lookups: [0] }, { tag: "afrc", lookups: [0] }], [{ kind: 1, subtables: [FontBuild.single1([5], 1)] }])
	traced(gsub, [5], Font.ShapeOptions.{ features: [Font.Feature.{ tag: "smcp" }, Font.Feature.{ tag: "afrc" }] }).origins == [Substituted({ feature: "afrc" })]
}

# Origins follow the run's visual order.
expect {
	gsub = table([{ tag: "liga", lookups: [0] }], [{ kind: 1, subtables: [FontBuild.single1([5], 10)] }])
	traced(gsub, [5, 6], Font.ShapeOptions.{ direction: RightToLeft }) == { glyphs: [6, 15], origins: [Mapped, Substituted({ feature: "liga" })] }
}

# The traced run is the run `shape_planned` gives.
expect {
	font = font_with(table([{ tag: "liga", lookups: [0] }], [{ kind: 4, subtables: [FontBuild.ligature([1], [[{ glyph: 9, rest: [2, 3] }]])] }]))
	plan = Font.plan(font, Font.ShapeOptions.{})
	text = text_of([4, 1, 2, 3, 4])
	match Font.shape_traced(font, plan, text) {
		Ok({ run, origins }) => run == Font.shape_planned(font, plan, text) and origins.len() == run.glyphs.len()
		Err(_) => False
	}
}

# A real font: Fira Code draws `->` with contextual alternates, and its
# space with no substitution.
expect {
	t = run_and_origins(Font.shape_traced(Font.mono, Font.plan(Font.mono, Font.ShapeOptions.{}), "-> "))
	t.origins.len() == t.run.glyphs.len() and t.origins.take_first(2).all(|o| o == Substituted({ feature: "calt" })) and t.origins.last() == Ok(Mapped)
}

# ------------------------------------------------------------ budgets

# A multiple substitution that would grow the run past its bound is not
# made, and `shape_checked` says so.
growing : List(U8)
growing = table([{ tag: "liga", lookups: [0] }], [{ kind: 2, subtables: [FontBuild.multiple([1], [List.repeat(2, 100)])] }])

expect {
	font = font_with(growing)
	tight = Font.plan(font, Font.ShapeOptions.{ limits: Font.ShapeLimits.{ growth: 1 } })
	text = text_of(List.repeat(1, 300))
	match Font.shape_checked(font, tight, text) {
		Err(OverBudget({ run, budgets })) => budgets == [Growth] and run == Font.shape_planned(font, tight, text)
		Ok(_) => False
	}
}

# Traced shaping says so too, with the origins of the run made so far.
expect {
	font = font_with(growing)
	tight = Font.plan(font, Font.ShapeOptions.{ limits: Font.ShapeLimits.{ growth: 1 } })
	text = text_of(List.repeat(1, 300))
	match Font.shape_traced(font, tight, text) {
		Err(OverBudget({ run, origins, budgets })) => budgets == [Growth] and run == Font.shape_planned(font, tight, text) and origins.len() == run.glyphs.len()
		Ok(_) => False
	}
}

# Within the bound the traced run is complete.
expect {
	font = font_with(growing)
	plan = Font.plan(font, Font.ShapeOptions.{})
	text = text_of(List.repeat(1, 10))
	match Font.shape_traced(font, plan, text) {
		Ok({ run, origins }) => run == Font.shape_planned(font, plan, text) and origins.take_first(1) == [Multiple({ feature: "liga" })]
		Err(_) => False
	}
}

# Within the bound the run is complete.
expect {
	font = font_with(growing)
	plan = Font.plan(font, Font.ShapeOptions.{})
	text = text_of(List.repeat(1, 10))
	Font.shape_checked(font, plan, text) == Ok(Font.shape_planned(font, plan, text))
}

# A contextual rule calling a lookup 100 times per glyph: 300 glyphs take
# 30000 calls, within the default budget (1024 per character) but past
# the smallest (16384 in all).
calling : List(U8)
calling = table([{ tag: "calt", lookups: [0] }], [{ kind: 5, subtables: [FontBuild.context3([[1]], List.repeat({ at: 0, lookup: 1 }, 100))] }, { kind: 1, subtables: [FontBuild.single1([1], 0)] }])

expect {
	font = font_with(calling)
	text = text_of(List.repeat(1, 300))
	tight = Font.plan(font, Font.ShapeOptions.{ limits: Font.ShapeLimits.{ operations: 1 } })
	roomy = Font.plan(font, Font.ShapeOptions.{})
	over = match Font.shape_checked(font, tight, text) {
		Err(OverBudget({ run, budgets })) => budgets == [Operations] and run.glyphs.len() == 300
		Ok(_) => False
	}
	over and Font.shape_checked(font, roomy, text).is_ok()
}

# Contextual rules nested deeper than `Limits.max_depth` call nothing, and
# `shape_checked` says so.
expect {
	gsub = FontBuild.layout(
		"latn",
		[{ tag: "calt", lookups: [0] }],
		[
			{ kind: 5, subtables: [FontBuild.context3([[1]], [{ at: 0, lookup: 1 }])] },
			{ kind: 5, subtables: [FontBuild.context3([[1]], [{ at: 0, lookup: 2 }])] },
			{ kind: 1, subtables: [FontBuild.single1([1], 2)] },
		],
	)
	bytes = FontBuild.file(FontBuild.replace(FontBuild.basic, "GSUB", gsub))
	checked = |depth|
		match Font.from_bytes(bytes, Font.ReadOptions.{ limits: Font.Limits.{ max_depth: depth } }) {
			Ok(font) =>
				match Font.shape_checked(font, Font.plan(font, Font.ShapeOptions.{}), "A") {
					Ok(run) => Complete(run.glyphs)
					Err(OverBudget({ run, budgets })) => Stopped(run.glyphs, budgets)
				}
			Err(_) => NotRead
		}
	checked(64) == Complete([3]) and checked(1) == Stopped([1], [Depth])
}

# Empty text is never over budget.
expect Font.shape_checked(Font.sans, Font.plan(Font.sans, Font.ShapeOptions.{}), "") == Ok(Font.shape(Font.sans, "", Font.ShapeOptions.{}))
