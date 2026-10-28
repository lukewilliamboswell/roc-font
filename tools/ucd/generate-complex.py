#!/usr/bin/env python3
"""Reproduce HarfBuzz 14.6's Indic/Khmer/Myanmar shaping properties and
Ragel machines as flat scalar Roc tables. These are shaping properties,
not script segmentation. Original generators and machines are vendored
with their notices in complex-src; every source/input is hash pinned.
"""
from pathlib import Path
import argparse, hashlib, json, re, sys, types, urllib.request

HERE=Path(__file__).resolve().parent
ROOT=HERE.parent.parent
PINS=json.loads((HERE/'complex-pins.json').read_text())
SRC=HERE/'complex-src'
CACHE=HERE/'.cache/complex'


def source(name):
    vendor=name.startswith('harfbuzz/')
    path=(SRC/name.removeprefix('harfbuzz/')) if vendor else CACHE/name
    pin=PINS['files'][name]
    if not path.exists():
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_bytes(urllib.request.urlopen(pin['url']).read())
    data=path.read_bytes()
    assert len(data)==pin['size'] and hashlib.sha256(data).hexdigest()==pin['sha256'],name
    return path


def header():
    return '\n'.join('# '+line if line else '#' for line in (SRC/'COPYING').read_text().splitlines())+'\n\n'


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    for name in PINS['files']: source(name)
    # Run the unchanged semantic portion of the pinned upstream generator.
    # packTab is only needed for C compression after this boundary.
    sys.modules['packTab']=types.SimpleNamespace(languages={'c':types.SimpleNamespace(name='c')})
    sys.argv=['gen-indic-table.py']+[str(source(n)) for n in ['IndicSyllabicCategory.txt','IndicPositionalCategory.txt','Blocks.txt']]
    original=source('harfbuzz/gen-indic-table.py').read_text()
    prefix=original.split('print ("/* == Start of generated table == */")')[0]
    env={};exec(compile(prefix,'pinned gen-indic-table.py','exec'),env)
    data=env['indic_data']|env['singles']
    cats={}
    for model in ['indic','khmer','myanmar']:
        text=source('harfbuzz/hb-ot-shaper-'+model+'-machine.hh').read_text()
        for name,value in re.findall(r'#define '+model+r'_syllable_machine_ex_(\w+) (\d+)u',text):
            if name in cats: assert cats[name]==int(value)
            cats[name]=int(value)
    positions=['START','RA_TO_BECOME_REPH','PRE_M','PRE_C','BASE_C','AFTER_MAIN','ABOVE_C','BEFORE_SUB','BELOW_C','AFTER_SUB','BEFORE_POST','POST_C','AFTER_POST','SMVD','END']
    points={cp:(cats[cat],positions.index(pos)) for cp,(cat,pos,_) in data.items()}
    # Sparse interval runs: absent scalars retain upstream X/END default.
    runs=[]
    for cp,value in sorted(points.items()):
        if runs and cp==runs[-1][1]+1 and value==runs[-1][2]: runs[-1]=(runs[-1][0],cp,value)
        else: runs.append((cp,cp,value))
    out=[header(),'## Generated shaping categories and exact Ragel transition tables.\n## Run tools/ucd/generate-complex.py; do not edit.\nShaperIndicData :: {}.{', '\tProperty : { category : U64, position : U64 }', '\tproperties : List({ first : U64, last : U64, category : U64, position : U64 })','\tproperties = [']
    out += [f'\t\t{{ first: 0x{a:X}, last: 0x{b:X}, category: {c}, position: {p} }},' for a,b,(c,p) in runs]
    out += ['\t]', '\tget : U64 -> Property', '\tget = |cp| {', '\t\tvar $lo = 0', '\t\tvar $hi = ShaperIndicData.properties.len()', '\t\tvar $value = { category: 0, position: 14 }', '\t\twhile $lo < $hi {', '\t\t\tmid = $lo + ($hi - $lo) // 2', '\t\t\tr = ShaperIndicData.properties.get(mid) ?? { first: 0, last: 0, category: 0, position: 14 }', '\t\t\tif cp < r.first { $hi = mid }', '\t\t\telse if cp > r.last { $lo = mid + 1 }', '\t\t\telse {\n\t\t\t\t$value = { category: r.category, position: r.position }\n\t\t\t\t$lo = $hi\n\t\t\t}', '\t\t}', '\t\t$value', '\t}']
    for model in ['indic','khmer','myanmar','use']:
        text=source('harfbuzz/hb-ot-shaper-'+model+'-machine.hh').read_text()
        for name,raw in re.findall(r'static const [^\n]+ _'+model+r'_syllable_machine_(\w+)\[\] = \{(.*?)\};',text,re.S):
            numbers=[int(s) for s in re.findall(r'\d+',raw)]
            out += [f'\t{model}_{name} : List(U64)',f'\t{model}_{name} = [']
            for i in range(0,len(numbers),24): out.append('\t\t'+', '.join(map(str,numbers[i:i+24]))+',')
            out.append('\t]')
        start=re.search(model+r'_syllable_machine_start = (\d+)',text).group(1)
        out += [f'\t{model}_start : U64',f'\t{model}_start = {start}']
    out.append('}\n')
    output=ROOT/'package/ShaperIndicData.roc';generated='\n'.join(out)
    # Formatting is deterministic and performed by caller with latest Roc.
    if args.check:
        import subprocess,tempfile
        with tempfile.NamedTemporaryFile(suffix='.roc',mode='w',delete=False) as f: f.write(generated);temp=Path(f.name)
        try:
            import os
            subprocess.run([os.environ.get('ROC','roc'),'fmt',str(temp)],check=True,capture_output=True)
            assert output.read_text()==temp.read_text(),'generated module differs'
        finally: temp.unlink()
    else: output.write_text(generated)
    print(f'{len(points)} code points; {len(runs)} property intervals; four exact syllable machines')

if __name__=='__main__': main()
