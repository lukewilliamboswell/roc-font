#!/usr/bin/env python3
"""Replay every cached Indic case through the optimized native public driver.
No oracle dependencies, tolerance, or selected hard-coded answers. Kept
outside the global gate while the corresponding model is being activated.
"""
from pathlib import Path
import os,subprocess,sys
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
sys.path.insert(0,str(ROOT/'scripts'))
import flight,conformance
from _common import parse_case_file,load_records
roc=os.environ.get('ROC','roc');work=ROOT/'.roc-font-tmp/complex-replay';work.mkdir(parents=True,exist_ok=True)
path=HERE/'indic-cases.jsonc';cases,problems=parse_case_file(path);assert not problems,problems
records=load_records(path);locations=conformance.Locations()
with flight.flight(roc,work=work/'flight') as dep:
 command=[roc,'build','--opt=speed',str(ROOT/'tools/driver/main.roc'),f'--output={work/"query"}',*dep]
 built=subprocess.run(command,cwd=ROOT,capture_output=True,text=True);print(built.stdout,built.stderr);assert built.returncode==0
 results,why,timing=conformance.run_driver([str(work/'query')],cases,True,locations,{})
failures=[];hashes={}
for case in cases:
 actual=results.get(case.id,'MISSING-ANSWER');record=records.get(case.id)
 outcome,detail=conformance.classify(case,record,actual,hashes,locations)
 if outcome!='agree':
  failures.append(case.id)
  print(case.id,outcome,detail,'expected',record['result'] if record else None,'actual',actual,'reader',why.get(case.id,''))
print(f'{len(cases)-len(failures)}/{len(cases)} cached records agree; {timing}')
raise SystemExit(bool(failures))
