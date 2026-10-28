app [target] {
	build: "../tests/support/main.roc",
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}
import font.Font
import build.FontBuild
import fuzz.Fuzz
import "../tests/fonts/color-images/images.ttf" as synthetic : List(U8)
import "../tests/fonts/color-images/emoji-subset.ttf" as real : List(U8)

## Independent SVG/sbix/CBDT scaling at8and64glyphs: every offset is
## checked before sizing allocations; all5CBLCindexformats are generated.
## sbix aliases form a long forward chain, then resolve to one image.
## Encoded image data is opaque, so arbitrary payloads need no decoder.
## Corrupted original/realfont seeds exercise optional - table dropping,
## total queries, exact payload preservation, deterministic facts/leaks.
recipe : U64, U64, U64, List(U8) -> { file : List(U8), payload : List(U8) }
recipe = |n, mode, choice, bytes| {
	payload = [0x89, 80, 78, 71, 13, 10, 26, 10].concat(bytes.take_first(16))
	var $extra = []
	if mode == 0 {
		doc = "<svg xmlns=\"http://www.w3.org/2000/svg\"/>".to_utf8()
		records = FontBuild.counting(n - 1).join_map(|i| [U16(i + 1), U16(i + 1), Ref32(doc), U32(doc.len())])
		table = FontBuild.pack([U16(0), Ref32(FontBuild.pack([U16(n - 1)].concat(records))), U32(0)])
		$extra = [{ tag: "SVG ", data: table }]
	} else if mode == 1 {
		image = FontBuild.pack([I16(3), I16(-4), Tag("png "), Raw(payload)])
		# Glyph1ends the chain. Glyph2..n - 1refer to the next glyph, and the
		# last points at1, so resolving the first alias walks the entire chain.
		records = FontBuild.counting(n).map(
			|g| if g == 0 {
				[]
			} else if g == 1 {
				image
			} else {
				FontBuild.pack([
					I16(99),
					I16(99),
					Tag("dupe"),
					U16(
						if g + 1 == n {
							1
						} else {
							g + 1
						},
					),
				])
			},
		)
		length = 4 + 4 * (n + 1) + records.fold(0, |sum, record| sum + record.len())
		strike = FontBuild.pack([U16(16), U16(72)].concat(records.map(|record| Ref32(record))).append(U32(length)))
		$extra = [{ tag: "sbix", data: FontBuild.pack([U16(1), U16(1), U32(1), Ref32(strike)]) }]
	} else {
		index_format = 1 + choice % 5
		image_format = if index_format == 2 or index_format == 5 {
			19
		} else if choice % 2 == 0 {
			17
		} else {
			18
		}
		small = [1, 1, 0xFE, 4, 7]
		big = [1, 1, 0xFE, 4, 7, 0xFD, 5, 8]
		record = (
			if image_format == 17 {
				small
			} else if image_format == 18 {
				big
			} else {
				[]
			}
		).concat(FontBuild.u32(payload.len())).concat(payload)
		images = List.repeat(record, n - 1).join_map(|image| image)
		header = FontBuild.u16(index_format).concat(FontBuild.u16(image_format)).concat(FontBuild.u32(4))
		body = if index_format == 1 or index_format == 3 {
			FontBuild.counting(n).join_map(
				|i| if index_format == 1 {
					FontBuild.u32(i * record.len())
				} else {
					FontBuild.u16(i * record.len())
				},
			)
		} else if index_format == 2 {
			FontBuild.u32(record.len()).concat(big)
		} else if index_format == 4 {
			FontBuild.u32(n - 1).concat(
				FontBuild.counting(n).join_map(
					|i| FontBuild.u16(
						if i + 1 == n {
							0
						} else {
							i + 1
						},
					).concat(FontBuild.u16(i * record.len())),
				),
			)
		} else {
			FontBuild.u32(record.len()).concat(big).concat(FontBuild.u32(n - 1)).concat(FontBuild.counting(n - 1).join_map(|i| FontBuild.u16(i + 1)))
		}
		sub = header.concat(body)
		array = FontBuild.u16(1).concat(FontBuild.u16(n - 1)).concat(FontBuild.u32(8)).concat(sub)
		padded = array.concat(List.repeat(0, (4 - array.len() % 4) % 4))
		size = FontBuild.pack([U32(56), U32(padded.len()), U32(1), U32(0), Raw(List.repeat(0, 24)), U16(1), U16(n - 1), Raw([16, 16, 32, 1])])
		$extra = [{ tag: "CBLC", data: FontBuild.u32(0x30000).concat(FontBuild.u32(1)).concat(size).concat(padded) }, { tag: "CBDT", data: FontBuild.u32(0x30000).concat(images) }]
	}
	base = [{ tag: "head", data: FontBuild.head(1000, False) }, { tag: "hhea", data: FontBuild.hhea(800, -200, n) }, { tag: "maxp", data: FontBuild.maxp(n) }, { tag: "hmtx", data: FontBuild.hmtx(List.repeat(600, n)) }, { tag: "cmap", data: FontBuild.cmap([{ system: 3, encoding: 1, subtable: FontBuild.cmap4([{ first: 65, last: 65, delta: 65472, glyphs: [] }]) }]) }]
	{ file: FontBuild.file(base.concat($extra)), payload }
}

checksum : Font -> U64
checksum = |font| {
	var $sum = 0
	for g in 0..<Font.glyph_count(font) {
		match Font.svg_glyph(font, g) {
			Present(doc) => {
				$sum = $sum + doc.bytes.len()
			}
			Absent => {}
		}
		for s in 0..<Font.bitmap_strikes(font).len() {
			match Font.bitmap_glyph(font, g, s.to_u32_wrap()) {
				Present(image) => {
					$sum = $sum + image.bytes.len()
				}
				Absent => {}
			}
		}
	}
	$sum
}

test! = |bytes| {
	choice = (bytes.first() ?? 0).to_u64()
	for mode in [0.U64, 1, 2] {
		var $small_read = 0.U64
		var $small_query = 0.U64
		for n in [8.U64, 64] {
			built = recipe(n, mode, choice, bytes)
			measured = Fuzz.measure_allocs!(|{}| Font.from_bytes(built.file, Font.ReadOptions.{ strict: True }))
			font = match measured.value {
				Ok(f) => f
				Err(problems) => crash Str.inspect(problems)
			}
			for glyph in 1..<n {
				if mode == 0 {
					match Font.svg_glyph(font, glyph.to_u32_wrap()) {
						Present(doc) => {
							if doc.first_glyph.to_u64() != glyph or doc.last_glyph.to_u64() != glyph {
								crash "SVG glyph range"
							}
						}
						Absent => crash "missing SVG"
					}
				} else {
					match Font.bitmap_glyph(font, glyph.to_u32_wrap(), 0) {
						Present(image) => {
							if image.bytes != built.payload {
								crash "payload repaired"
							}
						}
						Absent => crash "missing image"
					}
				}
			}
			query = Fuzz.measure_allocs!(|{}| checksum(font))
			Fuzz.expect_no_leaks!(|{}| checksum(font))
			if n == 8 {
				$small_read = measured.allocations
				$small_query = query.allocations
			} else if measured.allocations > 10 * $small_read + 128 or query.allocations > 10 * $small_query + 128 {
				crash "color feature allocation scaling"
			}
		}
	}
	source = if choice % 2 == 0 {
		synthetic
	} else {
		real
	}
	# Modulo proves the mutation index exists. Failure fallback retains no
	# oldlist reference, preserving ownership and avoiding any hidden repair.
	mutated = if bytes.len() >= 4 {
		source.set(((bytes.get(1) ?? 0).to_u64() * 256 + (bytes.get(2) ?? 0).to_u64()) % source.len(), bytes.get(3) ?? 0) ?? []
	} else {
		source
	}
	match Font.from_bytes(mutated, Font.ReadOptions.{}) {
		Err(problems) => match Font.from_bytes(mutated, Font.ReadOptions.{}) {
			Err(again) => {
				if problems != again {
					crash "read nondeterministic"
				}
			}
			Ok(_) => crash "read changed"
		}
		Ok(font) => {
			glyph = (bytes.get(4) ?? 1).to_u32()
			strike = (bytes.get(5) ?? 0).to_u32()
			if Font.svg_glyph(font, glyph) != Font.svg_glyph(font, glyph) or Font.bitmap_glyph(font, glyph, strike) != Font.bitmap_glyph(font, glyph, strike) {
				crash "image facts nondeterministic"
			}
			Fuzz.expect_no_leaks!(|{}| checksum(font))
		}
	}
	Fuzz.keep
}

target = Fuzz.target_with!({ name: "font-color-images", generator: Fuzz.raw_bytes, test!, show: |bytes| Str.inspect(bytes.take_first(16)) })
