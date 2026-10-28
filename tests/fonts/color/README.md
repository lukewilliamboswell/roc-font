# Color font foundation fixtures

These are test fonts, never default fonts or bundled package resources.
`generate.py` creates the original `color-v0.ttf`, `color-all.ttf`,
`color-map.ttf` and `color-precision.ttf` with fontTools 4.61.1. Their license
is `SYNTHETIC-LICENSE.txt` (UPL). They have simple TrueType box outlines.

The v0 font includes a two-layer glyph and an explicitly empty base record.
CPAL v1 palettes overlap in the underlying color records, with straight
RGBA, background flags, names, entry names and an absent entry name. The
v1 fonts cover every paint format 1–32, reference sharing, color glyph
references, clip boxes, gradient stops stored out of order (including
stable ties), all transforms and Multiply compositing. Variable cases
exercise the font's own store, an implicit identity index map, explicit
mapping, final-map-entry fallback, negative radial radii and alpha clamping.
The four-axis precision font produces a 2^-72 affine translation at
normalized coordinates [1,1,1,1], and a 32-column signed-32-bit delta sum at
[16384,16384,16384,16384]. Geometry is binary32 widened exactly to binary64;
small valid values are retained instead of a shaping-position cache's
2.30 scalar quantization.

`noto-emoji-subset.ttf` is a renamed test derivative of Google's official
Noto Emoji v2.051 COLRv1 font (copyright 2022 Google Inc.), licensed under
SIL OFL 1.1; its full license is `Noto-LICENSE.txt`. `sources.json` pins the
original commit, URL and hashes. Reproduce with:

```
python subset_noto.py /path/to/the/pinned/Noto-COLRv1.ttf
```

The subset retains the glyph closure for 😀, 👩‍💻 and ❤️, including GSUB,
120 glyphs and six color glyph roots. It uses genuine TrueType outlines.
The public behavior test shapes each sequence, queries its paint DAG, and
resolves every glyph-clipping leaf to a nonempty public outline. This
proves the font boundary needed by a renderer, without implementing one.
The native example also runs against the unmodified 4,991,984-byte source
font: 😀 maps to glyph1875 (18 paint nodes,9 outline leaves,144 path commands),
👩‍💻 to glyph1285 (33 nodes,17 leaves,290 commands), and ❤️ to glyph3721
(10 nodes,5 leaves,106 commands). The subset has the same outline-leaf and
path-command counts; its ZWJ DAG has31 nodes because fontTools shares some
identical paints. Semantic oracle comparison intentionally allows that
physical DAG sharing difference. The unmodified source also passes OTS9.3.

`cases.jsonc` is the independent test input. `oracle.py` records fontTools
4.61.1 parsed tables and independently evaluates variation fields in their
binary32 format units. HarfBuzz 14.6.0/uharfbuzz 0.56.3 independently checks
palette colors, flags, COLR0 layers and v1 glyph presence, traverses every
color glyph through paint callbacks to check leaf glyphs, fills, gradients,
stop values, alpha and extend modes, confirms the precision font's affine
matrix, and shapes the three real emoji sequences. Callback records are
cached beside the full font-fact records in `oracle.jsonl`.

`verify.py` builds `query.roc` as an optimized native application against a
served `roc bundle`. It replays every cached case without fontTools or
HarfBuzz installed. It checks returned IDs/reachability and compares semantic
graph hashes; physical node numbering/sharing is not prescribed by the
oracle. Every returned geometry value compares by binary64 bits, including
tiny values. Font hashes prevent stale fixture/oracle combinations.

The exported graph keeps typed transform operations rather than composing
matrices or using trigonometry. Consequently fontTools is the direct
metadata oracle for operation parameters; HarfBuzz's rendering callbacks
independently check the resulting fill facts. HarfBuzz gradient callbacks
return stops in stored order, so the recorder applies the specified stable
ordering. HarfBuzz resolves alpha to 8-bit color; callback checks allow
half a color-channel step, while font-fact alpha is checked exactly against
fontTools. HarfBuzz's clip callbacks round to integer positions nearest;
font-fact clip bounds use the COLR specification's outward rounding.

All five fixture fonts pass OTS 9.3.0. OTS is a structural acceptance oracle;
it does not replace the numeric graph oracle. The reader additionally
rejects paint cycles, references outside checked tables, unbounded base
paint graphs without clips, excessive depth and work-budget exhaustion.
A valid CPAL with at least one palette and one color is required for COLR,
even when a paint uses only foreground. No rendering, palette selection,
font discovery, text fallback, pixel rounding or image decoding happens
inside the package.

Primary specifications:
- https://learn.microsoft.com/en-us/typography/opentype/spec/cpal
- https://learn.microsoft.com/en-us/typography/opentype/spec/colr
