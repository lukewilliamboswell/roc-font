import font.Font
import "../fonts/aat-mort/direct-logical.ttf" as direct_file : List(U8)
import "../fonts/aat-mort/rearrange-logical.ttf" as rearrange_file : List(U8)
import "../fonts/aat-mort/context-logical.ttf" as context_file : List(U8)
import "../fonts/aat-mort/ligature-logical.ttf" as ligature_file : List(U8)
import "../fonts/aat-mort/insertion-logical.ttf" as insertion_file : List(U8)
import "../fonts/aat-mort/context-zero.ttf" as zero_file : List(U8)
import "../fonts/aat-mort/context-minus-one.ttf" as signed_file : List(U8)
import "../fonts/aat-mort/ligature-multistore.ttf" as multistore_file : List(U8)
import "../fonts/aat-mort/priority-morx.ttf" as priority_file : List(U8)
import "../fonts/aat-mort/priority-empty-morx.ttf" as empty_priority_file : List(U8)
import "../fonts/aat-mort/broken-mort-with-morx.ttf" as broken_mort_file : List(U8)
import "../fonts/aat-mort/broken-morx-with-mort.ttf" as broken_morx_file : List(U8)
import "../fonts/aat-mort/bad-mort-and-morx.ttf" as both_bad_file : List(U8)
import "../fonts/aat-mort/bad-chain.ttf" as bad_chain_file : List(U8)

## Original legacy Apple programs act through the ordinary public shaper.
MortTests :: {}.{}

read = |bytes| match Font.from_bytes(bytes, Font.ReadOptions.{}) {
	Ok(font) => font
	Err(problems) => crash Str.inspect(problems)
}

shape = |bytes, text| Font.shape(read(bytes), text, Font.ShapeOptions.{ script: "Latn" })
expect shape(direct_file, "abc").glyphs == [5, 6, 0]
expect shape(rearrange_file, "ab").glyphs == [2, 1]
expect shape(context_file, "ab").glyphs == [5, 6]
expect shape(ligature_file, "ab").glyphs == [5]
expect shape(insertion_file, "a").glyphs == [5, 1]
expect shape(zero_file, "ab").glyphs == [1, 2]
expect shape(signed_file, "ab").glyphs == [5, 6]
expect shape(multistore_file, "ab").glyphs == [6]
expect shape(priority_file, "ab").glyphs == [6, 5]
expect shape(empty_priority_file, "ab").glyphs == [1, 2]
expect shape(broken_mort_file, "ab").glyphs == [6, 5] and shape(broken_morx_file, "ab").glyphs == [5, 6]
expect {
	font = read(bad_chain_file)
	reported = Font.dropped(font).any(
		|problem| match problem {
			BadTable({ table, .. }) => table == "mort"
			_ => False
		},
	)
	reported and Font.shape(font, "ab", Font.ShapeOptions.{ script: "Latn" }).glyphs == [1, 2] and match Font.from_bytes(bad_chain_file, Font.ReadOptions.{ strict: True }) {
		Err(_) => True
		Ok(_) => False
	}
}
expect {
	match Font.from_bytes(both_bad_file, Font.ReadOptions.{ strict: True }) {
		Err(problems) => ["mort", "morx"].all(
			|tag| problems.any(
				|problem| match problem {
					BadTable({ table, .. }) => table == tag
					_ => False
				},
			),
		)
		Ok(_) => False
	}
}
expect [direct_file, rearrange_file, context_file, ligature_file, insertion_file, signed_file, multistore_file].all(
	|bytes| {
		run = shape(bytes, "aab áb")
		run == shape(bytes, "aab áb") and run.glyphs.len() == run.advances.len() and run.glyphs.len() == run.offsets.len() and run.glyphs.len() == run.clusters.len() and run.glyphs.len() == run.flags.len() and run.glyphs.all(|glyph| glyph < Font.glyph_count(read(bytes)))
	},
)
