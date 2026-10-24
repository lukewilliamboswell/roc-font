## Small synthetic font files for tests and fuzz targets: big-endian
## fields, tables whose offsets are worked out from the sizes of their
## parts, and a complete minimal font. Nothing here reads fonts or imports
## roc-font; it only builds bytes, which the tests hand to the public
## `Font` API. Test-only: the `tests/support` package is never reached from
## `package/main.roc`, so it is not part of the published package.
FontBuild :: {}.{

	## A field of a table under construction. `Ref` and `Ref32` write a 16- or
	## 32-bit offset to a child table, which is placed after the fields in the
	## order the references appear; offsets count from the start of the table.
	Field : [U16(U64), I16(I64), U32(U64), Tag(Str), Ref(List(U8)), Ref32(List(U8)), Raw(List(U8))]

	u16 : U64 -> List(U8)
	u16 = |v| [v.shr_zf_wrap(8).bitwise_and(0xFF).to_u8_wrap(), v.bitwise_and(0xFF).to_u8_wrap()]

	u32 : U64 -> List(U8)
	u32 = |v| FontBuild.u16(v.shr_zf_wrap(16).bitwise_and(0xFFFF)).concat(FontBuild.u16(v.bitwise_and(0xFFFF)))

	i16 : I64 -> List(U8)
	i16 = |v| FontBuild.u16((if (v < 0) v + 65536 else v).to_u64_wrap())

	size : Field -> U64
	size = |field|
		match field {
			U16(_) => 2
			I16(_) => 2
			Ref(_) => 2
			U32(_) => 4
			Tag(_) => 4
			Ref32(_) => 4
			Raw(bytes) => bytes.len()
		}

	## Lay out fields, then the tables they refer to.
	pack : List(Field) -> List(U8)
	pack = |fields| {
		var $head = []
		var $tail = []
		var $next = fields.fold(0, |sum, f| sum + FontBuild.size(f))
		for field in fields {
			match field {
				U16(v) => {
					$head = $head.concat(FontBuild.u16(v))
				}
				I16(v) => {
					$head = $head.concat(FontBuild.i16(v))
				}
				U32(v) => {
					$head = $head.concat(FontBuild.u32(v))
				}
				Tag(name) => {
					$head = $head.concat(name.to_utf8().concat([' ', ' ', ' ', ' ']).take_first(4))
				}
				Raw(bytes) => {
					$head = $head.concat(bytes)
				}
				Ref(child) => {
					$head = $head.concat(FontBuild.u16($next))
					$tail = $tail.concat(child)
					$next = $next + child.len()
				}
				Ref32(child) => {
					$head = $head.concat(FontBuild.u32($next))
					$tail = $tail.concat(child)
					$next = $next + child.len()
				}
			}
		}
		$head.concat($tail)
	}

	## A font file holding the given tables, each aligned to four bytes.
	file : List({ tag : Str, data : List(U8) }) -> List(U8)
	file = |tables| {
		count = tables.len()
		var $records = []
		var $body = []
		var $offset = 12 + 16 * count
		for t in tables {
			$records = $records.concat(t.tag.to_utf8().concat([' ', ' ', ' ', ' ']).take_first(4)).concat(FontBuild.u32(0)).concat(FontBuild.u32($offset)).concat(FontBuild.u32(t.data.len()))
			padding = (4 - t.data.len() % 4) % 4
			$body = $body.concat(t.data).concat(List.repeat(0, padding))
			$offset = $offset + t.data.len() + padding
		}
		FontBuild.u32(0x00010000).concat(FontBuild.u16(count)).concat(FontBuild.u16(0)).concat(FontBuild.u16(0)).concat(FontBuild.u16(0)).concat($records).concat($body)
	}

	## A font collection (`ttcf`) of fonts, each given as its tables. Each
	## face keeps its own copy of its tables; table offsets count from the
	## start of the collection, as the format requires.
	collection : List(List({ tag : Str, data : List(U8) })) -> List(U8)
	collection = |faces| {
		files = faces.map(FontBuild.file)
		header = 12 + 4 * files.len()
		var $offsets = []
		var $body = []
		for f in files {
			base = header + $body.len()
			$offsets = $offsets.append(base)
			# Move each table record's offset (at 12 + 16 i + 8) by the base.
			count = (f.get(4) ?? 0).to_u64() * 256 + (f.get(5) ?? 0).to_u64()
			var $moved = f
			for i in 0..<count {
				at = 12 + 16 * i + 8
				old = $moved.sublist({ start: at, len: 4 }).fold(0, |acc, b| acc * 256 + b.to_u64())
				$moved = FontBuild.patch($moved, at, FontBuild.u32(old + base))
			}
			$body = $body.concat($moved)
		}
		"ttcf".to_utf8().concat(FontBuild.u32(0x00010000)).concat(FontBuild.u32(files.len())).concat($offsets.join_map(FontBuild.u32)).concat($body)
	}

	## A `head` table: 54 bytes with units per em at 18 and the `loca` format
	## at 50, version 1.0 and the magic number OTS requires; other fields
	## are zero.
	head : U64, Bool -> List(U8)
	head = |units, long_loca|
		FontBuild.u32(0x00010000)
			.concat(List.repeat(0, 8))
			.concat(FontBuild.u32(0x5F0F3CF5))
			.concat(FontBuild.u16(0))
			.concat(FontBuild.u16(units))
			.concat(List.repeat(0, 30))
			.concat(FontBuild.u16(if (long_loca) 1 else 0))
			.concat(FontBuild.u16(0))

	## An `hhea` table: ascent, descent (negative below the baseline) and the
	## number of long metrics.
	hhea : I64, I64, U64 -> List(U8)
	hhea = |ascent, descent, metrics|
		FontBuild.u32(0x00010000).concat(FontBuild.i16(ascent)).concat(FontBuild.i16(descent)).concat(List.repeat(0, 26)).concat(FontBuild.u16(metrics))

	maxp : U64 -> List(U8)
	maxp = |glyphs| FontBuild.u32(0x00005000).concat(FontBuild.u16(glyphs))

	## An `OS/2` table with the vertical metrics `Font` reads.
	os2 : { use_typo : Bool, typo_ascent : I64, typo_descent : I64, win_ascent : U64, win_descent : U64 } -> List(U8)
	os2 = |o|
		List.repeat(0, 62)
			.concat(FontBuild.u16(if (o.use_typo) 0x80 else 0))
			.concat(List.repeat(0, 4))
			.concat(FontBuild.i16(o.typo_ascent))
			.concat(FontBuild.i16(o.typo_descent))
			.concat(FontBuild.u16(0))
			.concat(FontBuild.u16(o.win_ascent))
			.concat(FontBuild.u16(o.win_descent))
			.concat(List.repeat(0, 8))

	## Long horizontal metrics: an advance and a zero left side bearing each.
	hmtx : List(U64) -> List(U8)
	hmtx = |advances| advances.fold([], |acc, a| acc.concat(FontBuild.u16(a)).concat(FontBuild.u16(0)))

	## A `cmap` table with the given encoding records (platform as `system`, encoding,
	## subtable).
	cmap : List({ system : U64, encoding : U64, subtable : List(U8) }) -> List(U8)
	cmap = |records|
		FontBuild.pack(
			[U16(0), U16(records.len())].concat(records.join_map(|r| [U16(r.system), U16(r.encoding), Ref32(r.subtable)])),
		)

	## A format 4 subtable. Each segment maps by `delta`, or, when `glyphs` is
	## not empty, through its own glyph array (one entry per character). The
	## required final 0xFFFF segment is added.
	cmap4 : List({ first : U64, last : U64, delta : U64, glyphs : List(U64) }) -> List(U8)
	cmap4 = |segments| {
		all = segments.append({ first: 0xFFFF, last: 0xFFFF, delta: 1, glyphs: [] })
		n = all.len()
		# Glyph arrays follow the range offsets; an offset counts from its own
		# position.
		var $offsets = []
		var $array = []
		for s in 0..<n {
			seg = all.get(s) ?? { first: 0, last: 0, delta: 0, glyphs: [] }
			if seg.glyphs.is_empty() {
				$offsets = $offsets.append(0)
			} else {
				$offsets = $offsets.append(2 * (n - s) + $array.len())
				$array = $array.concat(seg.glyphs.join_map(FontBuild.u16))
			}
		}
		# The binary search fields, as OTS requires them: the largest power
		# of two not above the segment count, its log, and the rest.
		var $log = 0
		while (2.U64).shl_wrap($log.to_u8_wrap()) <= n {
			$log = $log + 1
		}
		search = (2.U64).shl_wrap($log.to_u8_wrap())
		body = FontBuild.u16(2 * n)
			.concat(FontBuild.u16(search))
			.concat(FontBuild.u16($log))
			.concat(FontBuild.u16(2 * n - search))
			.concat(all.join_map(|seg| FontBuild.u16(seg.last)))
			.concat(FontBuild.u16(0))
			.concat(all.join_map(|seg| FontBuild.u16(seg.first)))
			.concat(all.join_map(|seg| FontBuild.u16(seg.delta)))
			.concat($offsets.join_map(FontBuild.u16))
			.concat($array)
		FontBuild.u16(4).concat(FontBuild.u16(body.len() + 6)).concat(FontBuild.u16(0)).concat(body)
	}

	## A format 12 subtable of groups (first, last, first glyph).
	cmap12 : List({ first : U64, last : U64, glyph : U64 }) -> List(U8)
	cmap12 = |groups|
		FontBuild.u16(12)
			.concat(FontBuild.u16(0))
			.concat(FontBuild.u32(16 + 12 * groups.len()))
			.concat(FontBuild.u32(0))
			.concat(FontBuild.u32(groups.len()))
			.concat(groups.join_map(|g| FontBuild.u32(g.first).concat(FontBuild.u32(g.last)).concat(FontBuild.u32(g.glyph))))

	## A format 13 subtable of groups (first, last, the one glyph they all
	## map to).
	cmap13 : List({ first : U64, last : U64, glyph : U64 }) -> List(U8)
	cmap13 = |groups| FontBuild.u16(13).concat(FontBuild.cmap12(groups).drop_first(2))

	## A format 0 subtable: the glyphs of character codes 0 up to 255, in
	## order; codes past the list map to glyph 0.
	cmap0 : List(U64) -> List(U8)
	cmap0 = |glyphs|
		FontBuild.u16(0)
			.concat(FontBuild.u16(262))
			.concat(FontBuild.u16(0))
			.concat(glyphs.take_first(256).map(|g| g.to_u8_wrap()))
			.concat(List.repeat(0, 256 - glyphs.len().min(256)))

	## A format 6 subtable: consecutive character codes from `first`.
	cmap6 : U64, List(U64) -> List(U8)
	cmap6 = |first, glyphs|
		FontBuild.u16(6)
			.concat(FontBuild.u16(10 + 2 * glyphs.len()))
			.concat(FontBuild.u16(0))
			.concat(FontBuild.u16(first))
			.concat(FontBuild.u16(glyphs.len()))
			.concat(glyphs.join_map(FontBuild.u16))

	## A format 10 subtable: consecutive character codes from `first`.
	cmap10 : U64, List(U64) -> List(U8)
	cmap10 = |first, glyphs|
		FontBuild.u16(10)
			.concat(FontBuild.u16(0))
			.concat(FontBuild.u32(20 + 2 * glyphs.len()))
			.concat(FontBuild.u32(0))
			.concat(FontBuild.u32(first))
			.concat(FontBuild.u32(glyphs.len()))
			.concat(glyphs.join_map(FontBuild.u16))

	## A version 0 `OS/2` table (78 bytes) whose `fsSelection` holds a
	## Windows 3.1 font page in its high byte; other fields are zero.
	os2_page : U64 -> List(U8)
	os2_page = |page| FontBuild.patch(List.repeat(0, 78), 62, FontBuild.u16(page))

	## The tables of a minimal valid font with four glyphs: glyph 0 (the
	## missing glyph), 1 for `A`, 2 for `B`, 3 for `C`, advances 500, 600,
	## 700 and 800, 1000 units per em. Tests replace or add tables.
	basic : List({ tag : Str, data : List(U8) })
	basic = [
		{ tag: "head", data: FontBuild.head(1000, False) },
		{ tag: "hhea", data: FontBuild.hhea(800, -200, 4) },
		{ tag: "maxp", data: FontBuild.maxp(4) },
		{ tag: "hmtx", data: FontBuild.hmtx([500, 600, 700, 800]) },
		{ tag: "cmap", data: FontBuild.cmap([{ system: 3, encoding: 1, subtable: FontBuild.cmap4([{ first: 'A', last: 'C', delta: 65536 - 64, glyphs: [] }]) }]) },
	]

	## `basic` with a table added or replaced.
	replace : List({ tag : Str, data : List(U8) }), Str, List(U8) -> List({ tag : Str, data : List(U8) })
	replace = |tables, tag, data|
		tables.drop_if(|t| t.tag == tag).append({ tag, data })

	## `basic` without a table.
	without : List({ tag : Str, data : List(U8) }), Str -> List({ tag : Str, data : List(U8) })
	without = |tables, tag| tables.drop_if(|t| t.tag == tag)

	# ------------------------------------------------------------ layout tables

	## A coverage table of format 1 (a sorted glyph list).
	coverage1 : List(U64) -> List(U8)
	coverage1 = |glyphs| FontBuild.pack([U16(1), U16(glyphs.len())].concat(glyphs.map(|g| U16(g))))

	## A coverage table of format 2 (ranges first, last, first coverage index).
	coverage2 : List({ first : U64, last : U64, index : U64 }) -> List(U8)
	coverage2 = |ranges| FontBuild.pack([U16(2), U16(ranges.len())].concat(ranges.join_map(|r| [U16(r.first), U16(r.last), U16(r.index)])))

	## A class definition of format 1: classes of consecutive glyphs from
	## `start`.
	classes1 : U64, List(U64) -> List(U8)
	classes1 = |start, classes| FontBuild.pack([U16(1), U16(start), U16(classes.len())].concat(classes.map(|c| U16(c))))

	## A class definition of format 2: ranges first, last, class.
	classes2 : List({ first : U64, last : U64, class : U64 }) -> List(U8)
	classes2 = |ranges| FontBuild.pack([U16(2), U16(ranges.len())].concat(ranges.join_map(|r| [U16(r.first), U16(r.last), U16(r.class)])))

	## A `GSUB` or `GPOS` table: one script (`latn` or `DFLT`) whose default
	## language lists every feature, the features (tag and lookup indices),
	## and the lookups (type and subtables).
	layout : Str, List({ tag : Str, lookups : List(U64) }), List({ kind : U64, subtables : List(List(U8)) }) -> List(U8)
	layout = |script, features, lookups| FontBuild.layout_listing(script, FontBuild.counting(features.len()), 0xFFFF, features, lookups)

	## `layout` whose default language lists only some features (by index),
	## plus a required feature (0xFFFF for none).
	layout_listing : Str, List(U64), U64, List({ tag : Str, lookups : List(U64) }), List({ kind : U64, subtables : List(List(U8)) }) -> List(U8)
	layout_listing = |script, listed, required, features, lookups| {
		language = FontBuild.pack([U16(0), U16(required), U16(listed.len())].concat(listed.map(|i| U16(i))))
		scripts = FontBuild.pack([U16(1), Tag(script), Ref(FontBuild.pack([Ref(language), U16(0)]))])
		feature_list = FontBuild.pack(
			[U16(features.len())].concat(features.join_map(|f| [Tag(f.tag), Ref(FontBuild.pack([U16(0), U16(f.lookups.len())].concat(f.lookups.map(|l| U16(l)))))])),
		)
		lookup_list = FontBuild.pack(
			[U16(lookups.len())].concat(lookups.map(|l| Ref(FontBuild.pack([U16(l.kind), U16(0), U16(l.subtables.len())].concat(l.subtables.map(|s| Ref(s))))))),
		)
		FontBuild.pack([U32(0x00010000), Ref(scripts), Ref(feature_list), Ref(lookup_list)])
	}

	## An extension subtable (format 1) wrapping a subtable of `kind`.
	extension : U64, List(U8) -> List(U8)
	extension = |kind, subtable| FontBuild.pack([U16(1), U16(kind), Ref32(subtable)])

	## A pair adjustment subtable of format 1: each covered first glyph (in
	## increasing order) with its pairs, a second glyph and the fields of both
	## value records.
	pair1 : U64, U64, List({ glyph : U64, pairs : List({ second : U64, values : List(I64) }) }) -> List(U8)
	pair1 = |format1, format2, sets| {
		set_tables = sets.map(|s| Ref(FontBuild.pack([U16(s.pairs.len())].concat(s.pairs.join_map(|p| [U16(p.second)].concat(p.values.map(|v| I16(v))))))))
		FontBuild.pack([U16(1), Ref(FontBuild.coverage1(sets.map(|s| s.glyph))), U16(format1), U16(format2), U16(sets.len())].concat(set_tables))
	}

	## A pair adjustment subtable of format 2: coverage, the two class
	## definitions, the class counts and the fields of every cell, row by row.
	pair2 : U64, U64, List(U8), List(U8), List(U8), U64, U64, List(I64) -> List(U8)
	pair2 = |format1, format2, coverage, class1, class2, height, width, values|
		FontBuild.pack([U16(2), Ref(coverage), U16(format1), U16(format2), Ref(class1), Ref(class2), U16(height), U16(width)].concat(values.map(|v| I16(v))))

	## A TrueType `kern` table of format 0 subtables, each with its coverage
	## field (1 for horizontal kerning) and pairs in the order given, and its
	## binary search fields (`searchRange`, `entrySelector`, `rangeShift`)
	## filled in as the format defines them: OTS, and so lenient reading,
	## rejects a font whose `entrySelector` is wrong.
	kern : List({ coverage : U64, pairs : List({ left : U64, right : U64, value : I64 }) }) -> List(U8)
	kern = |subtables| {
		body = subtables.join_map(
			|s| {
				n = s.pairs.len()
				var $power = 0
				while (1.U64).shl_wrap(($power + 1).to_u8_wrap()) <= n {
					$power = $power + 1
				}
				range = 6 * (1.U64).shl_wrap($power.to_u8_wrap())
				FontBuild.pack([U16(0), U16(14 + 6 * n), U16(s.coverage), U16(n), U16(range), U16($power), U16(6 * n - range.min(6 * n))].concat(s.pairs.join_map(|p| [U16(p.left), U16(p.right), I16(p.value)])))
			},
		)
		FontBuild.u16(0).concat(FontBuild.u16(subtables.len())).concat(body)
	}

	## A TrueType glyph header with the given horizontal extent.
	outline : I64, I64 -> List(U8)
	outline = |left, right|
		# One contour of one on-curve point at (left, 0), with the header box
		# given: a glyph OTS accepts (flags 0x01: on curve, word deltas), padded
		# to an even length for short `loca` offsets.
		FontBuild.pack([I16(1), I16(left), I16(0), I16(right), I16(100), U16(0), U16(0)]).concat([0x01]).concat(FontBuild.i16(left)).concat(FontBuild.i16(0)).concat([0])

	## A glyph OTS accepts with the given header box: one contour of one
	## on-curve point at (x_min, y_min), padded to an even length.
	boxed : I64, I64, I64, I64 -> List(U8)
	boxed = |x_min, y_min, x_max, y_max|
		FontBuild.pack([I16(1), I16(x_min), I16(y_min), I16(x_max), I16(y_max), U16(0), U16(0)]).concat([0x01]).concat(FontBuild.i16(x_min)).concat(FontBuild.i16(y_min)).concat([0])

	## `loca` and `glyf` tables for glyphs given as their bytes (empty for a
	## glyph without an outline), with short or long offsets.
	outlines : List(List(U8)), Bool -> { loca : List(U8), glyf : List(U8) }
	outlines = |glyphs, long| {
		var $loca = []
		var $at = 0
		for g in glyphs {
			$loca = $loca.concat(if (long) FontBuild.u32($at) else FontBuild.u16($at // 2))
			$at = $at + g.len()
		}
		$loca = $loca.concat(if (long) FontBuild.u32($at) else FontBuild.u16($at // 2))
		{ loca: $loca, glyf: glyphs.join_map(|g| g) }
	}

	## Bytes with some replaced from `at`.
	patch : List(U8), U64, List(U8) -> List(U8)
	patch = |bytes, at, replacement|
		bytes.take_first(at).concat(replacement).concat(bytes.drop_first(at + replacement.len()))

	# Single substitution, format 1: add `delta` to covered glyphs.
	single1 : List(U64), I64 -> List(U8)
	single1 = |glyphs, delta| FontBuild.pack([U16(1), Ref(FontBuild.coverage1(glyphs)), I16(delta)])

	# Single substitution, format 2: covered glyphs replaced in order.
	single2 : List(U64), List(U64) -> List(U8)
	single2 = |glyphs, replacements| FontBuild.pack([U16(2), Ref(FontBuild.coverage1(glyphs)), U16(replacements.len())].concat(replacements.map(|g| U16(g))))

	# Multiple substitution: each covered glyph by a sequence.
	multiple : List(U64), List(List(U64)) -> List(U8)
	multiple = |glyphs, sequences| FontBuild.pack([U16(1), Ref(FontBuild.coverage1(glyphs)), U16(sequences.len())].concat(sequences.map(|seq| Ref(FontBuild.pack([U16(seq.len())].concat(seq.map(|g| U16(g))))))))

	# Ligature substitution: per covered first glyph, its ligature_table (glyph and
	# the components after the first).
	ligature : List(U64), List(List({ glyph : U64, rest : List(U64) })) -> List(U8)
	ligature = |glyphs, sets| {
		set_tables = sets.map(|set| Ref(FontBuild.pack([U16(set.len())].concat(set.map(|lig| Ref(FontBuild.pack([U16(lig.glyph), U16(lig.rest.len() + 1)].concat(lig.rest.map(|g| U16(g))))))))))
		FontBuild.pack([U16(1), Ref(FontBuild.coverage1(glyphs)), U16(sets.len())].concat(set_tables))
	}

	records : List({ at : U64, lookup : U64 }) -> List(Field)
	records = |list| list.join_map(|r| [U16(r.at), U16(r.lookup)])

	# A context rule of format 1 or 2: input after the first glyph (glyphs or
	# classes) and its lookup records.
	rule : List(U64), List({ at : U64, lookup : U64 }) -> List(U8)
	rule = |input, calls| FontBuild.pack([U16(input.len() + 1), U16(calls.len())].concat(input.map(|g| U16(g))).concat(FontBuild.records(calls)))

	# A chained rule of format 1 or 2.
	chain_rule : List(U64), List(U64), List(U64), List({ at : U64, lookup : U64 }) -> List(U8)
	chain_rule = |back, input, ahead, calls|
		FontBuild.pack(
			[U16(back.len())]
				.concat(back.map(|g| U16(g)))
				.concat([U16(input.len() + 1)])
				.concat(input.map(|g| U16(g)))
				.concat([U16(ahead.len())])
				.concat(ahead.map(|g| U16(g)))
				.concat([U16(calls.len())])
				.concat(FontBuild.records(calls)),
		)

	# A rule set (offsets to rules), or a null offset for a missing set.
	rule_set : List(List(U8)) -> Field
	rule_set = |rules| if (rules.is_empty()) U16(0) else Ref(FontBuild.pack([U16(rules.len())].concat(rules.map(|r| Ref(r)))))

	# Context substitution, format 1: rule sets per covered first glyph.
	context1 : List(U64), List(List(List(U8))) -> List(U8)
	context1 = |glyphs, sets| FontBuild.pack([U16(1), Ref(FontBuild.coverage1(glyphs)), U16(sets.len())].concat(sets.map(FontBuild.rule_set)))

	# Context substitution, format 2: rule sets per class of the first glyph.
	context2 : List(U64), List(U8), List(List(List(U8))) -> List(U8)
	context2 = |glyphs, classes, sets| FontBuild.pack([U16(2), Ref(FontBuild.coverage1(glyphs)), Ref(classes), U16(sets.len())].concat(sets.map(FontBuild.rule_set)))

	# Context substitution, format 3: a coverage per input position.
	context3 : List(List(U64)), List({ at : U64, lookup : U64 }) -> List(U8)
	context3 = |input, calls| FontBuild.pack([U16(3), U16(input.len()), U16(calls.len())].concat(input.map(|glyphs| Ref(FontBuild.coverage1(glyphs)))).concat(FontBuild.records(calls)))

	chain1 : List(U64), List(List(List(U8))) -> List(U8)
	chain1 = |glyphs, sets| FontBuild.pack([U16(1), Ref(FontBuild.coverage1(glyphs)), U16(sets.len())].concat(sets.map(FontBuild.rule_set)))

	chain2 : List(U64), List(U8), List(U8), List(U8), List(List(List(U8))) -> List(U8)
	chain2 = |glyphs, back, input, ahead, sets| FontBuild.pack([U16(2), Ref(FontBuild.coverage1(glyphs)), Ref(back), Ref(input), Ref(ahead), U16(sets.len())].concat(sets.map(FontBuild.rule_set)))

	chain3 : List(List(U64)), List(List(U64)), List(List(U64)), List({ at : U64, lookup : U64 }) -> List(U8)
	chain3 = |back, input, ahead, calls| {
		coverages = |list| [U16(list.len())].concat(list.map(|glyphs| Ref(FontBuild.coverage1(glyphs))))
		FontBuild.pack([U16(3)].concat(coverages(back)).concat(coverages(input)).concat(coverages(ahead)).concat([U16(calls.len())]).concat(FontBuild.records(calls)))
	}

	# ------------------------------------------------------------ whole fonts

	## A `GSUB` table with a lookup of every kind `LayoutGsub` reads: lookup
	## 0 (feature `calt`) is chained context of formats 3 and 2, calling
	## single substitutions (1), an extension holding a ligature (2), context
	## of formats 1 and 2 (3), which call a multiple substitution (4).
	every_lookup : List(U8)
	every_lookup = FontBuild.layout(
		"latn",
		[{ tag: "calt", lookups: [0] }],
		[
			{ kind: 6, subtables: [FontBuild.chain3([[7]], [[1], [2]], [[3]], [{ at: 0, lookup: 1 }, { at: 1, lookup: 2 }]), FontBuild.chain2([1], FontBuild.classes1(7, [1]), FontBuild.classes2([{ first: 1, last: 2, class: 1 }]), FontBuild.classes1(3, [1]), [[], [FontBuild.chain_rule([1], [1], [1], [{ at: 0, lookup: 3 }])]])] },
			{ kind: 1, subtables: [FontBuild.single1([1, 2], 10), FontBuild.single2([3], [30])] },
			{ kind: 7, subtables: [FontBuild.extension(4, FontBuild.ligature([1], [[{ glyph: 9, rest: [2] }]]))] },
			{ kind: 5, subtables: [FontBuild.context1([1], [[FontBuild.rule([2], [{ at: 0, lookup: 4 }])]]), FontBuild.context2([1], FontBuild.classes1(1, [1]), [[], [FontBuild.rule([0], [{ at: 1, lookup: 4 }])]])] },
			{ kind: 2, subtables: [FontBuild.multiple([1, 2], [[4, 5], []])] },
		],
	)

	## A `GPOS` table whose `kern` feature has pair adjustments of format 1,
	## format 2, and both behind extensions.
	every_pair : List(U8)
	every_pair = {
		pairs = FontBuild.pair1(4, 0, [{ glyph: 1, pairs: [{ second: 2, values: [-50] }, { second: 3, values: [-30] }] }, { glyph: 2, pairs: [{ second: 1, values: [20] }] }])
		classes = FontBuild.pair2(5, 4, FontBuild.coverage2([{ first: 1, last: 3, index: 0 }]), FontBuild.classes1(1, [0, 1, 1]), FontBuild.classes2([{ first: 2, last: 3, class: 1 }]), 2, 2, [0, 0, 0, 1, -11, 2, -22, 3, -33, 4, 0, 5])
		FontBuild.layout(
			"DFLT",
			[{ tag: "kern", lookups: [0, 1] }, { tag: "mark", lookups: [1] }],
			[{ kind: 2, subtables: [pairs, classes] }, { kind: 9, subtables: [FontBuild.extension(2, classes), FontBuild.extension(2, pairs)] }],
		)
	}

	## A complete font with 40 glyphs and every table `Font` reads: `A` to
	## `Z` are glyphs 1 to 26 (format 4 and format 12 character maps), with
	## outlines, typographic metrics, `GSUB` (`every_lookup`), `GPOS`
	## (`every_pair`) and a `kern` table that `GPOS` overrides.
	sample : List(U8)
	sample = {
		glyphs = FontBuild.counting(40).map(|g| if (g % 3 == 0) [] else FontBuild.outline(g.to_i64_wrap() - 5, 10 * g.to_i64_wrap()))
		boxes = FontBuild.outlines(glyphs, True)
		characters = FontBuild.cmap([
			{ system: 0, encoding: 3, subtable: FontBuild.cmap4([{ first: 'A', last: 'Z', delta: 65536 - 64, glyphs: [] }, { first: 'a', last: 'c', delta: 0, glyphs: [27, 0, 29] }]) },
			{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 'A', last: 'Z', glyph: 1 }, { first: 0x1F600, last: 0x1F600, glyph: 30 }]) },
			# Less preferred maps in the other formats, for mutations that
			# change which map is chosen.
			{ system: 0, encoding: 6, subtable: FontBuild.cmap13([{ first: 0x2190, last: 0x21FF, glyph: 31 }]) },
			{ system: 0, encoding: 4, subtable: FontBuild.cmap10(0x1F650, [32, 33]) },
			{ system: 1, encoding: 0, subtable: FontBuild.cmap0(List.repeat(0, 0x41).concat([1, 2, 3]).concat(List.repeat(0, 0x80 - 0x44)).concat([4])) },
			{ system: 1, encoding: 1, subtable: FontBuild.cmap6(0x41, [1, 0, 3]) },
		])
		FontBuild.file([
			{ tag: "head", data: FontBuild.head(2048, True) },
			{ tag: "hhea", data: FontBuild.hhea(1900, -500, 4) },
			{ tag: "maxp", data: FontBuild.maxp(40) },
			{ tag: "OS/2", data: FontBuild.os2({ use_typo: True, typo_ascent: 1800, typo_descent: -400, win_ascent: 2000, win_descent: 600 }) },
			{ tag: "hmtx", data: FontBuild.hmtx([1000, 1100, 1200, 1300]).concat(List.repeat(0, 72)) },
			{ tag: "cmap", data: characters },
			{ tag: "loca", data: boxes.loca },
			{ tag: "glyf", data: boxes.glyf },
			{ tag: "GSUB", data: FontBuild.every_lookup },
			{ tag: "GPOS", data: FontBuild.every_pair },
			{ tag: "kern", data: FontBuild.kern([{ coverage: 1, pairs: [{ left: 1, right: 2, value: -7 }] }]) },
		])
	}

	## `bytes` with patches applied: each group of four bytes of `patches`
	## names a position (three bytes, wrapped to the length) and its new
	## value.
	mutate : List(U8), List(U8) -> List(U8)
	mutate = |bytes, patches| {
		var $out = bytes
		var $k = 0
		while $k + 4 <= patches.len() and !$out.is_empty() {
			at = (patches.get($k) ?? 0).to_u64() * 65536 + (patches.get($k + 1) ?? 0).to_u64() * 256 + (patches.get($k + 2) ?? 0).to_u64()
			# The position is wrapped to the length, so it is in bounds.
			$out = $out.set(at % $out.len(), patches.get($k + 3) ?? 0) ?? []
			$k = $k + 4
		}
		$out
	}

	## The font file a fuzz input stands for. Inputs that start with a font
	## signature are the file itself, so a corpus can hold real fonts. Any
	## other input is a recipe: its first byte picks a base (`inter`, the
	## bytes of Inter; `sample`; `sample` cut short at a length from the next
	## two bytes; or no base, the rest of the input as it is) and the rest
	## patches it (see `mutate`), so most inputs are nearly valid fonts.
	fuzz_font : List(U8), List(U8) -> List(U8)
	fuzz_font = |bytes, inter| {
		signature = bytes.take_first(4)
		if signature == [0, 1, 0, 0] or signature == "true".to_utf8() or signature == "OTTO".to_utf8() or signature == "ttcf".to_utf8() {
			bytes
		} else {
			patches = bytes.drop_first(1)
			match (bytes.first() ?? 0) % 4 {
				0 => FontBuild.mutate(inter, patches)
				1 => FontBuild.mutate(FontBuild.sample, patches)
				2 => {
					cut = ((patches.get(0) ?? 0).to_u64() * 256 + (patches.get(1) ?? 0).to_u64()) % (FontBuild.sample.len() + 1)
					FontBuild.mutate(FontBuild.sample.take_first(cut), patches.drop_first(2))
				}
				_ => patches
			}
		}
	}

	## A font whose tables grow with `copies`: for each of up to 16 choice
	## bytes, `copies` items of the kind the byte picks (character map
	## entries, legacy kerning pairs, `GPOS` pair sets, `GPOS` class ranges,
	## ligatures, chained rules). The first byte also picks format 4 or 12
	## for the character map and whether `GPOS` replaces `kern`.
	scaled : List(U8), U64 -> List(U8)
	scaled = |choices, copies| {
		picks = choices.take_first(16)
		var $kinds = []
		for _ in 0..<copies {
			for b in picks {
				$kinds = $kinds.append(b.to_u64() % 6)
			}
		}
		items = $kinds.map_with_index(|kind, j| { kind, base: 8 + 4 * j })
		of_kind = |k| items.keep_if(|item| item.kind == k).map(|item| item.base)
		glyph_count = 16 + 4 * items.len()
		first = (picks.first() ?? 0).to_u64()
		mapped = of_kind(0)
		# Formats 12 and 13 need at least one group (OTS refuses none): U+F000
		# maps to glyph 1 when nothing else is mapped.
		groups = if (mapped.is_empty()) [{ first: 0xF000, last: 0xF000, glyph: 1 }] else mapped.map(|base| { first: 0x10000 + 2 * base, last: 0x10001 + 2 * base, glyph: base })
		subtable = if first % 2 == 0 {
			FontBuild.cmap4(mapped.map(|base| { first: 0x400 + 2 * base, last: 0x401 + 2 * base, delta: (65536 + base - (0x400 + 2 * base)) % 65536, glyphs: [] }))
		} else if first % 8 == 7 {
			FontBuild.cmap13(groups)
		} else {
			FontBuild.cmap12(groups)
		}
		legacy = FontBuild.kern([{ coverage: 1, pairs: of_kind(1).map(|base| { left: base, right: base + 1, value: -3 }) }])
		pair_sets = of_kind(2).map(|base| { glyph: base, pairs: [{ second: base + 1, values: [-1] }, { second: base + 2, values: [-2] }] })
		class_ranges = of_kind(3)
		classes = FontBuild.pair2(
			4,
			0,
			FontBuild.coverage2(class_ranges.map_with_index(|base, i| { first: base, last: base + 1, index: 2 * i })),
			FontBuild.classes2(class_ranges.map(|base| { first: base, last: base + 1, class: 1 })),
			FontBuild.classes2(class_ranges.map(|base| { first: base + 2, last: base + 3, class: 1 })),
			2,
			2,
			[0, 0, 0, -5],
		)
		gpos = FontBuild.layout("DFLT", [{ tag: "kern", lookups: [0] }], [{ kind: 2, subtables: [FontBuild.pair1(4, 0, pair_sets), classes] }])
		ligatures = of_kind(4)
		chained = of_kind(5)
		gsub = FontBuild.layout(
			"latn",
			[{ tag: "liga", lookups: [0, 1] }],
			[
				{ kind: 4, subtables: [FontBuild.ligature(ligatures, ligatures.map(|base| [{ glyph: base + 3, rest: [base + 1, base + 2] }]))] },
				{ kind: 6, subtables: [FontBuild.chain1(chained, chained.map(|base| [FontBuild.chain_rule([base + 3], [base + 1], [base + 2], [{ at: 0, lookup: 2 }])]))] },
				{ kind: 1, subtables: [FontBuild.single1(chained, 1)] },
			],
		)
		tables = [
			{ tag: "head", data: FontBuild.head(1000, False) },
			{ tag: "hhea", data: FontBuild.hhea(800, -200, glyph_count) },
			{ tag: "maxp", data: FontBuild.maxp(glyph_count) },
			{ tag: "hmtx", data: FontBuild.hmtx(FontBuild.counting(glyph_count).map(|g| 100 + g % 400)) },
			{ tag: "cmap", data: FontBuild.cmap([{ system: 3, encoding: if (first % 2 == 0) 1 else 10, subtable }]) },
			{ tag: "GSUB", data: gsub },
		]
		FontBuild.file(if (first % 4 < 2) tables.append({ tag: "GPOS", data: gpos }) else tables.append({ tag: "kern", data: legacy }))
	}

	counting : U64 -> List(U64)
	counting = |n| {
		var $out = []
		for i in 0..<n {
			$out = $out.append(i)
		}
		$out
	}

	# ------------------------------------------------------------ narrow fonts

	## A font of `advances.len()` glyphs (glyph `g` advancing by entry `g`,
	## 1000 units per em) with the given `cmap` table and further tables:
	## the smallest font that exercises one table or one lookup kind.
	glyphs_font : List(U64), List(U8), List({ tag : Str, data : List(U8) }) -> List(U8)
	glyphs_font = |advances, characters, extra| {
		count = advances.len()
		FontBuild.file(
			[
				{ tag: "head", data: FontBuild.head(1000, False) },
				{ tag: "hhea", data: FontBuild.hhea(800, -200, count) },
				{ tag: "maxp", data: FontBuild.maxp(count) },
				{ tag: "hmtx", data: FontBuild.hmtx(advances) },
				{ tag: "cmap", data: characters },
			].concat(extra),
		)
	}

	## Single substitution, format 1, over a coverage table given as bytes
	## (`coverage1` or `coverage2`): add `delta` to covered glyphs.
	single1_over : List(U8), I64 -> List(U8)
	single1_over = |coverage, delta| FontBuild.pack([U16(1), Ref(coverage), I16(delta)])

	## Single substitution, format 2, over a coverage table given as bytes:
	## the covered glyphs replaced in coverage order.
	single2_over : List(U8), List(U64) -> List(U8)
	single2_over = |coverage, replacements| FontBuild.pack([U16(2), Ref(coverage), U16(replacements.len())].concat(replacements.map(|g| U16(g))))

	## A TrueType `kern` table of one horizontal format 0 subtable (see
	## `kern`). Pairs are written in the order given (the format requires
	## increasing left, then right, glyph).
	kern_searchable : List({ left : U64, right : U64, value : I64 }) -> List(U8)
	kern_searchable = |pairs| FontBuild.kern([{ coverage: 1, pairs }])

	# ------------------------------------------------------------ variations

	## An `fvar` table (version 1.0) of axes, with no named instances. Axis
	## values are whole design units, written as 16.16 fixed-point numbers.
	fvar : List({ tag : Str, min : I64, default : I64, max : I64 }) -> List(U8)
	fvar = |axes| {
		fixed = |v| FontBuild.u32((if (v < 0) v * 65536 + 4294967296 else v * 65536).to_u64_wrap())
		header = FontBuild.u16(1).concat(FontBuild.u16(0)).concat(FontBuild.u16(16)).concat(FontBuild.u16(2)).concat(FontBuild.u16(axes.len())).concat(FontBuild.u16(20)).concat(FontBuild.u16(0)).concat(FontBuild.u16(4 * axes.len() + 4))
		header.concat(axes.join_map(|a| a.tag.to_utf8().concat([' ', ' ', ' ', ' ']).take_first(4).concat(fixed(a.min)).concat(fixed(a.default)).concat(fixed(a.max)).concat(FontBuild.u16(0)).concat(FontBuild.u16(256))))
	}

	## An `avar` table (version 1.0): one segment map per axis, each a list
	## of (from, to) pairs in F2Dot14 units (16384 is 1.0), written as given.
	avar : List(List({ from : I64, to : I64 })) -> List(U8)
	avar = |maps|
		FontBuild.u16(1)
			.concat(FontBuild.u16(0))
			.concat(FontBuild.u16(0))
			.concat(FontBuild.u16(maps.len()))
			.concat(maps.join_map(|m| FontBuild.u16(m.len()).concat(m.join_map(|p| FontBuild.i16(p.from).concat(FontBuild.i16(p.to))))))

	## An `ItemVariationStore` for `axis_count` axes: regions (per region,
	## one start, peak, end triple per axis, in F2Dot14 units) and data
	## subtables, each naming the regions its columns use and holding rows of
	## 16-bit deltas, one per column.
	variation_store : U64, List(List({ start : I64, peak : I64, end : I64 })), List({ regions : List(U64), rows : List(List(I64)) }) -> List(U8)
	variation_store = |axis_count, regions, subtables| {
		region_list = FontBuild.u16(axis_count).concat(FontBuild.u16(regions.len())).concat(regions.join_map(|r| r.join_map(|t| FontBuild.i16(t.start).concat(FontBuild.i16(t.peak)).concat(FontBuild.i16(t.end)))))
		data = |s| {
			columns = s.regions.len()
			FontBuild.u16(s.rows.len())
				.concat(FontBuild.u16(columns))
				.concat(FontBuild.u16(columns))
				.concat(s.regions.join_map(FontBuild.u16))
				.concat(s.rows.join_map(|row| row.concat(List.repeat(0, columns)).take_first(columns).join_map(FontBuild.i16)))
		}
		FontBuild.pack([U16(1), Ref32(region_list), U16(subtables.len())].concat(subtables.map(|s| Ref32(data(s)))))
	}

	## An `HVAR` table over a store. With no mapping, glyph `g` takes row `g`
	## of the store's first subtable; otherwise glyph `g` takes mapping entry
	## `g` (the last entry past the end), as a format 0 delta-set index map
	## with 32-bit entries.
	hvar : List(U8), List({ outer : U64, inner : U64 }) -> List(U8)
	hvar = |store, mapping| {
		map = FontBuild.u16(0x003F).concat(FontBuild.u16(mapping.len())).concat(mapping.join_map(|e| FontBuild.u16(e.outer).concat(FontBuild.u16(e.inner))))
		FontBuild.pack([U16(1), U16(0), Ref32(store), if (mapping.is_empty()) U32(0) else Ref32(map), U32(0), U32(0)])
	}

	## An `MVAR` table: value records (tag, delta-set outer and inner index),
	## which must come in increasing tag order, over a store.
	mvar : List(U8), List({ tag : Str, outer : U64, inner : U64 }) -> List(U8)
	mvar = |store, values|
		FontBuild.pack([U16(1), U16(0), U16(0), U16(8), U16(values.len()), Ref(store)].concat(values.join_map(|r| [Tag(r.tag), U16(r.outer), U16(r.inner)])))

	# ------------------------------------------------------------ lookup flags

	## The tables of a font with 64 glyphs, each 500 units wide (1000 units
	## per em): glyph g (from 1) draws U+10000 + g, the space draws glyph 3.
	sixty_four : List({ tag : Str, data : List(U8) })
	sixty_four = [
		{ tag: "head", data: FontBuild.head(1000, False) },
		{ tag: "hhea", data: FontBuild.hhea(800, -200, 64) },
		{ tag: "maxp", data: FontBuild.maxp(64) },
		{ tag: "hmtx", data: FontBuild.hmtx(List.repeat(500, 64)) },
		{ tag: "cmap", data: FontBuild.cmap([{ system: 3, encoding: 10, subtable: FontBuild.cmap12([{ first: 0x20, last: 0x20, glyph: 3 }, { first: 0x10001, last: 0x1003F, glyph: 1 }]) }]) },
	]

	## A `GDEF` (version 1.2) for `sixty_four`: glyphs 1 to 4 are base
	## glyphs, 5 and 6 marks of attachment classes 1 and 2, 7 a ligature;
	## mark glyph set 0 holds glyph 5 alone.
	marks_gdef : List(U8)
	marks_gdef = FontBuild.pack([
		U32(0x00010002),
		Ref(FontBuild.classes2([{ first: 1, last: 4, class: 1 }, { first: 5, last: 6, class: 3 }, { first: 7, last: 7, class: 2 }])),
		U16(0),
		U16(0),
		Ref(FontBuild.classes2([{ first: 5, last: 5, class: 1 }, { first: 6, last: 6, class: 2 }])),
		Ref(FontBuild.pack([U16(1), U16(1), Ref32(FontBuild.coverage1([5]))])),
	])

	## A `GSUB` or `GPOS` table with one script (`latn`), whose default
	## language lists one feature (`tag`) using every lookup in order; each
	## lookup has a type, a lookup flag, a mark filtering set (written only
	## when the flag uses one, 0x10) and its subtables.
	flagged_layout : Str, List({ kind : U64, flag : U64, set : U64, subtables : List(List(U8)) }) -> List(U8)
	flagged_layout = |tag, lookups| FontBuild.flagged_listing(tag, FontBuild.counting(lookups.len()), lookups)

	## `flagged_layout` whose feature uses only the lookups `listed`.
	flagged_listing : Str, List(U64), List({ kind : U64, flag : U64, set : U64, subtables : List(List(U8)) }) -> List(U8)
	flagged_listing = |tag, listed, lookups| {
		language = FontBuild.pack([U16(0), U16(0xFFFF), U16(1), U16(0)])
		scripts = FontBuild.pack([U16(1), Tag("latn"), Ref(FontBuild.pack([Ref(language), U16(0)]))])
		features = FontBuild.pack([U16(1), Tag(tag), Ref(FontBuild.pack([U16(0), U16(listed.len())].concat(listed.map(|i| U16(i)))))])
		lookup_list = FontBuild.pack(
			[U16(lookups.len())].concat(
				lookups.map(
					|l| {
						filter = if (l.flag.bitwise_and(0x10) != 0) [U16(l.set)] else []
						Ref(FontBuild.pack([U16(l.kind), U16(l.flag), U16(l.subtables.len())].concat(l.subtables.map(|s| Ref(s))).concat(filter)))
					},
				),
			),
		)
		FontBuild.pack([U32(0x00010000), Ref(scripts), Ref(features), Ref(lookup_list)])
	}

	## `flagged_listing` as version 1.1, with a `FeatureVariations` table
	## (`FontBuild.feature_variations`).
	flagged_layout_varied : Str, List(U64), List({ kind : U64, flag : U64, set : U64, subtables : List(List(U8)) }), List(U8) -> List(U8)
	flagged_layout_varied = |tag, listed, lookups, variations| {
		plain = FontBuild.flagged_listing(tag, listed, lookups)
		# The three offsets of the version 1.0 header move by the 4 bytes of
		# the `FeatureVariations` offset, which points after the rest.
		moved = |at| FontBuild.u16(((plain.get(at) ?? 0).to_u64() * 256 + (plain.get(at + 1) ?? 0).to_u64()) + 4)
		FontBuild.u32(0x00010001).concat(moved(4)).concat(moved(6)).concat(moved(8)).concat(FontBuild.u32(plain.len() + 4)).concat(plain.drop_first(10)).concat(variations)
	}

	# ------------------------------------------------------------ names

	## A `post` table of `version` (0x00010000, 0x00020000 or 0x00030000)
	## with an underline at -100, 50 thick. For version 2.0, `indices` are
	## the glyph name indices (one per glyph; from 258 they select a stored
	## name) and `stored` the stored names, each a length byte and its bytes.
	post : U64, List(U64), List(Str) -> List(U8)
	post = |version, indices, stored| {
		header = FontBuild.u32(version).concat(FontBuild.u32(0)).concat(FontBuild.i16(-100)).concat(FontBuild.i16(50)).concat(List.repeat(0, 20))
		if version == 0x00020000 {
			header
				.concat(FontBuild.u16(indices.len()))
				.concat(indices.join_map(FontBuild.u16))
				.concat(stored.join_map(|n| [n.to_utf8().len().to_u8_wrap()].concat(n.to_utf8())))
		} else {
			header
		}
	}

	## A `name` table of format 0, or of format 1 when `tags` (language
	## tags, as UTF-16BE bytes) is not empty: the records in order (platform
	## as `system`), each string stored once, then the tags.
	naming : List({ system : U64, encoding : U64, language : U64, id : U64, text : List(U8) }), List(List(U8)) -> List(U8)
	naming = |entries, tags| {
		format = if (tags.is_empty()) 0 else 1
		storage = 6 + 12 * entries.len() + (if (format == 1) 2 + 4 * tags.len() else 0)
		var $head = FontBuild.u16(format).concat(FontBuild.u16(entries.len())).concat(FontBuild.u16(storage))
		var $strings = []
		for r in entries {
			$head = $head.concat(FontBuild.u16(r.system)).concat(FontBuild.u16(r.encoding)).concat(FontBuild.u16(r.language)).concat(FontBuild.u16(r.id)).concat(FontBuild.u16(r.text.len())).concat(FontBuild.u16($strings.len()))
			$strings = $strings.concat(r.text)
		}
		if format == 1 {
			$head = $head.concat(FontBuild.u16(tags.len()))
			for t in tags {
				$head = $head.concat(FontBuild.u16(t.len())).concat(FontBuild.u16($strings.len()))
				$strings = $strings.concat(t)
			}
		}
		$head.concat($strings)
	}

	## ASCII text as UTF-16BE, for `naming`.
	utf16 : Str -> List(U8)
	utf16 = |text| text.to_utf8().join_map(|b| [0, b])

	## A `FeatureVariations` table (version 1.0): records of axis range
	## conditions (axis, minimum and maximum, F2Dot14), all of which must
	## hold, and feature substitutions (feature index and the lookups of its
	## alternate feature table).
	feature_variations : List({ conditions : List({ axis : U64, min : I64, max : I64 }), substitutions : List({ feature : U64, lookups : List(U64) }) }) -> List(U8)
	feature_variations = |variations| {
		condition_set = |conditions| FontBuild.pack([U16(conditions.len())].concat(conditions.map(|c| Ref32(FontBuild.pack([U16(1), U16(c.axis), I16(c.min), I16(c.max)])))))
		substitution = |subs| FontBuild.pack([U16(1), U16(0), U16(subs.len())].concat(subs.join_map(|f| [U16(f.feature), Ref32(FontBuild.pack([U16(0), U16(f.lookups.len())].concat(f.lookups.map(|l| U16(l)))))])))
		FontBuild.pack([U16(1), U16(0), U32(variations.len())].concat(variations.join_map(|r| [Ref32(condition_set(r.conditions)), Ref32(substitution(r.substitutions))])))
	}

	## A `FeatureVariations` table (version 1.1) without feature variation
	## records, with lookup variation records: each names a feature (by
	## index), whether it keeps the feature's own lookups (`keep`), and
	## conditions (an axis range, F2Dot14) each with the lookups it adds
	## when it holds.
	lookup_variations : List({ feature : U64, keep : Bool, conditions : List({ axis : U64, min : I64, max : I64, lookups : List(U64) }) }) -> List(U8)
	lookup_variations = |entries| {
		indices = |lookups| FontBuild.pack([U16(lookups.len())].concat(lookups.map(|l| U16(l))))
		condition = |c| FontBuild.pack([U16(1), U16(c.axis), I16(c.min), I16(c.max)])
		table = |r| FontBuild.pack([U16(1), U16(0), U16(if (r.keep) 1 else 0), U32(r.conditions.len())].concat(r.conditions.join_map(|c| [Ref32(condition(c)), Ref32(indices(c.lookups))])))
		FontBuild.pack([U16(1), U16(1), U32(0), U32(entries.len())].concat(entries.join_map(|r| [U16(r.feature), Ref32(table(r))])))
	}

	# ============================================================ outline and layout variations
	#
	# Builders for the `font-gvar` and `font-layout-var` fuzz targets:
	# TrueType outlines (`glyf`, `loca`, `hmtx` with side bearings), glyph
	# variations (`gvar`), a `GDEF` item variation store, pair adjustments
	# with device tables, and `FeatureVariations` with condition formats 1
	# and 3 to 5 and lookup variation records.

	## A simple TrueType glyph: contours of points (on-curve or not), its
	## header box computed from the points, no instructions. Coordinates are
	## written as short vectors, repeated values (same-coordinate flags) and
	## words where they fit, and runs of equal flags use the repeat flag.
	## Padded to an even length, so short `loca` offsets can address it.
	## No contours: an empty glyph (no bytes).
	simple_glyph : List(List({ x : I64, y : I64, on : Bool })) -> List(U8)
	simple_glyph = |contours| {
		points = contours.join_map(|c| c)
		if points.is_empty() {
			return []
		}
		first = points.first() ?? { x: 0, y: 0, on: True }
		x_min = points.fold(first.x, |m, p| m.min(p.x))
		x_max = points.fold(first.x, |m, p| m.max(p.x))
		y_min = points.fold(first.y, |m, p| m.min(p.y))
		y_max = points.fold(first.y, |m, p| m.max(p.y))
		var $ends = []
		var $total = 0
		for c in contours {
			$total = $total + c.len()
			$ends = $ends.concat(FontBuild.u16($total - 1))
		}
		var $flags = []
		var $xs = []
		var $ys = []
		var $px = 0
		var $py = 0
		for p in points {
			dx = p.x - $px
			dy = p.y - $py
			$px = p.x
			$py = p.y
			fx = if (dx == 0) 0x10 else if (dx >= -255 and dx <= 255) (if (dx > 0) 0x12 else 0x02) else 0
			fy = if (dy == 0) 0x20 else if (dy >= -255 and dy <= 255) (if (dy > 0) 0x24 else 0x04) else 0
			$xs = $xs.concat(if (dx == 0) [] else if (fx != 0) [dx.abs().to_u8_wrap()] else FontBuild.i16(dx))
			$ys = $ys.concat(if (dy == 0) [] else if (fy != 0) [dy.abs().to_u8_wrap()] else FontBuild.i16(dy))
			$flags = $flags.append((if (p.on) 1.U64 else 0) + fx + fy)
		}
		# Runs of equal flags, each written once with a repeat count.
		var $packed = []
		var $i = 0
		n = $flags.len()
		while $i < n {
			f = $flags.get($i) ?? 0
			var $j = $i + 1
			while $j < n and $j - $i < 256 and ($flags.get($j) ?? 0) == f {
				$j = $j + 1
			}
			run = $j - $i
			$packed = $packed.concat(if (run > 1) [(f + 0x08).to_u8_wrap(), (run - 1).to_u8_wrap()] else [f.to_u8_wrap()])
			$i = $j
		}
		body = FontBuild.pack([I16(contours.len().to_i64_wrap()), I16(x_min), I16(y_min), I16(x_max), I16(y_max)]).concat($ends).concat(FontBuild.u16(0)).concat($packed).concat($xs).concat($ys)
		if (body.len() % 2 == 1) body.append(0) else body
	}

	## A composite TrueType glyph: components (glyph, x and y offset,
	## optionally an explicit scale of 1.0) and the header box, which the
	## caller computes. Offsets are bytes or words as they fit.
	composite_glyph : List({ glyph : U64, dx : I64, dy : I64, scale : Bool }), { x_min : I64, y_min : I64, x_max : I64, y_max : I64 } -> List(U8)
	composite_glyph = |components, box| {
		count = components.len()
		component_records = components.map_with_index(
			|c, k| {
				words = c.dx < -128 or c.dx > 127 or c.dy < -128 or c.dy > 127
				flags = 0x0002 + (if (words) 0x0001 else 0) + (if (k + 1 < count) 0x0020 else 0) + (if (c.scale) 0x0008 else 0)
				args = if (words) FontBuild.i16(c.dx).concat(FontBuild.i16(c.dy)) else [(c.dx + 256).to_u8_wrap(), (c.dy + 256).to_u8_wrap()]
				FontBuild.u16(flags).concat(FontBuild.u16(c.glyph)).concat(args).concat(if (c.scale) FontBuild.u16(0x4000) else [])
			},
		)
		FontBuild.pack([I16(-1), I16(box.x_min), I16(box.y_min), I16(box.x_max), I16(box.y_max)]).concat(component_records.join_map(|r| r))
	}

	## A font of TrueType outlines: glyph `g` has the bytes `glyphs[g]`
	## (`simple_glyph`, `composite_glyph`, or empty), advance `advances[g]`
	## and left side bearing `bearings[g]`; the first `long_metrics` glyphs
	## have long metrics, the rest only bearings. `loca` offsets are long
	## or short (glyphs must then have even lengths). 1000 units per em.
	outline_font : List(List(U8)), List(U64), List(I64), U64, Bool, List(U8), List({ tag : Str, data : List(U8) }) -> List(U8)
	outline_font = |glyphs, advances, bearings, long_metrics, long_loca, characters, extra| {
		count = glyphs.len()
		boxes = FontBuild.outlines(glyphs, long_loca)
		metrics = FontBuild.counting(count).join_map(
			|g| {
				bearing = FontBuild.i16(bearings.get(g) ?? 0)
				if (g < long_metrics) FontBuild.u16(advances.get(g) ?? 0).concat(bearing) else bearing
			},
		)
		FontBuild.file(
			[
				{ tag: "head", data: FontBuild.head(1000, long_loca) },
				{ tag: "hhea", data: FontBuild.hhea(800, -200, long_metrics) },
				{ tag: "maxp", data: FontBuild.maxp(count) },
				{ tag: "hmtx", data: metrics },
				{ tag: "cmap", data: characters },
				{ tag: "loca", data: boxes.loca },
				{ tag: "glyf", data: boxes.glyf },
			].concat(extra),
		)
	}

	## Packed point numbers (`gvar`): a count, then runs of increments of
	## up to 128, as bytes or words. Points must ascend; none means all.
	gvar_points : List(U64) -> List(U8)
	gvar_points = |points| {
		n = points.len()
		var $out = if (n < 128) [n.to_u8_wrap()] else [(0x80 + n.shr_zf_wrap(8)).to_u8_wrap(), n.bitwise_and(0xFF).to_u8_wrap()]
		var $increments = List.with_capacity(n)
		var $previous = 0
		for p in points {
			$increments = $increments.append(p - $previous)
			$previous = p
		}
		var $i = 0
		while $i < n {
			words = ($increments.get($i) ?? 0) > 255
			var $j = $i
			while $j < n and $j - $i < 128 and (($increments.get($j) ?? 0) > 255) == words {
				$j = $j + 1
			}
			run = $increments.sublist({ start: $i, len: $j - $i })
			$out = $out.append(((if (words) 0x80 else 0) + run.len() - 1).to_u8_wrap()).concat(run.join_map(|v| if (words) FontBuild.u16(v) else [v.to_u8_wrap()]))
			$i = $j
		}
		$out
	}

	## Packed deltas (`gvar`): runs of up to 64 zeros, bytes or words.
	gvar_deltas : List(I64) -> List(U8)
	gvar_deltas = |values| {
		kind = |v| if (v == 0) 0 else if (v >= -128 and v <= 127) 1 else 2
		n = values.len()
		var $out = []
		var $i = 0
		while $i < n {
			k = kind(values.get($i) ?? 0)
			var $j = $i
			while $j < n and $j - $i < 64 and kind(values.get($j) ?? 0) == k {
				$j = $j + 1
			}
			run = values.sublist({ start: $i, len: $j - $i })
			control = (if (k == 0) 0x80 else if (k == 2) 0x40 else 0) + run.len() - 1
			data = if (k == 0) [] else if (k == 1) run.map(|v| (v + 256).to_u8_wrap()) else run.join_map(FontBuild.i16)
			$out = $out.append(control.to_u8_wrap()).concat(data)
			$i = $j
		}
		$out
	}

	## One tuple variation of a glyph: its peak (a shared tuple by index,
	## or embedded coordinates, F2Dot14 per axis), optionally an
	## intermediate region (start and end per axis), the points it moves
	## (`Inherit`: the glyph's shared points, or every point when it has
	## none; `All`; or private point numbers, ascending, counting the four
	## phantom points after the glyph's own) and one x and y delta per
	## point moved.
	GvarTuple : { peak : [Shared(U64), Embedded(List(I64))], between : [Peak, Range(List(I64), List(I64))], points : [Inherit, All, Own(List(U64))], xs : List(I64), ys : List(I64) }

	## One glyph's variation data (empty without tuples).
	gvar_glyph : { shared : [None, Points(List(U64))], tuples : List(GvarTuple) } -> List(U8)
	gvar_glyph = |glyph| {
		if glyph.tuples.is_empty() {
			return []
		}
		shared_bytes = match glyph.shared {
			None => []
			Points(points) => FontBuild.gvar_points(points)
		}
		parts = glyph.tuples.map(
			|t| {
				own = match t.points {
					Inherit => []
					All => [0]
					Own(points) => FontBuild.gvar_points(points)
				}
				data = own.concat(FontBuild.gvar_deltas(t.xs)).concat(FontBuild.gvar_deltas(t.ys))
				peak_index = match t.peak {
					Shared(k) => k
					Embedded(_) => 0x8000
				}
				intermediate = match t.between {
					Peak => 0
					Range(_, _) => 0x4000
				}
				private = match t.points {
					Inherit => 0
					_ => 0x2000
				}
				index = peak_index + intermediate + private
				embedded = match t.peak {
					Shared(_) => []
					Embedded(coords) => coords.join_map(FontBuild.i16)
				}
				range = match t.between {
					Peak => []
					Range(start, end) => start.join_map(FontBuild.i16).concat(end.join_map(FontBuild.i16))
				}
				{ header: FontBuild.u16(data.len()).concat(FontBuild.u16(index)).concat(embedded).concat(range), data }
			},
		)
		headers = parts.join_map(|p| p.header)
		count = glyph.tuples.len() + (
			match glyph.shared {
				None => 0
				Points(_) => 0x8000
			}
		)
		FontBuild.u16(count).concat(FontBuild.u16(4 + headers.len())).concat(headers).concat(shared_bytes).concat(parts.join_map(|p| p.data))
	}

	## A `gvar` table for `axis_count` axes: shared tuples (peaks, F2Dot14
	## per axis) and every glyph's variations (see `gvar_glyph`), with long
	## or short (even-padded) offsets.
	gvar : U64, List(List(I64)), List({ shared : [None, Points(List(U64))], tuples : List(GvarTuple) }), Bool -> List(U8)
	gvar = |axis_count, shared, glyphs, long| {
		datas = glyphs.map(
			|g| {
				d = FontBuild.gvar_glyph(g)
				if (!long and d.len() % 2 == 1) d.append(0) else d
			},
		)
		n = glyphs.len()
		var $offsets = []
		var $at = 0
		for d in datas {
			$offsets = $offsets.concat(if (long) FontBuild.u32($at) else FontBuild.u16($at // 2))
			$at = $at + d.len()
		}
		$offsets = $offsets.concat(if (long) FontBuild.u32($at) else FontBuild.u16($at // 2))
		tuples = shared.join_map(|t| t.join_map(FontBuild.i16))
		shared_at = 20 + $offsets.len()
		FontBuild.u16(1)
			.concat(FontBuild.u16(0))
			.concat(FontBuild.u16(axis_count))
			.concat(FontBuild.u16(shared.len()))
			.concat(FontBuild.u32(shared_at))
			.concat(FontBuild.u16(n))
			.concat(FontBuild.u16(if (long) 1 else 0))
			.concat(FontBuild.u32(shared_at + tuples.len()))
			.concat($offsets)
			.concat(tuples)
			.concat(datas.join_map(|d| d))
	}

	## A `GDEF` table (version 1.3) holding only an item variation store
	## (`variation_store`).
	gdef_store : List(U8) -> List(U8)
	gdef_store = |store| FontBuild.pack([U32(0x00010003), U16(0), U16(0), U16(0), U16(0), U16(0), Ref32(store)])

	## A device offset of a value record: none, a `VariationIndex` table
	## (outer and inner index into the `GDEF` store; 0xFFFF and 0xFFFF for
	## no variation), or a hinting device (start and end size, delta format
	## 1 to 3, every delta word `fill`), which adds nothing in font units.
	Device : [NoDevice, Index(U64, U64), Hinting(U64, U64, U64, U64)]

	device_field : Device -> Field
	device_field = |device|
		match device {
			NoDevice => U16(0)
			Index(outer, inner) => Ref(FontBuild.pack([U16(outer), U16(inner), U16(0x8000)]))
			Hinting(start, end, format, fill) => {
				bits = (1.U64).shl_wrap(format.to_u8_wrap())
				words = ((end - start + 1) * bits + 15) // 16
				Ref(FontBuild.pack([U16(start), U16(end), U16(format)].concat(List.repeat(U16(fill), words))))
			}
		}

	## A value record of `format` holding at most an x advance (0x04) and
	## its device (0x40).
	advance_fields : U64, I64, Device -> List(Field)
	advance_fields = |format, value, device|
		(if (format.bitwise_and(0x04) != 0) [I16(value)] else []).concat(if (format.bitwise_and(0x40) != 0) [FontBuild.device_field(device)] else [])

	## A pair adjustment subtable of format 1 whose first value records
	## have `format` (0x04 x advance, 0x40 its device, or both) and second
	## value records none; device offsets count from each pair set.
	pair1_devices : U64, List({ glyph : U64, pairs : List({ second : U64, value : I64, device : Device }) }) -> List(U8)
	pair1_devices = |format, sets| {
		set_tables = sets.map(|s| Ref(FontBuild.pack([U16(s.pairs.len())].concat(s.pairs.join_map(|p| [U16(p.second)].concat(FontBuild.advance_fields(format, p.value, p.device)))))))
		FontBuild.pack([U16(1), Ref(FontBuild.coverage1(sets.map(|s| s.glyph))), U16(format), U16(0), U16(sets.len())].concat(set_tables))
	}

	## A pair adjustment subtable of format 2 (see `pair2`) whose cells
	## have first value records of `format` (see `pair1_devices`); device
	## offsets count from the subtable.
	pair2_devices : U64, List(U8), List(U8), List(U8), U64, U64, List({ value : I64, device : Device }) -> List(U8)
	pair2_devices = |format, coverage, class1, class2, height, width, cells|
		FontBuild.pack([U16(2), Ref(coverage), U16(format), U16(0), Ref(class1), Ref(class2), U16(height), U16(width)].concat(cells.join_map(|c| FontBuild.advance_fields(format, c.value, c.device))))

	## A condition of a `FeatureVariations` table: an axis range (format 1,
	## `kind` 1, the first range), or the and (3), or (4) of its ranges, or
	## not (5) of its first range.
	VarCondition : { kind : U64, ranges : List({ axis : U64, min : I64, max : I64 }) }

	var_condition : VarCondition -> List(U8)
	var_condition = |c| {
		range = |r| FontBuild.pack([U16(1), U16(r.axis), I16(r.min), I16(r.max)])
		first = c.ranges.first() ?? { axis: 0, min: 0, max: 0 }
		if c.kind == 3 or c.kind == 4 {
			n = c.ranges.len()
			offsets = FontBuild.counting(n).join_map(|k| [0].concat(FontBuild.u16(3 + 3 * n + 8 * k)))
			FontBuild.u16(c.kind).concat([n.to_u8_wrap()]).concat(offsets).concat(c.ranges.join_map(range))
		} else if c.kind == 5 {
			FontBuild.u16(5).concat([0, 0, 5]).concat(range(first))
		} else {
			range(first)
		}
	}

	## A `FeatureVariations` table: records (conditions that must all
	## hold, and feature substitutions: feature index and the lookups of
	## its alternate feature table) and, when there are any, lookup
	## variation records (version 1.1: a feature, whether it keeps its own
	## lookups, and conditions each with the lookups it adds).
	layout_variations : List({ conditions : List(VarCondition), substitutions : List({ feature : U64, lookups : List(U64) }) }), List({ feature : U64, keep : Bool, conditions : List({ condition : VarCondition, lookups : List(U64) }) }) -> List(U8)
	layout_variations = |entries, lookup_records| {
		indices = |lookups| FontBuild.pack([U16(lookups.len())].concat(lookups.map(|l| U16(l))))
		condition_set = |conditions| FontBuild.pack([U16(conditions.len())].concat(conditions.map(|c| Ref32(FontBuild.var_condition(c)))))
		substitution = |subs| FontBuild.pack([U16(1), U16(0), U16(subs.len())].concat(subs.join_map(|f| [U16(f.feature), Ref32(FontBuild.pack([U16(0), U16(f.lookups.len())].concat(f.lookups.map(|l| U16(l)))))])))
		lookup_table = |r| FontBuild.pack([U16(1), U16(0), U16(if (r.keep) 1 else 0), U32(r.conditions.len())].concat(r.conditions.join_map(|c| [Ref32(FontBuild.var_condition(c.condition)), Ref32(indices(c.lookups))])))
		minor = if (lookup_records.is_empty()) 0 else 1
		tail = if (minor == 0) [] else [U32(lookup_records.len())].concat(lookup_records.join_map(|r| [U16(r.feature), Ref32(lookup_table(r))]))
		FontBuild.pack([U16(1), U16(minor), U32(entries.len())].concat(entries.join_map(|r| [Ref32(condition_set(r.conditions)), Ref32(substitution(r.substitutions))])).concat(tail))
	}

	## `layout` as version 1.1, with a `FeatureVariations` table
	## (`layout_variations`).
	layout_varied : Str, List({ tag : Str, lookups : List(U64) }), List({ kind : U64, subtables : List(List(U8)) }), List(U8) -> List(U8)
	layout_varied = |script, features, lookups, variations| {
		plain = FontBuild.layout(script, features, lookups)
		moved = |at| FontBuild.u16(((plain.get(at) ?? 0).to_u64() * 256 + (plain.get(at + 1) ?? 0).to_u64()) + 4)
		FontBuild.u32(0x00010001).concat(moved(4)).concat(moved(6)).concat(moved(8)).concat(FontBuild.u32(plain.len() + 4)).concat(plain.drop_first(10)).concat(variations)
	}
}

expect FontBuild.u16(0x1234) == [0x12, 0x34]
expect FontBuild.i16(-2) == [0xFF, 0xFE]
expect FontBuild.pack([U16(1), Ref([9, 9]), U16(2), Ref([7])]) == [0, 1, 0, 8, 0, 2, 0, 10, 9, 9, 7]
expect FontBuild.file([{ tag: "abc", data: [1] }]).len() == 12 + 16 + 4

# `gvar` packing: zeros, bytes and words in their own runs; point numbers
# as increments, bytes then words.
expect FontBuild.gvar_deltas([0, 0, 0, 5, -3, 300]) == [0x82, 0x01, 5, 0xFD, 0x40, 0x01, 0x2C]
expect FontBuild.gvar_points([1, 2, 300]) == [3, 0x01, 1, 1, 0x80, 0x01, 0x2A]
expect FontBuild.gvar_points([]) == [0]
