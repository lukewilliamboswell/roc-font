app [target] {
	build: "../../tests/support/main.roc",
	font: "../../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.8.0/BUNcJDHxCd7xLVSe3WBioyXqR6tm1MqXwzwGgtnmqK43.tar.zst",
}

import fuzz.Fuzz
import Cmap
import Features
import Gpos
import Gsub
import Math
import Metrics

target = Fuzz.suite([Cmap.target, Gpos.target, Gsub.target])

expect Features.check({})
expect Math.check({})
expect Metrics.check({})
