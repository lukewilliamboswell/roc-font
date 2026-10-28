"""Original deletion/association witnesses, independent of implementation code."""
from pathlib import Path
import argparse, io, runpy
from fontTools.ttLib import TTFont
HERE=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args()
m=runpy.run_path(str(HERE/'generate.py'))
programs={
 'delete-a':((1,),[0x20,0x19,0x32]),
 'delete-b':((2,),[0x20,0x19,0x32]),
 'delete-explicit':((1,2),[0x21,2,0,1,0x19,0x20,0x19,0x31]),
 'delete-clone-left':((1,2),[0x1f,0x1e,1,0x19,0x19,0x20,0x19,0x31]),
 'delete-clone-right':((1,2,1),[0x19,0x20,0x19,0x1f,0x1e,1,0x19,0x31]),
}
for name,(match,actions) in programs.items():
 font=TTFont(HERE/'replace.ttf');font.recalcTimestamp=False
 m['raw'](font,'Silf',m['program'](bytes(actions),match=match))
 out=io.BytesIO();font.save(out,reorderTables=True);target=HERE/(name+'.ttf')
 if args.check:assert target.read_bytes()==out.getvalue(),target
 else:target.write_bytes(out.getvalue())
print('5 original association controls current')
