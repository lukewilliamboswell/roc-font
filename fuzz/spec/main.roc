app [target] {
	build: "../../tests/support/main.roc",
	font: "../../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.8.0/BUNcJDHxCd7xLVSe3WBioyXqR6tm1MqXwzwGgtnmqK43.tar.zst",
}

import fuzz.Fuzz
import Budgets
import Cmap
import Composite
import Context
import DeltaMap
import Features
import Gpos
import Gsub
import Math
import MathVariants
import Metrics
import Outlines
import Reverse

target = Fuzz.suite([Cmap.target, Context.target, Gpos.target, Gsub.target])

expect Budgets.check({})
expect Composite.check({})
expect DeltaMap.check({})
expect Features.check({})
expect Math.check({})
expect MathVariants.check({})
expect Metrics.check({})
expect Outlines.check({})
expect Reverse.check({})
