# Encoded color-image font facts

`images.ttf` and its corruption variants are original synthetic tables
and geometric SVG/red-pixel fixtures under roc-font's UPL licence.
`generate.py` with pinned fontTools4.61.1 reproduces them.

Coverage includes:

- SVG document ranges, shared documents, plain UTF-8 and gzip;
- sbix PNG/JPEG/TIFF/PDF/mask tags, table-order strikes and multi-hop
  duplicate resolution, including cycle and invalid-reference rejection;
- all five CBLC index formats, CBDT image formats17/18/19, sparse glyph
  coverage, shared metrics, and horizontal/vertical small metrics;
- exact native pixel metrics, distinct from font-unit advances;
- malformed offsets/ranges/payload lengths, missing bitmap-table partners,
  independent optional-table problems and strict-versus-lenient reading.

The non-PNG sbix records deliberately contain opaque format-dispatch
payloads. They test byte preservation, not whether a JPEG/TIFF/PDF/mask
renderer accepts the content. Likewise, reading proves font-container
references and lengths, not image codecs, XML semantics or gzip contents.

`emoji-subset.ttf` is a renamed OFL1.1 derivative of Noto Color Emoji,
from googlefonts/noto-emoji revision
`99701e07d3d1fe1bdbcdb14964547f0fd592966f`,
`2D/fonts/NotoColorEmoji.ttf`. `emoji-pin.json` records source/subset
SHA-256 hashes and the selected text. Its exact upstream font licence is
`NotoColorEmoji-LICENSE.txt`. Rebuild it with:

```
/path/to/pinned-python generate.py --noto /path/to/pinned/NotoColorEmoji.ttf
```

The subset retains real substitutions, variation-selector mappings and
actual encoded PNG payloads for woman-technologist, a VS16 heart,
a skin-tone modifier sequence, the Australia flag and a single emoji.
Tests shape the text first, then retrieve artwork using the resulting
glyph IDs and an explicitly selected strike. The font subset is test-only;
it is never imported by the library or shipped as a fourth default font.

`cases.jsonc` is the conformance input. `oracle.py` records independent
fontTools4.61.1 metrics/container facts and HarfBuzz14.6.0
(uharfbuzz0.56.3) SVG/PNG blobs and shaped runs into `oracle.json`.
The real CBDT font's PNG payloads agree byte for byte with HarfBuzz.
FontTools exposes sbix strikes through a reverse-insertion-order dictionary;
the recorder reconstructs original file order instead of treating dictionary
order as table order. Duplicate placement follows FreeType's sbix retry
semantics: the source image's origin is retained, and `source_glyph`
identifies it. Vertical small metrics store top/left in the opposite
field order to big metrics; the API consistently exposes x=left,y=top.

`verify.py` uses standard-library Python only. It builds `query.roc`
as an optimised native executable against the served package bundle,
then replays **every cached fact**, including complete payload bytes,
all glyphs/strikes, absent and out-of-range queries, and actual shaped
emoji runs. No Roc files are generated. Run:

```
ROC=/path/to/roc python3 tests/fonts/color-images/verify.py
```

The recorded suite has8cases and245exact facts. `--dev` checks the default
native backend; recording anew requires the pinned oracle environment.
The dedicated public test app is `tests/api/color-images.roc`.
`fuzz/font-color-images.roc` measures reading/query allocations separately
for SVG,sbix,CBDT at8and64generated glyphs and exercises real-font seed
mutations, all five index formats, deterministic total queries and leaks.
