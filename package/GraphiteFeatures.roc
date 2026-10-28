import Bytes
import Sorted
import GraphiteSettings

## Graphite's numeric feature definitions and language defaults. Prepared
## arrays retain file order because bytecode addresses features by index.
GraphiteFeatures := {
	features : List({ id : U32, default : U16, maximum : U16, alias : U64, label : U16, start : U64, end : U64 }),
	keys : List(U64),
	values : List(I16),
	labels : List(U16),
	languages : List({ tag : U32, start : U64, end : U64 }),
	settings : List(U32),
}.{

	none : GraphiteFeatures
	none = { features: [], keys: [], values: [], labels: [], languages: [], settings: [] }

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
		var $keys = List.with_capacity(count)
		var $ordered = True
		var $last_end = 0
		var $total = 0
		for i in 0..<count {
			at = 12 + width * i
			id = if (wide) Bytes.u32(bytes, at) else Bytes.u16(bytes, at)
			n = Bytes.u16(bytes, at + (if (wide) 4 else 2))
			offset_field = at + (if (wide) 8 else 4)
			offset = Bytes.u32(bytes, offset_field)
			if !Bytes.fits(offset, n * 4, bytes.len()) {
				return bad(offset_field)
			}
			if version >= 0x00020001 and Bytes.u16(bytes, at + width - 4).bitwise_and(1) != 0 and i == 0 {
				return bad(at + width - 4)
			}
			$keys = $keys.append(id.shl_wrap(32).bitwise_or(i))
			if n != 0 {
				if offset < $last_end {
					$ordered = False
				}
				$last_end = offset + n * 4
			}
			$total = $total + n
		}
		keys = Sorted.sort($keys)
		for i in 1..<count {
			if (keys.get(i - 1) ?? 0).shr_zf_wrap(32) == (keys.get(i) ?? 0).shr_zf_wrap(32) {
				return bad(12 + width * (keys.get(i) ?? 0).bitwise_and(0xFFFFFFFF))
			}
		}
		if $ordered {
			return GraphiteFeatures.read_feat_ordered(bytes, count, width, version, keys, $total)
		}
		var $spans = List.with_capacity(count)
		for i in 0..<count {
			at = 12 + width * i
			$spans = $spans.append({ start: Bytes.u32(bytes, at + (if (wide) 8 else 4)).to_u32_wrap(), count: Bytes.u16(bytes, at + (if (wide) 4 else 2)).to_u16_wrap() })
		}
		map = GraphiteSettings.make($spans, bytes.len(), Feature).map_err(|Bad(at)| Bad({ table: "Feat", offset: at }))?
		var $values = List.with_capacity(map.count)
		var $labels = List.with_capacity(map.count)
		for range in map.ranges {
			var $at = range.start
			while $at < range.end {
				$values = $values.append(Bytes.i16(bytes, $at).to_i16_wrap())
				$labels = $labels.append(Bytes.u16(bytes, $at + 2).to_u16_wrap())
				$at = $at + 4
			}
		}
		maximum = GraphiteSettings.make_maximum($values)
		var $features = List.with_capacity(count)
		for i in 0..<count {
			at = 12 + width * i
			id = if (wide) Bytes.u32(bytes, at) else Bytes.u16(bytes, at)
			span = match GraphiteSettings.locate(map, $spans.get(i) ?? crash "checked feature record") {
				Found(value) => value
				Missing => crash "checked feature setting span"
			}
			alias = version >= 0x00020001 and Bytes.u16(bytes, at + width - 4).bitwise_and(1) != 0
			prior = if (alias) $features.last() ?? crash "alias has preceding feature" else { id: 0, default: 0, maximum: 0, alias: i, label: 0, start: span.start, end: span.end }
			default = if (alias) prior.default else if (span.start == span.end) 0 else ($values.get(span.start) ?? 0).to_u16_wrap()
			largest = if (alias) prior.maximum else GraphiteSettings.maximum(maximum, span.start, span.end)
			$features = $features.append({ id: id.to_u32_wrap(), default, maximum: largest, alias: prior.alias, label: Bytes.u16(bytes, at + width - 2).to_u16_wrap(), start: if (alias) prior.start else span.start, end: if (alias) prior.end else span.end })
		}
		Ok({ ..GraphiteFeatures.none, features: $features, keys, values: $values, labels: $labels })
	}

	# Already ordered disjoint spans prove their sum fits the table. Keep
	# the ordinary compiler output path at its original allocation count.
	read_feat_ordered : List(U8), U64, U64, U64, List(U64), U64 -> Try(GraphiteFeatures, [Bad({ table : Str, offset : U64 })])
	read_feat_ordered = |bytes, count, width, version, keys, total| {
		var $values = List.with_capacity(total)
		var $labels = List.with_capacity(total)
		var $features = List.with_capacity(count)
		for i in 0..<count {
			at = 12 + width * i
			wide = version >= 0x00020000
			id = if (wide) Bytes.u32(bytes, at) else Bytes.u16(bytes, at)
			n = Bytes.u16(bytes, at + (if (wide) 4 else 2))
			offset = Bytes.u32(bytes, at + (if (wide) 8 else 4))
			start = $values.len()
			var $maximum = 0.U16
			for j in 0..<n {
				value = Bytes.u16(bytes, offset + 4 * j).to_u16_wrap()
				$maximum = $maximum.max(value)
				$values = $values.append(value.to_i16_wrap())
				$labels = $labels.append(Bytes.u16(bytes, offset + 4 * j + 2).to_u16_wrap())
			}
			alias = version >= 0x00020001 and Bytes.u16(bytes, at + width - 4).bitwise_and(1) != 0
			prior = if (alias) $features.last() ?? crash "alias has preceding feature" else { id: 0, default: 0, maximum: 0, alias: i, label: 0, start, end: $values.len() }
			$features = $features.append({ id: id.to_u32_wrap(), default: if (alias) prior.default else if (n == 0) 0 else ($values.get(start) ?? 0).to_u16_wrap(), maximum: if (alias) prior.maximum else $maximum, alias: prior.alias, label: Bytes.u16(bytes, at + width - 2).to_u16_wrap(), start: prior.start, end: prior.end })
		}
		Ok({ ..GraphiteFeatures.none, features: $features, keys, values: $values, labels: $labels })
	}

	# This independent structure check remains useful when Feat itself is
	# broken: dependent feature references are then deliberately not followed.
	sill_spans : List(U8) -> Try(List(GraphiteSettings.Span), [Bad({ table : Str, offset : U64 })])
	sill_spans = |bytes| {
		bad = |offset| Err(Bad({ table: "Sill", offset }))
		if bytes.len() < 12 or Bytes.u32(bytes, 0) != 0x00010000 {
			return bad(0)
		}
		count = Bytes.u16(bytes, 4)
		if !Bytes.fits(12, 8 * (count + 1), bytes.len()) {
			return bad(4)
		}
		var $spans = List.with_capacity(count)
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
			$spans = $spans.append({ start: start.to_u32_wrap(), count: n.to_u16_wrap() })
		}
		Ok($spans)
	}

	read_sill : GraphiteFeatures, List(U8) -> Try(GraphiteFeatures, [Bad({ table : Str, offset : U64 })])
	read_sill = |features, bytes| {
		spans = GraphiteFeatures.sill_spans(bytes)?
		var $ordered = True
		var $same = True
		var $seen = False
		var $first = { start: 0.U32, count: 0.U16 }
		var $last_end = 0
		var $total = 0
		for span in spans {
			if span.count != 0 {
				if $seen and span != $first {
					$same = False
				}
				if !$seen {
					$first = span
					$seen = True
				}
				if span.start.to_u64() < $last_end {
					$ordered = False
				}
				$last_end = span.start.to_u64() + span.count.to_u64() * 8
			}
			$total = $total + span.count.to_u64()
		}
		var $languages = List.with_capacity(spans.len())
		if $ordered or $same {
			var $settings = List.with_capacity(if ($ordered) $total else $first.count.to_u64())
			if !$ordered {
				$settings = GraphiteFeatures.append_settings(features, bytes, $first.start.to_u64(), $first.count.to_u64(), $settings)?
			}
			for i in 0..<spans.len() {
				span = spans.get(i) ?? crash "checked language span"
				start = if ($ordered) $settings.len() else 0
				if $ordered {
					$settings = GraphiteFeatures.append_settings(features, bytes, span.start.to_u64(), span.count.to_u64(), $settings)?
				}
				$languages = $languages.append({ tag: Bytes.u32(bytes, 12 + 8 * i).to_u32_wrap(), start, end: start + span.count.to_u64() })
			}
			return Ok({ ..features, languages: $languages, settings: $settings })
		}
		map = GraphiteSettings.make(spans, bytes.len(), Language).map_err(|Bad(at)| Bad({ table: "Sill", offset: at }))?
		var $settings = List.with_capacity(map.count)
		for range in map.ranges {
			$settings = GraphiteFeatures.append_settings(features, bytes, range.start, (range.end - range.start) // 8, $settings)?
		}
		for i in 0..<spans.len() {
			span = match GraphiteSettings.locate(map, spans.get(i) ?? crash "checked language record") {
				Found(value) => value
				Missing => crash "checked language setting span"
			}
			$languages = $languages.append({ tag: Bytes.u32(bytes, 12 + 8 * i).to_u32_wrap(), start: span.start, end: span.end })
		}
		Ok({ ..features, languages: $languages, settings: $settings })
	}

	append_settings : GraphiteFeatures, List(U8), U64, U64, List(U32) -> Try(List(U32), [Bad({ table : Str, offset : U64 })])
	append_settings = |features, bytes, start, count, settings| {
		var $settings = settings
		for i in 0..<count {
			at = start + 8 * i
			index = GraphiteFeatures.find(features, Bytes.u32(bytes, at).to_u32_wrap())
			if index == GraphiteFeatures.missing {
				return Err(Bad({ table: "Sill", offset: at }))
			}
			feature = features.features.get(index) ?? crash "resolved feature index"
			value = Bytes.u16(bytes, at + 4)
			if value > feature.maximum.to_u64() {
				return Err(Bad({ table: "Sill", offset: at + 4 }))
			}
			$settings = $settings.append(index.to_u32_wrap().shl_wrap(16).bitwise_or(value.to_u32_wrap()))
		}
		Ok($settings)
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

	normalize_language : U32 -> U32
	normalize_language = |language| {
		var $tag = language
		var $shift = 0.U8
		while $shift < 32 and $tag.shr_zf_wrap($shift).bitwise_and(255) == 32 {
			$tag = $tag.bitwise_and((255.U32).shl_wrap($shift).bitwise_xor(0xFFFFFFFF))
			$shift = $shift + 8
		}
		$tag
	}

	defaults : GraphiteFeatures, U32 -> List(U16)
	defaults = |table, requested_language| {
		language = GraphiteFeatures.normalize_language(requested_language)
		var $matched = False
		var $values = table.features.map(|f| f.default)
		var $lo = 0
		var $hi = table.languages.len()
		while $lo < $hi {
			mid = $lo + ($hi - $lo) // 2
			entry = table.languages.get(mid) ?? crash "language search index"
			if entry.tag < language {
				$lo = mid + 1
			} else {
				$hi = mid
			}
		}
		match table.languages.get($lo) {
			Ok(entry) if entry.tag == language => {
				$matched = True
				for j in entry.start..<entry.end {
					setting = table.settings.get(j) ?? crash "checked language setting index"
					feature = table.features.get(setting.shr_zf_wrap(16).to_u64()) ?? crash "checked language feature index"
					$values = $values.set(feature.alias, setting.to_u16_wrap()) ?? []
				}
			}
			_ => {}
		}
		if $matched {
			index = GraphiteFeatures.find(table, 1)
			match table.features.get(index) {
				Ok(feature) if feature.start == feature.end => {
					$values = $values.set(feature.alias, language.to_u16_wrap()) ?? []
				}
				_ => {}
			}
		}
		for i in 0..<table.features.len() {
			feature = table.features.get(i) ?? crash "aligned feature index"
			if feature.alias != i {
				$values = $values.set(i, $values.get(feature.alias) ?? 0) ?? []
			}
		}
		$values
	}

	resolve : GraphiteFeatures, U32, List({ id : U32, value : I16 }) -> List(U16)
	resolve = |table, language, settings| {
		var $values = GraphiteFeatures.defaults(table, language)
		for setting in settings {
			index = GraphiteFeatures.find(table, setting.id)
			match table.features.get(index) {
				Ok(feature) if setting.value.to_u16_wrap() <= feature.maximum => {
					$values = $values.set(feature.alias, setting.value.to_u16_wrap()) ?? []
				}
				_ => {}
			}
		}
		for i in 0..<table.features.len() {
			feature = table.features.get(i) ?? crash "aligned feature index"
			if feature.alias != i {
				$values = $values.set(i, $values.get(feature.alias) ?? 0) ?? []
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
		var $i = found.alias
		while $i < table.features.len() and (table.features.get($i) ?? found).alias == found.alias {
			$values = $values.set($i, value) ?? []
			$i = $i + 1
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

expect {
	# The legacy, zero-setting language feature exposes the low half of a
	# matched Sill language tag
	# An ordinary declared feature1 stays ordinary.
	language_feature = { id: 1.U32, default: 0.U16, maximum: 0.U16, alias: 0.U64, label: 0.U16, start: 0.U64, end: 0.U64 }
	table = { ..GraphiteFeatures.none, features: [language_feature], keys: [(1.U64).shl_wrap(32)], languages: [{ tag: 0x6B737700, start: 0, end: 0 }] }
	GraphiteFeatures.defaults(table, 0x6B737700) == [0x7700] and GraphiteFeatures.defaults(table, 0x6B737720) == [0x7700] and GraphiteFeatures.defaults(table, 0) == [0] and GraphiteFeatures.defaults({ ..table, features: [{ ..language_feature, end: 1 }] }, 0x6B737700) == [0]
}

expect {
	# Two language records reuse one array. Pooled cells stay proportional
	# to source bytes while both languages retain their complete settings.
	shared = [0.U8, 1, 0, 0, 0, 2, 0, 16, 0, 1, 0, 0, 101, 110, 0, 0, 0, 2, 0, 36, 102, 114, 0, 0, 0, 2, 0, 36, 128, 128, 128, 128, 0, 0, 0, 52, 0, 0, 0, 100, 0, 1, 0, 0, 0, 0, 0, 100, 0, 1, 0, 0]
	base = GraphiteFeatures.read_feat(feat) ?? crash "original feature table"
	table = GraphiteFeatures.read_sill(base, shared) ?? crash "original shared language spans"
	table.settings.len() == 2 and GraphiteFeatures.defaults(table, 0x656E0000) == [1] and GraphiteFeatures.defaults(table, 0x66720000) == [1]
}
expect {
	shared = [0.U8, 2, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 100, 0, 2, 0, 0, 0, 0, 0, 44, 128, 0, 1, 0, 0, 0, 0, 101, 0, 2, 0, 0, 0, 0, 0, 44, 128, 0, 1, 0, 0, 0, 1, 1, 0, 1, 1, 2]
	table = GraphiteFeatures.read_feat(shared) ?? crash "original shared feature settings"
	table.values.len() == 2 and table.labels.len() == 2 and GraphiteFeatures.resolve(table, 0, [{ id: 100, value: 1 }]) == [1, 0]
}
expect {
	# An empty alias inherits its parent's range and maximum, rather than
	# becoming an unrelated feature that rejects every nonzero value.
	aliased = [0.U8, 2, 0, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 100, 0, 2, 0, 0, 0, 0, 0, 44, 128, 0, 1, 0, 0, 0, 0, 101, 0, 0, 0, 0, 0, 0, 0, 52, 0, 1, 1, 0, 0, 0, 1, 1, 0, 1, 1, 2]
	table = GraphiteFeatures.read_feat(aliased) ?? crash "original feature alias"
	GraphiteFeatures.resolve(table, 0, [{ id: 101, value: 1 }]) == [1, 1]
}

expect {
	# Partial overlap needs shared affine views, rather than merely detecting
	# identical arrays. Duplicate settings keep their original last-wins order.
	shared = [0.U8, 1, 0, 0, 0, 3, 0, 16, 0, 1, 0, 8, 101, 110, 0, 0, 0, 2, 0, 44, 102, 114, 0, 0, 0, 2, 0, 52, 107, 115, 119, 0, 0, 3, 0, 44, 128, 128, 128, 128, 0, 0, 0, 68, 0, 0, 0, 100, 0, 1, 0, 0, 0, 0, 0, 100, 0, 0, 0, 0, 0, 0, 0, 100, 0, 1, 0, 0]
	base = GraphiteFeatures.read_feat(feat) ?? crash "original feature table"
	table = GraphiteFeatures.read_sill(base, shared) ?? crash "original overlapping language spans"
	table.settings.len() == 3 and GraphiteFeatures.defaults(table, 0x656E0000) == [0] and GraphiteFeatures.defaults(table, 0x66720000) == [1] and GraphiteFeatures.defaults(table, 0x6B737700) == [1]
}
