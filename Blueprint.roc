# Development environment and named tasks for roc-font, realised by
# roc-blueprint without Nix (roc-automation's pure-package guide).
#
#     blueprint run check          # everything a pull request must pass
#     blueprint run check -- --only fmt,test
#     blueprint run examples       # build and run examples/, compare with tests/examples.json
#     blueprint run docs           # the manual as a site, Markdown and PDF in .docs-out/
#     blueprint update             # refresh Blueprint.lock after changing a recipe
#
# The package compiler is the bare `roc` on PATH, never a fetched program.
# It must be the nightly named in .roc-version: scripts/all_tests.py fails
# its roc-version step otherwise. Set ROC to that compiler's path when
# another `roc` comes first on PATH. The checks are Python 3 scripts using
# the standard library only, so no tooling compiler is fetched.
app [config] { pf: platform "https://github.com/lukewilliamboswell/roc-blueprint/releases/download/0.8.0/FbJymjYdCxx9vqMcau7r4tQfeAbnVGqqJoYrLGqPCqKu.tar.zst" }

import pf.Recipes

config = [
	Name("roc-font"),
	Systems(["x86_64-linux", "aarch64-linux", "aarch64-darwin"]),
	# The released documentation renderer; its bytes are pinned in Blueprint.lock.
	Environment("docs", [Programs([Fetch("roc-docs", Recipes.file("https://github.com/lukewilliamboswell/roc-automation/releases/download/tools-0.2.0/roc-docs-{system}"))]), Expect(["realpath", "sh"])]),
	# The package compiler and the check scripts' interpreter come from the machine.
	Environment("package", [Expect(["roc", "python3", "git"])]),
	# Every check, in order: fmt, check, tests (dev and interpreter), fuzz
	# smoke, conformance replay, allocation ratchet, API docs, bundle and
	# whitespace. Extra arguments go to scripts/all_tests.py (--only, --skip, --list).
	Task("check", [Use("package"), Run(["python3", "scripts/all_tests.py"])]),
	# The unit and API tests alone, on the dev backend and the interpreter.
	Task("test", [Use("package"), Run(["python3", "scripts/all_tests.py", "--only", "roc-version,test,test-interpreter"])]),
	# Build every fuzz target natively and replay its seeds briefly.
	Task("fuzz-smoke", [Use("package"), Run(["python3", "scripts/run_fuzz.py", "smoke"])]),
	# Replay the recorded HarfBuzz, Chrome and reading oracle results.
	Task("conformance", [Use("package"), Run(["python3", "scripts/conformance.py"])]),
	# Build and run every example under examples/ and compare its output with
	# tests/examples.json. After an intended change: blueprint run examples -- --update
	Task("examples", [Use("package"), Run(["python3", "scripts/examples.py", "check"])]),
	# Timing smoke run against the comparison implementations that are present.
	Task("bench-quick", [Use("package"), Run(["python3", "scripts/bench.py", "--quick"])]),
	# The manual: docs/index.adoc rendered as a site, static Markdown and a PDF.
	Task("docs", [Use("docs"), Run(["roc-docs", "build", "--workspace", ".", "--pdf-filename", "roc-font.pdf"])]),
	# The renderer's real path, for actions/blueprint-tool and actions/build-docs.
	Task("docs-path", [Use("docs"), Run(["sh", "-c", "realpath \"$(command -v roc-docs)\""])]),
]
