import Bytes

## Graphite's optional LZ4 block envelope. Internal. A validation pass
## proves the exact output length and every backward reference before
## allocating output. The second pass repeats the bounded byte grammar.
GraphiteCompression :: {}.{

	expand : List(U8), U64, U64 -> Try(List(U8), [Bad(U64), OverLimit(Str)])
	expand = |bytes, compressed_version, max_output| {
		if bytes.len() < 4 {
			return Err(Bad(0))
		}
		version = Bytes.u32(bytes, 0)
		if version < compressed_version {
			return Ok(bytes)
		}
		if bytes.len() < 8 {
			return Err(Bad(4))
		}
		header = Bytes.u32(bytes, 4)
		scheme = header.shr_zf_wrap(27)
		if scheme == 0 {
			return Ok(bytes)
		}
		if scheme != 1 {
			return Err(Bad(4))
		}
		size = header.bitwise_and(0x07FFFFFF)
		if size > max_output {
			return Err(OverLimit("graphite_uncompressed_bytes"))
		}
		if size < 8 {
			return Err(Bad(4))
		}
		GraphiteCompression.validate(bytes, 8, size)?
		var $out = List.with_capacity(size)
		var $at = 8
		while $at < bytes.len() {
			token = Bytes.u8(bytes, $at)
			literal = GraphiteCompression.length(bytes, $at + 1, token.shr_zf_wrap(4))?
			for i in 0..<literal.count {
				$out = $out.append(Bytes.u8(bytes, literal.next + i).to_u8_wrap())
			}
			$at = literal.next + literal.count
			if $at == bytes.len() {
				break
			}
			distance = Bytes.u8(bytes, $at) + 256 * Bytes.u8(bytes, $at + 1)
			backref = GraphiteCompression.length(bytes, $at + 2, token.bitwise_and(15))?
			for _ in 0..<(backref.count + 4) {
				# Validation proved distance is nonzero and at most output.len;
				# copying one byte at a time implements overlapping matches.
				next = $out.get($out.len() - distance) ?? 0
				$out = $out.append(next)
			}
			$at = backref.next
		}
		if Bytes.u32($out, 0) != version or Bytes.u32($out, 4).shr_zf_wrap(27) != 0 {
			return Err(Bad(8))
		}
		Ok($out)
	}

	length : List(U8), U64, U64 -> Try({ count : U64, next : U64 }, [Bad(U64)])
	length = |bytes, start, nibble| {
		var $count = nibble
		var $at = start
		if nibble == 15 {
			var $more = True
			while $more {
				if $at >= bytes.len() {
					return Err(Bad($at))
				}
				b = Bytes.u8(bytes, $at)
				$count = $count + b
				$at = $at + 1
				$more = b == 255
			}
		}
		Ok({ count: $count, next: $at })
	}

	validate : List(U8), U64, U64 -> Try({}, [Bad(U64)])
	validate = |bytes, start, size| {
		var $at = start
		var $produced = 0
		while $at < bytes.len() {
			token = Bytes.u8(bytes, $at)
			literal = GraphiteCompression.length(bytes, $at + 1, token.shr_zf_wrap(4))?
			if !Bytes.fits(literal.next, literal.count, bytes.len()) or !Bytes.fits($produced, literal.count, size) {
				return Err(Bad($at))
			}
			$produced = $produced + literal.count
			$at = literal.next + literal.count
			if $at == bytes.len() {
				if literal.count < 5 or $produced != size {
					return Err(Bad($at))
				}
				return Ok({})
			}
			if !Bytes.fits($at, 2, bytes.len()) {
				return Err(Bad($at))
			}
			distance = Bytes.u8(bytes, $at) + Bytes.u8(bytes, $at + 1) * 256
			if distance == 0 or distance > $produced {
				return Err(Bad($at))
			}
			backref = GraphiteCompression.length(bytes, $at + 2, token.bitwise_and(15))?
			if !Bytes.fits($produced, backref.count + 4, size) {
				return Err(Bad($at))
			}
			$produced = $produced + backref.count + 4
			$at = backref.next
		}
		Err(Bad($at))
	}
}

expect GraphiteCompression.validate([0x50, 1, 2, 3, 4, 5], 0, 5) == Ok({})
expect GraphiteCompression.validate([0x10, 1, 0, 0, 0x50, 1, 2, 3, 4, 5], 0, 10) == Err(Bad(2))
expect GraphiteCompression.validate([0x10, 7, 1, 0, 0x50, 1, 2, 3, 4, 5], 0, 10) == Ok({})
expect GraphiteCompression.validate([0xF0, 255], 0, 5) == Err(Bad(2))
