"""Original Glat geometry read-boundary controls from documented fields."""
from pathlib import Path
import argparse,io,runpy,json,hashlib
from fontTools.ttLib import TTFont
HERE=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');a=p.parse_args()
m=runpy.run_path(str(HERE/'generate.py'));raw=m['raw'];u16=m['u16'];u32=m['u32'];records=[]
for mode in ['valid','inverted-y','inverted-many','equal','unknown-gloc-flags']:
 header=bytes([0,3,0,255,0,255]);parts=bytes([0,255,0,255,0,255,0,255])*2
 offsets=[]
 if mode=='inverted-y':
  parts=parts[:10]+bytes([192,64])+parts[12:];offsets=[24]
 elif mode=='inverted-many':
  header=bytes([0,3,255,0,255,0]);parts=parts[:8]+bytes([255,0])*4;offsets=[10,12,22,24,26,28]
 elif mode=='equal':
  header=bytes([0,3,0,0,0,0]);parts=bytes(16)
 blocks=[header+parts,bytes([0,0,0,255,0,255]),bytes([0,0,0,255,0,255])]
 locations=[8]
 for block in blocks:locations.append(locations[-1]+len(block))
 font=TTFont(HERE/'replace.ttf');font.recalcTimestamp=False
 raw(font,'Gloc',u32(0x10000)+u16(0x8000 if mode=='unknown-gloc-flags' else 0)+u16(1)+b''.join(u16(n) for n in locations))
 raw(font,'Glat',u32(0x30000)+u32(1)+b''.join(blocks));out=io.BytesIO();font.save(out,reorderTables=True);data=out.getvalue();name=f'bounds-{mode}.ttf';target=HERE/name
 if a.check:assert target.read_bytes()==data,target
 else:target.write_bytes(data)
 records.append({'font':name,'sha256':hashlib.sha256(data).hexdigest(),'valid':not offsets,'glat_offsets':offsets})
target=HERE/'bounds-policy.json';text=json.dumps({'format_source':'https://github.com/silnrsi/graphite/blob/1.3.14/doc/GTF.asc','section':'Octabox_metrics/Subbox_entry, ordered min/max pairs; equality allowed','cases':records},indent=2)+'\n'
if a.check:assert target.read_text()==text
else:target.write_text(text)
print('5 original Glat/Gloc bound controls current')
