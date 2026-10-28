app [main!] {
	build: "../support/main.roc",
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	font: "../../package/main.roc",
}

import FontTests
import SubstituteTests
import ReadTests
import ReadOtsTests
import ShapeTests
import ShapeParityTests
import VariationTests
import FuzzRegressionTests
import GposFlagTests
import TraceTests
import QueryTests
import ParityTests
import MetadataTests
import MathTests
import OutlineTests
import CaretTests
import PositionFlagTests
import KhmerTests
import IndicTests
import KernPolicyTests
import MyanmarTests
import UseTests
import PositionContextTests
import PositionTests
import ColorTests
import ColorImageTests
import ArabicTests
import ArabicFallbackTests
import HangulTests
import ThaiLaoTests
import ContextTests
import VerticalTests
import CffTests
import VariationCompletionTests
import AatTests
import AatFallbackTests
import AatPositionTests
import GraphiteReaderTests
import MortTests
import GraphiteTests

## The tests of roc-font's public API. They import the package through
## `package/main.roc`, exactly what ships, and build their fonts with the
## test-only `tests/support` package. Run with:
##
##     roc test tests/api/main.roc
##
## The program itself does nothing; only its expects matter.
main! = |_args| Ok({})
