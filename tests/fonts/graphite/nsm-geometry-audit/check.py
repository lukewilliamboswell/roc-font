"""Offline exact table facts and immutable public oracle evidence."""
import hashlib,json,struct,subprocess,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
for command in [[HERE/'generate.py','--check'],[HERE/'record_hb.py','--check','--cases','cases.jsonc'],[HERE/'record_raw.py','--check']]:subprocess.run([sys.executable,*map(str,command)],check=True)
def table(data,tag):
 for i in range(struct.unpack_from('>H',data,4)[0]):
  at=12+16*i
  if data[at:at+4]==tag.encode():
   start,size=struct.unpack_from('>II',data,at+8);assert start+size<=len(data);return data[start:start+size]
 raise AssertionError(tag)
for flags in [0,32]:
 for aa,bb in [(601,0),(601,20),(601,602),(0,20)]:
  data=(HERE/f'nsm-noop-{flags}-{aa}-{bb}.ttf').read_bytes();silf=table(data,'Silf');hmtx=table(data,'hmtx');hhea=table(data,'hhea');sub=struct.unpack_from('>I',silf,12)[0];passmap=sub+struct.unpack_from('>H',silf,sub+4)[0];start=sub+struct.unpack_from('>I',silf,passmap)[0];end=sub+struct.unpack_from('>I',silf,passmap+4)[0];action=sub+struct.unpack_from('>I',silf,start+16)[0]
  assert struct.unpack_from('>I',silf)[0]==0x50000 and silf[start]==flags
  assert struct.unpack_from('>H',silf,start+4)[0]==1 and silf[action:end]==bytes([0x1b,0x31])
  assert len(hmtx)==12 and struct.unpack_from('>H',hhea,34)[0]==3
  assert struct.unpack_from('>H',hmtx,4)[0]==aa and struct.unpack_from('>H',hmtx,8)[0]==bb
  assert table(data,'Glat')==struct.pack('>I',0x10000)+b''.join(bytes([1,1])+struct.pack('>h',n)for n in [0,3,16])
records={r['id']:r['result']for r in json.loads((HERE/'raw-records.json').read_text())['records']}
bits=lambda x:struct.unpack('>I',struct.pack('>f',x))[0]
for aa,bb in [(601,0),(601,20),(601,602),(0,20)]:
 for text in ['ab','aab','abb','ba','bab','bb','a']:
  normal=records[f'nsm-noop-0-{aa}-{bb}/{text}'];reverse=records[f'nsm-noop-32-{aa}-{bb}/{text}']
  assert normal['advance_bits'][0]==bits(text.count('a')*aa+text.count('b')*bb)
  for result in [normal,reverse]:
   assert all(s['links_glyph'][:2]==[None,None]for s in result['slots'])
   assert [s['advance_bits'][0]for s in result['slots']]==[bits(aa if c=='a'else bb)for c in text]
  if text=='ab':assert reverse['advance_bits'][0]==bits(0) and all(s['position_bits'][0]==bits(0)for s in reverse['slots'])
print('8 exact SFNT program/metric facts and56 complete raw/HB records current; no reference exceptions')
