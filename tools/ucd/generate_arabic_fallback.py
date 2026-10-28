"""Generate Unicode Arabic presentation fallback data from the pinned shaper.

The reference includes historical PUA ligatures in addition to Unicode data;
using its exact table preserves those font-compatibility rules reproducibly.
"""
from pathlib import Path
import argparse, hashlib, json, re
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
OUTPUT=ROOT/'package/ShaperArabicFallbackData.roc'


def win_data(pin):
    raw=(HERE/pin['file']).read_bytes()
    assert len(raw)==pin['size'] and hashlib.sha256(raw).hexdigest()==pin['sha256']
    text=re.sub(r'/\*.*?\*/','',raw.decode(),flags=re.S).split('OT_TABLE_START\n',1)[1].split('OT_TABLE_END',1)[0]
    def calls(name):
        found=[]
        for m in re.finditer(r'(?<![A-Za-z_])'+name+r'\(',text):
            start=m.end();depth=1;i=start;parts=[];last=start
            while depth:
                c=text[i]
                if c=='(':depth+=1
                elif c==')':depth-=1
                elif c==',' and depth==1:parts.append(text[last:i].strip());last=i+1
                i+=1
            parts.append(text[last:i-1].strip());found.append(parts)
        return found
    glyphs=lambda value:[int(x) for x in re.findall(r'G\((\d+)\)',value)]
    offsets=lambda value:re.findall(r'OT_OFFSET\([^,]+,\s*(\w+)\)',value)
    singles={name:(glyphs(a),glyphs(b)) for name,a,b in calls('OT_SUBLOOKUP_SINGLE_SUBST_FORMAT2')}
    ligatures={name:(glyphs(a),glyphs(b)[0]) for name,a,b in calls('OT_LIGATURE')}
    sets={name:offsets(value) for name,value in calls('OT_LIGATURE_SET')}
    ligsubs={name:(glyphs(a),offsets(b)) for name,a,b in calls('OT_SUBLOOKUP_LIGATURE_SUBST_FORMAT1')}
    lookups={name:(1 if 'SINGLE' in kind else 4,8 if 'IGNORE_MARKS' in flag else 0,offsets(subs)) for name,kind,flag,subs in calls('OT_LOOKUP')}
    manifest=calls('MANIFEST_LOOKUP');ranges=[];values=[];subs=[];prepared=[];tags=[]
    for tag,lookupname in manifest:
        kind,props,names=lookups[lookupname];start=len(subs);covered=[]
        for name in names:
            coverage=len(ranges);data=len(values)
            if kind==1:
                source,target=singles[name];assert len(source)==len(target)
                values.extend(target)
            else:
                source,ligsets=ligsubs[name];assert len(source)==len(ligsets)
                values.extend([0]*(len(source)+1))
                for j,setname in enumerate(ligsets):
                    values[data+j]=len(values)
                    for ligname in sets[setname]:
                        components,target=ligatures[ligname];values.extend([target,len(components),*components])
                values[data+len(source)]=len(values)
            for j,glyph in enumerate(source):ranges.append(dict(first=glyph,last=glyph,index=j))
            covered.extend(source)
            subs.append(dict(kind=kind,coverage=coverage,coverage_len=len(source),data=data,data_len=len(source)))
        digest=lambda shift:sum(1<<bit for bit in set((g>>shift)&63 for g in covered))
        prepared.append(dict(start=start,count=len(names),mode=0 if kind==1 else 2,d0=digest(0),d1=digest(4),d2=digest(9),props=props,reverse=False))
        chars=re.findall(r"'(.)'",tag);assert len(chars)==4;tags.append(int.from_bytes(''.join(chars).encode(),'big'))
    def record(row):return '{ '+', '.join(k+': '+('True' if v is True else 'False' if v is False else str(v)) for k,v in row.items())+' }'
    out=['\twin_tags : List(U64)','\twin_tags = ['+', '.join(map(str,tags))+']','\twin_lookups : List(LayoutGsub.Lookup)','\twin_lookups = [']
    out += ['\t\t'+record(row)+',' for row in prepared];out += ['\t]','\twin_built : LayoutGsub.Built','\twin_built = {','\t\tsubtables: [']
    out += ['\t\t\t{ ..LayoutGsub.no_sub, '+record(row)[2:-2]+' },' for row in subs]
    out += ['\t\t],','\t\tranges: [']+['\t\t\t'+record(row)+',' for row in ranges]
    out += ['\t\t],','\t\tvalues: ['+', '.join(map(str,values))+'],','\t\trules: [],','\t\tsteps: 0,','\t}']
    return out

def generate():
    pin=json.loads((HERE/'arabic-fallback-pins.json').read_text())
    raw=(HERE/pin['file']).read_bytes()
    assert len(raw)==pin['size'] and hashlib.sha256(raw).hexdigest()==pin['sha256']
    text=raw.decode()
    table=text.split('shaping_table[][4] =',1)[1].split('};',1)[0]
    rows=[]
    for line in table.splitlines():
        values=re.findall(r'0x([0-9A-Fa-f]+)u',line)
        if values:rows.append(tuple(int(v,16) for v in values))
    assert len(rows)==0x06D3-0x0621+1 and all(len(r)==4 for r in rows)
    forms=[(cp,*row) for cp,row in enumerate(rows,0x0621) if any(row)]
    ligatures=[]
    for group,name in enumerate(['ligature_3_table','ligature_table','ligature_mark_table']):
        table=text.split(name+'[] =',1)[1].split('};',1)[0]
        first=None
        for line in table.splitlines():
            outer=re.match(r'\s*\{\s*0x([0-9A-Fa-f]+)u,\s*\{',line)
            if outer:first=int(outer.group(1),16)
            inner=re.match(r'\s*\{\s*\{([^}]+)\},\s*0x([0-9A-Fa-f]+)u',line)
            if inner:
                components=[int(v,16) for v in re.findall(r'0x([0-9A-Fa-f]+)u',inner.group(1))]
                assert first is not None and len(components) in (1,2)
                ligatures.append((group,first,components[0],components[1] if len(components)==2 else 0,int(inner.group(2),16)))
    notices=[]
    for source in [HERE/'complex-src/COPYING',HERE/'UNICODE-LICENSE.txt']:
        notices.extend('# '+line if line else '#' for line in source.read_text().splitlines());notices.append('')
    out=notices+['import LayoutGsub','', '## Pinned HarfBuzz14.6.0 / Unicode18 Arabic presentation fallback.',
        '## Generated by generate_arabic_fallback.py. Do not edit.',
        'ShaperArabicFallbackData :: {}.{',
        '\tforms : List({ cp : U64, init : U64, medi : U64, fina : U64, isol : U64 })',
        '\tforms = [']
    out += ['\t\t{ '+', '.join(f'{k}: {v}' for k,v in zip(['cp','init','medi','fina','isol'],row))+' },' for row in forms]
    out += ['\t]', '\tligatures : List({ group : U64, first : U64, second : U64, third : U64, substitute : U64 })','\tligatures = [']
    out += ['\t\t{ '+', '.join(f'{k}: {v}' for k,v in zip(['group','first','second','third','substitute'],row))+' },' for row in ligatures]
    out += ['\t]']+win_data(pin['win1256'])+['}']
    return '\n'.join(out)+'\n'


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--check',action='store_true');args=p.parse_args()
    expected=generate()
    if args.check:
        if OUTPUT.read_text()!=expected:raise SystemExit('Arabic presentation fallback data differs; regenerate')
    else:OUTPUT.write_text(expected)


if __name__=='__main__':main()
