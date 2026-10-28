"""Original public-format preload witnesses, without engine implementation code."""
import argparse,io,json,struct,sys
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables.DefaultTable import DefaultTable
from fontTools.pens.ttGlyphPen import TTGlyphPen
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent))
import collision_generate as collision
import generate as geometry

def raw(font,tag,data):
    table=DefaultTable(tag);table.data=bytes(data);font[tag]=table

def specifications():
    yield 'whole-only',{}
    yield 'margin',{'margin':50}
    yield 'attachment',{'attachment':'forward'}
    yield 'blank-target',{'blank':2}
    yield 'blank-obstacle',{'blank':1}
    yield 'without-boxes',{'no_boxes':True}
    yield 'without-collision',{'pass_flags':0}
    yield 'without-glat',{'remove':['Glat']}
    yield 'without-gloc',{'remove':['Gloc']}
    yield 'without-glat-gloc',{'remove':['Glat','Gloc']}
    for label,gids in [('unused',[0]),('target',[2]),('obstacle',[1]),('both',[1,2])]:
        yield 'full-subbox-'+label,{'box_glyphs':gids}
    yield 'half-subbox-target',{'box_glyphs':[2],'box_value':[0,127,0,127,0,255,0,255]}
    yield 'half-subbox-obstacle',{'box_glyphs':[1],'box_value':[0,127,0,127,0,255,0,255]}
    for metric in range(11):yield 'metric-'+str(metric),{'pass_flags':0,'flags_a':0,'flags_b':0,'metric':metric}
    for attribute in range(1,17):yield 'attribute-'+str(attribute),{'pass_flags':0,'flags_a':33,'flags_b':97,'margin':50,'weight':17,'glat_attr':attribute}

def make(name,parameters):
    params={'pass_flags':1,'flags_a':0,'flags_b':1};params.update(parameters)
    data,action=collision.make(name,params,False)
    font=TTFont(io.BytesIO(data),recalcTimestamp=False)
    if 'metric'in params or 'glat_attr'in params:
        push=bytes([0x2a,params['metric'],0,1])if'metric'in params else bytes([0x29,params['glat_attr'],0])
        action=geometry.NEXT+push+bytes([0x23,21])
        old=font.getTableData('Silf');program=bytearray(geometry.program(action+bytes([0x32]),True,(1,2)))
        for a,b in [(24,26),(35,36),(48,50),(84,85)]:program[a:b]=old[a:b]
        raw(font,'Silf',program)
    if 'box_glyphs'in params:
        old=font.getTableData('Glat');loc=font.getTableData('Gloc');pool=bytearray(old[:8]);offsets=[]
        for gid in range(len(font.getGlyphOrder())):
            offsets.append(len(pool));a,b=struct.unpack_from('>HH',loc,8+2*gid);entry=old[a:b]
            if gid in params['box_glyphs']:entry=struct.pack('>H',1)+entry[2:6]+bytes(params.get('box_value',[0,255,0,255,0,255,0,255]))+entry[6:]
            pool.extend(entry)
        offsets.append(len(pool));raw(font,'Glat',pool);raw(font,'Gloc',loc[:8]+struct.pack('>'+'H'*len(offsets),*offsets))
    if 'blank'in params:font['glyf'][font.getGlyphName(params['blank'])]=TTGlyphPen(None).glyph()
    for tag in params.get('remove',[]):del font[tag]
    out=io.BytesIO();font.save(out,reorderTables=True)
    return out.getvalue(),list(action)

def main():
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args();cases=[]
    def emit(path,data):
        if args.check:assert path.read_bytes()==data,path
        else:path.write_bytes(data)
    for label,params in specifications():
        name='collision-preload-'+label;data,action=make(name,params);emit(HERE/(name+'.ttf'),data)
        for mode in [0,2,4,6]:cases.append({'id':name+'-mode'+str(mode),'font':'preload-audit/'+name+'.ttf','text':'ab','direction':'ltr','face_options':mode,'parameters':params,'action':action})
    real=[
        ('charis/text-5/ltr/clusters-0','Charis5_eursub.ttf','a\u0301','ltr'),
        ('charis/text-19/ltr/clusters-0','Charis5_eursub.ttf','a\u0301'*129,'ltr'),
        ('padauk/text-4/ltr/clusters-0','Padauk.ttf','မြန်မာ','ltr'),
        ('padauk/text-4/rtl/clusters-0','Padauk.ttf','မြန်မာ','rtl'),
        ('padauk/text-6/ltr/clusters-0','Padauk.ttf','ေက','ltr'),
        ('scheherazade/text-6/rtl/clusters-0','Scheherazadegr.ttf','اللَّه','rtl'),
        ('scheherazade/text-12/ltr/clusters-0','Scheherazadegr.ttf','اَّ','ltr'),
        ('scheherazade/text-15/ltr/clusters-0','Scheherazadegr.ttf','ؐبَّ','ltr'),
        ('awami/text-1/ltr/clusters-0','AwamiNastaliq-Regular.ttf','([])','ltr'),
        ('awami/text-3/ltr/clusters-0','AwamiNastaliq-Regular.ttf','سلام','ltr'),
        ('awami/text-3/rtl/clusters-0','AwamiNastaliq-Regular.ttf','سلام','rtl'),
        ('awami/text-6/ltr/clusters-0','AwamiNastaliq-Regular.ttf','اللَّه','ltr'),
        ('awami/extra-long','AwamiNastaliq-Regular.ttf','بسم الله الرحمن الرحيم','rtl'),
    ]
    for source,font,text,direction in real:
        for mode in [0,2,4,6]:cases.append({'id':'collision-preload-real-'+source.replace('/','-')+'-mode'+str(mode),'font':'../graphite/'+font,'text':text,'direction':direction,'face_options':mode,'source_case':source,'control':'Unmodified real SIL font; existing font and license, not redistributed again. Raw UTF32 direct C API, without the HB normalization/cluster adapter.'})
    emit(HERE/'cases.jsonc',(json.dumps({'schema':1,'about':'Reference face modes are intentional semantic inputs; these are not a single package-output conformance gate.','cases':cases},indent=2,ensure_ascii=False)+'\n').encode())
    print(len(cases),'preload cases reproduced'if args.check else'preload cases generated')
if __name__=='__main__':main()
