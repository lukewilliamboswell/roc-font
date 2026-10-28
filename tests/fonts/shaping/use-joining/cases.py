#!/usr/bin/env python3
"""Write data-only full-flags USE joining cases, never generated Roc."""
from pathlib import Path
import argparse,json
HERE=Path(__file__).resolve().parent

def cases():
 profiles={
  'Nkoo':(['UseNKoSans','UseNKoUnjoined'],'nqo',[
   'ߊ','ߊߊ','ߊߊߊ','ߒߞߏ','ߊߋߌߍߎߏ','ߞߊ߲','ߞߊ߬','ߊ߫ߊ','ߊ߬ߊ','ߊ߭ߊ','ߊ߮ߊ','ߊ߯ߊ','ߊ߰ߊ','ߊ߱ߊ','ߊ߲ߊ','ߊ߳ߊ','ߊߺߊ',
   'ߊ\u200dߊ','ߊ\u200cߊ','\u200dߊ','ߊ\u200d','\u200cߊ','ߊ\u200c','ߊ\u034fߊ','ߊ\u200c߫ߊ','ߊ\u200c\u034f߫ߊ','ߊߊ ߊߊ','߫','\u034f߫','ߊ'*65,'ߊ'*257,
  ],'ߊ','߫'),
  'Mong':(['UseMongolianSans'],'mn',[
   'ᠠ','ᠠᠠ','ᠠᠠᠠ','ᠮᠣᠩᠭᠣᠯ','ᠠᠡᠢᠣᠤᠥᠦ','ᠠ᠋','ᠠ᠌','ᠠ᠍','ᠠ᠏','ᠨ᠋ᠠ','ᠭ᠋ᠠ','ᠭ᠌ᠠ','ᠠ᠎ᠠ','ᠠ\u202fᠠ','ᠠ\u200dᠠ','ᠠ\u200cᠠ',
   '\u200dᠠ','ᠠ\u200d','\u200cᠠ','ᠠ\u200c','ᠠ\u034fᠠ','ᠠ\u200c᠋ᠠ','ᠠ\u200c\u034f᠋ᠠ','ᠠᠠ ᠠᠠ','᠋','\u034f᠋','ᠠ'*65,'ᠠ'*257,
  ],'ᠠ','᠋'),
  'Adlm':(['UseAdlamSans','UseAdlamDisplay'],'ff',[
   '𞤢','𞤢𞤢','𞤢𞤢𞤢','𞤀𞤣𞤤𞤢𞤥','𞤢𞤣𞤤𞤥','𞤢𞥄𞤢','𞤢𞥅𞤢','𞤢𞥆𞤢','𞤢𞥇𞤢','𞤢𞥈𞤢','𞤢𞥉𞤢','𞤢𞥊𞤢',
   '𞤢\u200d𞤢','𞤢\u200c𞤢','\u200d𞤢','𞤢\u200d','\u200c𞤢','𞤢\u200c','𞤢\u034f𞤢','𞤢\u200c𞥄𞤢','𞤢\u200c\u034f𞥄𞤢','𞤢𞤢 𞤢𞤢','𞥄','\u034f𞥄','𞤢'*65,'𞤢'*257,
  ],'𞤢','𞥄'),
 }
 out=[]
 for script,(families,language,texts,base,mark) in profiles.items():
  for family in families:
   def add(label,text,extra=None):
    for direction in ['ltr','rtl']:
     for level in [0,1]:
      options={'script':script,'language':language,'direction':direction,'cluster_level':level,'hb_options':['--show-flags']};options.update(extra or {})
      out.append({'id':family.lower()+'-'+label+'-'+direction+'-'+str(level),'font':family+'.ttf','text':text,'options':options,'expected':'oracle'})
   for i,text in enumerate(texts):add(str(i),text)
   for label,features in [('init-off',['init=0']),('medi-off',['medi=0']),('fina-off',['fina=0']),('isol-on',['isol=1']),('calt-off',['calt=0']),('liga-off',['liga=0']),('ranged-init',['init[1:2]=0'])]:add(label,base*3,{'features':features})
   paragraph=base*3;width=len(base.encode())
   for i in range(3):add('range-'+str(i),paragraph,{'hb_options':['--show-flags',f'--text-range={i*width}:{(i+1)*width}']})
   paragraph=base+mark+base+base;start=len((base+mark).encode());add('range-transparent-context',paragraph,{'hb_options':['--show-flags',f'--text-range={start}:{start+width}']})
 return {'schema':1,'about':'Actual USE Arabic-joining interaction in2NKo+2Adlamfamilies and1Mongolianfamily,OTfontfactsselectedexplicitly,features,contexts,CGJ/ZWNJfiltering,variants,marks,longtext,directions,clusterlevels.','cases':out}

def main():
 p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args();text=json.dumps(cases(),ensure_ascii=False,indent=2)+'\n';path=HERE/'joining-cases.jsonc'
 if args.check:assert path.read_text()==text
 else:path.write_text(text)
 print(len(cases()['cases']),'USEjoining cases')
if __name__=='__main__':main()
