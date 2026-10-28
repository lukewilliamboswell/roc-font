import "../../tests/fonts/color/color-precision.ttf" as precision_file : List(U8)
import font.Font
import build.FontBuild
import "../../tests/fonts/color/color-v0.ttf" as v0_file : List(U8)
import "../../tests/fonts/color/color-all.ttf" as all_file : List(U8)
import "../../tests/fonts/color/color-map.ttf" as map_file : List(U8)
import "../../tests/fonts/color/noto-emoji-subset.ttf" as noto_file : List(U8)

## Color font facts, through the public served-bundle surface. Complete
## all-format numeric agreement lives in the cached native color oracle.
ColorTests :: {}.{}

read = |bytes| match Font.from_bytes(bytes, Font.ReadOptions.{}) {
	Ok(font) => font
	Err(problems) => crash Str.inspect(problems)
}

v0 = read(v0_file)

varied = read(all_file)

full = Font.at(varied, Font.Variation.{ weight: Weight(900) })

expect Font.color_palettes(Font.sans).is_empty() and Font.color_layers(Font.sans, 1).is_empty() and Font.color_glyph(Font.sans, 1) == Absent
expect Font.color_palettes(v0) == [
	{ colors: [{ red: 255, green: 0, blue: 0, alpha: 255 }, { red: 0, green: 255, blue: 0, alpha: 128 }, { red: 0, green: 0, blue: 255, alpha: 255 }], light_background: True, dark_background: False },
	{ colors: [{ red: 0, green: 255, blue: 0, alpha: 128 }, { red: 0, green: 0, blue: 255, alpha: 255 }, { red: 9, green: 8, blue: 7, alpha: 0 }], light_background: False, dark_background: True },
]
expect Font.color_palette_name(v0, 0) == Ok("Day") and Font.color_palette_name(v0, 1) == Ok("Night")
expect Font.color_entry_name(v0, 0) == Ok("Outline") and Font.color_entry_name(v0, 1) == Ok("Fill") and Font.color_entry_name(v0, 2) == Err(Missing)
expect Font.color_palette_color(v0, 0, 1) == Font.color_palette_color(v0, 1, 0)
expect [2.U32, 65535, 4294967295].all(|i| Font.color_palette_name(v0, i) == Err(Missing) and Font.color_palette_color(v0, i, 0) == Absent)
expect [3.U32, 65535, 4294967295].all(|i| Font.color_entry_name(v0, i) == Err(Missing) and Font.color_palette_color(v0, 0, i) == Absent)
expect Font.color_layers(v0, 1) == [{ glyph: 34, color: PaletteEntry(0) }, { glyph: 35, color: Foreground }]
expect match Font.color_glyph(v0, 2) {
	Present(g) => g.nodes == [Layers({ start: 0, len: 0 })] and g.edges.is_empty() and g.stops.is_empty() and g.clip == Absent
	Absent => False
}
expect Font.color_glyph(v0, 3) == Absent and Font.color_glyph(v0, 4294967295) == Absent and Font.color_layers(v0, 4294967295).is_empty()
expect {
	var $all = True
	for glyph in 1.U32..=32 {
		match Font.color_glyph(varied, glyph) {
			Present(g) => {
				if g.nodes.is_empty() {
					$all = False
				}
			}
			Absent => {
				$all = False
			}
		}
	}
	$all
}
expect match Font.color_glyph(full, 7) {
	Present(g) => g.clip == Present({ x_min: -9, y_min: -213, x_max: 817, y_max: 881 }) and g.nodes.any(
		|p| match p {
			RadialGradient(r) => r.radius1 == -1448 and r.radius0 == 612
			_ => False
		},
	)
	Absent => False
}
expect match Font.color_glyph(varied, 4) {
	Present(g) => g.stops == [{ offset: 0.25, color: PaletteEntry(0), alpha: 1 }, { offset: 0.75, color: PaletteEntry(2), alpha: 0.5 }, { offset: 0.75, color: Foreground, alpha: 0.75 }]
	Absent => False
}
expect match Font.color_glyph(full, 5) {
	Present(g) => g.stops == [{ offset: 1.25, color: PaletteEntry(0), alpha: 0.5 }, { offset: 1.75, color: PaletteEntry(2), alpha: 0 }, { offset: 1.75, color: Foreground, alpha: 0.25 }]
	Absent => False
}
expect match Font.color_glyph(Font.at(read(map_file), Font.Variation.{ weight: Weight(900) }), 7) {
	Present(g) => g.clip == Present({ x_min: 1004, y_min: 824, x_max: 1824, y_max: 1924 }) and g.nodes.any(
		|p| match p {
			RadialGradient(r) => r.radius1 == 16984 and r.radius0 == 87
			_ => False
		},
	)
	Absent => False
}
# A real emoji font consumer shapes ZWJ/VS16 sequences, obtains a color DAG
# and resolves every leaf glyph through the public TrueType outline API.
expect {
	font = read(noto_file)
	[("😀", 6.U32), ("👩‍💻", 3), ("❤️", 7)].all(
		|(text, id)| {
			run = Font.shape(font, text, Font.ShapeOptions.{})
			run.glyphs == [id] and (
				match Font.color_glyph(font, id) {
					Present(g) => !g.nodes.is_empty() and g.nodes.all(
						|p| match p {
							Glyph(leaf) => match Font.outline(font, leaf.glyph) {
								Outline(path) => !path.is_empty()
								_ => False
							}
							_ => True
						},
					)
					Absent => False
				}
			)
		},
	)
}

be = |bytes, at| (bytes.get(at) ?? 0).to_u64() * 256 + (bytes.get(at + 1) ?? 0).to_u64()

tables = |bytes| {
	var $out = []
	for i in 0..<be(bytes, 4) {
		at = 12 + 16 * i
		tag = Str.from_utf8(bytes.sublist({ start: at, len: 4 })) ?? ""
		start = be(bytes, at + 8) * 65536 + be(bytes, at + 10)
		length = be(bytes, at + 12) * 65536 + be(bytes, at + 14)
		$out = $out.append({ tag, data: bytes.sublist({ start, len: length }) })
	}
	$out
}

source_tables = tables(all_file)

table = |tag| {
	var $out = []
	for t in source_tables {
		if t.tag == tag {
			$out = t.data
		}
	}
	$out
}

replace = |tag, data| FontBuild.file(FontBuild.replace(source_tables, tag, data))

colr = table("COLR")

cpal = table("CPAL")

rejected = |bytes, tag| match (Font.from_bytes(bytes, Font.ReadOptions.{}), Font.from_bytes(bytes, Font.ReadOptions.{ strict: True })) {
	(Ok(font), Err(problems)) => !problems.is_empty() and Font.dropped(font).any(
		|p| match p {
			BadTable(b) => b.table == tag
			_ => False
		},
	) and Font.color_glyph(font, 1) == Absent
	_ => False
}
expect rejected(replace("COLR", FontBuild.patch(colr, 405, [0, 11])), "COLR")
expect rejected(replace("COLR", FontBuild.patch(colr, 408, [0, 0, 0])), "COLR")
expect rejected(replace("CPAL", FontBuild.patch(cpal, 0, [0, 2])), "CPAL")
expect {
	both = FontBuild.file(FontBuild.replace(FontBuild.replace(source_tables, "COLR", FontBuild.patch(colr, 0, [0, 2])), "CPAL", FontBuild.patch(cpal, 0, [0, 2])))
	match Font.from_bytes(both, Font.ReadOptions.{ strict: True }) {
		Err(ps) => ps.any(
			|p| match p {
				BadTable(b) => b.table == "CPAL"
				_ => False
			},
		) and ps.any(
			|p| match p {
				BadTable(b) => b.table == "COLR"
				_ => False
			},
		)
		Ok(_) => False
	}
}
# COLR depends on CPAL even when the only color would be foreground.
expect {
	without = FontBuild.file(FontBuild.without(source_tables, "CPAL"))
	match Font.from_bytes(without, Font.ReadOptions.{}) {
		Ok(font) => Font.color_palettes(font).is_empty() and Font.color_glyph(font, 1) == Absent
		Err(_) => False
	}
}

# Binary32-derived geometry must preserve valid tiny values and large
# long-word variation sums, exactly widened to binary64 at the boundary.

expect {
	font = read(precision_file)
	tiny = Font.at(font, Font.Variation.{ axes: ["wght", "AX02", "AX03", "AX04"].map(|tag| { tag, value: 1 }) })
	wide = Font.at(font, Font.Variation.{ axes: ["wght", "AX02", "AX03", "AX04"].map(|tag| { tag, value: 16384 }) })
	(
		match Font.color_glyph(tiny, 1) {
			Present(g) => g.nodes.any(
				|p| match p {
					Transform(t) => match t.operation {
						Affine(a) => a.dx > 0 and a.dx < 0.000000000000000001.F64
						_ => False
					}
					_ => False
				},
			)
			Absent => False
		}
	) and (
		match Font.color_glyph(wide, 1) {
			Present(g) => g.nodes.any(
				|p| match p {
					Transform(t) => match t.operation {
						Affine(a) => a.dx == 0.0000152587890625.F64 and a.dy == 1048576
						_ => False
					}
					_ => False
				},
			)
			Absent => False
		}
	)
}

# CPAL v0 and optional-v1 metadata absence preserve colors and have no
# invented labels or background preferences.
expect {
	font = read(replace("CPAL", FontBuild.patch(cpal, 0, [0, 0])))
	Font.color_palette_color(font, 1, 2) == Present({ red: 9, green: 8, blue: 7, alpha: 0 }) and Font.color_palette_name(font, 0) == Err(Missing) and Font.color_entry_name(font, 0) == Err(Missing) and Font.color_palettes(font).all(|p| !p.light_background and !p.dark_background)
}
expect {
	font = read(replace("CPAL", FontBuild.patch(cpal, 16, List.repeat(0, 12))))
	Font.color_palette_name(font, 1) == Err(Missing) and Font.color_entry_name(font, 1) == Err(Missing) and Font.color_palettes(font).all(|p| !p.light_background and !p.dark_background)
}
expect {
	# Empty COLRv1 has a complete header and no roots or paints.
	font = read(replace("COLR", [0, 1].concat(List.repeat(0, 32))))
	Font.dropped(font).is_empty() and Font.color_glyph(font, 1) == Absent
}
expect {
	# Zero and single-stop gradients remain explicit font facts. Rendering
	# their defined degenerate result is a downstream operation.
	[0.U64, 1].all(
		|n| {
			font = read(replace("COLR", FontBuild.patch(colr, 335, FontBuild.u16(n))))
			match Font.color_glyph(font, 4) {
				Present(g) => g.stops.len() == n
				Absent => False
			}
		},
	)
}
expect {
	# Unknown enum values have format-defined behavior, rather than failing
	# or accidentally selecting the last known mode.
	pad = read(replace("COLR", FontBuild.patch(colr, 334, [255])))
	clear = read(replace("COLR", FontBuild.patch(colr, 673, [255])))
	(
		match Font.color_glyph(pad, 4) {
			Present(g) => g.nodes.any(
				|p| match p {
					LinearGradient(l) => l.extend == Pad
					_ => False
				},
			)
			Absent => False
		}
	) and (
		match Font.color_glyph(clear, 32) {
			Present(g) => g.nodes.any(
				|p| match p {
					Composite(c) => c.mode == Clear
					_ => False
				},
			)
			Absent => False
		}
	)
}
expect {
	# With no item variation store, even variable paint formats ignore their
	# variation indices. The original values and explicit map bytes survive.
	bytes = FontBuild.patch(colr, 30, [0, 0, 0, 0])
	font = Font.at(read(replace("COLR", bytes)), Font.Variation.{ weight: Weight(900) })
	Font.color_glyph(font, 5) == Font.color_glyph(varied, 5)
}
expect {
	# Invalid palette flags and two independent optional array references
	# are reported together, while both colors and paints are dropped.
	bad = FontBuild.patch(FontBuild.patch(FontBuild.patch(cpal, 44, [128, 0, 0, 0]), 20, [255, 255, 255, 255]), 24, [255, 255, 255, 255])
	match Font.from_bytes(replace("CPAL", bad), Font.ReadOptions.{ strict: True }) {
		Err(ps) => ps.keep_if(
			|p| match p {
				BadTable(b) => b.table == "CPAL"
				_ => False
			},
		).len() == 3
		Ok(_) => False
	}
}
