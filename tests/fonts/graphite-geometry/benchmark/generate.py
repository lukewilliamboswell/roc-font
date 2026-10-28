"""Original UPL allocation/timing controls for attachment and phase3 parts."""
import argparse
import importlib.util
import json
from pathlib import Path
import sys

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent))
import generate as geometry
spec=importlib.util.spec_from_file_location('geometry_parts',HERE.parent/'kern-parts/generate.py')
parts=importlib.util.module_from_spec(spec);spec.loader.exec_module(parts)

def main():
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args()
    attachment=geometry.attach()+geometry.set_attr(3,80)+geometry.set_attr(8,0)+geometry.set_attr(0,0)
    made={
        'attachment.ttf':geometry.font('geometry-bench-attachment',attachment,True,False,2,False),
        'kerning-parts.ttf':parts.make('geometry-bench-kerning-parts',True,{1:[parts.PARTS['full'][0]]*4,2:[parts.PARTS['full'][0]]*4})[0],
    }
    for name,data in made.items():
        path=HERE/name
        if args.check:assert path.read_bytes()==data,path
        else:path.write_bytes(data)
    cases=[]
    for name,direction,script,sizes in [('attachment','ltr','Latn',[8,32,128]),('kerning-parts','rtl','Arab',[4,8,16])]:
        for size in sizes:
            cases.append({'id':f'geometry-benchmark-{name}-{size}','font':f'benchmark/{name}.ttf','text':'ab'*size,'direction':direction,'script':script,'copies':size})
    text=json.dumps({'schema':1,'cases':cases},indent=2)+'\n';path=HERE/'cases.jsonc'
    if args.check:assert path.read_text()==text
    else:path.write_text(text)
    print(f'{len(made)} original benchmark fonts and {len(cases)} scaling cases reproduce')

if __name__=='__main__':main()
