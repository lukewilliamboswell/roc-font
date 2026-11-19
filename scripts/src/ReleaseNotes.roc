## Render the small AsciiDoc subset used by release notes, failing placeholders.
ReleaseNotes := [].{
	render : Str, Str, Str -> Try(Str, Str)
	render = |source, url, compiler| {
		if !source.contains("{package-url}") {
			return Err("release notes must use {package-url}")
		}
		text = Str.join_with(source.split_on("{package-url}"), url)
		if text.split_on("{").drop_first(1).any(|part| part.split_first("}").map_ok(|pair| pair.before.ends_with("-url")) ?? False) {
			return Err("release notes contain an unresolved URL placeholder")
		}
		var $lines = []
		var $in_source = False
		var $language = ""
		for line in text.split_on("\n") {
			if line.starts_with("[source,") and line.ends_with("]") {
				$language = line.drop_prefix("[source,").drop_suffix("]").trim()
			} else if line.trim() == "----" {
				$lines = $lines.append(if ($in_source) "```" else "```${$language}")
				$in_source = !$in_source
				$language = ""
			} else if !$in_source and line.starts_with("=") {
				prefix = line.split_first(" ").map_ok(|pair| pair.before.to_utf8().len()) ?? 0
				if line.to_utf8().get(prefix) == Ok(' ') {
					$lines = $lines.append("${Str.repeat("#", prefix)}${Str.from_utf8_lossy(line.to_utf8().drop_first(prefix))}")
				} else {
					$lines = $lines.append(line)
				}
			} else {
				$lines = $lines.append(line)
			}
		}
		if $in_source {
			return Err("release notes contain an unclosed source block")
		}
		Ok("${Str.join_with($lines, "\n")}\n## Compilers\n\n```\n${compiler}\n```\n")
	}
}

expect ReleaseNotes.render("= Demo\n\n{package-url}\n", "https://example.test/bundle", "compiler")?.starts_with("# Demo\n\nhttps://example.test/bundle")
expect ReleaseNotes.render("= Demo", "url", "compiler").is_err()
expect ReleaseNotes.render("{package-url} {other-url}", "url", "compiler").is_err()
expect ReleaseNotes.render("{package-url}\n[source,roc]\n----\ncode", "url", "compiler").is_err()
