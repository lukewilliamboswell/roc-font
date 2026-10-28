"""Independently decode the original Feat2.1 alias and derive its public runs.

No package implementation or measured Roc output supplies an expected value.
The declared flag makes feature101 an alias of feature100. Its selected value
therefore comes from100's 0/1 domain, Sill default, and valid caller override.
"""
from pathlib import Path
import argparse, hashlib, json, struct
from fontTools.ttLib import TTFont
HERE=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');a=p.parse_args()
font=TTFont(HERE/'feature-alias.ttf');data=font.reader['Feat']
assert struct.unpack_from('>IH',data)==(0x20001,2)
first=struct.unpack_from('>IHHIHH',data,12);second=struct.unpack_from('>IHHIHH',data,28)
assert first[:2]==(100,2) and second[0]==101 and second[1]==0 and second[4]&1
domain=[struct.unpack_from('>h',data,first[3]+4*i)[0] for i in range(first[1])]
assert domain==[0,1]
sill=font.reader['Sill'];assert sill[12:16]==b'ksw\0'
offset=struct.unpack_from('>H',sill,18)[0];assert struct.unpack_from('>Ih',sill,offset)==(100,1)
cases=json.loads((HERE/'feature-cases.jsonc').read_text())['cases']
records={r['id']:r for r in json.loads((HERE/'feature-records.json').read_text())['records']}
out=[]
for case in cases:
 if case['font']!='feature-alias.ttf':continue
 value=1 if case.get('language','').split('-')[0]=='ksw' else 0
 for setting in case.get('features',[]):
  if setting['id'] in [100,101] and 0<=setting['value']<=max(domain):value=setting['value']
 glyphs=[{'glyph':1,'cluster':0,'advance':[value,0],'offset':[0,0],'flags':0},
         {'glyph':2,'cluster':1,'advance':[602,0],'offset':[0,0],'flags':1}]
 if case['direction']=='rtl':glyphs.reverse()
 expected={'success':True,'abort':'NoAbort','glyphs':glyphs};record=records[case['id']]
 if expected!=record['result']:
  out.append({'id':case['id'],'reference_key':record['key'],'expected':expected,
              'reason':'Graphite2 1.3.14 ignores the normative Feat2.1 alias flag.'})
assert len(out)==16
report={'source':'https://github.com/silnrsi/graphite/blob/1.3.14/doc/GTF.asc#feat',
        'section':'FeatureDefn / FeatureFlags, bit0: alias of the previous feature',
        'interpretation':'An alias shares its target feature value, domain and language defaults; its UI label can differ.',
        'font_sha256':hashlib.sha256((HERE/'feature-alias.ttf').read_bytes()).hexdigest(),
        'independent_decode':{'version':'2.1','features':[list(first),list(second)],'target_settings':domain,'sill':{'ksw':{'100':1}}},
        'cases':out}
target=HERE/'feature-divergences.json';text=json.dumps(report,indent=2)+'\n'
if a.check:assert target.read_text()==text
else:target.write_text(text)
print('16 normative Feat2.1 alias cases independently checked')
