app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	font: "../package/main.roc",
}
import cli.OsStr
import cli.Path
import cli.Stdout
import font.Font

# Shape caller-supplied emoji text and inspect its color graph and outline
# leaves. A downstream renderer chooses palette/foreground, applies graph
# transforms/clips/compositing and draws the returned paths.
# roc examples/color.roc -- /path/to/color-font.ttf
main! : List(OsStr) => Try({}, _)
main! = |args| {
	match args.first() {
		Err(_) => Stdout.line!("Pass the path of an OpenType color font.")?
		Ok(path) => {
			bytes = Path.read_bytes!(Path.utf8(OsStr.display(path)))?
			match Font.from_bytes(bytes, Font.ReadOptions.{}) {
				Err(ps) => {
					for p in ps {
						Stdout.line!(Font.describe_problem(p))?
					}
				}
				Ok(font) => {
					Stdout.line!("Color palettes: ${Font.color_palettes(font).len().to_str()}.")?
					for text in ["😀", "👩‍💻", "❤️"] {
						run = Font.shape(font, text, Font.ShapeOptions.{})
						for glyph in run.glyphs {
							match Font.color_glyph(font, glyph) {
								Absent => Stdout.line!("${text}: glyph ${glyph.to_str()} has no color paint.")?
								Present(graph) => {
									var $leaves = 0.U64
									var $commands = 0.U64
									for node in graph.nodes {
										match node {
											Glyph(leaf) => {
												$leaves = $leaves + 1
												match Font.outline(font, leaf.glyph) {
													Outline(commands) => {
														$commands = $commands + commands.len()
													}
													Unknown => {}
												}
											}
											_ => {}
										}
									}
									Stdout.line!("${text}: glyph ${glyph.to_str()}, ${graph.nodes.len().to_str()} paint nodes, ${$leaves.to_str()} outline leaves, ${$commands.to_str()} path commands.")?
								}
							}
						}
					}
				}
			}
		}
	}
	Ok({})
}
