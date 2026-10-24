# `name` and `post` fixtures

Tiny generated fonts for `package/TableNameTests.roc` and
`package/TablePostTests.roc`. They are not real typefaces: every glyph is
empty, and only the `name` and `post` tables matter.

- `mac-roman-v1.ttf`: a family name only on the Macintosh Roman platform
  (1, 0, language 0), with characters past ASCII (`Café™ Mac`); `post`
  version 1.0 for eight glyphs, with an underline, an italic angle of -12.5
  degrees and the fixed-pitch flag.
- `ranking-v2.ttf`: family names (name ID 1) in Windows German, Macintosh
  Roman, the Unicode platform and Windows British English, and typographic
  family names (name ID 16) in Macintosh Roman and in Windows full-repertoire
  US English with a character outside the BMP (`Emoji 😀 Sans`); `post`
  version 2.0 with stored names, one of them past ASCII (`café`).
- `format1-v25.ttf`: a format 1 naming table whose family names are on the
  Unicode platform with the language tags `de` and `EN-us`; `post` version
  2.5 (deprecated) for five glyphs. Both tables are assembled by hand:
  fontTools writes only format 0 naming tables and cannot read or write
  version 2.5.
- `japanese-v3.ttf`: a family name only in Windows Japanese; `post` version
  3.0 (no glyph names).

They are generated, byte for byte reproducibly, by `generate.py` (fontTools
4.61.1 from `tools/oracle/`):

    tools/oracle/.venv/bin/python -I tests/fonts/name-post/generate.py

fontTools' `getBestFamilyName()` agrees with roc-font on every fixture except
`ranking-v2.ttf`, where it answers `Mac Typo`: it takes the first record in
US English or Macintosh English, in table order, and records sort by
platform, so Macintosh comes before Windows. roc-font prefers the Windows
record, as browsers do.

These files and the script are original work of the roc-font authors,
released under the repository's licence (`LICENSE`, the Universal Permissive
License 1.0). They contain no third-party font data.
