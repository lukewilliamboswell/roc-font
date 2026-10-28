#!/usr/bin/env python3
"""Reproduce renamed OFL USE joining-script subsets with pinned fontTools."""
from pathlib import Path
import argparse,hashlib,io,json,os,urllib.request
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools import subset
HERE=Path(__file__).resolve().parent

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
 pins=json.loads((HERE/'pins.json').read_text());cache=Path(os.environ.get('ROC_FONT_USE_JOINING_SOURCES','/private/tmp/use-joining-sources'));cache.mkdir(parents=True,exist_ok=True)
 for record in pins['sources']:
  path=cache/record['file']
  if not path.exists():path.write_bytes(urllib.request.urlopen(record['url']).read())
  assert hashlib.sha256(path.read_bytes()).hexdigest()==record['sha256'],str(path)
 for record in pins['subsets']:
  target=record['file'].removesuffix('.ttf');f=TTFont(cache/record['source_file'])
  if record['axes']:f=instantiateVariableFont(f,record['axes'],inplace=True)
  opts=subset.Options();opts.layout_features=['*'];opts.name_IDs=['*'];opts.name_legacy=True;opts.name_languages=['*'];opts.recalc_timestamp=False
  sub=subset.Subsetter(options=opts);first,last=record['range'];sub.populate(unicodes=list(range(first,last))+[0x20,0xA0,0x34F,0x200C,0x200D,0x202F,0x25CC]);sub.subset(f)
  for name in f['name'].names:
   if name.nameID in [1,2,3,4,6,16,17]:
    value=target+('-Regular'if name.nameID in[3,4,6]else'')if name.nameID not in[2,17]else'Regular';name.string=value.encode(name.getEncoding())
  f.recalcTimestamp=False;buf=io.BytesIO();f.save(buf);data=buf.getvalue();assert hashlib.sha256(data).hexdigest()==record['sha256'],target
  assert (HERE/(target+'-OFL.txt')).read_bytes()==(cache/record['source_license']).read_bytes()
  if args.check:assert (HERE/record['file']).read_bytes()==data
  else:(HERE/record['file']).write_bytes(data)
  print(target,len(data))
if __name__=='__main__':main()
