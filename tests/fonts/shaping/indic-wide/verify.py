#!/usr/bin/env python3
"""Replay the complete cached Indic matrix through an optimized bundle app.
No oracle installation is required. Kept outside global gates until each
model's activation agrees on every case.
"""
import json
import os
from pathlib import Path
import subprocess
import sys

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
sys.path.insert(0,str(ROOT/'scripts'))
import conformance
import flight
from _common import parse_case_file


def main():
    path=HERE/'cases.jsonc'
    cases,problems=parse_case_file(path)
    assert not problems,problems
    records={r['id']:r for r in map(json.loads,(HERE/'cases-records.jsonl').read_text().splitlines())}
    assert len(records)==len(cases) and set(records)=={c.id for c in cases}
    locations=conformance.Locations()
    work=ROOT/'.roc-font-tmp/indic-wide-replay'
    work.mkdir(parents=True,exist_ok=True)
    roc=os.environ.get('ROC','roc')
    binary=work/'query'
    with flight.flight(roc,work=work/'flight') as dep:
        subprocess.run([roc,'build','--opt=speed',str(ROOT/'tools/driver/main.roc'),f'--output={binary}',*dep],cwd=ROOT,check=True)
        results,why,timing=conformance.run_driver([str(binary)],cases,True,locations,{})
    failures=[]
    hashes={}
    for case in cases:
        actual=results.get(case.id,'MISSING-ANSWER')
        record=records[case.id]
        outcome,detail=conformance.classify(case,record,actual,hashes,locations)
        if outcome!='agree':
            failures.append(case.id)
            print(case.id,outcome,detail,'expected',record['result'],'actual',actual,'reader',why.get(case.id,''))
    print(f'{len(cases)-len(failures)}/{len(cases)} exact Indic records agree; {timing}')
    return bool(failures)


if __name__=='__main__':raise SystemExit(main())
