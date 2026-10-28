"""Original UPL post-DELETE composite metric controls; public formats only."""
import argparse,importlib.util,io,json,struct
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables.DefaultTable import DefaultTable
HERE=Path(__file__).resolve().parent

def module(name,path):
 s=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
leaf=module('original_leaf',HERE.parent/'deleted-leaf-audit/generate.py');star=module('original_star',HERE.parent/'deleted-sibling-audit/generate.py');geo=leaf.geo

def recipes():
 for kind in ['intermediate','middle','tail','head']:
  for level in [0,1]:yield {'kind':kind,'metric':8,'level':level,'rtl':False}
 for metric in [2,5]:
  for level in [0,1]:yield {'kind':'intermediate','metric':metric,'level':level,'rtl':False}
  for kind in ['middle','tail','head']:yield {'kind':kind,'metric':metric,'level':1,'rtl':False}
 for kind in ['intermediate','middle','tail','head']:yield {'kind':kind,'metric':8,'level':1,'rtl':True}

def make(r):
 if r['kind']=='intermediate':builder=leaf;recipe={'kind':'delete-d','rtl':r['rtl']};remain=(1,3,4);root=3
 else:
  target={'middle':2,'tail':3,'head':1}[r['kind']];builder=star;recipe={'kind':'star','target':target,'deleted':True,'rtl':r['rtl']};remain=tuple(g for g in range(1,6)if g!=target);root=4
 data,_=builder.make(recipe);font=TTFont(io.BytesIO(data),recalcTimestamp=False);s=bytearray(font.getTableData('Silf'));sub=struct.unpack_from('>I',s,12)[0];pm=sub+struct.unpack_from('>H',s,sub+4)[0];third=struct.unpack_from('>I',s,pm+8)[0];s[sub+30]=1
 # Keep a raw VM witness in User0, and expose the captured value in the
 # independent trailing root's advance for ordinary public run replay.
 action=bytes([0x2a,r['metric'],remain.index(root),r['level'],0x23,22,0x28,22,0])+geo.NEXT*(len(remain)-1)+bytes([0x23,0,0x32]);payload=bytearray(geo.program(action,True,remain)[84:]);payload[0]=0
 for at in [8,12,16]:struct.pack_into('>I',payload,at,struct.unpack_from('>I',payload,at)[0]+third-68)
 s=s[:sub+third]+payload;struct.pack_into('>I',s,pm+12,len(s)-sub);t=DefaultTable('Silf');t.data=bytes(s);font['Silf']=t;out=io.BytesIO();font.save(out,reorderTables=True);return out.getvalue(),action,(4 if root==3 else 5)

def main():
 p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');a=p.parse_args();cases=[]
 def emit(path,data):
  if a.check:assert path.read_bytes()==data,path
  else:path.write_bytes(data)
 for r in recipes():
  name=f"collision-deleted-metric-{r['kind']}-{r['metric']}-{r['level']}"+('-rtl'if r['rtl']else'-ltr');data,action,count=make(r);emit(HERE/(name+'.ttf'),data);cases.append({'id':name,'font':'deleted-metric-audit/'+name+'.ttf','text':'abcde'[:count],'script':'Latn','direction':'rtl'if r['rtl']else'ltr','face_options':0,'recipe':r,'metric_action_hex':action.hex()})
 for mode,file in [(0,'cases.jsonc'),(6,'mode6-cases.jsonc')]:emit(HERE/file,(json.dumps({'cases':[{**c,'face_options':mode}for c in cases]},indent=2)+'\n').encode())
 print('22 original post-DELETE metric fonts '+('reproduced'if a.check else'generated'))
if __name__=='__main__':main()
