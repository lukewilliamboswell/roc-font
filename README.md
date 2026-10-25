# roc-font

Read font files and turn text into positioned glyphs, in pure Roc.

Give roc-font the bytes of a TrueType or OpenType font, or use one of its
three built-in fonts, and it tells you how wide text is and which glyphs to
draw where: font facts (units per em, ascent and descent, the glyph for
each character, advances and glyph boxes) and shaped runs (glyph ids,
advances, offsets, and clusters pointing back into your text), all in font
units. It needs no host, no system fonts and no file access, so it works
the same in an application, a package, a test or a browser.

It is for programs that lay out text themselves: diagram and chart
renderers, PDF writers, layout engines and games. Drawing glyphs, wrapping
lines and choosing fallback fonts stay with your program.

## Status

**0.1.0-rc2, a release candidate for the first release.** Text is shaped as HarfBuzz's default shaper
shapes it, which covers Latin, Greek, Cyrillic and other scripts that need
no script-specific shaper, plus HarfBuzz's Hebrew shaper. Variable fonts are
measured at any weight, width or optical size. Scripts that need their own
shaper (Arabic joining, the Indic scripts, Thai, Khmer and others) are shaped
by the default shaper for now, and mark attachment, cursive and contextual
positioning are not applied yet. The API may still change before 1.0.

## Example

How wide is "Hello, world!" at 16 px? This is
[`examples/measure.roc`](examples/measure.roc), which CI runs and checks:

```roc
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	font: "{package-url}",
}

import cli.Stdout
import font.Font

# How wide is a string, in pixels, at a given font size?
#
#     roc examples/measure.roc
#
# `Font.sans` is a font built into roc-font (Inter), so no font file is
# needed. `Font.width` shapes the text as a browser would, with the font's
# default ligatures and kerning, and adds up the glyphs' advances.
main! = |_args| {
	text = "Hello, world!"
	size = 16.I32 # the font size in pixels: the height of one em

	# roc-font measures in font units, integers on the font's own grid of
	# `units_per_em` units to the em.
	units = Font.width(Font.sans, text)
	units_per_em = Font.units_per_em(Font.sans)

	# Scale to pixels. Rounding, if you want it, is yours to choose.
	pixels = (units * size).to_dec() / units_per_em.to_dec()

	Stdout.line!("\"${text}\" is ${units.to_str()} font units wide (${units_per_em.to_str()} to the em),")?
	Stdout.line!("which is ${pixels.to_str()} px at ${size.to_str()} px.")?
	Ok({})
}
```

It prints:

```text
"Hello, world!" is 12111 font units wide (2048 to the em),
which is 94.6171875 px at 16 px.
```

[`examples/`](examples/) has more: shaping text into glyphs and clusters,
reading your own font file and reporting what is wrong with it, measuring
a variable font at several weights, turning features such as ligatures on
and off, and right-to-left text.

## Setup

Add the package to your application's header. `{package-url}` stands for
the bundle URL of the release you choose; each release's notes on the
[releases page](https://github.com/lukewilliamboswell/roc-font/releases)
give it in full.

```roc
app [main!] {
	font: "{package-url}",
	# ... your platform
}

import font.Font
```

Use the Roc nightly the release notes name. To use a font of your own, load
its bytes however your platform allows and read them once with
`Font.from_bytes`; reading is the only step that can fail, and it reports
every problem it finds. Every query and every shaping call on a font that
was read succeeds.

The API reference (generated with `roc docs`) and the manual, which covers
the design, conformance testing and the built-in fonts, are attached to
each release.

## What is included

The package carries three variable fonts, ready to use as `Font.sans`,
`Font.serif` and `Font.mono` with no font file:

- **Inter** 4.1, a sans for interfaces and diagrams;
- **Merriweather** 4.009, a serif for running text;
- **Fira Code** 6.2, a monospaced font with programming ligatures.

Each is unmodified and under the SIL Open Font License 1.1. Their exact
bytes (`Font.sans_bytes`, ...) and licences (`Font.sans_licence`, ...) are
available too, for embedding the font you measured with, say, a PDF; keep
the licence with the font when you pass it on. A program that never names a
built-in font carries none of it. See
[THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) for their copyright
notices and provenance.

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md) says what to install and how to run the
checks. The manual in [`docs/`](docs/index.adoc) explains the design and
how roc-font is tested against HarfBuzz, OTS and Chrome.

## Licence

roc-font is under the Universal Permissive License 1.0 ([LICENSE](LICENSE)).
The built-in fonts are under the SIL Open Font License 1.1, as above.
