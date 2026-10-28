"""Replay cached independent color facts using an optimized native bundle app.

Graph nodes are compared by their reachable semantic tree, so lawful DAG
sharing and physical node numbering do not constrain the public API. All
returned IDs/spans/reachability are independently checked before comparison.
No fontTools or HarfBuzz installation is needed to replay the cache.
"""
from pathlib import Path
import hashlib,json,os,struct,subprocess,sys,tempfile
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
sys.path.insert(0,str(ROOT/'scripts'))
import flight
from _common import load_jsonc

def graph_digest(g):
 if g is None:return None
 nodes=g['nodes'];seen=set();active=set();memo={}
 def visit(i):
  assert 0<=i<len(nodes),f'invalid node ID {i}'
  if i in memo:return memo[i]
  assert i not in active,'cyclic returned graph';active.add(i);seen.add(i)
  n=dict(nodes[i]);n['children']=[visit(j) for j in n.get('children',[])]
  # All exported geometric values are binary64 values, not decimal approximations.
  def bits(v):
   assert isinstance(v,(int,float)) and float('-inf')<v<float('inf'),'non-finite geometry'
   return struct.pack('>d',float(v)).hex()
  if 'values' in n:n['values']=[bits(v) for v in n['values']]
  if 'stops' in n:n['stops']=[[bits(s[0]),s[1],bits(s[2])] for s in n['stops']]
  if n.get('clip') is not None:n['clip']=[bits(v) for v in n['clip']]
  digest=hashlib.sha256(json.dumps(n,sort_keys=True,separators=(',',':')).encode()).hexdigest()
  active.remove(i);memo[i]=digest;return digest
 root=visit(g['root']);assert len(seen)==len(nodes),'unreachable returned nodes'
 return {'root':root,'clip':None if g['clip'] is None else [struct.pack('>d',float(v)).hex() for v in g['clip']]}

def compare(expected,actual,case):
 assert actual['palettes']==expected['palettes'],f'{case}: palette metadata'
 assert actual['entry_names']==expected['entry_names'],f'{case}: entry labels'
 assert actual['shapes']==expected['shapes'],f'{case}: emoji shaping'
 assert len(actual['glyphs'])==len(expected['glyphs']),f'{case}: glyph count'
 for e,a in zip(expected['glyphs'],actual['glyphs']):
  assert a['glyph']==e['glyph'] and a['layers']==e['layers'],f"{case}: glyph{e['glyph']} COLR0 layers"
  eg=graph_digest(e['graph']);ag=graph_digest(a['graph'])
  if eg!=ag:
   print(json.dumps({'case':case,'glyph':e['glyph'],'expected':e['graph'],'actual':a['graph']},indent=2),file=sys.stderr)
   raise AssertionError(f"{case}: glyph{e['glyph']} graph")

def main():
 cases=load_jsonc(HERE/'cases.jsonc')['cases'];records=[json.loads(s) for s in (HERE/'oracle.jsonl').read_text().splitlines() if s];indexed={r['id']:r for r in records}
 assert len(indexed)==len(records) and set(indexed)=={c['id'] for c in cases}
 for c in cases:assert hashlib.sha256((HERE/c['font']).read_bytes()).hexdigest()==indexed[c['id']]['font_sha256'],c['font']
 roc=os.environ.get('ROC','roc');temp=ROOT/'.roc-font-tmp';temp.mkdir(exist_ok=True)
 with tempfile.TemporaryDirectory(prefix='color-',dir=temp) as directory:
  work=Path(directory);binary=work/'color-queries'
  with flight.flight(roc,work=work) as dep:subprocess.run([roc,'build','--opt=speed',str(HERE/'query.roc'),f'--output={binary}',*dep],cwd=ROOT,check=True)
  requests=''.join(f"{c['id']}\t{HERE/c['font']}\t{c['weight']}\t{'precision' if c.get('precision') else int(c.get('emoji',False))}\n" for c in cases)
  result=subprocess.run([str(binary)],input=requests,text=True,capture_output=True,cwd=ROOT,timeout=120,check=True)
  lines=result.stdout.splitlines();assert len(lines)==len(cases),result.stdout
  for c,line in zip(cases,lines):
   tag,data=line.split('\t',1);assert tag==c['id'];compare(indexed[tag]['facts'],json.loads(data),tag)
 print(f'Color: {len(cases)} cases agree (palettes, labels, all32paint formats, clips, stops, transforms, variation stores/maps and real emoji).')
 return 0
if __name__=='__main__':raise SystemExit(main())
