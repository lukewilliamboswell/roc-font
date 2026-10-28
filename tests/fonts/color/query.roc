app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	font: "../../../package/main.roc",
}
import cli.OsStr
import cli.Path
import cli.Stdin
import cli.Stdout
import font.Font

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	input = Str.from_utf8_lossy(Stdin.read_to_end!()?)
	for line in input.split_on("\n") {
		if !line.is_empty() {
			match line.split_on("\t") {
				[tag, path, weight_text, emoji] => {
					bytes = Path.read_bytes!(Path.utf8(path))?
					read = match Font.from_bytes(bytes, Font.ReadOptions.{}) {
						Ok(font) => font
						Err(problems) => crash Str.inspect(problems)
					}
					font = if emoji == "precision" {
						value = Dec.from_str(weight_text) ?? 0
						Font.at(read, Font.Variation.{ axes: ["wght", "AX02", "AX03", "AX04"].map(|axis_tag| { tag: axis_tag, value }) })
					} else {
						Font.at(read, Font.Variation.{ weight: Weight(U16.from_str(weight_text) ?? 400) })
					}
					Stdout.line!("${tag}\t${facts(font, emoji == "1")}")?
				}
				_ => crash "color driver needs id, path, weight and emoji flag"
			}
		}
	}
	Ok({})
}

array = |parts| "[${Str.join_with(parts, ",")}]"

nums : List(F64) -> Str
nums = |values| array(values.map(|n| n.to_str()))

color_ref = |value| Str.inspect(
	match value {
		PaletteEntry(i) => "p:${i.to_str()}"
		Foreground => "f"
	},
)

rect = |value| match value {
	Present(r) => nums([r.x_min, r.y_min, r.x_max, r.y_max])
	Absent => "null"
}

name = |value| match value {
	Ok(s) => Str.inspect(s)
	Err(_) => "null"
}

child = |id| "\"children\":[${id.to_str()}]"

operation = |op| match op {
	Affine(a) => "\"kind\":\"affine\",\"values\":${nums([a.xx, a.yx, a.xy, a.yy, a.dx, a.dy])}"
	Translate(p) => "\"kind\":\"translate\",\"values\":${nums([p.x, p.y])}"
	Scale(s) => "\"kind\":\"scale\",\"values\":${nums([s.x, s.y, s.center.x, s.center.y])}"
	Rotate(r) => "\"kind\":\"rotate\",\"values\":${nums([r.degrees, r.center.x, r.center.y])}"
	Skew(s) => "\"kind\":\"skew\",\"values\":${nums([s.x_degrees, s.y_degrees, s.center.x, s.center.y])}"
}

stop_list = |graph, span| array(graph.stops.sublist({ start: span.start, len: span.len }).map(|s| "[${s.offset.to_str()},${color_ref(s.color)},${s.alpha.to_str()}]"))

node = |graph, paint| {
	inside = match paint {
		Layers(span) => "\"kind\":\"layers\",\"children\":${array(graph.edges.sublist({ start: span.start, len: span.len }).map(|i| i.to_str()))}"
		Solid(s) => "\"kind\":\"solid\",\"color\":${color_ref(s.color)},\"values\":${nums([s.alpha])}"
		LinearGradient(g) => "\"kind\":\"linear\",\"extend\":${Str.inspect(Str.inspect(g.extend))},\"stops\":${stop_list(graph, g.stops)},\"values\":${nums([g.p0.x, g.p0.y, g.p1.x, g.p1.y, g.p2.x, g.p2.y])}"
		RadialGradient(g) => "\"kind\":\"radial\",\"extend\":${Str.inspect(Str.inspect(g.extend))},\"stops\":${stop_list(graph, g.stops)},\"values\":${nums([g.c0.x, g.c0.y, g.radius0, g.c1.x, g.c1.y, g.radius1])}"
		SweepGradient(g) => "\"kind\":\"sweep\",\"extend\":${Str.inspect(Str.inspect(g.extend))},\"stops\":${stop_list(graph, g.stops)},\"values\":${nums([g.center.x, g.center.y, g.start_degrees, g.end_degrees])}"
		Glyph(g) => "\"kind\":\"glyph\",\"glyph\":${g.glyph.to_str()},${child(g.paint)}"
		ColorGlyph(g) => "\"kind\":\"color-glyph\",\"glyph\":${g.glyph.to_str()},${child(g.paint)},\"clip\":${rect(g.clip)}"
		Transform(t) => "${operation(t.operation)},${child(t.paint)}"
		Composite(c) => "\"kind\":\"composite\",\"mode\":${Str.inspect(Str.inspect(c.mode))},\"children\":[${c.source.to_str()},${c.backdrop.to_str()}]"
	}
	"{${inside}}"
}

graph_json = |value| match value {
	Absent => "null"
	Present(g) => "{\"root\":${g.root.to_str()},\"clip\":${rect(g.clip)},\"nodes\":${array(g.nodes.map(|p| node(g, p)))}}"
}

facts = |font, emoji| {
	palettes = array(
		Font.color_palettes(font).map_with_index(
			|p, i| {
				colors = array(p.colors.map(|c| "[${c.red.to_str()},${c.green.to_str()},${c.blue.to_str()},${c.alpha.to_str()}]"))
				"{\"colors\":${colors},\"light\":${if (p.light_background) "true" else "false"},\"dark\":${if (p.dark_background) "true" else "false"},\"name\":${name(Font.color_palette_name(font, i.to_u32_wrap()))}}"
			},
		),
	)
	entry_count = match Font.color_palettes(font).first() {
		Ok(p) => p.colors.len()
		Err(_) => 0
	}
	entry_names = array(indices(entry_count).map(|i| name(Font.color_entry_name(font, i.to_u32_wrap()))))
	glyphs = array(
		indices(Font.glyph_count(font).to_u64()).map(
			|i| {
				g = i.to_u32_wrap()
				layers = array(Font.color_layers(font, g).map(|l| "[${l.glyph.to_str()},${color_ref(l.color)}]"))
				"{\"glyph\":${i.to_str()},\"layers\":${layers},\"graph\":${graph_json(Font.color_glyph(font, g))}}"
			},
		),
	)
	shapes = if emoji {
		array(["😀", "👩‍💻", "❤️"].map(|text| "{\"text\":${Str.inspect(text)},\"glyphs\":${array(Font.shape(font, text, Font.ShapeOptions.{}).glyphs.map(|g| g.to_str()))}}"))
	} else "[]"
	"{\"palettes\":${palettes},\"entry_names\":${entry_names},\"glyphs\":${glyphs},\"shapes\":${shapes}}"
}

indices : U64 -> List(U64)
indices = |n| {
	var $out = List.with_capacity(n)
	for i in 0..<n {
		$out = $out.append(i)
	}
	$out
}
