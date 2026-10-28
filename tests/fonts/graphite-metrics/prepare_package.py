"""Prepare the explicitly partitioned normative public-package gate offline."""
import argparse,hashlib,json
from pathlib import Path
HERE=Path(__file__).resolve().parent
sha=lambda data:hashlib.sha256(data).hexdigest()
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args()
source=json.loads((HERE/'hb-cases.jsonc').read_text());saved=json.loads((HERE/'hb-records.json').read_text());oracle=json.loads((HERE/'hb-oracle.json').read_text())
records={r['id']:r for r in saved['records']};included=[];excluded=[]
for case in source['cases']:
    if case.get('diagnostic_maxp_matrix'):
        excluded.append({'id':case['id'],'reason':'Explicit nonnormative maxp-version/length/outline factorial diagnostic; reference face/engine eligibility evidence, not a valid-font package run requirement.'})
    elif case.get('diagnostic_maxp1'):
        excluded.append({'id':case['id'],'reason':'Explicit CFF maxp1 diagnostic; OTS corrects the incorrect CFF maxp version. Original unsanitized bytes isolate reference behavior but are excluded from normative package runs.'})
    elif case['id'].startswith('cff-only-') and case['engine']=='graphite2':
        excluded.append({'id':case['id'],'reason':'Forced reference Graphite failure on an unavailable callback face. The public package selects the primary engine automatically or disables font programs; it cannot force an unavailable Graphite backend. The matching default and explicit OT cases are included.'})
    else:
        assert case['id'].startswith(('raw-bounds-','variable-')) or (case['id'].startswith('cff-only-')and case['engine']in['auto','ot']),case
        included.append(case)
assert len(included)==38 and len(excluded)==56
ots={r['font']:r for r in json.loads((HERE/'ots.json').read_text())['fonts']}
for case in included:assert ots[case['font']]['accepted'] and not ots[case['font']]['diagnostic']
engines={}
for case in included:
    if case['engine']=='ot':engines[case['id']]='OpenType'
    elif case['engine']=='graphite2':
        assert records[case['id']]['result']['graphite_face_available'] and records[case['id']]['result']['success']
        engines[case['id']]='Graphite'
    else:
        assert case['engine']=='auto' and case['id'].startswith('cff-only-') and not records[case['id']]['result']['graphite_face_available']
        explicit=case['id'][:-len('-auto')]+'-ot';assert records[case['id']]['result']==records[explicit]['result']
        data=(HERE/case['font']).read_bytes();count=int.from_bytes(data[4:6],'big');assert 12+16*count<=len(data)
        tags={data[12+16*i:16+16*i]for i in range(count)};assert not tags.intersection({b'morx',b'mort',b'kerx',b'trak'})
        engines[case['id']]='OpenType'
manifest={'schema':1,'full_cases_sha256':sha((HERE/'hb-cases.jsonc').read_bytes()),'full_records_sha256':sha((HERE/'hb-records.json').read_bytes()),'full_oracle_sha256':sha((HERE/'hb-oracle.json').read_bytes()),'package_ids':[c['id']for c in included],'expected_primary_engines':engines,'raw_only':excluded}
outputs={
    'package-cases.jsonc':json.dumps({'schema':1,'about':'Normative package gate: original28 metrics/variation plus10 ordinary CFF default/OT controls; all raw-only IDs have explicit reasons in package-selection.json.','cases':included},indent=2)+'\n',
    'package-records.json':json.dumps({'oracle':oracle,'records':[records[c['id']]for c in included]},indent=2)+'\n',
    'package-oracle.json':(HERE/'hb-oracle.json').read_text(),
    'package-selection.json':json.dumps(manifest,indent=2)+'\n',
}
for filename,text in outputs.items():
    path=HERE/filename
    if args.check:assert path.read_text()==text,path
    else:path.write_text(text)
print('38 explicit normative package cases;56 individually explained raw-only controls', 'current'if args.check else'prepared')
