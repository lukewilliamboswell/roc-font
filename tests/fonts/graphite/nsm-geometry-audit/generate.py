"""Original UPL NSM no-op geometry controls, from public GTF/OpCodes only."""
import argparse,io,json,struct
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables.DefaultTable import DefaultTable
HERE=Path(__file__).resolve().parent
u16=lambda v:struct.pack('>H',v)
u32=lambda v:struct.pack('>I',v)
def raw(font,tag,data):
 table=DefaultTable(tag);table.data=data;font[tag]=table
def program(action,positioning=False,match=(1,),constraint=b'',pass_constraint=b'',j_levels=(),version=0x30000):
 # Original DFA for one exact glyph sequence and one output class [gid2].
 classes=(u16(1)+u16(1)+u32(12)+u32(14)+u16(2)) if version>=0x40000 else (u16(1)+u16(1)+u16(8)+u16(10)+u16(2))
 levels=b''.join(bytes(level) for level in j_levels)
 pass_start=58+len(levels)+len(classes)
 glyphs=sorted(set(match));columns={g:i for i,g in enumerate(glyphs)}
 ranges=b''.join(u16(g)+u16(g)+u16(columns[g]) for g in glyphs)
 count=len(glyphs);power=1<<(count.bit_length()-1)
 transitions=b''.join(u16(i+1 if g==wanted else 0) for i,wanted in enumerate(match) for g in glyphs)
 fsm=(u16(len(match)+1)+u16(len(match))+u16(1)+u16(count)+u16(count)
      +u16(power*6)+u16(power.bit_length()-1)+u16(count*6-power*6)
      +ranges+u16(0)+u16(1)+u16(0)+bytes([0,0])+u16(0)
      +u16(len(match))+bytes([0,0])+u16(len(pass_constraint))+u16(1 if constraint else 0)+u16(1+len(constraint) if constraint else 0)
      +u16(0)+u16(len(action))+transitions+bytes([0]))
 code_at=pass_start+24+len(fsm)
 raw_constraint=(bytes([0])+constraint) if constraint else b''
 pass_data=(bytes([0,10,len(match),0])+u16(1)+u16(24)+u32(code_at)
            +u32(code_at+len(pass_constraint))+u32(code_at+len(pass_constraint)+len(raw_constraint))
            +u32(0)+fsm+pass_constraint+raw_constraint+action)
 sub=(u32(0x30000)+u16(42+len(levels))+u16(50+len(levels))+u16(2)+u16(0)+u16(0)
      +bytes([1,0,0 if positioning else 1,1,255,0,0,0,0,0,0,0,0,len(j_levels)])
      +levels
      +u16(0)+bytes([0,1,1,0,0,0,0,0,0,0])+u16(0)
      +u32(pass_start)+u32(pass_start+len(pass_data))+u16(0)*4+classes+pass_data)
 assert len(sub)==pass_start+len(pass_data),(len(sub),pass_start,len(pass_data))
 return u32(version)+u32(0x30000)+u16(1)+u16(0)+u32(16)+sub

def main():
 p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args();cases=[];raw_cases=[]
 def emit(path,data):
  if args.check:assert path.read_bytes()==data,path
  else:path.write_bytes(data)
 for reverse in [0,32]:
  for aa,bb in [(601,0),(601,20),(601,602),(0,20)]:
   name=f'nsm-noop-{reverse}-{aa}-{bb}';f=TTFont(HERE.parent/'replace.ttf',recalcTimestamp=False);f['hmtx']['a']=(aa,0);f['hmtx']['b']=(bb,0)
   data=bytearray(program(bytes([0x1b,0x31]),version=0x50000));data[48]=2;data[40]=1;data[88]=reverse;data[90]=16;data[91]=16
   raw(f,'Silf',bytes(data));raw(f,'Gloc',u32(0x10000)+u16(0)+u16(2)+b''.join(u16(n)for n in [4,8,12,16]));raw(f,'Glat',u32(0x10000)+b''.join(bytes([1,1])+struct.pack('>h',n)for n in [0,3,16]));out=io.BytesIO();f.save(out,reorderTables=True);emit(HERE/(name+'.ttf'),out.getvalue())
   for text in ['ab','aab','abb','ba','bab','bb','a']:
    ident=f'{name}/{text}';cases.append({'id':ident,'font':name+'.ttf','text':text,'script':'Latn','direction':'ltr','cluster_level':1,'engine':'graphite2','recipe':{'pass_flags':reverse,'advance_a':aa,'advance_b':bb}})
    raw_cases.append({'id':ident,'font':name+'.ttf','text':text,'direction':'ltr','face_options':6})
 emit(HERE/'cases.jsonc',(json.dumps({'cases':cases},indent=2)+'\n').encode());emit(HERE/'raw-cases.jsonc',(json.dumps({'cases':raw_cases},indent=2)+'\n').encode());print('8 original fonts and56 NSM geometry cases current')
if __name__=='__main__':main()
