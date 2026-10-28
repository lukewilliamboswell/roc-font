"""Original GPOS context scheduling fixtures; fontTools 4.61.1, UPL.

The ordinary 256/2048/8192 fonts reproduce the integrator's before samples
byte for byte. Resource fixtures are structurally valid, including cycles;
they test bounded execution rather than pretending every reference shapes.
"""
from pathlib import Path
import copy,io,json,struct,sys
from fontTools.ttLib import TTFont,newTable
from fontTools.ttLib.tables import otTables as ot
from fontTools.ttLib.tables.otBase import ValueRecord
from fontTools.otlLib.builder import buildMarkBasePosSubtable,buildAnchor,buildSinglePosSubtable
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
sys.path.insert(0,str(ROOT/'scripts'))
import bench

def base(marks=False):
 names=['.notdef','a','b','acute'] if marks else ['.notdef','a']
 cmap={97:'a',98:'b',0x301:'acute'} if marks else {97:'a'}
 f=TTFont(io.BytesIO(bench._build_font(names,cmap,'feature mark {pos a 1;}mark;')),recalcTimestamp=False)
 f.setGlyphOrder(names)
 if marks:
  f['GDEF']=g=newTable('GDEF');g.table=ot.GDEF();g.table.Version=0x10000;g.table.populateDefaults();g.table.GlyphClassDef=ot.ClassDef();g.table.GlyphClassDef.classDefs={'a':1,'b':1,'acute':3}
 return f

def value(name,amount):
 v=ValueRecord();setattr(v,name,amount);return v

def record(seq,index):
 r=ot.PosLookupRecord();r.SequenceIndex=seq;r.LookupListIndex=index;return r

def cov(names):
 c=ot.Coverage();c.glyphs=names;return c

def lookup(kind,sub,flags=0):
 l=ot.Lookup();l.LookupType=kind;l.LookupFlag=flags;l.SubTable=[sub];l.SubTableCount=1;return l

def context(records,fmt=3,chain=False,inputs=None):
 names=inputs or ['a'];s=ot.ChainContextPos() if chain else ot.ContextPos();s.Format=fmt
 if fmt==3:
  if chain:
   s.BacktrackCoverage=[cov(['a'])];s.BacktrackGlyphCount=1;s.InputCoverage=[cov([n]) for n in names];s.InputGlyphCount=len(names);s.LookAheadCoverage=[];s.LookAheadGlyphCount=0
  else:s.Coverage=[cov([n]) for n in names];s.GlyphCount=len(names)
  s.PosLookupRecord=records;s.PosCount=len(records)
 elif fmt==1:
  s.Coverage=cov([names[0]])
  rule=ot.ChainPosRule() if chain else ot.PosRule();rule.Input=names[1:];rule.PosLookupRecord=records;rule.PosCount=len(records)
  if chain:
   rule.Backtrack=['a'];rule.BacktrackGlyphCount=1;rule.InputGlyphCount=len(names);rule.LookAhead=[];rule.LookAheadGlyphCount=0
   rs=ot.ChainPosRuleSet();rs.ChainPosRule=[rule];rs.ChainPosRuleCount=1;s.ChainPosRuleSet=[rs];s.ChainPosRuleSetCount=1
  else:
   rule.GlyphCount=len(names);rs=ot.PosRuleSet();rs.PosRule=[rule];rs.PosRuleCount=1;s.PosRuleSet=[rs];s.PosRuleSetCount=1
 else:
  s.Coverage=cov([names[0]]);classes={n:i+1 for i,n in enumerate(names)}
  rule=ot.ChainPosClassRule() if chain else ot.PosClassRule();rule.Class=[classes[n] for n in names[1:]];rule.PosLookupRecord=records;rule.PosCount=len(records)
  if chain:
   for field,values in [('BacktrackClassDef',{'a':1}),('InputClassDef',classes),('LookAheadClassDef',{})]:
    d=ot.ClassDef();d.classDefs=values;setattr(s,field,d)
   rule.Backtrack=[1];rule.BacktrackGlyphCount=1;rule.InputGlyphCount=len(names);rule.LookAhead=[];rule.LookAheadGlyphCount=0
   rs=ot.ChainPosClassSet();rs.ChainPosClassRule=[rule];rs.ChainPosClassRuleCount=1;s.ChainPosClassSet=[None,rs]+[None]*(len(names)-1);s.ChainPosClassSetCount=len(names)+1
  else:
   s.ClassDef=ot.ClassDef();s.ClassDef.classDefs=classes;rule.GlyphCount=len(names);rs=ot.PosClassSet();rs.PosClassRule=[rule];rs.PosClassRuleCount=1;s.PosClassSet=[None,rs]+[None]*(len(names)-1);s.PosClassSetCount=len(names)+1
 return s

def save(f,name,lookups):
 f['GPOS'].table.LookupList.Lookup=lookups;f['GPOS'].table.LookupList.LookupCount=len(lookups);f.save(HERE/name,reorderTables=True)

def many(n,ignored=False):
 f=base();leaf=copy.deepcopy(f['GPOS'].table.LookupList.Lookup[0]);s=context([record(1 if ignored else 0,1) for _ in range(n)])
 save(f,f'{"ignored" if ignored else "many"}-{n}.ttf',[lookup(7,s),leaf])

def order(name,records):
 f=base(True);gm=f.getReverseGlyphMap()
 attach=lookup(4,buildMarkBasePosSubtable({'acute':(0,buildAnchor(0,0))},{'a':{0:buildAnchor(100,700)}},gm))
 shift=lookup(1,buildSinglePosSubtable({'acute':value('XPlacement',7)},gm))
 nested=lookup(7,context([record(0,1),record(0,2)],inputs=['acute']))
 save(f,name,[lookup(7,context([record(*r) for r in records],inputs=['a','acute'])),attach,shift,nested])

def skips(fmt,chain=False):
 f=base(True);s=context([record(0 if chain else 1,1)],fmt,chain,inputs=['b'] if chain else ['a','b'])
 leaf=lookup(1,buildSinglePosSubtable({'b':value('XAdvance',17)},f.getReverseGlyphMap()))
 save(f,f'{"chain" if chain else "context"}-{fmt}.ttf',[lookup(8 if chain else 7,s,8),leaf])

def recursive(n,fanout=False):
 f=base();leaf=copy.deepcopy(f['GPOS'].table.LookupList.Lookup[0])
 if fanout:lookups=[lookup(7,context([record(0,1) for _ in range(n)])),lookup(7,context([record(0,2) for _ in range(n)])),leaf]
 else:lookups=[lookup(7,context([record(0,0) for _ in range(n)])),leaf]
 save(f,f'{"fanout" if fanout else "cycle"}-{n}.ttf',lookups)

def saturation(field):
 f=base();gm=f.getReverseGlyphMap()
 pos=lookup(1,buildSinglePosSubtable({'a':value(field,32767)},gm))
 neg=lookup(1,buildSinglePosSubtable({'a':value(field,-32768)},gm))
 lookups=[lookup(7,context([record(0,1) for _ in range(9)]+[record(0,2) for _ in range(9)])),lookup(7,context([record(0,3) for _ in range(8192)])),lookup(7,context([record(0,4) for _ in range(8192)])),pos,neg]
 save(f,'saturating-'+('advance' if field=='XAdvance' else 'placement')+'.ttf',lookups)

def wide(n):
 # Coverage overlaps the first ignored records, keeping Offset16 small
 # despite a >64KiB record list. The layout permits shared byte ranges.
 u16=lambda *v:struct.pack('>'+'H'*len(v),*v)
 u32=lambda v:struct.pack('>I',v)
 script=u16(1)+b'DFLT'+u16(8)+u16(4,0)+u16(0,65535,1,0)
 feature=u16(1)+b'mark'+u16(8)+u16(0,1,0)
 sub=u16(3,1,n,8)+u16(1,1,1,1)+u16(0,1)*(n-2)
 single=u16(1,8,4,1)+u16(1,1,1)
 entries=u16(2,6,22)+u16(9,0,1,8)+u16(1,7)+u32(30)+u16(1,0,1,8)+single+sub
 data=u32(0x10000)+u16(10,30,44)+script+feature+entries
 assert len(script)==20 and len(feature)==14
 f=base();from fontTools.ttLib.tables.DefaultTable import DefaultTable
 f['GPOS']=t=DefaultTable('GPOS');t.data=data;f.save(HERE/f'wide-{n-2}.ttf',reorderTables=True)

if __name__=='__main__':
 for n in [8,64,256,2048,8192]:many(n)
 many(8192,ignored=True)
 for fmt in [1,2,3]:skips(fmt);skips(fmt,chain=True)
 order('nested-order.ttf',[(1,3),(1,2)])
 order('shift-attach.ttf',[(1,2),(1,1)])
 order('attach-shift.ttf',[(1,1),(1,2)])
 recursive(8192);recursive(8192,fanout=True)
 for field in ['XAdvance','XPlacement']:saturation(field)
 for n in [16385,16386,16387]:wide(n)
