"""Original UPL1.0 kerx/kern/ankr fixtures, fontTools4.61.1."""
from pathlib import Path
import io,struct,sys,shutil
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables.DefaultTable import DefaultTable
from fontTools.fontBuilder import FontBuilder
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2];sys.path.insert(0,str(ROOT/'scripts'));import bench
u16=lambda *n:struct.pack('>'+'H'*len(n),*n)
u32=lambda *n:struct.pack('>'+'I'*len(n),*n)
i16=lambda *n:struct.pack('>'+'h'*len(n),*n)
i32=lambda *n:struct.pack('>'+'i'*len(n),*n)

def lookup(values,first=1,width=2):return u16(8,first,len(values))+b''.join((u32(v)if width==4 else u16(v))for v in values)
def base():
 names=['.notdef','a','b','c','acutecomb'];f=TTFont(io.BytesIO(bench._build_font(names,{97:'a',98:'b',99:'c',0x301:'acutecomb'})),recalcTimestamp=False)
 builder=FontBuilder(font=f);builder.setupVerticalMetrics({g:(700+10*i,100)for i,g in enumerate(names)});builder.setupVerticalHeader(ascent=800,descent=-200)
 addOpenTypeFeaturesFromString(f,'table GDEF { GlyphClassDef [a b c], , [acutecomb], ; } GDEF;')
 return f

def raw(f,tag,data):t=DefaultTable(tag);t.data=data;f[tag]=t

def sub(kind,body,coverage=0,tuples=0,apple=False,ot=False):
 header=6 if ot else 8 if apple else 12
 if ot:return u16(0,len(body)+header)+bytes([kind,coverage])+body
 if apple:return u32(len(body)+header)+bytes([coverage,kind])+u16(0)+body
 return u32(len(body)+header,coverage|kind,tuples)+body

def table(subtables,apple=False,ot=False,version=2,coverage=None):
 head=u16(0,len(subtables))if ot else u32(0x10000 if apple else version<<16,len(subtables))
 data=head+b''.join(subtables)
 if version>=3 and not apple and not ot:
  data+=b''.join(u32(v)for v in(coverage if coverage is not None else[0]*len(subtables)))
 return data

def save(name,data,tag='kerx',ankr=None,variable=False):
 f=base();raw(f,tag,data)
 if ankr is not None:raw(f,'ankr',ankr)
 if variable:FontBuilder(font=f).setupFvar([('wght',0,0,1,'Weight')],[])
 f.save(HERE/(name+'.ttf'))

def pairs(apple=False,ot=False,coverage=0,tuples=0,value=-51):
 wide=not(apple or ot);search=u32(1,6,0,0)if wide else u16(1,6,0,0)
 header=12 if wide else 8 if apple else 6
 offset=header+len(search)+6
 body=search+u16(1,2)+i16(offset if tuples else value)
 if tuples:body+=i16(value,*range(300,300+tuples-1))
 return sub(0,body,coverage,tuples,apple,ot)

def matrix2(apple=False,ot=False,coverage=0,tuples=0):
 ext=not(apple or ot);header=12 if ext else 8 if apple else 6;size=4 if ext else 2
 left_at=header+4*size
 left=lookup([0,2,0])if ext else u16(1,3,0,0,0)
 right_at=left_at+len(left);right=lookup([0,1,0])if ext else u16(1,3,0,2,0)
 array=right_at+len(right)
 if not ext:left=u16(1,3,array,array+4,array)
 fields=u32(4,left_at,right_at,array)if ext else u16(4,left_at,right_at,array)
 values=[0,-51,-30,0]
 if tuples:
  # Every matrix entry is an offset to a distinct tuple vector.
  vec=array+len(values)*2;cells=[];vectors=b''
  for v in values:cells.append(vec+len(vectors));vectors+=i16(v,700)
  payload=i16(*cells)+vectors
 else:payload=i16(*values)
 return sub(2,fields+left+right+payload,coverage,tuples,apple,ot)

def matrix6(long=False,coverage=0,tuples=0):
 header=12;left_at=36;left=lookup([0,2,0],width=4 if long else 2);right_at=left_at+len(left);right=lookup([0,1,0],width=4 if long else 2);array=right_at+len(right);values=[0,-51,-30,0]
 encode=i32 if long else i16
 if tuples:
  payload=encode(0,4,8,12);vector=array+len(payload);payload+=b''.join(i16(v,900)for v in values)
 else:payload=encode(*values);vector=0
 fields=u32(1 if long else 0)+u16(2,2)+u32(left_at,right_at,array,vector)
 return sub(6,fields+left+right+payload,coverage,tuples)

def machine(kind=1,action_type=2,coverage=0,tuples=0,legacy=False,apple=False,action_index=2,reset=False,epsilon=False):
 columns=8;header=8 if apple else 6 if legacy else 12
 classes=u16(1,4)+bytes([4,5,6,7])if legacy else lookup([4,5,6,7])
 machine_header=10 if legacy else 20
 class_at=machine_header;state_at=class_at+len(classes);rowbytes=columns if legacy else columns*2;entry_at=state_at+3*rowbytes
 rows=[[0]*columns for _ in range(3)];rows[0][4]=1;rows[1][4]=1;rows[2][5]=2
 if reset:rows[2][6]=3
 action_at=entry_at+(4 if reset else 3)*(4 if legacy else 6)
 if kind==4:
  entries=[(0,0,65535),(2,0x8000,65535),(0,0,0)]
  action=u16(2,0)if action_type==0 else u16(1,0)if action_type==1 else i16(400,600,50,100)
  field=(action_type<<30)|action_at
 else:
  entries=[(0,0,65535),(2,0x8000,65535),(0,0x8000|(0x4000 if epsilon else 0),action_index)]
  if reset:entries.append((0,0x2000,65535))
  action=i16(111)+i16(-20,*([500]*(max(1,tuples)-1)))+i16(-39,*([800]*(max(1,tuples)-1)))
  field=action_at
 if legacy:
  fields=u16(columns,class_at,state_at,entry_at,field)
  rowdata=b''.join(bytes(r)for r in rows)
  entrydata=b''
  for state,flags,index in entries:
   encodedflags=flags if index==65535 else flags|(action_at+action_index)
   entrydata+=u16(state_at+state*rowbytes,encodedflags)
 else:
  fields=u32(columns,class_at,state_at,entry_at,field);rowdata=b''.join(u16(*r)for r in rows);entrydata=b''.join(u16(*e)for e in entries)
 return sub(kind,fields+classes+rowdata+entrydata+action,coverage,tuples,apple=apple,ot=legacy and not apple)

def anchors():
 data=u32(2)+i16(100,200,400,600)+u32(1)+i16(50,100)
 loc=lookup([0,12]);return u16(0,0)+u32(12,12+len(loc))+loc+data

def compact(apple=True,ot=False,coverage=0):
 # Classes[a]=0,[b]=1,[c]=0,[mark]=0. Five valid glyphs.
 body=u16(5)+bytes([3,2,2,0])+i16(0,-51,-30)+bytes([0,0,1,0,0])+bytes([0,0,1,0,0])+bytes([0,1,2,0])
 return sub(3,body,coverage,apple=apple,ot=ot)

def main():
 for name,s in [('kerx0',pairs()),('kerx0-tuple',pairs(tuples=3)),('kerx0-backwards',pairs(coverage=0x10000000)),('kerx0-cross',pairs(coverage=0x40000000)),('kerx2',matrix2()),('kerx2-tuple',matrix2(tuples=2)),('kerx6',matrix6()),('kerx6-long',matrix6(True)),('kerx6-tuple',matrix6(tuples=2)),('kerx6-long-tuple',matrix6(True,tuples=2)),('kerx1',machine()),('kerx1-tuple',machine(tuples=3)),('kerx1-reset',machine(reset=True)),('kerx1-epsilon',machine(epsilon=True)),('kerx1-backwards',machine(coverage=0x10000000)),('kerx1-cross',machine(coverage=0x40000000)),('kerx4-coordinate',machine(4)),('kerx4-point',machine(4,0)),('kerx4-anchor',machine(4,1))]:save(name,table([s]),ankr=anchors()if'anchor'in name else None,variable='tuple'in name)
 for kind in [0,1,2,3]:
  s={0:lambda:pairs(apple=True),1:lambda:machine(legacy=True,apple=True),2:lambda:matrix2(apple=True),3:lambda:compact()}[kind]();save(f'apple-kern{kind}',table([s],apple=True),tag='kern')
 for kind in [0,1,2,3]:
  s={0:lambda:pairs(ot=True,coverage=1),1:lambda:machine(legacy=True,coverage=1),2:lambda:matrix2(ot=True,coverage=1),3:lambda:compact(apple=False,ot=True,coverage=1)}[kind]();save(f'ot-kern{kind}',table([s],ot=True),tag='kern')
 save('apple-variation-skipped',table([pairs(apple=True,coverage=0x20)],apple=True),tag='kern')
 save('kerx3-coverage',table([pairs()],version=3,coverage=[0xffffffff]))
 save('kerx4-tuples',table([pairs(tuples=3)],version=4))
 save('kerx-empty',table([]))
 save('kerx-unknown',table([sub(5,b'')]))
 for kind in [0,1,2,4,6]:
  s={0:lambda:pairs(coverage=0x80000000),1:lambda:machine(coverage=0x80000000),2:lambda:matrix2(coverage=0x80000000),4:lambda:machine(4,coverage=0x80000000),6:lambda:matrix6(coverage=0x80000000)}[kind]();save(f'kerx{kind}-vertical',table([s]))
 save('kerx-mixed',table([pairs(),matrix2(),machine(4),pairs(coverage=0x40000000)]))
 src=Path('/private/tmp/harfbuzz-14.6.0/test/shape/data/in-house/fonts/e39391c77a6321c2ac7a2d644de0396470cd4bfe.ttf')
 if src.is_file():
  shutil.copyfile(src,HERE/'Jellee-Roman.ttf');f=TTFont(src);(HERE/'Jellee-OFL.txt').write_text(f['name'].getDebugName(13)+'\n')
if __name__=='__main__':main()

def selection_fixtures():
 for name,features,legacy in [
  ('select-kerx-no-gsub','feature kern { pos a b -100; } kern;',False),
  ('select-gpos-with-gsub','feature calt { sub c by c; } calt; feature kern { pos a b -100; } kern;',False),
  ('select-gpos-dist-with-gsub','feature calt { sub c by c; } calt; feature dist { pos a b -100; } dist;',False),
  ('select-kerx-over-dist','feature dist { pos a b -100; } dist;',False),
  ('select-legacy-after-dist','feature dist { pos a b -100; } dist;',True),
 ]:
  f=base();addOpenTypeFeaturesFromString(f,features);raw(f,'kern'if legacy else'kerx',table([pairs(apple=legacy)],apple=legacy));f.save(HERE/f'{name}.ttf')

def variable_points():
 from fontTools.ttLib import newTable
 from fontTools.ttLib.tables.TupleVariation import TupleVariation
 f=TTFont(HERE/'kerx4-point.ttf',recalcTimestamp=False);FontBuilder(font=f).setupFvar([('wght',0,0,1,'Weight')],[])
 g=newTable('gvar');g.version=1;g.reserved=0;g.variations={'a':[TupleVariation({'wght':(0,1,1)},[None,None,(100,50),None,(-40,0),None,None,None])]};f['gvar']=g;f.save(HERE/'kerx4-point-variable.ttf')

def scaling_fonts():
 for count in [8,64,256]:
  names=['.notdef']+[f'g{i}'for i in range(1,count+1)];f=TTFont(io.BytesIO(bench._build_font(names,{97:'g1',98:f'g{count}'})),recalcTimestamp=False)
  power=count.bit_length()-1;search=u32(count,(1<<power)*6,power,count*6-(1<<power)*6)
  rows=b''.join(u16(i,count)+i16(-51)for i in range(1,count+1));raw(f,'kerx',table([sub(0,search+rows)]));f.save(HERE/f'kerx0-size-{count}.ttf')
if __name__=='__main__':selection_fixtures();variable_points();scaling_fonts()
