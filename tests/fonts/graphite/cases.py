"""Build deterministic Graphite adapter cases from licensed pinned inputs."""
from pathlib import Path
import argparse,json,struct
from fontTools.ttLib import TTFont
HERE=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args();cases=[]
def add(id,font,text,**options):cases.append({'id':id,'font':font,'text':text,**options})
for name in ['stack-1023','stack-1024','stack-unbalanced','replace','version','set-advance','divide-zero','mutate-then-divide-zero','copy-after-change','metric-after-change','trunc8','trunc16']:
 for text in ['','a','b','ab','ba','aaa']:
  for direction in ['ltr','rtl','ttb','btt']:add(f'{name}/{text or "empty"}/{direction}',name+'.ttf',text,direction=direction,script='Latn')
for value in [0,1,-1]:
 for text in ['a','b','ab','ba']:
  add(f'feature-abort/{value}/{text}','divide-feature.ttf',text,script='Latn',features=[{'id':100,'value':value}])
families=[
 ('charis','Charis5_eursub.ttf','Latn',['a','office','fi ffi','a\u0301','A\u0308\u0301','a\u0323\u0301','Tiếng Việt','Ǽȅǖ','α\u0313\u0301','a\u200cb','a\u200db','a\u034fb','a\u2060b','a\u00a0b','a\ufe0fb','😀','a'*65,'a\u0301'*129],'office a\u0301'),
 ('padauk','Padauk.ttf','Mymr',['က','က္က','မြန်မာ','င်္က','ေက','ကေ','က\u1031\u1031','က\u103a\u1039က','က\u103b\u103d\u103e','ေ','ြ','၁၂၃','က\u200cခ','က\u200dခ','က\u034fခ','က'*65,'ေ'*65+'က','မြန်မာ'*52],'မြန်မာ'),
 ('scheherazade','Scheherazadegr.ttf','Arab',['ب','سلام','بب','بَت','اللَّه','الحمد لله','س\u200dلام','س\u200cلام','ـ','ﷲ','ا\u064e\u0651','ب\u061cت','ب\u034fت','\u0610ب\u0651\u064e','بَجْدُ','بسم الله الرحمن الرحيم','نستعليق','ب'*65,'ب\u064e'*129],'بسم الله الرحمن الرحيم'),
 ('awami','AwamiNastaliq-Regular.ttf','Arab',['ب','سلام','بب','بَت','اللَّه','الحمد لله','س\u200dلام','س\u200cلام','ـ','ﷲ','ا\u064e\u0651','ب\u061cت','ب\u034fت','\u0610ب\u0651\u064e','بَجْدُ','بسم الله الرحمن الرحيم','نستعليق','ب'*65,'ب\u064e'*129],'نستعليق بَجْدُ'),
]
for family,name,script,texts,base in families:
 font=TTFont(HERE/name);assert not any(t in font for t in ['morx','mort','kerx','trak'])
 for i,text in enumerate(['']+texts):
  for direction in ['ltr','rtl']:
   for level in [0,1]:add(f'{family}/text-{i}/{direction}/clusters-{level}',name,text,script=script,direction=direction,cluster_level=level)
 for direction in ['ttb','btt']:add(f'{family}/horizontal-program-in-{direction}',name,base,script=script,direction=direction)
 for start,end in [[0,0],[0,1],[1,2**64-1],[2,9],[9,2],[2**64-1,2**64-1]]:
  add(f'{family}/range-{start}-{end}',name,base,script=script,direction='rtl' if script=='Arab' else 'ltr',range=[start,end])
 if 'Sill' in font:
  raw=font.reader['Sill'];count=int.from_bytes(raw[4:6],'big')
  for i in range(count):
   lang=raw[12+8*i:16+8*i].rstrip(b'\0').decode('ascii')
   for suffix in ['', '-ZZ']:add(f'{family}/language-{lang}{suffix}',name,base,script=script,direction='rtl' if script=='Arab' else 'ltr',language=lang+suffix)
 raw=font.reader['Feat'];version=int.from_bytes(raw[:4],'big');count=int.from_bytes(raw[4:6],'big');width=16 if version>=0x20000 else 12
 for i in range(count):
  at=12+i*width
  fid=int.from_bytes(raw[at:at+(4 if width==16 else 2)],'big');n=int.from_bytes(raw[at+(4 if width==16 else 2):at+(6 if width==16 else 4)],'big');off=int.from_bytes(raw[at+(8 if width==16 else 4):at+(12 if width==16 else 8)],'big')
  values=sorted({int.from_bytes(raw[off+4*j:off+4*j+2],'big',signed=True) for j in range(n)})
  for value in values:add(f'{family}/feature-{fid}-{value}',name,base,script=script,direction='rtl' if script=='Arab' else 'ltr',features=[{'id':fid,'value':value}])
 # These fonts contain no Apple layout tables, so HB's explicit 'ot'
 # matches the package's requested OpenType-only control without hybrids.
 add(f'{family}/opentype-only',name,base,script=script,direction='rtl' if script=='Arab' else 'ltr',engine='ot')
assert len({c['id'] for c in cases})==len(cases)
out=json.dumps({'cases':cases},indent=2,ensure_ascii=False)+'\n';target=HERE/'shape-cases.jsonc'
if args.check:assert target.read_text()==out
else:target.write_text(out)
print(f'{len(cases)} Graphite adapter cases current')
