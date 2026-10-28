"""Offline provenance and observed-relation checks; no oracle/fontTools needed."""
import hashlib,json,struct
from pathlib import Path
HERE=Path(__file__).resolve().parent
sha=lambda data:hashlib.sha256(data).hexdigest()
canonical=lambda data:json.dumps(data,sort_keys=True,separators=(',',':')).encode()
for kind in ['raw','hb']:
    cases=json.loads((HERE/(kind+'-cases.jsonc')).read_text())['cases']
    saved=json.loads((HERE/(kind+'-records.json')).read_text());records=saved['records'];assert len(cases)==len(records)
    oracle=saved['oracle']if kind=='raw'else json.loads((HERE/'hb-oracle.json').read_text())
    for case,record in zip(cases,records):
        assert case['id']==record['id']
        assert record['key']==sha(canonical({'case':case,'font':sha((HERE/case['font']).read_bytes()),'oracle':oracle}))
metrics=[0,302,600,0,0,300,600,300,602,0,0]
raw=json.loads((HERE/'raw-records.json').read_text())['records']
bits_to_float=lambda b:struct.unpack('>f',struct.pack('>I',b))[0]
for record in raw:
    if not record['id'].startswith('raw-bounds-'):
        assert not record['result']['face_accepted'];continue
    metric=int(record['id'].split('-metric')[1].split('-')[0]);result=record['result']
    assert result['face_accepted'] and result['segment']
    assert bits_to_float(result['slots'][1]['position_bits'][1])==metrics[metric]
hb={r['id']:r['result']for r in json.loads((HERE/'hb-records.json').read_text())['records']}
for lsb in [-100,100]:
    for metric,want in enumerate(metrics):assert hb[f'raw-bounds-lsb{lsb}-metric{metric}']['glyphs'][1]['offset'][1]==want
for value,want in [(0,602),(0.5,702),(1,802)]:
    graphite=hb[f'variable-{value}-graphite2'];ot=hb[f'variable-{value}-ot']
    assert graphite['ot_glyph2_advance']==ot['ot_glyph2_advance']==want
    assert graphite['glyphs'][1]['advance']==[602,0] and graphite['glyphs'][1]['offset']==[0,602]
    assert ot['glyphs'][1]['advance']==[want,0] and ot['glyphs'][1]['offset']==[0,0]
ots=json.loads((HERE/'ots.json').read_text());assert len(ots['fonts'])==74
for record in ots['fonts']:
    assert (record['accepted']or record['diagnostic']) and record['sha256']==sha((HERE/record['font']).read_bytes())
for metric in [0,4,5,7,8]:
    prefix=f'cff-only-metric{metric}';assert not hb[prefix+'-graphite2']['success']
    assert hb[prefix+'-auto']==hb[prefix+'-ot'] and not hb[prefix+'-auto']['graphite_face_available']
for outline in ['cff','glyf','both','neither']:
    for version in [0x5000,0x10000]:
        for length in [6,32]:
            prefix=f'maxp-matrix-{outline}-{version}-{length}';available=version==0x10000 and length==32
            assert hb[prefix+'-auto']['graphite_face_available']==available
            assert hb[prefix+'-auto']==hb[prefix+('-graphite2'if available else'-ot')]
assert json.loads((HERE/'hb-oracle.json').read_text())['shaper_priority']==['graphite2','ot','fallback']
proof=json.loads((HERE/'oracle-proof.json').read_text())
assert proof['raw_records_sha256']==sha((HERE/'raw-records.json').read_bytes())
assert proof['hb_records_sha256']==sha((HERE/'hb-records.json').read_bytes())
assert proof['tracing_result_digest']==sha(canonical([r['result']for r in raw]))
print('56 raw/94 true HB keys;74 OTS hashes; raw bounds, variation and default maxp selection PASS')
