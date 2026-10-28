app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	font: "../../../package/main.roc",
}
import cli.OsStr
import cli.Path
import cli.Stdin
import cli.Stdout
import font.Font

# Dedicated data-driven native conformance harness. No test fonts are
# imported: each request identifies the caller's bytes by path.
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	input = Str.from_utf8_lossy(Stdin.read_to_end!()?)
	for line in input.split_on("\n") {
		if !line.is_empty() {
			match line.split_on("\t") {
				[id, path, kind, text] => {
					bytes = Path.read_bytes!(Path.utf8(path))?
					font = match Font.from_bytes(bytes, Font.ReadOptions.{}) {
						Ok(f) => f
						Err(problems) => crash Str.inspect(problems)
					}
					if kind == "shape" {
						run = Font.shape(font, text, Font.ShapeOptions.{})
						rows = run.glyphs.map_with_index(
							|g, i| {
								a = run.advances.get(i) ?? { x: 0, y: 0 }
								o = run.offsets.get(i) ?? { x: 0, y: 0 }
								c = run.clusters.get(i) ?? 0
								"${g.to_str()},${c.to_str()},${a.x.to_str()},${a.y.to_str()},${o.x.to_str()},${o.y.to_str()}"
							},
						)
						Stdout.line!("${id}\tshape\t${Str.join_with(rows, ";")}")?
					} else {
						strikes = Font.bitmap_strikes(font)
						Stdout.line!("${id}\tcount\t${strikes.len().to_str()}")?
						for i in 0..<strikes.len() {
							fact = strikes.get(i) ?? Sbix({ ppem: 0, ppi: 0, draw_outlines: False })
							Stdout.line!("${id}\tstrike${i.to_str()}\t${strike_text(fact)}")?
						}
						for g in 0..<(Font.glyph_count(font) + 1) {
							Stdout.line!("${id}\tsvg${g.to_str()}\t${svg_text(Font.svg_glyph(font, g))}")?
							for i in 0..<(strikes.len() + 1) {
								Stdout.line!("${id}\timage${g.to_str()}:${i.to_str()}\t${image_text(Font.bitmap_glyph(font, g, i.to_u32_wrap()))}")?
							}
						}
					}
				}
				_ => crash "image driver request needs id,path,kind,text"
			}
		}
	}
	Ok({})
}

hex = |bytes| Str.join_with(
	bytes.map(
		|byte| {
			digits = "0123456789abcdef".to_utf8()
			Str.from_utf8_lossy([digits.get((byte.to_u64() // 16)) ?? 48, digits.get(byte.to_u64() % 16) ?? 48])
		},
	),
	"",
)

line_text : Font.BitmapLineMetrics -> Str
line_text = |m| Str.join_with([m.ascender.to_str(), m.descender.to_str(), m.width_max.to_str(), m.caret_slope_numerator.to_str(), m.caret_slope_denominator.to_str(), m.caret_offset.to_str(), m.min_origin_side_bearing.to_str(), m.min_advance_side_bearing.to_str(), m.max_before_baseline.to_str(), m.min_after_baseline.to_str()], ",")

strike_text : Font.BitmapStrike -> Str
strike_text = |s| match s {
	Sbix(m) => "s,${m.ppem.to_str()},${m.ppi.to_str()},${
		if m.draw_outlines {
			"1"
		} else {
			"0"
		}
	}"
	ColorBitmap(m) => "b,${m.ppem_x.to_str()},${m.ppem_y.to_str()},${m.bit_depth.to_str()},${m.flags.to_str()},${m.first_glyph.to_str()},${m.last_glyph.to_str()},${line_text(m.horizontal)},${line_text(m.vertical)}"
}

svg_text : [Present(Font.SvgDocument), Absent] -> Str
svg_text = |value| match value {
	Absent => "_"
	Present(doc) => "${doc.first_glyph.to_str()},${doc.last_glyph.to_str()},${
		match doc.encoding {
			Utf8 => "u"
			Gzip => "g"
		}
	},${hex(doc.bytes)}"
}

bearing_text : [Present(Font.BitmapBearingAdvance), Absent] -> Str
bearing_text = |value| match value {
	Absent => "_"
	Present(m) => "${m.bearing_x.to_str()},${m.bearing_y.to_str()},${m.advance.to_str()}"
}

image_text : [Present(Font.BitmapImage), Absent] -> Str
image_text = |value| match value {
	Absent => "_"
	Present(image) => {
		format = match image.format {
			Png => 1886283552
			Jpeg => 1785751328
			Tiff => 1953064550
			Pdf => 1885627936
			Mask => 1835103083
			Other(tag) => tag
		}
		placement = match image.placement {
			Sbix(m) => "s,${m.origin_x.to_str()},${m.origin_y.to_str()},${m.source_glyph.to_str()}"
			Bitmap(m) => "b,${m.width.to_str()},${m.height.to_str()};${bearing_text(m.horizontal)};${bearing_text(m.vertical)}"
		}
		"${format.to_str()};${placement};${hex(image.bytes)}"
	}
}
