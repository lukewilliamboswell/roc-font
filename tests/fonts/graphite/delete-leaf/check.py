"""Offline DELETE current-reference and full-run oracle checks."""
from pathlib import Path
import hashlib,json,subprocess,sys
HERE=Path(__file__).resolve().parent
subprocess.run([sys.executable,str(HERE/'generate.py'),'--check'],check=True)
subprocess.run([sys.executable,str(HERE.parent/'record_shapes.py'),'--check','--font-root',str(HERE),'--cases',str(HERE/'cases.jsonc'),'--output',str(HERE/'hb-records.json'),'--oracle',str(HERE/'hb-oracle.json')],check=True)
rows={r['id']:r['result']for r in json.loads((HERE/'hb-records.json').read_text())['records']}
for fact in json.loads((HERE/'facts.json').read_text()):
 for level in [0,1]:
  result=rows[fact['font'][:-4]+f'/clusters-{level}'];assert result['success'];survivor=[g for g in result['glyphs']if g['glyph']==2];assert len(survivor)==1 and survivor[0]['offset'][1]==fact['expected_y']
for direction in ['ltr','rtl']:
 for kind,advance in [('delete-da',5080),('delete-ad',603)]:
  result=rows[f'collision-deleted-leaf-{kind}-{direction}.ttf/clusters-1'];assert sum(g['advance'][0]for g in result['glyphs'])==advance+604
for entry in json.loads((HERE/'ots.json').read_text())['fonts']:assert hashlib.sha256((HERE/entry['font']).read_bytes()).hexdigest()==entry['sha256']
raw=json.loads((HERE/'star-raw-records.json').read_text())['records']
for r in raw:
 family={n['glyph']:n for n in r['result']['reachable_family']}
 if 'delete-d-'in r['id']:assert family[1]['links_glyph'][2]==2 and not family[2]['active']
 else:assert family[3]['links_glyph'][1]==2 and 1 not in family
assert rows['next-delete/a/ltr/clusters-1']=={'success':False,'abort':'ProgramAbort','glyphs':[]}
assert rows['next-delete/ab/ltr/clusters-1']['success'] and [g['glyph']for g in rows['next-delete/ab/ltr/clusters-1']['glyphs']]==[1]
print('100 full-run DELETE records and13 original controls current')
