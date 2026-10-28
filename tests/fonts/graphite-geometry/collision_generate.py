"""Original collision programs for public-C-API black-box experiments."""
from pathlib import Path
import argparse,io,json,struct
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables.DefaultTable import DefaultTable
from fontTools.pens.ttGlyphPen import TTGlyphPen
import generate as geo
HERE=Path(__file__).resolve().parent

def parameters():
 for distance in [0,50,100,200,299,300,301,500,601]:
  yield f'distance-{distance}',{'distance':distance}
 for limit in [0,1,100,199,200,201,500,1000]:
  yield f'limit-{limit}',{'limit':limit}
 for margin in [0,1,10,50,100,200]:
  for weight in [0,1,10,100]:
   yield f'margin-{margin}-weight-{weight}',{'margin':margin,'weight':weight}
 for axis in ['x','y','positive-x','negative-x','positive-y','negative-y']:
  yield 'axis-'+axis,{'axis':axis}
 for dx,dy in [(0,100),(0,500),(100,100),(100,500),(250,500),(-100,100)]:
  yield f'origin-{dx}-{dy}',{'shift_x':dx,'shift_y':dy}
 for a,b in [(0,1),(1,1),(2,1),(4,1),(8,1),(0,5),(0,9),(0,3),(0,0),(0,17),(0,129)]:
  yield f'flags-{a}-{b}',{'flags_a':a,'flags_b':b}
 for rounds in [0,1,2,3,7]:
  yield 'rounds-'+str(rounds),{'pass_flags':rounds}
 for rounds in [2,3,7]:
  yield f'blocked-rounds-{rounds}',{'limit':100,'pass_flags':rounds}
 for kern in [8,16,24]:
  yield 'kern-'+str(kern),{'pass_flags':1|kern,'flags_a':16,'flags_b':0}
 for ma,mb,wa,wb in [(50,0,10,0),(0,50,0,10),(50,100,1,10),(100,50,10,1),(0,50,10,0),(50,0,0,10)]:
  yield f'margin-owner-{ma}-{mb}-{wa}-{wb}',{'margin_a':ma,'margin_b':mb,'weight_a':wa,'weight_b':wb}
 for second in ['repeat','reveal','position','metric-left','metric-right','metric-advance']:
  yield 'second-pass-'+second,{'margin':50,'weight':10,'second':second}
 for a,b in [(17,0),(0,17),(17,17),(16,16)]:
  for margin in [0,10,50,100]:
   yield f'kern-fix-{a}-{b}-margin-{margin}',{'pass_flags':9,'flags_a':a,'flags_b':b,'margin':margin}
 for flags in [[0,1,0,0],[8,5,0,0],[8,1,0,0],[0,5,0,0],[0,9,4,0],[0,9,0,0],[8,13,4,0],[12,13,12,8]]:
  yield 'groups-'+'-'.join(map(str,flags)),{'group_flags':flags}
 for attachment in ['forward','backward']:
  for a,b in [(0,1),(1,0),(1,1)]:
   yield f'attached-{attachment}-{a}-{b}',{'attachment':attachment,'flags_a':a,'flags_b':b}
 for prefix in [0,1,511,512,513]:
  for shift in [0,1]:
   yield f'parent-float-{prefix}-{shift}',{'prefix_count':prefix,'parent_shift':shift,'margin':50,'weight':10}
 for diagonal in [[0,127,0,255],[0,255,127,255],[0,127,0,127],[127,255,0,255]]:
  for y in [0,500]:
   yield 'diagonal-'+'-'.join(map(str,diagonal))+f'-y{y}',{'diagonal':diagonal,'shift_y':y}
 for width,edge in [(300,127),(3,1)]:
  for diagonal_max in [127,255]:
   yield f'subbox-width{width}-edge{edge}-diag{diagonal_max}',{'glyph_width':width,'distance':0,'subboxes':[[0,edge,0,127,0,diagonal_max,0,255]]}
 for threshold in [0,1,10,100,255]:
  yield 'threshold-'+str(threshold),{'threshold':threshold}

def make(name,params,rtl):
 count=params.get('glyph_count',2)
 if params.get('prefix_count')is not None:count=3
 if 'group_flags'in params:count=len(params['group_flags'])
 match=(1,2)if params.get('prefix_count')is not None else tuple(range(1,count+1))
 distance=params.get('distance',100)
 action=(geo.NEXT if rtl else b'')+geo.set_attr(0,distance)
 action+=(b''if rtl else geo.NEXT)+geo.set_attr(20,params.get('shift_x',0))+geo.set_attr(21,params.get('shift_y',0))
 if 'group_flags'in params:
  action=b''.join(geo.set_attr(0,distance)+geo.NEXT for _ in range(count-1))
 if params.get('attachment'):
  action=(geo.NEXT+geo.attach(-1))if params['attachment']=='backward'else geo.BASE
 if params.get('prefix_count')is not None:
  action=bytes([1,1,0x26,2])+geo.set_attr(3,5)+geo.set_attr(8,0)+geo.set_attr(4,170)+geo.NEXT+geo.set_attr(20,params.get('parent_shift',0))
 font=TTFont(io.BytesIO(geo.font(name,action,True,False,count,rtl)),recalcTimestamp=False)
 if 'glyph_width'in params:
  for name in font.getGlyphOrder():
   pen=TTGlyphPen(None);pen.moveTo((0,0));pen.lineTo((params['glyph_width'],0));pen.lineTo((params['glyph_width'],600));pen.lineTo((0,600));pen.closePath();font['glyf'][name]=pen.glyph()
 if params.get('prefix_count')is not None:font['hmtx']['c']=(32768,0)
 silf=bytearray(geo.program(action+bytes([0x32]),True,match));silf[24:26]=struct.pack('>H',count);silf[48]=2 if rtl else 1
 silf[35]=32;silf[49]=1;silf[84]=params.get('pass_flags',1);silf[137+6*len(set(match))]=params.get('threshold',0)
 def raw(tag,data):t=DefaultTable(tag);t.data=data;font[tag]=t
 raw('Silf',bytes(silf))
 limit=params.get('limit',1000);xlo=ylo=-limit;xhi=yhi=limit;axis=params.get('axis','both')
 if axis=='x':ylo=yhi=0
 if axis=='y':xlo=xhi=0
 if axis=='positive-x':xlo=ylo=yhi=0
 if axis=='negative-x':xhi=ylo=yhi=0
 if axis=='positive-y':xlo=xhi=ylo=0
 if axis=='negative-y':xlo=xhi=yhi=0
 version=params.get('box_format',3);boxes=not params.get('no_boxes',False)
 data=struct.pack('>II',196608,1 if boxes else 0)if version==3 else struct.pack('>I',version<<16);offsets=[]
 for glyph in range(count+1):
  flags=params.get('flags_b',1)if glyph==2 else params.get('flags_a',0)
  if 'group_flags'in params:flags=params['group_flags'][glyph-1]if glyph else 0
  if params.get('prefix_count')is not None and glyph==3:flags=2
  values=[flags,xlo,ylo,xhi,yhi,params.get('margin_b'if glyph==2 else'margin_a',params.get('margin',0)),params.get('weight_b'if glyph==2 else'weight_a',params.get('weight',10)),0,0,0,0,0,0,0,0,0]
  offsets.append(len(data))
  if boxes:
   subboxes=params.get('subboxes',[]);bitmap=params.get('bitmap',(1<<len(subboxes))-1)
   data+=struct.pack('>H',bitmap)+bytes(params.get('diagonal',[0,255,0,255]))+b''.join(bytes(subbox)for subbox in subboxes)
  data+=(bytes([1,16])if version==1 else struct.pack('>HH',1,16))+struct.pack('>16h',*values)
 offsets.append(len(data));raw('Glat',data);raw('Gloc',struct.pack('>IHH',65536,0,17)+b''.join(struct.pack('>H',v)for v in offsets))
 if params.get('second'):
  one=font.getTableData('Silf');first=one[84:];mode=params['second']
  if mode=='repeat':second_action=action
  elif mode=='reveal':second_action=geo.set_attr(0,0)
  elif mode=='position':second_action=geo.NEXT+bytes([0x28,18,0,0x23,21])
  else:
   metric={'metric-left':4,'metric-right':5,'metric-advance':8}[mode];second_action=geo.NEXT+bytes([0x2a,metric,0,1,0x23,21])
  second=bytearray(geo.program(second_action+bytes([0x32]),True,match)[84:]);second[0]=params.get('pass_flags',1)if mode=='repeat'else 0
  def relocate(body,delta):
   data=bytearray(body)
   for at in [8,12,16]:struct.pack_into('>I',data,at,struct.unpack_from('>I',data,at)[0]+delta)
   return bytes(data)
  header=bytearray(one[:58]);header[30]=header[33]=2;struct.pack_into('>H',header,22,54)
  raw('Silf',bytes(header)+struct.pack('>III',72,72+len(first),72+len(first)+len(second))+one[66:84]+relocate(first,4)+relocate(second,4+len(first)))
 out=io.BytesIO();font.save(out,reorderTables=True);return out.getvalue(),action

def main():
 p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args();cases=[]
 for label,params in parameters():
  for rtl in [False,True]:
   name='collision-solver-'+label+('-rtl'if rtl else'-ltr');data,action=make(name,params,rtl);path=HERE/(name+'.ttf')
   if args.check:assert path.read_bytes()==data,path
   else:path.write_bytes(data)
   text=''.join(chr(97+i)for i in range(params.get('glyph_count',len(params.get('group_flags',[0,0])))))
   if params.get('prefix_count')is not None:text=('ab'+'c'*params['prefix_count'])if rtl else('c'*params['prefix_count']+'ab')
   cases.append({'id':name,'font':path.name,'text':text,'direction':'rtl'if rtl else'ltr','positioning':True,'precontext':0,'action':list(action),'collision':params})
 output=json.dumps({'schema':1,'cases':cases},indent=2)+'\n';path=HERE/'collision-cases.jsonc'
 if args.check:assert path.read_text()==output,path
 else:path.write_text(output)
 invalid=[]
 for version in [1,2,3]:
  for flags in [0,1,8,16,24,32,33]:
   name=f'collision-box-dependency-v{version}-flags{flags}';params={'box_format':version,'no_boxes':True,'pass_flags':flags};data,action=make(name,params,False);path=HERE/(name+'.ttf')
   if args.check:assert path.read_bytes()==data,path
   else:path.write_bytes(data)
   invalid.append({'id':name,'font':path.name,'text':'ab','direction':'ltr','positioning':True,'precontext':0,'action':list(action),'collision':params})
 invalid_output=json.dumps({'schema':1,'cases':invalid},indent=2)+'\n';path=HERE/'collision-box-cases.jsonc'
 if args.check:assert path.read_text()==invalid_output,path
 else:path.write_text(invalid_output)
 print(len(invalid),'collision box-dependency controls')
 print(len(cases),'original collision fonts '+('reproduced'if args.check else'generated'))

if __name__=='__main__':main()
