import Bytes

## Apple feature declarations. Internal. A feature with no selectors is
## not exposed. Selector/name records are checked even when only the
## exclusivity bit is needed for shaping.
AatFeatures := { entries : List(Feature) }.{

	Feature : { type : U64, exclusive : Bool, setting_start : U64, setting_count : U64 }
	none : AatFeatures
	none = { entries: [] }

	read : List(U8) -> Try(AatFeatures, [Bad(U64)])
	read = |bytes| {
		if bytes.len() < 12 or Bytes.u32(bytes, 0) != 0x00010000 {
			return Err(Bad(0))
		}
		count = Bytes.u16(bytes, 4)
		if !Bytes.fits(12, count * 12, bytes.len()) {
			return Err(Bad(4))
		}
		var $entries = List.with_capacity(count)
		var $previous = 0
		for i in 0..<count {
			at = 12 + i * 12
			type = Bytes.u16(bytes, at)
			settings = Bytes.u16(bytes, at + 2)
			start = Bytes.u32(bytes, at + 4)
			flags = Bytes.u16(bytes, at + 8)
			if i != 0 and type <= $previous {
				return Err(Bad(at))
			}
			if !Bytes.fits(start, settings * 4, bytes.len()) {
				return Err(Bad(at + 4))
			}
			exclusive = flags.bitwise_and(0x8000) != 0
			default = if (flags.bitwise_and(0x4000) != 0) flags.bitwise_and(255) else 0
			if exclusive and settings != 0 and default >= settings {
				return Err(Bad(at + 8))
			}
			$entries = $entries.append({ type, exclusive, setting_start: start, setting_count: settings })
			$previous = type
		}
		Ok({ entries: $entries })
	}

	feature : AatFeatures, U64 -> [Present({ exclusive : Bool }), Absent]
	feature = |table, type| {
		var $lo = 0
		var $hi = table.entries.len()
		while $lo < $hi {
			mid = $lo + ($hi - $lo) // 2
			e = table.entries.get(mid) ?? { type: 0, exclusive: False, setting_start: 0, setting_count: 0 }
			if type < e.type {
				$hi = mid
			} else if type > e.type {
				$lo = mid + 1
			} else {
				return if (e.setting_count == 0) Absent else Present({ exclusive: e.exclusive })
			}
		}
		Absent
	}
}

expect match AatFeatures.read([0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]) {
	Ok(t) => AatFeatures.feature(t, 1) == Absent
	Err(_) => False
}
expect match AatFeatures.read([0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0]) {
	Err(Bad(4)) => True
	_ => False
}
