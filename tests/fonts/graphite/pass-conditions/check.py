"""Offline table facts and cached true-HarfBuzz pass conditions."""
from pathlib import Path
import json,struct,subprocess,sys
HERE=Path(__file__).resolve().parent
subprocess.run([sys.executable,str(HERE.parent/'record_shapes.py'),'--check','--font-root',str(HERE),'--cases',str(HERE/'cases.jsonc'),'--output',str(HERE/'hb-records.json'),'--oracle',str(HERE/'hb-oracle.json')],check=True)
def table(data,tag):
 for i in range(struct.unpack_from('>H',data,4)[0]):
  at=12+16*i
  if data[at:at+4]==tag.encode():
   start,size=struct.unpack_from('>II',data,at+8);assert start+size<=len(data);return data[start:start+size]
 raise AssertionError(tag)
for name,expected in [(prefix+name,expected)for prefix in ['', 'zero-']for name,expected in [('absent',''),('false','31'),('true','32'),('feature','2b000030')]]:
 data=(HERE/(name+'.ttf')).read_bytes();silf=table(data,'Silf');sub=struct.unpack_from('>I',silf,12)[0];pm=sub+struct.unpack_from('>H',silf,sub+4)[0];start=sub+struct.unpack_from('>I',silf,pm)[0];end=sub+struct.unpack_from('>I',silf,pm+4)[0]
 rules=struct.unpack_from('>H',silf,start+4)[0];success=struct.unpack_from('>H',silf,start+28)[0];ranges=struct.unpack_from('>H',silf,start+32)[0];maps=start+40+6*ranges;count=struct.unpack_from('>H',silf,maps+2*success)[0];pre=maps+2*(success+1)+2*count;min_pre,max_pre=silf[pre:pre+2];lengths=pre+2+2*(max_pre-min_pre+1)+3*rules;pc_len=struct.unpack_from('>H',silf,lengths+1)[0];pc=sub+struct.unpack_from('>I',silf,start+8)[0];actions=sub+struct.unpack_from('>I',silf,start+16)[0]
 assert struct.unpack_from('>I',silf)[0]==0x50000 and rules==(0 if name.startswith('zero-')else 1) and silf[start]==1 and silf[sub+19]&32
 assert silf[pc:pc+pc_len].hex()==expected and silf[actions:end].hex()==(''if name.startswith('zero-')else '32')
 assert struct.unpack_from('>H',table(data,'hhea'),34)[0]==3 and len(table(data,'hmtx'))==12
 assert [struct.unpack_from('>H',table(data,'hmtx'),4*i)[0]for i in range(3)]==[600,100,602]
 feat=table(data,'Feat');assert struct.unpack_from('>I',feat,12)[0]==100 and struct.unpack_from('>H',feat,16)[0]==2 and [struct.unpack_from('>h',feat,28+4*i)[0]for i in range(2)]==[0,1]
rows={r['id']:r['result']for r in json.loads((HERE/'hb-records.json').read_text())['records']}
for prefix,expected in [('absent/None',-200),('true/None',-200),('false/None',0),('feature/None',0),('feature/0',0),('feature/1',-200)]:
 for kind in ['', 'zero-']:
  result=rows[kind+prefix+'/ab/ltr/1'];assert result['success'] and result['glyphs'][0]['offset']==[expected,0]
print('8 exact pass/feature/metric definitions and 384 complete HB records current')
