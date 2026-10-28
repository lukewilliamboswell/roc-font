app [target] {
	build: "../tests/support/main.roc",
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}
import font.Font
import fuzz.Fuzz
import build.FontBuild
import "../tests/fonts/cff/sans-cff2.otf" as sans : List(U8)
import "../tests/fonts/cff/serif-cff2.otf" as serif : List(U8)

## Narrow CFF2 target:16/64/256 nested blend pairs, a constant region
## contributing at the default location, a varying region, two font
## dictionaries and FDSelect4. No TrueType/gvar/hinting/rasterization.
generated = |n, delta| {
	store = FontBuild.variation_store(1, [[{ start: 0, peak: 16384, end: 16384 }], [{ start: 0, peak: 0, end: 0 }]], [{ regions: [0, 1], rows: [] }])
	var $program = [139, 139, 21]
	for _ in 0..<n {
		# Each blend adds delta*s +2. Two nested blends give dx5+2delta*s.
		$program = $program.concat([140, delta, 141, 140, 16, delta, 141, 140, 16, 140, 5])
	}
	store_at = 35
	fd_at = store_at + 2 + store.len()
	select_at = fd_at + 14
	cs_at = select_at + 21
	top = [29].concat(FontBuild.u32(cs_at)).concat([17, 29]).concat(FontBuild.u32(fd_at)).concat([12, 36, 29]).concat(FontBuild.u32(store_at)).concat([24, 29]).concat(FontBuild.u32(select_at)).concat([12, 37])
	fd_array = [0, 0, 0, 2, 1, 1, 4, 7, 139, 139, 18, 139, 139, 18]
	fd_select = [4].concat(FontBuild.u32(2)).concat(FontBuild.u32(0)).concat(FontBuild.u16(0)).concat(FontBuild.u32(2)).concat(FontBuild.u16(1)).concat(FontBuild.u32(4))
	cs = FontBuild.u32(4).concat([4]).concat(FontBuild.u32(1)).concat(FontBuild.u32(1)).concat(FontBuild.u32(1 + $program.len())).concat(FontBuild.u32(1 + $program.len())).concat(FontBuild.u32(1 + $program.len())).concat($program)
	cff = [2, 0, 5, 0, 26].concat(top).concat([0, 0, 0, 0]).concat(FontBuild.u16(store.len())).concat(store).concat(fd_array).concat(fd_select).concat(cs)
	fvar = FontBuild.fvar([{ tag: "wght", min: 0, default: 0, max: 1000 }])
	file = FontBuild.file(FontBuild.replace(FontBuild.replace(FontBuild.basic, "CFF2", cff), "fvar", fvar))
	"OTTO".to_utf8().concat(file.drop_first(4))
}

query = |font| {
	path = Font.outline(font, 1)
	{ path, box: Font.extents(font, 1) }
}

test! = |bytes| {
	delta = (bytes.first() ?? 0) % 201 + 39
	signed_delta = delta.to_i64() - 139
	var $read_allocations = 0.U64
	var $query_allocations = 0.U64
	for n in [16.U64, 64, 256] {
		file = generated(n, delta)
		font = match Font.from_bytes(file, Font.ReadOptions.{ strict: True }) {
			Ok(ready) => ready
			Err(problems) => crash Str.inspect(problems)
		}
		read_cost = Fuzz.measure_allocs!(|{}| Font.from_bytes(file, Font.ReadOptions.{}))
		query_cost = Fuzz.measure_allocs!(|{}| query(font))
		if n > 16 and (read_cost.allocations > 5 * $read_allocations + 64 or query_cost.allocations > 5 * $query_allocations + 64) {
			crash "CFF2 blend allocation scaling"
		}
		$read_allocations = read_cost.allocations
		$query_allocations = query_cost.allocations
		for weight in [0.U16, 500, 1000] {
			moved = Font.at(font, Font.Variation.{ weight: Weight(weight) })
			x = n.to_i64_wrap() * (5 + signed_delta * weight.to_i64() / 500)
			match Font.outline(moved, 1) {
				Outline(path) => {
					if path.len() != n + 2 or (path.get(n) ?? Close) != LineTo({ x: x.to_f64(), y: n.to_f64() }) {
						crash "CFF2 nested blends/default constant region/FDSelect4 changed"
					}
				}
				Unknown => crash "generated CFF2 unavailable"
			}
			if query(moved) != query(moved) {
				crash "CFF2 nondeterministic"
			}
			Fuzz.expect_no_leaks!(|{}| query(moved))
		}
		Fuzz.expect_no_leaks!(|{}| Font.from_bytes(file, Font.ReadOptions.{}))
	}
	seed = if ((bytes.first() ?? 0) % 2 == 0) sans else serif
	file = FontBuild.mutate(seed, bytes.drop_first(1))
	match Font.from_bytes(file, Font.ReadOptions.{}) {
		Err(_) => {}
		Ok(font) => {
			for weight in [1.U16, 400, 777, 1000] {
				moved = Font.at(font, Font.Variation.{ weight: Weight(weight) })
				if query(moved) != query(moved) {
					crash "real CFF2 location nondeterministic"
				}
			}
		}
	}
	Fuzz.keep
}

target = Fuzz.target_with!({ name: "font-cff2", generator: Fuzz.raw_bytes, test!, show: |bytes| Str.inspect(bytes.take_first(16)) })
