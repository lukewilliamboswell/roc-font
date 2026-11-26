app [target] {
	build: "../tests/support/main.roc",
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.8.0/BUNcJDHxCd7xLVSe3WBioyXqR6tm1MqXwzwGgtnmqK43.tar.zst",
}

import fuzz.Fuzz
import src/FontShape
import src/FontScalars
import src/FontIndic
import src/FontGsub
import src/FontGpos
import src/FontMarks

target = Fuzz.suite([
	FontShape.target,
	FontScalars.target,
	FontIndic.target,
	FontGsub.target,
	FontGpos.target,
	FontMarks.target,
])
