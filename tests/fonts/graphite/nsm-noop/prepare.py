"""Original no-op font controls; no reference implementation source used."""
from pathlib import Path
import argparse,io,json,runpy,struct
from fontTools.ttLib import TTFont
HERE=Path(__file__).resolve().parent;BASE=HERE.parent
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');a=p.parse_args();m=runpy.run_path(str(BASE/'generate.py'));cases=[]
for reverse in [0,32]:
 name=f'noop-{reverse}.ttf';f=TTFont(BASE/'replace.ttf');f.recalcTimestamp=False;f['hmtx'].metrics['b']=(0,0)
 data=bytearray(m['program'](bytes([0x1b,0x31]),version=0x50000));data[48]=2;data[40]=1;data[88]=reverse;data[90]=16;data[91]=16
 m['raw'](f,'Silf',bytes(data));m['raw'](f,'Gloc',m['u32'](0x10000)+m['u16'](0)+m['u16'](2)+b''.join(m['u16'](n)for n in [4,8,12,16]));m['raw'](f,'Glat',m['u32'](0x10000)+b''.join(bytes([1,1])+struct.pack('>h',n)for n in [0,3,16]));out=io.BytesIO();f.save(out,reorderTables=True);target=HERE/name
 if a.check:assert target.read_bytes()==out.getvalue(),target
 else:target.write_bytes(out.getvalue())
 for engine in ['graphite2','ot']:cases.append({'id':f'noop-{reverse}/{engine}','font':name,'text':'ab','script':'Latn','direction':'ltr','cluster_level':1,'engine':engine})
text=json.dumps({'cases':cases},indent=2)+'\n';target=HERE/'cases.jsonc'
if a.check:assert target.read_text()==text
else:target.write_text(text)
print('2 original no-op fonts and4 engine controls current')
