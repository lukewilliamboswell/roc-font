"""Original high cumulative advance control; no large font is needed."""
from pathlib import Path
import argparse,io
from fontTools.ttLib import TTFont
HERE=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');p.add_argument('--base',type=Path,default=HERE.parent/'graphite-metrics/raw-bounds-lsb100-metric8.ttf');a=p.parse_args()
font=TTFont(a.base,recalcTimestamp=False);font['hmtx'].metrics[font.getGlyphName(2)]=(65535,100)
out=io.BytesIO();font.save(out);target=HERE/'large-advance.ttf'
if a.check:assert target.read_bytes()==out.getvalue()
else:target.write_bytes(out.getvalue())
print('Original large cumulative advance fixture current')
