#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	roc: "nightly-2026-11-18-a520eed",
}

import cli.Env
import cli.OsStr
import cli.Path
import src/ReleaseNotes

main! : List(OsStr) => Try({}, _)
main! = |args| match args.map(OsStr.display) {
	[original, output] => {
		body = ReleaseNotes.render(Path.utf8(original).read_utf8!()?, Env.var_str!("PACKAGE_URL")?, Env.var_str!("COMPILER")?).map_err(|message| InvalidNotes(message))?
		Path.utf8(output).write_utf8!(body)
	}
	_ => Err(Usage("release_notes.roc SOURCE OUTPUT (PACKAGE_URL and COMPILER are required)"))
}
