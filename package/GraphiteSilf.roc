import Bytes
import GraphiteCompression
import GraphiteClasses
import GraphitePass
import GraphiteCode

## Checked rendering descriptions, finite-state passes and decoded font
## bytecode. Every prepared pool is flat and every hot record is scalar.
GraphiteSilf := {
	data : List(U8),
	subtables : List(Subtable),
	passes : List(GraphitePass.Pass),
	classes : List(GraphiteClasses.Class),
	pseudo_chars : List(U32),
	pseudo_glyphs : List(U16),
	constraint_endings : List(U64),
	programs : List(Program),
	instructions : List(GraphiteCode.Instruction),
}.{

	Subtable : {
		pass_start : U64,
		pass_end : U64,
		class_start : U64,
		class_end : U64,
		pseudo_start : U64,
		pseudo_end : U64,
		substitution : U64,
		positioning : U64,
		justification : U64,
		bidi : U64,
		flags : U64,
		direction : U64,
		pseudo_attribute : U64,
		break_attribute : U64,
		direction_attribute : U64,
		mirror_attribute : U64,
		skip_attribute : U64,
		collision_attribute : U64,
		user_count : U64,
		components : U64,
		line_break : U64,
		extra_ascent : I64,
		extra_descent : I64,
	}
	Program : { start : U64, end : U64, max_stack : U64 }

	none : GraphiteSilf
	none = { data: [], subtables: [], passes: [], classes: [], pseudo_chars: [], pseudo_glyphs: [], constraint_endings: [], programs: [], instructions: [] }

	read : List(U8), U64, U64, U64, U64 -> Try(GraphiteSilf, [Bad(U64), OverLimit(Str)])
	read = |raw, glyph_count, attribute_count, feature_count, max_bytes| {
		data = GraphiteCompression.expand(raw, 0x00050000, max_bytes)?
		if data.len() > max_bytes {
			return Err(OverLimit("graphite_uncompressed_bytes"))
		}
		if data.len() < 8 {
			return Err(Bad(0))
		}
		version = Bytes.u32(data, 0)
		if version < 0x00020000 or version > 0x00050001 {
			return Err(Bad(0))
		}
		header = if (version >= 0x00030000) 12 else 8
		if data.len() < header {
			return Err(Bad(0))
		}
		count = Bytes.u16(data, header - 4)
		if !Bytes.fits(header, count * 4, data.len()) {
			return Err(Bad(header - 4))
		}
		var $table = { ..GraphiteSilf.none, data }
		var $previous = header + count * 4
		for i in 0..<count {
			at = Bytes.u32(data, header + 4 * i)
			end = if (i + 1 < count) Bytes.u32(data, header + 4 * (i + 1)) else data.len()
			if at < $previous or end < at or end > data.len() {
				return Err(Bad(header + 4 * i))
			}
			$table = GraphiteSilf.read_subtable($table, at, end, version, glyph_count, attribute_count, feature_count)?
			$previous = end
		}
		Ok($table)
	}

	read_subtable : GraphiteSilf, U64, U64, U64, U64, U64, U64 -> Try(GraphiteSilf, [Bad(U64)])
	read_subtable = |table, start, end, version, glyph_count, attribute_count, feature_count| {
		{ data, subtables, passes: old_passes, classes: old_classes, pseudo_chars: old_chars, pseudo_glyphs: old_glyphs, constraint_endings: old_endings, programs: old_programs, instructions: old_instructions } = table
		prefix = if (version >= 0x00030000) 8 else 0
		base = start + prefix
		if !Bytes.fits(start, prefix + 20, end) {
			return Err(Bad(start))
		}
		if prefix != 0 {
			rule_version = Bytes.u32(data, start)
			if rule_version < 0x00020000 or rule_version > 0x00050001 {
				return Err(Bad(start))
			}
		}
		n = Bytes.u8(data, base + 6)
		substitution = Bytes.u8(data, base + 7)
		positioning = Bytes.u8(data, base + 8)
		justification = Bytes.u8(data, base + 9)
		bidi = Bytes.u8(data, base + 10)
		if substitution > positioning or positioning > justification or justification > n or (bidi != 255 and bidi > positioning) {
			return Err(Bad(base + 7))
		}
		levels = Bytes.u8(data, base + 19)
		meta = base + 20 + levels * 8
		if !Bytes.fits(meta, 10, end) {
			return Err(Bad(base + 19))
		}
		critical_count = Bytes.u8(data, meta + 9)
		scripts = meta + 10 + critical_count * 2
		if !Bytes.fits(scripts, 2, end) {
			return Err(Bad(meta + 9))
		}
		script_count = Bytes.u8(data, scripts + 1)
		line_break = scripts + 2 + script_count * 4
		pass_offsets = line_break + 2
		if !Bytes.fits(line_break, 2 + (n + 1) * 4 + 8, end) {
			return Err(Bad(line_break))
		}
		pseudos = pass_offsets + (n + 1) * 4
		pseudo_count = Bytes.u16(data, pseudos)
		pseudo_map = pseudos + 8
		if !Bytes.fits(pseudo_map, pseudo_count * 6, end) {
			return Err(Bad(pseudos))
		}
		var $previous = 0
		for i in 0..<pseudo_count {
			at = pseudo_map + i * 6
			cp = Bytes.u32(data, at)
			if cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF) or (i != 0 and cp <= $previous) or Bytes.u16(data, at + 4) >= glyph_count {
				return Err(Bad(at))
			}
			$previous = cp
		}
		class_map = pseudo_map + pseudo_count * 6
		first_pass = start + Bytes.u32(data, pass_offsets)
		if first_pass < class_map or first_pass > end {
			return Err(Bad(pass_offsets))
		}
		classes = GraphiteClasses.read(data, class_map, first_pass, version, glyph_count)?
		class_start = old_classes.len()
		var $classes = old_classes.concat(classes)
		var $passes = old_passes
		var $endings = old_endings
		var $programs = old_programs
		var $instructions = old_instructions
		pass_start = $passes.len()
		class_count = $classes.len() - class_start
		user_count = Bytes.u8(data, meta + 2)
		env = { classes: class_count, attributes: attribute_count, features: feature_count, users: user_count, constraint: False }
		for i in 0..<n {
			at = start + Bytes.u32(data, pass_offsets + 4 * i)
			limit = start + Bytes.u32(data, pass_offsets + 4 * (i + 1))
			if at < first_pass or limit < at or limit > end {
				return Err(Bad(pass_offsets + 4 * i))
			}
			prepared = GraphitePass.read(data, at, limit, start, version, if (glyph_count == 0) 0 else glyph_count - 1)?
			pass = { ..prepared.pass, constraint_ends: $endings.len(), programs: $programs.len() }
			$endings = $endings.concat(prepared.endings)
			decoded = GraphiteCode.read(data, pass.pass_constraint, pass.pass_constraint_end, { ..env, constraint: True })?
			$programs = $programs.append({ start: $instructions.len(), end: $instructions.len() + decoded.instructions.len(), max_stack: decoded.max_stack })
			$instructions = $instructions.concat(decoded.instructions)
			for rule in 0..<pass.rule_count {
				constraint = GraphitePass.code(data, $endings, pass, rule, True)
				condition = GraphiteCode.read(data, constraint.start, constraint.end, { ..env, constraint: True })?
				$programs = $programs.append({ start: $instructions.len(), end: $instructions.len() + condition.instructions.len(), max_stack: condition.max_stack })
				$instructions = $instructions.concat(condition.instructions)
				action = GraphitePass.code(data, $endings, pass, rule, False)
				body = GraphiteCode.read(data, action.start, action.end, env)?
				_ = GraphiteCode.check_references(data, body, Bytes.u8(data, pass.pre_contexts + rule), Bytes.u16(data, pass.sort_keys + 2 * rule))?
				$programs = $programs.append({ start: $instructions.len(), end: $instructions.len() + body.instructions.len(), max_stack: body.max_stack })
				$instructions = $instructions.concat(body.instructions)
			}
			$passes = $passes.append(pass)
		}
		var $pseudo_chars = old_chars
		var $pseudo_glyphs = old_glyphs
		pseudo_start = $pseudo_chars.len()
		for i in 0..<pseudo_count {
			$pseudo_chars = $pseudo_chars.append(Bytes.u32(data, pseudo_map + i * 6).to_u32_wrap())
			$pseudo_glyphs = $pseudo_glyphs.append(Bytes.u16(data, pseudo_map + i * 6 + 4).to_u16_wrap())
		}
		sub = { pass_start, pass_end: $passes.len(), class_start, class_end: $classes.len(), pseudo_start, pseudo_end: $pseudo_chars.len(), substitution, positioning, justification, bidi, flags: Bytes.u8(data, base + 11), direction: Bytes.u8(data, meta + 4), pseudo_attribute: Bytes.u8(data, base + 14), break_attribute: Bytes.u8(data, base + 15), direction_attribute: Bytes.u8(data, base + 16), mirror_attribute: Bytes.u8(data, base + 17), skip_attribute: Bytes.u8(data, base + 18), collision_attribute: Bytes.u8(data, meta + 5), user_count, components: Bytes.u8(data, meta + 3), line_break: Bytes.u16(data, line_break), extra_ascent: Bytes.i16(data, base + 2), extra_descent: Bytes.i16(data, base + 4) }
		Ok({ data, subtables: subtables.append(sub), passes: $passes, classes: $classes, pseudo_chars: $pseudo_chars, pseudo_glyphs: $pseudo_glyphs, constraint_endings: $endings, programs: $programs, instructions: $instructions })
	}

	pseudo : GraphiteSilf, Subtable, U32 -> [Found(U64), Missing]
	pseudo = |table, sub, cp| {
		var $lo = sub.pseudo_start
		var $hi = sub.pseudo_end
		while $lo < $hi {
			mid = $lo + ($hi - $lo) // 2
			candidate = table.pseudo_chars.get(mid) ?? 0
			if cp < candidate {
				$hi = mid
			} else if cp > candidate {
				$lo = mid + 1
			} else {
				return Found((table.pseudo_glyphs.get(mid) ?? 0).to_u64())
			}
		}
		Missing
	}
}

expect GraphiteSilf.read([], 1, 1, 1, 1024).is_err()
expect GraphiteSilf.read([0, 2, 0, 0, 0, 0, 0, 0], 1, 1, 1, 1024).is_ok()
