"""Pin already executed native failures; never turn them into oracle agreement.

Recording consumes explicit preserved verifier logs/reports plus build
provenance. --check validates committed keys and payloads without an oracle.
"""
from pathlib import Path
import argparse,ast,hashlib,json
from limitations import payload_sha,load
HERE=Path(__file__).resolve().parent
SETS={
 'shape':(HERE/'shape-cases.jsonc',HERE/'shape-records.json',HERE),
 'nsm':(HERE/'nsm-cases.jsonc',HERE/'nsm-records.json',HERE),
 'nsm-geometry':(HERE/'nsm-geometry-audit/cases.jsonc',HERE/'nsm-geometry-audit/hb-records.json',HERE/'nsm-geometry-audit'),
 'nsm-position-visit':(HERE/'nsm-position-visit/cases.jsonc',HERE/'nsm-position-visit/hb-records.json',HERE/'nsm-position-visit'),
 'nsm-native-arabic':(HERE/'nsm-position-visit/arabic-cases.jsonc',HERE/'nsm-position-visit/arabic-hb-records.json',HERE/'nsm-position-visit'),
}
COUNTS={'shape':45,'nsm':544,'nsm-geometry':22,'nsm-position-visit':36,'nsm-native-arabic':4}
REASONS={
 'AwamiPositioning':'Experimental Graphite positioning differs on this completed Awami run. The observed output is regression coverage, not reference agreement.',
 'AwamiDefaultWorkBudget':'The pure Roc Graphite work budget stops this Awami run at default limits. Its exact partial output and Operations diagnostic are retained; completion/reference agreement is not claimed.',
 'NonspacingDirectionPlacement':'Experimental font-defined nonspacing/directional placement differs. Glyph identities, clusters and flags agree in these cases; the observed advances/offsets are not reference agreement.',
}
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def references(name):
 cases,records,fonts=SETS[name]
 return json.loads(cases.read_text())['cases'],{r['id']:r for r in json.loads(records.read_text())['records']},fonts

def main():
 p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');p.add_argument('--logs',type=Path);p.add_argument('--provenance',type=Path);p.add_argument('--registry',type=Path,default=HERE/'known-limitations.json');p.add_argument('--observations',type=Path,default=HERE/'known-observations.json');a=p.parse_args()
 if a.check:
  policy=json.loads(a.registry.read_text());saved=json.loads(a.observations.read_text());assert policy['schema']==saved['schema']==1 and set(policy['sets'])==set(SETS);seen=set()
  for name in SETS:
   cases,records,fonts=references(name);entries,_=load(a.registry,name,cases,records);assert len(entries)==COUNTS[name]
   for row in saved['sets'][name]:
    key=row['id'];assert(name,key)not in seen;seen.add((name,key));entry=entries[key];assert entry['reference_key']==records[key]['key'] and entry['actual_sha256']==payload_sha(row['actual']) and entry['budgets']==row['actual']['budgets']
    case=next(c for c in cases if c['id']==key);assert entry['font_sha256']==sha(fonts/case['font'])
    raw=records[key]['result'];actual=row['actual'];agrees=not actual['budgets']and actual['engine']=='Graphite'and{k:actual.get(k)for k in raw}==raw;assert not agrees,key
  assert len(seen)==651;print('651 exact observed implementation limits current; none counted as reference agreement');return
 if not a.logs or not a.provenance:p.error('recording requires explicit --logs and --provenance')
 provenance=json.loads(a.provenance.read_text());snapshot={k:provenance[k]for k in ['source','bundle','bundle_sha256','compiler_sha256','binary_sha256','optimization','source_sentinel']};snapshot['query_source_sha256']=provenance['query_sha256']
 policy={'schema':1,'kind':'observed_implementation_limits','description':'Experimental Graphite results, not reference agreement or normative divergences. Exact per-case observations only; new, changed, stale-reference and now-agreeing cases fail.','snapshot':snapshot,'reasons':REASONS,'sets':{}}
 observed={'schema':1,'snapshot':snapshot,'sets':{}};sources={}
 for name in SETS:
  cases,records,fonts=references(name);case_map={c['id']:c for c in cases};report_path=a.logs/(name+'.json');log_path=a.logs/(name+'.log');report=json.loads(report_path.read_text());assert not report['reader_failures'] and report['provenance']['binary_sha256']==snapshot['binary_sha256'];actuals={}
  for line in log_path.read_text().splitlines():
   if line.startswith('DIFFER '):
    key,rest=line[7:].split(' expected ',1);expected,value=rest.split(' actual ',1);assert key not in actuals;raw=ast.literal_eval(expected);actual=ast.literal_eval(value);assert raw==records[key]['result'] and isinstance(actual,dict);actuals[key]=actual
  assert set(actuals)==set(report['failures'])and len(actuals)==COUNTS[name],name
  entries=[];rows=[]
  for key in sorted(actuals):
   actual=actuals[key];reference=records[key];raw=reference['result'];case=case_map[key];columns=set()
   assert actual['engine']=='Graphite'and actual['success']==raw['success']and actual['abort']==raw['abort']
   if len(raw['glyphs'])!=len(actual['glyphs']):columns.add('glyph_count')
   else:
    for left,right in zip(raw['glyphs'],actual['glyphs']):
     assert all(left[field]==right[field]for field in ['glyph','cluster','flags'])
     columns.update(field for field in left if left[field]!=right.get(field))
   reason='NonspacingDirectionPlacement'if name!='shape'else'AwamiDefaultWorkBudget'if actual['budgets']else'AwamiPositioning'
   entries.append({'id':key,'reference_key':reference['key'],'font_sha256':sha(fonts/case['font']),'actual_sha256':payload_sha(actual),'budgets':actual['budgets'],'different_fields':sorted(columns),'reason':reason});rows.append({'id':key,'actual':actual})
  policy['sets'][name]=entries;observed['sets'][name]=rows;sources[name]={'native_report_sha256':sha(report_path),'native_log_sha256':sha(log_path)}
 policy['recording_inputs']=sources
 a.registry.write_text(json.dumps(policy,indent=2)+'\n');a.observations.write_text('{\n"schema":1,\n"snapshot":'+json.dumps(snapshot,sort_keys=True)+',\n"sets":{\n'+',\n'.join(json.dumps(name)+':[\n'+',\n'.join(json.dumps(row,separators=(',',':'))for row in rows)+'\n]'for name,rows in observed['sets'].items())+'\n}}\n');print('recorded651 exact experimental observations; raw reference answers unchanged')
if __name__=='__main__':main()
