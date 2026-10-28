import Bytes
import TableVar
import TableOutline

## Checked COLR0 layers and COLR1 paint DAGs. Internal. Preparation retains
## scalar node descriptors, flat edge pools and checked byte spans. Queries
## evaluate only the requested glyph at a location and return a finite graph
## of font facts; no rasterizing, compositing or trigonometry happens here.
TableColor := {
	ctx : Context,
	v0_at : U64,
	v0_count : U64,
	v0_layers : U64,
	roots : List(U32),
	nodes : List(Node),
	edges : List(U32),
	clips_at : U64,
	clips_count : U64,
	scalars : List(U32),
}.{
	ColorRef : [PaletteEntry(U16), Foreground]
	Layer : { glyph : U32, color : ColorRef }
	Point : { x : F64, y : F64 }
	Rect : { x_min : F64, y_min : F64, x_max : F64, y_max : F64 }
	Span : { start : U64, len : U64 }
	Stop : { offset : F64, color : ColorRef, alpha : F64 }
	Extend : [Pad, Repeat, Reflect]
	Mode : [Clear, Source, Destination, SourceOver, DestinationOver, SourceIn, DestinationIn, SourceOut, DestinationOut, SourceAtop, DestinationAtop, Xor, Plus, Screen, Overlay, Darken, Lighten, ColorDodge, ColorBurn, HardLight, SoftLight, Difference, Exclusion, Multiply, HslHue, HslSaturation, HslColor, HslLuminosity]
	Operation : [
		Affine({ xx : F64, yx : F64, xy : F64, yy : F64, dx : F64, dy : F64 }),
		Translate(Point),
		Scale({ x : F64, y : F64, center : Point }),
		Rotate({ degrees : F64, center : Point }),
		Skew({ x_degrees : F64, y_degrees : F64, center : Point }),
	]
	Paint : [
		Layers(Span),
		Solid({ color : ColorRef, alpha : F64 }),
		LinearGradient({ stops : Span, extend : Extend, p0 : Point, p1 : Point, p2 : Point }),
		RadialGradient({ stops : Span, extend : Extend, c0 : Point, radius0 : F64, c1 : Point, radius1 : F64 }),
		SweepGradient({ stops : Span, extend : Extend, center : Point, start_degrees : F64, end_degrees : F64 }),
		Glyph({ glyph : U32, paint : U32 }),
		ColorGlyph({ glyph : U32, paint : U32, clip : [Present(Rect), Absent] }),
		Transform({ paint : U32, operation : Operation }),
		Composite({ source : U32, backdrop : U32, mode : Mode }),
	]
	Graph : { root : U32, nodes : List(Paint), edges : List(U32), stops : List(Stop), clip : [Present(Rect), Absent] }

	Context : {
		bytes : List(U8),
		glyph_count : U64,
		palette_entries : U64,
		base_at : U64,
		base_count : U64,
		layer_at : U64,
		layer_count : U64,
		store : [Present(TableVar.Store), Absent],
		map : [Present(TableVar.DeltaMap), Absent],
	}
	# Every field is scalar: accessing a prepared node never retains inner lists.
	Node : { at : U64, kind : U64, edge_start : U64, edge_len : U64, params_at : U64, var_base : U64, color_at : U64, stop_count : U64, glyph : U32, bounded : Bool }
	no_node : Node
	no_node = { at: 0, kind: 0, edge_start: 0, edge_len: 0, params_at: 0, var_base: 4294967295, color_at: 0, stop_count: 0, glyph: 0, bounded: False }

	none : TableColor
	none = { ctx: { bytes: [], glyph_count: 0, palette_entries: 0, base_at: 0, base_count: 0, layer_at: 0, layer_count: 0, store: Absent, map: Absent }, v0_at: 0, v0_count: 0, v0_layers: 0, roots: [], nodes: [], edges: [], clips_at: 0, clips_count: 0, scalars: [] }

	at_location : TableColor, List(I16) -> TableColor
	at_location = |table, coords| {
		scalars = match table.ctx.store {
			Present(store) => TableVar.region_scalars_precise(store, coords)
			Absent => []
		}
		{ ..table, scalars }
	}

	color_ref : U64 -> ColorRef
	color_ref = |index| if (index == 65535) Foreground else PaletteEntry(index.to_u16_wrap())

	u24 : List(U8), U64 -> U64
	u24 = |data, at| Bytes.u8(data, at) * 65536 + Bytes.u16(data, at + 1)

	v1_record : Context, U64 -> [Present(U64), Absent]
	v1_record = |ctx, glyph| {
		var $lo = 0
		var $hi = ctx.base_count
		while $lo < $hi {
			mid = $lo + ($hi - $lo) // 2
			at = ctx.base_at + 4 + 6 * mid
			g = Bytes.u16(ctx.bytes, at)
			if glyph < g {
				$hi = mid
			} else if glyph > g {
				$lo = mid + 1
			} else {
				return Present(mid)
			}
		}
		Absent
	}

	layers : TableColor, U32 -> List(Layer)
	layers = |table, glyph| {
		if glyph.to_u64() >= table.ctx.glyph_count {
			return []
		}
		var $lo = 0
		var $hi = table.v0_count
		while $lo < $hi {
			mid = $lo + ($hi - $lo) // 2
			at = table.v0_at + 6 * mid
			g = Bytes.u16(table.ctx.bytes, at)
			if glyph.to_u64() < g {
				$hi = mid
			} else if glyph.to_u64() > g {
				$lo = mid + 1
			} else {
				first = Bytes.u16(table.ctx.bytes, at + 2)
				n = Bytes.u16(table.ctx.bytes, at + 4)
				var $out = List.with_capacity(n)
				for i in 0..<n {
					r = table.v0_layers + 4 * (first + i)
					$out = $out.append({ glyph: Bytes.u16(table.ctx.bytes, r).to_u32_wrap(), color: TableColor.color_ref(Bytes.u16(table.ctx.bytes, r + 2)) })
				}
				return $out
			}
		}
		[]
	}

	check_palette : Context, U64 -> Try({}, [Bad(U64)])
	check_palette = |ctx, at| {
		p = Bytes.u16(ctx.bytes, at)
		if (p == 65535 or p < ctx.palette_entries) Ok({}) else Err(Bad(at))
	}

	# Work includes repeated shared color lines and edges; a hostile short
	# file cannot create quadratic preparation or an oversized output pool.
	spend : Context, U64, U64, U64 -> Try(U64, [Bad(U64)])
	spend = |ctx, steps, cost, at| {
		total = steps + cost + 1
		if (total > 8 * ctx.bytes.len() + 16384) Err(Bad(at)) else Ok(total)
	}

	check_var : Context, U64, U64, U64 -> Try({}, [Bad(U64)])
	check_var = |ctx, base, count, at| {
		if base == 4294967295 {
			return Ok({})
		}
		# The format defines no-store tables as static: ignore varIndexBase.
		match ctx.store {
			Absent => Ok({})
			Present(store) => {
				if count > 0 and base > 4294967295 - (count - 1) {
					return Err(Bad(at))
				}
				for i in 0..<count {
					index = base + i
					mapped = match ctx.map {
						Present(map) => TableVar.map_entry(map, index)
						Absent => { outer: index // 65536, inner: index % 65536 }
					}
					if !TableVar.valid_index(store, mapped.outer, mapped.inner) {
						return Err(Bad(at))
					}
				}
				Ok({})
			}
		}
	}

	delta : TableColor, U64 -> U32
	delta = |table, index| {
		if index == 4294967295 {
			return 0
		}
		match table.ctx.store {
			Absent => 0
			Present(store) => {
				mapped = match table.ctx.map {
					Present(map) => TableVar.map_entry(map, index)
					Absent => { outer: index // 65536, inner: index % 65536 }
				}
				TableVar.delta(store, table.scalars, mapped.outer, mapped.inner)
			}
		}
	}

	# Raw 16/32-bit values and deltas are added as binary32 before scaling
	# fixed-point representations. Every value is finite, then exactly
	# widened to F64. Accepted store sums are bounded below2^48.
	number_bits : TableColor, U64, U64, Bool, U64, U64 -> U32
	number_bits = |table, at, width, unsigned, base, index| {
		raw = if width == 4 {
			TableVar.i32(table.ctx.bytes, at)
		} else if unsigned {
			Bytes.u16(table.ctx.bytes, at).to_i64_wrap()
		} else {
			Bytes.i16(table.ctx.bytes, at)
		}
		varied = if (base == 4294967295) 0 else TableColor.delta(table, base + index)
		TableVar.f32_add(TableVar.f32_from_int(raw), varied)
	}

	number : TableColor, U64, U64, Bool, U64, U64, U64 -> F64
	number = |table, at, width, unsigned, base, index, divisor| {
		bits = TableColor.number_bits(table, at, width, unsigned, base, index)
		scaled = TableVar.f32_mul(bits, TableVar.f32_from_ratio(1, divisor.to_u128()))
		TableOutline.widen(scaled)
	}

	alpha : TableColor, U64, U64, U64 -> F64
	alpha = |table, at, base, index| {
		value = TableColor.number(table, at, 2, False, base, index, 16384)
		# COLR explicitly requires alpha clamping, including after variation.
		value.max(0).min(1)
	}

	check_v0 : Context, U64, U64, U64, U64 -> Try({}, [Bad(U64)])
	check_v0 = |ctx, base_at, base_count, layer_at, layer_count| {
		data = ctx.bytes
		if !Bytes.fits(base_at, 6 * base_count, data.len()) {
			return Err(Bad(4))
		}
		if !Bytes.fits(layer_at, 4 * layer_count, data.len()) {
			return Err(Bad(8))
		}
		if base_count > 0 and base_at == 0 {
			return Err(Bad(4))
		}
		if layer_count > 0 and layer_at == 0 {
			return Err(Bad(8))
		}
		var $previous = 0
		for i in 0..<base_count {
			at = base_at + 6 * i
			glyph = Bytes.u16(data, at)
			first = Bytes.u16(data, at + 2)
			count = Bytes.u16(data, at + 4)
			if glyph >= ctx.glyph_count or (i > 0 and glyph <= $previous) {
				return Err(Bad(at))
			}
			if first > layer_count or count > layer_count - first {
				return Err(Bad(at + 2))
			}
			$previous = glyph
		}
		for i in 0..<layer_count {
			at = layer_at + 4 * i
			if Bytes.u16(data, at) >= ctx.glyph_count {
				return Err(Bad(at))
			}
			TableColor.check_palette(ctx, at + 2)?
		}
		Ok({})
	}

	check_bases : Context -> Try({}, [Bad(U64)])
	check_bases = |ctx| {
		data = ctx.bytes
		var $previous = 0
		for i in 0..<ctx.base_count {
			at = ctx.base_at + 4 + 6 * i
			glyph = Bytes.u16(data, at)
			if glyph >= ctx.glyph_count or (i > 0 and glyph <= $previous) {
				return Err(Bad(at))
			}
			if Bytes.u32(data, at + 2) == 0 {
				return Err(Bad(at + 2))
			}
			$previous = glyph
		}
		Ok({})
	}

	check_clips : Context, U64 -> Try(U64, [Bad(U64)])
	check_clips = |ctx, at| {
		if at == 0 {
			return Ok(0)
		}
		data = ctx.bytes
		if !Bytes.fits(at, 5, data.len()) {
			return Err(Bad(at))
		}
		if Bytes.u8(data, at) != 1 {
			return Err(Bad(at))
		}
		n = Bytes.u32(data, at + 1)
		if !Bytes.fits(at + 5, 7 * n, data.len()) {
			return Err(Bad(at + 1))
		}
		var $previous = 0
		for i in 0..<n {
			r = at + 5 + 7 * i
			first = Bytes.u16(data, r)
			last = Bytes.u16(data, r + 2)
			if first > last or last >= ctx.glyph_count or (i > 0 and first <= $previous) {
				return Err(Bad(r))
			}
			offset = TableColor.u24(data, r + 4)
			box = at + offset
			if offset == 0 or !Bytes.fits(box, 9, data.len()) {
				return Err(Bad(r + 4))
			}
			format = Bytes.u8(data, box)
			if format != 1 and format != 2 {
				return Err(Bad(box))
			}
			if format == 2 {
				if !Bytes.fits(box, 13, data.len()) {
					return Err(Bad(box))
				}
				TableColor.check_var(ctx, Bytes.u32(data, box + 9), 4, box + 9)?
			}
			$previous = last
		}
		Ok(n)
	}

	clip_at : TableColor, U32 -> U64
	clip_at = |table, glyph| TableColor.find_clip(table.ctx.bytes, table.clips_at, table.clips_count, glyph)

	find_clip : List(U8), U64, U64, U32 -> U64
	find_clip = |data, clips_at, count, glyph| {
		var $lo = 0
		var $hi = count
		while $lo < $hi {
			mid = $lo + ($hi - $lo) // 2
			at = clips_at + 5 + 7 * mid
			first = Bytes.u16(data, at)
			last = Bytes.u16(data, at + 2)
			if glyph.to_u64() < first {
				$hi = mid
			} else if glyph.to_u64() > last {
				$lo = mid + 1
			} else {
				return clips_at + TableColor.u24(data, at + 4)
			}
		}
		0
	}

	clip : TableColor, U32 -> [Present(Rect), Absent]
	clip = |table, glyph| {
		at = TableColor.clip_at(table, glyph)
		if at == 0 {
			return Absent
		}
		base = if (Bytes.u8(table.ctx.bytes, at) == 2) Bytes.u32(table.ctx.bytes, at + 9) else 4294967295
		bits = |i| TableColor.number_bits(table, at + 1 + 2 * i, 2, False, base, i)
		# The format requires outward integer rounding after variation.
		lower = |i| TableVar.f32_floor(bits(i)).to_f64()
		upper = |i| (0 - TableVar.f32_floor(TableVar.f32_sub(0, bits(i)))).to_f64()
		Present({ x_min: lower(0), y_min: lower(1), x_max: upper(2), y_max: upper(3) })
	}

	lengths : List(U64)
	lengths = [0, 6, 5, 9, 16, 20, 16, 20, 12, 16, 6, 3, 7, 7, 8, 12, 8, 12, 12, 16, 6, 10, 10, 14, 6, 10, 10, 14, 8, 12, 12, 16, 8]

	parse : Context, U64, U64 -> Try({ node : Node, children : List(U64), steps : U64 }, [Bad(U64)])
	parse = |ctx, at, steps| {
		data = ctx.bytes
		if !Bytes.fits(at, 1, data.len()) {
			return Err(Bad(at))
		}
		kind = Bytes.u8(data, at)
		if kind == 0 or kind > 32 {
			return Err(Bad(at))
		}
		size = TableColor.lengths.get(kind) ?? 0
		if !Bytes.fits(at, size, data.len()) {
			return Err(Bad(at))
		}
		var $spent = TableColor.spend(ctx, steps, 1, at)?
		var $node = { ..TableColor.no_node, at, kind }
		var $children = []
		if kind == 1 {
			n = Bytes.u8(data, at + 1)
			first = Bytes.u32(data, at + 2)
			if first > ctx.layer_count or n > ctx.layer_count - first {
				return Err(Bad(at + 2))
			}
			$spent = TableColor.spend(ctx, $spent, n, at)?
			for i in 0..<n {
				field = ctx.layer_at + 4 + 4 * (first + i)
				offset = Bytes.u32(data, field)
				if offset == 0 {
					return Err(Bad(field))
				}
				$children = $children.append(ctx.layer_at + offset)
			}
		} else if kind == 2 or kind == 3 {
			TableColor.check_palette(ctx, at + 1)?
			base = if (kind == 3) Bytes.u32(data, at + 5) else 4294967295
			TableColor.check_var(ctx, base, 1, at + 5)?
			$node = { ..$node, params_at: at + 3, var_base: base }
		} else if kind >= 4 and kind <= 9 {
			varied = kind % 2 == 1
			count = if (kind <= 7) 6 else 4
			end = at + 4 + 2 * count
			base = if (varied) Bytes.u32(data, end) else 4294967295
			TableColor.check_var(ctx, base, count, end)?
			offset = TableColor.u24(data, at + 1)
			line = at + offset
			if offset == 0 or !Bytes.fits(line, 3, data.len()) {
				return Err(Bad(at + 1))
			}
			n = Bytes.u16(data, line + 1)
			width = if (varied) 10 else 6
			if !Bytes.fits(line + 3, width * n, data.len()) {
				return Err(Bad(line + 1))
			}
			$spent = TableColor.spend(ctx, $spent, n, at)?
			for i in 0..<n {
				r = line + 3 + width * i
				TableColor.check_palette(ctx, r + 2)?
				if varied {
					TableColor.check_var(ctx, Bytes.u32(data, r + 6), 2, r + 6)?
				}
			}
			$node = { ..$node, params_at: at + 4, var_base: base, color_at: line, stop_count: n }
		} else if kind == 11 {
			glyph = Bytes.u16(data, at + 1)
			record = match TableColor.v1_record(ctx, glyph) {
				Present(i) => i
				Absent => return Err(Bad(at + 1))
			}
			offset = Bytes.u32(data, ctx.base_at + 4 + 6 * record + 2)
			$children = [ctx.base_at + offset]
			$node = { ..$node, glyph: glyph.to_u32_wrap() }
		} else if kind == 32 {
			first = TableColor.u24(data, at + 1)
			second = TableColor.u24(data, at + 5)
			if first == 0 or second == 0 {
				return Err(Bad(at + 1))
			}
			$children = [at + first, at + second]
		} else {
			child = TableColor.u24(data, at + 1)
			if child == 0 {
				return Err(Bad(at + 1))
			}
			$children = [at + child]
			if kind == 10 {
				glyph = Bytes.u16(data, at + 4)
				if glyph >= ctx.glyph_count {
					return Err(Bad(at + 4))
				}
				$node = { ..$node, glyph: glyph.to_u32_wrap() }
			} else if kind == 12 or kind == 13 {
				offset = TableColor.u24(data, at + 4)
				transform = at + offset
				varied = kind == 13
				if offset == 0 or !Bytes.fits(transform, if (varied) 28 else 24, data.len()) {
					return Err(Bad(at + 4))
				}
				base = if (varied) Bytes.u32(data, transform + 24) else 4294967295
				TableColor.check_var(ctx, base, 6, transform + 24)?
				$node = { ..$node, params_at: transform, var_base: base }
			} else {
				varied = kind % 2 == 1
				plain = if (varied) kind - 1 else kind
				count = if plain == 14 or plain == 16 or plain == 28 {
					2
				} else if plain == 18 or plain == 30 {
					4
				} else if plain == 20 or plain == 24 {
					1
				} else {
					3
				}
				end = at + 4 + 2 * count
				base = if (varied) Bytes.u32(data, end) else 4294967295
				TableColor.check_var(ctx, base, count, end)?
				$node = { ..$node, params_at: at + 4, var_base: base }
			}
		}
		Ok({ node: $node, children: $children, steps: $spent })
	}

	# Header counts are validated before they size even a work list. Node IDs
	# follow deterministic root/discovery order; dictionary iteration is never
	# observed. Every DAG visit has a byte-derived budget and depth at most64.
	read : List(U8), U64, U64, U64 -> Try(TableColor, List(U64))
	read = |data, glyph_count, palette_entries, axis_count| {
		bad = |at| Err([at])
		if !Bytes.fits(0, 14, data.len()) {
			return bad(0)
		}
		version = Bytes.u16(data, 0)
		if version > 1 {
			return bad(0)
		}
		if version == 1 and !Bytes.fits(0, 34, data.len()) {
			return bad(0)
		}
		base_count = Bytes.u16(data, 2)
		base_at = Bytes.u32(data, 4)
		layer_at = Bytes.u32(data, 8)
		layer_count = Bytes.u16(data, 12)
		bases = if (version == 1) Bytes.u32(data, 14) else 0
		v1_layers = if (version == 1) Bytes.u32(data, 18) else 0
		clip_offset = if (version == 1) Bytes.u32(data, 22) else 0
		map_offset = if (version == 1) Bytes.u32(data, 26) else 0
		store_offset = if (version == 1) Bytes.u32(data, 30) else 0
		store = if store_offset == 0 {
			Absent
		} else {
			match TableVar.read_store(data, "COLR", store_offset, axis_count) {
				Ok(value) => Present(value)
				Err(ps) => return Err(ps.map(|p| p.offset))
			}
		}
		if map_offset != 0 {
			if !Bytes.fits(map_offset, 4, data.len()) {
				return bad(26)
			}
			entry_format = Bytes.u8(data, map_offset + 1)
			entry_size = entry_format.shr_zf_wrap(4).bitwise_and(3) + 1
			inner_bits = entry_format.bitwise_and(15) + 1
			if entry_format.bitwise_and(0xC0) != 0 or inner_bits > 8 * entry_size {
				return bad(map_offset + 1)
			}
		}

		map = if map_offset == 0 {
			Absent
		} else {
			match store {
				Present(s) => match TableVar.read_delta_map(data, "COLR", map_offset, s) {
					Ok(value) => Present(value)
					Err(ps) => return Err(ps.map(|p| p.offset))
				}
				Absent => {
					# The format ignores mappings without a store, but their byte spans
					# still have to fit. No map with an unchecked row is retained.
					if !Bytes.fits(map_offset, 4, data.len()) {
						return bad(26)
					}
					format = Bytes.u8(data, map_offset)
					width = Bytes.u8(data, map_offset + 1).shr_zf_wrap(4).bitwise_and(3) + 1
					header = if (format == 0) 4 else 6
					if format > 1 or !Bytes.fits(map_offset, header, data.len()) {
						return bad(map_offset)
					}
					n = if (format == 0) Bytes.u16(data, map_offset + 2) else Bytes.u32(data, map_offset + 2)
					if !Bytes.fits(map_offset + header, width * n, data.len()) {
						return bad(map_offset)
					}
					Absent
				}
			}
		}
		if bases != 0 and !Bytes.fits(bases, 4, data.len()) {
			return bad(14)
		}
		if v1_layers != 0 and !Bytes.fits(v1_layers, 4, data.len()) {
			return bad(18)
		}
		n = if (bases == 0) 0 else Bytes.u32(data, bases)
		l = if (v1_layers == 0) 0 else Bytes.u32(data, v1_layers)
		if !Bytes.fits(bases + 4, 6 * n, data.len()) and n != 0 {
			return bad(bases)
		}
		if !Bytes.fits(v1_layers + 4, 4 * l, data.len()) and l != 0 {
			return bad(v1_layers)
		}
		ctx = { bytes: data, glyph_count, palette_entries, base_at: bases, base_count: n, layer_at: v1_layers, layer_count: l, store, map }
		var $problems = []
		match TableColor.check_v0(ctx, base_at, base_count, layer_at, layer_count) {
			Ok(_) => {}
			Err(Bad(at)) => {
				$problems = $problems.append(at)
			}
		}
		match TableColor.check_bases(ctx) {
			Ok(_) => {}
			Err(Bad(at)) => {
				$problems = $problems.append(at)
			}
		}
		clips_count = match TableColor.check_clips(ctx, clip_offset) {
			Ok(count) => count
			Err(Bad(at)) => {
				$problems = $problems.append(at)
				0
			}
		}
		if !$problems.is_empty() {
			return Err($problems)
		}
		var $nodes = []
		var $raw_edges = []
		var $finished = []
		var $known = Dict.with_capacity((n + l).min(1024))
		var $steps = 0
		# Stream roots instead of allocating from the (possibly enormous)
		# layer count; many entries may share a single prepared paint.
		for root_index in 0..<(n + l) {
			root = if root_index < n {
				bases + Bytes.u32(data, bases + 4 + 6 * root_index + 2)
			} else {
				field = v1_layers + 4 + 4 * (root_index - n)
				offset = Bytes.u32(data, field)
				if offset == 0 {
					return bad(field)
				}
				v1_layers + offset
			}
			var $pending = [{ at: root, exit: False, depth: 0.U64, id: 0.U32 }]
			while !$pending.is_empty() {
				frame = $pending.last() ?? { at: 0, exit: False, depth: 0, id: 0 }
				$pending = $pending.drop_last(1)
				if frame.exit {
					$finished = $finished.append(frame.id)
					$known = $known.insert(frame.at, { id: frame.id, active: False })
				} else {
					match $known.get(frame.at) {
						Ok(found) if found.active => return bad(frame.at)
						Ok(_) => {}
						Err(_) => {
							if frame.depth > 64 {
								return bad(frame.at)
							}
							parsed = match TableColor.parse(ctx, frame.at, $steps) {
								Ok(value) => value
								Err(Bad(at)) => return bad(at)
							}
							$steps = parsed.steps
							if $nodes.len() > 4294967295 {
								return bad(frame.at)
							}
							id = $nodes.len().to_u32_wrap()
							node = { ..parsed.node, edge_start: $raw_edges.len(), edge_len: parsed.children.len() }
							$nodes = $nodes.append(node)
							$raw_edges = $raw_edges.concat(parsed.children)
							$known = $known.insert(frame.at, { id, active: True })
							$pending = $pending.append({ at: frame.at, exit: True, depth: frame.depth, id })
							for i in 0..<parsed.children.len() {
								child = parsed.children.get(parsed.children.len() - 1 - i) ?? 0
								$pending = $pending.append({ at: child, exit: False, depth: frame.depth + 1, id: 0 })
							}
						}
					}
				}
			}
		}
		var $edges = List.with_capacity($raw_edges.len())
		for offset in $raw_edges {
			found = $known.get(offset) ?? { id: 0, active: True }
			# Every edge was traversed above; absence is unreachable.
			if found.active {
				return bad(offset)
			}
			$edges = $edges.append(found.id)
		}
		var $roots = List.with_capacity(n)
		for i in 0..<n {
			at = bases + Bytes.u32(data, bases + 4 + 6 * i + 2)
			found = $known.get(at) ?? { id: 0, active: True }
			if found.active {
				return bad(at)
			}
			$roots = $roots.append(found.id)
		}
		# Children complete before parents in this explicit postorder.
		# Glyph clipping bounds a fill; composites follow the specification's
		# source/backdrop rules. Clip boxes also bound referenced color glyphs.
		for id in $finished {
			node = TableColor.node_at($nodes, id)
			bounded = if node.kind == 10 {
				True
			} else if node.kind == 11 {
				TableColor.child_bound($nodes, $edges, node, 0) or TableColor.find_clip(data, clip_offset, clips_count, node.glyph) != 0
			} else if node.kind == 1 {
				var $all = True
				for i in 0..<node.edge_len {
					if !TableColor.child_bound($nodes, $edges, node, i) {
						$all = False
					}
				}
				$all
			} else if node.kind == 32 {
				mode = TableColor.mode_index(Bytes.u8(data, node.at + 4))
				if mode == 0 {
					True
				} else if mode == 1 or mode == 7 {
					TableColor.child_bound($nodes, $edges, node, 0)
				} else if mode == 2 or mode == 8 {
					TableColor.child_bound($nodes, $edges, node, 1)
				} else if mode == 5 or mode == 6 {
					TableColor.child_bound($nodes, $edges, node, 0) or TableColor.child_bound($nodes, $edges, node, 1)
				} else {
					TableColor.child_bound($nodes, $edges, node, 0) and TableColor.child_bound($nodes, $edges, node, 1)
				}
			} else if node.kind >= 12 {
				TableColor.child_bound($nodes, $edges, node, 0)
			} else {
				False
			}
			# The traversal assigned every id below nodes.len(); this set
			# cannot fail and its fallback must not retain the old list.
			$nodes = $nodes.set(id.to_u64(), { ..node, bounded }) ?? []
		}
		for i in 0..<n {
			id = TableColor.id_at($roots, i)
			node = TableColor.node_at($nodes, id)
			glyph = Bytes.u16(data, bases + 4 + 6 * i).to_u32_wrap()
			if !node.bounded and TableColor.find_clip(data, clip_offset, clips_count, glyph) == 0 {
				return bad(node.at)
			}
		}

		table = { ctx, v0_at: base_at, v0_count: base_count, v0_layers: layer_at, roots: $roots, nodes: $nodes, edges: $edges, clips_at: clip_offset, clips_count, scalars: [] }
		# Even the default coordinates evaluate this table's own variation store.
		Ok(TableColor.at_location(table, List.repeat(0, axis_count)))
	}

	# All callers use IDs and spans proved by read or by graph's local
	# traversal. Missing data is an invariant violation, never glyph zero.
	node_at : List(Node), U32 -> Node
	node_at = |nodes, id| match nodes.get(id.to_u64()) {
		Ok(node) => node
		Err(_) => crash "a checked COLR node ID became unavailable"
	}
	id_at : List(U32), U64 -> U32
	id_at = |ids, index| match ids.get(index) {
		Ok(id) => id
		Err(_) => crash "a checked COLR edge ID became unavailable"
	}
	child_bound : List(Node), List(U32), Node, U64 -> Bool
	child_bound = |nodes, edges, node, index| TableColor.node_at(nodes, TableColor.id_at(edges, node.edge_start + index)).bounded

	modes : List(Mode)
	modes = [Clear, Source, Destination, SourceOver, DestinationOver, SourceIn, DestinationIn, SourceOut, DestinationOut, SourceAtop, DestinationAtop, Xor, Plus, Screen, Overlay, Darken, Lighten, ColorDodge, ColorBurn, HardLight, SoftLight, Difference, Exclusion, Multiply, HslHue, HslSaturation, HslColor, HslLuminosity]

	mode_index : U64 -> U64
	mode_index = |raw| if (raw < 28) raw else 0

	# Unknown extend modes use Pad, and unknown blend modes use Clear: these
	# are the format's specified fallbacks, not repairs of references.
	extend : U64 -> Extend
	extend = |raw| match raw {
		1 => Repeat
		2 => Reflect
		_ => Pad
	}

	param : TableColor, Node, U64, U64, Bool, U64 -> F64
	param = |table, node, index, width, unsigned, divisor| TableColor.number(table, node.params_at + width * index, width, unsigned, node.var_base, index, divisor)

	point : TableColor, Node, U64 -> Point
	point = |table, node, index| { x: TableColor.param(table, node, index, 2, False, 1), y: TableColor.param(table, node, index + 1, 2, False, 1) }

	angle : TableColor, Node, U64, Bool -> F64
	angle = |table, node, index, biased| {
		bits = TableColor.number_bits(table, node.params_at + 2 * index, 2, False, node.var_base, index)
		adjusted = if (biased) TableVar.f32_add(bits, TableVar.f32_from_int(16384)) else bits
		TableOutline.widen(TableVar.f32_mul(adjusted, TableVar.f32_from_ratio(180, 16384)))
	}

	operation : TableColor, Node -> Operation
	operation = |table, node| {
		plain = if (node.kind % 2 == 1) node.kind - 1 else node.kind
		p = |i, divisor| TableColor.param(table, node, i, 2, False, divisor)
		origin = { x: 0.F64, y: 0.F64 }
		if plain == 12 {
			value = |i| TableColor.param(table, node, i, 4, False, 65536)
			Affine({ xx: value(0), yx: value(1), xy: value(2), yy: value(3), dx: value(4), dy: value(5) })
		} else if plain == 14 {
			Translate(TableColor.point(table, node, 0))
		} else if plain == 16 or plain == 18 or plain == 20 or plain == 22 {
			uniform = plain == 20 or plain == 22
			center = if plain == 18 {
				TableColor.point(table, node, 2)
			} else if plain == 22 {
				TableColor.point(table, node, 1)
			} else {
				origin
			}
			Scale({ x: p(0, 16384), y: if (uniform) p(0, 16384) else p(1, 16384), center })
		} else if plain == 24 or plain == 26 {
			center = if (plain == 26) TableColor.point(table, node, 1) else origin
			Rotate({ degrees: TableColor.angle(table, node, 0, False), center })
		} else {
			center = if (plain == 30) TableColor.point(table, node, 2) else origin
			Skew({ x_degrees: TableColor.angle(table, node, 0, False), y_degrees: TableColor.angle(table, node, 1, False), center })
		}
	}

	# Most fonts already store stops in order. Check first, then use stable
	# bottom-up merging only when the format requires reordering them.
	sort_stops : List(Stop) -> List(Stop)
	sort_stops = |stops| {
		n = stops.len()
		var $ordered = True
		for i in 1..<n {
			a = stops.get(i - 1) ?? { offset: 0, color: Foreground, alpha: 0 }
			b = stops.get(i) ?? { offset: 0, color: Foreground, alpha: 0 }
			if a.offset > b.offset {
				$ordered = False
			}
		}
		if $ordered {
			return stops
		}
		var $input = stops
		var $width = 1
		while $width < n {
			var $output = List.with_capacity(n)
			var $start = 0
			while $start < n {
				middle = ($start + $width).min(n)
				end = ($start + 2 * $width).min(n)
				var $a = $start
				var $b = middle
				while $a < middle or $b < end {
					left = $input.get($a) ?? { offset: 0, color: Foreground, alpha: 0 }
					right = $input.get($b) ?? { offset: 0, color: Foreground, alpha: 0 }
					if $b >= end or ($a < middle and left.offset <= right.offset) {
						$output = $output.append(left)
						$a = $a + 1
					} else {
						$output = $output.append(right)
						$b = $b + 1
					}
				}
				$start = end
			}
			$input = $output
			$width = $width * 2
		}
		$input
	}

	stops : TableColor, Node -> List(Stop)
	stops = |table, node| {
		varied = node.kind % 2 == 1
		width = if (varied) 10 else 6
		var $out = List.with_capacity(node.stop_count)
		for i in 0..<node.stop_count {
			at = node.color_at + 3 + width * i
			base = if (varied) Bytes.u32(table.ctx.bytes, at + 6) else 4294967295
			$out = $out.append({ offset: TableColor.number(table, at, 2, False, base, 0, 16384), color: TableColor.color_ref(Bytes.u16(table.ctx.bytes, at + 2)), alpha: TableColor.alpha(table, at + 4, base, 1) })
		}
		TableColor.sort_stops($out)
	}

	decode : TableColor, Node, List(U32), Span, Span -> Paint
	decode = |table, node, children, edge_span, stop_span| {
		data = table.ctx.bytes
		if node.kind == 1 {
			Layers(edge_span)
		} else if node.kind == 2 or node.kind == 3 {
			Solid({ color: TableColor.color_ref(Bytes.u16(data, node.at + 1)), alpha: TableColor.alpha(table, node.params_at, node.var_base, 0) })
		} else if node.kind >= 4 and node.kind <= 9 {
			extend_mode = TableColor.extend(Bytes.u8(data, node.color_at))
			if node.kind <= 5 {
				LinearGradient({ stops: stop_span, extend: extend_mode, p0: TableColor.point(table, node, 0), p1: TableColor.point(table, node, 2), p2: TableColor.point(table, node, 4) })
			} else if node.kind <= 7 {
				RadialGradient({ stops: stop_span, extend: extend_mode, c0: TableColor.point(table, node, 0), radius0: TableColor.param(table, node, 2, 2, True, 1), c1: TableColor.point(table, node, 3), radius1: TableColor.param(table, node, 5, 2, True, 1) })
			} else {
				SweepGradient({ stops: stop_span, extend: extend_mode, center: TableColor.point(table, node, 0), start_degrees: TableColor.angle(table, node, 2, True), end_degrees: TableColor.angle(table, node, 3, True) })
			}
		} else if node.kind == 10 {
			Glyph({ glyph: node.glyph, paint: TableColor.id_at(children, 0) })
		} else if node.kind == 11 {
			ColorGlyph({ glyph: node.glyph, paint: TableColor.id_at(children, 0), clip: TableColor.clip(table, node.glyph) })
		} else if node.kind == 32 {
			mode = TableColor.modes.get(TableColor.mode_index(Bytes.u8(data, node.at + 4))) ?? Clear
			Composite({ source: TableColor.id_at(children, 0), backdrop: TableColor.id_at(children, 1), mode })
		} else {
			Transform({ paint: TableColor.id_at(children, 0), operation: TableColor.operation(table, node) })
		}
	}

	v0_graph : List(Layer) -> Graph
	v0_graph = |layer_list| {
		n = layer_list.len()
		var $nodes = List.with_capacity(1 + 2 * n)
		$nodes = $nodes.append(Layers({ start: 0, len: n }))
		var $edges = List.with_capacity(n)
		for i in 0..<n {
			layer = layer_list.get(i) ?? { glyph: 0, color: Foreground }
			glyph_id = (1 + 2 * i).to_u32_wrap()
			$nodes = $nodes.append(Glyph({ glyph: layer.glyph, paint: glyph_id + 1 })).append(Solid({ color: layer.color, alpha: 1 }))
			$edges = $edges.append(glyph_id)
		}
		{ root: 0, nodes: $nodes, edges: $edges, stops: [], clip: Absent }
	}

	graph : TableColor, U32 -> [Present(Graph), Absent]
	graph = |table, glyph| {
		if glyph.to_u64() >= table.ctx.glyph_count {
			return Absent
		}
		record = match TableColor.v1_record(table.ctx, glyph.to_u64()) {
			Present(index) => index
			Absent => {
				# Preserve a present zero-layer COLR0 definition as an empty graph.
				var $lo = 0
				var $hi = table.v0_count
				while $lo < $hi {
					mid = $lo + ($hi - $lo) // 2
					found = Bytes.u16(table.ctx.bytes, table.v0_at + 6 * mid)
					if glyph.to_u64() < found {
						$hi = mid
					} else if glyph.to_u64() > found {
						$lo = mid + 1
					} else {
						return Present(TableColor.v0_graph(TableColor.layers(table, glyph)))
					}
				}
				return Absent
			}
		}
		root = TableColor.id_at(table.roots, record)
		var $ids = [root]
		var $local = Dict.with_capacity(16)
		$local = $local.insert(root, 0.U32)
		var $cursor = 0
		# Reading proved acyclicity; each prepared node is inserted at most once.
		while $cursor < $ids.len() and $cursor < table.nodes.len() {
			id = TableColor.id_at($ids, $cursor)
			node = TableColor.node_at(table.nodes, id)
			for i in 0..<node.edge_len {
				child = TableColor.id_at(table.edges, node.edge_start + i)
				if !$local.contains(child) {
					next = $ids.len().to_u32_wrap()
					$local = $local.insert(child, next)
					$ids = $ids.append(child)
				}
			}
			$cursor = $cursor + 1
		}
		var $paints = List.with_capacity($ids.len())
		var $edges = []
		var $stops = []
		for id in $ids {
			node = TableColor.node_at(table.nodes, id)
			var $children = List.with_capacity(node.edge_len)
			for i in 0..<node.edge_len {
				child = TableColor.id_at(table.edges, node.edge_start + i)
				# Every child was assigned a local ID by the traversal above.
				match $local.get(child) {
					Ok(value) => {
						$children = $children.append(value)
					}
					Err(_) => crash "a checked COLR edge lost its local node"
				}
			}
			edge_span = { start: $edges.len(), len: if (node.kind == 1) $children.len() else 0 }
			if node.kind == 1 {
				$edges = $edges.concat($children)
			}
			new_stops = if (node.kind >= 4 and node.kind <= 9) TableColor.stops(table, node) else []
			stop_span = { start: $stops.len(), len: new_stops.len() }
			$stops = $stops.concat(new_stops)
			$paints = $paints.append(TableColor.decode(table, node, $children, edge_span, stop_span))
		}
		Present({ root: 0, nodes: $paints, edges: $edges, stops: $stops, clip: TableColor.clip(table, glyph) })
	}

}

# Original fixture COLR table, copied with tests/fonts/inline_tables.py.
color_all_bytes : List(U8)
color_all_bytes = [
	[0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	[0, 34, 0, 0, 2, 176, 0, 0, 2, 210, 0, 0, 0, 0, 0, 0],
	[2, 235, 0, 0, 0, 32, 0, 1, 0, 0, 0, 196, 0, 2, 0, 0],
	[0, 202, 0, 3, 0, 0, 0, 207, 0, 4, 0, 0, 0, 216, 0, 5],
	[0, 0, 0, 232, 0, 6, 0, 0, 0, 252, 0, 7, 0, 0, 1, 12],
	[0, 8, 0, 0, 1, 32, 0, 9, 0, 0, 1, 65, 0, 10, 0, 0],
	[2, 154, 0, 11, 0, 0, 1, 114, 0, 12, 0, 0, 1, 117, 0, 13],
	[0, 0, 1, 148, 0, 14, 0, 0, 1, 183, 0, 15, 0, 0, 1, 191],
	[0, 16, 0, 0, 1, 203, 0, 17, 0, 0, 1, 211, 0, 18, 0, 0],
	[1, 223, 0, 19, 0, 0, 1, 235, 0, 20, 0, 0, 1, 251, 0, 21],
	[0, 0, 2, 1, 0, 22, 0, 0, 2, 11, 0, 23, 0, 0, 2, 21],
	[0, 24, 0, 0, 2, 35, 0, 25, 0, 0, 2, 41, 0, 26, 0, 0],
	[2, 51, 0, 27, 0, 0, 2, 61, 0, 28, 0, 0, 2, 75, 0, 29],
	[0, 0, 2, 83, 0, 30, 0, 0, 2, 95, 0, 31, 0, 0, 2, 107],
	[0, 32, 0, 0, 2, 123, 1, 2, 0, 0, 0, 0, 2, 0, 1, 32],
	[0, 3, 0, 1, 32, 0, 0, 0, 0, 0, 4, 0, 0, 84, 0, 10],
	[0, 20, 1, 144, 0, 50, 0, 50, 1, 244, 5, 0, 0, 105, 0, 10],
	[0, 20, 1, 144, 0, 50, 0, 50, 1, 244, 0, 0, 0, 0, 6, 0],
	[0, 48, 0, 10, 0, 20, 0, 100, 1, 44, 1, 144, 2, 88, 7, 0],
	[0, 69, 0, 10, 0, 20, 0, 100, 1, 44, 1, 144, 2, 88, 0, 0],
	[0, 0, 8, 0, 0, 12, 0, 100, 0, 200, 160, 0, 32, 0, 1, 0],
	[3, 48, 0, 0, 2, 32, 0, 16, 0, 0, 0, 64, 0, 48, 0, 255],
	[255, 48, 0, 9, 0, 0, 16, 0, 100, 0, 200, 160, 0, 32, 0, 0],
	[0, 0, 0, 1, 0, 3, 48, 0, 0, 2, 32, 0, 0, 0, 0, 6],
	[16, 0, 0, 0, 64, 0, 0, 0, 0, 6, 48, 0, 255, 255, 48, 0],
	[0, 0, 0, 6, 11, 0, 1, 12, 0, 1, 37, 0, 0, 7, 0, 1],
	[0, 0, 0, 0, 64, 0, 255, 255, 224, 0, 0, 0, 192, 0, 0, 12],
	[128, 0, 255, 247, 192, 0, 13, 0, 1, 6, 0, 0, 7, 0, 1, 0],
	[0, 0, 0, 64, 0, 255, 255, 224, 0, 0, 0, 192, 0, 0, 12, 128],
	[0, 255, 247, 192, 0, 0, 0, 0, 0, 14, 0, 0, 227, 0, 12, 255],
	[248, 15, 0, 0, 219, 0, 12, 255, 248, 0, 0, 0, 0, 16, 0, 0],
	[207, 80, 0, 48, 0, 17, 0, 0, 199, 80, 0, 48, 0, 0, 0, 0],
	[0, 18, 0, 0, 187, 80, 0, 48, 0, 0, 100, 0, 200, 19, 0, 0],
	[175, 80, 0, 48, 0, 0, 100, 0, 200, 0, 0, 0, 0, 20, 0, 0],
	[159, 80, 0, 21, 0, 0, 153, 80, 0, 0, 0, 0, 0, 22, 0, 0],
	[143, 80, 0, 0, 100, 0, 200, 23, 0, 0, 133, 80, 0, 0, 100, 0],
	[200, 0, 0, 0, 0, 24, 0, 0, 119, 16, 0, 25, 0, 0, 113, 16],
	[0, 0, 0, 0, 0, 26, 0, 0, 103, 16, 0, 0, 100, 0, 200, 27],
	[0, 0, 93, 16, 0, 0, 100, 0, 200, 0, 0, 0, 0, 28, 0, 0],
	[79, 8, 0, 240, 0, 29, 0, 0, 71, 8, 0, 240, 0, 0, 0, 0],
	[0, 30, 0, 0, 59, 8, 0, 240, 0, 0, 100, 0, 200, 31, 0, 0],
	[47, 8, 0, 240, 0, 0, 100, 0, 200, 0, 0, 0, 0, 32, 0, 0],
	[31, 23, 0, 0, 8, 10, 0, 0, 6, 0, 35, 2, 0, 2, 64, 0],
	[0, 0, 0, 2, 0, 0, 0, 12, 0, 0, 0, 23, 10, 0, 0, 6],
	[0, 34, 2, 0, 0, 48, 0, 10, 0, 0, 6, 0, 35, 2, 255, 255],
	[64, 0, 1, 0, 0, 0, 1, 0, 1, 0, 32, 0, 0, 12, 2, 255],
	[236, 255, 56, 3, 32, 3, 132, 0, 0, 0, 8, 0, 1, 0, 0, 0],
	[12, 0, 1, 0, 0, 0, 22, 0, 1, 0, 1, 0, 0, 64, 0, 64],
	[0, 0, 12, 0, 1, 0, 1, 0, 0, 0, 128, 255, 0, 2, 0, 253],
	[0, 4, 0, 248, 0, 64, 0, 224, 0, 0, 11, 255, 243, 0, 17, 255],
	[237],
].join_map(|row| row)

# Original fixture COLR table, copied with tests/fonts/inline_tables.py.
color_map_bytes : List(U8)
color_map_bytes = [
	[0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	[0, 34, 0, 0, 2, 176, 0, 0, 2, 210, 0, 0, 2, 235, 0, 0],
	[2, 247, 0, 0, 0, 32, 0, 1, 0, 0, 0, 196, 0, 2, 0, 0],
	[0, 202, 0, 3, 0, 0, 0, 207, 0, 4, 0, 0, 0, 216, 0, 5],
	[0, 0, 0, 232, 0, 6, 0, 0, 0, 252, 0, 7, 0, 0, 1, 12],
	[0, 8, 0, 0, 1, 32, 0, 9, 0, 0, 1, 65, 0, 10, 0, 0],
	[2, 154, 0, 11, 0, 0, 1, 114, 0, 12, 0, 0, 1, 117, 0, 13],
	[0, 0, 1, 148, 0, 14, 0, 0, 1, 183, 0, 15, 0, 0, 1, 191],
	[0, 16, 0, 0, 1, 203, 0, 17, 0, 0, 1, 211, 0, 18, 0, 0],
	[1, 223, 0, 19, 0, 0, 1, 235, 0, 20, 0, 0, 1, 251, 0, 21],
	[0, 0, 2, 1, 0, 22, 0, 0, 2, 11, 0, 23, 0, 0, 2, 21],
	[0, 24, 0, 0, 2, 35, 0, 25, 0, 0, 2, 41, 0, 26, 0, 0],
	[2, 51, 0, 27, 0, 0, 2, 61, 0, 28, 0, 0, 2, 75, 0, 29],
	[0, 0, 2, 83, 0, 30, 0, 0, 2, 95, 0, 31, 0, 0, 2, 107],
	[0, 32, 0, 0, 2, 123, 1, 2, 0, 0, 0, 0, 2, 0, 1, 32],
	[0, 3, 0, 1, 32, 0, 0, 0, 0, 0, 4, 0, 0, 84, 0, 10],
	[0, 20, 1, 144, 0, 50, 0, 50, 1, 244, 5, 0, 0, 105, 0, 10],
	[0, 20, 1, 144, 0, 50, 0, 50, 1, 244, 0, 0, 0, 0, 6, 0],
	[0, 48, 0, 10, 0, 20, 0, 100, 1, 44, 1, 144, 2, 88, 7, 0],
	[0, 69, 0, 10, 0, 20, 0, 100, 1, 44, 1, 144, 2, 88, 0, 0],
	[0, 0, 8, 0, 0, 12, 0, 100, 0, 200, 160, 0, 32, 0, 1, 0],
	[3, 48, 0, 0, 2, 32, 0, 16, 0, 0, 0, 64, 0, 48, 0, 255],
	[255, 48, 0, 9, 0, 0, 16, 0, 100, 0, 200, 160, 0, 32, 0, 0],
	[0, 0, 0, 1, 0, 3, 48, 0, 0, 2, 32, 0, 0, 0, 0, 6],
	[16, 0, 0, 0, 64, 0, 0, 0, 0, 6, 48, 0, 255, 255, 48, 0],
	[0, 0, 0, 6, 11, 0, 1, 12, 0, 1, 37, 0, 0, 7, 0, 1],
	[0, 0, 0, 0, 64, 0, 255, 255, 224, 0, 0, 0, 192, 0, 0, 12],
	[128, 0, 255, 247, 192, 0, 13, 0, 1, 6, 0, 0, 7, 0, 1, 0],
	[0, 0, 0, 64, 0, 255, 255, 224, 0, 0, 0, 192, 0, 0, 12, 128],
	[0, 255, 247, 192, 0, 0, 0, 0, 0, 14, 0, 0, 227, 0, 12, 255],
	[248, 15, 0, 0, 219, 0, 12, 255, 248, 0, 0, 0, 0, 16, 0, 0],
	[207, 80, 0, 48, 0, 17, 0, 0, 199, 80, 0, 48, 0, 0, 0, 0],
	[0, 18, 0, 0, 187, 80, 0, 48, 0, 0, 100, 0, 200, 19, 0, 0],
	[175, 80, 0, 48, 0, 0, 100, 0, 200, 0, 0, 0, 0, 20, 0, 0],
	[159, 80, 0, 21, 0, 0, 153, 80, 0, 0, 0, 0, 0, 22, 0, 0],
	[143, 80, 0, 0, 100, 0, 200, 23, 0, 0, 133, 80, 0, 0, 100, 0],
	[200, 0, 0, 0, 0, 24, 0, 0, 119, 16, 0, 25, 0, 0, 113, 16],
	[0, 0, 0, 0, 0, 26, 0, 0, 103, 16, 0, 0, 100, 0, 200, 27],
	[0, 0, 93, 16, 0, 0, 100, 0, 200, 0, 0, 0, 0, 28, 0, 0],
	[79, 8, 0, 240, 0, 29, 0, 0, 71, 8, 0, 240, 0, 0, 0, 0],
	[0, 30, 0, 0, 59, 8, 0, 240, 0, 0, 100, 0, 200, 31, 0, 0],
	[47, 8, 0, 240, 0, 0, 100, 0, 200, 0, 0, 0, 0, 32, 0, 0],
	[31, 23, 0, 0, 8, 10, 0, 0, 6, 0, 35, 2, 0, 2, 64, 0],
	[0, 0, 0, 2, 0, 0, 0, 12, 0, 0, 0, 23, 10, 0, 0, 6],
	[0, 34, 2, 0, 0, 48, 0, 10, 0, 0, 6, 0, 35, 2, 255, 255],
	[64, 0, 1, 0, 0, 0, 1, 0, 1, 0, 32, 0, 0, 12, 2, 255],
	[236, 255, 56, 3, 32, 3, 132, 0, 0, 0, 8, 0, 3, 0, 8, 11],
	[10, 9, 8, 7, 6, 5, 4, 0, 1, 0, 0, 0, 12, 0, 1, 0],
	[0, 0, 22, 0, 1, 0, 1, 0, 0, 64, 0, 64, 0, 0, 12, 0],
	[1, 0, 1, 0, 0, 0, 128, 255, 0, 2, 0, 253, 0, 4, 0, 248],
	[0, 64, 0, 224, 0, 0, 11, 255, 243, 0, 17, 255, 237],
].join_map(|row| row)

# Original fixture COLR table, copied with tests/fonts/inline_tables.py.
color_v0_bytes : List(U8)
color_v0_bytes = [
	[0, 0, 0, 2, 0, 0, 0, 14, 0, 0, 0, 26, 0, 2, 0, 1],
	[0, 0, 0, 2, 0, 2, 0, 2, 0, 0, 0, 34, 0, 0, 0, 35],
	[255, 255],
].join_map(|row| row)

# Only private byte-validation and preparation invariants live here;
# public behavior is exercised against the served bundle in ColorTests.
expect match TableColor.read(color_all_bytes, 36, 3, 1) {
	Ok(table) => {
		var $valid = True
		for g in 1.U32..=32 {
			match TableColor.graph(table, g) {
				Present(graph) => {
					if graph.nodes.is_empty() {
						$valid = False
					}
				}
				Absent => {
					$valid = False
				}
			}
		}
		$valid
	}
	Err(_) => False
}
expect match TableColor.read(color_map_bytes, 36, 3, 1) {
	Ok(_) => True
	Err(_) => False
}
expect match TableColor.read(color_v0_bytes, 36, 3, 0) {
	Ok(table) => TableColor.layers(table, 1) == [{ glyph: 34, color: PaletteEntry(0) }, { glyph: 35, color: Foreground }] and (
		match TableColor.graph(table, 2) {
			Present(graph) => graph.nodes == [Layers({ start: 0, len: 0 })]
			Absent => False
		}
	)
	Err(_) => False
}
expect match TableColor.read(color_all_bytes, 36, 0, 1) {
	Err(_) => True
	Ok(_) => False
}
expect match TableColor.read(color_all_bytes, 1, 3, 1) {
	Err(_) => True
	Ok(_) => False
}
expect match TableColor.read([], 36, 3, 1) {
	Err(offsets) => offsets == [0]
	Ok(_) => False
}
expect TableColor.graph(TableColor.none, 1) == Absent

# Checked offset changes exercise individual validation gates without
# introducing a dependency on test-font files into the package bundle.
color_changed : List(U8), U64, List(U8) -> List(U8)
color_changed = |bytes, at, replacement| bytes.take_first(at).concat(replacement).concat(bytes.drop_first(at + replacement.len()))

expect {
	# ColorGlyph g11 -> g11 is a reference cycle, including through glyph IDs.
	bad = color_changed(color_all_bytes, 405, [0, 11])
	match TableColor.read(bad, 36, 3, 1) {
		Err(_) => True
		Ok(_) => False
	}
}
expect {
	# A child Offset24 may not be NULL even if a header at zero is readable.
	bad = color_changed(color_all_bytes, 408, [0, 0, 0])
	match TableColor.read(bad, 36, 3, 1) {
		Err(_) => True
		Ok(_) => False
	}
}
expect {
	# Palette entry3 is out of range for a three-entry palette.
	bad = color_changed(color_all_bytes, 707, [0, 3])
	match TableColor.read(bad, 36, 3, 1) {
		Err(_) => True
		Ok(_) => False
	}
}
expect {
	# Glyph clipping references the exact font's glyph count.
	bad = color_changed(color_all_bytes, 704, [0, 36])
	match TableColor.read(bad, 36, 3, 1) {
		Err(_) => True
		Ok(_) => False
	}
}
expect {
	# Reserved entryFormat bits and inner bits wider than entry bytes fail.
	[195.U8, 15].all(
		|entry| match TableColor.read(color_changed(color_map_bytes, 748, [entry]), 36, 3, 1) {
			Err(_) => True
			Ok(_) => False
		},
	)
}
expect {
	var $safe = True
	for n in 0..<color_all_bytes.len() {
		match TableColor.read(color_all_bytes.take_first(n), 36, 3, 1) {
			Err(_) => {}
			Ok(_) => {
				$safe = False
			}
		}
	}
	$safe
}

# A valid chain at the depth boundary remains accepted, while the next
# level fails preparation before a query can consume an unbounded stack.
color_chain : U64 -> List(U8)
color_chain = |depth| [0, 1].concat(List.repeat(0, 12)).concat([0, 0, 0, 34]).concat(List.repeat(0, 16))
	.concat([0, 0, 0, 1, 0, 1, 0, 0, 0, 10])
	.concat(List.repeat([14, 0, 0, 8, 0, 0, 0, 0], depth).join_map(|b| b))
	.concat([10, 0, 0, 6, 0, 1, 2, 0, 0, 64, 0])
expect match TableColor.read(color_chain(63), 36, 3, 0) {
	Ok(_) => True
	Err(_) => False
}
expect match TableColor.read(color_chain(64), 36, 3, 0) {
	Err(_) => True
	Ok(_) => False
}
