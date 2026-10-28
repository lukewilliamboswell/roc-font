import Bytes
import GraphiteAttributes
import GraphiteFeatures
import GraphiteSilf
import GraphiteCompression

## Prepared Graphite font programs. Reading proves every table span and
## bytecode operand before runtime; text-dependent arithmetic can still
## cause the explicitly reported program-abort result of this language.
TableGraphite := {
	attributes : GraphiteAttributes,
	features : GraphiteFeatures,
	program : GraphiteSilf,
	glyph_count : U64,
	real_glyph_count : U64,
}.{

	Tables : { silf : List(U8), gloc : List(U8), glat : List(U8), feat : [Present(List(U8)), Absent], sill : [Present(List(U8)), Absent], glyph_count : U64 }
	Problem : { table : Str, offset : U64, reason : [Malformed, TooMuchWork] }

	none : TableGraphite
	none = { attributes: GraphiteAttributes.none, features: GraphiteFeatures.none, program: GraphiteSilf.none, glyph_count: 0, real_glyph_count: 0 }

	read : Tables, U64 -> Try(TableGraphite, List(Problem))
	read = |tables, max_bytes| {
		var $problems = []
		features = match GraphiteFeatures.read(tables.feat, tables.sill) {
			Ok(value) => value
			Err(Bad({ table, offset })) => {
				$problems = $problems.append({ table, offset, reason: Malformed })
				if table == "Feat" {
					match tables.sill {
						Present(data) => match GraphiteFeatures.sill_spans(data) {
							Err(Bad(problem)) => {
								$problems = $problems.append({ table: problem.table, offset: problem.offset, reason: Malformed })
							}
							Ok(_) => {}
						}
						Absent => {}
					}
				}
				GraphiteFeatures.none
			}
		}
		count = match TableGraphite.gloc_count(tables.gloc) {
			Ok(value) => value
			Err(Bad(at)) => {
				$problems = $problems.append({ table: "Gloc", offset: at, reason: Malformed })
				0
			}
		}
		attributes = if count != 0 {
			match GraphiteAttributes.read(tables.gloc, tables.glat, count, max_bytes) {
				Ok(value) => value
				Err(Bad({ table, offset })) => {
					$problems = $problems.append({ table, offset, reason: Malformed })
					GraphiteAttributes.none
				}
				Err(Bads(found)) => {
					$problems = $problems.concat(found.map(|problem| { table: problem.table, offset: problem.offset, reason: Malformed }))
					GraphiteAttributes.none
				}
				Err(OverLimit(_)) => {
					$problems = $problems.append({ table: "Glat", offset: 0, reason: TooMuchWork })
					GraphiteAttributes.none
				}
			}
		} else {
			# Glat compression/header errors remain independent of a broken
			# Gloc directory. Validate that envelope without following offsets.
			match GraphiteCompression.expand(tables.glat, 0x00030000, max_bytes) {
				Ok(data) => {
					if data.len() < 4 or Bytes.u32(data, 0) < 0x00010000 or Bytes.u32(data, 0) > 0x00030000 {
						$problems = $problems.append({ table: "Glat", offset: 0, reason: Malformed })
					}
				}
				Err(Bad(at)) => {
					$problems = $problems.append({ table: "Glat", offset: at, reason: Malformed })
				}
				Err(OverLimit(_)) => {
					$problems = $problems.append({ table: "Glat", offset: 0, reason: TooMuchWork })
				}
			}
			GraphiteAttributes.none
		}
		# Generous placeholder counts only allow independent Silf structure
		# checks after another table failed. Such a result is never returned.
		valid_dependencies = $problems.is_empty()
		program = match GraphiteSilf.read(tables.silf, if (count == 0) 65536 else count, if (valid_dependencies) attributes.attribute_count else 65536, if (valid_dependencies) features.features.len() else 256, max_bytes) {
			Ok(value) => value
			Err(Bad(offset)) => {
				$problems = $problems.append({ table: "Silf", offset, reason: Malformed })
				GraphiteSilf.none
			}
			Err(OverLimit(_)) => {
				$problems = $problems.append({ table: "Silf", offset: 0, reason: TooMuchWork })
				GraphiteSilf.none
			}
		}
		if attributes.major != 0 and attributes.major < 3 and program.passes.any(|pass| pass.flags.bitwise_and(31) != 0) {
			$problems = $problems.append({ table: "Glat", offset: 0, reason: Malformed })
		}
		if $problems.is_empty() {
			Ok({ attributes, features, program, glyph_count: count, real_glyph_count: tables.glyph_count })
		} else Err($problems)
	}

	gloc_count : List(U8) -> Try(U64, [Bad(U64)])
	gloc_count = |bytes| {
		if bytes.len() < 8 {
			return Err(Bad(0))
		}
		version = Bytes.u32(bytes, 0)
		flags = Bytes.u16(bytes, 4)
		if version != 0x00010000 and version != 0x00010001 {
			return Err(Bad(0))
		}
		width = if (flags.bitwise_and(1) == 0) 2 else 4
		labels = if (flags.bitwise_and(2) == 0) 0 else 2 * Bytes.u16(bytes, 6)
		if !Bytes.fits(8, labels + width, bytes.len()) {
			return Err(Bad(8))
		}
		array = bytes.len() - 8 - labels
		if array % width != 0 or array // width > 65537 {
			return Err(Bad(8))
		}
		Ok(array // width - 1)
	}

	available : TableGraphite -> Bool
	available = |table| table.glyph_count != 0 and !table.program.subtables.is_empty()
}

expect TableGraphite.gloc_count([0, 1, 0, 0, 0, 0, 0, 1, 0, 4, 0, 8, 0, 12, 0, 16]) == Ok(3)
expect TableGraphite.gloc_count([0, 1, 0, 0, 0, 0, 0, 1, 0, 4, 0, 8, 0, 12]) == Ok(2)
expect TableGraphite.gloc_count([0, 1, 0, 0, 0, 0, 0, 1, 0, 4, 0, 8, 0, 12, 0]).is_err()
expect {
	match TableGraphite.read({ silf: [], gloc: [], glat: [], feat: Present([]), sill: Absent, glyph_count: 0 }, 1024) {
		Err(problems) => problems.len() == 4 and problems.map(|p| p.table) == ["Feat", "Gloc", "Glat", "Silf"]
		Ok(_) => False
	}
}

# Original fixture tables, also accepted by Graphite2 1.3.14 and OTS9.3.
inline_silf = [0, 3, 0, 0, 0, 3, 0, 0, 0, 1, 0, 0, 0, 0, 0, 16, 0, 3, 0, 0, 0, 42, 0, 50, 0, 2, 0, 0, 0, 0, 1, 0, 1, 1, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 68, 0, 0, 0, 145, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 8, 0, 10, 0, 2, 0, 10, 1, 0, 0, 1, 0, 24, 0, 0, 0, 141, 0, 0, 0, 141, 0, 0, 0, 141, 0, 0, 0, 0, 0, 2, 0, 1, 0, 1, 0, 1, 0, 1, 0, 6, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 1, 0, 28, 0, 25, 49]

inline_gloc = [0, 1, 0, 0, 0, 0, 0, 1, 0, 4, 0, 8, 0, 12, 0, 16]

inline_glat = [0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0]

inline_feat = [0, 2, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 100, 0, 2, 0, 0, 0, 0, 0, 28, 128, 0, 1, 0, 0, 0, 1, 1, 0, 1, 1, 2]
expect {
	match TableGraphite.read({ silf: inline_silf, gloc: inline_gloc, glat: inline_glat, feat: Present(inline_feat), sill: Absent, glyph_count: 3 }, 4096) {
		Ok(table) => TableGraphite.available(table) and table.glyph_count == 3 and table.program.passes.len() == 1 and table.program.instructions.len() == 3 and GraphiteFeatures.defaults(table.features, 0) == [0]
		Err(_) => False
	}
}

expect {
	# Collision flags require Glat3. This cross-table dependency is read
	# eagerly; older glyph-attribute tables remain valid for ordinary passes.
	match TableGraphite.read({ silf: inline_collision_silf, gloc: inline_gloc, glat: inline_glat, feat: Present(inline_feat), sill: Absent, glyph_count: 3 }, 4096) {
		Err(problems) => problems == [{ table: "Glat", offset: 0, reason: Malformed }]
		Ok(_) => False
	}
}

expect {
	match TableGraphite.read({ silf: [], gloc: [], glat: [], feat: Present([]), sill: Present([]), glyph_count: 0 }, 1024) {
		Err(problems) => problems.map(|p| p.table) == ["Feat", "Sill", "Gloc", "Glat", "Silf"]
		Ok(_) => False
	}
}

# Original proper Silf5 collision-pass header; long class offsets.
inline_collision_silf = [0.U8, 5, 0, 0, 0, 3, 0, 0, 0, 1, 0, 0, 0, 0, 0, 16, 0, 3, 0, 0, 0, 42, 0, 50, 0, 2, 0, 0, 0, 0, 1, 0, 1, 1, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 72, 0, 0, 0, 161, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 12, 0, 0, 0, 14, 0, 2, 1, 10, 2, 0, 0, 1, 0, 24, 0, 0, 0, 157, 0, 0, 0, 157, 0, 0, 0, 157, 0, 0, 0, 0, 0, 3, 0, 2, 0, 1, 0, 2, 0, 2, 0, 12, 0, 1, 0, 0, 0, 1, 0, 1, 0, 0, 0, 2, 0, 2, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 1, 0, 0, 0, 0, 0, 2, 0, 28, 0, 25, 49]

expect TableGraphite.gloc_count([0.U8, 1, 0, 0, 128, 0, 0, 1, 0, 4, 0, 8, 0, 12, 0, 16]) == Ok(3)
