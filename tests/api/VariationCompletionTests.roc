import font.Font
import build.FontBuild
import "../fonts/variation-complete/phantom-simple.ttf" as simple_file : List(U8)
import "../fonts/variation-complete/phantom-composite.ttf" as composite_file : List(U8)
import "../fonts/variation-complete/phantom-last-metrics.ttf" as last_file : List(U8)
import "../fonts/variation-complete/phantom-hvar-priority.ttf" as hvar_file : List(U8)
import "../fonts/variation-complete/phantom-boundary.ttf" as boundary_file : List(U8)
import "../fonts/variation-complete/vertical-boundary.ttf" as vertical_file : List(U8)
import "../fonts/variation-complete/avar-cross.ttf" as cross_file : List(U8)
import "../fonts/variation-complete/avar-mapped.ttf" as mapped_file : List(U8)
import "../fonts/variation-complete/avar-first-cache.ttf" as cache_file : List(U8)
import "../fonts/variation-complete/avar-null.ttf" as null_file : List(U8)
import "../fonts/variation-complete/avar-empty-map.ttf" as empty_file : List(U8)
import "../fonts/variation-complete/duplicate-axes.ttf" as duplicate_file : List(U8)
import "../fonts/variation-complete/Amstelvar-avar2.ttf" as real_file : List(U8)

import "../fonts/variation-complete/axes-invalid-instance.ttf" as invalid_axes_file : List(U8)

## Public variable-font regressions; numerical facts are actual HB14.6
## outputs in variation-complete/cases.jsonc, replayed by its native driver.
VariationCompletionTests :: {}.{}

read : List(U8) -> Font
read = |bytes| match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
	Ok(f) => f
	Err(ps) => crash Str.inspect(ps)
}

weight : List(U8), Dec -> Font
weight = |bytes, value| Font.at(read(bytes), Font.Variation.{ axes: [{ tag: "wght", value }] })

coords : Font -> List(I16)
coords = |f| Font.coordinates(f).map(|a| a.value)

xy : List(U8), Dec, Dec -> Font
xy = |bytes, x, y| Font.at(read(bytes), Font.Variation.{ axes: [{ tag: "wght", value: x }, { tag: "wdth", value: y }] })
expect [0.Dec, 0.5, 1].map(|v| Font.advance(weight(simple_file, v), 1)) == [510, 560, 610]
# USE_MY_METRICS phantoms are copied before component transforms. At the
# static default HB reads the parent's hmtx directly; the last flagged
# component wins at nonzero coordinates, including nested composites.
expect [0.Dec, 0.5, 1].map(|v| Font.advance(weight(composite_file, v), 3)) == [530, 560, 610]
expect [0.Dec, 0.5, 1].map(|v| Font.advance(weight(composite_file, v), 4)) == [540, 560, 610]
expect [0.Dec, 0.5, 1].map(|v| Font.advance(weight(last_file, v), 3)) == [530, 620, 720]
expect Font.advance(weight(hvar_file, 1), 1) == 810
expect Font.advance(weight(boundary_file, 1), 1) == -2147483648
expect Font.vertical_advance(weight(vertical_file, 1), 1) == 2147483648
expect Font.vertical_origin(weight(vertical_file, 1), 1) == { x: 255, y: 800 }
expect coords(xy(cross_file, 0.25, 0.75)) == [7168, 13312]
expect coords(xy(mapped_file, 0.25, 0.75)) == [5120, 15360]
expect coords(xy(empty_file, 0.5, 0.5)) == [10240, 10240]
expect coords(xy(null_file, 0.5, 0.5)) == [8192, 8192]
expect coords(Font.at(read(cache_file), Font.Variation.{ axes: [{ tag: "AX01", value: 0.00006103515625 }, { tag: "AX02", value: 0.00006103515625 }, { tag: "AX03", value: 0.0625 }] })) == [2, 1, 1024]
expect {
	f = Font.at(read(duplicate_file), Font.Variation.{ axes: [{ tag: "0001", value: 500 }] })
	Font.axes(f).map(|a| a.tag) == ["0001", "0001", "0001"] and coords(f) == [8192, 8192, 8192] and Font.advance(f, 2) == 681
}
expect coords(Font.at(read(duplicate_file), Font.Variation.{ axes: [{ tag: "0001", value: 1000 }, { tag: "0001", value: 500 }] })) == [8192, 8192, 8192]
expect Font.axes(read(real_file)).len() == 92
expect coords(Font.at(read(real_file), Font.Variation.{ axes: [{ tag: "wght", value: 500 }] })).take_first(4) == [0, 2731, 0, 0]
expect {
	f = weight(simple_file, 1)
	Font.advance(f, 4294967295) == 0 and Font.advance(f, Font.glyph_count(f)) == 0 and coords(Font.at(f, Font.Variation.{ axes: [{ tag: "wght", value: 0 }] })) == [0]
}

table : Font, Str -> List(U8)
table = |f, tag| match Font.table_bytes(f, tag) {
	Present(bytes) => bytes
	Absent => []
}

source : Font
source = read(cross_file)

avar_bytes : List(U8)
avar_bytes = table(source, "avar")

fvar_bytes : List(U8)
fvar_bytes = table(source, "fvar")

broken : List(U8) -> Bool
broken = |data| {
	bytes = FontBuild.parity_font([{ tag: "fvar", data: fvar_bytes }, { tag: "avar", data }])
	match (Font.from_bytes(bytes, Font.ReadOptions.{}), Font.from_bytes(bytes, Font.ReadOptions.{ strict: True })) {
		(Ok(f), Err(ps)) => !ps.is_empty() and !Font.dropped(f).is_empty() and Font.dropped(f).all(
			|p| match p {
				BadTable(b) => b.table == "avar"
				_ => False
			},
		) and coords(Font.at(f, Font.Variation.{ axes: [{ tag: "wght", value: 0.5 }, { tag: "wdth", value: 0.5 }] })) == [8192, 8192]
		_ => False
	}
}
expect [1.U64, 7, 8, 20, 35, 43, avar_bytes.len() - 1].all(|n| broken(avar_bytes.take_first(n)))
expect broken(FontBuild.patch(avar_bytes, 2, [0, 1]))
expect broken(FontBuild.patch(avar_bytes, 4, [0, 1]))
# Tail starts at8+2*(2+3*4)=36; neither offset can point into the header.
expect broken(FontBuild.patch(avar_bytes, 36, [0, 0, 0, 1]))
expect broken(FontBuild.patch(avar_bytes, 40, [255, 255, 255, 255]))
expect {
	bytes = FontBuild.parity_font([{ tag: "fvar", data: fvar_bytes }, { tag: "avar", data: FontBuild.patch(FontBuild.patch(avar_bytes, 36, [0, 0, 0, 1]), 40, [255, 255, 255, 255]) }])
	match Font.from_bytes(bytes, Font.ReadOptions.{}) {
		Ok(f) => Font.dropped(f).len() == 2
		Err(_) => False
	}
}

# Validate both map formats, reserved bits, all explicit references (even
# entries beyond the axis count), and implicit no-map row references.
map_font : Font
map_font = read(mapped_file)

map_bytes : List(U8)
map_bytes = table(map_font, "avar")
expect broken(FontBuild.patch(map_bytes, 44, [2]))
expect broken(FontBuild.patch(map_bytes, 45, [192]))
expect broken(FontBuild.patch(map_bytes, 48, [255]))
expect broken(FontBuild.patch(avar_bytes, 58, [0, 1]))
expect {
	start = map_bytes.len()
	raw = FontBuild.patch(map_bytes.concat([0, 0, 0, 3, 1, 0, 255]), 36, FontBuild.u32(start))
	broken(raw)
}
expect {
	start = map_bytes.len()
	raw = FontBuild.patch(map_bytes.concat([1, 0, 0, 0, 0, 2, 1, 0]), 36, FontBuild.u32(start))
	bytes = FontBuild.parity_font([{ tag: "fvar", data: fvar_bytes }, { tag: "avar", data: raw }])
	match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
		Ok(f) => coords(Font.at(f, Font.Variation.{ axes: [{ tag: "wght", value: 0.25 }, { tag: "wdth", value: 0.75 }] })) == [5120, 15360]
		Err(_) => False
	}
}
expect {
	bytes = FontBuild.parity_font([{ tag: "fvar", data: fvar_bytes }, { tag: "avar", data: FontBuild.patch(FontBuild.patch(map_bytes, 40, [0, 0, 0, 0]), 48, [255]) }])
	match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True }) {
		Ok(f) => coords(Font.at(f, Font.Variation.{ axes: [{ tag: "wght", value: 0.5 }, { tag: "wdth", value: 0.5 }] })) == [8192, 8192]
		Err(_) => False
	}
}

# An axis count cannot exceed the byte-defined instance stride. Like OTS,
# lenient mode drops malformed fvar; strict mode reports it.
expect match (Font.from_bytes(invalid_axes_file, Font.ReadOptions.{}), Font.from_bytes(invalid_axes_file, Font.ReadOptions.{ strict: True })) {
	(Ok(f), Err(ps)) => Font.axes(f).is_empty() and !Font.dropped(f).is_empty() and !ps.is_empty()
	_ => False
}

simple_source : Font
simple_source = read(simple_file)

gvar_bytes : List(U8)
gvar_bytes = table(simple_source, "gvar")

gvar_tables : List({ tag : Str, data : List(U8) })
gvar_tables = ["head", "hhea", "maxp", "hmtx", "cmap", "loca", "glyf", "fvar", "name", "OS/2", "post"].keep_oks(
	|tag| match Font.table_bytes(simple_source, tag) {
		Present(data) => Ok({ tag, data })
		Absent => Err({})
	},
)

broken_gvar : List(U8) -> Bool
broken_gvar = |data| {
	bytes = FontBuild.file(gvar_tables.append({ tag: "gvar", data }))
	match (Font.from_bytes(bytes, Font.ReadOptions.{}), Font.from_bytes(bytes, Font.ReadOptions.{ strict: True })) {
		(Ok(f), Err(ps)) => !Font.dropped(f).is_empty() and !ps.is_empty() and Font.advance(Font.at(f, Font.Variation.{ axes: [{ tag: "wght", value: 1 }] }), 1) == 510
		_ => False
	}
}
expect [1.U64, 19, gvar_bytes.len() - 1].all(|n| broken_gvar(gvar_bytes.take_first(n)))
expect broken_gvar(FontBuild.patch(gvar_bytes, 16, [255, 255, 255, 255]))
