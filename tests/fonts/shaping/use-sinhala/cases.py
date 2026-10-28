#!/usr/bin/env python3
"""Reproduce a two-family Sinhala USE oracle matrix, including invalid vowels."""
import argparse
import json
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]


def build():
    texts=['', 'සිංහල','ශ්‍රී ලංකාව','ආයුබෝවන්','කර්ම','ප්‍රශ්නය','ඥානය',
           'ක','කා','කැ','කෑ','කි','කී','කු','කූ','කෘ','කෙ','කේ','කෛ','කො','කෝ','කෞ',
           'උ','ඌ','ඍ','ඎ','ඏ','ඐ','එ','ඒ','ඓ','ඔ','ඕ','ඖ','ෲ','ෳ',
           'ක්ක','ක්ඛ','න්ද','න්ද්‍ර','ත්‍ර','ර්ක','ර්\u200dක','ක්\u200dය','ක්\u200cය',
           'ක\u200dෙ','ක\u200cෙ','ක\u034fි','ෙ','ි','්','ෙක','◌ෙ','◌්ක',
           'කෙ\ufe00ෙ\ufe01','කෙෙ','ක'+('ෙ'*65),'ක'+('ෙ'*127),'ක'+('ෙ'*257),
           'ක'+('ෙ\ufe00'*128),'abc සිංහල','(සිංහල) 123']
    rules=[]
    for line in (ROOT/'tools/ucd/complex-src/ms-use/IndicShapingInvalidCluster.txt').read_text().splitlines():
        prefix=line.split(';')[0].split('#')[0].strip()
        if not prefix:
            continue
        scalars=[int(x,16) for x in prefix.split()]
        if 0xD80 <= scalars[0] <= 0xDFF:
            rules.append(''.join(map(chr,scalars)))
    texts+=rules
    cases=[]
    pins=json.loads((HERE/'pins.json').read_text())
    for family in pins['families']:
        for i,text in enumerate(texts):
            for direction in ('ltr','rtl'):
                for level in ((0,1) if i%4==0 else (0,)):
                    cases.append({'id':f"sinh-{family['style'].lower()}-{i}-{direction}-c{level}",
                                  'font':family['subset']['file'],'font_sha256':family['subset']['sha256'],'text':text,
                                  'options':{'script':'Sinh','language':'si','direction':direction,'cluster_level':level,'hb_options':['--show-flags']},'expected':'oracle'})
        for tag in ('rphf','pref','pres','abvs','blws','psts','haln','ccmp','locl','rlig','mark','mkmk'):
            cases.append({'id':f"sinh-{family['style'].lower()}-disable-{tag}",'font':family['subset']['file'],
                          'font_sha256':family['subset']['sha256'],'text':'ශ්‍රී ලංකාව ප්‍රශ්නය',
                          'options':{'script':'Sinh','language':'si','features':[tag+'=0'],'hb_options':['--show-flags']},'expected':'oracle'})
    return {'schema':1,'about':'Exact Sinhala USE shaping in two renamed static real Noto families: split vowels, reph, conjuncts, controls, dotted circles, long64-bounded callbacks, feature choices and all pinned Sinhala invalid-vowel rules.','cases':cases}


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--check',action='store_true');args=ap.parse_args()
    data=build();text=json.dumps(data,indent=2,ensure_ascii=True)+'\n';path=HERE/'sinhala-cases.jsonc'
    if args.check:assert path.read_text()==text
    else:path.write_text(text)
    print(len(data['cases']),'Sinhala cases')


if __name__=='__main__':main()
