app [target] {
	build: "../tests/support/main.roc",
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}
import fuzz.Fuzz
import font.Font
import build.FontBuild
import "../tests/fonts/vertical/variable.ttf" as variable : List(U8)
import "../tests/fonts/vertical/cff2-vvar.otf" as cff : List(U8)

## Vertical metric arrays at16times the glyph count, then targeted corruptions
## of vhea/vmtx/VORG/VVAR. A successfully read font has total stable queries.
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	choice = bytes.first() ?? 0
	small = recipe(8, choice)
	large = recipe(128, choice)
	a = Fuzz.measure_allocs!(|{}| Font.from_bytes(small, Font.ReadOptions.{}))
	b = Fuzz.measure_allocs!(|{}| Font.from_bytes(large, Font.ReadOptions.{}))
	if b.allocations > 20 * a.allocations + 256 {
		crash "vertical metric read allocations grew faster than glyph count"
	}
	f = Font.from_bytes(small, Font.ReadOptions.{}) ?? crash "valid small metric recipe"
	g = Font.from_bytes(large, Font.ReadOptions.{}) ?? crash "valid large metric recipe"
	for id in 0..<8.U32 {
		if Font.vertical_advance(f, id) != Font.vertical_advance(g, id) or Font.vertical_origin(f, id) != Font.vertical_origin(g, id) {
			crash "unused vertical metrics changed a glyph"
		}
	}
	file = if (choice.bitwise_and(1) == 0) variable else cff
	tags = [0x76686561, 0x766D7478, 0x564F5247, 0x56564152]
	wanted = tags.get((choice.to_u64() // 2) % 4) ?? 0
	var $changed = file
	for i in 0..<u16(file, 4) {
		at = 12 + 16 * i
		if u32(file, at) == wanted {
			start = u32(file, at + 8)
			length = u32(file, at + 12)
			for j in 0..<bytes.len().min(8) {
				changed_at = start + ((bytes.get(j) ?? 0).to_u64() + 17 * j) % length
				$changed = $changed.set(changed_at, ($changed.get(changed_at) ?? 0).bitwise_xor(bytes.get(j) ?? 0)) ?? []
			}
		}
	}
	check($changed, choice.bitwise_and(32) != 0)
	Fuzz.expect_no_leaks!(|{}| Font.from_bytes($changed, Font.ReadOptions.{}))
	Fuzz.keep
}

recipe : U64, U8 -> List(U8)
recipe = |count, choice| {
	long = if (choice.bitwise_and(64) == 0) 2 else count
	metrics = FontBuild.counting(count).join_map(
		|i| {
			bearing = FontBuild.i16(i.to_i64_wrap() % 7 - 3)
			if (i < long) FontBuild.u16(1000 + i).concat(bearing) else bearing
		},
	)
	cmap = FontBuild.cmap([{ system: 3, encoding: 1, subtable: FontBuild.cmap4([{ first: 0xE000, last: 0xE000 + count - 1, delta: 65536 - 0xE000, glyphs: [] }]) }])
	FontBuild.glyphs_font(List.repeat(600, count), cmap, [{ tag: "vhea", data: FontBuild.hhea(500, -500, long) }, { tag: "vmtx", data: metrics }])
}

check : List(U8), Bool -> {}
check = |bytes, strict| {
	match (Font.from_bytes(bytes, Font.ReadOptions.{ strict }), Font.from_bytes(bytes, Font.ReadOptions.{ strict })) {
		(Ok(a), Ok(b)) => {
			varied_a = Font.at(a, Font.Variation.{ axes: [{ tag: "wght", value: 900 }] })
			varied_b = Font.at(b, Font.Variation.{ axes: [{ tag: "wght", value: 900 }] })
			for id in [0, 1, 2, 999].map(|n| n.to_u32()) {
				if Font.vertical_advance(varied_a, id) != Font.vertical_advance(varied_b, id) or Font.vertical_origin(varied_a, id) != Font.vertical_origin(varied_b, id) {
					crash "vertical queries are not deterministic"
				}
			}
			run = Font.shape(varied_a, "ab", Font.ShapeOptions.{ direction: BottomToTop })
			if run.glyphs.len() != run.advances.len() or run.glyphs.len() != run.offsets.len() or run.glyphs.len() != run.clusters.len() {
				crash "vertical output lost alignment"
			}
		}
		(Err(a), Err(b)) => if a != b {
			crash "vertical reader problems are not deterministic"
		}
		_ => crash "vertical reader outcome is not deterministic"
	}
}

u16 : List(U8), U64 -> U64
u16 = |bytes, at| (bytes.get(at) ?? 0).to_u64() * 256 + (bytes.get(at + 1) ?? 0).to_u64()

u32 : List(U8), U64 -> U64
u32 = |bytes, at| u16(bytes, at) * 65536 + u16(bytes, at + 2)

target = Fuzz.target_with!({ name: "font-vertical-tables", generator: Fuzz.raw_bytes, test!, show: |bytes| Str.inspect(bytes.take_first(8)) })
