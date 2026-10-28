"""Reproducible synthetic TrueType outlines and GDEF caret fixture.
Run with the repository's pinned fontTools oracle environment.
All drawings are original test geometry under the repository licence.
"""
from pathlib import Path
from array import array
import runpy
import struct
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib.tables._g_l_y_f import Glyph, GlyphCoordinates, GlyphComponent
from fontTools.ttLib.tables.DefaultTable import DefaultTable
from fontTools.ttLib import newTable
from fontTools.ttLib.tables.TupleVariation import TupleVariation

HERE = Path(__file__).resolve().parent
u16 = lambda x: struct.pack('>H', x)
raw = lambda tag, data: make_raw(tag, data)

def make_raw(tag, data):
    table = DefaultTable(tag)
    table.data = data
    return table

def simple(points, flags, ends):
    g = Glyph()
    g.numberOfContours = len(ends)
    g.coordinates = GlyphCoordinates(points)
    g.flags = array('B', flags)
    g.endPtsOfContours = ends
    from fontTools.ttLib.tables.ttProgram import Program
    g.program = Program()
    g.program.fromBytecode([])
    return g

def composite(parts):
    g = Glyph()
    g.numberOfContours = -1
    g.components = []
    for name, offset, anchor in parts:
        c = GlyphComponent()
        c.glyphName = name
        c.flags = 0
        if anchor:
            c.firstPt, c.secondPt = anchor
        else:
            c.x, c.y = offset
        g.components.append(c)
    return g

def main():
    names = ['.notdef', 'square', 'curves', 'alloff', 'anchored', 'nested']
    glyphs = {
        '.notdef': TTGlyphPen(None).glyph(),
        'square': simple([(100, 0), (500, 0), (500, 700), (100, 700)], [1]*4, [3]),
        'curves': simple([(0, 0), (100, 200), (300, 200), (400, 0)], [1, 0, 0, 1], [3]),
        'alloff': simple([(0, 100), (100, 200), (200, 100), (100, 0)], [0]*4, [3]),
        'anchored': composite([('square', (0, 0), None), ('curves', None, (2, 0))]),
        # An anchored glyph after a sibling catches parent-relative point
        # numbering incorrectly treated as root-relative.
        'nested': composite([('square', (1000, 0), None), ('anchored', (10, 20), None)]),
    }
    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder(names)
    fb.setupCharacterMap({65+i:name for i,name in enumerate(names[1:])})
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics({name: (1200, 0 if name=='.notdef' else glyphs[name].xMin) for name in names})
    fb.setupHorizontalHeader(ascent=1000, descent=-200)
    fb.setupNameTable({'familyName':'RocOutlineCaretFixture', 'styleName':'Regular', 'uniqueFontIdentifier':'RocOutlineCaretFixture', 'fullName':'RocOutlineCaretFixture Regular','psName':'RocOutlineCaretFixture-Regular'})
    fb.setupOS2(sTypoAscender=1000, sTypoDescender=-200, usWinAscent=1200, usWinDescent=200)
    fb.setupPost()
    fb.setupHead(unitsPerEm=1000, created=0, modified=0)
    fb.setupFvar([('wght',100,400,900,'Weight')], [])
    values = struct.pack('>Hh',1,150) + struct.pack('>HH',2,1) + struct.pack('>HhHHHH',3,250,6,0,0,0x8000)
    lig = struct.pack('>HHHH',3,8,12,16) + values
    liglist = struct.pack('>HHH',6,1,12) + struct.pack('>HHH',1,1,1) + lig
    ivs = runpy.run_path(str(HERE.parent/'variable'/'generate.py'))['ivs']
    store = ivs(1,[[(0,1,1)]],[([0],1,False,[[80]])])
    gdef = struct.pack('>IHHHHHI',0x00010003,0,0,18,0,0,18+len(liglist)) + liglist + store
    fb.font['GDEF'] = make_raw('GDEF',gdef)
    gvar = newTable('gvar')
    gvar.variations = {name: [] for name in names}
    gvar.variations['square'] = [TupleVariation({'wght': (0,1,1)}, [(0,0),(50,0),(0,0),(0,0),(7,0),(0,0),(0,0),(0,0)])]
    fb.font['gvar'] = gvar
    fb.font.recalcTimestamp = False
    fb.save(HERE/'outlines-carets.ttf')
    for label, position, replacement in [
      ('bad-point',18+12+12+2,u16(65535)),
      ('bad-index',18+12+16+6+2,u16(99)),
      ('bad-coverage',18+6+2,u16(2)),
    ]:
        altered=bytearray(gdef)
        altered[position:position+len(replacement)]=replacement
        fb.font['GDEF']=make_raw('GDEF',bytes(altered))
        fb.save(HERE/(label+'.ttf'))

if __name__ == '__main__':
    main()

# Kept separate from fontTools' glyph bounding-box recalculation: the
# intentionally hostile matrix chain exceeds signed16 header boxes.
def numeric_chains():
    from fontTools.ttLib import TTFont
    base=TTFont(HERE/'outlines-carets.ttf',recalcBBoxes=False,recalcTimestamp=False)
    def assemble(tables):
        def checksum(data):
            padded=data+bytes((-len(data))%4)
            return sum(struct.unpack('>'+('I'*(len(padded)//4)),padded))&0xffffffff
        tags=sorted(tables)
        count=len(tags); power=2**(count.bit_length()-1)
        header=struct.pack('>HHHHHH',1,0,count,16*power,power.bit_length()-1,16*(count-power))
        directory=b'';payload=b'';position=12+16*count
        positions={}
        for tag in tags:
            data=tables[tag];positions[tag]=position
            directory+=struct.pack('>4sIII',tag.encode(),checksum(data),position,len(data))
            padded=data+bytes((-len(data))%4);payload+=padded;position+=len(padded)
        out=bytearray(header+directory+payload)
        out[positions['head']+8:positions['head']+12]=struct.pack('>I',(0xb1b0afba-checksum(out))&0xffffffff)
        return bytes(out)
    for label,matrix in [('numeric-overflow',(32767,32767,32767,32767)),('deep-identity',(16384,0,0,16384))]:
        tables={tag:base.getTableData(tag) for tag in base.keys() if len(tag)==4 and tag not in ('fvar','gvar','GDEF')}
        tables['head']=tables['head'][:8]+bytes(4)+tables['head'][12:50]+u16(1)+tables['head'][52:]
        # Empty glyph0, square glyph1, then63 single-child composites.
        square=base['glyf']['square'].compile(base['glyf'])
        glyphs=[b'',square]
        for i in range(2,65):
            glyphs.append(struct.pack('>hhhhhHHhhhhhh',-1,0,0,500,700,0x83,i-1,0,0,*matrix))
        data=b'';offsets=[0]
        for glyph in glyphs:
            data+=glyph+bytes((-len(glyph))%2);offsets.append(len(data))
        tables['post']=struct.pack('>I',0x00030000)+bytes(28)
        tables['glyf']=data;tables['loca']=b''.join(struct.pack('>I',x) for x in offsets)
        tables['hmtx']=struct.pack('>Hh',1000,0)*65
        tables['hhea']=tables['hhea'][:34]+u16(65)
        maxp=bytearray(tables['maxp']);maxp[4:6]=u16(65);maxp[30:32]=u16(64);tables['maxp']=bytes(maxp)
        (HERE/(label+'.ttf')).write_bytes(assemble(tables))

if __name__ == '__main__':
    numeric_chains()
