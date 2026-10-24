app [main!] {
	build: "../support/main.roc",
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	font: "../../package/main.roc",
}

import FontTests
import SubstituteTests
import ReadTests
import ShapeTests
import ShapeParityTests
import VariationTests
import FuzzRegressionTests
import GposFlagTests
import TraceTests
import QueryTests

## The tests of roc-font's public API. They import the package through
## `package/main.roc`, exactly what ships, and build their fonts with the
## test-only `tests/support` package. Run with:
##
##     roc test tests/api/main.roc
##
## The program itself does nothing; only its expects matter.
main! = |_args| Ok({})
