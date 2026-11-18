# Product checks use the current nightly on PATH. Released automation tools
# and the compiler that runs scripts have independent, reviewed lock entries.
app [config] { pf: platform "https://github.com/lukewilliamboswell/roc-blueprint/releases/download/0.12.0/GSb71LxYHqLohZz8jMfawWEwQcyev9ZdVC26sfsDwfq8.tar.zst" }

import pf.Recipes

config = [
	Name("roc-font"),
	Systems(["x86_64-linux", "aarch64-linux", "aarch64-darwin"]),
	Environment("package", [Programs([Fetch("roc-stable", Recipes.roc_nightly("nightly-2026-11-18-a520eed")), Fetch("release-package", Recipes.file("https://github.com/lukewilliamboswell/roc-automation/releases/download/tools-0.10.1/release-package-{system}"))]), Expect(["roc", "python3", "git", "zip", "touch"])]),
	Environment("release", [Programs([Fetch("release-package", Recipes.file("https://github.com/lukewilliamboswell/roc-automation/releases/download/tools-0.10.1/release-package-{system}"))]), Expect(["roc", "git", "gh", "tar", "unzip", "zip", "chmod", "touch", "env"])]),
	Environment("release-test", [Programs([Fetch("release-package", Recipes.file("https://github.com/lukewilliamboswell/roc-automation/releases/download/tools-0.10.1/release-package-{system}"))]), Expect(["roc"])]),
	Environment("docs", [Programs([Fetch("roc-docs", Recipes.file("https://github.com/lukewilliamboswell/roc-automation/releases/download/tools-0.10.1/roc-docs-{system}"))]), Expect(["sh", "realpath", "roc"])]),
	Task("check", [Use("package"), Run(["roc-stable", "scripts/check.roc"])]),
	Task("examples", [Use("package"), Run(["roc-stable", "scripts/examples.roc"])]),
	Task("fuzz-smoke", [Use("package"), Run(["python3", "scripts/run_fuzz.py", "smoke"])]),
	Task("conformance", [Use("package"), Run(["python3", "scripts/conformance.py"])]),
	Task("bench-quick", [Use("package"), Run(["python3", "scripts/bench.py", "--quick"])]),
	Task("api-docs", [Use("package"), Run(["roc", "docs", "package/main.roc", "--output=generated-docs"])]),
	Task("test", [Use("package"), Run(["roc-stable", "scripts/check.roc", "--", "--only", "compiler,test"])]),
	Task("release-examples", [Use("package"), Run(["roc-stable", "scripts/release_examples.roc"])]),
	Task("release-notes", [Use("package"), Run(["roc-stable", "scripts/release_notes.roc"])]),
	Task("release-test", [Use("release-test"), Run(["release-package"])]),
	Task("docs", [Use("docs"), Run(["roc-docs", "build", "--workspace", ".", "--pdf-filename", "roc-font.pdf", "--api-entrypoint", "package/main.roc", "--roc-command", "roc", "--site-url", "https://lukewilliamboswell.github.io/roc-font/"])]),
	Task("docs-path", [Use("docs"), Run(["sh", "-c", "realpath \"$(command -v roc-docs)\""])]),
]
