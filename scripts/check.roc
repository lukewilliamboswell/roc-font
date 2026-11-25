#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	roc: "nightly-2026-11-25-d5a4f1e",
}

import cli.Env
import cli.OsStr
import cli.Path
import cli.Stdout
import src/CheckOptions
import src/Run

main! : List(OsStr) => Try({}, _)
main! = |native_args| {
	args = native_args.map(OsStr.display)
	options = CheckOptions.parse(args).map_err(|message| BadArguments(message))?
	selected = CheckOptions.selected(options).map_err(|message| BadArguments(message))?
	if options.list {
		for name in CheckOptions.steps {
			Stdout.line!(name)?
		}
		return Ok({})
	}
	root = Run.root!()?
	work = Run.work!()?
	compiler = Run.compiler!()
	# The adapter serves exactly this artifact and starts this executable in
	# a mirror with no package sources. Selection and all checks stay in Roc.
	if !options.source and !options.flight and CheckOptions.needs_bundle(selected) {
		bundle = if options.bundle != "" {
			Path.utf8(options.bundle).absolute!()?
		} else {
			out = Run.fresh!(work.join("flight-bundle"))?
			Run.call!(compiler, ["bundle", "package/main.roc", "--output-dir", out.display()], root)?
			match out.list!()?.keep_if(|p| p.display().ends_with(".tar.zst")) {
				[one] => one
				_ => return Err(CheckFailed("expected one package bundle"))
			}
		}
		return Run.call!("python3", [root.join("scripts/flight.py").display(), "--roc", compiler, "--bundle", bundle.display(), "--mirror", work.join("mirror").display(), "--", "roc-stable", "scripts/check.roc", "--", "--flight"].concat(args), root)
	}
	consumer = Env.cwd!()?
	dep = if (options.source) [] else Run.dep!()
	if options.flight {
		if dep.is_empty() {
			return Err(CheckFailed("flight phase requires a bundle URL"))
		}
		control = Run.command(compiler, ["check", "tests/api/main.roc"], consumer).run!()?
		if control.status == Exited(0) {
			return Err(CheckFailed("sentinel package compiled: consumers are not isolated"))
		}
		Stdout.line!("PASS sentinel control: source imports fail in the consumer mirror")?
	}
	var $failed = []
	for name in selected {
		Stdout.line!("\n== ${name}")?
		result = step!(name, { root, work, compiler, consumer, dep, options })
		match result {
			Ok(_) => Stdout.line!("PASS ${name}")?
			Err(problem) => {
				Stdout.line!("FAIL ${name}: ${Str.inspect(problem)}")?
				$failed = $failed.append(name)
			}
		}
	}
	if $failed.is_empty() {
		Stdout.line!("\nall checks passed")?
		Ok({})
	} else {
		Err(CheckFailed("checks failed: ${Str.join_with($failed, ", ")}"))
	}
}

Context : { root : Path, work : Path, compiler : Str, consumer : Path, dep : List(Str), options : CheckOptions.Options }

step! : Str, Context => Try({}, _)
step! = |name, ctx| {
	{ root, work, compiler, consumer, dep, options } = ctx
	cache = if (options.no_cache) ["--no-cache"] else []
	match name {
		"compiler" => {
			Run.call!(compiler, ["version"], root)?
			Run.call!("roc-stable", ["version"], root)
		}
		"fmt" => {
			Run.call!(compiler, ["fmt", "--check", "Blueprint.roc", "package", "fuzz", "tools", "bench", "tests", "examples"], root)?
			Run.call!("roc-stable", ["fmt", "--check", "scripts"], root)?
			blueprint = root.join("Blueprint.roc").read_utf8!()?
			pin = "nightly-2026-11-25-d5a4f1e"
			if !blueprint.contains("Recipes.roc_nightly(\"${pin}\")") {
				return Err(CheckFailed("roc-stable compiler pin does not match scripts"))
			}
			for path in Run.files!(root.join("scripts"))? {
				if path.display().ends_with(".roc") {
					source = path.read_utf8!()?
					if source.contains("app [") and (!source.starts_with("#!/usr/bin/env roc-stable\n") or !source.contains("roc: \"${pin}\"")) {
						return Err(CheckFailed("script compiler pin or shebang mismatch: ${path.display()}"))
					}
				}
			}
			Ok({})
		}
		"check" => {
			Run.call!(compiler, ["check", "package/main.roc"], root)?
			for path in consumer_apps!(consumer)? {
				Run.call!(compiler, ["check", path].concat(dep), consumer)?
			}
			Ok({})
		}
		"test" => {
			Run.call!("roc-stable", ["test", "scripts/check.roc"], root)?
			Run.call!("roc-stable", ["test", "scripts/release_notes.roc"], root)?
			Run.call!(compiler, ["test", "--opt=dev", "package/main.roc"].concat(cache), root)?
			for module_path in ["tests/api/main.roc", "tools/driver/Case.roc", "fuzz/spec/main.roc"] {
				Run.call!(compiler, ["test", "--opt=dev", module_path].concat(cache).concat(dep), consumer)?
			}
			Ok({})
		}
		"fuzz-smoke" => {
			target_names = if (options.smoke) ["font-read", "font-shape", "font-math"] else []
			runs = if (options.fuzz_runs != "") ["--runs=${options.fuzz_runs}"] else if (options.smoke) ["--runs=200"] else []
			adapter!("run_fuzz.py", ["smoke"].concat(target_names).concat(runs), ctx)?
			spec_runs = if (options.fuzz_runs == "") [] else ["--runs=${options.fuzz_runs}"]
			adapter!("run_fuzz.py", ["spec-smoke"].concat(spec_runs), ctx)
		}
		"examples" => Run.call!("roc-stable", ["scripts/examples.roc"].concat(if (options.source) ["--", "--source"] else []), consumer)
		"conformance" => {
			adapter!("conformance.py", [], ctx)?
			Run.call!("python3", ["tests/fonts/math/verify.py"], consumer)
		}
		"bench" => adapter!("bench.py", if (options.smoke) ["--quick", "--langs", "roc", "--only", "inter", "--no-allocations", "--repetitions", "1", "--label", "smoke"] else ["--check", "--quick"], ctx)
		"docs" => {
			out = Run.fresh!(work.join("docs"))?
			Run.call!(compiler, ["docs", "package/main.roc", "--output=${out.display()}"], root)?
			Run.call!("python3", ["tools/check_artifacts.py", "docs", out.display()], root)
		}
		"bundle" => {
			Run.call!("python3", ["tools/default-fonts/verify.py"], root)?
			out = Run.fresh!(work.join("bundle"))?
			Run.call!(compiler, ["bundle", "package/main.roc", "--output-dir", out.display()], root)?
			Run.call!("python3", ["tools/check_artifacts.py", "bundle", out.display()], root)
		}
		"diff-check" => {
			Run.call!("git", ["diff", "--check"], root)?
			Run.call!("git", ["diff", "--cached", "--check"], root)?
			listing = Run.command("git", ["ls-files", "--others", "--exclude-standard", "-z"], root).capture!()?
			for path in listing.split_on("\u(0000)").keep_if(|p| p != "") {
				output = Run.command("git", ["diff", "--no-index", "--check", "--", "/dev/null", path], root).run!()?
				match output.status {
					Exited(0) | Exited(1) => {}
					_ => return Err(CheckFailed("whitespace error: ${path}: ${output.stdout_utf8_lossy()}"))
				}
			}
			Ok({})
		}
		_ => Err(CheckFailed("unknown check: ${name}"))
	}
}

adapter! : Str, List(Str), Context => Try({}, _)
adapter! = |script, args, ctx| {
	Run.call!("python3", ["scripts/${script}"].concat(args).concat(if (ctx.options.source) ["--source"] else []), ctx.consumer)
}

consumer_apps! : Path => Try(List(Str), _)
consumer_apps! = |directory| {
	fuzz = directory.join("fuzz").list!()?
	Ok(["tests/api/main.roc", "tools/driver/main.roc", "bench/roc/font.roc", "bench/roc/alloc.roc", "fuzz/spec/main.roc"].concat(fuzz.keep_if(|p| p.display().ends_with(".roc")).map(|p| "fuzz/${p.filename().map_ok(Path.display) ?? ""}")))
}
