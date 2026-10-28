"""Original UPL scan-cell/facet witnesses, from public formats and API only."""
import argparse,importlib.util,io,json,struct
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('original_kernel_builder',HERE.parent/'kerning-audit/generate.py');base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base)

def recipes():
    def r(name,h=10,qs=255,qd=255,margin=10,ty=0,ny=0,nx=0,w=300,th=None,part=None,shift_x=0,shift_y=0,distance=100,purpose='facet selection'):
        return {'name':name,'target':[0,ty,300,ty+(h if th is None else th)],'neighbor':[nx,ny,nx+w,ny+h],'margin':margin,'diagonal':[0,qs,0,qd],'part':part,'shift_x':shift_x,'shift_y':shift_y,'distance':distance,'purpose':purpose}
    full=[0,255,0,255,0,255,0,255]
    yield r('whole-height1',h=1,purpose='whole first cell seeds horizontal bound')
    yield r('part-height1',h=1,part=full,purpose='geometrically identical actual part also seeds')
    yield r('whole-formal-height1',h=1,qs=127,purpose='formal upper SUM remains active')
    yield r('part-formal-height1',h=1,part=[0,255,0,255,0,127,0,255],purpose='actual part formal control')
    yield r('fractional-part-formal',h=3,w=137,margin=101,ty=53,ny=40,th=40,shift_y=11,part=[17,249,23,247,0,247,0,255],purpose='part-bounds proxy fails; actual diagonal corner is used')
    yield r('fractional-part-seeded',h=1,w=300,margin=17,ny=-9,nx=-30000,th=40,shift_y=11,part=[0,253,1,255,0,250,0,255],purpose='nonempty fractional part seeds and retains fractional x cap')
    yield r('shifted-neighbor5',h=1,ny=5,th=10,purpose='cell2 formal control')
    yield r('shifted-neighbor6',h=1,ny=6,th=10,purpose='cell2 seeded control')
    yield r('lower-diff-cut',qd=247,purpose='lower DIFF remains active')
    yield r('combined-245-253',qs=245,qd=253,purpose='SUM-DIFF corner rejects whole-bounds proxy')
    yield r('combined-245-251',qs=245,qd=251,purpose='both facets cut with distinct output')
    yield r('combined-part',part=[0,255,0,255,0,245,0,253],purpose='combined cuts in actual part')
    yield r('later-cell3',h=100,qs=200,qd=245,purpose='center facet choice applies beyond first cell')
    yield r('later-cell46',h=600,qs=128,qd=128,purpose='later diagonal vertex has no horizontal cap')
    yield r('later-cell20',h=600,qs=132,qd=208,margin=13,purpose='later diagonal vertex with horizontal cap')
    yield r('equality-margin101',h=10,margin=101,ny=-6,th=40,purpose='2*low+width association is rejected')
    yield r('equality-margin13',h=2,margin=13,ny=-2,th=40,purpose='independent equality margin control')
    yield r('translated-midpoint32000',h=201,w=200,margin=101,ty=32000,ny=32100,nx=1000,th=400,qs=170,distance=1200,purpose='normalized midpoint rejected by exact needed101')
    yield r('translated-midpoint31900',h=201,w=200,margin=101,ty=31900,ny=32000,nx=2000,th=400,qs=170,distance=2200,purpose='translated equality replication')
    yield r('fractional85',h=604,w=202,margin=101,ny=33,th=1000,qs=85,purpose='same right facets as q170 with different raw normalization')
    yield r('fractional170',h=201,w=202,margin=101,ny=33,th=1000,qs=170,purpose='same right facets as q85')
    yield r('recurrence-unresolved',h=606,w=202,margin=101,ty=-31,ny=69,th=1000,qs=85,purpose='retains unresolved later-sample F32 association evidence')
    yield r('sum245-formal',qs=245,purpose='upper SUM threshold below seed')
    yield r('sum246-seeded',qs=246,purpose='upper SUM threshold above seed')

def make(recipe):
    data,programs=base.make('OriginalCell-'+recipe['name'],{'pass_flags':9,'flags_a':17,'flags_b':0,'margin':recipe['margin'],'distance':recipe['distance'],'shift_x':recipe['shift_x'],'shift_y':recipe['shift_y'],'diagonals':{2:recipe['diagonal']}},True)
    font=TTFont(io.BytesIO(data),recalcTimestamp=False)
    for gid,box in [(1,recipe['target']),(2,recipe['neighbor'])]:
        x0,y0,x1,y1=box;pen=TTGlyphPen(None);pen.moveTo((x0,y0));pen.lineTo((x1,y0));pen.lineTo((x1,y1));pen.lineTo((x0,y1));pen.closePath();font['glyf'][font.getGlyphName(gid)]=pen.glyph()
    old=font.getTableData('Glat');loc=font.getTableData('Gloc');pool=bytearray(old[:8]);offsets=[]
    for gid in range(font['maxp'].numGlyphs):
        offsets.append(len(pool));a,b=struct.unpack_from('>HH',loc,8+2*gid);entry=old[a:b]
        part=[0,255,0,255,0,255,0,255]if gid==0 else recipe['part']if gid==2 else None
        if part is not None:entry=b'\0\1'+entry[2:6]+bytes(part)+entry[6:]
        pool.extend(entry)
    offsets.append(len(pool));base.raw(font,'Glat',pool);base.raw(font,'Gloc',loc[:8]+struct.pack('>'+'H'*len(offsets),*offsets));out=io.BytesIO();font.save(out,reorderTables=True)
    return out.getvalue(),programs

def main():
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args();cases=[]
    def emit(path,data):
        if args.check:assert path.read_bytes()==data,path
        else:path.write_bytes(data)
    for recipe in recipes():
        name='collision-cell-'+recipe['name'];data,programs=make(recipe);emit(HERE/(name+'.ttf'),data)
        cases.append({'id':name,'font':'first-cell-audit/'+name+'.ttf','text':'ab','direction':'rtl','positioning':True,'precontext':0,'face_options':0,'recipe':recipe,'programs':[list(p)for p in programs]})
    emit(HERE/'cases.jsonc',(json.dumps({'schema':1,'about':'Original per-cell facet-selection and numerical association observations; no runtime exception or generated Roc expected source.','cases':cases},indent=2)+'\n').encode())
    emit(HERE/'mode6-cases.jsonc',(json.dumps({'schema':1,'cases':[{**c,'face_options':6}for c in cases]},indent=2)+'\n').encode())
    print(len(cases),'original scan-cell cases reproduced'if args.check else'original scan-cell cases generated')
if __name__=='__main__':main()
