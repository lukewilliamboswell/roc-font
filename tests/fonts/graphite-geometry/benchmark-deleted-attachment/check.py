"""Offline proof that the BEFORE baseline times only matched ordered output."""
import hashlib,json,struct,subprocess,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
commands=[[HERE/'generate.py','--check'],[HERE/'record_hb.py','--check'],[HERE/'record_raw.py','--check'],[HERE/'record_hb.py','--check','--cases','benchmark-deleted-attachment/positive-cases.jsonc','--output','benchmark-deleted-attachment/positive-hb-records.json','--oracle','benchmark-deleted-attachment/positive-hb-oracle.json'],[HERE/'record_raw.py','--check','--cases','benchmark-deleted-attachment/positive-cases.jsonc','--output','benchmark-deleted-attachment/positive-raw-records.json'],[HERE/'record_ots.py','--check']]
for command in commands:subprocess.run([sys.executable,*map(str,command)],check=True)
sha=lambda b:hashlib.sha256(b).hexdigest()
def table(data,tag):
 for i in range(struct.unpack_from('>H',data,4)[0]):
  p=12+16*i
  if data[p:p+4]==tag.encode():start,size=struct.unpack_from('>II',data,p+8);assert start+size<=len(data);return data[start:start+size]
 raise AssertionError(tag)
zero=lambda attr:bytes([3,0,0,0x23,attr]);attach=bytes([1,1,0x26,2])+b''.join(zero(attr)for attr in [3,8,4,9]);chain=zero(0)+attach+bytes([0x19])+attach+zero(0)+bytes([0x32])
for name,advances in [('all-zero-advances.ttf',[0,0]),('positive-root-diagnostic.ttf',[603,604])]:
 data=(HERE/name).read_bytes();s=table(data,'Silf');sub=struct.unpack_from('>I',s,12)[0];pm=sub+struct.unpack_from('>H',s,sub+4)[0];first=sub+struct.unpack_from('>I',s,pm)[0];end=sub+struct.unpack_from('>I',s,pm+4)[0];code=sub+struct.unpack_from('>I',s,first+16)[0];assert s[code:end]==chain
 hmtx=table(data,'hmtx');assert[struct.unpack_from('>H',hmtx,4*gid)[0]for gid in[3,4]]==advances
proof=json.loads((HERE/'before-public-proof.json').read_text());assert len(proof['rows'])==6
for row in proof['rows']:
 benchmark='positive-diagnostic'not in row['id'];assert row['exact_complete_run']==benchmark
 assert row['actual']['engine']=='Graphite'and not row['actual']['budgets']
 assert (row['actual']['glyphs']==row['expected']['glyphs'])==benchmark
font=(HERE/'all-zero-advances.ttf').read_bytes();bench=json.loads((HERE/'before-speed.json').read_text());assert bench['font_sha256']==sha(font)and bench['text_piece']=='abcd'and bench['script']=='Latn'and bench['direction']=='ltr'
records=json.loads((HERE/'hb-records.json').read_text())['records'];raw=json.loads((HERE/'records.json').read_text())['records'];assert[len(r['result']['glyphs'])for r in records]==[12,24,48]
mask=2**64-1
mix=lambda h,n:((h^(n&mask))*1099511628211)&mask
for row,record,rr,allocations in zip(bench['rows'],records,raw,[125,225,426]):
 h=mix(14695981039346656037,len(record['result']['glyphs']))
 for glyph in record['result']['glyphs']:
  for value in[glyph['glyph'],glyph['cluster'],*glyph['advance'],*glyph['offset'],glyph['flags']&1]:h=mix(h,value)
 assert row['output_checksum']==h and row['allocations']==allocations and row['leaked']==0
 assert rr['result']['advance_bits']==[0,0]
 assert row['copies']in[4,8,16]and len(row['samples'])==5
 assert all(sample['ratio']==sample['roc_ns']/sample['hb_graphite_ns']for sample in row['samples'])
assert bench['requested_bytes']is None and bench['peak_live_bytes']is None
print('Matched BEFORE only: 3 zero-advance runs, 3 preserved positive-root failures, ordered HB checksums and native allocation/timing evidence current')
