"""Original UPL glyph-placement markers; documented GTF/OpCodes only."""
from pathlib import Path
import io,json,runpy,struct
from fontTools.ttLib import TTFont
import argparse
HERE=Path(__file__).resolve().parent;source=HERE.parent;out=HERE
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args();m=runpy.run_path(str(source/'generate.py'))
cases=[]

for native in [1,2]:
 for flags in [0,32]:
  for name,action in [('identity',bytes([0x1b,0x31])),('y0',bytes([1,0,0x23,21,0x1b,0x31])),('y17',bytes([1,17,0x23,21,0x1b,0x31]))]:
   f=TTFont(source/'nsm-geometry-audit/nsm-noop-0-601-20.ttf');f.recalcTimestamp=False;data=bytearray(m['program'](action,version=0x50000));data[48]=native;data[40]=1;sub=16;passmap=sub+struct.unpack_from('>H',data,sub+4)[0];start=sub+struct.unpack_from('>I',data,passmap)[0];data[start]=flags;assert struct.unpack_from('>HHH',data,start+40)==(1,1,0);data[start+42:start+44]=struct.pack('>H',2);m['raw'](f,'Silf',bytes(data));path=out/f'{native}-{flags}-{name}.ttf';buffer=io.BytesIO();f.save(buffer);data=buffer.getvalue()
   if args.check:assert path.read_bytes()==data,path
   else:path.write_bytes(data)
   for text in ['ab','aab','abb','bab','bb','ba']:
    cases.append({'id':f'{native}-{flags}-{name}/{text}','font':path.name,'text':text,'script':'Latn','direction':'ltr','cluster_level':1})

text=json.dumps({'cases':cases},indent=2)+'\n'
if args.check:assert (HERE/'cases.jsonc').read_text()==text
else:(HERE/'cases.jsonc').write_text(text)
print('12 original placement-marker fonts and 72 cases current')

# Natural Arabic mapping and matching requested/native RTL eliminate an
# ASCII/script or unsupported-direction explanation of the observation.
arabic=[]
for flags in [0,32]:
 for advance in [0,20]:
  for action in ['identity','y17']:
   f=TTFont(HERE/f'2-{flags}-{action}.ttf');f.recalcTimestamp=False
   for cmap in f['cmap'].tables:
    if cmap.isUnicode():cmap.cmap={0x628:'a',0x64e:'b'}
   f['hmtx'].metrics['b']=(advance,0);name=f'arabic-{flags}-{advance}-{action}';buffer=io.BytesIO();f.save(buffer);data=buffer.getvalue();path=HERE/(name+'.ttf')
   if args.check:assert path.read_bytes()==data,path
   else:path.write_bytes(data)
   arabic.append({'id':name+'/beh-fatha','font':path.name,'text':'بَ','script':'Arab','direction':'rtl','cluster_level':1})
text=json.dumps({'cases':arabic},indent=2,ensure_ascii=False)+'\n'
if args.check:assert (HERE/'arabic-cases.jsonc').read_text()==text
else:(HERE/'arabic-cases.jsonc').write_text(text)
print('8 natural Arabic/native-RTL controls current')
