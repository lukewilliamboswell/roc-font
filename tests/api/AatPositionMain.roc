app [main!] {
	build: "../support/main.roc",
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	font: "../../package/main.roc",
}
import cli.OsStr
import AatPositionTests
main! : List(OsStr) => Try({}, _)
main! = |_| Ok({})
