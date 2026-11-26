app [target] {
	build: "../tests/support/main.roc",
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.8.0/BUNcJDHxCd7xLVSe3WBioyXqR6tm1MqXwzwGgtnmqK43.tar.zst",
}

import fuzz.Fuzz
import src/FontRead
import src/FontCmap
import src/FontCoverage
import src/FontMarkRead
import src/FontOts

target = Fuzz.suite([
	FontRead.target,
	FontCmap.target,
	FontCoverage.target,
	FontMarkRead.target,
	FontOts.target,
])
