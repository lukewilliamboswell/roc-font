"""Record real HB successes and explicit reference failures; never invent runs."""
from pathlib import Path
import hashlib,json,subprocess
import fontTools,uharfbuzz as hb
HERE=Path(__file__).resolve().parent

def shape(path,text,direction):
 font=hb.Font(hb.Face(path.read_bytes()));hb.ot_font_set_funcs(font)
 b=hb.Buffer();b.add_str(text);b.direction=direction;b.script='Latn';b.language='en'
 try:hb.shape(font,b)
 except MemoryError:return {'reference_failure':'MemoryError: HarfBuzz marked the buffer unsuccessful (resource bound)'}
 offsets=[];offset=0
 for char in text:offsets.append(offset);offset+=len(char.encode())
 return {'glyphs':[i.codepoint for i in b.glyph_infos], 'advances':[[p.x_advance,p.y_advance] for p in b.glyph_positions], 'offsets':[[p.x_offset,p.y_offset] for p in b.glyph_positions], 'clusters':[offsets[i.cluster] for i in b.glyph_infos]}

def main():
 cases=[]
 for path in sorted(HERE.glob('*.ttf')):
  if path.stem.startswith(('context-','chain-')):texts=['ab','a\u0301b','a\u200db','a\u200cb','a\u0301\u0301b']
  elif 'order' in path.stem or path.stem in ['shift-attach','attach-shift']:texts=['a\u0301']
  else:texts=['a']
  for text in texts:
   for direction in ['ltr','rtl']:
    c={'id':f'{path.stem}-{len(cases)}','font':path.name,'text':text,'direction':direction,'depth':64,'operations':4096}
    c['font_sha256']=hashlib.sha256(path.read_bytes()).hexdigest();c['oracle']=shape(path,text,direction);cases.append(c)
 for name in ['many-8','ignored-8192','nested-order','cycle-8192','fanout-8192']:
  for depth in [0,1,2,3]:
   cases.append({'id':f'{name}-depth{depth}','font':name+'.ttf','font_sha256':hashlib.sha256((HERE/(name+'.ttf')).read_bytes()).hexdigest(),'text':'a\u0301' if name=='nested-order' else 'a','direction':'ltr','depth':depth,'operations':4096,'contract_only':True})
 result={'harfbuzz':hb.version_string(),'uharfbuzz':hb.__version__,'fontTools':fontTools.__version__,'cases':cases}
 (HERE/'cases.jsonc').write_text('// Generated with oracle.py. Resource failures are not glyph oracles.\n'+json.dumps(result,ensure_ascii=False,indent=2)+'\n')
 print(len(cases),'cases;',sum('reference_failure' in c.get('oracle',{}) for c in cases),'honest reference failures')
if __name__=='__main__':main()
