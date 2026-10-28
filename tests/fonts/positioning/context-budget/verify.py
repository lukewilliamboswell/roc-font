"""Cached HB facts plus independent bounded-depth/work model, via native bundle."""
from pathlib import Path
import argparse,copy,hashlib,json,os,subprocess,sys
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
sys.path.insert(0,str(ROOT/'scripts'))
import flight
from _common import load_jsonc

def resource(case):
 """Literal DFS call interpreter; top-level application is not charged."""
 if not case['text']:return None
 name=case['font'];limit=max(65536,case['operations']*len(case['text']))
 depth=case['depth'];calls=0;leaves=0;stopped=set();stack=[]
 if name.startswith('cycle-'):tree={0:[0]*8192}
 elif name.startswith('fanout-'):tree={0:[1]*8192,1:[2]*8192}
 elif name.startswith('many-'):tree={0:[1]*int(name.split('-')[1].split('.')[0])}
 elif name.startswith('ignored-'):return {'advance':510,'budgets':[]}
 else:return None
 stack.append((0,0,0))
 while stack:
  node,index,level=stack[-1]
  children=tree.get(node)
  if children is None:leaves+=1;stack.pop();continue
  if index==len(children):stack.pop();continue
  if calls>=limit:stopped.add('Operations');break
  if level>=depth:stopped.add('Depth');stack.pop();continue
  stack[-1]=(node,index+1,level);calls+=1;stack.append((children[index],0,level+1))
 return {'advance':510+leaves,'budgets':sorted(stopped)}

def mixed_work(case):
 """Interpret cached fontTools graph facts without production execution code."""
 graph=case['work_graph'];limit=max(65536,case['operations']*len(case['text']))
 used=0;inners=0;leaves=0;offset=graph['initial_offset'];stopped=False
 sat=lambda n:max(-2147483648,min(2147483647,n))
 for _ in range(graph['inner_calls']):
  if used==limit:stopped=True;break
  used+=1;inners+=1
  for _ in range(graph['leaves_per_inner']):
   if used==limit:stopped=True;break
   used+=1;leaves+=1;offset=sat(offset+graph['leaf_x_placement'])
  if stopped:break
 for advance in graph['parent_advances']:offset=sat(offset-advance)
 return {'offset':offset,'used':used,'inner_calls':inners,'leaves':leaves,'budgets':['Operations'] if stopped else []}

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--binary',type=Path);args=ap.parse_args()
 data=load_jsonc(HERE/'cases.jsonc');cases=data['cases']
 # Huge direct record arrays are a validator-policy probe, separate from
 # the OTS-accepted nesting/operation regressions replayed here.
 cases=[c for c in cases if not c['font'].startswith('wide-')]
 for c in cases:assert hashlib.sha256((HERE/c['font']).read_bytes()).hexdigest()==c['font_sha256']
 binary=args.binary or ROOT/'.roc-font-tmp/context/query'
 if not args.binary:
  binary.parent.mkdir(parents=True,exist_ok=True);roc=os.environ.get('ROC','roc')
  with flight.flight(roc,work=binary.parent) as dep:subprocess.run([roc,'build','--opt=speed',str(HERE/'query.roc'),f'--output={binary}',*dep],cwd=ROOT,check=True)
 requests=''.join(f"{c['id']}\t{HERE/c['font']}\t{c['depth']}\t{c['operations']}\t{c['direction']}\t{c.get('weight',0)}\t{c['text']}\n" for c in cases)
 p=subprocess.run([str(binary)],input=requests,text=True,capture_output=True,check=True,timeout=120)
 actual={id:json.loads(row) for id,row in (s.split('\t',1) for s in p.stdout.splitlines())}
 errors=[];declared=0
 for c in cases:
  got=actual[c['id']];expected=c.get('oracle',{});model=resource(c)
  if model:
   if not c.get('contract_only') and 'reference_failure' not in expected:assert expected['advances']==[[model['advance'],0]],(c['id'],expected,model)
   if got['advances']!=[[model['advance'],0]] or sorted(got['budgets'])!=model['budgets']:errors.append((c['id'],model,got))
  elif c.get('contract_only') and c['font']=='nested-order.ttf':
   target=0 if c['depth']==0 else 7 if c['depth']==1 else -396
   vertical=0 if c['depth']<2 else 700
   budgets=['Depth'] if c['depth']<2 else []
   if got['offsets']!=[[0,0],[target,vertical]] or got['budgets']!=budgets:errors.append((c['id'],{'offset':[target,vertical],'budgets':budgets},got))
  elif c.get('divergence'):
   assert c['divergence']['kind']=='WorkBudgetAccounting'
   assert c['font']=='attachment-mixed-advances.ttf' and c['text']=='a\u0301'+' '*8 and c['depth']>=2
   assert c['direction'] in ['ltr','rtl'] and c['expected_budgets']==['Operations']
   progress=mixed_work(c);assert progress['budgets']==['Operations']
   adjusted=copy.deepcopy(expected);marks=[i for i,g in enumerate(adjusted['glyphs']) if g==c['work_graph']['mark_glyph']];assert len(marks)==1
   adjusted['offsets'][marks[0]][0]=progress['offset']
   if {k:got[k] for k in adjusted}!=adjusted or got['budgets']!=progress['budgets']:errors.append((c['id'],adjusted,got))
   declared+=1
  elif not c.get('contract_only') and 'reference_failure' not in expected:
   compared={k:([got[k][i] for i in c['sample']] if 'sample' in c else got[k]) for k in expected}
   if compared!=expected or got['budgets']!=c.get('expected_budgets',[]):errors.append((c['id'],expected,got))
  # Queries stay index aligned and retain valid byte clusters on failures.
  n=len(got['glyphs']);assert all(len(got[k])==n for k in ['advances','offsets','clusters'])
  assert all(0<=i<len(c['text'].encode()) for i in got['clusters'])
 again=subprocess.run([str(binary)],input=requests,text=True,capture_output=True,check=True,timeout=120)
 assert p.stdout==again.stdout,'nondeterministic context result'
 for id,expected,got in errors[:16]:
  print(json.dumps({'id':id,'expected_budgets':next(c.get('expected_budgets',[]) for c in cases if c['id']==id),'got_budgets':got.get('budgets'),'expected_sample':{k:v[:3] if isinstance(v,list) else v for k,v in expected.items()},'got_sample':{k:v[:3] if isinstance(v,list) else v for k,v in got.items()}},ensure_ascii=False))
 if errors:raise SystemExit(f'{len(errors)} context mismatches')
 assert declared==2
 print(f"Context positioning: {len(cases)} native cases PASS, including {declared} declared WorkBudgetAccounting partial-progress differences checked by an independent graph; repeated output identical.")
if __name__=='__main__':main()
