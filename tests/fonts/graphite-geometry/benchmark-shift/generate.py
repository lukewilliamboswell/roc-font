"""Original UPL four-subbox collision-shifting scaling control."""
import argparse
import importlib.util
import io
import json
from pathlib import Path
import struct
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables.DefaultTable import DefaultTable
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('original_parts',HERE.parent/'kern-parts/generate.py')
parts=importlib.util.module_from_spec(spec);spec.loader.exec_module(parts)

def raw(font,tag,data):
    table=DefaultTable(tag);table.data=bytes(data);font[tag]=table

def main():
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args()
    data,_=parts.make('geometry-bench-shifting-parts',True,{1:[parts.PARTS['full'][0]]*4,2:[parts.PARTS['full'][0]]*4})
    font=TTFont(io.BytesIO(data),recalcTimestamp=False)
    silf=bytearray(font.getTableData('Silf'));silf[84]=1;raw(font,'Silf',silf)
    glat=bytearray(font.getTableData('Glat'));gloc=font.getTableData('Gloc');starts=struct.unpack_from('>4H',gloc,8)
    struct.pack_into('>h',glat,starts[1]+6+4*8+4,1);raw(font,'Glat',glat)
    out=io.BytesIO();font.save(out,reorderTables=True);path=HERE/'shifting-parts.ttf'
    if args.check:assert path.read_bytes()==out.getvalue()
    else:path.write_bytes(out.getvalue())
    cases=[{'id':f'geometry-benchmark-shifting-parts-{n}','font':'benchmark-shift/shifting-parts.ttf','text':'ab'*n,'direction':'rtl','script':'Arab','copies':n}for n in [4,8,16]]
    text=json.dumps({'schema':1,'cases':cases},indent=2)+'\n';path=HERE/'cases.jsonc'
    if args.check:assert path.read_text()==text
    else:path.write_text(text)
    print('One original shifting font and three scaling cases reproduce')
if __name__=='__main__':main()
