"""Pin, instantiate and subset two OFL Japanese families for vertical shaping."""
from pathlib import Path
import argparse,hashlib,io,json,urllib.request
from fontTools.ttLib import TTFont
from fontTools import subset
from fontTools.varLib.instancer import instantiateVariableFont
HERE=Path(__file__).resolve().parent
parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');parser.add_argument('--source-dir',type=Path,default=Path('/private/tmp'));args=parser.parse_args()
texts=['日本語。','「東京」（大阪）','縦書き、句読点。','カタカナ・ひらがな','ー…—（）［］｛｝','ABC abc 123','A\u0301B','日\u200d本','日\u200c本','日\u034f本','日本語'*25]
cases=[]
for i,source in enumerate(json.loads((HERE/'pins.json').read_text())['sources']):
 path=args.source_dir/('vertical-'+source['family']+'.ttf')
 if not path.exists():path.write_bytes(urllib.request.urlopen(source['url']).read())
 assert hashlib.sha256(path.read_bytes()).hexdigest()==source['sha256']
 font=TTFont(path,recalcTimestamp=False);font=instantiateVariableFont(font,{'wght':400},inplace=True)
 options=subset.Options();options.layout_features=['*'];options.name_IDs=['*'];options.recalc_timestamp=False
 sub=subset.Subsetter(options=options);sub.populate(text=''.join(texts));sub.subset(font)
 family='Vertical'+('Sans' if i==0 else 'Serif')+'JP'
 for record in font['name'].names:
  if record.nameID in [1,4,6,16]:record.string=family.encode(record.getEncoding())
 font['head'].created=font['head'].modified=3406620153;out=io.BytesIO();font.save(out,reorderTables=True)
 target=HERE/(family+'.ttf')
 if args.check:assert target.read_bytes()==out.getvalue(),target
 else:target.write_bytes(out.getvalue())
 for script in ['Hani','Kana','Latn']:
  for direction in ['ttb','btt']:
   for index,text in enumerate(texts):
    for feature in [None,'vert=0','vrt2=1','vkrn=1']:
     options={'script':script,'direction':direction,'hb_options':['--show-flags']}
     if feature:options['features']=[feature]
     cases.append({'id':f'{family}-{script}-{direction}-{index}-{feature or "default"}','font':family+'.ttf','text':text,'options':options,'expected':'oracle'})
out=(json.dumps({'schema':1,'about':'Two renamed static OFL JP families; vertical punctuation, marks, controls, directions and explicit features.','cases':cases},ensure_ascii=False,indent=2)+'\n').encode()
target=HERE/'real-cases.jsonc'
if args.check:assert target.read_bytes()==out,target
else:target.write_bytes(out)
