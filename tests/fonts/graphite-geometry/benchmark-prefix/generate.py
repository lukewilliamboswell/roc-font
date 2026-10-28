"""Original UPL attachment SHIFT witness whose root advance really changes."""
import argparse, importlib.util, io, json, struct, sys
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables.DefaultTable import DefaultTable
from fontTools.pens.ttGlyphPen import TTGlyphPen
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent))
spec=importlib.util.spec_from_file_location('original_collision',HERE.parent/'collision_generate.py')
base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base)

def raw(font,tag,data):
    table=DefaultTable(tag);table.data=bytes(data);font[tag]=table

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    data,_=base.make('OriginalPrefixChanging',{'group_flags':[0,1,0],'attachment':'forward','axis':'positive-x','limit':1000,'pass_flags':1},True)
    font=TTFont(io.BytesIO(data),recalcTimestamp=False)
    font['hmtx'][font.getGlyphName(1)]=(2500,0)
    pen=TTGlyphPen(None);pen.moveTo((0,0));pen.lineTo((1000,0));pen.lineTo((1000,600));pen.lineTo((0,600));pen.closePath();font['glyf'][font.getGlyphName(3)]=pen.glyph()
    original=font.getTableData('Glat');loc=font.getTableData('Gloc');pool=bytearray(original[:8]);offsets=[]
    for gid in range(font['maxp'].numGlyphs):
        offsets.append(len(pool));start,end=struct.unpack_from('>HH',loc,8+2*gid);entry=bytearray(original[start:end])
        if gid==2:
            struct.pack_into('>h',entry,14,-1);struct.pack_into('>h',entry,18,1)
        if gid==0:entry=b'\0\1'+entry[2:6]+bytes([0,255,0,255,0,255,0,255])+entry[6:]
        pool.extend(entry)
    offsets.append(len(pool));raw(font,'Glat',pool);raw(font,'Gloc',loc[:8]+struct.pack('>'+'H'*len(offsets),*offsets))
    output=io.BytesIO();font.save(output,reorderTables=True)
    def emit(path,data):
        if args.check:assert path.read_bytes()==data,path
        else:path.write_bytes(data)
    emit(HERE/'prefix-changing.ttf',output.getvalue())
    cases=[{'id':f'geometry-benchmark-prefix-changing-{n}','font':'benchmark-prefix/prefix-changing.ttf','text':'abc'*n,'script':'Arab','direction':'rtl','copies':n}for n in [4,8,16]]
    emit(HERE/'cases.jsonc',(json.dumps({'schema':1,'cases':cases},indent=2)+'\n').encode())
    print('One original prefix-changing SHIFT font and three cases reproduce')
if __name__=='__main__':main()
