import Bytes
import LayoutVar
import TableVar

## GPOS anchor formats 1–3 in design units. The font-unit API uses the
## stored coordinates of a format 2 point anchor. Hinting devices have
## no effect at ppem zero; format 3 VariationIndex devices do.
LayoutAnchor := {}.{
	check : List(U8), U64, LayoutVar, List(U64) -> Try(List(U64), [Bad(U64)])
	check = |data, at, lv, deltas| {
		format = Bytes.u16(data, at)
		size = match format {
			1 => 6
			2 => 8
			3 => 10
			_ => return Err(Bad(at))
		}
		if !Bytes.fits(at, size, data.len()) {
			return Err(Bad(at))
		}
		var $out = deltas
		if format == 3 {
			var $field = at + 6
			while $field < at + 10 {
				offset = Bytes.u16(data, $field)
				if offset != 0 {
					device = at + offset
					match LayoutVar.check_device_ots(data, device) {
						Ok(_) => {}
						Err(Truncated) => return Err(Bad($field))
						Err(_) => return Err(Bad(device + 4))
					}
					if Bytes.u16(data, device + 4) == 0x8000 and !LayoutVar.valid_index(lv, Bytes.u16(data, device), Bytes.u16(data, device + 2)) {
						$out = $out.append(device)
					}
				}
				$field = $field + 2
			}
		}
		Ok($out)
	}

	Coordinates : { x : I64, y : I64 }

	coordinates : List(U8), U64, LayoutVar, LayoutVar.Location -> Coordinates
	coordinates = |data, at, lv, loc| {
		x = Bytes.i16(data, at + 2)
		y = Bytes.i16(data, at + 4)
		if loc.active and Bytes.u16(data, at) == 3 {
			{ x: x + LayoutVar.device_delta(lv, loc, data, at, at + 6), y: y + LayoutVar.device_delta(lv, loc, data, at, at + 8) }
		} else {
			{ x, y }
		}
	}

	## The anchor displacement requested by a positioning lookup.
	displacement : List(U8), U64, U64, LayoutVar, LayoutVar.Location -> Coordinates
	displacement = |data, target, source, lv, loc| {
		{ x: bx, y: by } = LayoutAnchor.coordinates(data, target, lv, loc)
		{ x: mx, y: my } = LayoutAnchor.coordinates(data, source, lv, loc)
		if loc.active and (Bytes.u16(data, target) == 3 or Bytes.u16(data, source) == 3) {
			# HarfBuzz subtracts the two anchor coordinates in float.
			difference = |left, right| TableVar.f32_floor(TableVar.f32_sub(TableVar.f32_from_int(left), TableVar.f32_from_int(right)))
			{ x: difference(bx, mx), y: difference(by, my) }
		} else {
			{ x: bx - mx, y: by - my }
		}
	}
}
