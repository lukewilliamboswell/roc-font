"""Original UPL raw-bounds and variable/default Graphite controls."""
import argparse,io,json,sys
from pathlib import Path
from fontTools.ttLib import TTFont,newTable
from fontTools.ttLib.tables.DefaultTable import DefaultTable
from fontTools.ttLib.tables._f_v_a_r import Axis
from fontTools.ttLib.tables.TupleVariation import TupleVariation
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent/'graphite-geometry'))
import collision_generate as collision
import generate as geometry

def make(name,metric,lsb,variable=False):
    data,_=collision.make(name,{'pass_flags':0,'flags_a':0,'flags_b':0},False)
    f=TTFont(io.BytesIO(data),recalcTimestamp=False)
    old=f.getTableData('Silf');action=geometry.NEXT+bytes([0x2a,metric,0,1,0x23,21])
    program=bytearray(geometry.program(action+bytes([0x32]),True,(1,2)))
    for a,b in [(24,26),(35,36),(48,50),(84,85)]:program[a:b]=old[a:b]
    # These metric-only fixtures have no collision stage or collision attribute.
    program[35]=0;program[49]=0
    table=DefaultTable('Silf');table.data=bytes(program);f['Silf']=table
    glyph=f.getGlyphName(2);advance,_=f['hmtx'].metrics[glyph];f['hmtx'].metrics[glyph]=(advance,lsb)
    if variable:
        a=Axis();a.axisTag='wght';a.minValue=0;a.defaultValue=0;a.maxValue=1;a.flags=0;a.axisNameID=256
        fvar=newTable('fvar');fvar.axes=[a];fvar.instances=[];f['fvar']=fvar;f['name'].setName('Weight',256,3,1,0x409)
        gvar=newTable('gvar');gvar.version=1;gvar.reserved=0;gvar.variations={};count=len(f['glyf'][glyph].coordinates)
        gvar.variations[glyph]=[TupleVariation({'wght':(0,1,1)},[(0,0)]*count+[(0,0),(200,0),(0,0),(0,0)])];f['gvar']=gvar
    out=io.BytesIO();f.save(out);return out.getvalue()

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args();raw=[];hb=[]
    def emit(path,data):
        if args.check:assert path.read_bytes()==data,path
        else:path.write_bytes(data)
    for lsb in [-100,100]:
        for metric in range(11):
            name=f'raw-bounds-lsb{lsb}-metric{metric}';emit(HERE/(name+'.ttf'),make(name,metric,lsb))
            case={'id':name,'font':name+'.ttf','text':'ab','script':'Latn','direction':'ltr','metric':metric,'glyph2':{'glyf_bbox':[0,0,300,600],'hmtx_lsb':lsb,'hmtx_advance':602}}
            hb.append({**case,'engine':'graphite2'})
            for mode in [0,6]:raw.append({**case,'id':name+'-mode'+str(mode),'face_options':mode})
    name='variable-default';emit(HERE/(name+'.ttf'),make(name,8,0,True))
    for value in [0,0.5,1]:
        for engine in ['graphite2','ot']:hb.append({'id':f'variable-{value}-{engine}','font':name+'.ttf','text':'ab','script':'Latn','direction':'ltr','engine':engine,'variations':[{'tag':'wght','value':value}]})
    for file,cases in [('raw-cases.jsonc',raw),('hb-cases.jsonc',hb)]:emit(HERE/file,(json.dumps({'schema':1,'cases':cases},indent=2)+'\n').encode())
    print('23 original fonts,44 raw cases,28 HB cases', 'reproduced'if args.check else'generated')
if __name__=='__main__':main()
