# Seeded from roc-graph-layout's package-mermaid

- Source worktree: `roc-graph-layout/.claude/worktrees/package-mermaid/`
  (branch `feature/package-mermaid`)
- Source commit: `8813961b6d0c809d87ce7eaf413169daa589a6ee`
- Copied: 2026-10-24, about 16:49 +11:00
- **Working-tree copy, including uncommitted changes.** `Font.roc` and
  `FontShape.roc` were modified, and `FontTest.roc` and both fuzz targets
  were untracked, at the time of copying; another session was still adding
  tests and fixes to them.

These working-tree copies were later committed unchanged in roc-graph-layout
commit `3eccac6` ("Test and harden the font reader and shaper", branch
`feature/package-mermaid`): every hash below matches that commit, so the
seed includes the final test and hardening work.

SHA-256 of each source file as copied, to tell whether the source has moved
on since:

| Source (under the worktree) | SHA-256 |
|---|---|
| `package-mermaid/Font.roc` | `21f7eba51e5b8f7f5e4a71dd32a91ddceb45424006aafd833a95d84a9cef8759` |
| `package-mermaid/FontShape.roc` | `c5f0aba38890fe9b5807047c28176615434aeee9c3654fc177b4d0a4a58187bc` |
| `package-mermaid/FontTest.roc` | `07c7c1ea7fa828e8a2b50b74b7134506c4322c353de1bed0753d401ec8dfd435` |
| `package-mermaid/fuzz_font_read.roc` | `d7cdd2fa431858aa4359adfbd203c2efe3b286e971d81cd3119935ed989d49da` |
| `package-mermaid/fuzz_font_shape.roc` | `4b5592ff7a171b985be6bc333cad5bc2b854e6f3a9e82fdd2cd5f709dc19e5f1` |
| `package-mermaid/FontInter.ttf` | `aee1d667e8df7bce848c20eec4d5fb266a7994c8ac010829a5fc900d681c675c` |
| `package-mermaid/FontInter-OFL.txt` | `262481e844521b326f5ecd053e59b98c8b2da78c8ee1bdbb6e8174305e54935a` |
| `tools/mermaid-oracle/font_subset.mjs` | `830f4abb71741f68725e1d288a9a21343bf52ecb4ccdfb8478fde43731110343` |

## What changed in each file

**`package/Font.roc`** from `package-mermaid/Font.roc`, the part before the
first top-level `expect` (source lines 2-956):
- removed `import "FontInter.ttf" as inter_file : List(U8)` and the public
  `inter : Font` value (no font in the package);
- removed `import FontTest` (only the tests used it);
- module doc: replaced the sentence describing the built-in `inter` with
  "No font is built in: callers supply the bytes of the font they use.";
- no other change. Behaviour of every remaining item is unchanged.

**`package/FontTests.roc`** (new, test-only) from `package-mermaid/Font.roc`
source lines 958 to the end (all 134 top-level expects and their helpers),
verbatim except:
- a header importing `Font`, `FontTest` and
  `"../tests/fonts/Inter-Regular-metrics.ttf" as inter_file`, and the
  namesake `FontTests :: {}.{}`;
- a module-local `inter : Font` (the former `Font.inter`, same fallback to
  `Font.empty`), and every `Font.inter` replaced by `inter`.

**`package/FontShape.roc`** from `package-mermaid/FontShape.roc`, the part
before the test helpers (source lines 2-905): removed `import FontTest`
and the leading blank line. No other change.

**`package/FontShapeTests.roc`** (new, test-only) from
`package-mermaid/FontShape.roc` source lines 907 to the end (all 71
expects and their helpers), verbatim, under a header importing `FontShape`
and `FontTest` and the namesake `FontShapeTests :: {}.{}`.

**`package/FontTest.roc`**: verbatim.

**`package/fuzz_font_read.roc`**:
- the Inter import now reads `"../tests/fonts/Inter-Regular-metrics.ttf"`;
- target name `mermaid-font-read` became `font-read`.

**`package/fuzz_font_shape.roc`**, rewritten where it used
package-mermaid's `TextMeasure` and `FlowGeometry`, which stay there:
- removed `import FlowGeometry` and `import TextMeasure`; the Inter import
  reads from `tests/fonts/`; target name `mermaid-font-shape` became
  `font-shape`;
- the fallback font `Font.inter` became a local `inter` read from the test
  font (`?? Font.empty`);
- unchanged: determinism of substitution, the `4 n + 32` / `36 n` growth
  bound, clusters in range, one finite kerning value per glyph;
- replaced: the `TextMeasure.block` checks (finite non-negative pixel
  sizes, line height) with a font-unit `width` (advances plus kerning after
  substitution) that must be deterministic and finite;
- replaced: allocation scaling of `TextMeasure.block` (unwrapped 2 vs 16
  copies, wrapped 16 vs 128) with scaling of `width` at 2 vs 16 copies,
  same bound (`10 x + 256`) and `expect_no_leaks!`. The wrapped case is
  gone because wrapping is consumer policy.

**`tests/fonts/Inter-Regular-metrics.ttf`** and **`tests/fonts/Inter-OFL.txt`**:
byte-identical copies of `FontInter.ttf` and `FontInter-OFL.txt`, renamed.

**`tools/font_subset.mjs`**: the header comment now describes a test
fixture instead of the package's embedded default, and gives the new path.
Code unchanged.

Not copied: `tools/mermaid-oracle/measure_probe.mjs` (it drives Mermaid
through `oracle.mjs`; nothing font-specific to reuse beyond the Puppeteer
font-loading pattern, which a font oracle can take from it later). There
were no `font_test_*` scripts. `TextMeasure.roc` was read only, to see how
the API is consumed.

## Re-syncing

When the package-mermaid testing work lands, redo the same split:
1. `Font.roc`: everything before the first top-level `expect` goes to
   `package/Font.roc` (drop the Inter import, `import FontTest` and
   `inter`; keep the doc change); everything from it goes to
   `package/FontTests.roc` under the existing header, with `Font.inter`
   replaced by `inter`.
2. `FontShape.roc`: everything before `# ---... test helpers` goes to
   `package/FontShape.roc` (drop `import FontTest`); the rest goes to
   `package/FontShapeTests.roc`.
3. `FontTest.roc`: copy verbatim.
4. Fuzz targets: copy, then reapply the changes above. For
   `fuzz_font_shape.roc`, port any new font-level checks and leave
   `TextMeasure` checks in package-mermaid.
5. If the font fixture changed, copy it to `tests/fonts/` again.
Then run the checks listed in `README.md` and update this file.
