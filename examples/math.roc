app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	font: "../package/main.roc",
}

import cli.OsStr
import cli.Path
import cli.Stdout
import font.Font

# Inspect the font facts a math layout package uses to place a fraction,
# choose a large delimiter and construct a taller one from font glyphs.
#
#     roc examples/math.roc -- /path/to/a/math-font.ttf
#
# The caller supplies its math font. Equation parsing, expression layout
# and drawing rules/glyphs are downstream work; these values are font units.
main! : List(OsStr) => Try({}, _)
main! = |args| {
	match args.first() {
		Err(_) => {
			Stdout.line!("Pass the path of an OpenType math font.")?
		}
		Ok(path) => {
			bytes = Path.read_bytes!(Path.utf8(OsStr.display(path)))?
			match Font.from_bytes(bytes, Font.ReadOptions.{}) {
				Err(problems) => {
					for problem in problems {
						Stdout.line!(Font.describe_problem(problem))?
					}
				}
				Ok(font) => {
					match Font.math_constants(font) {
						Absent => {
							Stdout.line!("This font has no usable mathematical typesetting data.")?
						}
						Present(c) => {
							Stdout.line!("Math axis: ${c.axis_height.to_str()} font units; fraction rule: ${c.fraction_rule_thickness.to_str()} font units.")?
							Stdout.line!("Script sizes: ${c.script_percent_scale_down.to_str()}% and ${c.script_script_percent_scale_down.to_str()}% of the main size.")?
							match Font.glyph(font, 0x28) {
								Err(_) => {
									Stdout.line!("The font does not map an opening parenthesis.")?
								}
								Ok(glyph) => {
									variants = Font.math_variants(font, glyph, Vertical)
									for variant in variants {
										Stdout.line!("Parenthesis variant: glyph ${variant.glyph.to_str()}, vertical advance ${variant.advance.to_str()}.")?
									}
									match Font.math_assembly(font, glyph, Vertical) {
										Absent => {
											Stdout.line!("No assembly recipe for taller parentheses.")?
										}
										Present(assembly) => {
											Stdout.line!("A taller parenthesis uses ${assembly.parts.len().to_str()} parts; minimum connector overlap ${Font.math_min_connector_overlap(font).to_str()} font units.")?
											for part in assembly.parts {
												repeatable = if (part.extender) "repeatable" else "fixed"
												Stdout.line!("  glyph ${part.glyph.to_str()}: ${repeatable}, full advance ${part.full_advance.to_str()}.")?
											}
										}
									}
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
