app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	font: "../../../../package/main.roc",
}
import cli.OsStr
import cli.Path
import cli.Stdin
import cli.Stdout
import font.Font

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	for line in Str.from_utf8_lossy(Stdin.read_to_end!()?).split_on("\n") {
		if !line.is_empty() {
			match line.split_on("\t") {
				[id, path, depth, factor, direction, text] => {
					bytes = Path.read_bytes!(Path.utf8(path))?
					font = match Font.from_bytes(bytes, Font.ReadOptions.{ strict: True, limits: Font.Limits.{ max_depth: U32.from_str(depth) ?? 64 } }) {
						Ok(f) => f
						Err(ps) => crash Str.inspect(ps)
					}
					plan = Font.plan(font, Font.ShapeOptions.{ script: "Latn", language: "en", direction: if (direction == "rtl") RightToLeft else LeftToRight, limits: Font.ShapeLimits.{ operations: U32.from_str(factor) ?? 4096 } })
					result = Font.shape_checked(font, plan, text)
					{ run, budgets } = match result {
						Ok(completed) => { run: completed, budgets: [] }
						Err(OverBudget(r)) => { run: r.run, budgets: r.budgets.map(|b| Str.inspect(b)) }
					}
					nums = |xs| "[${Str.join_with(xs.map(|n| n.to_str()), ",")}]"
					points = |xs| "[${Str.join_with(xs.map(|p| "[${p.x.to_str()},${p.y.to_str()}]"), ",")}]"
					budget = "[${Str.join_with(budgets.map(|b| Str.inspect(b)), ",")}]"
					Stdout.line!("${id}\t{\"glyphs\":${nums(run.glyphs)},\"advances\":${points(run.advances)},\"offsets\":${points(run.offsets)},\"clusters\":${nums(run.clusters)},\"budgets\":${budget}}")?
				}
				_ => crash "context query needs id/path/depth/operations/direction/text"
			}
		}
	}
	Ok({})
}
