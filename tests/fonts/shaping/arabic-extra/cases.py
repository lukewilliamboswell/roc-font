"""Deterministic real-font Arabic/Syriac matrix using unmodified pinned fonts."""
from pathlib import Path
import json,hashlib
HERE=Path(__file__).resolve().parent
for pin in json.loads((HERE/'sources.json').read_text()):
 raw=(HERE/pin['file']).read_bytes();assert len(raw)==pin['size'] and hashlib.sha256(raw).hexdigest()==pin['sha256']
syriac=['ܐ','ܒܐ','ܐܒ','ܕܐ','ܪܐ','ܒܐܐ','ܒܐܒ','ܒܕܐ','ܒܕܒ','ܡܠܟܐ','ܫܠܡܐ','ܒܰܐ','ܒ\u200dܐ','ܒ\u200cܐ','ܒ\u034fܐ','ܒ\u200dܕ','ܒ\u200cܕ','\u070fܐܒܓ','\u070fܡܠܟܐ','\u070fܐ ܒܓ','\u070fܐܒ\u070fܓܕ','\u070f'+'ܐ'*65,'\u070f'+'ܐ'*257,'ܒ'+'ܰ'*254+'ܐ','ܒ'+'ܰ'*255+'ܐ']
arabic=['ب','بب','ببب','لاب','بلاب','لآ','لأ','لإ','لَا','لّٰا','ب\u200dب','ب\u200cب','ب\u034fب','ل\u200dا','ل\u200cا','سَلَام','ڤڤڤ','کیک','َّ','َّ','ب'+'َ'*254+'ب','ب'+'َ'*255+'ب']
cases=[]
for font in sorted(HERE.glob('*.ttf')):
 script='Arab' if 'Urdu' in font.name else 'Syrc';texts=arabic if script=='Arab' else syriac
 for i,text in enumerate(texts):
  for direction in ['rtl','ltr']:
   for level in [0,1]:
    cases.append({'id':f'{font.stem}-{i}-{direction}-{level}','font':font.name,'text':text,'options':{'script':script,'direction':direction,'hb_options':['--show-flags',f'--cluster-level={level}']},'expected':'oracle'})
 for feature in ['init=0','medi=0','fina=0','fin2=0','fin3=0','med2=0','stch=0','rlig=0','calt=0','init[2:4]=0']:
  text='ببب لاب' if script=='Arab' else '\u070fܒܐܒܕܐ'
  cases.append({'id':font.stem+'-'+feature,'font':font.name,'text':text,'options':{'script':script,'features':[feature],'hb_options':['--show-flags']},'expected':'oracle'})
 for weight in ['100','650','900']:
  for direction in ['rtl','ltr']:
   text='سلام' if script=='Arab' else '\u070fܡܠܟܐ'
   cases.append({'id':font.stem+'-weight'+weight+'-'+direction,'font':font.name,'text':text,'options':{'script':script,'direction':direction,'variations':['wght='+weight],'hb_options':['--show-flags']},'expected':'oracle'})
 for span in ['2:4','0:4','2:6']:
  text='ببب' if script=='Arab' else 'ܒܐܒ'
  cases.append({'id':font.stem+'-context'+span,'font':font.name,'text':text,'options':{'script':script,'hb_options':['--show-flags','--text-range='+span]},'expected':'oracle'})
(HERE/'extra-cases.jsonc').write_text(json.dumps({'schema':1,'about':'Unmodified pinned Noto Syriac/Eastern/Western and Nastaliq fonts: joining groups, variable positioning, real stch, controls, long255flagspans and paragraphcontext.','cases':cases},indent=2,ensure_ascii=False)+'\n')
