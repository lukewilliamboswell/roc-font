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
    text=(SRC/'COPYING').read_text()+'\n'+(HERE/'UNICODE-LICENSE.txt').read_text()
    return '\n'.join('# '+line if line else '#' for line in text.splitlines())+'\n\n'


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
    write_extra(ROOT/'package/ShaperIndicVowelData.roc',vowel_module(),args.check)
    write_extra(ROOT/'package/ShaperUseData.roc',use_module(),args.check)
    print(f'{len(points)} code points; {len(runs)} property intervals; four exact syllable machines')

def vowel_module():
    aliases={}
    for raw in source('PropertyValueAliases.txt').read_text().splitlines():
        fields=[field.strip() for field in raw.split('#')[0].split(';')]
        if len(fields)>2 and fields[0]=='sc': aliases[fields[2]]=fields[1]
    constraints=[]
    for raw in source('harfbuzz/ms-use/IndicShapingInvalidCluster.txt').read_text().splitlines():
        words=raw.split('#')[0].split(';')[0].split()
        if words: constraints.append(tuple(int(cp,16) for cp in words))
    firsts={row[0] for row in constraints};scripts={}
    for raw in source('Scripts.txt').read_text().splitlines():
        fields=[field.strip() for field in raw.split('#')[0].split(';')]
        if len(fields)<2:continue
        bounds=fields[0].split('..');lo=int(bounds[0],16);hi=int(bounds[-1],16)
        for cp in firsts:
            if lo<=cp<=hi:scripts[cp]=int.from_bytes(aliases[fields[1]].encode(),'big')
    # Upstream ConstraintSet.add drops a longer sequence when another
    # prohibited sequence is its prefix. Preserve that exact behavior.
    rules=sorted((scripts[row[0]],row) for row in set(constraints) if not any(len(other)<len(row) and row[:len(other)]==other for other in constraints))
    notice='\n'.join('# '+line if line else '#' for line in (SRC/'ms-use/COPYING').read_text().splitlines())
    out=[header(),notice,'','## Pinned HB14.6 invalid-vowel shaping constraints, with upstream','## minimal-prefix semantics. Generated by tools/ucd/generate-complex.py.','ShaperIndicVowelData :: {}.{','\tRule : { script : U64, first : U64, second : U64, third : U64, length : U64 }','\trules : List(Rule)','\trules = [']
    for script,row in rules:
        out.append(f'\t\t{{ script: 0x{script:X}, first: 0x{row[0]:X}, second: 0x{row[1]:X}, third: 0x{row[2] if len(row)>2 else 0:X}, length: {len(row)} }},')
    out+=['\t]','\tno_rule : Rule','\tno_rule = { script: 0, first: 0, second: 0, third: 0, length: 0 }', '''
    has_script : U64 -> Bool
    has_script = |script| ShaperIndicVowelData.rules.any(|rule| rule.script == script)

    length : U64, U64, U64, U64 -> U64
    length = |script, first, second, third| {
        var $lo = 0
        var $hi = ShaperIndicVowelData.rules.len()
        while $lo < $hi {
            mid = $lo + ($hi - $lo) // 2
            rule = ShaperIndicVowelData.rules.get(mid) ?? ShaperIndicVowelData.no_rule
            less = rule.script < script or (rule.script == script and (rule.first < first or (rule.first == first and rule.second < second)))
            if less { $lo = mid + 1 } else { $hi = mid }
        }
        var $found = 0
        var $i = $lo
        var $search = True
        while $i < ShaperIndicVowelData.rules.len() and $search {
            rule = ShaperIndicVowelData.rules.get($i) ?? ShaperIndicVowelData.no_rule
            if rule.script != script or rule.first != first or rule.second != second { $search = False }
            else {
                if rule.length == 2 or rule.third == third { $found = rule.length }
                $i = $i + 1
            }
        }
        $found
    }
}
''']
    return '\n'.join(out)


def write_extra(path,generated,check):
    if not check:path.write_text(generated);return
    import os,subprocess,tempfile
    with tempfile.NamedTemporaryFile(suffix='.roc',mode='w',delete=False) as f:f.write(generated);temp=Path(f.name)
    try:
        subprocess.run([os.environ.get('ROC','roc'),'fmt',str(temp)],check=True,capture_output=True)
        assert path.read_text()==temp.read_text(),str(path)+' differs'
    finally:temp.unlink()


def use_module():
    sys.modules['packTab']=types.SimpleNamespace(languages={'c':types.SimpleNamespace(name='c')})
    sys.argv=['gen-use-table.py']+[str(source(name)) for name in ['IndicSyllabicCategory.txt','IndicPositionalCategory.txt','ArabicShaping.txt','DerivedCoreProperties.txt','UnicodeData.txt','Blocks.txt','Scripts.txt','harfbuzz/IndicSyllabicCategory-Additional.txt','harfbuzz/IndicPositionalCategory-Additional.txt']]
    original=source('harfbuzz/gen-use-table.py').read_text()
    prefix=original.split('print ("/* == Start of generated table == */")')[0]
    env={};exec(compile(prefix,'pinned gen-use-table.py','exec'),env)
    text=source('harfbuzz/hb-ot-shaper-use-machine.hh').read_text()
    cats={name:int(value) for name,value in re.findall(r'#define use_syllable_machine_ex_(\w+) (\d+)u',text)}
    values={cp:cats[name] for cp,(name,_) in env['use_data'].items() if cats[name]!=0}
    runs=[]
    for cp,category in sorted(values.items()):
        if runs and cp==runs[-1][1]+1 and category==runs[-1][2]:runs[-1]=(runs[-1][0],cp,category)
        else:runs.append((cp,cp,category))
    notice='\n'.join('# '+line if line else '#' for line in (SRC/'ms-use/COPYING').read_text().splitlines())
    out=[header(),notice,'','## Exact USE shaping categories from pinned HB14.6 generator semantics.','## Unicode18 inputs with DerivedCoreProperties17, as the reference table','## records. Generated by tools/ucd/generate-complex.py; do not edit.','ShaperUseData :: {}.{','\tranges : List({ first : U64, last : U64, category : U64 })','\tranges = [']
    for first,last,cat in runs:out.append(f'\t\t{{ first: 0x{first:X}, last: 0x{last:X}, category: {cat} }},')
    aliases={}
    for raw in source('PropertyValueAliases.txt').read_text().splitlines():
        fields=[field.strip() for field in raw.split('#')[0].split(';')]
        if len(fields)>2 and fields[0]=='sc':aliases[fields[2].upper()]=int.from_bytes(fields[1].encode(),'big')
    selector=source('harfbuzz/hb-ot-shaper.hh').read_text().split('case HB_SCRIPT_TIBETAN:')[1]
    supported=['TIBETAN']+re.findall(r'case HB_SCRIPT_(\w+):',selector)
    joining=re.findall(r'case HB_SCRIPT_(\w+):',source('harfbuzz/hb-ot-shaper-arabic-joining-list.hh').read_text())
    out+=['\t]','\tscripts : List(U64)','\tscripts = ['+', '.join('0x%X'%aliases[name] for name in supported)+']','\tjoining_scripts : List(U64)','\tjoining_scripts = ['+', '.join('0x%X'%aliases[name] for name in joining)+']', '''
    get : U64 -> U64
    get = |cp| {
        var $lo = 0
        var $hi = ShaperUseData.ranges.len()
        var $found = 0
        while $lo < $hi {
            mid = $lo + ($hi - $lo) // 2
            range = ShaperUseData.ranges.get(mid) ?? { first: 0, last: 0, category: 0 }
            if cp < range.first { $hi = mid }
            else if cp > range.last { $lo = mid + 1 }
            else { $found = range.category
                $lo = $hi }
        }
        $found
    }
}
''']
    print(f'USE: {len(values)} nondefault code points; {len(runs)} intervals')
    return '\n'.join(out)


if __name__=='__main__': main()
