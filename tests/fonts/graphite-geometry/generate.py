"""Original Graphite geometry witnesses from documented GTF/OpCodes formats.
No Graphite2 implementation source is used. Font bytes are UPL-licensed.
"""
from pathlib import Path
import argparse,io,json,struct
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib.tables.DefaultTable import DefaultTable
HERE=Path(__file__).resolve().parent
def u16(v):return struct.pack('>H',v)
def u32(v):return struct.pack('>I',v)
def program(action, positioning=False, match=(1,)):
    classes = u16(1) + u16(1) + u16(8) + u16(10) + u16(2)
    pass_start = 58 + len(classes)
    glyphs = sorted(set(match))
    columns = {g: i for i, g in enumerate(glyphs)}
    ranges = b''.join((u16(g) + u16(g) + u16(columns[g]) for g in glyphs))
    count = len(glyphs)
    power = 1 << count.bit_length() - 1
    transitions = b''.join((u16(i + 1 if g == wanted else 0) for i, wanted in enumerate(match) for g in glyphs))
    fsm = u16(len(match) + 1) + u16(len(match)) + u16(1) + u16(count) + u16(count) + u16(power * 6) + u16(power.bit_length() - 1) + u16(count * 6 - power * 6) + ranges + u16(0) + u16(1) + u16(0) + bytes([0, 0]) + u16(0) + u16(len(match)) + bytes([0, 0]) + u16(0) + u16(0) + u16(0) + u16(0) + u16(len(action)) + transitions + bytes([0])
    code_at = pass_start + 24 + len(fsm)
    pass_data = bytes([0, 10, len(match), 0]) + u16(1) + u16(24) + u32(code_at) * 3 + u32(0) + fsm + action
    sub = u32(196608) + u16(42) + u16(50) + u16(2) + u16(0) + u16(0) + bytes([1, 0, 0 if positioning else 1, 1, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0]) + u16(0) + bytes([0, 1, 1, 0, 0, 0, 0, 0, 0, 0]) + u16(0) + u32(pass_start) + u32(pass_start + len(pass_data)) + u16(0) * 4 + classes + pass_data
    assert len(sub) == pass_start + len(pass_data), (len(sub), pass_start, len(pass_data))
    return u32(196608) + u32(196608) + u16(1) + u16(0) + u32(16) + sub

def set_attr(attr,value):return bytes([3,(value>>8)&255,value&255,0x23,attr])
def attach(offset=1):return bytes([1,offset&255,0x26,2])+set_attr(3,100)+set_attr(8,20)+set_attr(4,200)+set_attr(9,30)
NEXT=bytes([0x19])
BASE=attach()

def variants():
 yield 'plain',b'',True,False,2
 yield 'attach-forward',BASE,True,False,2
 yield 'attach-backward',NEXT+attach(-1),True,False,2
 yield 'attach-cycle',BASE+NEXT+attach(-1),True,False,2
 yield 'attach-self',BASE+bytes([1,0,0x26,2]),True,False,2
 yield 'attach-same',BASE+bytes([1,1,0x26,2]),True,False,2
 yield 'attach-invalid',BASE+bytes([1,255,0x23,2]),True,False,2
 yield 'deleted-parent',NEXT+bytes([0x20,1,1,0x23,2])+set_attr(3,100)+set_attr(8,20),False,False,2
 yield 'deleted-child',BASE+bytes([0x20]),False,False,2
 yield 'copy-parent',BASE+bytes([0x1e,1]),False,False,2
 yield 'copy-child',BASE+NEXT+bytes([0x1e,255]),False,False,2
 yield 'copy-unrelated-parent',BASE+NEXT+NEXT+bytes([0x1e,255]),False,False,3
 yield 'copy-unrelated-child',BASE+NEXT+NEXT+bytes([0x1e,254]),False,False,3
 for name,action in [('child-copies-root',BASE+bytes([0x1e,2])),('parent-copies-root',BASE+NEXT+bytes([0x1e,1])),('child-copies-self',BASE+bytes([0x1e,0])),('parent-copies-self',BASE+NEXT+bytes([0x1e,0])),('siblings-copy',BASE+NEXT+NEXT+bytes([1,255,0x26,2,0x1e,254])),('chain-copies-root',BASE+NEXT+NEXT+bytes([1,254,0x26,2,0x1e,255]))]:
  yield name,action,False,False,3
 for name in ['positive','negative','disabled']:
  yield 'collision-default-'+name,b'',True,False,2
 for positioning in [False,True]:
  for put in [False,True]:
   label='collision-phase-'+('pos'if positioning else'sub')+('-put'if put else'')
   yield label,(bytes([0x1c,0])if put else b'')+bytes([0x28,57,0,0x23,21]),positioning,False,2
 for target in range(57,78):
  for value in [-1,65536]:
   action=bytes([5])+struct.pack('>i',value)+bytes([0x23,target,0x28,target,0,0x23,21])
   yield f'collision-write-{target}-{value}',action,True,False,2
 yield 'copy-parent-control',bytes([0x1e,1]),False,False,2
 yield 'copy-child-control',NEXT+bytes([0x1e,255]),False,False,2
 for attr in [2,5,6,7,10,11,12,13]:
  yield f'read-{attr}',BASE+bytes([0x28,attr,0,0x23,21]),True,False,2
 yield 'read-unattached',bytes([0x28,2,0,0x23,21]),True,False,2
 for value in [-300,-100,0,100,300,32767,-32768]:
  for who in ['child','parent']:
   for attr in [0,1,20,21,29]:
    yield f'{who}-{attr}-{value}',BASE+(NEXT if who=='parent' else b'')+set_attr(attr,value),True,False,2
 for value in [-1,0,1,50,255,256,300]:
  yield f'level-{value}',BASE+set_attr(13,value)+bytes([0x28,13,0,0x23,21]),True,False,2
 for metric in range(11):
  for level in [0,1,49,50,255]:
   yield f'metric-{metric}-{level}',BASE+set_attr(13,50)+bytes([0x2a,metric,0,level,0x23,21]),True,False,2
 for value in [0,1]:
  yield f'precontext-raw-{value}',bytes([1,value,0x23,2])+set_attr(3,100)+set_attr(8,20),True,True,2
 yield 'precontext-relative',attach(-1),True,True,2
 yield 'nested',BASE+NEXT+bytes([1,1,0x26,2])+set_attr(3,50)+set_attr(8,10)+set_attr(4,80)+set_attr(9,20),True,False,3
 yield 'siblings',BASE+NEXT+NEXT+bytes([1,255,0x26,2])+set_attr(3,50)+set_attr(8,10)+set_attr(4,80)+set_attr(9,20),True,False,3
 yield 'nested-child-shift',BASE+NEXT+bytes([1,1,0x26,2])+set_attr(3,50)+set_attr(8,10)+set_attr(20,100),True,False,3

def font(label,action,positioning,precontext,count,rtl):
 names=['.notdef']+[chr(97+i) for i in range(count)]
 fb=FontBuilder(1000,isTTF=True);fb.setupGlyphOrder(names);fb.setupCharacterMap({ord(n):n for n in names[1:]})
 glyphs={}
 for name in names:
  p=TTGlyphPen(None);p.moveTo((0,0));p.lineTo((300,0));p.lineTo((300,600));p.lineTo((0,600));p.closePath();glyphs[name]=p.glyph()
 fb.setupGlyf(glyphs);fb.setupHorizontalMetrics({name:(600+i,0)for i,name in enumerate(names)})
 fb.setupHorizontalHeader(ascent=800,descent=-200)
 fb.setupNameTable({'familyName':'Roc Graphite Geometry','styleName':label,'psName':'RocGraphiteGeometry-'+label})
 fb.setupOS2(sTypoAscender=800,sTypoDescender=-200,usWinAscent=800,usWinDescent=200);fb.setupPost();fb.setupMaxp()
 data=bytearray(program(action+bytes([0x32]),positioning,tuple(range(1,count+1))))
 data[24:26]=u16(count);data[48]=2 if rtl else 1
 if precontext:
  # GTF pass FSM: pre-context min/max and rule's pre-context count.
  pass_at=16+68
  ranges=count*6;pre_at=pass_at+24+16+ranges+6
  assert data[pre_at:pre_at+2]==b'\0\0'
  data[pre_at:pre_at+2]=bytes([1,1]);data[pre_at+6]=1;data[36]=1
 collision=label.startswith('collision-')
 collision_kind=label.rsplit('-',1)[0].split('collision-default-')[-1]
 if collision:data[35]=0 if 'disabled'in label else 32;data[49]=1
 def raw(tag,value):t=DefaultTable(tag);t.data=value;fb.font[tag]=t
 raw('Silf',bytes(data));raw('Glat',u32(65536)+bytes([0,1,0,0])*len(names))
 raw('Gloc',u32(65536)+u16(0)+u16(1)+b''.join(u16(4+i*4)for i in range(len(names)+1)))
 if collision:
  values=[-1]*16 if collision_kind=='negative'else list(range(101,117))
  entries=[bytes([1,16])+struct.pack('>16h',*([(glyph+1)*100+i+1 for i in range(16)]if 'phase'in label else values))for glyph in range(len(names))]
  raw('Glat',u32(65536)+b''.join(entries))
  raw('Gloc',u32(65536)+u16(0)+u16(17)+b''.join(u16(4+i*len(entries[0]))for i in range(len(names)+1)))
 fb.font['head'].created=fb.font['head'].modified=3406620153;fb.font.recalcTimestamp=False
 out=io.BytesIO();fb.font.save(out,reorderTables=True);return out.getvalue()

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args();cases=[]
 for label,action,positioning,precontext,count in variants():
  for rtl in [False,True]:
   name=label+('-rtl'if rtl else '-ltr');path=HERE/(name+'.ttf');data=font(name,action,positioning,precontext,count,rtl)
   if args.check:assert path.read_bytes()==data,path
   else:path.write_bytes(data)
   cases.append({'id':name,'font':path.name,'text':''.join(chr(97+i)for i in range(count)),'direction':'rtl'if rtl else'ltr','positioning':positioning,'precontext':int(precontext),'action':list(action)})
 output=json.dumps({'schema':1,'cases':cases},indent=2)+'\n';path=HERE/'geometry-cases.jsonc'
 if args.check:assert path.read_text()==output,path
 else:path.write_text(output)
 print(f'{len(cases)} original geometry fonts '+('reproduced'if args.check else'generated'))

if __name__=='__main__':main()
