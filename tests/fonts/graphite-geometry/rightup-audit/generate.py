"""Original public-format complementary sequencing controls; no engine source."""
import argparse,importlib.util,json
from pathlib import Path
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('original_sequence_builder',HERE.parent/'sequencing-audit/generate.py');base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args();cases=[]
    def emit(path,data):
        if args.check:assert path.read_bytes()==data,path
        else:path.write_bytes(data)
    for rtl in [False,True]:
        for reverse in [False,True]:
            for field,value in [(3,-100),(3,100),(5,-100),(5,100),(5,-2000)]:
                name=f'collision-rightup-field{field}-{value}-'+('reversed'if reverse else'forward')+('-rtl'if rtl else'-ltr')
                params={'order':1 if reverse else 2,'reverse_pass':reverse,'neighbor_fields':{field:value}}
                data,programs=base.make(name,params,rtl);emit(HERE/(name+'.ttf'),data)
                cases.append({'id':name,'font':'rightup-audit/'+name+'.ttf','text':'ab','direction':'rtl'if rtl else'ltr','positioning':True,'precontext':0,'collision':params,'programs':[list(p)for p in programs]})
    emit(HERE/'cases.jsonc',(json.dumps({'schema':1,'about':'Complementary RIGHTUP sign and C-H boundary observations from public API traces.','cases':cases},indent=2)+'\n').encode())
    print(len(cases),'original RIGHTUP cases reproduced'if args.check else'original RIGHTUP cases generated')
if __name__=='__main__':main()
