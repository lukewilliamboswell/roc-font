"""Print HarfBuzz's results for the fixtures in this directory, in the shape
the expects in package/TableVarTests.roc embed them.

    tools/oracle/.venv/bin/python -I tests/fonts/variable/oracle.py

Pinned: uharfbuzz 0.56.3 (HarfBuzz 14.6.0). For each location: the
normalised coordinates (F2Dot14), every glyph's advance, and for fonts with
MVAR the x height and underline position.
"""
import os

import uharfbuzz as hb

HERE = os.path.dirname(os.path.abspath(__file__))

LOCATIONS = {
    "var-mapped.ttf": [
        {}, {"wght": 100}, {"wght": 250}, {"wght": 333}, {"wght": 400}, {"wght": 550},
        {"wght": 650}, {"wght": 900}, {"wght": 1000}, {"wght": 700, "wdth": 75},
        {"wght": 456.7, "wdth": 110.25}, {"wdth": 125}, {"wght": 812, "wdth": 81},
    ],
    "var-implicit.ttf": [{}, {"wght": 300}, {"wght": 350}, {"wght": 401}, {"wght": 500}, {"wght": 700}, {"wght": 200}],
    "var-format1.ttf": [{}, {"wght": 800}, {"opsz": 48}, {"wght": 800, "opsz": 48}, {"wght": 600, "opsz": 30}, {"wght": 300, "opsz": 10}],
}

for name, locations in LOCATIONS.items():
    face = hb.Face(hb.Blob.from_file_path(os.path.join(HERE, name)))
    font = hb.Font(face)
    font.scale = (face.upem, face.upem)
    print(f"# {name}")
    for loc in locations:
        font.set_variations(loc)
        coords = [round(c * 16384) for c in font.get_var_coords_normalized()]
        advances = [font.get_glyph_h_advance(g) for g in range(face.glyph_count)]
        extra = ""
        if name == "var-mapped.ttf":
            xh = font.get_metric_position(hb.OTMetricsTag.X_HEIGHT)
            ul = font.get_metric_position(hb.OTMetricsTag.UNDERLINE_OFFSET)
            extra = f" x_height={xh} underline={ul}"
        print(f"{loc} coords={coords} advances={advances}{extra}")
