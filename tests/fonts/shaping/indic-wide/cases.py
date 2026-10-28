#!/usr/bin/env python3
"""Reproduce a script-specific, two-family Indic oracle matrix."""
import argparse
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
LANGUAGES = {'Beng':'bn','Guru':'pa','Gujr':'gu','Orya':'or','Taml':'ta','Telu':'te','Knda':'kn','Mlym':'ml'}
EXTRAS = {
    'Beng': [[0x09AF,0x09BC],[0x09DC],[0x09DD],[0x09B0,0x09CD,0x09AF],[0x0987,0x09BF]],
    'Guru': [[0x0A71,0x0A15],[0x0A15,0x0A70],[0x0A15,0x0A3C,0x0A3F]],
    'Gujr': [[0x0A95,0x0ABC,0x0ACD,0x0AB7,0x0ABF]],
    'Orya': [[0x0B30,0x0B4D,0x0B15,0x0B3F],[0x0B5F,0x0B3F]],
    'Taml': [[0x0B94],[0x0B95,0x0BC6],[0x0B92,0x0BD7]],
    'Telu': [[0x0C30,0x0C4D,0x200D,0x0C15],[0x0C30,0x0C4D,0x0C15]],
    'Knda': [[0x0CB0,0x0CCD,0x200D,0x0C95],[0x0C9A,0x0CCD,0x0C9A,0x0CCD]],
    'Mlym': [[0x0D4E,0x0D15],[0x0D7B,0x0D46],[0x0D38,0x0D4D,0x0D31,0x0D4D,0x0D31,0x0D4D]],
}


def build():
    pins = json.loads((HERE/'pins.json').read_text())
    cases = []
    for family in pins['families']:
        script = family['script']
        block = family['block']
        ka,ra,ya,h,i,u,e,au = [block+n for n in (0x15,0x30,0x2F,0x4D,0x3F,0x41,0x47,0x4C)]
        texts = [[ka],[ka,i],[ka,u],[ka,e],[ka,au],[ra,h,ka],[ka,h,ya],[ka,h,ka,i],
                 [ka,h,0x200D,ka],[ka,h,0x200C,ka],[i],[h],[ra,h,0x200D,ka],
                 [ka,h,h],[ka,i,u],[ka,h,h,h,h,ka,i],[ka,0x034F,i],[ra,h,ya],
                 [0x61,0x20,ka,i],[ka,i,0x20,ra,h,ka],[ka,h,ka,h,ka],[i,ka]] + EXTRAS[script]
        for index, codepoints in enumerate(texts):
            for direction in ('ltr','rtl'):
                for level in ((0,1) if index < 8 else (0,)):
                    cases.append({'id':f"wide-{script.lower()}-{family['style'].lower()}-{index}-{direction}-c{level}",
                                  'font':family['subset']['file'], 'font_sha256':family['subset']['sha256'],
                                  'text':''.join(map(chr,codepoints)),
                                  'options':{'script':script,'language':LANGUAGES[script],'direction':direction,'cluster_level':level,'hb_options':['--show-flags']},
                                  'expected':'oracle'})
    return {'schema':1,'about':'Two-family modern Indic matrix: exact glyphs, advances, offsets, UTF-8 clusters and unsafe flags. Inputs cover reph, matras, conjuncts, controls, broken syllables and script-specific composition. Font pins list actual GSUB script tags; this does not claim complete old-spec font coverage.','cases':cases}


def main():
    parser = argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    text = json.dumps(build(),indent=2,ensure_ascii=True)+'\n'
    path=HERE/'cases.jsonc'
    if args.check:
        assert path.read_text()==text,'cases do not reproduce'
    else:
        path.write_text(text)
    print(len(build()['cases']),'cases')


if __name__=='__main__':main()
