import cli.Cmd
import cli.Duration
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stdout

## Bounded native child processes. Product commands always use ROC or bare roc;
## only this automation runs on roc-stable.
Run := [].{
	compiler! : () => Str
	compiler! = || Env.var_str!("ROC") ?? "roc"
	root! : () => Try(Path, _)
	root! = || match Env.var_str!("ROC_FONT_CHECKOUT") {
		Ok(path) => Ok(Path.utf8(path))
		Err(_) => Env.cwd!()
	}
	work! : () => Try(Path, _)
	work! = || match Env.var_str!("ROC_FONT_RUN_WORK") {
		Ok(path) => Ok(Path.utf8(path))
		Err(_) => {
			root = root!()?
			base = Path.utf8(Env.var_str!("ROC_FONT_TMPDIR") ?? root.join(".roc-font-tmp").display()).join("checks")
			base.create_all!()?
			Env.create_temp_dir_in!(base, "run-")
		}
	}
	command : Str, List(Str), Path -> Cmd.Command
	command = |program, args, cwd| Cmd.new(OsStr.from_str(program)).args(args.map(OsStr.from_str)).cwd(cwd).timeout(Duration.millis(3_600_000)).manage_tree(True)
	call! : Str, List(Str), Path => Try({}, _)
	call! = |program, args, cwd| {
		Stdout.line!("+ ${program} ${Str.join_with(args, " ")}")?
		command(program, args, cwd).call!()
	}
	files! : Path => Try(List(Path), _)
	files! = |directory| {
		var $files = []
		for path in directory.list!()? {
			if path.is_dir!()? {
				$files = $files.concat(files!(path)?)
			} else {
				$files = $files.append(path)
			}
		}
		Ok($files)
	}
	fresh! : Path => Try(Path, _)
	fresh! = |path| {
		if path.exists!()? {
			path.delete_all!()?
		}
		path.create_all!()?
		Ok(path)
	}
	dep! : () => List(Str)
	dep! = || {
		url = Env.var_str!("ROC_FONT_BUNDLE_URL") ?? ""
		if (url == "") [] else ["--replace-dep", "./package/main.roc", url]
	}
}
