"""Original UPL same-root sequence collection scaling witness."""
import argparse,importlib.util,io,json,struct
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables.DefaultTable import DefaultTable
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('original_sequence',HERE.parent/'sequencing-audit/generate.py');seq=importlib.util.module_from_spec(spec);spec.loader.exec_module(seq)
def raw(font,tag,data):
 t=DefaultTable(tag);t.data=bytes(data);font[tag]=t

def main():
 p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args()
 data,_=seq.make('geometry-bench-sequence-members',{'classes':[0,1,0]},True)
 font=TTFont(io.BytesIO(data),recalcTimestamp=False);glat=bytearray(font.getTableData('Glat'));gloc=font.getTableData('Gloc');old=struct.unpack_from('>4H',gloc,8)
 struct.pack_into('>h',glat,old[1]+6+4,2)
 made=bytearray(glat[:8]);offsets=[]
 for gid in range(3):
  offsets.append(len(made));piece=glat[old[gid]:old[gid+1]]
  if gid==0:piece=struct.pack('>H',1)+piece[2:6]+bytes([0,255,0,255,0,255,0,255])+piece[6:]
  made+=piece
 offsets.append(len(made));raw(font,'Glat',made);raw(font,'Gloc',gloc[:8]+struct.pack('>4H',*offsets));out=io.BytesIO();font.save(out,reorderTables=True)
 path=HERE/'sequence-members.ttf'
 if args.check:assert path.read_bytes()==out.getvalue()
 else:path.write_bytes(out.getvalue())
 cases=[{'id':f'geometry-benchmark-sequence-members-{n}','font':'benchmark-sequence/sequence-members.ttf','text':'ab'*n,'direction':'rtl','script':'Arab','copies':n}for n in [4,8,16]]
 text=json.dumps({'schema':1,'cases':cases},indent=2)+'\n';path=HERE/'cases.jsonc'
 if args.check:assert path.read_text()==text
 else:path.write_text(text)
 print('One original sequence font and three scaling cases reproduce')
if __name__=='__main__':main()
