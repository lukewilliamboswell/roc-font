#!/usr/bin/env python3
"""Replay cached AAT cases through the optimized public driver."""
from pathlib import Path
import argparse,contextlib,json,os,subprocess,sys
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
sys.path.insert(0,str(ROOT/'scripts'))
import flight,conformance
from _common import parse_case_file,load_records
parser=argparse.ArgumentParser();parser.add_argument('--binary',type=Path);parser.add_argument('--cases',default='mort-cases');args=parser.parse_args()
roc=os.environ.get('ROC','roc');work=ROOT/('.roc-font-tmp/'+'mort-replay');work.mkdir(parents=True,exist_ok=True)
path=HERE/(args.cases+'.jsonc');cases,problems=parse_case_file(path);assert not problems,problems
records={record['id']:record for record in map(json.loads,(HERE/(args.cases+'-records.jsonl')).read_text().splitlines())};locations=conformance.Locations()
with (contextlib.nullcontext([]) if args.binary else flight.flight(roc,work=work/'flight')) as dep:
 if not args.binary:
  mirror=flight.make_mirror(work/'mirror')
  command=[roc,'build','--opt=speed',str(mirror/'tools/driver/main.roc'),f'--output={work/"query"}',*dep]
  built=subprocess.run(command,cwd=mirror,capture_output=True,text=True);print(built.stdout,built.stderr);assert built.returncode==0
 results,why,timing=conformance.run_driver([str(args.binary.resolve() if args.binary else work/'query')],cases,True,locations,{})
failures=[];hashes={}
for case in cases:
 actual=results.get(case.id,'MISSING-ANSWER');record=records.get(case.id)
 outcome,detail=conformance.classify(case,record,actual,hashes,locations)
 if outcome!='agree':
  failures.append(case.id)
  print(case.id,outcome,detail,'expected',record['result'] if record else None,'actual',actual,'reader',why.get(case.id,''))
print(f'{len(cases)-len(failures)}/{len(cases)} cached records agree; {timing}')
raise SystemExit(bool(failures))
