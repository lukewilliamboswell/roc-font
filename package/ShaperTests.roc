import Face
import Shaper
import "../tests/fonts/Inter-Regular-metrics.ttf" as inter_file : List(U8)

## In-package tests of `Shaper` for what `Font` does not reach yet: the
## character cluster level (`Shaper.plan_with_clusters`). Expectations are
## HarfBuzz 14.6.0's (uharfbuzz 0.56.3) at cluster levels 0 and 1, glyphs,
## clusters and unsafe-to-break flags (mark offsets come from `GPOS` mark
## positioning, which is not compared here). Test-only: `main.roc` does not
## import this module. Run with `roc test package/ShaperTests.roc`.
ShaperTests :: {}.{}

inter : Face
inter = match Face.read(inter_file, { face: 0, strict: False, max_bytes: 268_435_456, max_faces: 1024, max_lookups: 16_384, max_depth: 64 }) {
	Ok(face) => face
	Err(_) => crash "the Inter test font could not be read"
}

shaped : Str, [Graphemes, Characters], [FromScript, LeftToRight, RightToLeft] -> { glyphs : List(U32), clusters : List(U64), flags : List(U8) }
shaped = |text, level, direction| {
	options = { script: "Latn", language: "", direction, features: [], growth: 64, operations: 1024 }
	run = Shaper.shape(inter, Face.current(inter), Shaper.plan_with_clusters(inter, options, level), Shaper.decode(text))
	{ glyphs: run.glyphs, clusters: run.clusters, flags: run.flags }
}

# A letter and a combining acute: one cluster at the grapheme level; two at
# the character level, unsafe to break between them.
expect shaped("x\u(301)", Graphemes, LeftToRight) == { glyphs: [993, 1770], clusters: [0, 0], flags: [0, 0] }
expect shaped("x\u(301)", Characters, LeftToRight) == { glyphs: [993, 1770], clusters: [0, 1], flags: [0, 1] }

# Marks reordered by combining class merge the clusters of what moved, at
# either level.
expect shaped("x\u(301)\u(323)y", Graphemes, LeftToRight).clusters == [0, 0, 0, 5]
expect shaped("x\u(301)\u(323)y", Characters, LeftToRight) == { glyphs: [993, 1775, 1770, 998], clusters: [0, 1, 1, 5], flags: [0, 1, 1, 0] }

# An emoji modifier and a ZWJ sequence continue the grapheme before them.
expect shaped("\u(1F44D)\u(1F3FD)", Graphemes, LeftToRight) == { glyphs: [0, 0], clusters: [0, 0], flags: [2, 2] }
expect shaped("\u(1F44D)\u(1F3FD)", Characters, LeftToRight) == { glyphs: [0, 0], clusters: [0, 4], flags: [2, 3] }
expect shaped("a\u(200D)\u(1F600)b", Graphemes, LeftToRight) == { glyphs: [507, 1777, 0, 578], clusters: [0, 0, 0, 8], flags: [0, 0, 2, 0] }
expect shaped("a\u(200D)\u(1F600)b", Characters, LeftToRight) == { glyphs: [507, 1777, 0, 578], clusters: [0, 1, 4, 8], flags: [0, 1, 3, 0] }

# Shaped against the script's direction, graphemes reverse whole; at the
# character level their clusters merge as they do.
expect shaped("x\u(301)\u(323)y", Characters, RightToLeft).clusters == [5, 0, 0, 0]
expect shaped("\u(1F44D)\u(1F3FD)", Characters, RightToLeft).clusters == [0, 0]
