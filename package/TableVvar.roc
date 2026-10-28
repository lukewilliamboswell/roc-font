import TableVar
import Bytes

## Vertical advance and origin variation maps over the shared item store.
TableVvar := {
	store : TableVar.Store,
	advances : [Implicit, Mapped(TableVar.DeltaMap)],
	top : [Present(TableVar.DeltaMap), Absent],
	bottom : [Present(TableVar.DeltaMap), Absent],
	origins : [Present(TableVar.DeltaMap), Absent],
}.{

	read : List(U8), U64, U64 -> Try(TableVvar, List(TableVar.Problem))
	read = |bytes, axis_count, glyph_count| {
		bad = |at, reason| Err([{ table: "VVAR", offset: at, reason }])
		if bytes.len() < 24 {
			return bad(0, Truncated)
		}
		if Bytes.u32(bytes, 0) != 0x00010000 {
			return bad(0, UnsupportedVersion)
		}
		store_at = Bytes.u32(bytes, 4)
		if store_at == 0 {
			return bad(4, Truncated)
		}
		store = TableVar.read_store(bytes, "VVAR", store_at, axis_count)?
		advance_at = Bytes.u32(bytes, 8)
		advances = if advance_at == 0 {
			if (store.item_counts.get(0) ?? 0) < glyph_count {
				return bad(store_at, ItemCount)
			}
			Implicit
		} else Mapped(TableVar.read_delta_map(bytes, "VVAR", advance_at, store)?)
		optional = |field| {
			at = Bytes.u32(bytes, field)
			if (at == 0) Ok(Absent) else Ok(Present(TableVar.read_delta_map(bytes, "VVAR", at, store)?))
		}
		# All supplied maps are validated, including unused side bearings.
		top = optional(12)?
		bottom = optional(16)?
		origins = optional(20)?
		Ok({ store, advances, top, bottom, origins })
	}

	scalars : TableVvar, List(I16) -> List(U32)
	scalars = |table, coords| TableVar.region_scalars(table.store, coords)

	advance_delta : TableVvar, List(U32), U64 -> I64
	advance_delta = |table, factors, glyph| {
		index = match table.advances {
			Implicit => { outer: 0, inner: glyph }
			Mapped(map) => TableVar.map_entry(map, glyph)
		}
		TableVar.f32_round_half_up(TableVar.delta(table.store, factors, index.outer, index.inner))
	}

	origin_delta : TableVvar, List(U32), U64 -> I64
	origin_delta = |table, factors, glyph|
		match table.origins {
			Absent => 0
			Present(map) => {
				index = TableVar.map_entry(map, glyph)
				TableVar.f32_round_half_up(TableVar.delta(table.store, factors, index.outer, index.inner))
			}
		}
}

expect match TableVvar.read([], 1, 1) {
	Err(problems) => problems == [{ table: "VVAR", offset: 0, reason: Truncated }]
	_ => False
}
expect match TableVvar.read(List.repeat(0, 24), 1, 1) {
	Err(problems) => problems == [{ table: "VVAR", offset: 0, reason: UnsupportedVersion }]
	_ => False
}
expect match TableVvar.read([0, 1, 0, 0].concat(List.repeat(0, 20)), 1, 1) {
	Err(problems) => problems == [{ table: "VVAR", offset: 4, reason: Truncated }]
	_ => False
}

# fontTools4.61.1 original one-region store: implicit glyph rows100/200.
fixture = [0, 1, 0, 0, 0, 0, 0, 24, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 12, 0, 1, 0, 0, 0, 22, 0, 1, 0, 1, 0, 0, 64, 0, 64, 0, 0, 2, 0, 1, 0, 1, 0, 0, 0, 100, 0, 200]
expect {
	match TableVvar.read(fixture, 1, 2) {
		Ok(table) => {
			factors = TableVvar.scalars(table, [8192])
			TableVvar.advance_delta(table, factors, 0) == 50 and TableVvar.advance_delta(table, factors, 1) == 100 and TableVvar.origin_delta(table, factors, 0) == 0
		}
		Err(_) => False
	}
}
expect TableVvar.read(fixture, 2, 2).is_err()
expect TableVvar.read(fixture, 1, 3).is_err()
expect TableVvar.read(fixture.drop_last(1), 1, 2).is_err()
