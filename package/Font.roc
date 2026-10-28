import Face
import Shaper
import TableMetadata
import TableMath
import TableColorImages
import TablePalette
import TableColor
import "fonts/Inter-Variable.ttf" as inter_file : List(U8)
import "fonts/Merriweather-Variable.ttf" as merriweather_file : List(U8)
import "fonts/FiraCode-Variable.ttf" as fira_code_file : List(U8)
import "fonts/Inter-OFL.txt" as inter_licence : Str
import "fonts/Merriweather-OFL.txt" as merriweather_licence : Str
import "fonts/FiraCode-OFL.txt" as fira_code_licence : Str

## A font read from TrueType or OpenType bytes, ready to measure and shape
## text. Read it once with `from_bytes`; every query and every shaping call
## on it then succeeds.
##
## Everything is in font units: integers in the font's own grid of
## `units_per_em` units to the em. Divide by `units_per_em` and multiply by
## the font size for pixels or points; rounding to a device grid is left to
## the caller, because every consumer rounds differently.
##
## Glyph ids are `U32`. Text is a `Str`, and shaping reports which part of
## the text each glyph draws as UTF-8 byte offsets into it (clusters).
##
## Three fonts are built in, ready to use: `sans`, `serif` and `mono`.
## Any other font is read from its bytes with `from_bytes`. The bytes are
## never trusted; `from_bytes` reports everything wrong with a file it
## cannot use.
##
## Where to start:
##
## - How wide is a string? `width` (or `width_planned`, with options).
## - Which glyphs draw it, where? `shape`, which gives a `Run`.
## - Shaping many strings the same way? Make a `plan` once and use
##   `shape_planned`.
## - A font of your own? `from_bytes`, and `describe_problem` for anything
##   wrong with it.
## - Text as UTF-8 bytes (read from a file or the network)? Make it a
##   `Str` with `Str.from_utf8` and shape that: clusters are then offsets
##   into the bytes. Bytes that may not be valid UTF-8 can be decoded by
##   the caller and shaped with `shape_scalars`, each scalar with the
##   byte offset it starts at, so clusters still point into the bytes.
##
## ```
## units = Font.width(Font.sans, "Hello, world!") # 12111
## pixels = (units * 16).to_dec() / Font.units_per_em(Font.sans).to_dec() # 94.6171875 at 16 px
## ```
Font :: { face : Face }.{

	# ------------------------------------------------------------ reading

	## How to read a font file.
	##
	## - `face`: which font of a collection (a `.ttc` file) to read, from 0.
	##   A single font file has only face 0.
	## - `strict`: reject the font for any problem, for a file you will pass
	##   on (embed in a PDF, say) and want to work everywhere. By default
	##   reading is lenient, as browsers are: a font reads exactly when a browser would
	##   draw it. A broken table a browser rejects the font for (including
	##   substitutions, positioning, names, `OS/2` and `post`) rejects it
	##   here too; what a browser leaves out is left out and reported by
	##   `dropped`: a faulty legacy `kern` table, a faulty `avar`, or faulty
	##   variation data, which drops all of the font's variations (it then
	##   reads as its default design).
	## - `limits`: bounds on the work and memory a file may ask for.
	ReadOptions := { face : U32 ?? 0, strict : Bool ?? False, limits : Limits ?? Limits.{} }

	## Bounds on what a font file may ask for. Exceeding one is an
	## `OverLimit` problem naming the field, never a crash.
	##
	## - `max_bytes`: the largest file accepted.
	## - `max_faces`: the most faces a collection may hold.
	## - `max_lookups`: the most substitution or positioning lookups a table
	##   may list; a table with more is left out and reported by `dropped`
	##   (or, when strict, rejects the font).
	## - `max_depth`: how deeply contextual substitution and positioning
	##   lookups may call further lookups while shaping.
	##
	## The defaults (256 MiB, 1024 faces, 16384 lookups, depth 64) admit
	## every real font with room to spare.
	##
	## TrueType outlines also have fixed work and numerical bounds checked
	## while reading. In particular, a conservative coordinate envelope for
	## every composite, including possible variations, must not exceed
	## 2^100 font units before the final phantom-point shift. This leaves
	## room for every intermediate operation to stay finite; exposed path
	## coordinates are bounded by 2^101. Exceeding this fixed envelope is
	## reported as `BadTable` at the glyph's data, rather than clamped.
	Limits := { max_bytes : U64 ?? 268_435_456, max_faces : U32 ?? 1024, max_lookups : U32 ?? 16_384, max_depth : U32 ?? 64 }

	## Why bytes could not be read as a font, or what lenient reading left
	## out.
	##
	## - `NotAFont`: too short, or not a TrueType, OpenType or collection
	##   signature.
	## - `NoSuchFace`: `ReadOptions.face` is not below the collection's face
	##   count.
	## - `OverLimit`: the `Limits` field that was exceeded.
	## - `MissingTable`: a table the font cannot be used without, by its
	##   four-letter tag (`head`, `hhea`, `maxp`, `hmtx` or `cmap`).
	## - `BadTable`: a table by its tag, and the byte offset in the file of
	##   the part that is wrong (a count, an offset or a record that does not
	##   fit, or a value the format does not allow).
	## - `BadUnitsPerEm`: units per em outside 16 to 16384.
	## - `NoUnicodeMapping`: no character map this reader can use (one for
	##   Unicode, a Windows symbol map or a Macintosh map, in format 0, 4, 6,
	##   10, 12 or 13).
	##
	## `describe_problem` puts any of them into words.
	Problem : [
		NotAFont,
		NoSuchFace({ face : U32, count : U32 }),
		OverLimit(Str),
		MissingTable(Str),
		BadTable({ table : Str, offset : U32 }),
		BadUnitsPerEm,
		NoUnicodeMapping,
	]

	## Read a font file. Every independent problem is reported at once.
	##
	## ```
	## font = Font.from_bytes(bytes, Font.ReadOptions.{})?
	## pdf_font = Font.from_bytes(bytes, Font.ReadOptions.{ strict: True })?
	## ```
	##
	## The font measures at `Variation.{}` (Regular weight) until `at` moves
	## it.
	from_bytes : List(U8), ReadOptions -> Try(Font, List(Problem))
	from_bytes = |bytes, options| {
		limits = options.limits
		read = Face.read(bytes, { face: options.face.to_u64(), strict: options.strict, max_bytes: limits.max_bytes, max_faces: limits.max_faces.to_u64(), max_lookups: limits.max_lookups.to_u64(), max_depth: limits.max_depth.to_u64() })
		match read {
			Ok(face) => Ok({ face: Face.moved_to(face, Regular, Normal, FontDefault, []) })
			Err(problems) => Err(problems)
		}
	}

	## How many fonts a file holds: 1 for a single font file, the face count
	## of a collection.
	face_count : List(U8) -> Try(U32, [NotAFont])
	face_count = |bytes|
		match Face.face_count(bytes) {
			Ok(count) => Ok(count.min(0xFFFFFFFF).to_u32_wrap())
			Err(NotAFont) => Err(NotAFont)
		}

	## What lenient reading left out, and why; empty when nothing was left
	## out. A problem in a font's variation data names the table where it
	## was found; all of the font's variations are then left out.
	dropped : Font -> List(Problem)
	dropped = |font| Face.dropped(font.face)

	## A problem in plain English, for a message or a log: what is wrong and
	## where (the table and, for a damaged one, the byte offset in the
	## file).
	##
	## ```
	## match Font.from_bytes(bytes, Font.ReadOptions.{}) {
	##     Ok(font) => ...
	##     Err(problems) => Str.join_with(problems.map(Font.describe_problem), "; ")
	## }
	## ```
	##
	## gives, for example, "the GSUB table is damaged at byte 1234 of the
	## file". Match on `Problem` instead when a program acts on the kind of
	## problem.
	describe_problem : Problem -> Str
	describe_problem = |problem|
		match problem {
			NotAFont => "not a TrueType or OpenType font file"
			NoSuchFace({ face, count }) => "there is no font ${face.to_str()} in a collection of ${count.to_str()} (fonts are numbered from 0)"
			OverLimit(limit) => "the file asks for more than the ${limit} reading limit allows"
			MissingTable(table) => "the ${table} table, which every font needs, is missing"
			BadTable({ table, offset }) => "the ${table} table is damaged at byte ${offset.to_str()} of the file"
			BadUnitsPerEm => "the font's units per em (in the head table) are outside 16 to 16384"
			NoUnicodeMapping => "the font has no character map for Unicode text (cmap table)"
		}

	# ------------------------------------------------------------ facts

	## The font's vertical measures, in font units, at the font's location.
	##
	## - `ascent` and `descent`: the height above and the depth below the
	##   baseline (both positive for ordinary fonts), and `line_gap`, the
	##   extra space between lines, as a browser takes them: the typographic
	##   values when the font asks for them, else the horizontal header's,
	##   else the typographic ones, else the Windows ones (with no line gap).
	## - `cap_height` and `x_height`: the height of capitals and of small
	##   letters. Fonts that do not store them get HarfBuzz's estimates: the
	##   top of `x`, and the top plus the bottom of `O` (half and two thirds
	##   of the em without those letters).
	## - `underline` and `strikeout`: each line's position (its top, from the
	##   baseline, negative below) and thickness. A font without the tables
	##   that store them has no underline (zeros) and, for strikeout,
	##   HarfBuzz's estimate: half the ascent, one eighteenth of the em thick.
	Metrics : {
		ascent : I32,
		descent : I32,
		line_gap : I32,
		cap_height : I32,
		x_height : I32,
		underline : { position : I32, thickness : I32 },
		strikeout : { position : I32, thickness : I32 },
	}

	## The size of the em square in font units.
	units_per_em : Font -> U16
	units_per_em = |font| Face.units_per_em(font.face)

	## The font's vertical measures; see `Metrics`. In a variable font they
	## follow the font's location.
	metrics : Font -> Metrics
	metrics = |font| Face.metrics(font.face, Face.current(font.face))

	## How many glyphs the font has; glyph ids run below this.
	glyph_count : Font -> U32
	glyph_count = |font| Face.glyph_count(font.face).min(0xFFFFFFFF).to_u32_wrap()

	## The glyph that draws a Unicode code point, if the font has one. Fonts
	## whose character map is not in Unicode (old symbol fonts and Macintosh
	## fonts) are translated to Unicode the way HarfBuzz does.
	glyph : Font, U32 -> Try(U32, [Missing])
	glyph = |font, code_point|
		match Face.glyph(font.face, code_point) {
			Ok(g) => Ok(g.to_u32_wrap())
			Err(Missing) => Err(Missing)
		}

	## A glyph's advance width, at the font's location. Uses the font's
	## horizontal metric variations (`HVAR`) when present; otherwise uses
	## the TrueType phantom points moved by `gvar`. A glyph id past the
	## font has an advance of 0.
	advance : Font, U32 -> I32
	advance = |font, id| Face.advance(font.face, Face.current(font.face), id.to_u64())

	## A glyph's vertical pen distance in font units, before choosing the
	## run's direction. Uses vertical metrics when present; otherwise uses
	## the font's ascent plus descent. A glyph id past the font gives zero.
	vertical_advance : Font, U32 -> I32
	vertical_advance = |font, id| Face.vertical_advance(font.face, Face.current(font.face), id.to_u64())

	## Where a glyph's vertical baseline meets its horizontal baseline,
	## in font units. Subtract this origin from a horizontal glyph's drawing
	## position to place it on a vertical baseline. A glyph id past the font
	## gives { x: 0, y: 0 }.
	vertical_origin : Font, U32 -> { x : I32, y : I32 }
	vertical_origin = |font, id| Face.vertical_origin(font.face, Face.current(font.face), id.to_u64())

	## A glyph's bounding box (its ink), in font units, y up from the
	## baseline: from `x_min` to `x_max` across and from `y_min` to `y_max`
	## up. See `extents`.
	Extents : { x_min : I32, y_min : I32, x_max : I32, y_max : I32 }

	## A glyph's bounding box (its ink) at the font's location, in font
	## units, y up from the baseline:
	##
	## - `Extents`: the box. As HarfBuzz gives it, the left edge is the
	##   glyph's left side bearing, and away from a variable font's default
	##   design the box is measured on the outline moved there.
	## - `Empty`: the glyph draws nothing (such as a space, or a glyph whose
	##   outline has no contours), or the glyph id is past the font.
	## - `Unknown`: the font's outlines are in a form roc-font does not
	##   read (CFF or CFF2 outlines, or bitmaps only), so the glyph may draw
	##   something whose box cannot be measured. Fall back on the font's
	##   `metrics` and the glyph's `advance`.
	extents : Font, U32 -> [Extents(Extents), Empty, Unknown]
	extents = |font, id| Face.extents(font.face, id.to_u64())

	## Every code point the font maps to a glyph, in increasing order: what a
	## glyph atlas or a coverage check needs.
	code_points : Font -> List(U32)
	code_points = |font| Face.code_points(font.face)

	## The font's family name (such as `Inter`), in English when the font
	## has it: the typographic family name if present, else the family name.
	family_name : Font -> Try(Str, [Missing])
	family_name = |font| Face.family_name(font.face)

	## A glyph's PostScript name (such as `uni00E9`), if the font has names.
	glyph_name : Font, U32 -> Try(Str, [Missing])
	glyph_name = |font, id| Face.glyph_name(font.face, id.to_u64())

	## The typographic features the font offers, by their four-letter tags
	## (such as `kern`, `liga`, `smcp` or `ss01`), in increasing order
	## without repeats: what a `Feature` can turn on or off in this font.
	## Use it to offer the choices to users, or to check for a feature
	## before relying on it.
	##
	## ```
	## Font.features(Font.mono).contains("calt") # True
	## ```
	##
	## Every feature the font's substitution and positioning tables
	## (`GSUB` and `GPOS`) name is listed, for any script or language, as
	## is `kern` when the font has an old-style `kern` table. Shaping
	## applies some of them by default (see `ShapeOptions`); a font may
	## offer a feature for one script only.
	features : Font -> List(Str)
	features = |font| Face.feature_tags(font.face).map(Shaper.tag_text)

	# ------------------------------------------------------------ variations
	## Font-wide parameters for laying out mathematical expressions. Wide
	## I64 distances preserve variation adjustments without saturation. All
	## distances are in font units; the three fields ending in `percent`
	## or `percent_scale_down` are percentages, not distances.
	MathConstants : {
		script_percent_scale_down : I16,
		script_script_percent_scale_down : I16,
		delimited_sub_formula_min_height : I32,
		display_operator_min_height : I32,
		math_leading : I64,
		axis_height : I64,
		accent_base_height : I64,
		flattened_accent_base_height : I64,
		subscript_shift_down : I64,
		subscript_top_max : I64,
		subscript_baseline_drop_min : I64,
		superscript_shift_up : I64,
		superscript_shift_up_cramped : I64,
		superscript_bottom_min : I64,
		superscript_baseline_drop_max : I64,
		sub_superscript_gap_min : I64,
		superscript_bottom_max_with_subscript : I64,
		space_after_script : I64,
		upper_limit_gap_min : I64,
		upper_limit_baseline_rise_min : I64,
		lower_limit_gap_min : I64,
		lower_limit_baseline_drop_min : I64,
		stack_top_shift_up : I64,
		stack_top_display_style_shift_up : I64,
		stack_bottom_shift_down : I64,
		stack_bottom_display_style_shift_down : I64,
		stack_gap_min : I64,
		stack_display_style_gap_min : I64,
		stretch_stack_top_shift_up : I64,
		stretch_stack_bottom_shift_down : I64,
		stretch_stack_gap_above_min : I64,
		stretch_stack_gap_below_min : I64,
		fraction_numerator_shift_up : I64,
		fraction_numerator_display_style_shift_up : I64,
		fraction_denominator_shift_down : I64,
		fraction_denominator_display_style_shift_down : I64,
		fraction_numerator_gap_min : I64,
		fraction_num_display_style_gap_min : I64,
		fraction_rule_thickness : I64,
		fraction_denominator_gap_min : I64,
		fraction_denom_display_style_gap_min : I64,
		skewed_fraction_horizontal_gap : I64,
		skewed_fraction_vertical_gap : I64,
		overbar_vertical_gap : I64,
		overbar_rule_thickness : I64,
		overbar_extra_ascender : I64,
		underbar_vertical_gap : I64,
		underbar_rule_thickness : I64,
		underbar_extra_descender : I64,
		radical_vertical_gap : I64,
		radical_display_style_vertical_gap : I64,
		radical_rule_thickness : I64,
		radical_extra_ascender : I64,
		radical_kern_before_degree : I64,
		radical_kern_after_degree : I64,
		radical_degree_bottom_raise_percent : I16,
	}

	## Which corner of a glyph a mathematical script is placed against.
	MathCorner : [TopRight, TopLeft, BottomRight, BottomLeft]

	## The direction in which a mathematical symbol is stretched. This is
	## independent of the direction of a shaped text run.
	MathDirection : [Horizontal, Vertical]

	## A prebuilt mathematical symbol and its size along the stretch axis.
	MathVariant : { glyph : U32, advance : I32 }

	## One component of a stretchable symbol. Connector lengths and full
	## advance are in font units. Extenders may be repeated by the caller's
	## bounded equation layout algorithm.
	MathPart : { glyph : U32, start_connector : I32, end_connector : I32, full_advance : I32, extender : Bool }

	## A stretchable symbol's construction recipe, in table order, and its
	## italic correction. Equation layout chooses repeats and overlaps.
	MathAssembly : { italic_correction : I64, parts : List(MathPart) }

	## Height thresholds and corner kern values, in font units. There is
	## one more value than threshold; `math_kern` selects the value at a
	## correction height without requiring callers to search this list.
	MathKernTable : { heights : List(I64), values : List(I64) }

	## Whether the font supplies mathematical typesetting data (`MATH`).
	## A damaged optional MATH table is left out and reported by `dropped`
	## in lenient reading, and rejects the font in strict reading.
	has_math : Font -> Bool
	has_math = |font| TableMath.has_data(font.face.math)

	## Font parameters for equation layout at the selected variation
	## location, or `Absent` without mathematical typesetting data.
	## This supplies font facts; it does not lay out mathematical expressions.
	math_constants : Font -> [Present(MathConstants), Absent]
	math_constants = |font| TableMath.constants(font.face.math)

	## The stored italic correction for a mathematical glyph, in font
	## units, or `Absent` when no correction is stored. A layout engine
	## commonly uses zero for absence; no fallback is invented here.
	math_italic_correction : Font, U32 -> [Present(I64), Absent]
	math_italic_correction = |font, id| TableMath.italic_correction(font.face.math, id)

	## The stored horizontal position for centering an accent over a glyph,
	## in font units, or `Absent`. A layout engine may fall back to half
	## the advance; the query preserves absence for callers choosing policy.
	math_top_accent_attachment : Font, U32 -> [Present(I64), Absent]
	math_top_accent_attachment = |font, id| TableMath.top_accent_attachment(font.face.math, id)

	## Whether the font marks a glyph as an extended mathematical shape.
	math_extended_shape : Font, U32 -> Bool
	math_extended_shape = |font, id| TableMath.extended_shape(font.face.math, id)

	## Corner kerning at a correction height, in font units, at the selected
	## variation location. Missing corner data gives the format's zero value.
	## Mathematical kerning is distinct from ordinary text pair kerning.
	math_kern : Font, U32, MathCorner, I64 -> I64
	math_kern = |font, id, corner, height| TableMath.kern(font.face.math, id, corner, height)

	## The stored corner-kerning thresholds and values at the selected
	## location; absent data gives empty lists. Use `math_kern` to query a
	## single correction height.
	math_kern_table : Font, U32, MathCorner -> MathKernTable
	math_kern_table = |font, id, corner| TableMath.kern_table(font.face.math, id, corner)

	## Prebuilt sizes of a mathematical glyph in the font's table order.
	## Missing constructions and glyphs past the font give an empty list.
	math_variants : Font, U32, MathDirection -> List(MathVariant)
	math_variants = |font, id, direction| TableMath.variants(font.face.math, id, direction)

	## Component recipe for stretching a mathematical symbol, or `Absent`.
	## The caller lays out these parts; no repeated output is allocated here.
	math_assembly : Font, U32, MathDirection -> [Present(MathAssembly), Absent]
	math_assembly = |font, id, direction| TableMath.assembly(font.face.math, id, direction)

	## The font's minimum overlap between connectors of mathematical symbol
	## parts, in font units; zero without mathematical typesetting data.
	math_min_connector_overlap : Font -> I32
	math_min_connector_overlap = |font| TableMath.min_connector_overlap(font.face.math)

	## One unpremultiplied sRGB color from a font palette. Every channel,
	## including alpha, is an unsigned byte. Transparent colors retain the
	## font's original RGB values.
	Color : { red : U8, green : U8, blue : U8, alpha : U8 }

	## An ordered color palette. Background flags express the font's
	## preferences; both false means no preference was supplied.
	ColorPalette : { colors : List(Color), light_background : Bool, dark_background : Bool }

	## Every color palette in font order; palette zero is the format's
	## default. Entries at the same index in each palette color the same
	## artwork. Fonts without palettes give an empty list.
	color_palettes : Font -> List(ColorPalette)
	color_palettes = |font| TablePalette.palettes(font.face.palettes).map(
		|palette| {
			colors: match TablePalette.colors(font.face.palettes, palette.index) {
				Present(colors) => colors
				Absent => []
			},
			light_background: palette.light_background,
			dark_background: palette.dark_background,
		},
	)

	## One palette entry without listing the rest of the palette. An index
	## past either the palettes or their entries gives `Absent`.
	color_palette_color : Font, U32, U32 -> [Present(Color), Absent]
	color_palette_color = |font, palette, entry| TablePalette.color(font.face.palettes, palette, entry)

	## The font's display name for a palette, chosen in English when
	## available; `Missing` means that no usable name was supplied.
	color_palette_name : Font, U32 -> Try(Str, [Missing])
	color_palette_name = |font, index| match TablePalette.palette_name_id(font.face.palettes, index) {
		Present(id) => Face.name(font.face, id)
		Absent => Err(Missing)
	}

	## A display name for a color entry, shared by that index in every
	## palette. Missing labels and indices past the entries give `Missing`.
	color_entry_name : Font, U32 -> Try(Str, [Missing])
	color_entry_name = |font, index| match TablePalette.entry_name_id(font.face.palettes, index) {
		Present(id) => Face.name(font.face, id)
		Absent => Err(Missing)
	}

	## A palette entry or the caller's foreground color.
	ColorSource : [PaletteEntry(U16), Foreground]

	## One ordered outline layer of COLR version 0 artwork.
	ColorLayer : { glyph : U32, color : ColorSource }

	## A position in font units.
	ColorPoint : { x : F64, y : F64 }

	## A clipping rectangle in font units.
	ColorRect : { x_min : F64, y_min : F64, x_max : F64, y_max : F64 }

	## A checked contiguous span in the graph's edges or stops pool.
	ColorSpan : { start : U64, len : U64 }

	## A gradient stop: offset and alpha are fractions, color remains unresolved.
	ColorStop : { offset : F64, color : ColorSource, alpha : F64 }

	## How a gradient extends beyond its first and last stops.
	ColorExtend : [Pad, Repeat, Reflect]

	## The compositing operation defined by the font.
	ColorMode : [Clear, Source, Destination, SourceOver, DestinationOver, SourceIn, DestinationIn, SourceOut, DestinationOut, SourceAtop, DestinationAtop, Xor, Plus, Screen, Overlay, Darken, Lighten, ColorDodge, ColorBurn, HardLight, SoftLight, Difference, Exclusion, Multiply, HslHue, HslSaturation, HslColor, HslLuminosity]

	## A transform in font units; angles are degrees. Consumers apply the transform.
	ColorOperation : [
		Affine({ xx : F64, yx : F64, xy : F64, yy : F64, dx : F64, dy : F64 }),
		Translate(ColorPoint),
		Scale({ x : F64, y : F64, center : ColorPoint }),
		Rotate({ degrees : F64, center : ColorPoint }),
		Skew({ x_degrees : F64, y_degrees : F64, center : ColorPoint }),
	]

	## One paint node; child references index the graph's nodes. Layers index edges; gradients index stops.
	ColorPaint : [
		Layers(ColorSpan),
		Solid({ color : ColorSource, alpha : F64 }),
		LinearGradient({ stops : ColorSpan, extend : ColorExtend, p0 : ColorPoint, p1 : ColorPoint, p2 : ColorPoint }),
		RadialGradient({ stops : ColorSpan, extend : ColorExtend, c0 : ColorPoint, radius0 : F64, c1 : ColorPoint, radius1 : F64 }),
		SweepGradient({ stops : ColorSpan, extend : ColorExtend, center : ColorPoint, start_degrees : F64, end_degrees : F64 }),
		Glyph({ glyph : U32, paint : U32 }),
		ColorGlyph({ glyph : U32, paint : U32, clip : [Present(ColorRect), Absent] }),
		Transform({ paint : U32, operation : ColorOperation }),
		Composite({ source : U32, backdrop : U32, mode : ColorMode }),
	]

	## A flat paint graph. Start at root; edges and stops are shared pools. The optional clip applies to the whole graph.
	ColorGlyph : { root : U32, nodes : List(ColorPaint), edges : List(U32), stops : List(ColorStop), clip : [Present(ColorRect), Absent] }

	## Ordered outline layers for a glyph with COLR version 0 artwork.
	## Resolve each color using a palette or the caller's foreground, then
	## obtain its outline with `outline`. Other glyphs return an empty list.
	color_layers : Font, U32 -> List(ColorLayer)
	color_layers = |font, id| TableColor.layers(font.face.color, id)

	## Paint instructions for a color glyph at the font's current variation
	## location. Includes COLR version 0 layers and version 1 gradients,
	## transforms, clipping and composition. Colors remain palette references;
	## rendering these instructions belongs to the consumer. Missing artwork
	## gives `Absent`. All coordinates remain in font units.
	color_glyph : Font, U32 -> [Present(ColorGlyph), Absent]
	color_glyph = |font, id| TableColor.graph(font.face.color, id)

	## Encoding of an embedded SVG document. The bytes remain encoded;
	## callers decode UTF-8/XML or gzip using their own image pipeline.
	SvgEncoding : [Utf8, Gzip]

	## An encoded SVG glyph document, which can describe a range of glyphs.
	## Document coordinates use the font's em space. Payloads are returned
	## unchanged; roc-font validates their container, not XML or image data.
	SvgDocument : { bytes : List(U8), encoding : SvgEncoding, first_glyph : U32, last_glyph : U32 }

	## Embedded SVG artwork for a glyph, or `Absent`. Use the document's
	## glyph elements when one document supplies several glyphs. No artwork
	## is synthesized from outlines or another color format.
	svg_glyph : Font, U32 -> [Present(SvgDocument), Absent]
	svg_glyph = |font, id| TableColorImages.svg(font.face.svg_images, id.to_u64())

	## Native strike-pixel placement and advance for an embedded bitmap.
	## These values are pixels at that strike's ppem, unlike outline and
	## shaping coordinates, which are font units.
	BitmapBearingAdvance : { bearing_x : I16, bearing_y : I16, advance : U16 }

	## Font-stored line metrics of a bitmap strike, in native strike pixels.
	BitmapLineMetrics : { ascender : I16, descender : I16, width_max : U8, caret_slope_numerator : I16, caret_slope_denominator : I16, caret_offset : I16, min_origin_side_bearing : I16, min_advance_side_bearing : I16, max_before_baseline : I16, min_after_baseline : I16 }

	## A bitmap size offered by the font. `Sbix` is a self-contained image
	## strike with a ppem and device density; `ColorBitmap` supplies separate
	## horizontal and vertical metrics through the CBDT/CBLC tables.
	## The flags and bit depth describe the stored image format.
	BitmapStrike : [Sbix({ ppem : U16, ppi : U16, draw_outlines : Bool }), ColorBitmap({ ppem_x : U8, ppem_y : U8, bit_depth : U8, flags : U8, first_glyph : U32, last_glyph : U32, horizontal : BitmapLineMetrics, vertical : BitmapLineMetrics })]

	## Every embedded bitmap strike: sbix strikes first, then CBDT/CBLC
	## strikes, each in its own table order. The index selects that exact
	## entry in `bitmap_glyph`; choosing a size is the consumer's policy.
	bitmap_strikes : Font -> List(BitmapStrike)
	bitmap_strikes = |font| TableColorImages.strikes(font.face.sbix_images).concat(TableColorImages.strikes(font.face.cbdt_images))

	## Encoding of the original bitmap payload. `Other` preserves an
	## unrecognized four-byte graphics tag as a big-endian number.
	BitmapFormat : [Png, Jpeg, Tiff, Pdf, Mask, Other(U32)]

	## Native pixel dimensions and placement stored with a CBDT bitmap.
	BitmapMetrics : { width : U8, height : U8, horizontal : [Present(BitmapBearingAdvance), Absent], vertical : [Present(BitmapBearingAdvance), Absent] }

	## Bitmap placement in its native strike pixels. A resolved sbix
	## duplicate identifies the source glyph whose image and origin it uses.
	BitmapPlacement : [Sbix({ origin_x : I16, origin_y : I16, source_glyph : U32 }), Bitmap(BitmapMetrics)]

	## Encoded bitmap bytes and their stored placement. Image decoding and
	## rendering belong to the consumer; malformed encoded image content
	## is not repaired or rasterized by this font-container reader.
	BitmapImage : { format : BitmapFormat, bytes : List(U8), placement : BitmapPlacement }

	## Artwork for one glyph at exactly the selected `bitmap_strikes`
	## index. Missing glyphs, unavailable strikes and absent images give
	## `Absent`; no size selection, rescaling or cross-format fallback occurs.
	bitmap_glyph : Font, U32, U32 -> [Present(BitmapImage), Absent]
	bitmap_glyph = |font, id, strike| {
		first_count = font.face.sbix_images.strike_records.len()
		index = strike.to_u64()
		if index < first_count {
			TableColorImages.bitmap(font.face.sbix_images, index, id.to_u64())
		} else {
			TableColorImages.bitmap(font.face.cbdt_images, index - first_count, id.to_u64())
		}
	}

	## One point of a glyph path, in fractional font units. Composite
	## transforms and variations are evaluated without hinting or rounding
	## to pixels; their binary32 coordinates are widened exactly to F64.
	OutlinePoint : { x : F64, y : F64 }

	## A glyph path in drawing order. Quadratic curves are used by TrueType;
	## cubic commands allow consumers to share a path vocabulary. A new
	## contour starts with `MoveTo` and ends with `Close`.
	OutlineCommand : [MoveTo(OutlinePoint), LineTo(OutlinePoint), QuadraticTo({ control : OutlinePoint, end : OutlinePoint }), CubicTo({ control1 : OutlinePoint, control2 : OutlinePoint, end : OutlinePoint }), Close]

	## The glyph's outline at the current variation location, for vector
	## output or a caller's renderer. An empty glyph or an id past the font
	## gives `Outline([])`. `Unknown` means the font uses outlines this
	## reader cannot expose, such as CFF/CFF2 or bitmap-only glyphs.
	outline : Font, U32 -> [Outline(List(OutlineCommand)), Unknown]
	outline = |font, id| Face.outline(font.face, id.to_u64())

	## One font-defined horizontal caret within a ligature, in font units,
	## or `Unavailable` when it refers to an outline point this reader
	## cannot expose. Coordinates retain fractional component transforms.
	LigatureCaret : [Position(F64), Unavailable]

	## Font-defined caret positions within a ligature, in table order,
	## at the current variation location. Missing glyphs and glyphs without
	## stored carets give `[]`; no equally spaced carets are invented.
	## Pixel device adjustments add nothing at the font-unit boundary.
	ligature_carets : Font, U32 -> List(LigatureCaret)
	ligature_carets = |font, id| Face.ligature_carets(font.face, id.to_u64())

	## Original bytes of a font table, selected by its four-byte tag (such
	## as "head" or "glyf"), for embedding and subsetting tools. Missing
	## tables and tags of any other byte length return `Absent`.
	## These are the caller's original bytes, including optional tables
	## reported by `dropped`; they are not a sanitized or rewritten font.
	table_bytes : Font, Str -> [Present(List(U8)), Absent]
	table_bytes = |font, tag| TableMetadata.table(font.face.metadata, tag)

	## One original table directory entry. `tag` is its four bytes as an
	## unsigned big-endian number. Offsets are from the start of the caller's
	## file, including when reading a face of a collection.
	TableEntry : { tag : U32, offset : U32, length : U32 }

	## Original table directory entries in file order. Useful when copying
	## font data into a document or writing a subset.
	tables : Font -> List(TableEntry)
	tables = |font| TableMetadata.directory(font.face.metadata)

	## The font's full name (name ID 4), chosen in English when available
	## using the same deterministic preference as `family_name`.
	full_name : Font -> Try(Str, [Missing])
	full_name = |font| Face.name(font.face, 4)

	## The font's PostScript name (name ID 6), for identifying an embedded
	## font in a document. `Missing` means no usable name was supplied.
	postscript_name : Font -> Try(Str, [Missing])
	postscript_name = |font| Face.name(font.face, 6)

	## The legacy family name (name ID 1), without the typographic-family
	## preference of `family_name`, for document formats that require it.
	legacy_family_name : Font -> Try(Str, [Missing])
	legacy_family_name = |font| Face.name(font.face, 1)

	## The original OS/2 embedding flags (`fsType`), or `Absent` when that
	## table is missing. These are facts for a document writer's embedding
	## policy; roc-font does not decide whether a consumer may embed a font.
	embedding_flags : Font -> [Present(U16), Absent]
	embedding_flags = |font| TableMetadata.embedding_flags(font.face.metadata)

	## A glyph's original left side bearing from `hmtx`, in font units,
	## independent of the selected variation location. Glyphs past the font
	## return `Absent`. After the long metrics the format stores one bearing
	## per glyph, even though those glyphs share their last advance width.
	stored_left_side_bearing : Font, U32 -> [Present(I32), Absent]
	stored_left_side_bearing = |font, id| TableMetadata.left_side_bearing(font.face.metadata, id.to_u64())

	## The font-wide box stored in `head`, in font units at the original
	## design. This is a stored font descriptor, not the ink box at the
	## location chosen with `at`; use `extents` for individual glyph ink.
	stored_bounds : Font -> Extents
	stored_bounds = |font| TableMetadata.bounds(font.face.metadata)

	## The original horizontal-header line metrics (`hhea`), in font units.
	## Descent retains the stored sign, normally negative. Unlike `metrics`,
	## these values are not selected from OS/2 or varied with the font.
	HeaderMetrics : { ascent : I32, descent : I32, line_gap : I32 }

	## Stored horizontal-header metrics for document font descriptors.
	stored_header_metrics : Font -> HeaderMetrics
	stored_header_metrics = |font| { ascent: font.face.hhea.ascent, descent: font.face.hhea.descent, line_gap: font.face.hhea.line_gap }

	## Where to measure a variable font: its weight, width and optical size,
	## and any other axis by its tag.
	##
	## - `weight` and `width` follow CSS (`font-weight`, `font-stretch`).
	## - `optical_size`: the font's own default, or `Size(px)` for text drawn
	##   at that size, as a browser sets it.
	## - `axes`: values for any axis, such as `{ tag: "GRAD", value: 50 }`.
	##   They apply after the named fields and override them, like CSS
	##   `font-variation-settings`; a later entry for one tag wins. A tag
	##   that is not four bytes, or that the font lacks, is ignored.
	##
	## The default, `Variation.{}`, is Regular weight and Normal width at
	## the font's own optical size: what a browser draws for text with no
	## weight or width set, and where every font starts. Values outside an
	## axis's range are clamped to it, as the format defines. Named fields
	## apply only to axes the font has, and a font without variations
	## ignores them all.
	Variation := { weight : Weight ?? Regular, width : Width ?? Normal, optical_size : OpticalSize ?? FontDefault, axes : List({ tag : Str, value : Dec }) ?? [] }

	## CSS weights: `Thin` is 100, `Regular` 400, `Bold` 700, `Black` 900,
	## or any value from 1 to 1000.
	Weight : [Thin, ExtraLight, Light, Regular, Medium, SemiBold, Bold, ExtraBold, Black, Weight(U16)]

	## CSS widths, as a percentage of normal: `UltraCondensed` is 50,
	## `ExtraCondensed` 62.5, `Condensed` 75, `SemiCondensed` 87.5, `Normal`
	## 100, `SemiExpanded` 112.5, `Expanded` 125, `ExtraExpanded` 150 and
	## `UltraExpanded` 200.
	Width : [UltraCondensed, ExtraCondensed, Condensed, SemiCondensed, Normal, SemiExpanded, Expanded, ExtraExpanded, UltraExpanded, Percent(Dec)]

	## The font's own default optical size, or the size in CSS pixels the
	## text is drawn at.
	OpticalSize : [FontDefault, Size(Dec)]

	## One axis of a variable font: its four-letter tag (such as `wght`) and
	## its range in the axis's own units.
	Axis : { tag : Str, min : Dec, default : Dec, max : Dec }

	## The font at another point of its variation space. Every query and
	## shaping call on the result measures there: advances, metrics, glyph
	## boxes and kerning vary. Cheap: the font's tables are shared.
	##
	## ```
	## bold = Font.at(font, Font.Variation.{ weight: Bold })
	## ```
	##
	## A font is read at `Variation.{}`, as a browser draws it. To measure
	## the font's own default design instead (what a PDF embeds), give every
	## axis its default:
	##
	## ```
	## design = Font.at(font, Font.Variation.{ axes: Font.axes(font).map(|axis| { tag: axis.tag, value: axis.default }) })
	## ```
	at : Font, Variation -> Font
	at = |font, variation| { face: Face.moved_to(font.face, variation.weight, variation.width, variation.optical_size, variation.axes) }

	## The axes of a variable font, in the font's order; empty for a static
	## font.
	axes : Font -> List(Axis)
	axes = |font| Face.axes(font.face)

	## The designs a variable font names (such as `Bold` or `Condensed
	## Light`), in the font's order, each with its value on every axis;
	## empty for a static font. Move to one with
	## `Font.at(font, Font.Variation.{ axes: instance.axes })`. The name is
	## empty when the font does not store it.
	instances : Font -> List({ name : Str, axes : List({ tag : Str, value : Dec }) })
	instances = |font| Face.instances(font.face)

	## Where `at` put the font, as each axis's normalised coordinate in
	## units of 1/16384: -16384 at the axis minimum, 0 at its default and
	## 16384 at its maximum, after the font's own remapping (`avar`). In the
	## font's axis order; empty for a static font. These are the numbers
	## HarfBuzz reports as the normalised coordinates.
	coordinates : Font -> List({ tag : Str, value : I16 })
	coordinates = |font| {
		coords = Face.coords(font.face)
		Face.axes(font.face).map_with_index(|a, i| { tag: a.tag, value: coords.get(i) ?? 0 })
	}

	# ------------------------------------------------------------ shaping

	## Which way text runs. `FromScript` (the default) takes the script's
	## own direction (right to left for Arabic and Hebrew, for example; left
	## to right for an empty script). `TopToBottom` and `BottomToTop` select
	## vertical glyph forms, metrics and positioning. Vertical advances use
	## negative y font units; bottom-to-top reverses the glyph order.
	Direction : [FromScript, LeftToRight, RightToLeft, TopToBottom, BottomToTop]

	## How characters group into clusters, the parts of the text a run's
	## glyphs say they draw.
	##
	## - `Graphemes` (the default): what a reader sees as one character
	##   stays together. A character that extends a grapheme (a combining
	##   mark, an emoji modifier, a zero-width joiner and the pictograph
	##   after it, a variation selector) takes the cluster of the grapheme's
	##   first character. Suits measuring, cursor movement and line
	##   breaking.
	## - `Characters`: each character keeps its own cluster, and the run is
	##   unsafe to break inside a grapheme. Suits mapping glyphs back to
	##   single characters.
	##
	## Either way, glyphs that draw several characters together (ligatures)
	## share the first character's cluster. These are HarfBuzz's monotone
	## cluster levels 0 and 1.
	ClusterLevel : [Graphemes, Characters]

	## A typographic feature, turned on (value 1, the default), off (0) or to
	## a value, over the whole text or over the characters whose cluster
	## offsets lie in `start ..< end` (UTF-8 byte offsets for `shape`; the
	## given offsets for `shape_scalars`). The default range is the whole
	## text: `end` defaults to the largest `U64`, past every offset.
	##
	## ```
	## no_ligatures = Font.Feature.{ tag: "liga", value: 0 }
	## small_caps = Font.Feature.{ tag: "smcp", start: 4, end: 9 }
	## ```
	##
	## The tag is the feature's four-letter OpenType name; `features` lists
	## those a font offers, and a tag it does not offer changes nothing. A
	## value above 1 chooses that alternate where the feature offers
	## several (`salt` with value 2 is the second).
	Feature := { tag : Str, value : U32 ?? 1, start : U64 ?? 0, end : U64 ?? 18_446_744_073_709_551_615 }

	## Bounds on shaping work, per input character, never below 65536 in
	## all. `growth` bounds output glyphs (256 per character by default).
	## `operations` bounds contextual lookup calls, script preprocessing,
	## reordering and feature probes, and contextual positioning (4096 per
	## character by default). The factors follow HarfBuzz's shaping budgets.
	## Past a bound, the operation stops at a complete mutation boundary.
	## Shaping returns the partial run, retaining the input text's glyphs;
	## `shape_checked` also reports which bounds stopped work (see `Budget`).
	ShapeLimits := { growth : U32 ?? 256, operations : U32 ?? 4096 }

	## How to shape.
	##
	## - `script`: the text's ISO 15924 script code, such as `Latn`, `Grek`,
	##   `Cyrl` or `Arab`. Empty is Latin, as a browser shapes text whose
	##   script it is not told. roc-font does not detect scripts; split text
	##   into runs of one script (with the `unicode` package) first.
	## - `language`: a BCP 47 language tag, such as `en`, `tr` or `sr-Latn`,
	##   which can select the font's language-specific forms. Empty is none.
	##   `-x-hbot` and `-x-hbsc` private-use subtags give raw OpenType
	##   language and script tags, as in HarfBuzz.
	## - `direction`, `features`, `clusters` and `limits`: see their types.
	##   The browser defaults for the direction always apply (ligatures,
	##   contextual forms and kerning, among others) unless a `Feature`
	##   turns one off; `features` lists only the changes.
	##
	## Characters compose or decompose to what the font maps, brackets
	## mirror in right-to-left text, default-ignorable characters draw with
	## no width, and missing spaces take widths from the font's space.
	## Substitution and positioning follow the font's selected features,
	## including cursive and mark attachment and contextual positioning.
	## Dedicated script stages handle Arabic/Syriac joining, Hebrew mark order,
	## Thai/Lao Sara Am, Khmer, Myanmar, and Hangul syllables, Jamo forms and tone
	## marks. Indic syllable reordering covers Devanagari, Bengali, Gurmukhi,
	## Gujarati, Odia, Tamil, Telugu, Kannada and Malayalam when the font's
	## script data selects that model. The Universal Shaping Engine handles
	## its script-specific syllables and joining, including Tibetan, Sinhala,
	## NKo, Adlam and Mongolian. Arabic presentation-form fallback and Syriac
	## stretching apply when selected by the font and script.
	## Other scripts use the default shaping model, which applies the
	## font's lookups without script-specific syllable reordering.
	ShapeOptions := { script : Str ?? "", language : Str ?? "", direction : Direction ?? FromScript, features : List(Feature) ?? [], clusters : ClusterLevel ?? Graphemes, limits : ShapeLimits ?? ShapeLimits.{} }

	## A shaped run, one entry per glyph in each list, in visual order (left
	## to right, also for right-to-left text):
	##
	## - `glyphs`: glyph ids;
	## - `advances`: how far each glyph moves the pen, in font units;
	## - `offsets`: where to draw each glyph relative to the pen;
	## - `clusters`: the UTF-8 byte offset in the text of the first character
	##   each glyph draws (for `shape_scalars`, the offset given with it),
	##   never clamped;
	## - `flags`: facts about each glyph, read with `is_unsafe_to_break`
	##   (bit 0: breaking the text at the start of the glyph's cluster would
	##   change the glyphs on either side, so both sides must be shaped
	##   again) and `is_missing` (bit 1: glyph 0 drawn for a character the
	##   font does not map, where a browser would fall back to another font).
	##
	## Positions use signed 32-bit font units. GPOS adjustments saturate
	## each addition and subtraction at that range, before later corrections.
	## Anchor conversions outside the range are held at its limits.
	## `cluster_ranges` gives the part of the text each glyph draws.
	##
	## What every run guarantees (for `shape_scalars`, when the offsets
	## given increase):
	##
	## - Clusters never decrease from glyph to glyph in a left-to-right run
	##   and never increase in a right-to-left one, and the glyphs of one
	##   cluster are adjacent. A cluster's glyphs draw the characters from
	##   its offset up to the next larger cluster offset (or the end of the
	##   text), so slicing the text at cluster offsets never splits what a
	##   glyph draws.
	## - Every cluster is the offset of a character of the text. A character
	##   with no glyph of its own (joined into a ligature, or removed by a
	##   substitution) is drawn by the cluster it was merged into.
	## - A character the font does not map is drawn with glyph 0, never left
	##   out, and the glyph is missing (`is_missing`); only a substitution in the font
	##   may replace that glyph. The exceptions are default-ignorable
	##   characters (such as a zero-width joiner, a soft hyphen or a
	##   variation selector), which draw nothing visible: the font's space
	##   glyph with no advance, or no glyph when the font has no space. A
	##   glyph 0 the font itself gives (by its character map or a
	##   substitution) is not missing.
	## - Empty text gives a run of empty lists; glyph ids past the font have
	##   an advance of 0.
	Run : { glyphs : List(U32), advances : List({ x : I32, y : I32 }), offsets : List({ x : I32, y : I32 }), clusters : List(U64), flags : List(U8) }

	## Which substitution produced a glyph of a run shaped by
	## `shape_traced`, for callers that must map glyphs back to the text
	## exactly, such as a PDF writer recording what a ligature stands for.
	##
	## - `Mapped`: the font's character map gave the glyph (after composing
	##   or decomposing characters to what the font maps) and no
	##   substitution changed it.
	## - `Substituted`: one glyph replaced by another (an alternate, a small
	##   capital, a contextual form).
	## - `Ligature`: one glyph that joined `components` glyphs, each a
	##   character's glyph or an earlier ligature counting as one; the text
	##   it draws is its cluster's.
	## - `Multiple`: the first of several glyphs that replaced one glyph; it
	##   stands for the replaced glyph's characters.
	## - `Inserted`: a further glyph of such a replacement; it stands for no
	##   character of its own and shares the first glyph's cluster.
	##
	## `feature` is the four-letter tag (such as `liga`, `smcp` or `ccmp`)
	## of the feature whose substitution step made the glyph's last
	## substitution. A substitution made by a contextual rule is credited to
	## the feature whose rule it is (`calt` for a contextual alternate),
	## even when the rule calls on substitutions that features do not list
	## themselves. A one-for-one substitution of a ligature or of a glyph of
	## a multiple substitution keeps its kind (the glyph still draws the
	## same characters) and takes the later feature.
	##
	## Fonts often list one substitution under several features (`liga`
	## and `clig` listing the same ligatures, say). It is credited to one of
	## them that is on for the glyph: `liga` first, then the other features
	## shaping applies by default (such as `clig`, `calt` or `ccmp`), then
	## features the options turned on, each group in tag order. So a
	## ligature is reported as `liga` whenever `liga` lists it and is on.
	##
	## An origin names a kind and a feature only: it carries no lookup
	## index and no input glyphs. The characters a glyph stands for are
	## its cluster's (see `cluster_ranges`), and `components` counts what a
	## ligature joined.
	GlyphOrigin : [Mapped, Substituted({ feature : Str }), Ligature({ feature : Str, components : U32 }), Multiple({ feature : Str }), Inserted({ feature : Str })]

	## A bound that stopped shaping before it finished: `Growth` and
	## `Operations` are the `ShapeLimits` fields, and `Depth` is
	## `Limits.max_depth`, how deeply contextual lookups may call further
	## lookups (a reading option, because it guards the
	## work a font file may ask for).
	Budget : [Growth, Operations, Depth]

	## The choices `ShapeOptions` make for one font, worked out once. Plan
	## once and shape many times with `shape_planned`. A plan belongs to the
	## font it was made for; with another font the run is defined but
	## meaningless.
	ShapePlan :: { plan : Shaper.Plan }

	## Work out a plan for shaping with these options, to shape or measure
	## many strings the same way (`shape_planned`, `width_planned` and the
	## others that take a plan) without working out the options each time.
	##
	## ```
	## plan = Font.plan(font, Font.ShapeOptions.{ script: "Grek", language: "el" })
	## runs = lines.map(|line| Font.shape_planned(font, plan, line))
	## ```
	plan : Font, ShapeOptions -> ShapePlan
	plan = |font, options| {
		limits = options.limits
		chosen = options.features.map(|f| { tag: f.tag, value: f.value, start: f.start, end: f.end })
		{ plan: Shaper.plan_with_clusters(font.face, { script: options.script, language: options.language, direction: options.direction, features: chosen, growth: limits.growth.to_u64(), operations: limits.operations.to_u64() }, options.clusters) }
	}

	## Shape text: the glyphs that draw it, where, and which part of the
	## text each draws. Use it to draw text, or to map between glyphs and
	## text (a cursor, a selection, a line break); for a width alone,
	## `width` is shorter.
	##
	## ```
	## run = Font.shape(font, "office -> home", Font.ShapeOptions.{})
	## ```
	shape : Font, Str, ShapeOptions -> Run
	shape = |font, text, options| Font.shape_planned(font, Font.plan(font, options), text)

	## Shape text with a plan made by `plan`: the run `shape` gives for the
	## plan's options.
	shape_planned : Font, ShapePlan, Str -> Run
	shape_planned = |font, shape_plan, text| Shaper.shape(font.face, Face.current(font.face), shape_plan.plan, Shaper.decode(text))

	## Shape text with a plan, and say whether shaping finished. `Ok` holds
	## the run `shape_planned` gives. When a bound stopped substitution
	## early, the result is `OverBudget` with the run made so far (total
	## and finite, still drawing the whole text) and every bound that
	## stopped it; raise those bounds (`ShapeLimits` in the plan's options,
	## `Limits.max_depth` when reading) to shape further. On a real font
	## the defaults never bind, so this matters where fonts come from
	## untrusted sources.
	##
	## ```
	## match Font.shape_checked(font, plan, text) {
	##     Ok(run) => run
	##     Err(OverBudget({ run, budgets })) => ...
	## }
	## ```
	shape_checked : Font, ShapePlan, Str -> Try(Run, [OverBudget({ run : Run, budgets : List(Budget) })])
	shape_checked = |font, shape_plan, text| {
		shaped = Shaper.shape_items(font.face, Face.current(font.face), shape_plan.plan, Shaper.decode(text))
		if shaped.stopped == 0 {
			Ok(shaped.run)
		} else {
			Err(OverBudget({ run: shaped.run, budgets: Shaper.budgets(shaped.stopped) }))
		}
	}

	## Shape characters a paragraph layer has already split up (by script,
	## direction or font): each Unicode scalar value with the offset to
	## report as its cluster (normally its UTF-8 byte offset in the
	## paragraph), so runs of one paragraph report offsets into it. It also
	## shapes text a caller decoded itself, such as UTF-8 bytes that may be
	## invalid, with clusters pointing into the bytes.
	## Scalars sharing an offset form one cluster. Clusters in the run are
	## these offsets, unchanged.
	shape_scalars : Font, ShapePlan, List({ scalar : U32, offset : U64 }) -> Run
	shape_scalars = |font, shape_plan, scalars| Shaper.shape(font.face, Face.current(font.face), shape_plan.plan, scalars)

	## A range of character start offsets in the original UTF-8 text.
	## Characters whose first byte is in `start ..< end` are selected.
	## Defaults select the whole text. Empty or reversed ranges select none;
	## an offset inside a character selects by its start, without changing
	## the caller's offsets or repairing the range.
	TextRange := { start : U64 ?? 0, end : U64 ?? 18_446_744_073_709_551_615 }

	## Shape a selected part of a paragraph while retaining surrounding
	## characters as context, for joining across font or style boundaries.
	## Only selected characters produce glyphs; clusters remain byte offsets
	## into the original paragraph. This does not split scripts or choose
	## fallback fonts. For `cluster_ranges`, pass the selected text's end
	## offset rather than the end of a longer paragraph.
	shape_range : Font, ShapePlan, Str, TextRange -> Run
	shape_range = |font, shape_plan, text, range| match Font.shape_range_checked(font, shape_plan, text, range) {
		Ok(run) => run
		Err(OverBudget({ run, budgets: _ })) => run
	}

	## Shape a range with paragraph context and report exhausted work
	## budgets as `shape_checked` does. Context is supplied per call and
	## never becomes part of the reusable shaping plan.
	shape_range_checked : Font, ShapePlan, Str, TextRange -> Try(Run, [OverBudget({ run : Run, budgets : List(Budget) })])
	shape_range_checked = |font, shape_plan, text, range| {
		var $before = []
		var $selected = []
		var $after = []
		for character in Shaper.decode(text) {
			if character.offset < range.start {
				$before = $before.append(character.scalar)
			} else if character.offset < range.end and range.end > range.start {
				$selected = $selected.append(character)
			} else {
				$after = $after.append(character.scalar)
			}
		}
		shaped = Shaper.shape_items_with_context(font.face, Face.current(font.face), shape_plan.plan, $selected, { before: $before, after: $after })
		if shaped.stopped == 0 {
			Ok(shaped.run)
		} else {
			Err(OverBudget({ run: shaped.run, budgets: Shaper.budgets(shaped.stopped) }))
		}
	}

	## Shape text as `shape_planned` does, and also say which substitution
	## produced each glyph (see `GlyphOrigin`) and whether shaping
	## finished, as `shape_checked` says it: one call for a caller that
	## needs both. `origins` has one entry per glyph, in the run's (visual)
	## order. The run is the one `shape_planned` gives; only this
	## call pays for the origins (one more list, and naming the features of
	## the plan's substitution steps). When a bound stopped substitution
	## early, the result is `OverBudget` with the run and origins made so
	## far and every bound that stopped it.
	##
	## ```
	## match Font.shape_traced(font, plan, "fi") {
	##     Ok({ run, origins }) => origins # [Ligature({ feature: "liga", components: 2 })] in a font with an fi ligature
	##     Err(OverBudget({ run, origins, budgets })) => ...
	## }
	## ```
	shape_traced : Font, ShapePlan, Str -> Try({ run : Run, origins : List(GlyphOrigin) }, [OverBudget({ run : Run, origins : List(GlyphOrigin), budgets : List(Budget) })])
	shape_traced = |font, shape_plan, text| {
		shaped = Shaper.shape_items(font.face, Face.current(font.face), shape_plan.plan, Shaper.decode(text))
		origins = Shaper.origins(font.face, shape_plan.plan, shaped.items)
		if shaped.stopped == 0 {
			Ok({ run: shaped.run, origins })
		} else {
			Err(OverBudget({ run: shaped.run, origins, budgets: Shaper.budgets(shaped.stopped) }))
		}
	}

	## How wide text is, in font units: the sum of the advances of the run
	## `shape` gives with the default options (ligatures, kerning and the
	## other browser defaults). For other options, use `width_planned`.
	##
	## ```
	## units = Font.width(Font.sans, "Hello, world!") # 12111, at 2048 units to the em
	## ```
	##
	## A total beyond the range of `I32` (only possible for text of tens of
	## thousands of glyphs at the largest advances) is held at its limit.
	width : Font, Str -> I32
	width = |font, text| Font.width_planned(font, Font.plan(font, ShapeOptions.{}), text)

	## How wide text is with a plan made by `plan`, in font units: the sum
	## of the advances of the run `shape_planned` gives, held at the range
	## of `I32` as `width` is.
	##
	## ```
	## tabular = Font.plan(font, Font.ShapeOptions.{ features: [Font.Feature.{ tag: "tnum" }] })
	## Font.width_planned(font, tabular, "1111") == Font.width_planned(font, tabular, "0000")
	## ```
	width_planned : Font, ShapePlan, Str -> I32
	width_planned = |font, shape_plan, text| {
		run = Font.shape_planned(font, shape_plan, text)
		total = run.advances.fold(0.I64, |sum, a| sum + a.x.to_i64())
		total.max(-2147483648).min(2147483647).to_i32_wrap()
	}

	## Whether a glyph's entry in `Run.flags` says the text must not be
	## broken at the start of the glyph's cluster without shaping both sides
	## again: a ligature, kerning or contextual form spans the break, so the
	## glyphs on either side would change. Breaking elsewhere lets a line
	## breaker reuse the run's glyphs as they are.
	##
	## ```
	## safe_breaks = run.flags.map(|flags| !Font.is_unsafe_to_break(flags))
	## ```
	is_unsafe_to_break : U8 -> Bool
	is_unsafe_to_break = |flags| flags.bitwise_and(1) != 0

	## Whether a glyph's entry in `Run.flags` says the glyph is glyph 0
	## drawn for a character the font does not map: where a browser would
	## draw the character with another font.
	##
	## ```
	## needs_fallback = run.flags.any(Font.is_missing)
	## ```
	is_missing : U8 -> Bool
	is_missing = |flags| flags.bitwise_and(2) != 0

	## The part of the text each glyph of a run draws, as UTF-8 byte ranges
	## `start ..< end`, one per glyph in the run's order (so in
	## right-to-left text, too, entry `i` is glyph `i`'s). `length` is the
	## text's length in bytes (`text.count_utf8_bytes()`).
	##
	## ```
	## bytes = text.to_utf8()
	## drawn = Font.cluster_ranges(run, bytes.len()).map(|r| Str.from_utf8(bytes.sublist({ start: r.start, len: r.end - r.start })) ?? "")
	## ```
	##
	## A range runs from the glyph's cluster to the next larger cluster in
	## the run, or to `length` when there is none, so glyphs of one cluster
	## share a range and a ligature's covers every character it draws. A
	## cluster at or past `length` gets an empty range there.
	cluster_ranges : Run, U64 -> List({ start : U64, end : U64 })
	cluster_ranges = |run, length| Shaper.cluster_ranges(run.clusters, length)

	# ------------------------------------------------------------ default fonts

	## Inter 4.1, a sans for interfaces and diagrams, at Regular: ready to
	## use with no font file. Variable in weight (100 to 900) and optical
	## size; move it with `at`. Read when the program is compiled (a file
	## that did not read would stop the compilation), so using it costs
	## nothing at run time; a program that never names it carries none of
	## it.
	sans : Font
	sans =
		match Font.from_bytes(inter_file, ReadOptions.{}) {
			Ok(font) => font
			Err(_) => crash "a built-in font of roc-font could not be read"
		}

	## Merriweather 4.009, a serif for running text, at Regular. Variable in
	## weight (300 to 900), width (87 to 112) and optical size.
	serif : Font
	serif =
		match Font.from_bytes(merriweather_file, ReadOptions.{}) {
			Ok(font) => font
			Err(_) => crash "a built-in font of roc-font could not be read"
		}

	## Fira Code 6.2, a monospaced font with programming ligatures, at
	## Regular. Variable in weight (300 to 700); every glyph is 1200 units
	## wide at every weight.
	mono : Font
	mono =
		match Font.from_bytes(fira_code_file, ReadOptions.{}) {
			Ok(font) => font
			Err(_) => crash "a built-in font of roc-font could not be read"
		}

	## The exact font file `sans` was read from, for drawing or embedding
	## (in a PDF, say) the font that was measured.
	sans_bytes : List(U8)
	sans_bytes = inter_file

	## The exact font file `serif` was read from.
	serif_bytes : List(U8)
	serif_bytes = merriweather_file

	## The exact font file `mono` was read from.
	mono_bytes : List(U8)
	mono_bytes = fira_code_file

	## The licence of `sans` (the SIL Open Font License 1.1, with Inter's
	## copyright notice). Keep it with the font when passing the bytes on.
	sans_licence : Str
	sans_licence = inter_licence

	## The licence of `serif` (the SIL Open Font License 1.1, with
	## Merriweather's copyright notice and Reserved Font Name).
	serif_licence : Str
	serif_licence = merriweather_licence

	## The licence of `mono` (the SIL Open Font License 1.1, with Fira
	## Code's copyright notice).
	mono_licence : Str
	mono_licence = fira_code_licence
}
