"""Author the finite Myanmar conformance matrix; never generate Roc source."""
from pathlib import Path
import json
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
texts=[
'', 'မြန်မာ','မင်္ဂလာပါ','ကျွန်တော်','ရန်ကုန်','ကြိုးစား','ဉာဏ်','အင်္ဂလိပ်','သင်္ချာ','ပစ္စည်း','ခြင်္သေ့','မြို့','ကောင်းကင်','လွှတ်တော်',
'င်္က','င်္ကျ','င်္ကြ','င်္ကေ','င်္ကြေ','င်္ကိ','င်္ကီ','င်္ကွ','င်္ကာ','င်္ကိံ','င်္ကွှ',
'က္က','က္ခ','က္တ','န္တ','န္ဒ','တ္ထ','ပ္ပ','မ္မ','က်','တ်','န်',
'ကေ','ကော','ကော်','ကေ့','ကီး','ကီ','ကု','ကူ','ကံ','ကိံ','ကုံ','ကွှေ','ကြွှေ','ကျွှေ',
'ကျ','ကြ','ကွ','ကှ','ကျွ','ကြွ','ကွှ','ကျွှ','ကြွှ','ကျှ',
'ကေ\ufe00ေ\ufe01','ကေေ','ကေ\ufe00ေ\ufe00ေ\ufe01',
'ေ','ိ','ု','့','္','်','ျ','ြ','ွ','ှ','ိံ','င်္',
'က္\u200cက','က္\u200dက','င်္\u200dက','က\u200dေ','က\u200cေ','ေ\u200d','က\u200c','က\u200d','က\u034fိ','က\u200bေ',
'◌ေ','◌ြ','◌္က','abc မြန်မာ','၁၂၃၄၅','() မြန်မာ ၁၂',
'ၵႂၢမ်းတႆး','မႂ်ႇသုင်','တႆး','ႁႂ်ႈ','လွင်ႈ','ဘာသာမန်','မန်','တ္ၚဲ','သ္ၚိ','ကၞုဲ','ၚၞုဟ်','ကညီကျိာ်','ပှၤ','လီၤ','တၢ်','က့ၤ','သ့ၣ်',
'ဦ','ဦ','ꩠၞꩡ','က\uaa7b\uaa7c\uaa7d','\U000116d0\U000116d1',
'က'*20,'ကေ'*20,'က'+'ေ'*256,'က'+('ေ\ufe00'*128),
]
texts.append("ေ"+"a"*14+"ေ")
cases=[]
def add(id,font,text,**options):
 cases.append(dict(id=id,font=font,text=text,options=dict(script='Mymr',language='my',hb_options=['--show-flags'],**options),expected='oracle'))
for family,font in [('sans','NotoSansMyanmar-Regular.ttf'),('serif','NotoSerifMyanmar-Regular.ttf')]:
 for i,text in enumerate(texts):
  for direction in ['ltr','rtl']:add(f'{family}-text-{i:03}-{direction}',font,text,direction=direction)
 for feature in ['rphf','pref','blwf','pstf','pres','abvs','blws','psts','ccmp','locl','calt','liga','mark','mkmk']:
  for text_index,text in enumerate(['င်္ကြွှေိံ','မြန်မာ']):
   add(f'{family}-disable-{feature}-{text_index}',font,text,direction='ltr',features=[f'{feature}=0'])
 for language in ['shn','mnw','ksw','pwo','kht','en']:
  cases.append(dict(id=f'{family}-language-{language}',font=font,text='ၵႂၢမ်းတႆး ဘာသာမန် ကညီကျိာ်',options=dict(script='Mymr',language=language,direction='ltr',hb_options=['--show-flags']),expected='oracle'))
for family,font in [('sans','NotoSansMyanmar-Regular.ttf'),('serif','NotoSerifMyanmar-Regular.ttf')]:
 for i,text in enumerate(['င်္က','ကြေ','ကိံ','ေ','ြ','က္က','က\u200cေ','က\u200dေ','မြန်မာ','ကေ\ufe00ေ\ufe01','က'+'ေ'*256,'abc မြန်မာ']):
  for direction in ['ltr','rtl']:add(f'{family}-characters-{i}-{direction}',font,text,direction=direction,cluster_level=1)
 for i,feature in enumerate(['rphf[0:3]=0','pref[1:3]=0','blwf[2:5]=0','pstf[0:1]=0']):
  add(f'{family}-range-{i}',font,'င်္ကြေ မြန်မာ',direction='ltr',features=[feature])
for font in ['modern.ttf','legacy.ttf','no-circle.ttf']:
 stem=font.removesuffix('.ttf')
 for i,text in enumerate(['က','ကေ','ကြေ','င်္ကြေ','ြ','ေ','က္က','က\u200cေ','က\u200dေ']):
  for direction in ['ltr','rtl']:add(f'{stem}-{i}-{direction}',font,text,direction=direction)
 for feature in ['rphf','pref','blwf','pstf','pres','abvs','blws','psts']:
  add(f'{stem}-disable-{feature}',font,'ကေ',direction='ltr',features=[f'{feature}=0'])
for count in [8,64,256]:add(f'sort-{count}',f'sort-{count}.ttf','က'+'ေ'*count,direction='ltr')
add('sort-32-window','sort-32.ttf','က'+'ေ'*31,direction='ltr')
for font in ['modern.ttf','no-circle.ttf']:
 for direction in ['ltr','rtl']:add(font.removesuffix('.ttf')+'-broken-serial-wrap-'+direction,font,'ေ'+'a'*14+'ေ',direction=direction)
(HERE/'myanmar.jsonc').write_text(json.dumps(dict(schema=1,about='Myanmar modern mym2 shaping in two unmodified real families: kinzi, stacks, medials, vowels, variation selectors, broken clusters, language features, joins, directions, long syllables and unsafe flags.',cases=cases),ensure_ascii=False,indent=2)+'\n')
print(len(cases),'Myanmar cases')
