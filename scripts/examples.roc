#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	roc: "nightly-2026-11-24-ff5e544",
}

import cli.Env
import cli.OsStr
import cli.Path
import cli.Stdout
import src/Run

Case : { name : Str, args : List(Str), stdin : Str, stdout : Str, stderr : Str, exit_code : I32 }

Suite : { schema_version : U64, release : Str, dependencies : List(Str), apps : List({ path : Str, cases : List(Case) }) }

main! : List(OsStr) => Try({}, _)
main! = |native_args| {
	args = native_args.map(OsStr.display).keep_if(|arg| arg != "--")
	if args.any(|arg| !["--source", "--update"].contains(arg)) {
		return Err(InvalidArguments)
	}
	root = Run.root!()?
	cwd = Env.cwd!()?
	work = Run.work!()?
	compiler = Run.compiler!()
	if args.contains("--update") {
		return Run.call!("release-package", ["test-examples", "--update"], root)
	}
	dep = if (args.contains("--source")) [] else Run.dep!()
	if dep.is_empty() and !args.contains("--source") {
		return Run.call!("roc-stable", ["scripts/check.roc", "--", "--only", "examples"], root)
	}
	suite : Suite
	suite = Json.parse(cwd.join("tests/spec.json").read_utf8!()?)?
	if suite.schema_version != 1 or suite.release != "working-tree" or !suite.dependencies.is_empty() or suite.apps.is_empty() {
		return Err(InvalidExampleSuite)
	}
	listed = suite.apps.map(|example| example.path)
	if listed.len() != listed.fold([], |seen, path| if (seen.contains(path)) seen else seen.append(path)).len() {
		return Err(DuplicateExample)
	}
	var $actual_apps = []
	for path in Run.files!(cwd.join("examples"))? {
		if path.display().ends_with(".roc") and path.read_utf8!()?.contains("app [") {
			$actual_apps = $actual_apps.append("examples/${path.filename().map_ok(Path.display) ?? ""}")
		}
	}
	if listed.len() != $actual_apps.len() or !listed.all(|path| $actual_apps.contains(path)) {
		return Err(ExampleCoverageMismatch)
	}
	readme!(root, suite)?
	var $failed = []
	for example in suite.apps {
		if example.cases.is_empty() {
			return Err(NoExampleCases(example.path))
		}
		case_names = example.cases.map(|case| case.name)
		if case_names.len() != case_names.fold([], |seen, name| if (seen.contains(name)) seen else seen.append(name)).len() {
			return Err(DuplicateExampleCase(example.path))
		}
		executable = work.join(example.path.drop_prefix("examples/").drop_suffix(".roc"))
		Run.call!(compiler, ["check", example.path, "--no-cache"].concat(dep), cwd)?
		Run.call!(compiler, ["build", example.path, "--no-cache", "--opt=dev", "--output=${executable.display()}"].concat(dep), cwd)?
		for case in example.cases {
			output = Run.command(executable.display(), case.args, cwd.join("examples"))
				.stdin(Bytes(case.stdin.to_utf8())).run!()?
			if output.status != Exited(case.exit_code) or output.stdout_bytes != case.stdout.to_utf8() or output.stderr_bytes != case.stderr.to_utf8() {
				Stdout.line!("FAIL ${example.path} [${case.name}]: ${Str.inspect(output)}")?
				$failed = $failed.append("${example.path} [${case.name}]")
			} else {
				Stdout.line!("PASS ${example.path} [${case.name}]")?
			}
		}
	}
	if ($failed.is_empty()) Ok({}) else Err(ExampleOutputMismatch($failed))
}

readme! : Path, Suite => Try({}, _)
readme! = |root, suite| {
	readme = root.join("README.md").read_utf8!()?
	source = Str.join_with(root.join("examples/measure.roc").read_utf8!()?.split_on("\tfont: \"../package/main.roc\","), "\tfont: \"{package-url}\",")
	output = match suite.apps.find_first(|example| example.path == "examples/measure.roc") {
		Ok(example) => match example.cases {
			[first, ..] => first.stdout
			[] => return Err(MissingMeasureCase)
		}
		Err(_) => return Err(MissingMeasureCase)
	}
	if !readme.contains("```roc\n${source}```") or !readme.contains("```text\n${output}```") {
		return Err(ReadmeExampleMismatch)
	}
	manual = root.join("docs/index.adoc").read_utf8!()?
	if !manual.contains("include::../examples/measure.roc[]") or !manual.contains("[source,text]\n----\n${output}----") {
		return Err(ManualExampleMismatch)
	}
	Ok({})
}
