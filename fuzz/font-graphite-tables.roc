app [target] {
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}
import font.Font
import fuzz.Fuzz
import "../tests/fonts/graphite/overlap-64.ttf" as small : List(U8)
import "../tests/fonts/graphite/overlap-1024.ttf" as large : List(U8)
import "../tests/fonts/graphite/Charis5_eursub.ttf" as charis : List(U8)
import "../tests/fonts/graphite/Padauk.ttf" as padauk : List(U8)
import "../tests/fonts/graphite/Scheherazadegr.ttf" as scheherazade : List(U8)
import "../tests/fonts/graphite/AwamiNastaliq-Regular.ttf" as awami : List(U8)

# Shared setting references increase256-fold while source bytes increase8-fold.
# Preparation must retain one flat source pool rather than expand references.
test! = |input| {
	a = Fuzz.measure_allocs!(|{}| Font.from_bytes(small, Font.ReadOptions.{ strict: True }))
	b = Fuzz.measure_allocs!(|{}| Font.from_bytes(large, Font.ReadOptions.{ strict: True }))
	if b.allocations > a.allocations + 8 {
		crash "shared Graphite spans increased preparation allocation calls"
	}
	match (a.value, b.value) {
		(Ok(x), Ok(y)) => if Font.glyph_count(x) != Font.glyph_count(y) {
			crash "shared settings changed glyph count"
		}
		_ => crash "valid shared Graphite settings rejected"
	}
	choice = input.first() ?? 0
	files = [small, charis, padauk, scheherazade, awami]
	file = files.get(choice.to_u64() % files.len()) ?? small
	tags = [0x53696C66, 0x476C6F63, 0x476C6174, 0x46656174, 0x53696C6C]
	wanted = tags.get((choice.to_u64() // 5) % tags.len()) ?? 0
	var $changed = file
	for i in 0..<u16(file, 4) {
		at = 12 + 16 * i
		if u32(file, at) == wanted {
			start = u32(file, at + 8)
			length = u32(file, at + 12)
			if length != 0 {
				for j in 0..<input.len().min(64) {
					pos = start + ((input.get(j) ?? 0).to_u64() + 257 * j) % length
					# The original validated sfnt table span proves this index.
					$changed = $changed.set(pos, ($changed.get(pos) ?? 0).bitwise_xor(input.get(j) ?? 0)) ?? []
				}
			}
		}
	}
	if choice.bitwise_and(128) != 0 {
		$changed = $changed.take_first(input.len().min($changed.len()))
	}
	check($changed, choice.bitwise_and(64) != 0)
	Fuzz.expect_no_leaks!(|{}| Font.from_bytes($changed, Font.ReadOptions.{}))
	Fuzz.keep
}

check : List(U8), Bool -> {}
check = |bytes, strict| {
	match (Font.from_bytes(bytes, Font.ReadOptions.{ strict }), Font.from_bytes(bytes, Font.ReadOptions.{ strict })) {
		(Ok(a), Ok(b)) => {
			if Font.dropped(a) != Font.dropped(b) or Font.glyph_count(a) != Font.glyph_count(b) {
				crash "Graphite reader facts are not deterministic"
			}
			for id in [0, 1, 2, 0xFFFFFFFF].map(|x| x.to_u32()) {
				if Font.advance(a, id) != Font.advance(b, id) {
					crash "accepted Graphite font has unstable metrics"
				}
			}
		}
		(Err(a), Err(b)) => if a != b {
			crash "Graphite diagnostics are not deterministic"
		}
		_ => crash "Graphite read result is not deterministic"
	}
}

u16 : List(U8), U64 -> U64
u16 = |bytes, at| (bytes.get(at) ?? 0).to_u64() * 256 + (bytes.get(at + 1) ?? 0).to_u64()

u32 : List(U8), U64 -> U64
u32 = |bytes, at| u16(bytes, at) * 65536 + u16(bytes, at + 2)

target = Fuzz.target_with!({ name: "font-graphite-tables", generator: Fuzz.raw_bytes, test!, show: |bytes| Str.inspect(bytes.take_first(64)) })
