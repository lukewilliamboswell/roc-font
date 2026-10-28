"""Original UPL observable DELETE references, from documented GTF bytecode."""
from pathlib import Path
import argparse,hashlib,io,json,struct,runpy
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables.DefaultTable import DefaultTable
HERE=Path(__file__).resolve().parent;SOURCE=HERE.parents[1]/'graphite-geometry/deleted-leaf-audit'
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');a=p.parse_args();cases=[];facts=[]
for rtl in [False,True]:
 direction='rtl'if rtl else'ltr';script='Arab'if rtl else'Latn'
 for kind in ['getter','constant']:
  for detached in [False,True]:
   name=f'{kind}-'+('detached-'if detached else'')+direction;source=SOURCE/f'collision-deleted-leaf-{name}.ttf';f=TTFont(source,lazy=True);f.recalcTimestamp=False;data=bytearray(f.reader['Silf']);needle=bytes.fromhex('2028020019231632'if kind=='getter'else'20017b19231632');assert data.count(needle)==1
   at=data.index(needle)+len(needle)-2;assert data[at]==22;data[at]=21;raw=DefaultTable('Silf');raw.data=bytes(data);f['Silf']=raw;out=io.BytesIO();f.save(out);path=HERE/(name+'.ttf');result=out.getvalue()
   if a.check:assert path.read_bytes()==result
   else:path.write_bytes(result)
   facts.append({'font':path.name,'source':source.name,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'silf_changed_offset':at,'old_attribute':22,'new_attribute':21,'expected_y':123 if kind=='constant'else(0 if detached else 1)})
   for level in [0,1]:cases.append({'id':name+f'/clusters-{level}','font':path.name,'text':'abcd','direction':direction,'script':script,'cluster_level':level})
 for kind in ['keep','delete-d','delete-a','delete-da','delete-ad']:
  name=f'collision-deleted-leaf-{kind}-{direction}.ttf'
  for level in [0,1]:cases.append({'id':name+f'/clusters-{level}','font':'../../graphite-geometry/deleted-leaf-audit/'+name,'text':'abcd','direction':direction,'script':script,'cluster_level':level})
# A two-child star exercises the budgeted non-first-sibling unlink.
 for kind in ['delete-d','delete-a']:
  source=SOURCE/f'collision-deleted-leaf-{kind}-{direction}.ttf';f=TTFont(source,lazy=True);f.recalcTimestamp=False;data=bytearray(f.reader['Silf']);needle=bytes([1,1,0x26,2]);assert data.count(needle)==2;at=data.index(needle)+1;data[at]=2;raw=DefaultTable('Silf');raw.data=bytes(data);f['Silf']=raw;out=io.BytesIO();f.save(out);path=HERE/f'star-{kind}-{direction}.ttf'
  if a.check:assert path.read_bytes()==out.getvalue()
  else:path.write_bytes(out.getvalue())
  for level in [0,1]:cases.append({'id':path.stem+f'/clusters-{level}','font':path.name,'text':'abcd','direction':direction,'script':script,'cluster_level':level})
# NEXT can reach a text slot beyond the rule match; missing text aborts DELETE.
program=runpy.run_path(str(HERE.parent/'nsm-geometry-audit/generate.py'))['program'];f=TTFont(HERE.parent/'replace.ttf',recalcTimestamp=False);raw=DefaultTable('Silf');raw.data=program(bytes([0x19,0x20,0x32]),version=0x50000);f['Silf']=raw;out=io.BytesIO();f.save(out);path=HERE/'next-delete.ttf'
if a.check:assert path.read_bytes()==out.getvalue()
else:path.write_bytes(out.getvalue())
for text in ['', 'a','ab','aa','aba']:
 for direction in ['ltr','rtl','ttb','btt']:
  for level in [0,1]:cases.append({'id':f'next-delete/{text}/{direction}/clusters-{level}','font':path.name,'text':text,'direction':direction,'script':'Latn','cluster_level':level})
for end in [1,2]:
 for direction in ['ltr','rtl','ttb','btt']:
  for level in [0,1]:cases.append({'id':f'next-delete/range-{end}/{direction}/clusters-{level}','font':path.name,'text':'ab','range':[0,end],'direction':direction,'script':'Latn','cluster_level':level})
for name,contents in [('cases.jsonc',{'cases':cases}),('facts.json',facts)]:
 text=json.dumps(contents,indent=2)+'\n'
 if a.check:assert(HERE/name).read_text()==text
 else:(HERE/name).write_text(text)
print('13 original deletion fonts and100 true-HB cases current')
