import Sfnt
import Bytes
import TableCmap
import TableGlyf
import TableGlyfPoints
import TableGvar
import TableHead
import TableHhea
import TableHmtx
import TableMaxp
import TableOs2
import TableName
import TablePost
import TableVar
import LayoutGsub
import LayoutGdef
import LayoutKerning
import LayoutVar
import LayoutCommon
import Sorted
import TableMetadata
import TableCaret
import TableOutline
import TableVhea
import TableVmtx
import TableVorg
import TableVvar
import AatMorx
import AatFeatures
import AatFeatureSelect
import TableCff
import TableMath
import TableColorImages
import TablePalette
import TableColor
import TableGraphite
import TableAatKern
import TableAatAnchor

## A prepared face at a location of its variation space: every table
## `Font` uses, checked once, the queries on it, and the location state
## (`moved`) that variable queries read.
##
## Internal. Reading composes the table readers (`from_tables` of each
## `Table*` and `Layout*` module) and applies the reading mode. Lenient
## reading accepts what OTS 9.3.0 accepts, so a font reads exactly when a
## browser would draw it:
##
## - a broken `head`, `hhea`, `maxp`, `hmtx`, `cmap`, `loca`, `glyf`,
##   `OS/2`, `post`, `name`, `GSUB`, `GPOS` or `GDEF`, or a structurally
##   broken `kern`, rejects the font;
## - a `kern` table OTS drops (another version, pairs out of order, ...) is
##   dropped;
## - a bad `avar` is dropped alone, as OTS drops it, and the axes are
##   normalised without it;
## - any other problem in the variation data (`fvar`, `HVAR`, `MVAR`,
##   `gvar` and the outline points it moves, the `GDEF` item variation
##   store, `GPOS` device indices, `FeatureVariations` conditions) drops
##   the variations as one unit, as OTS drops them: the font reads as its
##   default instance. Variation data OTS keeps but roc-font cannot apply
##   (an `avar` version 2) is dropped the same way.
##
## A layout table over `max_lookups` is dropped (a roc-font limit, not a
## fault). Strict reading rejects the font for any problem. Every problem
## is reported, required ones first.
Face := {
	metadata : TableMetadata,
	carets : TableCaret,
	math : TableMath,
	svg_images : TableColorImages,
	sbix_images : TableColorImages,
	cbdt_images : TableColorImages,
	palettes : TablePalette,
	color : TableColor,
	units_per_em : U16,
	glyph_count : U64,
	advances : List(U16),
	vhea : [Present(TableVhea.Header), Absent],
	v_advances : List(U16),
	v_bearings : List(I16),
	vorg : [Present(TableVorg), Absent],
	boxes : List(TableGlyf.Bounds),
	# Whether the font has TrueType outlines (`glyf` and `loca`), so that
	# `boxes` measure every glyph.
	has_glyf : Bool,
	cmap : TableCmap,
	hhea : TableHhea.Hhea,
	os2 : [Present(TableOs2.Metrics), Absent],
	post : TablePost,
	name : TableName,
	gsub : LayoutGsub,
	aat : [Present(AatMorx), Absent],
	aat_features : AatFeatures,
	graphite : TableGraphite,
	kerx : TableAatKern,
	aat_kern : TableAatKern,
	anchors : TableAatAnchor,
	gdef : LayoutGdef,
	kerning : LayoutKerning,
	space : [Present(TableVar), Absent],
	hvar : [Present(TableVar.Hvar), Absent],
	vvar : [Present(TableVvar), Absent],
	mvar : [Present(TableVar.Mvar), Absent],
	outlines : [Present({ points : TableGlyfPoints, gvar : TableGvar }), Absent],
	cff : [Present(TableCff), Absent],
	layout_var : LayoutVar,
	gsub_variations : LayoutVar.FeatureVariations,
	gpos_variations : LayoutVar.FeatureVariations,
	location : Location,
	max_depth : U64,
	dropped : List(Problem),
}.{

	Problem : [
		NotAFont,
		NoSuchFace({ face : U32, count : U32 }),
		OverLimit(Str),
		MissingTable(Str),
		BadTable({ table : Str, offset : U32 }),
		BadUnitsPerEm,
		NoUnicodeMapping,
	]

	Options : { face : U64, strict : Bool, max_bytes : U64, max_faces : U64, max_lookups : U64, max_depth : U64 }

	## A location in the variation space: normalised coordinates (F2Dot14,
	## one per axis, empty for a static font), the region scalars of the
	## `HVAR` and `MVAR` stores there, whether any coordinate is not zero
	## (at the default location every delta is zero), and the `gvar`
	## location state. The `GDEF` store's state travels with the kerning.
	Location : { coords : List(I16), hvar : List(U32), vvar : List(U32), mvar : List(U32), cff : TableCff.Location, varied : Bool, gvar : TableGvar.Location }

	Metrics : {
		ascent : I32,
		descent : I32,
		line_gap : I32,
		cap_height : I32,
		x_height : I32,
		underline : { position : I32, thickness : I32 },
		strikeout : { position : I32, thickness : I32 },
	}

	default_location : Location
	default_location = { coords: [], hvar: [], vvar: [], mvar: [], cff: [], varied: False, gvar: { coords: [], nonzero: False, shared: [] } }

	## What reading found in the variation tables: the parts to use, the
	## problems that drop them all (`problems`), and those that drop only
	## `avar` (`avar_problems`).
	Variations : {
		space : [Present(TableVar), Absent],
		hvar : [Present(TableVar.Hvar), Absent],
		vvar : [Present(TableVvar), Absent],
		mvar : [Present(TableVar.Mvar), Absent],
		outlines : [Present({ points : TableGlyfPoints, gvar : TableGvar }), Absent],
		problems : List(Problem),
		avar_problems : List(Problem),
		fvar_axes : [Present(U64), Absent],
	}

	# Graphite tables form one program. A broken dependency drops that
	read_aat_kern : List(U8), List(Sfnt.Table), Str, U64 -> { value : TableAatKern, problems : List(Problem) }
	read_aat_kern = |bytes, tables, tag, glyphs| {
		match Sfnt.located(bytes, tables, tag, 0) {
			Missing => { value: TableAatKern.none, problems: [] }
			Bad(at) => { value: TableAatKern.none, problems: [Sfnt.bad(tag, at)] }
			Found(found) => match (if (tag == "kerx") TableAatKern.read_kerx(found.data, glyphs) else TableAatKern.read_kern(found.data, glyphs)) {
				Ok(value) => { value, problems: [] }
				Err(problems) => { value: TableAatKern.none, problems: problems.map(|p| Sfnt.bad(tag, found.offset + p.offset)) }
			}
		}
	}

	# Graphite tables form one program. A broken dependency drops that
	# program as a unit; diagnostics retain the original file offsets.
	read_graphite : List(U8), List(Sfnt.Table), U64, U64 -> { value : TableGraphite, problems : List(Problem) }
	read_graphite = |bytes, tables, glyphs, max_bytes| {
		if !tables.any(|t| t.tag == 0x53696C66) {
			return { value: TableGraphite.none, problems: [] }
		}
		var $data = []
		var $offsets = []
		var $problems = []
		for tag in ["Silf", "Gloc", "Glat", "Feat", "Sill"] {
			match Sfnt.located(bytes, tables, tag, 0) {
				Found(found) => {
					$data = $data.append(found.data)
					$offsets = $offsets.append(found.offset)
				}
				Missing => {
					if tag == "Silf" or tag == "Gloc" or tag == "Glat" {
						$problems = $problems.append(MissingTable(tag))
					}
					$data = $data.append([])
					$offsets = $offsets.append(0)
				}
				Bad(at) => {
					$problems = $problems.append(Sfnt.bad(tag, at))
					$data = $data.append([])
					$offsets = $offsets.append(at)
				}
			}
		}
		optional = |index, tag| if (tables.any(|t| t.tag == tag)) Present($data.get(index) ?? []) else Absent
		prepared = TableGraphite.read({ silf: $data.get(0) ?? [], gloc: $data.get(1) ?? [], glat: $data.get(2) ?? [], feat: optional(3, 0x46656174), sill: optional(4, 0x53696C6C), glyph_count: glyphs }, max_bytes)
		prepared_value = match prepared {
			Ok(value) => value
			Err(problems) => {
				for problem in problems {
					index = match problem.table {
						"Silf" => 0
						"Gloc" => 1
						"Glat" => 2
						"Feat" => 3
						_ => 4
					}
					$problems = $problems.append(
						match problem.reason {
							Malformed => Sfnt.bad(problem.table, ($offsets.get(index) ?? 0) + problem.offset)
							TooMuchWork => OverLimit(problem.table)
						},
					)
				}
				TableGraphite.none
			}
		}
		{ value: if ($problems.is_empty()) prepared_value else TableGraphite.none, problems: Face.unique($problems) }
	}

	# ------------------------------------------------------------ reading

	## How many faces a file holds.
	face_count : List(U8) -> Try(U64, [NotAFont])
	face_count = |bytes| Sfnt.face_count(bytes)

	read : List(U8), Options -> Try(Face, List(Problem))
	read = |bytes, options| {
		if bytes.len() > options.max_bytes {
			return Err([OverLimit("max_bytes")])
		}
		count = match Sfnt.face_count(bytes) {
			Ok(c) => c
			Err(NotAFont) => return Err([NotAFont])
		}
		if count > options.max_faces {
			return Err([OverLimit("max_faces")])
		}
		tables = match Sfnt.directory_of(bytes, options.face) {
			Ok(t) => t
			Err(NotAFont) => return Err([NotAFont])
			Err(NoSuchFace(which)) => return Err([NoSuchFace(which)])
		}
		# The directory as OTS checks it, whichever tables are named. OTS
		# compares offsets with the directory's size even in a collection,
		# where tables may come before a face's directory. OTS refuses 4096
		# tables or more.
		if tables.len() >= 4096 {
			return Err([NotAFont])
		}
		var $required = Face.directory_problems(bytes, tables, 12 + 16 * tables.len())
		head = TableHead.from_tables(bytes, tables)
		hhea = TableHhea.from_tables(bytes, tables)
		maxp = TableMaxp.from_tables(bytes, tables)
		cmap = TableCmap.from_tables(bytes, tables)
		$required = Face.collect($required, head)
		$required = Face.collect($required, hhea)
		$required = Face.collect($required, maxp)
		$required = Face.collect($required, cmap)
		# OTS rejects a font with a broken `OS/2` or `name`.
		os2 = TableOs2.from_tables(bytes, tables)
		$required = Face.collect($required, os2)
		name = TableName.from_tables(bytes, tables)
		$required = Face.collect_all($required, name)
		var $optional = []
		match (head, hhea, maxp) {
			(Ok(h), Ok(hh), Ok(glyph_count)) => {
				advances = TableHmtx.from_tables(bytes, tables, hh.metric_count, glyph_count)
				boxes = TableGlyf.from_tables(bytes, tables, h.long_offsets, glyph_count, hh.metric_count)
				$required = Face.collect($required, advances)
				$required = Face.collect($required, boxes)
				vertical = Face.read_vertical(bytes, tables, glyph_count)
				$optional = $optional.concat(vertical.problems)
				vorg = TableVorg.from_tables(bytes, tables, glyph_count)
				$optional = Face.collect($optional, vorg)
				graphite = Face.read_graphite(bytes, tables, glyph_count, options.max_bytes)
				$optional = $optional.concat(graphite.problems)
				kerx = Face.read_aat_kern(bytes, tables, "kerx", glyph_count)
				aat_kern = Face.read_aat_kern(bytes, tables, "kern", glyph_count)
				$optional = $optional.concat(kerx.problems)
				anchors = match Sfnt.located(bytes, tables, "ankr", 12) {
					Missing => TableAatAnchor.none
					Bad(at) => {
						$optional = $optional.append(Sfnt.bad("ankr", at))
						TableAatAnchor.none
					}
					Found(found) => match TableAatAnchor.read(found.data, glyph_count) {
						Ok(value) => value
						Err(problems) => {
							$optional = $optional.concat(problems.map(|p| Sfnt.bad("ankr", found.offset + p.offset)))
							TableAatAnchor.none
						}
					}
				}
				aat = match Sfnt.located(bytes, tables, "morx", 8) {
					Missing => Absent
					Bad(at) => {
						$optional = $optional.append(Sfnt.bad("morx", at))
						Absent
					}
					Found(found) => match AatMorx.read(found.data, glyph_count) {
						Ok(value) => Present(value)
						Err(Bad(at)) => {
							$optional = $optional.append(Sfnt.bad("morx", found.offset + at))
							Absent
						}
					}
				}
				aat_features = match Sfnt.located(bytes, tables, "feat", 12) {
					Missing => AatFeatures.none
					Bad(at) => {
						$optional = $optional.append(Sfnt.bad("feat", at))
						AatFeatures.none
					}
					Found(found) => match AatFeatures.read(found.data) {
						Ok(value) => value
						Err(Bad(at)) => {
							$optional = $optional.append(Sfnt.bad("feat", found.offset + at))
							AatFeatures.none
						}
					}
				}
				# Every glyph's outline is checked as OTS checks it (flags,
				# instruction lengths, coordinates, composites), whether or not
				# the font varies: a broken `glyf` rejects the font. The points
				# read here are the ones `gvar` moves, so a variable font reads
				# its outlines once.
				points =
					if boxes.is_ok() {
						match (Sfnt.located(bytes, tables, "glyf", 0), Sfnt.located(bytes, tables, "loca", 0), Sfnt.located(bytes, tables, "hmtx", 0)) {
							(Found(glyf), Found(loca), Found(hmtx)) => {
								checked = match TableGlyfPoints.read(glyf.data, loca.data, h.long_offsets, glyph_count, hmtx.data, hh.metric_count) {
									Ok(p) => match vertical.header {
										Present(_) => TableGlyfPoints.with_vertical(p, { advances: vertical.advances, bearings: vertical.bearings })
										Absent => Ok(p)
									}
									Err(problems) => Err(problems)
								}
								match checked {
									Ok(_) => {}
									Err(problems) => {
										$required = $required.concat(problems.take_first(1).map(|q| Sfnt.bad(q.table, (if (q.table == "glyf") glyf.offset else loca.offset) + q.offset)))
									}
								}
								Read(checked)
							}
							_ => Unread
						}
					} else {
						Unread
					}
				post = TablePost.from_tables(bytes, tables, glyph_count)
				$required = Face.collect_all($required, post)
				# A layout table over the lookup limit is dropped; a broken one
				# rejects the font, as OTS rejects it.
				gsub = LayoutGsub.from_tables(bytes, tables, options.max_lookups)
				match gsub {
					Err(OverLimit(which)) => {
						$optional = $optional.append(OverLimit(which))
					}
					Err(BadTable(b)) => {
						$required = $required.append(BadTable(b))
					}
					Ok(_) => {}
				}
				variations = Face.read_variations(bytes, tables, glyph_count, h.long_offsets, hh.metric_count, points)
				var $var_problems = variations.problems
				axes = match variations.space {
					Present(space) => Present(TableVar.axis_total(space))
					Absent => Absent
				}
				axis_count = match axes {
					Present(n) => n
					Absent => 0
				}
				# The `GDEF` table is checked whole, as OTS checks it; its item
				# variation store is read for use when the font has variations.
				fvar_axes = variations.fvar_axes
				lv_read = match Face.located_tag(bytes, tables, 0x47444546, 0) {
					Missing => Ok(Absent)
					Bad(at) => Err(Required(Sfnt.bad("GDEF", at)))
					Found(found) =>
						match LayoutVar.check_gdef(found.data, glyph_count, fvar_axes) {
							Err(p) => Err(Required(Sfnt.bad("GDEF", found.offset + p.offset)))
							Ok(_) =>
								match axes {
									Absent => Ok(Absent)
									Present(n) =>
										match LayoutVar.read_gdef(found.data, n) {
											Ok(store) => Ok(Present(store))
											Err(ps) => Err(Variation(ps.map(|p| Sfnt.bad("GDEF", found.offset + p.offset))))
										}
								}
						}
				}
				lv = match lv_read {
					Ok(Present(store)) => store
					Ok(Absent) => LayoutVar.none(axis_count)
					Err(Required(p)) => {
						$required = $required.append(p)
						LayoutVar.none(0)
					}
					Err(Variation(ps)) => {
						$var_problems = $var_problems.concat(ps)
						LayoutVar.none(axis_count)
					}
				}
				gpos = LayoutKerning.from_gpos(bytes, tables, glyph_count, options.max_lookups, lv)
				match gpos {
					Err(OverLimit(which)) => {
						$optional = $optional.append(OverLimit(which))
					}
					Err(BadTable(b)) => {
						$required = $required.append(BadTable(b))
					}
					Ok(Present(g)) if axes != Absent => {
						$var_problems = $var_problems.concat(g.deltas.map(|at| Sfnt.bad("GPOS", at)))
					}
					Ok(_) => {}
				}
				# OTS drops a `kern` table from a font without `glyf` ("not for
				# CFF fonts"). It rejects fonts with no outlines at all, which
				# roc-font reads, so only CFF fonts lose `kern` here.
				# Tags as numbers: `glyf`, `CFF ` and `CFF2`.
				cff_only = !tables.any(|t| t.tag == 0x676C7966) and tables.any(|t| t.tag == 0x43464620 or t.tag == 0x43464632)
				kern = match LayoutKerning.from_kern(bytes, tables) {
					Ok(Present(_)) if cff_only => Err(Drop(Sfnt.bad("kern", Face.table_offset(tables, "kern"))))
					Err(_) if TableAatKern.has_data(aat_kern.value) and !cff_only => Ok(Absent)
					read => read
				}
				match kern {
					Err(Drop(problem)) => {
						$optional = $optional.append(problem)
					}
					Err(Reject(problem)) => {
						$required = $required.append(problem)
					}
					Ok(_) => {}
				}
				# `FeatureVariations` of the layout tables that are used.
				gsub_fv = match (if (gsub.is_ok()) Face.read_feature_variations(bytes, tables, "GSUB", 0x47535542, axes, fvar_axes, lv) else Ok(LayoutVar.no_feature_variations)) {
					Ok(fv) => fv
					Err(Required(ps)) => {
						$required = $required.concat(ps)
						LayoutVar.no_feature_variations
					}
					Err(Variation(ps)) => {
						$var_problems = $var_problems.concat(ps)
						LayoutVar.no_feature_variations
					}
				}
				gpos_fv = match (if (gpos.is_ok()) Face.read_feature_variations(bytes, tables, "GPOS", 0x47504F53, axes, fvar_axes, lv) else Ok(LayoutVar.no_feature_variations)) {
					Ok(fv) => fv
					Err(Required(ps)) => {
						$required = $required.concat(ps)
						LayoutVar.no_feature_variations
					}
					Err(Variation(ps)) => {
						$var_problems = $var_problems.concat(ps)
						LayoutVar.no_feature_variations
					}
				}
				# Variation problems drop every variation table as one unit.
				keep_variations = $var_problems.is_empty()
				images = Face.read_image_tables(bytes, tables, glyph_count)
				$optional = $optional.concat(images.problems)
				palettes = match Face.located_tag(bytes, tables, 0x4350414C, 0) {
					Missing => TablePalette.none
					Bad(at) => {
						$optional = $optional.append(Sfnt.bad("CPAL", at))
						TablePalette.none
					}
					Found(found) => match TablePalette.read(found.data) {
						Ok(value) => value
						Err(offsets) => {
							$optional = $optional.concat(offsets.map(|at| Sfnt.bad("CPAL", found.offset + at)))
							TablePalette.none
						}
					}
				}
				color = match Face.located_tag(bytes, tables, 0x434F4C52, 0) {
					Missing => TableColor.none
					Bad(at) => {
						$optional = $optional.append(Sfnt.bad("COLR", at))
						TableColor.none
					}
					Found(found) => {
						# COLR depends on a valid CPAL, including foreground-only artwork.
						if TablePalette.palette_count(palettes) == 0 {
							$optional = $optional.append(Sfnt.bad("COLR", found.offset))
							TableColor.none
						} else {
							color_axes = match fvar_axes {
								Present(n) => n
								Absent => 0
							}
							match TableColor.read(found.data, glyph_count, TablePalette.entry_count(palettes).to_u64(), color_axes) {
								Ok(value) => TableColor.at_location(value, [])
								Err(offsets) => {
									$optional = $optional.concat(offsets.map(|at| Sfnt.bad("COLR", found.offset + at)))
									TableColor.none
								}
							}
						}
					}
				}
				math = match Face.located_tag(bytes, tables, 0x4D415448, 0) {
					Missing => TableMath.none
					Bad(at) => {
						$optional = $optional.append(Sfnt.bad("MATH", at))
						TableMath.none
					}
					Found(found) => match TableMath.read(found.data, glyph_count, lv) {
						Ok(value) => value
						Err(offsets) => {
							$optional = $optional.concat(offsets.map(|at| Sfnt.bad("MATH", found.offset + at)))
							TableMath.none
						}
					}
				}
				# Static outlines are prepared too: path and point queries need
				# them even when the font has no variation space.
				cff_read = Face.read_cff(
					bytes,
					tables,
					glyph_count,
					match fvar_axes {
						Present(n) => n
						Absent => 0
					},
				)
				$required = $required.concat(cff_read.problems)
				cff_default = match cff_read.prepared {
					Present(prepared) => TableCff.location(prepared, [])
					Absent => []
				}
				static_outlines = match points {
					Read(Ok(p)) => Present({ points: p, gvar: TableGvar.absent })
					_ => Absent
				}
				outline_points = match static_outlines {
					Present(o) => Present(o.points)
					Absent => Absent
				}
				carets = match Sfnt.located(bytes, tables, "GDEF", 12) {
					Found(found) => match TableCaret.read(found.data, glyph_count, outline_points, lv) {
						Ok(value) => value
						Err(Bad(at)) => {
							$required = $required.append(Sfnt.bad("GDEF", found.offset + at))
							TableCaret.none
						}
					}
					_ => TableCaret.none
				}
				$optional = $optional.concat(variations.avar_problems).concat($var_problems)
				$required = Face.unique($required)
				$optional = Face.unique($optional).drop_if(|p| $required.contains(p))
				problems = $required.concat($optional)
				if !$required.is_empty() or (options.strict and !problems.is_empty()) {
					Err(problems)
				} else {
					match (advances, boxes, cmap) {
						(Ok(a), Ok(b), Ok(c)) => {
							no_lv = LayoutVar.none(0)
							gdef = match Face.located_tag(bytes, tables, 0x47444546, 12) {
								Found(found) => LayoutGdef.read(found.data) ?? LayoutGdef.none
								_ => LayoutGdef.none
							}
							Ok({
								metadata: { bytes, tables, glyph_count, metric_count: hh.metric_count },
								carets,
								math,
								svg_images: images.svg,
								sbix_images: images.sbix,
								cbdt_images: images.cbdt,
								palettes,
								color,
								units_per_em: h.units_per_em,
								glyph_count,
								advances: a,
								vhea: vertical.header,
								v_advances: vertical.advances,
								v_bearings: vertical.bearings,
								vorg: vorg ?? Absent,
								boxes: b,
								has_glyf: tables.any(|t| t.tag == 0x676C7966) and tables.any(|t| t.tag == 0x6C6F6361),
								cmap: c,
								hhea: hh,
								os2: os2 ?? Absent,
								post: Face.present(post ?? Absent, TablePost.none),
								name: Face.present(name ?? Absent, TableName.none),
								gsub: LayoutGsub.with_gdef(gsub ?? LayoutGsub.none, gdef),
								aat,
								aat_features,
								graphite: graphite.value,
								kerx: kerx.value,
								aat_kern: if (cff_only) TableAatKern.none else aat_kern.value,
								anchors,
								gdef,
								kerning: LayoutKerning.combine(gpos ?? Absent, kern ?? Absent, if (keep_variations) lv else no_lv, gdef),
								space: if (keep_variations) variations.space else Absent,
								hvar: if (keep_variations) variations.hvar else Absent,
								vvar: if (keep_variations) variations.vvar else Absent,
								mvar: if (keep_variations) variations.mvar else Absent,
								outlines: if keep_variations {
									match variations.outlines {
										Present(o) => Present(o)
										Absent => static_outlines
									}
								} else {
									static_outlines
								},
								layout_var: if (keep_variations) lv else no_lv,
								cff: cff_read.prepared,
								gsub_variations: if (keep_variations) gsub_fv else LayoutVar.no_feature_variations,
								gpos_variations: if (keep_variations) gpos_fv else LayoutVar.no_feature_variations,
								location: { ..Face.default_location, cff: cff_default },
								max_depth: options.max_depth,
								dropped: $optional,
							})
						}
						# Unreachable: a failed required table is in `$required`.
						_ => Err(problems)
					}
				}
			}
			_ => {
				required = Face.unique($required)
				Err(required.concat(Face.unique($optional).drop_if(|p| required.contains(p))))
			}
		}
	}

	## Encoded color assets are independent optional font facts. This checks
	## container structure; consumers decode image/XML payloads themselves.
	read_image_tables : List(U8), List(Sfnt.Table), U64 -> { svg : TableColorImages, sbix : TableColorImages, cbdt : TableColorImages, problems : List(Problem) }
	read_image_tables = |bytes, tables, glyph_count| {
		one = |tag, number, reader| match Face.located_tag(bytes, tables, number, 0) {
			Missing => { value: TableColorImages.none, problems: [] }
			Bad(at) => { value: TableColorImages.none, problems: [Sfnt.bad(tag, at)] }
			Found(found) => match reader(found.data, glyph_count) {
				Ok(value) => { value, problems: [] }
				Err(Bad(problem)) => { value: TableColorImages.none, problems: [Sfnt.bad(problem.table, found.offset + problem.offset)] }
			}
		}
		svg = one("SVG ", 0x53564720, TableColorImages.read_svg)
		sbix = one("sbix", 0x73626978, TableColorImages.read_sbix)
		cblc = Face.located_tag(bytes, tables, 0x43424C43, 0)
		cbdt = Face.located_tag(bytes, tables, 0x43424454, 0)
		bitmap = match (cblc, cbdt) {
			(Missing, Missing) => { value: TableColorImages.none, problems: [] }
			(Found(locations), Found(data)) => match TableColorImages.read_cbdt(locations.data, data.data, glyph_count) {
				Ok(value) => { value, problems: [] }
				Err(Bad(problem)) => { value: TableColorImages.none, problems: [Sfnt.bad(problem.table, Face.table_offset(tables, problem.table) + problem.offset)] }
			}
			_ => {
				var $problems = []
				match cblc {
					Found(found) => {
						$problems = $problems.append(Sfnt.bad("CBLC", found.offset))
					}
					Bad(at) => {
						$problems = $problems.append(Sfnt.bad("CBLC", at))
					}
					Missing => {}
				}
				match cbdt {
					Found(found) => {
						$problems = $problems.append(Sfnt.bad("CBDT", found.offset))
					}
					Bad(at) => {
						$problems = $problems.append(Sfnt.bad("CBDT", at))
					}
					Missing => {}
				}
				{ value: TableColorImages.none, problems: $problems }
			}
		}
		{ svg: svg.value, sbix: sbix.value, cbdt: bitmap.value, problems: svg.problems.concat(sbix.problems).concat(bitmap.problems) }
	}

	## The table records OTS rejects a font for, each named by its table and
	## offset: a table not aligned to four bytes, starting inside the
	## directory (before `data_start`) or past the end of the file, empty,
	## running past the end of the file, or overlapping another table.
	## (OTS also requires `OS/2`, `name`, `post` and outlines to be present;
	## roc-font does not, so metrics-only and synthetic fonts read.)
	directory_problems : List(U8), List(Sfnt.Table), U64 -> List(Problem)
	directory_problems = |bytes, tables, data_start| {
		size = bytes.len()
		name_of = |t| Str.from_utf8_lossy([t.tag.shr_zf_wrap(24), t.tag.shr_zf_wrap(16), t.tag.shr_zf_wrap(8), t.tag].map(|b| b.bitwise_and(0xFF).to_u8_wrap()))
		var $out = []
		for t in tables {
			if t.offset.bitwise_and(3) != 0 or t.offset < data_start or t.offset >= size or t.length == 0 or t.length > size - t.offset {
				$out = $out.append(Sfnt.bad(name_of(t), t.offset))
			}
		}
		if $out.is_empty() {
			# Overlap. Directories usually list tables in increasing offset
			# order, which needs one pass and no allocation; otherwise every
			# pair is compared (at most 4095 tables, so at most 8.4 million
			# comparisons, and only for an unusual directory).
			var $previous_end = 0
			var $in_order = True
			for t in tables {
				if t.offset < $previous_end {
					$in_order = False
				}
				$previous_end = $previous_end.max(t.offset + t.length)
			}
			if !$in_order {
				count = tables.len()
				for i in 0..<count {
					a = tables.get(i) ?? { tag: 0, offset: 0, length: 0 }
					var $j = i + 1
					while $j < count {
						b = tables.get($j) ?? { tag: 0, offset: 0, length: 0 }
						if a.offset < b.offset + b.length and b.offset < a.offset + a.length {
							$out = $out.append(Sfnt.bad(name_of(b), b.offset))
							$j = count
						} else {
							$j = $j + 1
						}
					}
				}
			}
		}
		$out
	}

	## Problems without repeats (a table past the end of the file is found
	## twice: by the directory check and by its reader), in first order.
	unique : List(Problem) -> List(Problem)
	unique = |problems| {
		var $out = []
		for p in problems {
			if !$out.contains(p) {
				$out = $out.append(p)
			}
		}
		$out
	}

	present : [Present(a), Absent], a -> a
	present = |found, fallback|
		match found {
			Present(value) => value
			Absent => fallback
		}

	## Add a reading result's problem, if it has one, to a list of problems.
	collect : List(p), Try(a, p) -> List(p)
	collect = |problems, result|
		match result {
			Ok(_) => problems
			Err(problem) => problems.append(problem)
		}

	collect_all : List(p), Try(a, List(p)) -> List(p)
	collect_all = |problems, result|
		match result {
			Ok(_) => problems
			Err(found) => problems.concat(found)
		}

	## The variation tables: `fvar`, then `avar`, `HVAR`, `MVAR` and `gvar`
	## (with the outline points it moves) when `fvar` reads. A bad `avar`
	## drops itself (`avar_problems`); every other problem drops them all.
	## Without `fvar` the others mean nothing and are not read. Problems
	## name each table and the byte offset in the file. `points_read` is the
	## outline points already read from `glyf`, `loca` and `hmtx` as found
	## here, or `Unread` when they were not.
	read_variations : List(U8), List(Sfnt.Table), U64, Bool, U64, [Read(Try(TableGlyfPoints, List(TableGlyfPoints.Problem))), Unread] -> Variations
	read_variations = |bytes, tables, glyph_count, long_offsets, metric_count, points_read| {
		nothing = { space: Absent, hvar: Absent, vvar: Absent, mvar: Absent, outlines: Absent, problems: [], avar_problems: [], fvar_axes: Absent }
		# Each problem in the file: its table's offset plus its own.
		placed = |ps| ps.map(|p| Sfnt.bad(p.table, Face.table_offset(tables, p.table) + p.offset))
		match Sfnt.located(bytes, tables, "fvar", 0) {
			Missing => nothing
			Bad(at) => { ..nothing, problems: [Sfnt.bad("fvar", at)] }
			Found(fvar) =>
			# The axis count OTS checks other tables against, even when
			# `fvar` itself is dropped.
				match TableVar.read_fvar(fvar.data) {
					Err(problems) => { ..nothing, problems: placed(problems), fvar_axes: if (fvar.data.len() >= 10) Present(Bytes.u16(fvar.data, 8)) else Absent }
					Ok(axes_only) => {
						axes = TableVar.axis_total(axes_only)
						avar = match Sfnt.located(bytes, tables, "avar", 0) {
							Found(found) =>
								match TableVar.read_avar(found.data, axes) {
									Ok(maps) => Maps(maps)
									Err(problems) => Dropped(placed(problems))
								}
							Bad(at) => Dropped([Sfnt.bad("avar", at)])
							Missing => Identity
						}
						space = match avar {
							Maps(maps) => TableVar.with_avar(axes_only, maps)
							_ => axes_only
						}
						avar_problems = match avar {
							Dropped(ps) => ps
							_ => []
						}
						hvar = match Sfnt.located(bytes, tables, "HVAR", 0) {
							Missing => Ok(Absent)
							Bad(at) => Err([Sfnt.bad("HVAR", at)])
							Found(found) => TableVar.read_hvar(found.data, axes, glyph_count).map_ok(|value| Present(value)).map_err(placed)
						}
						mvar = match Sfnt.located(bytes, tables, "MVAR", 0) {
							Missing => Ok(Absent)
							Bad(at) => Err([Sfnt.bad("MVAR", at)])
							Found(found) => TableVar.read_mvar(found.data, axes).map_ok(|value| Present(value)).map_err(placed)
						}
						outlines = match (Sfnt.located(bytes, tables, "gvar", 0), Sfnt.located(bytes, tables, "glyf", 0), Sfnt.located(bytes, tables, "loca", 0), Sfnt.located(bytes, tables, "hmtx", 0)) {
							(Found(gvar), Found(glyf), Found(loca), Found(hmtx)) => {
								checked = match points_read {
									Read(already) => already
									Unread => TableGlyfPoints.read(glyf.data, loca.data, long_offsets, glyph_count, hmtx.data, metric_count)
								}
								match checked {
									Err(problems) => Err(placed(problems))
									Ok(points) =>
										match TableGvar.read(gvar.data, axes, points) {
											Err(problems) => Err(placed(problems))
											Ok(moves) => Ok(Present({ points, gvar: moves }))
										}
								}
							}
							_ => Ok(Absent)
						}

						vvar = match Sfnt.located(bytes, tables, "VVAR", 0) {
							Missing => Ok(Absent)
							Bad(at) => Err([Sfnt.bad("VVAR", at)])
							Found(found) => TableVvar.read(found.data, axes, glyph_count).map_ok(|value| Present(value)).map_err(placed)
						}
						problems = Face.collect_all(Face.collect_all(Face.collect_all(Face.collect_all([], hvar), vvar), mvar), outlines)
						if problems.is_empty() {
							{ space: Present(space), hvar: hvar ?? Absent, vvar: vvar ?? Absent, mvar: mvar ?? Absent, outlines: outlines ?? Absent, problems: [], avar_problems, fvar_axes: Present(axes) }
						} else {
							{ ..nothing, problems: problems, avar_problems, fvar_axes: Present(axes) }
						}
					}
				}
		}
	}

	## The `FeatureVariations` of `GSUB` or `GPOS` (`tag`) in a font with
	## variations. A problem OTS rejects the table for is `Required`; any
	## other drops the variations (`Variation`). OTS also rejects feature
	## variations in a font without `fvar`.
	read_feature_variations : List(U8), List(Sfnt.Table), Str, U64, [Present(U64), Absent], [Present(U64), Absent], LayoutVar -> Try(LayoutVar.FeatureVariations, [Required(List(Problem)), Variation(List(Problem))])
	read_feature_variations = |bytes, tables, tag, tag_value, axes, fvar_axes, lv|
		match (Face.located_tag(bytes, tables, tag_value, 10), axes) {
			(Found(found), Present(n)) =>
				match LayoutVar.read_feature_variations(found.data, tag, lv, n) {
					Ok(fv) => Ok(fv)
					Err(ps) => {
						structural = ps.keep_if(|p| p.reason == Truncated or p.reason == AxisIndex or p.reason == LookupIndex or p.reason == MapRange)
						if structural.is_empty() {
							Err(Variation(ps.map(|p| Sfnt.bad(tag, found.offset + p.offset))))
						} else {
							Err(Required(structural.map(|p| Sfnt.bad(tag, found.offset + p.offset))))
						}
					}
				}
			(Found(found), Absent) if fvar_axes == Absent and Bytes.u16(found.data, 2) >= 1 and found.data.len() >= 14 and Bytes.u32(found.data, 10) != 0 => Err(Required([Sfnt.bad(tag, found.offset + 10)]))
			_ => Ok(LayoutVar.no_feature_variations)
		}

	## `Sfnt.located` for a tag given as its number, without converting a
	## string or allocating: the tables reading adds to every font use it.
	located_tag : List(U8), List(Sfnt.Table), U64, U64 -> [Found({ data : List(U8), offset : U64 }), Missing, Bad(U64)]
	located_tag = |bytes, tables, tag, minimum| {
		var $result = Missing
		var $i = 0
		while $i < tables.len() {
			t = tables.get($i) ?? { tag: 0, offset: 0, length: 0 }
			if t.tag == tag {
				$result = if (Bytes.fits(t.offset, t.length, bytes.len()) and t.length >= minimum) Found({ data: bytes.sublist({ start: t.offset, len: t.length }), offset: t.offset }) else Bad(t.offset)
				$i = tables.len()
			} else {
				$i = $i + 1
			}
		}
		$result
	}

	## The offset in the file of a table, by its tag (0 if absent).
	table_offset : List(Sfnt.Table), Str -> U64
	table_offset = |tables, name| {
		wanted = Face.tag(name).to_u64()
		match tables.find_first(|t| t.tag == wanted) {
			Ok(t) => t.offset
			Err(_) => 0
		}
	}

	## The axis settings a `Font.Variation` stands for: CSS weight and width
	## values on `wght` and `wdth`, the optical size on `opsz` when given,
	## then the caller's axes whose tags are four bytes.
	settings : [Thin, ExtraLight, Light, Regular, Medium, SemiBold, Bold, ExtraBold, Black, Weight(U16)], [UltraCondensed, ExtraCondensed, Condensed, SemiCondensed, Normal, SemiExpanded, Expanded, ExtraExpanded, UltraExpanded, Percent(Dec)], [FontDefault, Size(Dec)], List({ tag : Str, value : Dec }) -> List({ tag : U32, value : Dec })
	settings = |weight_name, width_name, optical_size, axes| {
		weight = match weight_name {
			Thin => 100
			ExtraLight => 200
			Light => 300
			Regular => 400
			Medium => 500
			SemiBold => 600
			Bold => 700
			ExtraBold => 800
			Black => 900
			Weight(w) => Dec.from_attos(w.to_i128() * 1_000_000_000_000_000_000)
		}
		width = match width_name {
			UltraCondensed => 50
			ExtraCondensed => 62.5
			Condensed => 75
			SemiCondensed => 87.5
			Normal => 100
			SemiExpanded => 112.5
			Expanded => 125
			ExtraExpanded => 150
			UltraExpanded => 200
			Percent(p) => p
		}
		size = match optical_size {
			FontDefault => []
			Size(px) => [{ tag: Face.tag("opsz"), value: px }]
		}
		extra = axes.keep_if(|a| a.tag.to_utf8().len() == 4).map(|a| { tag: Face.tag(a.tag), value: a.value })
		[{ tag: Face.tag("wght"), value: weight }, { tag: Face.tag("wdth"), value: width }].concat(size).concat(extra)
	}

	# ------------------------------------------------------------ locations

	## The location for design-space settings (axis tag, value); see
	## `TableVar.coords_for`. A static font has one location.
	location : Face, List({ tag : U32, value : Dec }) -> Location
	location = |face, given|
		match face.space {
			Absent => face.location
			Present(space) => Face.location_at(face, TableVar.coords_for(space, given))
		}

	## The location state at normalised coordinates.
	location_at : Face, List(I16) -> Location
	location_at = |face, coords| {
		varied = coords.any(|c| c != 0)
		hvar = match face.hvar {
			Present(h) if varied => TableVar.region_scalars(h.store, coords)
			_ => []
		}
		mvar = match face.mvar {
			Present(m) if varied => TableVar.region_scalars(m.store, coords)
			_ => []
		}
		gvar = match face.outlines {
			Present(o) if varied => TableGvar.location(o.gvar, coords)
			_ => Face.default_location.gvar
		}
		vvar = match face.vvar {
			Present(v) if varied => TableVvar.scalars(v, coords)
			_ => []
		}
		cff = match face.cff {
			Present(prepared) => TableCff.location(prepared, coords)
			Absent => []
		}
		{ coords, hvar, vvar, mvar, cff, varied, gvar }
	}

	## The face moved to a location: every query, and shaping (kerning and
	## feature variations), then measures there. The tables are shared.
	moved : Face, List({ tag : U32, value : Dec }) -> Face
	moved = |face, given| {
		loc = Face.location(face, given)
		layout_location = LayoutVar.location(face.layout_var, loc.coords)
		# Ordinary variable fonts do not need a second, precise scalar pool
		# for a mathematical table they do not contain.
		math = if (TableMath.has_data(face.math)) TableMath.at_location(face.math, LayoutVar.math_location(face.layout_var, loc.coords)) else face.math
		{ ..face, location: loc, kerning: LayoutKerning.at_location(face.kerning, layout_location), math, color: TableColor.at_location(face.color, loc.coords) }
	}

	## The face moved to a `Font.Variation`'s location (see `settings`). A
	## static face is returned as it is, without building any settings.
	moved_to : Face, [Thin, ExtraLight, Light, Regular, Medium, SemiBold, Bold, ExtraBold, Black, Weight(U16)], [UltraCondensed, ExtraCondensed, Condensed, SemiCondensed, Normal, SemiExpanded, Expanded, ExtraExpanded, UltraExpanded, Percent(Dec)], [FontDefault, Size(Dec)], List({ tag : Str, value : Dec }) -> Face
	moved_to = |face, weight, width, optical_size, axes|
		match face.space {
			Absent => face
			Present(_) => Face.moved(face, Face.settings(weight, width, optical_size, axes))
		}

	## The face's location.
	current : Face -> Location
	current = |face| face.location

	## The normalised coordinates of the face's location, one per axis in
	## `fvar` order (F2Dot14, after `avar`); empty for a static font.
	coords : Face -> List(I16)
	coords = |face| face.location.coords

	## What feature variations need: the `FeatureVariations` of `GSUB` and
	## `GPOS` (each `LayoutVar.no_feature_variations` when absent or
	## dropped), the `GDEF` store their conditions may read, and the
	## face's normalised coordinates. `LayoutVar.substitutions_at(fv, lv,
	## coords)` gives the feature table substitutions in force.
	feature_variations : Face -> { gsub : LayoutVar.FeatureVariations, gpos : LayoutVar.FeatureVariations, lv : LayoutVar, coords : List(I16) }
	feature_variations = |face| { gsub: face.gsub_variations, gpos: face.gpos_variations, lv: face.layout_var, coords: face.location.coords }

	## The named instances in `fvar` order: each instance's name (from the
	## `name` table, "" without one) and its value on every axis.
	instances : Face -> List({ name : Str, axes : List({ tag : Str, value : Dec }) })
	instances = |face|
		match face.space {
			Absent => []
			Present(space) => {
				tags = Face.axes(face).map(|a| a.tag)
				count = tags.len()
				var $out = List.with_capacity(space.instance_names.len())
				for i in 0..<space.instance_names.len() {
					id = (space.instance_names.get(i) ?? 0).to_u64()
					name = TableName.string(face.name, id) ?? ""
					var $axes = List.with_capacity(count)
					for a in 0..<count {
						fixed = (space.instance_coords.get(i * count + a) ?? 0).to_i128()
						$axes = $axes.append({ tag: tags.get(a) ?? "", value: Dec.from_attos(fixed * 15_258_789_062_500) })
					}
					$out = $out.append({ name, axes: $axes })
				}
				$out
			}
		}

	## The axes of the variation space, in `fvar` order: tag, minimum,
	## default and maximum in design units.
	axes : Face -> List({ tag : Str, min : Dec, default : Dec, max : Dec })
	axes = |face|
		match face.space {
			Absent => []
			Present(space) => {
				# Fixed 16.16 is exact in `Dec`: 10^18 / 65536 is a whole number.
				dec = |list, a| Dec.from_attos((list.get(a) ?? 0).to_i128() * 15_258_789_062_500)
				var $out = List.with_capacity(space.tags.len())
				for a in 0..<space.tags.len() {
					t = (space.tags.get(a) ?? 0).to_u64()
					bytes = [t.shr_zf_wrap(24), t.shr_zf_wrap(16), t.shr_zf_wrap(8), t].map(|b| b.bitwise_and(0xFF).to_u8_wrap())
					$out = $out.append({ tag: Str.from_utf8_lossy(bytes), min: dec(space.minimum, a), default: dec(space.default, a), max: dec(space.maximum, a) })
				}
				$out
			}
		}

	## Whether the face has an axis with this tag.
	has_axis : Face, U32 -> Bool
	has_axis = |face, tag|
		match face.space {
			Absent => False
			Present(space) => space.tags.contains(tag)
		}

	# ------------------------------------------------------------ queries

	units_per_em : Face -> U16
	units_per_em = |face| face.units_per_em

	glyph_count : Face -> U64
	glyph_count = |face| face.glyph_count

	dropped : Face -> List(Problem)
	dropped = |face| face.dropped

	glyph : Face, U32 -> Try(U64, [Missing])
	glyph = |face, code_point| TableCmap.glyph(face.cmap, code_point, face.glyph_count)

	code_points : Face -> List(U32)
	code_points = |face| TableCmap.code_points(face.cmap, face.glyph_count)

	contour_point : Face, Location, U64, U64 -> [Present(TableAatAnchor.Point), Absent]
	contour_point = |face, loc, id, index| match face.outlines {
		Absent => Absent
		Present(outline) => {
			if id >= face.glyph_count {
				return Absent
			}
			points = TableGvar.points(outline.points, outline.gvar, loc.gvar, id)
			count = points.xs.len()
			if count < 4 or index >= count - 4 {
				return Absent
			}
			shift = points.xs.get(count - 4) ?? 0
			Present({ x: TableVar.f32_round_half_up(TableVar.f32_sub(points.xs.get(index) ?? 0, shift)).to_i32_wrap(), y: TableVar.f32_round_half_up(points.ys.get(index) ?? 0).to_i32_wrap() })
		}
	}

	## Outline programs are required when present, like TrueType glyf.
	## Validate both independent CFF tables before choosing CFF2 over CFF1.
	read_cff : List(U8), List(Sfnt.Table), U64, U64 -> { prepared : [Present(TableCff), Absent], problems : List(Problem) }
	read_cff = |bytes, tables, glyphs, cff_axes| {
		var $prepared = Absent
		var $problems = []
		for entry in [{ tag: "CFF ", version: Cff1 }, { tag: "CFF2", version: Cff2 }] {
			match Sfnt.located(bytes, tables, entry.tag, 0) {
				Missing => {}
				Bad(at) => {
					$problems = $problems.append(Sfnt.bad(entry.tag, at))
				}
				Found(found) => match TableCff.read(found.data, glyphs, cff_axes, entry.version) {
					Ok(value) => {
						$prepared = Present(value)
					}
					Err(Bad(problem)) => {
						$problems = $problems.append(Sfnt.bad(entry.tag, found.offset + problem.offset))
					}
					Err(OverLimit(bound)) => {
						$problems = $problems.append(OverLimit(bound))
					}
				}
			}
		}
		{ prepared: $prepared, problems: $problems }
	}

	## Validate the optional vertical metric pair as one usable unit. A
	## missing dependency is reported, never supplied by repairing bytes.
	read_vertical : List(U8), List(Sfnt.Table), U64 -> { header : [Present(TableVhea.Header), Absent], advances : List(U16), bearings : List(I16), problems : List(Problem) }
	read_vertical = |bytes, tables, glyphs| {
		none = { header: Absent, advances: [], bearings: [], problems: [] }
		header = TableVhea.from_tables(bytes, tables)
		match header {
			Err(problem) => { ..none, problems: [problem] }
			Ok(Absent) => if (tables.any(|t| t.tag == 0x766D7478)) { ..none, problems: [MissingTable("vhea")] } else none
			Ok(Present(h)) => match TableVmtx.from_tables(bytes, tables, h.metric_count, glyphs) {
				Err(problem) => { ..none, problems: [problem] }
				Ok(m) => { header: Present(h), advances: m.advances, bearings: m.bearings, problems: [] }
			}
		}
	}

	## Positive vertical pen distance. Without vertical metrics, synthesize
	## it from horizontal font extents, as the OpenType reference does.
	vertical_advance : Face, Location, U64 -> I64
	vertical_advance = |face, loc, id| {
		if id >= face.glyph_count {
			return 0
		}
		match face.v_advances.get(id) {
			Ok(advance) => match face.vvar {
				# The metric accelerator defines a negative varied advance
				# as zero (HarfBuzz hb-ot-hmtx-table.hh); I32 bounds keep the
				# font-unit public position representation finite.
				Present(v) if loc.varied => (advance.to_i64() + TableVvar.advance_delta(v, loc.vvar, id)).max(0).min(2147483648)
				_ if loc.varied => match face.outlines {
					Present(o) => {
						p = TableGvar.phantoms(o.points, o.gvar, loc.gvar, id)
						TableVar.f32_round_half_up(TableVar.f32_sub(p.top, p.bottom)).max(0).min(2147483648)
					}
					Absent => advance.to_i64()
				}
				_ => advance.to_i64()
			}
			Err(_) => {
				m = Face.metrics(face, loc)
				(m.ascent.to_i64() + m.descent.to_i64())
			}
		}
	}

	## Origin relative to the horizontal baseline. OpenType VORG applies
	## to CFF/CFF2; TrueType uses its top bearing and outline instead.
	vertical_origin : Face, Location, U64 -> { x : I32, y : I32 }
	vertical_origin = |face, loc, id| {
		if id >= face.glyph_count {
			return { x: 0, y: 0 }
		}
		x = Face.advance(face, loc, id) // 2
		if face.has_glyf and loc.varied and !face.v_bearings.is_empty() {
			match face.outlines {
				Present(o) => {
					p = TableGvar.phantoms(o.points, o.gvar, loc.gvar, id)
					return { x, y: TableVar.f32_round_half_up(p.top).max(-2147483648).min(2147483647).to_i32_wrap() }
				}
				Absent => {}
			}
		}
		if !face.has_glyf {
			match face.vorg {
				Present(v) => {
					base = TableVorg.origin(v, id).to_i64()
					delta = match face.vvar {
						Present(vv) if loc.varied => TableVvar.origin_delta(vv, loc.vvar, id)
						_ => 0
					}
					return { x, y: (base + delta).max(-2147483648).min(2147483647).to_i32_wrap() }
				}
				Absent => {}
			}
		}
		located_face = { ..face, location: loc }
		y = match Face.extents(located_face, id) {
			Extents(box) => match face.v_bearings.get(id) {
				Ok(bearing) if face.has_glyf => box.y_max.to_i64() + bearing.to_i64()
				_ => {
					# With no applicable top bearing, the reference centers in
					# the horizontal font extents, independently of vmtx.
					metrics = Face.metrics(face, loc)
					remaining = metrics.ascent.to_i64() + metrics.descent.to_i64() - (box.y_max.to_i64() - box.y_min.to_i64())
					# Arithmetic shift gives floor division for a negative odd gap.
					box.y_max.to_i64() + remaining.shr_wrap(1)
				}
			}
			Empty => match face.v_bearings.get(id) {
				Ok(bearing) if face.has_glyf => bearing.to_i64()
				_ => {
					metrics = Face.metrics(face, loc)
					(metrics.ascent.to_i64() + metrics.descent.to_i64()).shr_wrap(1)
				}
			}
			Unknown => Face.metrics(face, loc).ascent.to_i64()
		}
		{ x, y: y.max(-2147483648).min(2147483647).to_i32_wrap() }
	}

	## A glyph's advance at a location: `hmtx`, plus the `HVAR` delta away
	## from the default location. Past the font: 0, as HarfBuzz.
	advance : Face, Location, U64 -> I32
	advance = |face, loc, id|
		match face.advances.get(id) {
			Err(_) => 0
			Ok(base) =>
				match face.hvar {
					Present(hvar) if loc.varied => TableVar.advance(hvar, loc.hvar, id, base.to_i64()).to_i32_wrap()
					_ if loc.varied => match face.outlines {
						Present(o) => TableGvar.advance(o.points, o.gvar, loc.gvar, id).to_i32_wrap()
						Absent => base.to_i32()
					}
					_ => base.to_i32()
				}
		}

	## A glyph's bounding box at the face's location, or `Empty`, as
	## HarfBuzz reports it. At the default location (and in a font without
	## `gvar`) it is the glyph header's box (`TableGlyf`); elsewhere the
	## outline's points are moved by `gvar` and measured (`TableGvar`).
	## `Unknown` for a glyph of a font without `glyf` outlines (CFF, CFF2
	## or bitmaps, which roc-font does not read); a glyph id past the font
	## is `Empty` in every font.
	extents : Face, U64 -> [Extents({ x_min : I32, y_min : I32, x_max : I32, y_max : I32 }), Empty, Unknown]
	extents = |face, id|
		match face.outlines {
			Present(o) if face.location.varied => {
				e = TableGvar.extents(o.points, o.gvar, face.location.gvar, id)
				if e.width == 0 and e.height == 0 and e.x_bearing == 0 and e.y_bearing == 0 {
					Empty
				} else {
					clamp = |v| v.max(-2147483648).min(2147483647).to_i32_wrap()
					Extents({ x_min: clamp(e.x_bearing), y_min: clamp(e.y_bearing + e.height), x_max: clamp(e.x_bearing + e.width), y_max: clamp(e.y_bearing) })
				}
			}
			_ =>
				match face.boxes.get(id) {
					Ok(b) if b.x_min <= b.x_max and b.y_min <= b.y_max => Extents({ x_min: b.x_min, y_min: b.y_min, x_max: b.x_max, y_max: b.y_max })
					Ok(_) if !face.has_glyf => match face.cff {
						Present(prepared) => TableCff.extents(prepared, face.location.cff, id)
						Absent => Unknown
					}
					_ => Empty
				}
		}

	tag : Str -> U32
	tag = |name| name.to_utf8().fold(0, |acc, b| acc * 256 + b.to_u32())

	# A metric at a location: `MVAR`'s delta for `tag` added to the stored
	# value, rounded as HarfBuzz rounds it.
	varied : Face, Location, Str, I32 -> I32
	varied = |face, loc, name, value|
		match face.mvar {
			Present(mvar) if loc.varied => TableVar.metric(mvar, loc.mvar, Face.tag(name), value.to_i64()).to_i32_wrap()
			_ => value
		}

	metrics : Face, Location -> Metrics
	metrics = |face, loc| {
		v = |name, value| Face.varied(face, loc, name, value)
		hh = face.hhea
		upem = face.units_per_em.to_i32()
		vertical = match face.os2 {
			Present(o) if o.use_typo => { ascent: v("hasc", o.typo_ascent), descent: -v("hdsc", o.typo_descent), line_gap: v("hlgp", o.typo_line_gap) }
			_ if hh.ascent != 0 or hh.descent != 0 => { ascent: v("hasc", hh.ascent), descent: -v("hdsc", hh.descent), line_gap: v("hlgp", hh.line_gap) }
			Present(o) if o.typo_ascent != 0 or o.typo_descent != 0 => { ascent: v("hasc", o.typo_ascent), descent: -v("hdsc", o.typo_descent), line_gap: v("hlgp", o.typo_line_gap) }
			Present(o) => { ascent: v("hcla", o.win_ascent), descent: v("hcld", o.win_descent), line_gap: 0 }
			Absent => { ascent: 0, descent: 0, line_gap: 0 }
		}
		# HarfBuzz's fallbacks for heights the font does not store.
		box_of = |code_point|
			match Face.glyph(face, code_point) {
				Err(_) => NoGlyph
				Ok(g) =>
					match Face.extents(face, g) {
						Extents(b) => Box(b)
						# HarfBuzz reads CFF boxes; roc-font, which does not,
						# takes a zero box, as for a glyph that draws nothing.
						Empty | Unknown => Box({ x_min: 0, y_min: 0, x_max: 0, y_max: 0 })
					}
			}
		stored = match face.os2 {
			Present(o) => o.heights
			Absent => Absent
		}
		heights = match stored {
			Present(h) => { x_height: v("xhgt", h.x_height), cap_height: v("cpht", h.cap_height) }
			Absent => {
				x_height: match box_of('x') {
					Box(b) => b.y_max
					NoGlyph => upem // 2
				},
				cap_height: match box_of('O') {
					Box(b) => b.y_max + b.y_min
					NoGlyph => upem * 2 // 3
				},
			}
		}
		strikeout = match face.os2 {
			Present(o) => { position: v("stro", o.strikeout_position), thickness: v("strs", o.strikeout_size) }
			Absent => { position: vertical.ascent // 2, thickness: upem // 18 }
		}
		line = TablePost.underline(face.post)
		{
			ascent: vertical.ascent,
			descent: vertical.descent,
			line_gap: vertical.line_gap,
			cap_height: heights.cap_height,
			x_height: heights.x_height,
			underline: { position: v("undo", line.position), thickness: v("unds", line.thickness) },
			strikeout,
		}
	}

	family_name : Face -> Try(Str, [Missing])
	family_name = |face| TableName.family_name(face.name)

	name : Face, U16 -> Try(Str, [Missing])
	name = |face, id| TableName.string(face.name, id.to_u64())

	outline : Face, U64 -> [Outline(List(TableOutline.Command)), Unknown]
	outline = |face, id| match face.outlines {
		Present(o) => Outline(TableOutline.commands(o.points, o.gvar, face.location.gvar, id))
		Absent => if id >= face.glyph_count {
			Outline([])
		} else {
			match face.cff {
				Present(prepared) => Outline(TableCff.commands(prepared, face.location.cff, id))
				Absent => Unknown
			}
		}
	}

	ligature_carets : Face, U64 -> List([Position(F64), Unavailable])
	ligature_carets = |face, id| TableCaret.positions(face.carets, id, face.layout_var, LayoutVar.location(face.layout_var, face.location.coords), face.outlines, face.location.gvar)

	glyph_name : Face, U64 -> Try(Str, [Missing])
	glyph_name = |face, id| if (id > 0xFFFFFFFF) Err(Missing) else TablePost.glyph_name(face.post, id.to_u32_wrap())

	## The feature tags the font's `GSUB` and `GPOS` feature lists name, in
	## increasing order without repeats, with `kern` when the font has a
	## legacy `kern` table shaping applies. A layout table left out when
	## reading (over `max_lookups`) names none.
	feature_tags : Face -> List(U64)
	feature_tags = |face| {
		gsub = LayoutGsub.common_of(face.gsub)
		gpos = LayoutKerning.common_of(face.kerning)
		var $tags = List.with_capacity(gsub.feature_count + gpos.feature_count + 1)
		for i in 0..<gsub.feature_count {
			$tags = $tags.append(LayoutCommon.feature_tag(gsub, i))
		}
		for i in 0..<gpos.feature_count {
			$tags = $tags.append(LayoutCommon.feature_tag(gpos, i))
		}
		if LayoutKerning.has_kern(face.kerning) {
			$tags = $tags.append(Face.tag("kern").to_u64())
		}
		match face.aat {
			Present(_) => {
				$tags = $tags.concat(AatFeatureSelect.tags(face.aat_features))
			}
			Absent => {}
		}
		Sorted.unique($tags)
	}

	gsub : Face -> LayoutGsub
	gsub = |face| face.gsub

	## The face's character map, checked when the face was read.
	cmap : Face -> TableCmap
	cmap = |face| face.cmap

	## The face's `GDEF` glyph classes, mark attachment classes and mark
	## glyph sets, as lookup flags use them (`LayoutGdef.none` without a
	## `GDEF`, or for one HarfBuzz would drop).
	gdef : Face -> LayoutGdef
	gdef = |face| face.gdef

	kerning : Face -> LayoutKerning
	kerning = |face| face.kerning

	max_depth : Face -> U64
	max_depth = |face| face.max_depth
}
