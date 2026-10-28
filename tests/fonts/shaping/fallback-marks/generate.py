"""Original no-layout font exposing fallback modified combining classes."""
from pathlib import Path
import json
from fontTools.ttLib import TTFont
HERE=Path(__file__).resolve().parent
font=TTFont(HERE.parent/'arabic-fallback/wrong-alef.ttf')
points=[0x05E9,*range(0x05B0,0x05BE),0x05BF,0x05C1,0x05C2,0x05C4,0x05C5,0x05C7,0x0712,*range(0x0730,0x074B),0x0F40,0x0F71,0x0F72,0x0F74,0x0F7A,0x0F7C,0x0E01,0x0E31,0x0E38,0x0E48,0x0E81,0x0EB8,0x0EC8]
for cmap in font['cmap'].tables:
 if cmap.isUnicode():cmap.cmap.update({cp:font.getGlyphName(80+i) for i,cp in enumerate(points)})
font['head'].created=font['head'].modified=3406620153;font.recalcTimestamp=False;font.save(HERE/'marks.ttf',reorderTables=True)
texts={'Hebr':['ש'+chr(cp) for cp in [*range(0x05B0,0x05BE),0x05BF,0x05C1,0x05C2,0x05C7]]+['שִׁ','שְּׂ','שָֹ'],'Arab':['ب'+chr(cp) for cp in range(0x064B,0x0653)]+['بُّ','بِّ'],'Syrc':['ܒ'+chr(cp) for cp in range(0x0730,0x074B)]}
cases=[]
for script,words in texts.items():
 for i,text in enumerate(words):
  for direction in ['ltr','rtl']:
   for level in [0,1]:
    cases.append({'id':f'{script}-{i}-{direction}-{level}','font':'marks.ttf','text':text,'options':{'script':script,'direction':direction,'cluster_level':level,'hb_options':['--show-flags']},'expected':'oracle'})
(HERE/'mark-cases.jsonc').write_text(json.dumps({'schema':1,'about':'Valid no-GSUB/GPOS fixture isolates modified combining-class aliases for Hebrew,ArabicandSyriacfallbackmarkplacement.','cases':cases},indent=2,ensure_ascii=False)+'\n')
