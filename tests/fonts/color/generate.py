"""Original color-font fixtures; reproduce with fontTools4.61.1.

All32COLRv1formats, CPALv1metadata/overlappingpalettes, own variation
store and explicit/identity maps, clipboxes and COLRv0are covered. Fonts
are original testdata under thisrepository's UPL, not defaultfonts.
"""
from pathlib import Path
import copy, struct
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.colorLib.builder import buildCOLR
from fontTools.ttLib.tables.DefaultTable import DefaultTable
from fontTools.ttLib.tables._f_v_a_r import Axis
from fontTools.ttLib import newTable
from fontTools.varLib.builder import buildVarRegionList,buildVarData,buildVarStore,buildDeltaSetIndexMap

HERE=Path(__file__).resolve().parent


def base():
    b=FontBuilder(1000,isTTF=True)
    names=['.notdef']+[f'g{i}' for i in range(1,36)]
    b.setupGlyphOrder(names)
    glyphs={}
    for i,name in enumerate(names):
        p=TTGlyphPen(None)
        if i:
            p.moveTo((0,0));p.lineTo((600,0));p.lineTo((600,700));p.lineTo((0,700));p.closePath()
        glyphs[name]=p.glyph()
    b.setupGlyf(glyphs)
    b.setupHorizontalMetrics({n:(700,0) for n in names})
    b.setupHorizontalHeader(ascent=800,descent=-200)
    b.setupCharacterMap({0x40+i:name for i,name in enumerate(names) if i})
    b.setupNameTable({'familyName':'Roc Color Fixture','styleName':'Regular','uniqueFontIdentifier':'RocColorFixture-1','fullName':'Roc Color Fixture Regular','psName':'RocColorFixture-Regular'})
    b.setupOS2(sTypoAscender=800,sTypoDescender=-200,usWinAscent=800,usWinDescent=200)
    b.setupPost();b.setupMaxp()
    b.font.recalcTimestamp=False
    b.font['head'].created=b.font['head'].modified=3700000000
    for id,text in [(256,'Day'),(257,'Night'),(258,'Outline'),(259,'Fill'),(260,'Highlight'),(300,'Weight')]:
        b.font['name'].setName(text,id,3,1,0x409)
    # Two3-entrypalettes share2records. Colorbytes areBGRA, notpremultiplied.
    u16=lambda v:struct.pack('>H',v)
    u32=lambda v:struct.pack('>I',v)
    data=u16(1)+u16(3)+u16(2)+u16(4)+u32(28)+u16(0)+u16(1)+u32(44)+u32(52)+u32(56)
    data+=bytes([0,0,255,255, 0,255,0,128, 255,0,0,255, 7,8,9,0])
    data+=u32(1)+u32(2)+u16(256)+u16(257)+u16(258)+u16(259)+u16(65535)
    assert len(data)==62
    b.font['CPAL']=cpal=DefaultTable('CPAL');cpal.data=data
    return b.font


SOLID={'Format':2,'PaletteIndex':0,'Alpha':0.75}
SHAPE={'Format':10,'Paint':SOLID,'Glyph':'g34'}


def paint(fmt):
    p={'Format':fmt}
    if fmt==1:return {**p,'Layers':[SHAPE,{'Format':10,'Glyph':'g35','Paint':{'Format':2,'PaletteIndex':65535,'Alpha':1}}]}
    if fmt in (2,3):p.update(PaletteIndex=1,Alpha=0.5)
    elif 4<=fmt<=9:
        varied=fmt%2==1
        stops=[{'StopOffset':0.75,'PaletteIndex':2,'Alpha':0.5},{'StopOffset':0.25,'PaletteIndex':0,'Alpha':1},{'StopOffset':0.75,'PaletteIndex':65535,'Alpha':0.75}]
        if varied:
            for s in stops:s['VarIndexBase']=6
        p['ColorLine']={'Extend':1,'ColorStop':stops}
        if fmt<=5:p.update(x0=10,y0=20,x1=400,y1=50,x2=50,y2=500)
        elif fmt<=7:p.update(x0=10,y0=20,r0=100,x1=300,y1=400,r1=600)
        else:p.update(centerX=100,centerY=200,startAngle=-90,endAngle=270)
    elif fmt==10:p.update(Paint=SOLID,Glyph='g34')
    elif fmt==11:p['Glyph']='g1'
    elif fmt in (12,13):
        p.update(Paint=SHAPE,Transform={'xx':1,'yx':0.25,'xy':-0.125,'yy':0.75,'dx':12.5,'dy':-8.25})
        if fmt==13:p['Transform']['VarIndexBase']=0
    elif fmt in (14,15):p.update(Paint=SHAPE,dx=12,dy=-8)
    elif fmt in (16,17,18,19):
        p.update(Paint=SHAPE,scaleX=1.25,scaleY=0.75)
        if fmt>=18:p.update(centerX=100,centerY=200)
    elif fmt in (20,21,22,23):
        p.update(Paint=SHAPE,scale=1.25)
        if fmt>=22:p.update(centerX=100,centerY=200)
    elif fmt in (24,25,26,27):
        p.update(Paint=SHAPE,angle=45)
        if fmt>=26:p.update(centerX=100,centerY=200)
    elif fmt in (28,29,30,31):
        p.update(Paint=SHAPE,xSkewAngle=22.5,ySkewAngle=-45)
        if fmt>=30:p.update(centerX=100,centerY=200)
    else:p.update(SourcePaint=SHAPE,CompositeMode=23,BackdropPaint={'Format':10,'Glyph':'g35','Paint':{'Format':2,'PaletteIndex':2,'Alpha':1}})
    if fmt in (3,5,7,9,15,17,19,21,23,25,27,29,31):p['VarIndexBase']=0
    return p


def make(name,mapped=False,v0=False):
    font=base()
    if v0:
        font['COLR']=buildCOLR({'g1':[('g34',0),('g35',65535)],'g2':[]},version=0,glyphMap=font.getReverseGlyphMap())
    else:
        font['fvar']=fvar=newTable('fvar');a=Axis();a.axisTag='wght';a.minValue=100;a.defaultValue=400;a.maxValue=900;a.flags=0;a.axisNameID=300;fvar.axes=[a];fvar.instances=[]
        rows=[[128],[-256],[512],[-768],[1024],[-2048],[16384],[-8192],[11],[-13],[17],[-19]]
        store=buildVarStore(buildVarRegionList([{'wght':(0,1,1)}],['wght']),[buildVarData([0],rows,optimize=False)])
        mapping=buildDeltaSetIndexMap([11,10,9,8,7,6,5,4]) if mapped else None
        glyphs={f'g{fmt}':paint(fmt) for fmt in range(1,33)}
        clips={f'g{fmt}':(-20,-200,800,900,8) for fmt in range(1,33)}
        font['COLR']=buildCOLR(glyphs,version=1,glyphMap=font.getReverseGlyphMap(),varStore=store,varIndexMap=mapping,clipBoxes=clips,allowLayerReuse=True)
    font.save(HERE/name,reorderTables=True)


if __name__=='__main__':
    make('color-v0.ttf',v0=True)
    make('color-all.ttf')
    make('color-map.ttf',mapped=True)


def precision():
    font=base();font['fvar']=fvar=newTable('fvar');fvar.axes=[];fvar.instances=[]
    tags=['wght','AX02','AX03','AX04']
    for tag in tags:
        a=Axis();a.axisTag=tag;a.minValue=0;a.defaultValue=0;a.maxValue=16384;a.flags=0;a.axisNameID=300;fvar.axes.append(a)
    rows=[[0]*32 for _ in range(4)]+[[1]+[0]*31,[2147483647]*32]
    store=buildVarStore(buildVarRegionList([{t:(0,1,1) for t in tags}],tags),[buildVarData([0]*32,rows,optimize=False)])
    p={'Format':13,'Paint':SHAPE,'Transform':{'xx':0,'yx':0,'xy':0,'yy':0,'dx':0,'dy':0,'VarIndexBase':0}}
    font['COLR']=buildCOLR({'g1':p},version=1,glyphMap=font.getReverseGlyphMap(),varStore=store,clipBoxes={'g1':(-20,-200,800,900)})
    font.save(HERE/'color-precision.ttf',reorderTables=True)

if __name__=='__main__':precision()
