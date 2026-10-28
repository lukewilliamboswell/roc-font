app [target] {
	build: "../tests/support/main.roc",
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}
import font.Font
import fuzz.Fuzz
import build.FontBuild
import "../tests/fonts/cff/sans-cff1.otf" as sans : List(U8)
import "../tests/fonts/cff/cid-cff1.otf" as cid : List(U8)
import "../tests/fonts/cff/sans-cff2.otf" as variable_sans : List(U8)
import "../tests/fonts/cff/serif-cff2.otf" as variable_serif : List(U8)
import "../tests/fonts/cff/operators-cff1.otf" as operators : List(U8)
import "../tests/fonts/cff/calculator-cff1.otf" as calculator : List(U8)

## Narrow CFF execution sizes isolate16/64/256 line operators, proving
## finite deterministic output and approximately linear preparation/query
## allocations. Real CFF1/CID/CFF2/calculator seeds exercise the same public
## APIs under arbitrary byte corruption, locations and out-of-range glyphs.
finite_point = |point| point.x.is_finite() and point.y.is_finite() and point.x >= -1073741823 and point.x <= 1073741823 and point.y >= -1073741823 and point.y <= 1073741823

finite_command = |command| match command {
	MoveTo(point) | LineTo(point) => finite_point(point)
	QuadraticTo(curve) => finite_point(curve.control) and finite_point(curve.end)
	CubicTo(curve) => finite_point(curve.control1) and finite_point(curve.control2) and finite_point(curve.end)
	Close => True
}

container = |program| {
	# Four glyphs and a four-byte INDEX offset array. All operands and
	# offsets are original test bytes; no implementation helper is imported.
	prefix = [1, 0, 4, 4, 0, 1, 1, 1, 2, 65, 0, 1, 1, 1, 7, 29, 0, 0, 0, 25, 17, 0, 0, 0, 0]
	cs = [0, 4, 4].concat(FontBuild.u32(1)).concat(FontBuild.u32(2)).concat(FontBuild.u32(2 + program.len())).concat(FontBuild.u32(3 + program.len())).concat(FontBuild.u32(4 + program.len())).concat([14]).concat(program).concat([14, 14])
	file = FontBuild.file(FontBuild.replace(FontBuild.basic, "CFF ", prefix.concat(cs)))
	"OTTO".to_utf8().concat(file.drop_first(4))
}

generated = |n, bytes| {
	var $program = [139, 139, 21]
	for i in 0..<n {
		dy = (bytes.get(i % bytes.len().max(1)) ?? 0) % 201 + 39
		$program = $program.concat([140, dy, 5])
	}
	container($program.append(14))
}

query = |font, glyph| {
	outline = Font.outline(font, glyph)
	match outline {
		Outline(path) => if path.len() > 200000 or !path.all(finite_command) {
			crash "CFF path escaped eager numerical/output proof"
		}
		Unknown => {}
	}
	{ outline, extents: Font.extents(font, glyph) }
}

test! = |bytes| {
	var $read_allocs = 0.U64
	var $query_allocs = 0.U64
	for n in [16.U64, 64, 256] {
		file = generated(n, bytes)
		font = match Font.from_bytes(file, Font.ReadOptions.{ strict: True }) {
			Ok(ready) => ready
			Err(problems) => crash Str.inspect(problems)
		}
		match Font.outline(font, 1) {
			Outline(path) => if path.len() != n + 2 or !path.all(finite_command) {
				crash "generated CFF output alignment"
			}
			Unknown => crash "generated CFF outline missing"
		}
		read_cost = Fuzz.measure_allocs!(|{}| Font.from_bytes(file, Font.ReadOptions.{}))
		query_cost = Fuzz.measure_allocs!(|{}| query(font, 1))
		if n > 16 and (read_cost.allocations > 5 * $read_allocs + 64 or query_cost.allocations > 5 * $query_allocs + 64) {
			crash "CFF feature allocation scaling"
		}
		$read_allocs = read_cost.allocations
		$query_allocs = query_cost.allocations
		Fuzz.expect_no_leaks!(|{}| query(font, 1))
		Fuzz.expect_no_leaks!(|{}| Font.from_bytes(file, Font.ReadOptions.{}))
	}
	# The exact accepted coordinate envelope is checked without clipping.
	boundary = [(bytes.first() ?? 0) % 200 + 39, 12, 18].concat([28, 127, 255, 12, 27, 12, 24, 28, 127, 255, 141, 12, 24, 12, 10, 139, 21])
	match Font.from_bytes(container(boundary.append(14)), Font.ReadOptions.{}) {
		Ok(font) => if Font.outline(font, 1) != Outline([MoveTo({ x: 1073741823, y: 0 }), Close]) {
			crash "CFF coordinate boundary changed"
		}
		Err(problems) => crash Str.inspect(problems)
	}
	match Font.from_bytes(container(boundary.concat([140, 139, 5, 14])), Font.ReadOptions.{}) {
		Err(problems) => if !problems.any(
			|p| match p {
				OverLimit(_) => True
				_ => False
			},
		) {
			crash "CFF outside numerical envelope was not an explicit resource limit"
		}
		Ok(_) => crash "CFF outside numerical envelope accepted"
	}
	choice = (bytes.first() ?? 0).to_u64()
	seed = match choice % 6 {
		0 => sans
		1 => cid
		2 => variable_sans
		3 => variable_serif
		4 => operators
		_ => calculator
	}
	file = if bytes.take_first(4) == "OTTO".to_utf8() or bytes.take_first(4) == [0, 1, 0, 0] {
		bytes
	} else FontBuild.mutate(seed, bytes.drop_first(1))
	match Font.from_bytes(file, Font.ReadOptions.{}) {
		Err(problems) => match Font.from_bytes(file, Font.ReadOptions.{}) {
			Err(again) => if problems != again {
				crash "CFF read errors nondeterministic"
			}
			Ok(_) => crash "CFF read changed"
		}
		Ok(font) => {
			again = match Font.from_bytes(file, Font.ReadOptions.{}) {
				Ok(ready) => ready
				Err(_) => crash "CFF repeated read changed"
			}
			for weight in [1.U16, 400, 650, 1000] {
				moved = Font.at(font, Font.Variation.{ weight: Weight(weight), axes: [{ tag: "opsz", value: 8 + (bytes.get(2) ?? 0).to_dec() }] })
				repeated = Font.at(again, Font.Variation.{ weight: Weight(weight), axes: [{ tag: "opsz", value: 8 + (bytes.get(2) ?? 0).to_dec() }] })
				for glyph in [0.U32, (bytes.get(1) ?? 1).to_u32(), Font.glyph_count(font), 0xFFFFFFFF] {
					if query(moved, glyph) != query(repeated, glyph) {
						crash "CFF path/extents nondeterministic"
					}
				}
			}
		}
	}
	Fuzz.keep
}

target = Fuzz.target_with!({ name: "font-cff", generator: Fuzz.raw_bytes, test!, show: |bytes| Str.inspect(bytes.take_first(16)) })
