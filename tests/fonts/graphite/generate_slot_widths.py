"""Original VM slot-write width probes and independent wide getter controls."""
from pathlib import Path
import argparse, io, runpy
from fontTools.ttLib import TTFont
HERE=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args()
m=runpy.run_path(str(HERE/'generate.py'));programs={}
for attr in [0,20,21,29]:
 for value in [32767,32768,65535,65536]:
  programs[f'slot-width-{attr}-{value}']=(bytes([5])+m['u32'](value)+bytes([0x23,attr,0x28,attr,0,1,2,9,0x23,21,0x32]),False)
programs['slot-wide-getter']=(bytes([0x28,0,0,1,2,9,0x23,21,0x32]),True)
programs['feature-wide-getter']=(bytes([0x2b,1,0,1,2,9,0x23,21,0x32]),False)
programs['metric-wide-getter']=(bytes([0x2a,8,0,0,1,2,9,0x23,21,0x32]),True)
for name,(action,wide) in programs.items():
 font=TTFont(HERE/('continuous-ordinary.ttf' if name=='feature-wide-getter' else 'replace.ttf'));font.recalcTimestamp=False
 if wide:font['hmtx'].metrics['a']=(40000,0)
 m['raw'](font,'Silf',m['program'](action,positioning=True))
 out=io.BytesIO();font.save(out,reorderTables=True);target=HERE/(name+'.ttf')
 if args.check:assert target.read_bytes()==out.getvalue(),target
 else:target.write_bytes(out.getvalue())
print('19 original slot operand width controls current')
