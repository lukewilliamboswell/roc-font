## Check selection shared by the outer runner and its bundle consumer process.
CheckOptions := [].{
	Options : { only : List(Str), skip : List(Str), smoke : Bool, source : Bool, flight : Bool, bundle : Str, no_cache : Bool, fuzz_runs : Str, list : Bool }
	steps = ["compiler", "fmt", "check", "test", "fuzz-smoke", "examples", "conformance", "bench", "docs", "bundle", "diff-check"]
	defaults : Options
	defaults = { only: [], skip: [], smoke: False, source: False, flight: False, bundle: "", no_cache: False, fuzz_runs: "", list: False }
	parse : List(Str) -> Try(Options, Str)
	parse = |args| parse_more(args, defaults)
	parse_more = |args, options| match args {
		[] => if (options.source and options.bundle != "") Err("--source and --bundle exclude each other") else Ok(options)
		["--", .. as rest] => parse_more(rest, options)
		["--only", names, .. as rest] => parse_more(rest, { ..options, only: names.split_on(",") })
		["--skip", names, .. as rest] => parse_more(rest, { ..options, skip: names.split_on(",") })
		["--bundle", path, .. as rest] => parse_more(rest, { ..options, bundle: path })
		["--fuzz-runs", count, .. as rest] => parse_more(rest, { ..options, fuzz_runs: count })
		["--smoke", .. as rest] => parse_more(rest, { ..options, smoke: True })
		["--source", .. as rest] => parse_more(rest, { ..options, source: True })
		["--flight", .. as rest] => parse_more(rest, { ..options, flight: True })
		["--no-cache", .. as rest] => parse_more(rest, { ..options, no_cache: True })
		["--verbose", .. as rest] => parse_more(rest, options)
		["--list", .. as rest] => parse_more(rest, { ..options, list: True })
		[unknown, ..] => Err("unknown check argument: ${unknown}")
	}
	selected : Options -> Try(List(Str), Str)
	selected = |options| {
		unknown = options.only.concat(options.skip).keep_if(|name| !steps.contains(name))
		if !unknown.is_empty() {
			return Err("unknown checks: ${Str.join_with(unknown, ", ")}")
		}
		Ok(steps.keep_if(|name| (options.only.is_empty() or options.only.contains(name)) and !options.skip.contains(name)))
	}
	needs_bundle : List(Str) -> Bool
	needs_bundle = |names| names.any(|name| ["check", "test", "fuzz-smoke", "examples", "conformance", "bench"].contains(name))
}

expect CheckOptions.selected(CheckOptions.parse(["--only", "fmt,test", "--skip", "fmt"])?) == Ok(["test"])
expect CheckOptions.parse(["--source", "--bundle", "bundle.tar.zst"]).is_err()
expect CheckOptions.selected(CheckOptions.parse(["--only", "typo"])?).is_err()
