"""Original UPL zero-transform deleted-intermediate benchmark control."""
import argparse,importlib.util,io,json,struct
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables.DefaultTable import DefaultTable
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('original_deleted_leaf',HERE.parent/'deleted-leaf-audit/generate.py');base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base)

def make(all_zero=True):
 data,actions=base.make({'kind':'delete-d','rtl':False});font=TTFont(io.BytesIO(data),recalcTimestamp=False);g=base.geo
 attach=bytes([1,1,0x26,2])+b''.join(g.set_attr(attr,0)for attr in [3,8,4,9])
 chain=g.set_attr(0,0)+attach+g.NEXT+attach+g.set_attr(0,0)+bytes([0x32]);s=bytearray(font.getTableData('Silf'));sub=struct.unpack_from('>I',s,12)[0];pm=sub+struct.unpack_from('>H',s,sub+4)[0];first=sub+struct.unpack_from('>I',s,pm)[0];end=sub+struct.unpack_from('>I',s,pm+4)[0];code=sub+struct.unpack_from('>I',s,first+16)[0];assert end-code==len(chain);s[code:end]=chain;table=DefaultTable('Silf');table.data=bytes(s);font['Silf']=table
 if all_zero:
  for gid in [3,4]:font['hmtx'][font.getGlyphName(gid)]=(0,0)
 out=io.BytesIO();font.save(out,reorderTables=True);return out.getvalue(),chain

def main():
 p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args();data,chain=make()
 def emit(path,data):
  if args.check:assert path.read_bytes()==data,path
  else:path.write_bytes(data)
 emit(HERE/'all-zero-advances.ttf',data)
 positive,_=make(False);emit(HERE/'positive-root-diagnostic.ttf',positive)
 cases=[{'id':f'deleted-attachment-benchmark-{n}','font':'benchmark-deleted-attachment/all-zero-advances.ttf','text':'abcd'*n,'script':'Latn','direction':'ltr','cluster_level':0,'engine':'graphite2','face_options':6,'copies':n,'first_action_hex':chain.hex()}for n in [4,8,16]]
 emit(HERE/'cases.jsonc',(json.dumps({'cases':cases},indent=2)+'\n').encode())
 diagnostics=[{**c,'id':c['id'].replace('benchmark','positive-diagnostic'),'font':'benchmark-deleted-attachment/positive-root-diagnostic.ttf'}for c in cases]
 emit(HERE/'positive-cases.jsonc',(json.dumps({'cases':diagnostics},indent=2)+'\n').encode())
 emit(HERE/'ots-cases.jsonc',(json.dumps({'cases':[cases[0],diagnostics[0]]},indent=2)+'\n').encode());print('One zero-transform font and 3 matched benchmark cases '+('reproduced'if args.check else'generated'))
if __name__=='__main__':main()
