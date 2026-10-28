"""Original UPL conditional collision passes from documented GTF/OpCodes."""
from pathlib import Path
import argparse,hashlib,io,json,runpy,struct
from fontTools.ttLib import TTFont
HERE=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');p.add_argument('--base',type=Path,default=HERE.parents[1]/'graphite-geometry/benchmark-shift/shifting-parts.ttf');args=p.parse_args()
assert hashlib.sha256(args.base.read_bytes()).hexdigest()==json.loads((HERE/'base.json').read_text())['sha256']
m=runpy.run_path(str(HERE.parent/'generate.py'));cases=[]
conditions={'absent':b'','false':bytes([0x31]),'true':bytes([0x32]),'feature':bytes([0x2b,0,0,0x30])}
for name,pc in list(conditions.items())+[(f'zero-{name}',pc)for name,pc in conditions.items()]:
 f=TTFont(args.base,lazy=True);f.recalcTimestamp=False;f['hmtx'].metrics['a']=(100,0);old=f.reader['Silf'];oldsub=struct.unpack_from('>I',old,12)[0]
 d=bytearray(m['program'](bytes([0x32]),positioning=True,pass_constraint=pc,version=0x50000));sub=16;d[sub+19]=old[oldsub+19];d[sub+33]=old[oldsub+33];pm=sub+struct.unpack_from('>H',d,sub+4)[0];start=sub+struct.unpack_from('>I',d,pm)[0];d[start]=1
 if name.startswith('zero-'):
  packet=bytearray(54);packet[0]=1;packet[1]=10;struct.pack_into('>H',packet,6,24);struct.pack_into('>H',packet,47,len(pc));code=start+len(packet)-sub;struct.pack_into('>III',packet,8,code,code+len(pc),code+len(pc));d=d[:start]+packet+pc;struct.pack_into('>I',d,pm+4,len(d)-sub)
 m['raw'](f,'Silf',bytes(d))
 # One numeric global feature, with declared values0/1 and actual names.
 m['raw'](f,'Feat',m['u32'](0x20000)+m['u16'](1)+bytes(6)+m['u32'](100)+m['u16'](2)+m['u16'](0)+m['u32'](28)+m['u16'](0x8000)+m['u16'](256)+m['u16'](0)+m['u16'](257)+m['u16'](1)+m['u16'](258))
 for ident,label in [(256,'Collision pass'),(257,'Off'),(258,'On')]:f['name'].setName(label,ident,3,1,0x409)
 buffer=io.BytesIO();f.save(buffer);data=buffer.getvalue();path=HERE/(name+'.ttf')
 if args.check:assert path.read_bytes()==data,path
 else:path.write_bytes(data)
 choices=[None,0,1]if name.endswith('feature')else[None]
 for choice in choices:
  for text in ['', 'ab','ba','aa']:
   for direction in ['ltr','rtl','ttb','btt']:
    for level in [0,1]:
     case={'id':f'{name}/{choice}/{text}/{direction}/{level}','font':path.name,'text':text,'script':'Arab'if direction=='rtl'else'Latn','direction':direction,'cluster_level':level}
     if choice is not None:case['features']=[{'id':100,'value':choice}]
     cases.append(case)
# Pass constraints have one current slot even when there are no rules.
for suffix,reference in [('before',255),('after',1)]:
 f=TTFont(HERE/'zero-feature.ttf',lazy=True);f.recalcTimestamp=False;data=bytearray(f.reader['Silf']);sub=struct.unpack_from('>I',data,12)[0];pm=sub+struct.unpack_from('>H',data,sub+4)[0];start=sub+struct.unpack_from('>I',data,pm)[0];pc=sub+struct.unpack_from('>I',data,start+8)[0];data[pc+2]=reference;m['raw'](f,'Silf',bytes(data));buffer=io.BytesIO();f.save(buffer);path=HERE/f'invalid-reference-{suffix}.ttf'
 if args.check:assert path.read_bytes()==buffer.getvalue(),path
 else:path.write_bytes(buffer.getvalue())
text=json.dumps({'cases':cases},indent=2)+'\n'
if args.check:assert(HERE/'cases.jsonc').read_text()==text
else:(HERE/'cases.jsonc').write_text(text)
print(f'8 original conditional collision fonts and {len(cases)} cases current')
