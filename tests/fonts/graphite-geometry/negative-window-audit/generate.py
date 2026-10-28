"""Original UPL negative movement-window regression; public formats only."""
import argparse,importlib.util,io,json,struct,sys
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib.tables.DefaultTable import DefaultTable
HERE=Path(__file__).resolve().parent
root=HERE.parent
sys.path.insert(0,str(root))
spec=importlib.util.spec_from_file_location('original',root/'collision_generate.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

def make():
    data,_=m.make('negative-window-three-roots',{'group_flags':[1,0,0]},True)
    f=TTFont(io.BytesIO(data),recalcTimestamp=False)
    def raw(tag,data):
     t=DefaultTable(tag);t.data=bytes(data);f[tag]=t
    a=m.geo.set_attr(21,170)+m.geo.NEXT+m.geo.set_attr(0,683)+m.geo.NEXT+m.geo.set_attr(0,1284)
    s=bytearray(m.geo.program(a+bytes([0x32]),True,(1,2,3)));s[24:26]=struct.pack('>H',3);s[48]=2;s[35]=32;s[49]=1;s[84]=1;s[137+6*3]=0;raw('Silf',s)
    g=bytearray(f.getTableData('Glat'));loc=f.getTableData('Gloc')
    for gid in range(4):
     at=struct.unpack_from('>H',loc,8+2*gid)[0];struct.pack_into('>4h',g,at+6+4+2,-1000,-1,0,1)
    raw('Glat',g)
    for gid in [2,3]:
     pen=TTGlyphPen(None);pen.moveTo((0,0));pen.lineTo((1000,0));pen.lineTo((1000,600));pen.lineTo((0,600));pen.closePath();f['glyf'][f.getGlyphName(gid)]=pen.glyph()
    # Neutralize the independently observed whole-only preload slantBox defect.
    g=bytearray(f.getTableData('Glat'));loc=bytearray(f.getTableData('Gloc'));start=struct.unpack_from('>H',loc,8)[0]
    struct.pack_into('>H',g,start,1);g[start+6:start+6]=bytes([0,255]*4)
    for at in range(10,len(loc),2):struct.pack_into('>H',loc,at,struct.unpack_from('>H',loc,at)[0]+8)
    raw('Glat',g);raw('Gloc',loc)
    out=io.BytesIO();f.save(out)
    return out.getvalue()

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    def emit(path,data):
        if args.check:assert path.read_bytes()==data,path
        else:path.write_bytes(data)
    emit(HERE/'negative-window-three.ttf',make())
    case={'id':'collision-negative-window-three-roots','font':'negative-window-audit/negative-window-three.ttf','text':'abc','script':'Arab','direction':'rtl'}
    for mode,file in [(0,'cases.jsonc'),(6,'mode6-cases.jsonc')]:emit(HERE/file,(json.dumps({'schema':1,'cases':[{**case,'face_options':mode}]},indent=2)+'\n').encode())
    print('One original negative movement-window font reproduces')
if __name__=='__main__':main()
