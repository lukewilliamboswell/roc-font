"""Original UPL Graphite byte-program fixtures built from GTF/OpCodes formats."""
from pathlib import Path
import struct
import argparse
import io
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib.tables.DefaultTable import DefaultTable
HERE=Path(__file__).resolve().parent
parser=argparse.ArgumentParser();parser.add_argument("--check",action="store_true");args=parser.parse_args()
def u16(value):return struct.pack('>H',value)
def u32(value):return struct.pack('>L',value)
def raw(font,tag,data):
 table=DefaultTable(tag);table.data=data;font[tag]=table
def program(action,positioning=False,match=(1,)):
 # Original DFA for one exact glyph sequence and one output class [gid2].
 classes=u16(1)+u16(1)+u16(8)+u16(10)+u16(2)
 pass_start=58+len(classes)
 glyphs=sorted(set(match));columns={g:i for i,g in enumerate(glyphs)}
 ranges=b''.join(u16(g)+u16(g)+u16(columns[g]) for g in glyphs)
 count=len(glyphs);power=1<<(count.bit_length()-1)
 transitions=b''.join(u16(i+1 if g==wanted else 0) for i,wanted in enumerate(match) for g in glyphs)
 fsm=(u16(len(match)+1)+u16(len(match))+u16(1)+u16(count)+u16(count)
      +u16(power*6)+u16(power.bit_length()-1)+u16(count*6-power*6)
      +ranges+u16(0)+u16(1)+u16(0)+bytes([0,0])+u16(0)
      +u16(len(match))+bytes([0,0])+u16(0)+u16(0)+u16(0)
      +u16(0)+u16(len(action))+transitions+bytes([0]))
 code_at=pass_start+24+len(fsm)
 pass_data=bytes([0,10,len(match),0])+u16(1)+u16(24)+u32(code_at)*3+u32(0)+fsm+action
 sub=(u32(0x30000)+u16(42)+u16(50)+u16(2)+u16(0)+u16(0)
      +bytes([1,0,0 if positioning else 1,1,255,0,0,0,0,0,0,0,0,0])
      +u16(0)+bytes([0,1,1,0,0,0,0,0,0,0])+u16(0)
      +u32(pass_start)+u32(pass_start+len(pass_data))+u16(0)*4+classes+pass_data)
 assert len(sub)==pass_start+len(pass_data),(len(sub),pass_start,len(pass_data))
 return u32(0x30000)+u32(0x30000)+u16(1)+u16(0)+u32(16)+sub
programs={
 'replace':(bytes([0x1c,0,0x19,0x31]),False),
 'copy-after-change':(bytes([0x1c,0,0x1e,0,0x19,0x31]),False),
 'metric-after-change':(bytes([0x1c,0,0x2a,8,0,0,0x23,0,0x19,0x31]),False),
 'trunc8':(bytes([4,0,255,0x0d,0x23,0,0x32]),True),
 'trunc16':(bytes([5,0,0,255,255,0x0e,0x23,0,0x32]),True),
 'version':(bytes([0x37,0x23,0,0x32]),True),
 'set-advance':(bytes([1,17,0x23,0,0x32]),True),
 'version-shift':(bytes([0x37,0x23,20,0x32]),True),
 'divide-feature':(bytes([1,5,0x2b,0,0,9,0x23,0,0x32]),True),
 'divide-zero':(bytes([1,5,1,0,9,0x23,0,0x32]),True),
 'mutate-then-divide-zero':(bytes([1,17,0x23,0,1,5,1,0,9,0x23,0,0x32]),True),
}
for mode,(action,positioning) in programs.items():
 names=['.notdef','a','b'];fb=FontBuilder(1000,isTTF=True);fb.setupGlyphOrder(names);fb.setupCharacterMap({97:'a',98:'b'})
 glyphs={}
 for name in names:
  p=TTGlyphPen(None);p.moveTo((0,0));p.lineTo((300,0));p.lineTo((300,600));p.lineTo((0,600));p.closePath();glyphs[name]=p.glyph()
 fb.setupGlyf(glyphs);fb.setupHorizontalMetrics({n:(600+i,0) for i,n in enumerate(names)});fb.setupHorizontalHeader(ascent=800,descent=-200)
 fb.setupNameTable({'familyName':'Roc Graphite '+mode,'styleName':'Regular','psName':'RocGraphite-'+mode});fb.setupOS2(sTypoAscender=800,sTypoDescender=-200,usWinAscent=800,usWinDescent=200);fb.setupPost();fb.setupMaxp()
 for name_id,label in [(256,'Test feature'),(257,'Off'),(258,'On')]:fb.font['name'].setName(label,name_id,3,1,0x409)
 raw(fb.font,'Silf',program(action,positioning));raw(fb.font,'Feat',u32(0x20000)+u16(1)+bytes(6)+u32(100)+u16(2)+u16(0)+u32(28)+u16(0x8000)+u16(256)+u16(0)+u16(257)+u16(1)+u16(258));raw(fb.font,'Gloc',u32(0x10000)+u16(0)+u16(1)+b''.join(u16(i) for i in [4,8,12,16]));raw(fb.font,'Glat',u32(0x10000)+bytes([0,1,0,0])*3)
 fb.font['head'].created=fb.font['head'].modified=3406620153;fb.font.recalcTimestamp=False
 out=io.BytesIO();fb.font.save(out,reorderTables=True);target=HERE/(mode+'.ttf')
 if args.check:assert target.read_bytes()==out.getvalue(),target
 else:target.write_bytes(out.getvalue())
