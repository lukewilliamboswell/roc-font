"""Independent Glat structure oracle for the no-octabox controls."""
from pathlib import Path
import argparse,hashlib,json
HERE=Path(__file__).resolve().parent
def sha(data):return hashlib.sha256(data).hexdigest()
def canonical(value):return json.dumps(value,sort_keys=True,separators=(',',':')).encode()

def main():
 p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args()
 cases=json.loads((HERE/'collision-box-cases.jsonc').read_text())['cases'];path=HERE/'collision-box-fonttools.json'
 if args.check:
  saved=json.loads(path.read_text());records={r['id']:r for r in saved['records']}
  for case in cases:
   assert records[case['id']]['key']==sha(canonical({'case':case,'font':sha((HERE/case['font']).read_bytes()),'oracle':saved['oracle']}))
  print(len(cases),'cached fontTools Glat keys current');return
 import fontTools
 from fontTools.ttLib import TTFont
 assert fontTools.__version__=='4.61.1'
 oracle={'engine':'fontTools','version':fontTools.__version__,'api':'TTFont Glat decoded attributes and hasOctaboxes','extractor':1};records=[]
 for case in cases:
  with TTFont(HERE/case['font'])as font:
   glat=font['Glat'];result={'version':glat.version,'has_octaboxes':bool(getattr(glat,'hasOctaboxes',False)),'glyphs':[{'glyph':i,'attributes':sorted(glat.attributes[name].items())}for i,name in enumerate(font.getGlyphOrder())]}
  records.append({'id':case['id'],'key':sha(canonical({'case':case,'font':sha((HERE/case['font']).read_bytes()),'oracle':oracle})),'result':result})
 path.write_text(json.dumps({'oracle':oracle,'records':records},indent=2)+'\n');print(len(records),'independent fontTools Glat records cached')

if __name__=='__main__':main()
