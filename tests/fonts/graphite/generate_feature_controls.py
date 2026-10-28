"""Original continuous, alias and language-feature controls from GTF formats."""
from pathlib import Path
import argparse, io, runpy
from fontTools.ttLib import TTFont
HERE=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args()
m=runpy.run_path(str(HERE/'generate.py'));u16=m['u16'];u32=m['u32'];raw=m['raw']
for name,identity,declared,alias in [
 ('continuous-language',1,False,False),('continuous-ordinary',102,False,False),
 ('declared-language',1,True,False),('feature-alias',101,False,True),
]:
 font=TTFont(HERE/'replace.ttf');font.recalcTimestamp=False
 # Bytecode feature index1, regardless of caller-visible numeric identity.
 raw(font,'Silf',m['program'](bytes([0x2b,1,0,0x23,0,0x32]),positioning=True))
 first=u32(100)+u16(2)+u16(0)+u32(44)+u16(0x8000)+u16(256)
 second=u32(identity)+u16(2 if declared else 0)+u16(0)+u32(52)+u16(1 if alias else 0)+u16(256)
 values=u16(0)+u16(257)+u16(1)+u16(258)
 raw(font,'Feat',u32(0x20001 if alias else 0x20000)+u16(2)+bytes(6)+first+second+values+(values if declared else b''))
 raw(font,'Sill',u32(0x10000)+u16(1)+u16(8)+u16(0)+u16(0)+b'ksw\0'+u16(1)+u16(28)+u32(0x80808080)+u16(0)+u16(36)+u32(100)+u16(1)+u16(0))
 out=io.BytesIO();font.save(out,reorderTables=True);target=HERE/(name+'.ttf')
 if args.check:assert target.read_bytes()==out.getvalue(),target
 else:target.write_bytes(out.getvalue())
print('4 original feature controls current')
