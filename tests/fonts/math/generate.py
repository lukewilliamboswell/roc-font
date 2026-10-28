"""Regenerate our original synthetic MATH fixtures with fontTools 4.61.1.

Run from the repository root with the oracle virtualenv. The real Noto font
is unmodified and never regenerated. Generated fixtures use this repo's UPL.
"""
from pathlib import Path
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.otlLib.builder import buildMathTable
from fontTools.ttLib import newTable
from fontTools.ttLib.tables import otTables as ot
from fontTools.ttLib.tables._f_v_a_r import Axis
from fontTools.varLib.builder import buildVarRegionList, buildVarData, buildVarStore

HERE = Path(__file__).resolve().parent


def value(v, device=None):
    r = ot.MathValueRecord()
    r.Value = v
    r.DeviceTable = device
    return r


def device(format, start, end, deltas=None):
    d = ot.Device()
    d.DeltaFormat = format
    d.StartSize = start
    d.EndSize = end
    if deltas is not None:
        d.DeltaValue = deltas
    return d


def base():
    b = FontBuilder(1000, isTTF=True)
    names = ['.notdef'] + [f'g{i}' for i in range(1,16)]
    b.setupGlyphOrder(names)
    glyphs = {}
    for i, name in enumerate(names):
        p = TTGlyphPen(None)
        if i:
            p.moveTo((20,0)); p.lineTo((400,0)); p.lineTo((400,600)); p.lineTo((20,600)); p.closePath()
        glyphs[name] = p.glyph()
    b.setupGlyf(glyphs)
    b.setupHorizontalMetrics({n:(500,20 if i else 0) for i,n in enumerate(names)})
    b.setupHorizontalHeader(ascent=800, descent=-200)
    b.setupCharacterMap({0x60+i:n for i,n in enumerate(names) if i})
    b.setupNameTable({'familyName':'Roc Math Fixture','styleName':'Regular','uniqueFontIdentifier':'RocMathFixture-1','fullName':'Roc Math Fixture Regular','psName':'RocMathFixture-Regular'})
    b.setupOS2(sTypoAscender=800,sTypoDescender=-200,usWinAscent=800,usWinDescent=200)
    b.setupPost(); b.setupMaxp()
    b.font['head'].created = b.font['head'].modified = 3700000000
    b.font.recalcTimestamp = False
    return b.font


def make(name, varied=False, empty=False):
    font=base()
    buildMathTable(font,
        constants={'ScriptPercentScaleDown':80,'ScriptScriptPercentScaleDown':60,'AxisHeight':250,'FractionRuleThickness':40,'RadicalDegreeBottomRaisePercent':65},
        italicsCorrections={} if empty else {'g1':12,'g3':-9},
        topAccentAttachments={} if empty else {'g1':240,'g3':0},
        extendedShapes=set() if empty else {'g1','g3'},
        mathKerns={} if empty else {'g1':{'TopRight':([-100,100],[10,20,30]),'TopLeft':([50],[-10,25]),'BottomRight':([],[7]),'BottomLeft':([-50,0,50],[-30,-20,-10,0])},'g3':{'TopRight':([0,0,100,100],[1,2,3,4,5])}},
        minConnectorOverlap=0 if empty else 20,
        vertGlyphVariants={} if empty else {'g1':[('g2',700),('g3',1100)]},
        horizGlyphVariants={} if empty else {'g3':[('g4',800),('g5',1200)]},
        vertGlyphAssembly={} if empty else {'g1':([('g6',0,0,100,400),('g7',1,100,100,200),('g8',0,100,0,400)],30)},
        horizGlyphAssembly={} if empty else {'g3':([],0)})
    # Keep empty root subtables explicit; zero-count coverage is valid.
    table=font['MATH'].table
    if table.MathGlyphInfo is None:
        table.MathGlyphInfo=ot.MathGlyphInfo();table.MathGlyphInfo.populateDefaults()
    if table.MathVariants is None:
        table.MathVariants=ot.MathVariants();table.MathVariants.populateDefaults();table.MathVariants.MinConnectorOverlap=0
    if not empty:
        table.MathConstants.FractionRuleThickness.DeviceTable=device(1,10,12,[-1,0,1])
        table.MathConstants.OverbarRuleThickness.DeviceTable=device(2,9,10,[-2,3])
        table.MathConstants.UnderbarRuleThickness.DeviceTable=device(3,8,8,[-8])
    if varied:
        font['fvar']=fvar=newTable('fvar');a=Axis();a.axisTag='wght';a.minValue=100;a.defaultValue=400;a.maxValue=900;a.flags=0;a.axisNameID=256;fvar.axes=[a];fvar.instances=[]
        store=buildVarStore(buildVarRegionList([{'wght':(0,1,1)}],['wght']),[buildVarData([0],[[100],[20],[-40],[25],[30],[50]],optimize=False)])
        font['GDEF']=gdef=newTable('GDEF');gdef.table=ot.GDEF();gdef.table.Version=0x10003;gdef.table.populateDefaults();gdef.table.VarStore=store
        table.MathConstants.AxisHeight.DeviceTable=device(0x8000,0,0)
        table.MathGlyphInfo.MathItalicsCorrectionInfo.ItalicsCorrection[0].DeviceTable=device(0x8000,0,1)
        table.MathGlyphInfo.MathTopAccentAttachment.TopAccentAttachment[0].DeviceTable=device(0x8000,0,2)
        kern=table.MathGlyphInfo.MathKernInfo.MathKernInfoRecords[0].TopRightMathKern
        kern.CorrectionHeight[1].DeviceTable=device(0x8000,0,3)
        table.MathGlyphInfo.MathKernInfo.MathKernInfoRecords[1].TopRightMathKern.CorrectionHeight[1].DeviceTable=device(0x8000,0,3)
        kern.KernValue[0].DeviceTable=device(0x8000,0,4)
        table.MathVariants.VertGlyphConstruction[0].GlyphAssembly.ItalicsCorrection.DeviceTable=device(0x8000,0,5)
    font.save(HERE/name,reorderTables=True)


if __name__=='__main__':
    make('math.ttf');make('math-variable.ttf',varied=True);make('math-empty.ttf',empty=True)
