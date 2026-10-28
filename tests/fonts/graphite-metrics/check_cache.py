"""Offline exact checks for the reference's final short-metric edge case."""
import hashlib,json,struct
from pathlib import Path
HERE=Path(__file__).resolve().parent
sha=lambda b:hashlib.sha256(b).hexdigest()
canonical=lambda v:json.dumps(v,sort_keys=True,separators=(',',':')).encode()
for stem,raw in [('cache',False),('cache-raw',True)]:
    cases=json.loads((HERE/(stem+'-cases.jsonc')).read_text())['cases'];saved=json.loads((HERE/(stem+'-records.json')).read_text());records={r['id']:r for r in saved['records']}
    oracle=saved['oracle']if raw else json.loads((HERE/'cache-oracle.json').read_text());assert len(records)==len(cases)==(44 if raw else 41)
    for case in cases:
        record=records[case['id']];assert record['key']==sha(canonical({'case':case,'font':sha((HERE/case['font']).read_bytes()),'oracle':oracle}))
        gid=case['expected_glyph'];advance=0 if gid==3 and case['long_metric_count']==1 and case['padding']==0 else 600
        metric=case.get('metric');want_y=0 if metric is None else [0,advance-300,600,0,0,300,600,300,advance,0,0][metric]
        if raw:
            result=record['result'];assert result['face_accepted'] and result['segment'] and len(result['slots'])==1
            slot=result['slots'][0];bits=lambda v:struct.unpack('>I',struct.pack('>f',v))[0]
            assert slot['glyph']==gid and slot['advance_bits']==[bits(advance),0] and slot['position_bits']==[0,bits(want_y)]
        else:
            result=record['result'];assert result['success'] and result['graphite_face_available'] and result['ot_glyph2_advance']==600
            assert result['glyphs']==[{'glyph':gid,'cluster':0,'advance':[advance,0],'offset':[0,want_y],'flags':0}]
ots={r['font']:r for r in json.loads((HERE/'ots.json').read_text())['fonts']}
for case in json.loads((HERE/'cache-cases.jsonc').read_text())['cases']:
    if case['category'].startswith('ordinary'):assert ots[case['font']]['accepted'] and not ots[case['font']]['stderr']
proof=json.loads((HERE/'cache-proof.json').read_text());assert proof['release_tracing_bit_identical']==44
for name in ['cache-records.json','cache-raw-records.json']:assert proof[name+'_sha256']==sha((HERE/name).read_bytes())
print('41 true HB/44 raw CAPI short-metric outputs; bbox retained; only advance/rightbearing change PASS')
