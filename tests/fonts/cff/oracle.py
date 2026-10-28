#!/usr/bin/env python3
"""Cache independent CFF paths/extents, never generated Roc assertions.

fontTools supplies unrounded doubles. HarfBuzz's draw ABI narrows coordinates
to binary32; retain that separate record rather than degrading public paths.
"""
import argparse
import hashlib
import json
import struct
from pathlib import Path
import fontTools
from fontTools.ttLib import TTFont
from fontTools.pens.recordingPen import RecordingPen, DecomposingRecordingPen
from fontTools.varLib.varStore import VarStoreInstancer
import uharfbuzz as hb

HERE = Path(__file__).resolve().parent

def f32(value):
    return struct.unpack(">f", struct.pack(">f", value))[0]

def region_scalars(store, axes, normalized):
    """OFF region formula using the reference shaper's binary32 policy.

    Geometry still executes through fontTools' unmodified Type2 interpreter;
    only its explicitly supplied scalar input vector differs.
    """
    result = []
    for region in store.VarRegionList.Region:
        scalar = 1.0
        for axis, support in zip(axes, region.VarRegionAxis):
            start, peak, end = support.StartCoord, support.PeakCoord, support.EndCoord
            coord = normalized.get(axis.axisTag, 0)
            if start > peak or peak > end or (start < 0 < end and peak != 0):
                factor = 1.0
            elif peak == 0 or coord == peak:
                factor = 1.0
            elif coord <= start or coord >= end:
                factor = 0.0
            elif coord < peak:
                factor = f32((coord - start) / (peak - start))
            else:
                factor = f32((end - coord) / (end - peak))
            scalar = f32(scalar * factor)
        result.append(scalar)
    return result

def canonical(path):
    result = []
    start = None
    for op, points in path:
        points = [list(point) for point in points]
        if op == "moveTo":
            start = points[0]
        if op == "closePath" and result and result[-1] == ["lineTo", [start]]:
            result.pop()
        result.append([op, points])
    return result

def locations(font):
    result = [{}]
    if "fvar" in font:
        axes = font["fvar"].axes
        for axis in axes:
            for value in [axis.minValue, (axis.minValue + axis.defaultValue) / 2,
                          (axis.defaultValue + axis.maxValue) / 2, axis.maxValue]:
                point = {axis.axisTag: value}
                if value != axis.defaultValue and point not in result:
                    result.append(point)
        if len(axes) > 1:
            result.append({axis.axisTag: axis.maxValue for axis in axes})
            result.append({axis.axisTag: axis.minValue for axis in axes})
    return result

def generate():
    assert fontTools.__version__ == "4.61.1"
    assert hb.version_string() == "14.6.0"
    records = []
    for file in ["sans-cff1.otf", "cid-cff1.otf", "sans-cff2.otf", "serif-cff2.otf", "operators-cff1.otf"]:
        path = HERE / file
        data = path.read_bytes()
        tt = TTFont(path, recalcTimestamp=False)
        face = hb.Face(data)
        digest = hashlib.sha256(data).hexdigest()
        for axes in locations(tt):
            reference = hb.Font(face)
            reference.set_variations(axes)
            # The public package and HarfBuzz select normalized F2DOT14
            # coordinates. Give fontTools those same inputs: its default
            # design-space normalization otherwise retains extra precision.
            normalized = dict(zip([axis.axisTag for axis in tt["fvar"].axes],
                                  reference.get_var_coords_normalized())) if "fvar" in tt else {}
            glyph_set = tt.getGlyphSet(location=normalized, normalized=True)
            scalar_set = tt.getGlyphSet(location=normalized, normalized=True)
            scalars = []
            if "CFF2" in tt and hasattr(scalar_set.charStrings, "varStore"):
                store = scalar_set.charStrings.varStore.otVarStore
                axes_info = tt["fvar"].axes
                scalars = region_scalars(store, axes_info, normalized)
                instancer = VarStoreInstancer(store, axes_info, normalized)
                instancer._scalars.update(enumerate(scalars))
                scalar_set.blender = instancer.interpolateFromDeltas
            for glyph, name in enumerate(tt.getGlyphOrder()):
                ft_pen = DecomposingRecordingPen(glyph_set)
                glyph_set[name].draw(ft_pen)
                scalar_pen = DecomposingRecordingPen(scalar_set)
                scalar_set[name].draw(scalar_pen)
                hb_pen = RecordingPen()
                reference.draw_glyph_with_pen(glyph, hb_pen)
                extents = reference.get_glyph_extents(glyph)
                bounds = None if extents is None else [extents.x_bearing,
                    extents.y_bearing + extents.height,
                    extents.x_bearing + extents.width, extents.y_bearing]
                records.append({"id": f"cff-{len(records):05d}", "font": file,
                    "sha256": digest, "glyph": glyph, "axes": axes, "normalized": normalized,
                    "fonttools_path": canonical(ft_pen.value),
                    "region_scalars_f32": scalars,
                    "fonttools_f32_scalar_path": canonical(scalar_pen.value),
                    "harfbuzz_path": canonical(hb_pen.value), "harfbuzz_extents": bounds})
    return {"fontTools": fontTools.__version__, "harfbuzz": hb.version_string(), "records": records}

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    data = json.dumps(generate(), separators=(",", ":")) + "\n"
    destination = HERE / "oracle.json"
    if args.check:
        assert destination.read_text() == data, "regenerate oracle.json"
    else:
        destination.write_text(data)
    print(f"CFF: {len(json.loads(data)['records'])} independent cached path/extents records")
