"""Original two-glyph controls for the explicit Silf bidi pass boundary."""
from pathlib import Path
import argparse,io,runpy
from fontTools.ttLib import TTFont
HERE=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');a=p.parse_args()
m=runpy.run_path(str(HERE/'generate.py'))
for native,bidi,reverse in [(1,1,0),(1,255,0),(2,1,0),(2,255,0),(2,1,32),(2,255,32)]:
 name=f'phase-{native}-{bidi}-{reverse}';font=TTFont(HERE/'replace.ttf');font.recalcTimestamp=False
 data=bytearray(m['program'](bytes([0x1c,0,0x19,0x31]),match=(1,2)))
 data[16+18]=bidi;data[16+32]=native;data[16+68]=reverse
 m['raw'](font,'Silf',bytes(data));out=io.BytesIO();font.save(out,reorderTables=True);target=HERE/(name+'.ttf')
 if a.check:assert target.read_bytes()==out.getvalue(),target
 else:target.write_bytes(out.getvalue())
print('6 original pass-boundary controls current')
