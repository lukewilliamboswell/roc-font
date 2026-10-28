"""Original bounded attachment propagation and cursive rerooting fixtures."""
from pathlib import Path
import json
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
HERE=Path(__file__).resolve().parent
for mode in ['mark-chain','cursive-chain','cursive-reroot']:
 names=['.notdef','space','a','acute'];fb=FontBuilder(1000,isTTF=True);fb.setupGlyphOrder(names);fb.setupCharacterMap({32:'space',97:'a',0x0301:'acute'})
 glyphs={}
 for name in names:
  p=TTGlyphPen(None)
  if name!='space':p.moveTo((0,0));p.lineTo((100,0));p.lineTo((100,300));p.lineTo((0,300));p.closePath()
  glyphs[name]=p.glyph()
 fb.setupGlyf(glyphs);fb.setupHorizontalMetrics({name:(0 if name=='acute' else 500,0) for name in names});fb.setupHorizontalHeader(ascent=800,descent=-200)
 fb.setupNameTable({'familyName':'Roc Attachment Caps '+mode,'styleName':'Regular','psName':'RocAttachmentCaps-'+mode});fb.setupOS2(sTypoAscender=800,sTypoDescender=-200,usWinAscent=800,usWinDescent=200);fb.setupPost();fb.setupMaxp()
 if mode=='mark-chain':
  fea='markClass acute <anchor 0 0> @M; feature dist {pos a <13 0 0 0>;} dist; feature mark {pos base a <anchor 0 0> mark @M;} mark; feature mkmk {pos mark acute <anchor 0 10> mark @M;} mkmk;'
 else:
  fea='lookup First {lookupflag RightToLeft;pos cursive a <anchor 30 100> <anchor 470 120>;} First; feature curs {lookup First;'
  if mode=='cursive-reroot':fea+='lookup Second {pos cursive a <anchor 40 200> <anchor 460 230>;} Second;'
  fea+='} curs;'
 addOpenTypeFeaturesFromString(fb.font,'languagesystem DFLT dflt;'+fea)
 fb.font['head'].created=fb.font['head'].modified=3406620153;fb.font.recalcTimestamp=False;fb.font.save(HERE/(mode+'.ttf'),reorderTables=True)
cases=[]
for mode in ['mark-chain','cursive-chain','cursive-reroot']:
 for n in [8,62,63,64,65,66,127,129,257]:
  text='a'+'\u0301'*n if mode=='mark-chain' else 'a'*n
  for direction in ['ltr','rtl']:
   for level in [0,1]:
    cases.append({'id':f'{mode}-{n}-{direction}-{level}','font':mode+'.ttf','text':text,'options':{'script':'Latn','direction':direction,'cluster_level':level,'hb_options':['--show-flags']},'expected':'oracle'})
(HERE/'attachment-cases.jsonc').write_text(json.dumps({'schema':1,'about':'Original OTS-valid font isolation of64 nested attachment propagation,65 cursive reroot edges and native traversal order; boundary and growing cases.','cases':cases},indent=2,ensure_ascii=False)+'\n')
