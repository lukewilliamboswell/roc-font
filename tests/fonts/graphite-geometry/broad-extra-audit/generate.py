"""Original independent broad-guard challenges; public formats/API only."""
import argparse,importlib.util,json
from pathlib import Path
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('original_broad_builder',HERE.parent/'broad-audit/generate.py');base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base)

def recipes():
    for margin,distances in [(50,[1601,1649,1650,1651]),(500,[1601,2099,2100,2101])]:
        for d in distances:yield {'name':f'margin{margin}-distance{d}','params':{'pass_flags':1,'flags_a':1,'flags_b':0,'distance':d,'margin':margin},'boxes':{},'expected_mode':'full'if d<=1600+margin else'missed'}
    for offset in [2000,-2000]:yield {'name':f'both-box-offset{offset}','params':{'pass_flags':1,'flags_a':1,'flags_b':0,'distance':100},'boxes':{'1':[offset,offset,offset+300,offset+600],'2':[offset,offset,offset+300,offset+600]},'expected_mode':'missed'}
    for d in [-1600,-1599,1100,1101]:yield {'name':f'fractional-prior-distance{d}','params':{'pass_flags':1,'flags_a':0,'flags_b':1,'margin':50,'second_distance':d,'second_bounds':[-1000,-1000,1000,1000]},'boxes':{},'expected_mode':'full'}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args();cases=[]
    def emit(path,data):
        if args.check:assert path.read_bytes()==data,path
        else:path.write_bytes(data)
    for recipe in recipes():
        name='collision-broad-extra-'+recipe['name'];data,programs=base.make(name,recipe);emit(HERE/(name+'.ttf'),data)
        cases.append({'id':name,'font':'broad-extra-audit/'+name+'.ttf','text':'ab','direction':'ltr','positioning':True,'precontext':0,'recipe':recipe,'programs':[list(p)for p in programs]})
    emit(HERE/'cases.jsonc',(json.dumps({'schema':1,'about':'Independent margins, translated bounds and fractional-prior probes; no general predicate inferred.','cases':cases},indent=2)+'\n').encode())
    print(len(cases),'independent broad cases reproduced'if args.check else'independent broad cases generated')
if __name__=='__main__':main()
