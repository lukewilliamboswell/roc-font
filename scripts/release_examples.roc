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
	if args.len() != 7 or args.first() != Ok("package") {
		return Err(Usage("package --version VERSION --bundle FILE --output-dir DIR"))
	}
	version = option(args, "--version").map_err(|message| InvalidArguments(message))?
	bundle = Path.utf8(option(args, "--bundle").map_err(|message| InvalidArguments(message))?)
	output = Path.utf8(option(args, "--output-dir").map_err(|message| InvalidArguments(message))?).absolute!()?
	if !plain(version, "-.") or version.starts_with("-") {
		return Err(InvalidVersion)
	}
	name = bundle.filename().map_ok(Path.display).map_err(|_| InvalidBundle)?
	if name == ".tar.zst" or !name.ends_with(".tar.zst") or !name.drop_suffix(".tar.zst").to_utf8().all(|b| "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".to_utf8().contains(b)) or !bundle.is_file!()? {
		return Err(InvalidBundle)
	}
	root = Run.root!()?
	repository = Env.var_str!("GITHUB_REPOSITORY") ?? "lukewilliamboswell/roc-font"
	if repository.split_on("/").len() != 2 or !repository.split_on("/").all(|part| plain(part, "-._")) {
		return Err(InvalidRepository)
	}
	url = "https://github.com/${repository}/releases/download/${version}/${name}"
	stage = Env.create_temp_dir_in!(Run.work!()?, "archive-")?
	root_name = "roc-font-examples-${version}"
	archive_root = stage.join(root_name)
	archive_root.create_all!()?
	suite : Suite
	suite = Json.parse(root.join("tests/spec.json").read_utf8!()?)?
	if suite.schema_version != 1 or suite.release != "working-tree" or !suite.dependencies.is_empty() {
		return Err(InvalidSuite)
	}
	archive_root.join("spec.json").write_utf8!(Json.to_str({ ..suite, release: version, dependencies: [url] }))?
	archive_root.join("README.md").write_utf8!("# roc-font ${version} examples\n\nRun with the latest Roc nightly. Each application imports ${url}.\n\n`spec.json` records every case's arguments, input, output and exit status.\n")?
	listing = Run.command("git", ["ls-files", "-z", "--", "examples"], root).capture!()?
	files = listing.split_on("\u(0000)").keep_if(|path| path != "")
	var $members = ["${root_name}/README.md", "${root_name}/spec.json"]
	var $archived_apps = []
	for path in files {
		original = root.join(path)
		if original.type!()? != IsFile or !path.split_on("/").all(|part| plain(part, "-._")) {
			return Err(UnsafeArchivePath(path))
		}
		destination = archive_root.join(path)
		destination.parent()?.create_all!()?
		if path.ends_with(".roc") {
			text = original.read_utf8!()?
			if text.contains("app [") {
				local = "\tfont: \"../package/main.roc\","
				parts = text.split_on(local)
				if parts.len() != 2 {
					return Err(InvalidDependency(path))
				}
				destination.write_utf8!(Str.join_with(parts, "\tfont: \"${url}\","))?
				$archived_apps = $archived_apps.append(path)
			} else {
				original.copy!(destination)?
			}
		} else {
			original.copy!(destination)?
		}
		$members = $members.append("${root_name}/${path}")
	}
	if suite.apps.len() != $archived_apps.len() or !suite.apps.all(|example| $archived_apps.contains(example.path)) {
		return Err(ExampleCoverageMismatch)
	}
	for member in $members {
		stage.join(member).set_permissions!(PublicRead)?
	}
	# Files only, in fixed order, with fixed ZIP timestamps and no extra fields.
	Run.command("touch", ["-t", "198001010000"].concat($members), stage).env("TZ", "UTC").call!()?
	output.create_all!()?
	archive = output.join("${root_name}.zip")
	if archive.exists!()? {
		archive.delete!()?
	}
	Run.command("zip", ["-X", "-q", archive.display()].concat($members), stage).env("TZ", "UTC").call!()?
	stage.delete_all!()?
	Stdout.line!("Created ${archive.display()}")?
	Ok({})
}

option : List(Str), Str -> Try(Str, Str)
option = |args, key| match args.split_first(key) {
	Ok({ after: [value, ..], .. }) => Ok(value)
	_ => Err("missing ${key}")
}

plain : Str, Str -> Bool
plain = |value, extra| value != "" and value.to_utf8().all(|b| (b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z') or (b >= '0' and b <= '9') or extra.to_utf8().contains(b))
