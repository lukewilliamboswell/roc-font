import Bytes
import TableVar
import TableOutline
import TableCffIndex
import TableCffDict
import TableCffTables
import TableCffData
import TableCffBlend
import TableCffCharstring
import TableCffPath

## Prepared CFF1/CFF2 cubic outlines. The eager interpreter proves every
## reachable program, including a conservative all-location coordinate
## envelope. FontMatrix is checked finite but outlines retain the raw
## OpenType font-unit coordinates used by HarfBuzz.
TableCff := {
	data : List(U8),
	cff2 : Bool,
	glyphs : TableCffIndex.Index,
	globals : TableCffIndex.Index,
	fds : List({ locals : TableCffIndex.Index, ivs : U64, seed : U32 }),
	fd_for_glyph : List(U32),
	store : TableVar.Store,
	proofs : List({ operations : U64, commands : U64, envelope : F64, seac : [Absent, Present({ base : U64, accent : U64, dx : F64, dy : F64 })] }),
}.{
	Reason : [Malformed]
	Location : List(U32)
	none : TableCff
	none = { data: [], cff2: False, glyphs: TableCffIndex.empty, globals: TableCffIndex.empty, fds: [], fd_for_glyph: [], store: TableCff.empty_store, proofs: [] }
	empty_store : TableVar.Store
	empty_store = { axis_count: 0, region_count: 0, regions: [], item_counts: [], word_counts: [], long_words: [], index_starts: [], region_indexes: [], row_starts: [], row_sizes: [], bytes: [] }
	read : List(U8), U64, U64, [Cff1, Cff2] -> Try(TableCff, [Bad({ offset : U64, reason : Reason }), OverLimit(Str)])
	read = |data, glyph_count, axis_count, version| {
		match TableCff.prepare(data, glyph_count, axis_count, version == Cff2) {
			Ok(prepared) => Ok(prepared)
			Err(Bad(offset)) => Err(Bad({ offset, reason: Malformed }))
			Err(OverLimit(bound)) => Err(OverLimit(bound))
		}
	}

	entry_nat : TableCffDict.Parsed, U64, U64, U64 -> Try(U64, [Bad(U64)])
	entry_nat = |dict, op, fallback, maximum| match TableCffDict.find(dict, op) {
		Absent => Ok(fallback)
		Present(entry) => TableCffDict.nat(dict, entry, 0, maximum)
	}
	private : List(U8), TableCffDict.Parsed, Bool, TableVar.Store, U64 -> Try({ locals : TableCffIndex.Index, ivs : U64, seed : U32 }, [Bad(U64), OverLimit(Str)])
	private = |data, font_dict, cff2, store, origin| {
		match TableCffDict.find(font_dict, 18) {
			Absent => if (cff2) Err(Bad(origin)) else Ok({ locals: TableCffIndex.empty, ivs: 0, seed: 987654321 })
			Present(entry) => {
				length = TableCffDict.nat(font_dict, entry, 0, data.len())?
				offset = TableCffDict.nat(font_dict, entry, 1, data.len())?
				if !Bytes.fits(offset, length, data.len()) {
					return Err(Bad(offset))
				}
				dict = TableCffDict.read(data, { start: offset, end: offset + length }, if (cff2) Private2 else Private1, store)?
				locals = match TableCffDict.find(dict, 19) {
					Absent => TableCffIndex.empty
					Present(subrs) => {
						relative = TableCffDict.nat(dict, subrs, 0, data.len() - offset)?
						TableCffIndex.read(data, offset + relative, cff2)?
					}
				}
				ivs = TableCff.entry_nat(dict, 22, 0, 65535)?
				var $seed = 987654321.U32
				if !cff2 {
					match TableCffDict.find(dict, 275) {
						Absent => {}
						Present(seed_entry) => {
							arg = dict.args.get(seed_entry.start) ?? return Err(Bad(seed_entry.at))
							v = arg.value
							absolute = if (v < 0) 0 - v else v
							parsed = TableCffDict.natural(absolute, 2147483648, seed_entry.at)?
							if parsed != 0 {
								$seed = parsed.to_u32_wrap()
							}
						}
					}
				}
				Ok({ locals, ivs, seed: $seed })
			}
		}
	}

	prepare : List(U8), U64, U64, Bool -> Try(TableCff, [Bad(U64), OverLimit(Str)])
	prepare = |data, glyph_count, axis_count, cff2| {
		if glyph_count == 0 or glyph_count > 65535 or !Bytes.fits(0, if (cff2) 5 else 4, data.len()) {
			return Err(Bad(0))
		}
		if Bytes.u8(data, 0) != (if (cff2) 2 else 1) or Bytes.u8(data, 1) != 0 {
			return Err(Bad(0))
		}
		header = Bytes.u8(data, 2)
		if header < (if (cff2) 5 else 4) or header > data.len() {
			return Err(Bad(2))
		}
		var $top_span = { start: 0, end: 0 }
		var $global = TableCffIndex.empty
		var $strings = 0
		if cff2 {
			length = Bytes.u16(data, 3)
			if !Bytes.fits(header, length, data.len()) {
				return Err(Bad(3))
			}
			$top_span = { start: header, end: header + length }
			$global = TableCffIndex.read(data, header + length, True)?
		} else {
			off_size = Bytes.u8(data, 3)
			if off_size < 1 or off_size > 4 {
				return Err(Bad(3))
			}
			names = TableCffIndex.read(data, header, False)?
			if names.count != 1 {
				return Err(Bad(header))
			}
			tops = TableCffIndex.read(data, names.next, False)?
			if tops.count != 1 {
				return Err(Bad(names.next))
			}
			$top_span = TableCffIndex.span(data, tops, 0)
			strings = TableCffIndex.read(data, tops.next, False)?
			$strings = strings.count
			$global = TableCffIndex.read(data, strings.next, False)?
		}
		top = TableCffDict.read(data, $top_span, if (cff2) Top2 else Top1, TableCff.empty_store)?
		cs_at = TableCff.entry_nat(top, 17, 0, data.len())?
		if cs_at == 0 {
			return Err(Bad($top_span.start))
		}
		glyphs = TableCffIndex.read(data, cs_at, cff2)?
		if glyphs.count != glyph_count {
			return Err(Bad(cs_at))
		}
		var $store = TableCff.empty_store
		if cff2 {
			store_at = TableCff.entry_nat(top, 24, 0, data.len())?
			if store_at != 0 {
				if !Bytes.fits(store_at, 2, data.len()) {
					return Err(Bad(store_at))
				}
				length = Bytes.u16(data, store_at)
				if !Bytes.fits(store_at + 2, length, data.len()) {
					return Err(Bad(store_at))
				}
				$store = TableVar.read_store(data.take_first(store_at + 2 + length), "CFF2", store_at + 2, axis_count) ?? return Err(Bad(store_at))
			}
		}
		cid = match TableCffDict.find(top, 286) {
			Present(_) => True
			Absent => False
		}
		if !cff2 {
			charstring_type = TableCff.entry_nat(top, 262, 2, 2)?
			if charstring_type != 2 {
				return Err(Bad($top_span.start))
			}
		}
		var $fds = []
		var $fd_for_glyph = []
		if cff2 or cid {
			fd_at = TableCff.entry_nat(top, 292, 0, data.len())?
			if fd_at == 0 {
				return Err(Bad($top_span.start))
			}
			fd_array = TableCffIndex.read(data, fd_at, cff2)?
			if fd_array.count == 0 or fd_array.count > 65536 {
				return Err(Bad(fd_at))
			}
			$fds = List.with_capacity(fd_array.count)
			for i in 0..<fd_array.count {
				dict_span = TableCffIndex.span(data, fd_array, i)
				dict = TableCffDict.read(data, dict_span, if (cff2) Font2 else Font1, $store)?
				$fds = $fds.append(TableCff.private(data, dict, cff2, $store, dict_span.start)?)
			}
			selection = TableCff.entry_nat(top, 293, 0, data.len())?
			if selection == 0 {
				if !cff2 or fd_array.count != 1 {
					return Err(Bad($top_span.start))
				}
				$fd_for_glyph = List.repeat(0, glyph_count)
			} else {
				$fd_for_glyph = TableCffTables.fd_select(data, selection, glyph_count, fd_array.count, cff2)?
			}
		} else {
			$fds = [TableCff.private(data, top, False, $store, $top_span.start)?]
			$fd_for_glyph = List.repeat(0, glyph_count)
		}
		var $charset = []
		if !cff2 {
			charset_at = TableCff.entry_nat(top, 15, 0, data.len())?
			if cid and charset_at <= 2 {
				return Err(Bad($top_span.start))
			}
			$charset = TableCffTables.charset(data, charset_at, glyph_count, if (cid) 65535 else 390 + $strings)?
			if !cid {
				encoding_at = TableCff.entry_nat(top, 16, 0, data.len())?
				_ = TableCffTables.encoding(data, encoding_at, $charset)?
			}
		}
		regions = TableCffBlend.regions_of($store)
		var $proofs = List.with_capacity(glyph_count)
		var $total_operations = 0
		# A finite read budget protects shared subroutines invoked by many
		# glyphs. This is a resource limit, never a fabricated malformed font.
		read_limit = (1000000.U64).max(data.len().min(1000000) * 64)
		for glyph in 0..<glyph_count {
			fd_index = ($fd_for_glyph.get(glyph) ?? 0).to_u64()
			fd = $fds.get(fd_index) ?? return Err(Bad(cs_at))
			config = { cff2, globals: $global, locals: fd.locals, ivs: fd.ivs, seed: fd.seed, operation_limit: 1000000, command_limit: 200000 }
			result = TableCffCharstring.run(data, TableCffIndex.span(data, glyphs, glyph), config, regions, [], True, False, 0)?
			$total_operations = $total_operations + result.operations
			if $total_operations > read_limit {
				return Err(OverLimit("CFF preparation instruction count"))
			}
			seac = match result.seac {
				Absent => Absent
				Present(parts) => {
					if cid or cff2 {
						return Err(Bad(cs_at))
					}
					base_sid = TableCffData.standard_encoding.get(parts.base) ?? return Err(Bad(cs_at))
					accent_sid = TableCffData.standard_encoding.get(parts.accent) ?? return Err(Bad(cs_at))
					var $base = glyph_count
					var $accent = glyph_count
					for i in 0..<glyph_count {
						sid = $charset.get(i) ?? 0
						if sid == base_sid {
							$base = i
						}
						if sid == accent_sid {
							$accent = i
						}
					}
					if $base == glyph_count or $accent == glyph_count {
						return Err(Bad(cs_at))
					}
					Present({ base: $base, accent: $accent, dx: parts.dx, dy: parts.dy })
				}
			}
			$proofs = $proofs.append({ operations: result.operations, commands: result.path.count, envelope: result.path.envelope, seac })
		}
		prepared : TableCff
		prepared = { data, cff2, glyphs, globals: $global, fds: $fds, fd_for_glyph: $fd_for_glyph, store: $store, proofs: $proofs }
		TableCff.check_seac(prepared)
	}

	check_seac : TableCff -> Try(TableCff, [Bad(U64), OverLimit(Str)])
	check_seac = |prepared| {
		# A bounded explicit DFS proves every expanded component tree. Depth
		# is limited independently of visit count, including zero-path cycles.
		for glyph in 0..<prepared.proofs.len() {
			var $work = [{ glyph, depth: 0, dx: 0.F64, dy: 0.F64 }]
			var $visits = 0
			var $commands = 0
			while !$work.is_empty() {
				frame = $work.last() ?? break
				$work = $work.take_first($work.len() - 1)
				$visits = $visits + 1
				if $visits > 1024 or frame.depth > 10 {
					return Err(OverLimit("CFF seac expansion"))
				}
				proof = prepared.proofs.get(frame.glyph) ?? return Err(Bad(0))
				$commands = $commands + proof.commands
				if $commands > 200000 {
					return Err(OverLimit("CFF expanded glyph command count"))
				}
				x = if (frame.dx < 0) 0 - frame.dx else frame.dx
				y = if (frame.dy < 0) 0 - frame.dy else frame.dy
				if proof.envelope + x.max(y) > TableCffPath.coordinate_limit {
					return Err(OverLimit("CFF seac coordinate envelope"))
				}
				match proof.seac {
					Absent => {}
					Present(parts) => {
						$work = $work.append({ glyph: parts.accent, depth: frame.depth + 1, dx: frame.dx + parts.dx, dy: frame.dy + parts.dy })
						$work = $work.append({ glyph: parts.base, depth: frame.depth + 1, dx: frame.dx, dy: frame.dy })
					}
				}
			}
		}
		Ok(prepared)
	}

	location : TableCff, List(I16) -> Location
	location = |prepared, coords| TableVar.region_scalars_precise(prepared.store, coords)

	query : TableCff, Location, U64, Bool -> { commands : List(TableOutline.Command), bounds : TableCffPath.Bounds }
	query = |prepared, scalars, glyph, draw| {
		if glyph >= prepared.glyphs.count {
			return { commands: [], bounds: TableCffPath.empty_bounds }
		}
		regions = TableCffBlend.regions_of(prepared.store)
		single_proof = prepared.proofs.get(glyph) ?? return { commands: [], bounds: TableCffPath.empty_bounds }
		if single_proof.seac == Absent {
			# Return the single proven, already-sized command buffer directly.
			# No component worklist or second growing command list is needed.
			fd_index = (prepared.fd_for_glyph.get(glyph) ?? 0).to_u64()
			fd = prepared.fds.get(fd_index) ?? return { commands: [], bounds: TableCffPath.empty_bounds }
			config = { cff2: prepared.cff2, globals: prepared.globals, locals: fd.locals, ivs: fd.ivs, seed: fd.seed, operation_limit: single_proof.operations, command_limit: single_proof.commands }
			# Preparation proved these indices and this exact static program.
			result = TableCffCharstring.run(prepared.data, TableCffIndex.span(prepared.data, prepared.glyphs, glyph), config, regions, scalars, False, draw, single_proof.commands) ?? return { commands: [], bounds: TableCffPath.empty_bounds }
			return { commands: result.path.commands, bounds: result.path.bounds }
		}
		var $work = [{ glyph, dx: 0.F64, dy: 0.F64 }]
		var $commands = []
		var $bounds = TableCffPath.empty_bounds
		for _ in 0..<1024 {
			frame = $work.last() ?? break
			$work = $work.take_first($work.len() - 1)
			proof = prepared.proofs.get(frame.glyph) ?? break
			fd_index = (prepared.fd_for_glyph.get(frame.glyph) ?? 0).to_u64()
			fd = prepared.fds.get(fd_index) ?? break
			config = { cff2: prepared.cff2, globals: prepared.globals, locals: fd.locals, ivs: fd.ivs, seed: fd.seed, operation_limit: proof.operations, command_limit: proof.commands }
			# Preparation proved this same program, with all branch/control
			# operands static. Its interval proof covers these location scalars.
			result = TableCffCharstring.run(prepared.data, TableCffIndex.span(prepared.data, prepared.glyphs, frame.glyph), config, regions, scalars, False, draw, proof.commands) ?? break
			if draw {
				for command in result.path.commands {
					translated = match command {
						MoveTo(point) => MoveTo({ x: point.x + frame.dx, y: point.y + frame.dy })
						LineTo(point) => LineTo({ x: point.x + frame.dx, y: point.y + frame.dy })
						QuadraticTo(curve) => QuadraticTo({ control: { x: curve.control.x + frame.dx, y: curve.control.y + frame.dy }, end: { x: curve.end.x + frame.dx, y: curve.end.y + frame.dy } })
						CubicTo(curve) => CubicTo({ control1: { x: curve.control1.x + frame.dx, y: curve.control1.y + frame.dy }, control2: { x: curve.control2.x + frame.dx, y: curve.control2.y + frame.dy }, end: { x: curve.end.x + frame.dx, y: curve.end.y + frame.dy } })
						Close => Close
					}
					$commands = $commands.append(translated)
				}
			}
			b = result.path.bounds
			if !b.empty {
				$bounds = TableCffPath.include($bounds, { x: b.x_min + frame.dx, y: b.y_min + frame.dy })
				$bounds = TableCffPath.include($bounds, { x: b.x_max + frame.dx, y: b.y_max + frame.dy })
			}
			match proof.seac {
				Absent => {}
				Present(parts) => {
					$work = $work.append({ glyph: parts.accent, dx: frame.dx + parts.dx, dy: frame.dy + parts.dy })
					$work = $work.append({ glyph: parts.base, dx: frame.dx, dy: frame.dy })
				}
			}
		}
		{ commands: $commands, bounds: $bounds }
	}
	commands : TableCff, Location, U64 -> List(TableOutline.Command)
	commands = |prepared, scalars, glyph| TableCff.query(prepared, scalars, glyph, True).commands
	round_coordinate : F64 -> I32
	round_coordinate = |v| {
		shifted = v + 0.5
		truncated = shifted.to_i64_try() ?? 0
		floor_value = if (truncated.to_f64() > shifted) truncated - 1 else truncated
		floor_value.to_i32_wrap()
	}
	extents : TableCff, Location, U64 -> [Extents({ x_min : I32, y_min : I32, x_max : I32, y_max : I32 }), Empty]
	extents = |prepared, scalars, glyph| {
		bounds = TableCff.query(prepared, scalars, glyph, False).bounds
		if bounds.empty {
			Empty
		} else {
			Extents({ x_min: TableCff.round_coordinate(bounds.x_min), y_min: TableCff.round_coordinate(bounds.y_min), x_max: TableCff.round_coordinate(bounds.x_max), y_max: TableCff.round_coordinate(bounds.y_max) })
		}
	}
}

# Original small containers exercise preparation without importing test
# builders or font files into the bundle.
test_cff1 : List(U8)
test_cff1 = [1, 0, 4, 4, 0, 1, 1, 1, 2, 65, 0, 1, 1, 1, 3, 160, 17, 0, 0, 0, 0, 0, 1, 1, 1, 8, 139, 139, 21, 239, 139, 5, 14]

test_cff2 : List(U8)
test_cff2 = [2, 0, 5, 0, 5, 153, 17, 166, 12, 36, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 7, 139, 139, 21, 239, 139, 5, 0, 0, 0, 1, 1, 1, 4, 139, 139, 18]

expect {
	match TableCff.read(test_cff1, 1, 0, Cff1) {
		Ok(prepared) => TableCff.commands(prepared, TableCff.location(prepared, []), 0) == [MoveTo({ x: 0, y: 0 }), LineTo({ x: 100, y: 0 }), Close] and TableCff.extents(prepared, [], 0) == Extents({ x_min: 0, y_min: 0, x_max: 100, y_max: 0 }) and TableCff.commands(prepared, [], 1).is_empty()
		Err(_) => False
	}
}
expect {
	match TableCff.read(test_cff2, 1, 0, Cff2) {
		Ok(prepared) => TableCff.commands(prepared, [], 0) == [MoveTo({ x: 0, y: 0 }), LineTo({ x: 100, y: 0 }), Close]
		Err(_) => False
	}
}
expect {
	# Truncation is found during reading rather than query execution.
	match TableCff.read(test_cff1.take_first(test_cff1.len() - 1), 1, 0, Cff1) {
		Err(Bad(_)) => True
		_ => False
	}
}
expect TableCff.round_coordinate(-1.5) == -1 and TableCff.round_coordinate(1.5) == 2
expect {
	# CFF2 requires a PrivateDICT even when its length is zero.
	missing = test_cff2.take_first(33).append(1)
	match TableCff.read(missing, 1, 0, Cff2) {
		Err(Bad({ offset, .. })) => offset == 34
		_ => False
	}
}
