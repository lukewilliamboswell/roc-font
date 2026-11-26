app [target] {
	build: "../tests/support/main.roc",
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.8.0/BUNcJDHxCd7xLVSe3WBioyXqR6tm1MqXwzwGgtnmqK43.tar.zst",
}

import fuzz.Fuzz
import src/FontVar
import src/FontGvar
import src/FontLayoutVar
import src/FontMath

target = Fuzz.suite([
	FontVar.target,
	FontGvar.target,
	FontLayoutVar.target,
	FontMath.target,
])
