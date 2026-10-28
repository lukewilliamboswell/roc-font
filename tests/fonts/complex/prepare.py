#!/usr/bin/env python3
"""Rebuild renamed OFL Devanagari subsets with pinned fontTools 4.61.1.
Run with the oracle Python; original fonts are kept outside the checkout.
"""
from pathlib import Path
import argparse, hashlib, json, os, urllib.request
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools import subset

HERE=Path(__file__).resolve().parent

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');parser.add_argument('--update',action='store_true');args=parser.parse_args()
    pins=json.loads((HERE/'pins.json').read_text())
    cache=Path(os.environ.get('ROC_FONT_COMPLEX_SOURCES', '/private/tmp/complex-font-sources'));cache.mkdir(exist_ok=True)
    for name in pins['sources']:
        path=cache/name['file']
        if not path.exists(): path.write_bytes(urllib.request.urlopen(name['url']).read())
        assert hashlib.sha256(path.read_bytes()).hexdigest()==name['sha256']
    for record in pins['subsets']:
        family=record['source_family'];target=record['file'].removesuffix('.ttf')
        f=instantiateVariableFont(TTFont(cache/(family+'.ttf')),record['source_axes'],inplace=True)
        opts=subset.Options();opts.layout_features=['*'];opts.name_IDs=['*'];opts.name_legacy=True;opts.name_languages=['*'];opts.recalc_timestamp=False
        sub=subset.Subsetter(options=opts)
        sub.populate(unicodes=list(range(0x900,0x980))+list(range(0x1CD0,0x1D00))+list(range(0xA8E0,0xA900))+[0x20,0xA0,0x200C,0x200D,0x25CC]);sub.subset(f)
        for name in f['name'].names:
            if name.nameID in [1,2,3,4,6,16,17]:
                value=target+('-Regular' if name.nameID in [3,4,6] else '') if name.nameID not in [2,17] else 'Regular'
                name.string=value.encode(name.getEncoding())
        f.recalcTimestamp=False
        import io
        output=io.BytesIO();f.save(output);data=output.getvalue()
        if args.update:
            record['sha256']=hashlib.sha256(data).hexdigest();record['size']=len(data)
        else: assert hashlib.sha256(data).hexdigest()==record['sha256'],target+' changed'
        if args.check: assert (HERE/record['file']).read_bytes()==data
        else: (HERE/record['file']).write_bytes(data)
        assert (HERE/(target+'-OFL.txt')).read_bytes()==(cache/(family+'-OFL.txt')).read_bytes()
        print(target,len(data))
    if args.update: (HERE/'pins.json').write_text(json.dumps(pins,indent=2)+'\n')

if __name__=='__main__':main()
