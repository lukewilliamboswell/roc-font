"""Original Silf5 directionality/NSM controls from documented table fields."""
from pathlib import Path
import argparse,io,json,runpy,struct
from fontTools.ttLib import TTFont
HERE=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');a=p.parse_args()
m=runpy.run_path(str(HERE/'generate.py'));root=HERE/'nsm';root.mkdir(exist_ok=True);cases=[]
variants=[(native,mark,first,reverse)for native in [1,2]for mark in [0,16]for first in [1,2]for reverse in [0,32]]
variants += [(2,mark,1,reverse)for mark in [272,-240,528]for reverse in [0,32]]
for native,mark,first,reverse in variants:
 name=f'nsm-{native}-{mark}-{first}-{reverse}.ttf';f=TTFont(HERE/'replace.ttf');f.recalcTimestamp=False
 d=bytearray(m['program'](bytes([0x1c,0,0x19,0x19,0x31]),match=(first,3-first),version=0x50000));d[48]=native;d[40]=1;d[88]=reverse
 m['raw'](f,'Silf',bytes(d));m['raw'](f,'Gloc',m['u32'](0x10000)+m['u16'](0)+m['u16'](2)+b''.join(m['u16'](n)for n in [4,8,12,16]));m['raw'](f,'Glat',m['u32'](0x10000)+b''.join(bytes([1,1])+struct.pack('>h',n)for n in [0,3,mark]))
 output=io.BytesIO();f.save(output,reorderTables=True);target=root/name
 if a.check:assert target.read_bytes()==output.getvalue(),target
 else:target.write_bytes(output.getvalue())
 texts=['ab','ba','abab','baba','abb','bbab','aabbab']if mark in [0,16]else ['ab','baba']
 for script in ['Latn','Arab']:
  for direction in ['ltr','rtl','ttb','btt']:
   for level in [0,1]:
    for text in texts:cases.append({'id':f'{name[:-4]}/{script}/{direction}/{level}/{text}','font':'nsm/'+name,'text':text,'script':script,'direction':direction,'cluster_level':level})
text=json.dumps({'cases':cases},ensure_ascii=False,indent=2)+'\n';target=HERE/'nsm-cases.jsonc'
if a.check:assert target.read_text()==text
else:target.write_text(text)
print(len(variants),'original proper-Silf5 fonts,',len(cases),'NSM direction controls current')
