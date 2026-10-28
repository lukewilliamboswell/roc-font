"""Original variation-completion fixtures, UPL; fontTools4.61.1."""
from pathlib import Path
import io,sys
from fontTools.ttLib import TTFont,newTable
from fontTools.fontBuilder import FontBuilder
from fontTools.ttLib.tables.TupleVariation import TupleVariation
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2];sys.path.insert(0,str(ROOT/'scripts'));import bench

def base():
 names=['.notdef','a','b'];f=TTFont(io.BytesIO(bench._build_font(names,{97:'a',98:'b'})),recalcTimestamp=False);f.setGlyphOrder(names);FontBuilder(font=f).setupFvar([('wght',0,0,1,'Weight')],[]);return f

def boundary():
 f=base();f['gvar']=g=newTable('gvar');g.version=1;g.reserved=0;g.variations={'a':[TupleVariation({'wght':(0,1,1)},[None]*4+[(0,0),(2147483136,0),(0,0),(0,0)])]};f.save(HERE/'phantom-boundary.ttf')
def vertical_boundary(top_delta,bottom_delta,name,bearing=100):
 f=base();builder=FontBuilder(font=f);builder.setupVerticalMetrics({g:(700,bearing) for g in f.getGlyphOrder()});builder.setupVerticalHeader(ascent=800,descent=-200)
 f['gvar']=g=newTable('gvar');g.version=1;g.reserved=0;g.variations={'a':[TupleVariation({'wght':(0,1,1)},[None]*4+[(0,0),(0,0),(0,top_delta),(0,bottom_delta)])]};f.save(HERE/name)

def vertical_large():
 f=base();builder=FontBuilder(font=f);builder.setupVerticalMetrics({name:(700,100) for name in f.getGlyphOrder()});builder.setupVerticalHeader(ascent=800,descent=-200)
 tuple=TupleVariation({'wght':(0,1,1)},[None]*4+[(0,0),(0,0),(0,0),(0,-2147483648)])
 import copy
 f['gvar']=g=newTable('gvar');g.version=1;g.reserved=0;g.variations={'a':[tuple,copy.deepcopy(tuple)]};f.save(HERE/'vertical-large.ttf')

if __name__=='__main__':
 boundary()
 vertical_large()
 vertical_boundary(0,-2147483008,'vertical-boundary.ttf')
 vertical_boundary(2147483136,0,'origin-boundary.ttf')
 vertical_boundary(-2147483648,0,'origin-negative-boundary.ttf',bearing=-1000)

# Additional original fixtures. Main invocation is below after definitions.
from fontTools.ttLib.tables import otTables as ot
from fontTools.varLib.builder import buildVarRegionList,buildVarData,buildVarStore,buildDeltaSetIndexMap
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib.tables.DefaultTable import DefaultTable
import copy,struct

def axis_base(axes):
 names=['.notdef','a','b'];f=TTFont(io.BytesIO(bench._build_font(names,{97:'a',98:'b'})),recalcTimestamp=False);f.setGlyphOrder(names);FontBuilder(font=f).setupFvar(axes,[]);return f

def avar_table(f,store,indexes=None):
 a=newTable('avar');a.majorVersion=2;a.minorVersion=0;a.segments={x.axisTag:{-1:-1,0:0,1:1} for x in f['fvar'].axes};a.table=ot.avar();a.table.VarStore=store;a.table.VarIdxMap=buildDeltaSetIndexMap(indexes) if indexes is not None else None;f['avar']=a

def avar_cross():
 f=axis_base([('wght',0,0,1,'Weight'),('wdth',0,0,1,'Width')]);tags=['wght','wdth']
 regions=buildVarRegionList([{'wght':(0,1,1)},{'wdth':(0,1,1)}],tags)
 store=buildVarStore(regions,[buildVarData([0,1],[[0,4096],[4096,0]],optimize=False)]);avar_table(f,store);f.save(HERE/'avar-cross.ttf')
 avar_table(f,store,[1,0]);f.save(HERE/'avar-mapped.ttf')
 avar_table(f,None);f.save(HERE/'avar-null.ttf')
 empty=buildVarStore(buildVarRegionList([],tags),[]);avar_table(f,empty,[0xffffffff,0xffffffff]);f.save(HERE/'avar-no-variation.ttf')
 # DeltaSetIndexMap count0 is the implicit axis-index mapping.
 avar_table(f,store);raw=f['avar'].compile(f);n=sum(2+4*len(a) for a in f['avar'].segments.values())+8
 raw=raw[:n]+struct.pack('>II',len(raw),struct.unpack_from('>I',raw,n+4)[0])+raw[n+8:]+bytes([0,0,0,0]);t=DefaultTable('avar');t.data=raw;f['avar']=t;f.save(HERE/'avar-empty-map.ttf')

def avar_tiny():
 tags=['AX01','AX02','AX03'];f=axis_base([(tag,0,0,1,tag) for tag in tags]);regions=buildVarRegionList([{tag:(0,1,1)for tag in tags}],tags)
 rows=[[2147483647]*32,[2147483647]*32,[0]*32];store=buildVarStore(regions,[buildVarData([0]*32,rows,optimize=False)]);avar_table(f,store);f.save(HERE/'avar-first-cache.ttf')

def phantom_normal():
 f=base();f['gvar']=g=newTable('gvar');g.version=1;g.reserved=0;g.variations={'a':[TupleVariation({'wght':(0,1,1)},[None]*4+[(-40,0),(60,0),(0,0),(0,0)])]};f.save(HERE/'phantom-simple.ttf')
 both=TupleVariation({'wght':(0,.5,1)},[(10,5)]*4+[(-20,0),(80,0),(0,0),(0,0)])
 sparse=TupleVariation({'wght':(0,1,1)},[None]*4+[(-20,0),(40,0),None,None]);g.variations['a']=[both,sparse];f.save(HERE/'phantom-mixed-tuples.ttf')

def composite_metrics():
 f=base();names=['.notdef','a','b','comp','nested'];f.setGlyphOrder(names);gm=f['glyf'].glyphs;hm=f['hmtx'].metrics
 for name in ['comp','nested']:hm[name]=(530 if name=='comp' else 540,50)
 pen=TTGlyphPen(gm);pen.addComponent('a',(1.5,0,0,1.5,100,20));pen.addComponent('b',(.5,0,0,.5,200,40));gm['comp']=pen.glyph();gm['comp'].components[0].flags|=0x200
 pen=TTGlyphPen(gm);pen.addComponent('comp',(.75,0,0,.75,80,10));gm['nested']=pen.glyph();gm['nested'].components[0].flags|=0x200
 for table in f['cmap'].tables:
  if table.isUnicode():table.cmap.update({99:'comp',100:'nested'})
 f['maxp'].numGlyphs=5;f['hhea'].numberOfHMetrics=5
 f['gvar']=g=newTable('gvar');g.version=1;g.reserved=0
 g.variations={'a':[TupleVariation({'wght':(0,1,1)},[None]*4+[(0,0),(100,0),None,None])], 'b':[TupleVariation({'wght':(0,1,1)},[None]*4+[(0,0),(200,0),None,None])], 'comp':[TupleVariation({'wght':(0,1,1)},[(300,0),(400,0),(0,0),(500,0),(0,0),(0,0)])]}
 f.save(HERE/'phantom-composite.ttf')
 gm['comp'].components[1].flags|=0x200;f.save(HERE/'phantom-last-metrics.ttf')

def scaled_phantoms():
 for count in [4,64,512]:
  for all_points in [False,True]:
   f=base();pen=TTGlyphPen(None);pen.moveTo((0,0))
   for i in range(1,count):pen.lineTo(((i%32)*10,(i//32)*10))
   pen.closePath();f['glyf'].glyphs['a']=pen.glyph()
   coords=([(0,0)]*count if all_points else [None]*count)+[(-40,0),(60,0),(0,0),(0,0)]
   f['gvar']=g=newTable('gvar');g.version=1;g.reserved=0;g.variations={'a':[TupleVariation({'wght':(0,1,1)},coords)]};f.save(HERE/f'phantom-{"all" if all_points else "sparse"}-{count}.ttf')

if __name__=='__main__':
 avar_cross();avar_tiny();phantom_normal();composite_metrics();scaled_phantoms()

def hvar_priority():
 f=TTFont(HERE/'phantom-simple.ttf',recalcTimestamp=False);h=ot.HVAR();h.Version=0x10000;h.VarStore=buildVarStore(buildVarRegionList([{'wght':(0,1,1)}],['wght']),[buildVarData([0],[[0],[300],[0]],optimize=False)]);h.AdvWidthMap=None;h.LsbMap=None;h.RsbMap=None;t=newTable('HVAR');t.table=h;f['HVAR']=t;f.save(HERE/'phantom-hvar-priority.ttf')

if __name__=='__main__':hvar_priority()

def many_axes():
 for count in [8,32,128,16382]:
  axes=[(f'{i:04X}',0,0,1,f'Axis {i}')for i in range(count)]
  if count<1000:f=axis_base(axes)
  else:
   # The format permits all axes to share a name ID. Avoid fontTools'
   # quadratic unique-name insertion in the format-limit stress fixture.
   from fontTools.ttLib.tables._f_v_a_r import Axis
   f=base();f['fvar'].axes=[]
   for tag,lo,default,hi,_ in axes:
    axis=Axis();axis.axisTag=tag;axis.minValue=lo;axis.defaultValue=default;axis.maxValue=hi;axis.flags=0;axis.axisNameID=256;f['fvar'].axes.append(axis)
  f.save(HERE/f'axes-{count}.ttf')
 # Format itself cannot represent required instanceSize=4*16383+4 in U16.
 f=TTFont(HERE/'axes-16382.ttf',recalcTimestamp=False);raw=bytearray(f.getTableData('fvar'));struct.pack_into('>H',raw,8,16383);struct.pack_into('>H',raw,14,0);t=DefaultTable('fvar');t.data=bytes(raw);f['fvar']=t;f.save(HERE/'axes-invalid-instance.ttf')

def inter_no_hvar():
 from fontTools import subset
 f=TTFont(HERE/'InterVariable.ttf',recalcTimestamp=False)
 options=subset.Options();options.recalc_timestamp=False;options.name_IDs=['*'];options.name_legacy=True;options.name_languages=['*']
 sub=subset.Subsetter(options=options);sub.populate(text='AVariable\u00e9\u00c5\u00fc');sub.subset(f)
 if 'HVAR'in f:del f['HVAR']
 # Inter is an OFL reserved font name; every font-identifying name changes.
 for rec in f['name'].names:
  if rec.nameID in [1,2,3,4,6,16,17,18,20,21,22,25]:
   value={2:'Regular',17:'Regular',22:'Regular',6:'RocVariationCorpus-Regular',25:'RocVariationCorpus'}.get(rec.nameID,'Roc Variation Corpus')
   rec.string=value.encode(rec.getEncoding(),errors='replace')
 f.save(HERE/'RocVariationCorpus-noHVAR.ttf')
if __name__=='__main__':many_axes();inter_no_hvar()
