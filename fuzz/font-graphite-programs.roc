app [target] {
	font: "../package/main.roc",
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
}
import font.Font
import fuzz.Fuzz
import "../tests/fonts/graphite/delete-clone-left.ttf" as associations : List(U8)
import "../tests/fonts/graphite/slot-direction.ttf" as direction : List(U8)
import "../tests/fonts/graphite/stack-1024.ttf" as stack : List(U8)
import "../tests/fonts/graphite/Charis5_eursub.ttf" as real : List(U8)
import "../tests/fonts/graphite/pass-conditions/feature.ttf" as conditional : List(U8)
import "../tests/fonts/graphite/pass-conditions/zero-feature.ttf" as zero_conditional : List(U8)

## Change checked Silf programs and execute every accepted result. Reader
## rejection is expected; accepted text-dependent aborts have empty output.
test! = |input| {
	files = [associations, direction, stack, real]
	choice = input.first() ?? 0
	file = if choice.bitwise_and(128) != 0 {
		if (choice.bitwise_and(32) != 0) zero_conditional else conditional
	} else files.get(choice.to_u64() % files.len()) ?? associations
	original_false = choice.bitwise_and(128) != 0 and choice.bitwise_and(64) == 0 and input.drop_first(1).all(|b| b == 0)
	var $changed = file
	for i in 0..<u16(file, 4) {
		at = 12 + 16 * i
		if u32(file, at) == 0x53696C66 {
			start = u32(file, at + 8)
			length = u32(file, at + 12)
			if length != 0 {
				for j in 1..<input.len().min(17) {
					# Bias toward the tail containing rule bytecode, while
					# retaining header/class/FSM mutations in the other half.
					value = (input.get(j) ?? 0).to_u64()
					within = if (choice.bitwise_and(4) == 0) length - 1 - (value + 17 * j) % length else (257 * value + j) % length
					pos = start + within
					$changed = $changed.set(pos, ($changed.get(pos) ?? 0).bitwise_xor(input.get(j) ?? 0)) ?? []
				}
			}
		}
	}
	match Font.from_bytes($changed, Font.ReadOptions.{ strict: True }) {
		Err(_) => {
			if original_false {
				crash "valid conditional pass fixture rejected"
			}
		}
		Ok(font) => {
			plan = Font.plan(font, Font.ShapeOptions.{ script: if (choice.bitwise_and(8) == 0) "Latn" else "Arab", limits: Font.ShapeLimits.{ growth: 1, operations: 1 }, graphite_features: if (choice.bitwise_and(128) != 0) [Font.GraphiteFeature.{ id: 100, value: if (choice.bitwise_and(64) == 0) 0 else 1 }] else [] })
			if Font.shaping_engine(plan) != Graphite {
				if original_false {
					crash "conditional pass fixture selected another engine"
				}
				return Fuzz.keep
			}
			if original_false {
				var $previous = 0
				for copies in [1.U64, 4, 16] {
					text = Str.join_with(List.repeat("ab", copies), "")
					measured = Fuzz.measure_allocs!(|{}| Font.shape_planned(font, plan, text))
					if measured.value.glyphs.len() != 2 * copies or ($previous != 0 and measured.allocations > 4 * $previous + 128) {
						crash "disabled pass changed slots or allocation scaling"
					}
					$previous = measured.allocations
				}
			}
			for text in ["", "a", "ab", "aba", "abababababababab"] {
				result = Font.shape_checked(font, plan, text)
				if result != Font.shape_checked(font, plan, text) {
					crash "accepted Graphite program is not deterministic"
				}
				run = match result {
					Ok(value) => value
					Err(OverBudget(partial)) => partial.run
					Err(ProgramAborted(aborted)) => {
						if !aborted.run.glyphs.is_empty() {
							crash "program abort retained output"
						}
						aborted.run
					}
				}
				if original_false and run.offsets.any(|offset| offset.x != 0 or offset.y != 0) {
					crash "a false pass condition still applied collision positioning"
				}
				n = run.glyphs.len()
				if n > 65536 or n != run.advances.len() or n != run.offsets.len() or n != run.clusters.len() or n != run.flags.len() {
					crash "font program exceeded its growth/alignment contract"
				}
				for cluster in run.clusters {
					if cluster >= text.to_utf8().len() {
						crash "association outside text"
					}
				}
			}
			Fuzz.expect_no_leaks!(|{}| Font.shape_checked(font, plan, "abababab"))
		}
	}
	Fuzz.keep
}

u16 : List(U8), U64 -> U64
u16 = |bytes, at| (bytes.get(at) ?? 0).to_u64() * 256 + (bytes.get(at + 1) ?? 0).to_u64()

u32 : List(U8), U64 -> U64
u32 = |bytes, at| u16(bytes, at) * 65536 + u16(bytes, at + 2)

target = Fuzz.target_with!({ name: "font-graphite-programs", generator: Fuzz.raw_bytes, test!, show: |bytes| Str.inspect(bytes.take_first(17)) })
