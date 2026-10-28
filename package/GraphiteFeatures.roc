import Bytes
import Sorted

## Graphite's numeric feature definitions and language defaults. Prepared
## arrays retain file order because bytecode addresses features by index.
GraphiteFeatures := {
	features : List({ id : U32, default : U16, maximum : U16, alias : U64, label : U16, start : U64, end : U64 }),
	keys : List(U64),
	values : List(I16),
	labels : List(U16),
	languages : List(U32),
	language_starts : List(U64),
	settings : List({ feature : U64, value : U16 }),
}.{

	none : GraphiteFeatures
	none = { features: [], keys: [], values: [], labels: [], languages: [], language_starts: [0], settings: [] }

	read : [Present(List(U8)), Absent], [Present(List(U8)), Absent] -> Try(GraphiteFeatures, [Bad({ table : Str, offset : U64 })])
	read = |feat, sill| {
		base = match feat {
			Absent => GraphiteFeatures.none
			Present(bytes) => GraphiteFeatures.read_feat(bytes)?
		}
		match sill {
			Absent => Ok(base)
			Present(bytes) => GraphiteFeatures.read_sill(base, bytes)
		}
	}

	read_feat : List(U8) -> Try(GraphiteFeatures, [Bad({ table : Str, offset : U64 })])
	read_feat = |bytes| {
		bad = |offset| Err(Bad({ table: "Feat", offset }))
		if bytes.len() < 12 {
			return bad(0)
		}
		version = Bytes.u32(bytes, 0)
		if version < 0x00010000 or version > 0x00020001 {
			return bad(0)
		}
		wide = version >= 0x00020000
		width = if (wide) 16 else 12
		count = Bytes.u16(bytes, 4)
		if !Bytes.fits(12, width * count, bytes.len()) {
			return bad(4)
		}
		var $settings_count = 0
		var $keys = List.with_capacity(count)
		for i in 0..<count {
			at = 12 + width * i
			start = Bytes.u32(bytes, at + (if (wide) 8 else 4))
			n = Bytes.u16(bytes, at + (if (wide) 4 else 2))
			if !Bytes.fits(start, n * 4, bytes.len()) {
				return bad(at + (if (wide) 8 else 4))
			}
			id = if (wide) Bytes.u32(bytes, at) else Bytes.u16(bytes, at)
			$keys = $keys.append(id.shl_wrap(32).bitwise_or(i))
			$settings_count = $settings_count + n
		}
		keys = Sorted.sort($keys)
		for i in 1..<count {
			if (keys.get(i - 1) ?? 0).shr_zf_wrap(32) == (keys.get(i) ?? 0).shr_zf_wrap(32) {
				return bad(12 + width * (keys.get(i) ?? 0).bitwise_and(0xFFFFFFFF))
			}
		}
		var $features = List.with_capacity(count)
		var $values = List.with_capacity($settings_count)
		var $labels = List.with_capacity($settings_count)
		for i in 0..<count {
			at = 12 + width * i
			start = Bytes.u32(bytes, at + (if (wide) 8 else 4))
			n = Bytes.u16(bytes, at + (if (wide) 4 else 2))
			id = if (wide) Bytes.u32(bytes, at) else Bytes.u16(bytes, at)
			flags = Bytes.u16(bytes, at + width - 4)
			alias = version >= 0x00020001 and flags.bitwise_and(1) != 0
			if alias and i == 0 {
				return bad(at + width - 4)
			}
			first = if (n == 0) 0 else Bytes.u16(bytes, start)
			var $maximum = first
			span_start = $values.len()
			for j in 0..<n {
				value = Bytes.u16(bytes, start + 4 * j)
				$maximum = $maximum.max(value)
				$values = $values.append(Bytes.i16(bytes, start + 4 * j).to_i16_wrap())
				$labels = $labels.append(Bytes.u16(bytes, start + 4 * j + 2).to_u16_wrap())
			}
			previous = if (alias) ($features.last() ?? { id: 0, default: 0, maximum: 0, alias: 0, label: 0, start: 0, end: 0 }).alias else i
			$features = $features.append({ id: id.to_u32_wrap(), default: first.to_u16_wrap(), maximum: $maximum.to_u16_wrap(), alias: previous, label: Bytes.u16(bytes, at + width - 2).to_u16_wrap(), start: span_start, end: $values.len() })
		}
		Ok({ ..GraphiteFeatures.none, features: $features, keys, values: $values, labels: $labels })
	}

	read_sill : GraphiteFeatures, List(U8) -> Try(GraphiteFeatures, [Bad({ table : Str, offset : U64 })])
	read_sill = |features, bytes| {
		bad = |offset| Err(Bad({ table: "Sill", offset }))
		if bytes.len() < 12 or Bytes.u32(bytes, 0) != 0x00010000 {
			return bad(0)
		}
		count = Bytes.u16(bytes, 4)
		if !Bytes.fits(12, 8 * (count + 1), bytes.len()) {
			return bad(4)
		}
		var $total = 0
		var $previous = 0
		for i in 0..<count {
			at = 12 + i * 8
			language = Bytes.u32(bytes, at)
			if i != 0 and language <= $previous {
				return bad(at)
			}
			$previous = language
			n = Bytes.u16(bytes, at + 4)
			start = Bytes.u16(bytes, at + 6)
			if !Bytes.fits(start, 8 * n, bytes.len()) {
				return bad(at + 6)
			}
			for j in 0..<n {
				index = GraphiteFeatures.find(features, Bytes.u32(bytes, start + j * 8).to_u32_wrap())
				if index == GraphiteFeatures.missing {
					return bad(start + j * 8)
				}
				feature = features.features.get(index) ?? return bad(start + j * 8)
				if Bytes.u16(bytes, start + j * 8 + 4) > feature.maximum.to_u64() {
					return bad(start + j * 8 + 4)
				}
			}
			$total = $total + n
		}
		var $languages = List.with_capacity(count)
		var $starts = List.with_capacity(count + 1)
		var $settings = List.with_capacity($total)
		for i in 0..<count {
			at = 12 + i * 8
			$languages = $languages.append(Bytes.u32(bytes, at).to_u32_wrap())
			$starts = $starts.append($settings.len())
			start = Bytes.u16(bytes, at + 6)
			for j in 0..<Bytes.u16(bytes, at + 4) {
				field = start + j * 8
				$settings = $settings.append({ feature: GraphiteFeatures.find(features, Bytes.u32(bytes, field).to_u32_wrap()), value: Bytes.u16(bytes, field + 4).to_u16_wrap() })
			}
		}
		Ok({ ..features, languages: $languages, language_starts: $starts.append($settings.len()), settings: $settings })
	}

	missing : U64
	missing = 0xFFFFFFFFFFFFFFFF

	find : GraphiteFeatures, U32 -> U64
	find = |table, id| {
		var $lo = 0
		var $hi = table.keys.len()
		while $lo < $hi {
			mid = $lo + ($hi - $lo) // 2
			key = table.keys.get(mid) ?? 0
			if key.shr_zf_wrap(32) < id.to_u64() {
				$lo = mid + 1
			} else {
				$hi = mid
			}
		}
		match table.keys.get($lo) {
			Ok(key) if key.shr_zf_wrap(32) == id.to_u64() => key.bitwise_and(0xFFFFFFFF)
			_ => GraphiteFeatures.missing
		}
	}

	defaults : GraphiteFeatures, U32 -> List(U16)
	defaults = |table, language| {
		var $values = table.features.map(|f| f.default)
		for i in 0..<table.languages.len() {
			if table.languages.get(i) == Ok(language) {
				start = table.language_starts.get(i) ?? 0
				end = table.language_starts.get(i + 1) ?? 0
				for j in start..<end {
					setting = table.settings.get(j) ?? { feature: 0, value: 0 }
					$values = GraphiteFeatures.set(table, $values, setting.feature, setting.value)
				}
				break
			}
		}
		$values
	}

	set : GraphiteFeatures, List(U16), U64, U16 -> List(U16)
	set = |table, values, feature, value| {
		found = table.features.get(feature) ?? return values
		if value > found.maximum {
			return values
		}
		var $values = values
		for i in 0..<table.features.len() {
			if (table.features.get(i) ?? found).alias == found.alias {
				$values = $values.set(i, value) ?? []
			}
		}
		$values
	}
}

expect GraphiteFeatures.read_feat([]).is_err()
expect GraphiteFeatures.read_sill(GraphiteFeatures.none, []).is_err()
expect GraphiteFeatures.find(GraphiteFeatures.none, 1) == GraphiteFeatures.missing
expect GraphiteFeatures.defaults(GraphiteFeatures.none, 0) == []

# Original feature100 with values0/1, and language"en" selecting1.
feat = [0, 2, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 100, 0, 2, 0, 0, 0, 0, 0, 28, 128, 0, 1, 0, 0, 0, 1, 1, 0, 1, 1, 2]

sill = [0, 1, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 101, 110, 0, 0, 0, 1, 0, 28, 128, 128, 128, 128, 0, 0, 0, 36, 0, 0, 0, 100, 0, 1, 0, 0]
expect {
	match GraphiteFeatures.read(Present(feat), Present(sill)) {
		Ok(table) => GraphiteFeatures.find(table, 100) == 0 and GraphiteFeatures.find(table, 101) == GraphiteFeatures.missing and GraphiteFeatures.defaults(table, 0) == [0] and GraphiteFeatures.defaults(table, 0x656E0000) == [1]
		Err(_) => False
	}
}
expect GraphiteFeatures.read(Present(feat.drop_last(1)), Absent).is_err()
expect GraphiteFeatures.read(Present(feat), Present(sill.set(31, 101) ?? [])).is_err()
expect GraphiteFeatures.read(Present(feat), Present(sill.set(33, 2) ?? [])).is_err()
