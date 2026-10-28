"""Original shared-language-setting spans: accepted by Graphite2 and OTS."""
from pathlib import Path
import argparse,runpy
from fontTools.ttLib import TTFont
HERE=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args();m=runpy.run_path(str(HERE/'generate.py'));u16=m['u16'];u32=m['u32']
for count in [64,256,1024]:
 font=TTFont(HERE/'replace.ttf');start=12+8*(count+1);entries=[]
 for i in range(count):
  code=bytes([97+i//676,97+(i//26)%26,97+i%26,0]);entries.append(code+u16(count)+u16(start))
 data=u32(0x10000)+u16(count)+u16(8*count)+u16(count.bit_length()-1)+u16(0)+b''.join(entries)+u32(0x80808080)+u16(0)+u16(start+8*count)+((u32(100)+u16(1)+u16(0))*count)
 m['raw'](font,'Sill',data);font.recalcTimestamp=False
 import io
 out=io.BytesIO();font.save(out,reorderTables=True);target=HERE/f'overlap-{count}.ttf'
 if args.check:assert target.read_bytes()==out.getvalue()
 else:target.write_bytes(out.getvalue())
print('3 shared-setting span fixtures current')
