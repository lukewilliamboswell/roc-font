import build.FontBuild
import build.MarkBuild
import font.Font

# OpenType's 0xFFFF/0xFFFF delta-set index contributes zero. The other
# records in the same tables still vary. The strict and lenient outcomes
# for a nonexistent row are roc-font's table-reading policy.
# https://learn.microsoft.com/en-us/typography/opentype/spec/otvarcommonformats
NoVariation := {}.{
	check : {} -> Bool
	check = |_| [Clean, Anchor(Outer), Anchor(Inner), MathAxis(Outer), MathAxis(Inner), Advance(Outer), Advance(Inner), AdvanceAndAnchor].all(check_case)
}

Half : [Outer, Inner]

Case : [Clean, Advance(Half), Anchor(Half), MathAxis(Half), AdvanceAndAnchor]

Index : (U64, U64)

no_delta : Index
no_delta = (0xFFFF, 0xFFFF)

single_max : Half -> Index
single_max = |half| if (half == Outer) (0xFFFF, 0) else (0, 0xFFFF)

index_bytes : Index -> List(U8)
index_bytes = |(outer, inner)| FontBuild.pack([U16(outer), U16(inner)])

device : Index -> List(U8)
device = |index| index_bytes(index).concat(FontBuild.u16(0x8000))

fixture : Case -> List(U8)
fixture = |case| {
	advance = match case {
		Advance(half) => single_max(half)
		AdvanceAndAnchor => single_max(Outer)
		_ => no_delta
	}
	anchor = match case {
		Anchor(half) => single_max(half)
		AdvanceAndAnchor => single_max(Inner)
		_ => no_delta
	}
	math_axis = match case {
		MathAxis(half) => single_max(half)
		_ => no_delta
	}
	cmap = FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 'A', last: 'C', glyph: 1 }]) }])
	fvar = FontBuild.fvar([{ tag: "wght", min: 100, default: 400, max: 800 }])
	regions = [[{ start: 0, peak: 16384, end: 16384 }]]
	store = |amount| FontBuild.variation_store(1, regions, [{ regions: [0], rows: [[amount]] }])
	# Format 0 map with four entries, each two 16-bit halves.
	mapping = [0, 0x3F, 0, 4].concat([no_delta, advance, no_delta, (0, 0)].join_map(index_bytes))
	hvar = FontBuild.pack([U16(1), U16(0), Ref32(store(60)), Ref32(mapping), U32(0), U32(0)])
	gdef_store = FontBuild.variation_store(1, regions.append([{ start: 0, peak: 0, end: 0 }]), [{ regions: [0, 1], rows: [[40, 0], [40, 20]] }])
	gdef = FontBuild.pack([U32(0x00010003), Ref(FontBuild.classes1(1, [1, 3, 1])), U16(0), U16(0), U16(0), U16(0), Ref32(gdef_store)])
	mark = { glyph: 2, class: 0, anchor: MarkBuild.anchor(-6, 19) }
	base = { glyph: 1, anchors: [MarkBuild.device_anchor(30, 200, device(anchor), device((0, 0)))] }
	gpos = FontBuild.layout("latn", [{ tag: "mark", lookups: [0] }], [{ kind: 4, subtables: [MarkBuild.position([mark], 1, [base])] }])
	# The axis-height MathValueRecord keeps its stored value with the sentinel.
	# MathLeading uses a neutral region as well, so it varies even at
	# the default location while the variation store is active.
	constants = FontBuild.pack([I16(80), I16(60), U16(1000), U16(1100), I16(-3), Ref(device((0, 1))), I16(250), Ref(device(math_axis)), Raw(List.repeat(0, 198))])
	math = FontBuild.pack([U32(0x00010000), Ref(constants), Ref(List.repeat(0, 8)), Ref(List.repeat(0, 10))])
	FontBuild.glyphs_font([500, 600, 0, 700], cmap, [{ tag: "fvar", data: fvar }, { tag: "HVAR", data: hvar }, { tag: "GDEF", data: gdef }, { tag: "GPOS", data: gpos }, { tag: "MATH", data: math }])
}

check_case : Case -> Bool
check_case = |case| {
	bytes = fixture(case)
	font = Font.from_bytes(bytes, Font.ReadOptions.{}) ?? crash "lenient variation sentinel fixture rejected"
	strict = Font.from_bytes(bytes, Font.ReadOptions.{ strict: True })
	(issues, keeps_axes, keeps_math) = match case {
		Clean => ([], True, True)
		Advance(half) => ([("HVAR", single_max(half))], False, True)
		Anchor(half) => ([("GPOS", single_max(half))], False, True)
		MathAxis(half) => ([("MATH", single_max(half))], True, False)
		AdvanceAndAnchor => ([("HVAR", single_max(Outer)), ("GPOS", single_max(Inner))], False, True)
	}
	problems = Font.dropped(font)
	diagnostics = match strict {
		Ok(_) => issues.is_empty() and problems.is_empty()
		Err(found) => !issues.is_empty() and found == problems and problems.len() == issues.len() and issues.all(
			|(table, index)| {
				wire = if (table == "HVAR") index_bytes(index) else device(index)
				problems.any(
					|problem| match problem {
						BadTable({ table: actual, offset }) => actual == table and bytes.sublist({ start: offset.to_u64(), len: wire.len() }) == wire
						_ => False
					},
				)
			},
		)
	}
	at = Font.at(font, Font.Variation.{ weight: Weight(800) })
	run = Font.shape(at, "AB", Font.ShapeOptions.{ script: "Latn" })
	(y, advance, default_leading, peak_leading) = if (keeps_axes) (221, 760, 17, 57) else (181, 700, -3, -3)
	want_math = |leading| if (keeps_math) Present((250, leading)) else Absent
	math = math_axis_and_leading(at)
	default_math = math_axis_and_leading(font)
	if diagnostics and (Font.axes(at).len() == (if (keeps_axes) 1 else 0)) and Font.advance(at, 1) == 600 and Font.advance(at, 3) == advance
		and run.glyphs == [1, 2] and run.offsets == [{ x: 0, y: 0 }, { x: -564, y }] and math == want_math(peak_leading) and default_math == want_math(default_leading) {
		True
	} else {
		crash "variation sentinel ${Str.inspect(case)}: ${Str.inspect(Font.dropped(font))}, ${Str.inspect(run)}, MATH ${Str.inspect((default_math, math))}, control advance ${Font.advance(at, 3).to_str()}"
	}
}

math_axis_and_leading : Font -> [Present((I64, I64)), Absent]
math_axis_and_leading = |font| match Font.math_constants(font) {
	Present(c) => Present((c.axis_height, c.math_leading))
	Absent => Absent
}
