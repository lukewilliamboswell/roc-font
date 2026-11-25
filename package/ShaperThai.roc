import ShaperNormalize
import ShaperUnicode

## Thai SARA AM preprocessing for an already selected horizontal run.
## The pinned reference is HarfBuzz 14.6.0's `preprocess_text_thai`.
ShaperThai :: {}.{
	sara_am : U64
	sara_am = 0x0E33

	sara_aa : U64
	sara_aa = 0x0E32

	nikhahit : U64
	nikhahit = 0x0E4D

	## SARA AM alone introduces a movable NIKHAHIT. Authored marks keep
	## their order. Preallocate the exact output so the move and the
	## cluster merges can work in place, including at a repeated offset
	## that extends into the unread input.
	preprocess : List(ShaperNormalize.Char), Bool -> List(ShaperNormalize.Char)
	preprocess = |chars, characters| {
		var $added = 0
		for c in chars {
			if c.cp == ShaperThai.sara_am {
				$added = $added + 1
			}
		}
		if $added == 0 {
			return chars
		}

		props = ShaperUnicode.props(ShaperThai.nikhahit).bitwise_or(ShaperUnicode.continuation)
		var $out = List.with_capacity(chars.len() + $added)
		for c in chars {
			if c.cp == ShaperThai.sara_am {
				$out = $out.append({ ..c, cp: ShaperThai.nikhahit, props })
			}
			# Keep the source SARA AM here until its new NIKHAHIT moves.
			$out = $out.append(c)
		}
		for i in 1..<$out.len() {
			c = $out.get(i) ?? ShaperNormalize.no_char
			if c.cp == ShaperThai.sara_am {
				# Both this slot and the inserted one before it exist.
				$out = $out.set(i, { ..c, cp: ShaperThai.sara_aa, props: ShaperUnicode.props(ShaperThai.sara_aa) }) ?? []
				mark = i - 1
				var $start = mark
				while $start > 0 and ShaperThai.above_base(($out.get($start - 1) ?? ShaperNormalize.no_char).cp) {
					$start = $start - 1
				}
				# Moving the mark merges the moved span. At grapheme level,
				# the split also joins the cluster immediately before it.
				merge_start = if (!characters and $start > 0) $start - 1 else $start
				$out = ShaperNormalize.merge_clusters($out, merge_start, i + 1)
				if $start < mark {
					moved = $out.get(mark) ?? ShaperNormalize.no_char
					var $at = mark
					while $at > $start {
						# `start <= at - 1 < at < i`, all inside the output.
						$out = $out.set($at, $out.get($at - 1) ?? ShaperNormalize.no_char) ?? []
						$at = $at - 1
					}
					$out = $out.set($start, moved) ?? []
				}
			}
		}
		$out
	}

	## The Thai above-base marks that a split NIKHAHIT crosses in the
	## pinned shaper. Below-base marks, bases and spacing vowels stop it.
	above_base : U64 -> Bool
	above_base = |cp|
		cp == 0x0E31 or cp == 0x0E3B or (cp >= 0x0E34 and cp <= 0x0E37) or (cp >= 0x0E47 and cp <= 0x0E4E)
}
