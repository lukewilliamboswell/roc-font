app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	font: "../../../package/main.roc",
}
import cli.OsStr
import cli.Path
import cli.Stdin
import cli.Stdout
import font.Font

# One caller font per process; preparation is shared across every request.
# The conformance verifier supplies trusted tab-separated case fields.
main! : List(OsStr) => Try({}, _)
main! = |args| {
	path = OsStr.display(args.first() ?? crash "Graphite query requires caller font path")
	bytes = Path.read_bytes!(Path.utf8(path))?
	font = Font.from_bytes(bytes, Font.ReadOptions.{}) ?? crash "Graphite caller font rejected"
	for line in Str.from_utf8_lossy(Stdin.read_to_end!()?).split_on("\n") {
		if !line.is_empty() {
			fields = line.split_on("\t")
			request = match fields {
				[id, script, language, direction, cluster_level, settings, engine, start, end, text, variations] => { parts: [id, script, language, direction, cluster_level, settings, engine, start, end, text], variations }
				_ => { parts: fields, variations: "" }
			}
			match request.parts {
				[id, script, language, direction, cluster_level, settings, engine, start, end, text] => {
					var $features = []
					if !settings.is_empty() {
						for pair in settings.split_on(",") {
							match pair.split_on(":") {
								[key, value] => {
									$features = $features.append(Font.GraphiteFeature.{ id: U32.from_str(key) ?? crash "invalid feature id", value: I16.from_str(value) ?? crash "invalid feature value" })
								}
								_ => crash "Graphite feature requires id:value"
							}
						}
					}
					var $axes = []
					if !request.variations.is_empty() {
						for pair in request.variations.split_on(",") {
							match pair.split_on(":") {
								[tag, value] => {
									$axes = $axes.append({ tag, value: Dec.from_str(value) ?? crash "invalid variation coordinate" })
								}
								_ => crash "variation requires tag:value"
							}
						}
					}
					active_font = if ($axes.is_empty()) font else Font.at(font, Font.Variation.{ axes: $axes })
					plan = Font.plan(
						active_font,
						Font.ShapeOptions.{
							script,
							language,
							direction: match direction {
								"ltr" => LeftToRight
								"rtl" => RightToLeft
								"ttb" => TopToBottom
								"btt" => BottomToTop
								_ => crash "invalid direction"
							},
							clusters: if (cluster_level == "1") Characters else Graphemes,
							graphite_features: $features,
							use_font_programs: engine != "ot",
						},
					)
					range = Font.TextRange.{ start: U64.from_str(start) ?? crash "invalid range start", end: U64.from_str(end) ?? crash "invalid range end" }
					checked = Font.shape_range_checked(active_font, plan, text, range)
					if checked != Font.shape_range_checked(active_font, plan, text, range) {
						crash "nondeterministic Graphite result"
					}
					{ run, abort, budgets } = match checked {
						Ok(value) => { run: value, abort: "NoAbort", budgets: [] }
						Err(OverBudget(result)) => { run: result.run, abort: "NoAbort", budgets: result.budgets.map(|budget| Str.inspect(budget)) }
						Err(ProgramAborted(result)) => { run: result.run, abort: "ProgramAbort", budgets: [] }
					}
					if run.glyphs.len() != run.advances.len() or run.glyphs.len() != run.offsets.len() or run.glyphs.len() != run.clusters.len() or run.glyphs.len() != run.flags.len() {
						crash "unaligned Graphite run"
					}
					var $rows = []
					for i in 0..<run.glyphs.len() {
						glyph = run.glyphs.get(i) ?? 0
						cluster = run.clusters.get(i) ?? 0
						advance = run.advances.get(i) ?? { x: 0, y: 0 }
						offset = run.offsets.get(i) ?? { x: 0, y: 0 }
						flags = if (Font.is_unsafe_to_break(run.flags.get(i) ?? 0)) "1" else "0"
						$rows = $rows.append("{\"glyph\":${glyph.to_str()},\"cluster\":${cluster.to_str()},\"advance\":[${advance.x.to_str()},${advance.y.to_str()}],\"offset\":[${offset.x.to_str()},${offset.y.to_str()}],\"flags\":${flags}}")
					}
					budget_json = Str.join_with(budgets.map(Str.inspect), ",")
					Stdout.line!("${id}\t{\"success\":${if (abort == "NoAbort") "true" else "false"},\"abort\":${Str.inspect(abort)},\"glyphs\":[${Str.join_with($rows, ",")}],\"ot_glyph2_advance\":${Font.advance(active_font, 2).to_str()},\"budgets\":[${budget_json}],\"engine\":${Str.inspect(Str.inspect(Font.shaping_engine(plan)))}}")?
				}
				_ => crash "Graphite query requires id/script/language/direction/clusters/features/engine/start/end/text"
			}
		}
	}
	Ok({})
}
