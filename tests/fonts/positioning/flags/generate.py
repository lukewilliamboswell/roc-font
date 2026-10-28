"""Original valid fonts isolating pair safety flags in the general GPOS path."""
from pathlib import Path
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
HERE=Path(__file__).resolve().parent
names=['.notdef','space','a','b','c','d']
for mode,feature in {
 'zero-first':'pos a b 0; pos c d -20;',
 'zero-second':'pos a <0 0 0 0> b <0 0 0 0>; pos c <0 0 -20 0> d <0 0 10 0>;',
 'zero-class':'pos [a] [b] 0; pos [c] [d] -20;',
 'vertical-only':'pos a b <0 0 0 40>;',
 'variable-cancellation':'pos a b -80;'
}.items():
 fb=FontBuilder(1000,isTTF=True);fb.setupGlyphOrder(names);fb.setupCharacterMap({32:'space',97:'a',98:'b',99:'c',100:'d'})
 glyphs={}
 for name in names:
  pen=TTGlyphPen(None)
  if name!='space':pen.moveTo((0,0));pen.lineTo((200,0));pen.lineTo((200,300));pen.lineTo((0,300));pen.closePath()
  glyphs[name]=pen.glyph()
 fb.setupGlyf(glyphs);fb.setupHorizontalMetrics({name:(600,0) for name in names});fb.setupHorizontalHeader(ascent=800,descent=-200)
 fb.setupNameTable({'familyName':'Roc Pair Flags '+mode,'styleName':'Regular','psName':'RocPairFlags-'+mode});fb.setupOS2(sTypoAscender=800,sTypoDescender=-200,usWinAscent=800,usWinDescent=200);fb.setupPost();fb.setupMaxp()
 # The harmless single positioning lookup deliberately selects the full
 # positioning engine. Pair-only fixture coverage separately protects its
 # existing fast path.
 addOpenTypeFeaturesFromString(fb.font, 'languagesystem DFLT dflt; '+('feature dist { pos a 0; } dist; feature kern { '+feature+' } kern;' if mode=='variable-cancellation' else 'feature kern { pos a 0; '+feature+' } kern;'))
 if mode=='variable-cancellation':
  from fontTools.ttLib.tables import otTables as ot
  from fontTools.ttLib import newTable
  from fontTools.varLib.builder import buildVarRegionList,buildVarData,buildVarStore
  fb.setupFvar([('wght',100,400,900,'Weight')],[])
  gdef=newTable('GDEF');gdef.table=ot.GDEF();gdef.table.Version=0x00010003;gdef.table.GlyphClassDef=None;gdef.table.AttachList=None;gdef.table.LigCaretList=None;gdef.table.MarkAttachClassDef=None;gdef.table.MarkGlyphSetsDef=None
  gdef.table.VarStore=buildVarStore(buildVarRegionList([{'wght':(0,1,1)}],['wght']),[buildVarData([0],[[80]],optimize=False)]);fb.font['GDEF']=gdef
  sub=next(l.SubTable[0] for l in fb.font['GPOS'].table.LookupList.Lookup if l.LookupType==2)
  sub.ValueFormat1|=0x40
  d=ot.Device();d.StartSize=0;d.EndSize=0;d.DeltaFormat=0x8000
  sub.PairSet[0].PairValueRecord[0].Value1.XAdvDevice=d
 fb.font['head'].created=fb.font['head'].modified=3406620153;fb.font.recalcTimestamp=False;fb.font.save(HERE/(mode+'.ttf'),reorderTables=True)
