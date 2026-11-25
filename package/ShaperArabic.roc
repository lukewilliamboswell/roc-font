import ShaperArabicData
import ShaperNormalize

## Joining masks for horizontal Arabic. The joining types come from the
## pinned Unicode Character Database. As in HarfBuzz 14.6.0, edges with
## context affect the form, while only clusters inside the run get flags.
ShaperArabic :: {}.{
	Joining : [NonJoining, JoinLeft, JoinRight, JoinBoth, Transparent]

	Masks : { isol : U64, fina : U64, medi : U64, init : U64 }

	Context : { before : Bool, after : Bool }

	## The significant neighbour in up to five scalars, supplied in order
	## away from the run. A non-joining scalar stops the search.
	context_connects : List(U32), Bool -> Bool
	context_connects = |nearest, before| {
		for cp in nearest.take_first(5) {
			form = ShaperArabic.joining(cp.to_u64())
			if form != Transparent {
				return if (before) ShaperArabic.toward_next(form) else ShaperArabic.toward_previous(form)
			}
		}
		False
	}

	## Set each joining character's form by its previous and next
	## significant neighbours. Transparent characters do not join and do
	## not interrupt a connection between two joining characters.
	setup : List(ShaperNormalize.Char), Masks, Context, (List(ShaperNormalize.Char), U64, U64 -> List(ShaperNormalize.Char)) -> List(ShaperNormalize.Char)
	setup = |input, masks, context, flag_join| {
		count = input.len()
		var $chars = input
		var $previous = count
		var $from_previous = False
		var $previous_type = if (context.before) JoinBoth else NonJoining
		for i in 0..<count {
			form = ShaperArabic.joining(($chars.get(i) ?? ShaperNormalize.no_char).cp)
			if form != Transparent {
				connected = ShaperArabic.toward_next($previous_type) and ShaperArabic.toward_previous(form)
				if $previous < count {
					if connected {
						$chars = flag_join($chars, $previous, i + 1)
					}
					$chars = ShaperArabic.set_form($chars, $previous, $previous_type, $from_previous, connected, masks)
				}
				$previous = i
				$previous_type = form
				$from_previous = connected
			}
		}
		if $previous < count {
			connected = ShaperArabic.toward_next($previous_type) and context.after
			if connected {
				$chars = flag_join($chars, $previous, count)
			}
			$chars = ShaperArabic.set_form($chars, $previous, $previous_type, $from_previous, connected, masks)
		}
		$chars
	}

	set_form : List(ShaperNormalize.Char), U64, Joining, Bool, Bool, Masks -> List(ShaperNormalize.Char)
	set_form = |chars, at, form, before, after, masks| {
		mask = match (form, before, after) {
			(NonJoining, _, _) => 0
			(_, True, True) => masks.medi
			(_, True, False) => masks.fina
			(_, False, True) => masks.init
			_ => masks.isol
		}
		if mask == 0 {
			chars
		} else {
			c = chars.get(at) ?? ShaperNormalize.no_char
			# The caller visits an index below the input's length.
			chars.set(at, { ..c, mask: c.mask.bitwise_or(mask) }) ?? []
		}
	}

	toward_next : Joining -> Bool
	toward_next = |form| form == JoinBoth or form == JoinLeft

	toward_previous : Joining -> Bool
	toward_previous = |form| form == JoinBoth or form == JoinRight

	joining : U64 -> Joining
	joining = |cp| {
		if cp < 0xAD {
			return NonJoining
		}
		var $low = 0
		var $high = ShaperArabicData.ranges.len()
		while $low < $high {
			mid = ($low + $high) // 2
			word = ShaperArabicData.ranges.get(mid) ?? 0
			first = word.shr_zf_wrap(24)
			last = word.shr_zf_wrap(3).bitwise_and(0x1FFFFF)
			if cp < first {
				$high = mid
			} else if cp > last {
				$low = mid + 1
			} else {
				return match word.bitwise_and(7) {
					1 => JoinLeft
					2 => JoinRight
					3 => JoinBoth
					4 => Transparent
					_ => NonJoining
				}
			}
		}
		NonJoining
	}
}
