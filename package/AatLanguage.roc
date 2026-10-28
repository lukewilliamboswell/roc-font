import Bytes

## Checked Apple language tags used by morphing feature type 39.
## Tags stay index aligned with the font's selectors.
AatLanguage := { bytes : List(U8), ranges : List({ start : U64, length : U64 }) }.{
	none : AatLanguage
	none = { bytes: [], ranges: [] }

	read : List(U8) -> Try(AatLanguage, [Bad(U64)])
	read = |bytes| {
		if bytes.len() < 12 or Bytes.u32(bytes, 0) < 1 {
			return Err(Bad(0))
		}
		count = Bytes.u32(bytes, 8)
		if !Bytes.fits(12, count * 4, bytes.len()) {
			return Err(Bad(8))
		}
		var $ranges = List.with_capacity(count)
		for i in 0..<count {
			at = 12 + i * 4
			start = Bytes.u16(bytes, at)
			length = Bytes.u16(bytes, at + 2)
			if !Bytes.fits(start, length, bytes.len()) {
				return Err(Bad(at))
			}
			$ranges = $ranges.append({ start, length })
		}
		Ok({ bytes, ranges: $ranges })
	}

	canonical : List(U8) -> List(U8)
	canonical = |bytes| {
		var $tag = []
		for b in bytes {
			if b >= 'A' and b <= 'Z' {
				$tag = $tag.append(b + 32)
			}
			else if b == '_' {
				$tag = $tag.append('-')
			}
			else if (b >= 'a' and b <= 'z') or (b >= '0' and b <= '9') or b == '-' {
				$tag = $tag.append(b)
			}
			else {
				break
			}
		}
		$tag
	}

	selectors : AatLanguage, Str -> List(U64)
	selectors = |table, language| {
		specific = AatLanguage.canonical(language.to_utf8())
		var $selectors = []
		for i in 0..<table.ranges.len() {
			range = table.ranges.get(i) ?? { start: 0, length: 0 }
			tag = AatLanguage.canonical(table.bytes.sublist({ start: range.start, len: range.length }))
			if !tag.is_empty() and tag.len() <= specific.len() and specific.take_first(tag.len()) == tag and (specific.len() == tag.len() or (specific.get(tag.len()) ?? 0) == '-') {
				$selectors = $selectors.append(i + 1)
			}
		}
		$selectors
	}
}

expect AatLanguage.read([]).is_err()
expect AatLanguage.read([0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 16, 0, 2, 'e']).is_err()
expect {
	match AatLanguage.read([0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 16, 0, 2, 'e', 'n']) {
		Ok(table) => AatLanguage.selectors(table, "en-US") == [1] and AatLanguage.selectors(table, "eng").is_empty()
		Err(_) => False
	}
}
