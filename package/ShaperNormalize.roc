import Face
import TableCmap
import ShaperUnicode

## The steps between text and glyphs that GSUB does not express, as
## HarfBuzz 14.6.0 takes them (`hb-ot-shape.cc`, `hb-ot-shape-normalize.cc`,
## `hb-ot-shaper-hebrew.cc`): Unicode properties and grapheme clusters,
## shaping a run in its script's own direction, mirroring characters in
## right-to-left text, and mapping characters to glyphs while composing or
## decomposing them by what the font's `cmap` maps, with variation
## sequences, space fallbacks and the no-break hyphen.
##
## Internal. Each step is a pure function over a flat list of `Char`; the
## list grows only by canonical decomposition (at most four characters for
## one) and never past `growth_limit` of `normalize`.
ShaperNormalize :: {}.{

	## A character on its way to a glyph: its code point, the glyph that
	## draws it (0 until mapped), its cluster (a text offset), its feature
	## mask and HarfBuzz's Unicode property word (`ShaperUnicode.props`).
	Char : { cp : U64, glyph : U64, cluster : U64, mask : U64, props : U64 }

	no_char : Char
	no_char = { cp: 0, glyph: 0, cluster: 0, mask: 0, props: 0 }

	## What the text holds that later steps look for.
	Found : { ignorables : Bool, continuations : Bool, fraction_slash : Bool }

	# ------------------------------------------------------------ properties

	## Characters with their property words and grapheme continuations,
	## as HarfBuzz's `hb_set_unicode_props` marks them: marks, emoji
	## modifiers, the second of a pair of regional indicators, ZWJ and an
	## Extended_Pictographic character after it, halfwidth katakana voiced
	## marks and tag characters continue the grapheme before them.
	prepare : List({ scalar : U32, offset : U64 }), U64 -> { chars : List(Char), found : Found }
	prepare = |scalars, mask| {
		n = scalars.len()
		var $chars = List.with_capacity(n)
		var $ignorables = False
		var $continuations = False
		var $fraction = False
		var $i = 0
		while $i < n {
			s = scalars.get($i) ?? { scalar: 0, offset: 0 }
			u = s.scalar.to_u64()
			p = ShaperUnicode.props(u)
			if p.bitwise_and(ShaperUnicode.ignorable) != 0 {
				$ignorables = True
			}
			gc = ShaperUnicode.general_category_of(p)
			cont = ShaperUnicode.continuation
			{ props, extra } =
				if u < 0x80 or (ShaperUnicode.is_letter_category(gc) and gc != ShaperUnicode.modifier_letter) or gc == ShaperUnicode.space_separator {
					{ props: p, extra: False }
				} else if gc == ShaperUnicode.modifier_symbol and u >= 0x1F3FB and u <= 0x1F3FF {
					{ props: p.bitwise_or(cont), extra: False }
				} else if $i > 0 and ShaperUnicode.is_regional_indicator(u) {
					previous = $chars.last() ?? ShaperNormalize.no_char
					if (ShaperUnicode.is_regional_indicator(previous.cp) and previous.props.bitwise_and(cont) == 0) { props: p.bitwise_or(cont), extra: False } else { props: p, extra: False }
				} else if ShaperUnicode.is_zwj(p) {
					next = scalars.get($i + 1)
					following = match next {
						Ok(nx) => ShaperUnicode.is_pictographic(nx.scalar.to_u64())
						Err(_) => False
					}
					{ props: p.bitwise_or(cont), extra: following }
				} else if (u >= 0xFF9E and u <= 0xFF9F) or (u >= 0xE0020 and u <= 0xE007F) {
					{ props: p.bitwise_or(cont), extra: False }
				} else {
					if u == 0x2044 {
						$fraction = True
					}
					{ props: p, extra: False }
				}
			if props.bitwise_and(cont) != 0 {
				$continuations = True
			}
			$chars = $chars.append({ cp: u, glyph: 0, cluster: s.offset, mask, props })
			if extra {
				# The pictographic character after a ZWJ continues the grapheme.
				nx = scalars.get($i + 1) ?? { scalar: 0, offset: 0 }
				v = nx.scalar.to_u64()
				q = ShaperUnicode.props(v)
				if q.bitwise_and(ShaperUnicode.ignorable) != 0 {
					$ignorables = True
				}
				$chars = $chars.append({ cp: v, glyph: 0, cluster: nx.offset, mask, props: q.bitwise_or(cont) })
				$i = $i + 2
			} else {
				$i = $i + 1
			}
		}
		{ chars: $chars, found: { ignorables: $ignorables, continuations: $continuations, fraction_slash: $fraction } }
	}

	is_continuation : Char -> Bool
	is_continuation = |c| c.props.bitwise_and(ShaperUnicode.continuation) != 0

	## The end of the grapheme starting at `start`.
	grapheme_end : List(Char), U64 -> U64
	grapheme_end = |chars, start| {
		var $end = start + 1
		while $end < chars.len() and ShaperNormalize.is_continuation(chars.get($end) ?? ShaperNormalize.no_char) {
			$end = $end + 1
		}
		$end
	}

	## Each grapheme one cluster (HarfBuzz's `hb_form_clusters` at its
	## grapheme cluster level).
	form_clusters : List(Char) -> List(Char)
	form_clusters = |chars| {
		var $chars = chars
		var $start = 0
		n = chars.len()
		while $start < n {
			end = ShaperNormalize.grapheme_end($chars, $start)
			$chars = ShaperNormalize.merge_clusters($chars, $start, end)
			$start = end
		}
		$chars
	}

	## HarfBuzz's `merge_clusters` on a list without an output: the
	## characters of `start ..< end`, and their neighbours sharing the
	## clusters at either end, take the smallest cluster.
	merge_clusters : List(Char), U64, U64 -> List(Char)
	merge_clusters = |chars, start, end_in|
		if end_in <= start + 1 {
			chars
		} else {
			n = chars.len()
			at = |i| (chars.get(i) ?? ShaperNormalize.no_char).cluster
			var $cluster = at(start)
			for i in (start + 1)..<end_in {
				$cluster = $cluster.min(at(i))
			}
			cluster = $cluster
			var $end = end_in
			if cluster != at($end - 1) {
				while $end < n and at($end - 1) == at($end) {
					$end = $end + 1
				}
			}
			var $start = start
			if cluster != at($start) {
				while $start > 0 and at($start - 1) == at($start) {
					$start = $start - 1
				}
			}
			var $chars = chars
			for i in $start..<$end {
				c = $chars.get(i) ?? ShaperNormalize.no_char
				# `i < $end <= n`.
				$chars = $chars.set(i, { ..c, cluster, mask: if (c.cluster == cluster) c.mask else c.mask.bitwise_and(0x7FFFFFFFFFFFFFFF) }) ?? []
			}
			$chars
		}

	## Each grapheme unsafe to break inside, its characters keeping their
	## clusters (HarfBuzz's `hb_form_clusters` at its character level).
	flag_graphemes : List(Char) -> List(Char)
	flag_graphemes = |chars| {
		var $chars = chars
		var $start = 0
		n = chars.len()
		while $start < n {
			end = ShaperNormalize.grapheme_end($chars, $start)
			if end - $start >= 2 and end - $start <= 255 {
				first = ($chars.get($start) ?? ShaperNormalize.no_char).cluster
				last = ($chars.get(end - 1) ?? ShaperNormalize.no_char).cluster
				cluster = first.min(last)
				for i in $start..<end {
					c = $chars.get(i) ?? ShaperNormalize.no_char
					flagged = if (cluster != first and cluster != last) c.cluster != cluster else if (cluster == first) c.cluster != first else c.cluster != last
					if flagged {
						# `i < end <= n`.
						$chars = $chars.set(i, { ..c, mask: c.mask.bitwise_or(0x8000000000000000) }) ?? []
					}
				}
			}
			$start = end
		}
		$chars
	}

	## Graphemes in reverse order, each kept in order (HarfBuzz's
	## `_hb_ot_layout_reverse_graphemes`), for a run shaped against its
	## script's direction. At the character level each grapheme's clusters
	## merge, as HarfBuzz merges them there.
	reverse_graphemes : List(Char), Bool -> List(Char)
	reverse_graphemes = |chars_in, merge| {
		n = chars_in.len()
		var $starts = []
		var $chars = chars_in
		var $s = 0
		while $s < n {
			$starts = $starts.append($s)
			end = ShaperNormalize.grapheme_end($chars, $s)
			if merge {
				$chars = ShaperNormalize.merge_clusters($chars, $s, end)
			}
			$s = end
		}
		chars = $chars
		var $out = List.with_capacity(n)
		var $k = $starts.len()
		var $end = n
		while $k > 0 {
			start = $starts.get($k - 1) ?? 0
			$out = $out.concat(chars.sublist({ start, len: $end - start }))
			$end = start
			$k = $k - 1
		}
		$out
	}

	## Whether a run of a right-to-left script shaped left to right keeps
	## its order, as HarfBuzz decides in `hb_ensure_native_direction`: when
	## it holds a decimal digit or regional indicator and no letter.
	numeric : List(Char) -> Bool
	numeric = |chars| {
		var $number = False
		var $letter = False
		for c in chars {
			gc = ShaperUnicode.general_category_of(c.props)
			if ShaperUnicode.is_letter_category(gc) {
				$letter = True
			} else if gc == ShaperUnicode.decimal_number or ShaperUnicode.is_regional_indicator(c.cp) {
				$number = True
			}
		}
		$number and !$letter
	}

	## Mirror characters for right-to-left text (HarfBuzz's
	## `hb_ot_rotate_chars`): a character whose mirror the font maps becomes
	## its mirror; any other gets `rtlm_mask`.
	mirror : Face, List(Char), U64 -> List(Char)
	mirror = |face, chars, rtlm_mask|
		chars.map(
			|c| {
				m = ShaperUnicode.mirroring(c.cp)
				if m != c.cp and Face.glyph(face, m.to_u32_wrap()).is_ok() {
					{ ..c, cp: m }
				} else {
					{ ..c, mask: c.mask.bitwise_or(rtlm_mask) }
				}
			},
		)

	# ------------------------------------------------------------ normalisation

	## Set in a property word (above HarfBuzz's 48 bits) when the font maps
	## nothing to the character, so it is drawn with glyph 0.
	missing : U64
	missing = 0x10000000000

	## A character with the glyph a lookup found, or glyph 0 marked missing.
	mapped : Char, Try(U64, [Missing]) -> Char
	mapped = |c, found|
		match found {
			Ok(glyph) => { ..c, glyph }
			Err(_) => { ..c, glyph: 0, props: c.props.bitwise_or(ShaperNormalize.missing) }
		}

	## The glyph the font maps a code point to.
	nominal : Face, U64 -> Try(U64, [Missing])
	nominal = |face, cp| if (cp > 0x10FFFF) Err(Missing) else Face.glyph(face, cp.to_u32_wrap())

	## How a run is normalised: the font, its variation sequences, whether
	## Hebrew presentation forms may compose (HarfBuzz's Hebrew shaper for a
	## font without `mark` positioning) and Hebrew marks reordered.
	Context : { face : Face, variants : TableCmap.Variants, hebrew : Bool, hebrew_forms : Bool }

	## The glyph of a variation sequence (HarfBuzz's `get_variation_glyph`).
	variation_glyph : Context, U64, U64 -> Try(U64, [Missing])
	variation_glyph = |ctx, cp, selector|
		if cp > 0x10FFFF or selector > 0x10FFFF {
			Err(Missing)
		} else {
			match TableCmap.variant(ctx.variants, cp.to_u32_wrap(), selector.to_u32_wrap()) {
				Found(g) => Ok(g)
				UseDefault => ShaperNormalize.nominal(ctx.face, cp)
				NotFound => Err(Missing)
			}
		}

	## Map characters to glyphs, composing and decomposing by what the font
	## maps, as HarfBuzz's `_hb_ot_shape_normalize` does in its composed
	## mode: each character the font lacks is decomposed (as deeply as the
	## font needs; with marks after it, as deeply as the font supports),
	## marks are reordered by combining class, and a mark is composed with
	## the character before it when the font has the composite. A character
	## followed by a variation selector takes the sequence's glyph, and the
	## cluster is not normalised further. A space the font lacks is drawn
	## with the space glyph (its width is fixed later); a no-break hyphen
	## the font lacks with the hyphen's glyph. Anything else the font
	## cannot draw gets glyph 0, marked `missing`. `space_fallback` says
	## whether any space was drawn that way.
	normalize : Context, List(Char) -> { chars : List(Char), space_fallback : Bool }
	normalize = |ctx, chars| ShaperNormalize.normalize_with_marks(ctx, chars, |marks| marks)

	## Script-specific mark ordering runs after canonical ordering and before
	## recomposition. The ordinary normalization path supplies the identity.
	normalize_with_marks : Context, List(Char), (List(Char) -> List(Char)) -> { chars : List(Char), space_fallback : Bool }
	normalize_with_marks = |ctx, chars, order_marks| ShaperNormalize.normalize_mode(ctx, chars, order_marks, { short_simple: True, short_marks: False, compose: True, profile: Unicode })

	## The reference's NONE normalization mode: nominal mappings short
	## circuit decomposition even in a mark cluster, and there is no final
	## recomposition. Unmapped characters still get canonical decomposition
	## and the ordinary space/variation-selector fallbacks; marks still get
	## canonical ordering. This preserves a script shaper's Hangul choices.
	normalize_short_circuit : Context, List(Char) -> { chars : List(Char), space_fallback : Bool }
	normalize_short_circuit = |ctx, chars| ShaperNormalize.normalize_mode(ctx, chars, |marks| marks, { short_simple: True, short_marks: True, compose: False, profile: Unicode })

	Profile : [Unicode, Indic, Khmer, Use]
	Mode : { short_simple : Bool, short_marks : Bool, compose : Bool, profile : Profile }

	## Fully decompose where the font permits, then compose diacritics. Script
	## overrides follow the reference shaper; Unicode is used by Myanmar.
	normalize_script : Context, List(Char), Profile -> { chars : List(Char), space_fallback : Bool }
	normalize_script = |ctx, chars, profile| ShaperNormalize.normalize_mode(ctx, chars, |marks| marks, { short_simple: False, short_marks: False, compose: True, profile })

	normalize_mode : Context, List(Char), (List(Char) -> List(Char)), Mode -> { chars : List(Char), space_fallback : Bool }
	normalize_mode = |ctx, chars, order_marks, mode| {
		count = chars.len()
		if count == 0 {
			return { chars, space_fallback: False }
		}
		# First round: decompose.
		var $out = List.with_capacity(count + 8)
		var $idx = 0
		var $all_simple = True
		var $space = False
		var $going = True
		while $going {
			var $end = $idx + 1
			while $end < count and !ShaperUnicode.is_mark((chars.get($end) ?? ShaperNormalize.no_char).props) {
				$end = $end + 1
			}
			if $end < count {
				# Leave one base for the marks to cluster with.
				$end = $end - 1
			}
			while $idx < $end {
				{ out, space } = ShaperNormalize.decompose_current_in(ctx, chars.get($idx) ?? ShaperNormalize.no_char, mode.short_simple, $out, mode.profile)
				$out = out
				$space = $space or space
				$idx = $idx + 1
			}
			if $idx >= count {
				$going = False
			} else {
				$all_simple = False
				var $marks_end = $idx + 1
				while $marks_end < count and ShaperUnicode.is_mark((chars.get($marks_end) ?? ShaperNormalize.no_char).props) {
					$marks_end = $marks_end + 1
				}
				cluster = chars.sublist({ start: $idx, len: $marks_end - $idx })
				if cluster.any(|c| ShaperUnicode.is_variation_selector(c.cp)) {
					$out = ShaperNormalize.variation_cluster(ctx, cluster, $out)
				} else {
					for c in cluster {
						{ out, space } = ShaperNormalize.decompose_current_in(ctx, c, mode.short_marks, $out, mode.profile)
						$out = out
						$space = $space or space
					}
				}
				$idx = $marks_end
				if $idx >= count {
					$going = False
				}
			}
		}
		if $all_simple {
			return { chars: $out, space_fallback: $space }
		}
		# Second round: reorder marks by combining class.
		reordered = ShaperNormalize.reorder(ctx, $out)
		unhidden = ShaperNormalize.unhide_joiners(order_marks(reordered))
		# Third round: recompose.
		{ chars: if (mode.compose) ShaperNormalize.recompose_in(ctx, unhidden, mode.profile) else unhidden, space_fallback: $space }
	}

	## HarfBuzz's `decompose_current_character`.
	decompose_current : Context, Char, Bool, List(Char) -> { out : List(Char), space : Bool }
	decompose_current = |ctx, c, shortest, out| ShaperNormalize.decompose_current_in(ctx, c, shortest, out, Unicode)

	decompose_current_in : Context, Char, Bool, List(Char), Profile -> { out : List(Char), space : Bool }
	decompose_current_in = |ctx, c, shortest, out, profile| {
		face = ctx.face
		direct = ShaperNormalize.nominal(face, c.cp)
		match (shortest, direct) {
			(True, Ok(glyph)) => { out: out.append({ ..c, glyph }), space: False }
			_ =>
				match ShaperNormalize.decompose_in(ctx, c.cp, shortest, 4, profile) {
					Ok(parts) => { out: out.concat(parts.map(|p| { ..c, cp: p.cp, glyph: p.glyph, props: ShaperUnicode.props(p.cp) })), space: False }
					Err(_) =>
						match direct {
							Ok(glyph) => { out: out.append({ ..c, glyph }), space: False }
							Err(_) => {
								kind = ShaperUnicode.space_type(c.cp)
								space_glyph = ShaperNormalize.nominal(face, 0x20)
								if ShaperUnicode.is_space(c.props) and kind != 0 and space_glyph.is_ok() {
									{ out: out.append({ ..c, glyph: space_glyph ?? 0, props: ShaperUnicode.with_high(c.props, kind) }), space: True }
								} else if c.cp == 0x2011 {
									{ out: out.append(ShaperNormalize.mapped(c, ShaperNormalize.nominal(face, 0x2010))), space: False }
								} else {
									{ out: out.append(ShaperNormalize.mapped(c, Err(Missing))), space: False }
								}
							}
						}
				}
		}
	}

	## HarfBuzz's `decompose`: the characters (with glyphs) a code point
	## decomposes into when the font can draw them; `shortest` stops at the
	## first decomposition the font supports. Unicode decompositions are at
	## most four steps deep; `depth` bounds the walk regardless.
	decompose : Context, U64, Bool, U64 -> Try(List({ cp : U64, glyph : U64 }), [NoDecomposition])
	decompose = |ctx, ab, shortest, depth| ShaperNormalize.decompose_in(ctx, ab, shortest, depth, Unicode)

	decomposition : U64, Profile -> [Two(U64, U64), One(U64), Unchanged]
	decomposition = |cp, profile| match profile {
		Indic if cp == 0x0931 or cp == 0x09DC or cp == 0x09DD or cp == 0x0B94 => Unchanged
		Khmer if cp == 0x17BE or cp == 0x17BF or cp == 0x17C0 or cp == 0x17C4 or cp == 0x17C5 => Two(0x17C1, cp)
		_ => ShaperUnicode.decompose(cp)
	}

	decompose_in : Context, U64, Bool, U64, Profile -> Try(List({ cp : U64, glyph : U64 }), [NoDecomposition])
	decompose_in = |ctx, ab, shortest, depth, profile| {
		face = ctx.face
		split = if (depth == 0) Unchanged else ShaperNormalize.decomposition(ab, profile)
		{ a, b } = match split {
			Two(x, y) => { a: x, b: y }
			One(x) => { a: x, b: 0 }
			Unchanged => { a: 0, b: 0 }
		}
		b_glyph = if (b == 0) Ok(0) else ShaperNormalize.nominal(face, b)
		if a == 0 or b_glyph.is_err() {
			Err(NoDecomposition)
		} else {
			tail = if (b == 0) [] else [{ cp: b, glyph: b_glyph ?? 0 }]
			a_glyph = ShaperNormalize.nominal(face, a)
			match (shortest, a_glyph) {
				(True, Ok(g)) => Ok([{ cp: a, glyph: g }].concat(tail))
				_ =>
					match ShaperNormalize.decompose_in(ctx, a, shortest, depth - 1, profile) {
						Ok(parts) => Ok(parts.concat(tail))
						Err(_) =>
							match a_glyph {
								Ok(g) => Ok([{ cp: a, glyph: g }].concat(tail))
								Err(_) => Err(NoDecomposition)
							}
					}
			}
		}
	}

	## HarfBuzz's `handle_variation_selector_cluster`: a character followed
	## by a variation selector takes the sequence's glyph and absorbs the
	## selector; a sequence the font lacks keeps both characters (the
	## selector marked as one, to be hidden later); nothing is normalised.
	variation_cluster : Context, List(Char), List(Char) -> List(Char)
	variation_cluster = |ctx, cluster, out_in| {
		face = ctx.face
		set = |c| ShaperNormalize.mapped(c, ShaperNormalize.nominal(face, c.cp))
		end = cluster.len()
		var $out = out_in
		var $idx = 0
		while $idx + 1 < end {
			cur = cluster.get($idx) ?? ShaperNormalize.no_char
			next = cluster.get($idx + 1) ?? ShaperNormalize.no_char
			if ShaperUnicode.is_variation_selector(next.cp) {
				match ShaperNormalize.variation_glyph(ctx, cur.cp, next.cp) {
					Ok(glyph) => {
						$out = $out.append({ ..cur, glyph, cluster: cur.cluster.min(next.cluster) })
					}
					Err(_) => {
						$out = $out.append(set(cur))
						selector = { ..next, props: ShaperUnicode.with_category(next.props, ShaperUnicode.format).bitwise_or(ShaperUnicode.variation_selector) }
						$out = $out.append(set(selector))
					}
				}
				$idx = $idx + 2
				while $idx < end and ShaperUnicode.is_variation_selector((cluster.get($idx) ?? ShaperNormalize.no_char).cp) {
					$out = $out.append(set(cluster.get($idx) ?? ShaperNormalize.no_char))
					$idx = $idx + 1
				}
			} else {
				$out = $out.append(set(cur))
				$idx = $idx + 1
			}
		}
		if $idx < end {
			$out = $out.append(set(cluster.get($idx) ?? ShaperNormalize.no_char))
		}
		$out
	}

	## HarfBuzz's longest run of marks it reorders
	## (`HB_OT_SHAPE_MAX_COMBINING_MARKS`).
	max_marks : U64
	max_marks = 32

	class : Char -> U64
	class = |c| ShaperUnicode.class_of(c.props)

	## Runs of marks sorted by combining class, stably, merging the clusters
	## of what moves (HarfBuzz's `hb_buffer_t::sort`); then the Hebrew
	## shaper's own reordering.
	reorder : Context, List(Char) -> List(Char)
	reorder = |ctx, chars| {
		count = chars.len()
		var $chars = chars
		var $i = 0
		while $i < count {
			if ShaperNormalize.class($chars.get($i) ?? ShaperNormalize.no_char) == 0 {
				$i = $i + 1
			} else {
				var $end = $i + 1
				while $end < count and ShaperNormalize.class($chars.get($end) ?? ShaperNormalize.no_char) != 0 {
					$end = $end + 1
				}
				if $end - $i <= ShaperNormalize.max_marks {
					$chars = ShaperNormalize.sort_marks($chars, $i, $end)
					if ctx.hebrew {
						$chars = ShaperNormalize.reorder_hebrew($chars, $i, $end)
					}
				}
				$i = $end
			}
		}
		$chars
	}

	sort_marks : List(Char), U64, U64 -> List(Char)
	sort_marks = |chars, start, end| {
		var $chars = chars
		for i in (start + 1)..<end {
			item = $chars.get(i) ?? ShaperNormalize.no_char
			key = ShaperNormalize.class(item)
			var $j = i
			while $j > start and ShaperNormalize.class($chars.get($j - 1) ?? ShaperNormalize.no_char) > key {
				$j = $j - 1
			}
			if $j != i {
				$chars = ShaperNormalize.merge_clusters($chars, $j, i + 1)
				moved = $chars.get(i) ?? ShaperNormalize.no_char
				var $k = i
				while $k > $j {
					# `$j < $k <= i < end`.
					$chars = $chars.set($k, $chars.get($k - 1) ?? ShaperNormalize.no_char) ?? []
					$k = $k - 1
				}
				$chars = $chars.set($j, moved) ?? []
			}
		}
		$chars
	}

	## HarfBuzz's `reorder_marks_hebrew`: patah or qamats, then sheva or
	## hiriq, then meteg or a below mark: the last two swap (once a run).
	reorder_hebrew : List(Char), U64, U64 -> List(Char)
	reorder_hebrew = |chars, start, end| {
		var $chars = chars
		var $i = start + 2
		while $i < end {
			c0 = ShaperNormalize.class($chars.get($i - 2) ?? ShaperNormalize.no_char)
			c1 = ShaperNormalize.class($chars.get($i - 1) ?? ShaperNormalize.no_char)
			c2 = ShaperNormalize.class($chars.get($i) ?? ShaperNormalize.no_char)
			if (c0 == 20 or c0 == 21) and (c1 == 22 or c1 == 23) and (c2 == 25 or c2 == 220) {
				$chars = ShaperNormalize.merge_clusters($chars, $i - 1, $i + 1)
				a = $chars.get($i - 1) ?? ShaperNormalize.no_char
				b = $chars.get($i) ?? ShaperNormalize.no_char
				# Both indices are below `end`.
				$chars = ($chars.set($i - 1, b) ?? []).set($i, a) ?? []
				$i = end
			} else {
				$i = $i + 1
			}
		}
		$chars
	}

	## A combining grapheme joiner that blocked no reordering is not hidden
	## (HarfBuzz's CGJ rule), so lookups may skip it.
	unhide_joiners : List(Char) -> List(Char)
	unhide_joiners = |chars| {
		count = chars.len()
		var $chars = chars
		if count >= 3 {
			for i in 1..<(count - 1) {
				c = $chars.get(i) ?? ShaperNormalize.no_char
				if c.cp == 0x034F {
					after = ShaperNormalize.class($chars.get(i + 1) ?? ShaperNormalize.no_char)
					before = ShaperNormalize.class($chars.get(i - 1) ?? ShaperNormalize.no_char)
					if after == 0 or before <= after {
						# `i < count`.
						$chars = $chars.set(i, { ..c, props: c.props.bitwise_and(0xFFFFFFFFFFFFFFBF) }) ?? []
					}
				}
			}
		}
		$chars
	}

	## The composition of two characters for the shaper (HarfBuzz's
	## `compose_unicode`, or `compose_hebrew` with presentation forms).
	compose : Context, U64, U64 -> Try(U64, [NoComposition])
	compose = |ctx, a, b| ShaperNormalize.compose_in(ctx, a, b, Unicode)

	compose_in : Context, U64, U64, Profile -> Try(U64, [NoComposition])
	compose_in = |ctx, a, b, profile| {
		if profile != Unicode and ShaperUnicode.is_mark(ShaperUnicode.props(a)) {
			return Err(NoComposition)
		}
		if profile == Indic and a == 0x09AF and b == 0x09BC {
			return Ok(0x09DF)
		}
		match ShaperUnicode.compose(a, b) {
			Ok(ab) => Ok(ab)
			Err(_) => if (ctx.hebrew_forms) ShaperNormalize.compose_hebrew(a, b) else Err(NoComposition)
		}
	}

	dagesh_forms : List(U16)
	dagesh_forms = [0xFB30, 0xFB31, 0xFB32, 0xFB33, 0xFB34, 0xFB35, 0xFB36, 0x0000, 0xFB38, 0xFB39, 0xFB3A, 0xFB3B, 0xFB3C, 0x0000, 0xFB3E, 0x0000, 0xFB40, 0xFB41, 0x0000, 0xFB43, 0xFB44, 0x0000, 0xFB46, 0xFB47, 0xFB48, 0xFB49, 0xFB4A]

	## Hebrew presentation forms Unicode excludes from composition but old
	## fonts want (HarfBuzz's `compose_hebrew`).
	compose_hebrew : U64, U64 -> Try(U64, [NoComposition])
	compose_hebrew = |a, b| {
		found =
			if b == 0x05B4 and a == 0x05D9 {
				0xFB1D
			} else if b == 0x05B7 and a == 0x05F2 {
				0xFB1F
			} else if b == 0x05B7 and a == 0x05D0 {
				0xFB2E
			} else if b == 0x05B8 and a == 0x05D0 {
				0xFB2F
			} else if b == 0x05B9 and a == 0x05D5 {
				0xFB4B
			} else if b == 0x05BC and a >= 0x05D0 and a <= 0x05EA {
				(ShaperNormalize.dagesh_forms.get(a - 0x05D0) ?? 0).to_u64()
			} else if b == 0x05BC and a == 0xFB2A {
				0xFB2C
			} else if b == 0x05BC and a == 0xFB2B {
				0xFB2D
			} else if b == 0x05BF and a == 0x05D1 {
				0xFB4C
			} else if b == 0x05BF and a == 0x05DB {
				0xFB4D
			} else if b == 0x05BF and a == 0x05E4 {
				0xFB4E
			} else if b == 0x05C1 and a == 0x05E9 {
				0xFB2A
			} else if b == 0x05C1 and a == 0xFB49 {
				0xFB2C
			} else if b == 0x05C2 and a == 0x05E9 {
				0xFB2B
			} else if b == 0x05C2 and a == 0xFB49 {
				0xFB2D
			} else {
				0
			}
		if (found == 0) Err(NoComposition) else Ok(found)
	}

	## HarfBuzz's third round: a mark composes with the last starter when
	## nothing between them has an equal or higher class and the font maps
	## the composite; the composite takes both clusters.
	recompose : Context, List(Char) -> List(Char)
	recompose = |ctx, chars| ShaperNormalize.recompose_in(ctx, chars, Unicode)

	recompose_in : Context, List(Char), Profile -> List(Char)
	recompose_in = |ctx, chars, profile| {
		count = chars.len()
		var $in = chars
		var $out = List.with_capacity(count)
		$out = $out.append(chars.get(0) ?? ShaperNormalize.no_char)
		var $starter = 0
		var $idx = 1
		while $idx < count {
			cur = $in.get($idx) ?? ShaperNormalize.no_char
			previous = $out.last() ?? ShaperNormalize.no_char
			starter_char = $out.get($starter) ?? ShaperNormalize.no_char
			composed =
				if ShaperUnicode.is_mark(cur.props) and ($starter + 1 == $out.len() or ShaperNormalize.class(previous) < ShaperNormalize.class(cur)) {
					match ShaperNormalize.compose_in(ctx, starter_char.cp, cur.cp, profile) {
						Ok(ab) =>
							match ShaperNormalize.nominal(ctx.face, ab) {
								Ok(glyph) => Ok({ ab, glyph })
								Err(_) => Err(NoComposition)
							}
						Err(_) => Err(NoComposition)
					}
				} else {
					Err(NoComposition)
				}
			match composed {
				Ok({ ab, glyph }) => {
					# Merge the clusters of the starter up to this mark, as
					# `merge_out_clusters` does, with this mark appended.
					{ out: merged, rest } = ShaperNormalize.merge_out($out.append(cur), $starter, $in, $idx + 1)
					$in = rest
					$out = merged.drop_last(1)
					s = $out.get($starter) ?? ShaperNormalize.no_char
					# `$starter` is below the output's length.
					$out = $out.set($starter, { ..s, cp: ab, glyph, props: ShaperUnicode.props(ab) }) ?? []
				}
				Err(_) => {
					$out = $out.append(cur)
					if ShaperNormalize.class(cur) == 0 {
						$starter = $out.len() - 1
					}
				}
			}
			$idx = $idx + 1
		}
		$out
	}

	## HarfBuzz's `merge_out_clusters` for `out[start ..]`: they, the output
	## before them sharing the first one's cluster and the input from `next`
	## sharing the last one's, take the smallest cluster.
	merge_out : List(Char), U64, List(Char), U64 -> { out : List(Char), rest : List(Char) }
	merge_out = |out, start_in, rest, next| {
		end = out.len()
		if end <= start_in + 1 {
			{ out, rest }
		} else {
			at = |i| (out.get(i) ?? ShaperNormalize.no_char).cluster
			var $cluster = at(start_in)
			for i in (start_in + 1)..<end {
				$cluster = $cluster.min(at(i))
			}
			cluster = $cluster
			var $start = start_in
			while $start > 0 and at($start - 1) == at($start) {
				$start = $start - 1
			}
			last = at(end - 1)
			var $rest = rest
			var $k = next
			while $k < $rest.len() and ($rest.get($k) ?? ShaperNormalize.no_char).cluster == last {
				c = $rest.get($k) ?? ShaperNormalize.no_char
				# `$k` is below the input's length.
				$rest = $rest.set($k, { ..c, cluster, mask: if (c.cluster == cluster) c.mask else c.mask.bitwise_and(0x7FFFFFFFFFFFFFFF) }) ?? []
				$k = $k + 1
			}
			var $out = out
			for i in $start..<end {
				c = $out.get(i) ?? ShaperNormalize.no_char
				# `i < end`, the output's length.
				$out = $out.set(i, { ..c, cluster, mask: if (c.cluster == cluster) c.mask else c.mask.bitwise_and(0x7FFFFFFFFFFFFFFF) }) ?? []
			}
			{ out: $out, rest: $rest }
		}
	}
}

## The Khmer self-tail split must terminate without decomposing its tail
## again; the common decomposer recurses only into the first component.
expect {
	ShaperNormalize.decomposition(0x17BE, Khmer) == Two(0x17C1, 0x17BE) and
		ShaperNormalize.decomposition(0x0931, Indic) == Unchanged and
			ShaperNormalize.decomposition(0x0931, Unicode) == Two(0x0930, 0x093C)
}

## Cluster reassignment clears safety only on characters whose cluster
## actually changes, preserving feature and model metadata in both buffers.
expect {
	a = { ..ShaperNormalize.no_char, cluster: 0, mask: 0x8000000000001234 }
	b = { ..a, cluster: 3 }
	merged = ShaperNormalize.merge_clusters([a, b], 0, 2)
	output = ShaperNormalize.merge_out([a, b], 0, [b], 0)
	merged == [a, { ..b, cluster: 0, mask: 0x1234 }] and
		output.out == merged and output.rest == [{ ..b, cluster: 0, mask: 0x1234 }]
}
