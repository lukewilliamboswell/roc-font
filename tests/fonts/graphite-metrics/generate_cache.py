"""Original UPL isolation of the final short-hmtx reference edge case."""
import argparse,io,json,struct,sys
from pathlib import Path
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.t2CharStringPen import T2CharStringPen
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables.DefaultTable import DefaultTable
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent/'graphite-geometry'));import generate as original
ORDER=['.notdef','a','b','c']

def set_raw(font,tag,data):
    table=DefaultTable(tag);table.data=data;font[tag]=table

def make(name,cff,long,padding=0,glyf=False,metric=None):
    donor=TTFont(io.BytesIO(original.font('OriginalShortMetricDonor',b'',True,False,3,False)),recalcTimestamp=False)
    if glyf:f=donor
    else:
        fb=FontBuilder(1000,isTTF=False);fb.setupGlyphOrder(ORDER);fb.setupCharacterMap({0xE000+i:g for i,g in enumerate(ORDER)});fb.setupHorizontalMetrics({g:(600,0)for g in ORDER});fb.setupHorizontalHeader(ascent=800,descent=-200)
        fb.setupNameTable({'familyName':name,'styleName':'Regular','psName':name,'fullName':name});fb.setupOS2(sTypoAscender=800,sTypoDescender=-200,usWinAscent=800,usWinDescent=200);fb.setupPost();strings={}
        for glyph in ORDER:
            pen=T2CharStringPen(600,None);pen.moveTo((0,0));pen.lineTo((300,0));pen.lineTo((300,600));pen.lineTo((0,600));pen.closePath();strings[glyph]=pen.getCharString()
        fb.setupCFF(name,{'FullName':name,'FamilyName':name,'FontBBox':[0,0,300,600]},strings,{});f=fb.font
        for tag in ['Silf','Glat','Gloc','Feat','Sill']:
            if tag in donor:set_raw(f,tag,donor.getTableData(tag))
        if not cff:del f['CFF ']
    f.recalcBBoxes=False;f.recalcTimestamp=False;f['head'].created=f['head'].modified=2082844800
    for table in f['cmap'].tables:
        if table.isUnicode():table.cmap={0xE000+i:g for i,g in enumerate(f.getGlyphOrder())}
    if not glyf:set_raw(f,'maxp',struct.pack('>IH',0x10000,4)+bytes(26))
    if metric is not None:
        old=f.getTableData('Silf');program=bytearray(original.program(bytes([0x2a,metric,0,0,0x23,21,0x32]),True,(3,)))
        for a,b in [(24,26),(35,36),(48,50),(84,85)]:program[a:b]=old[a:b]
        set_raw(f,'Silf',bytes(program))
    f['hhea'].numberOfHMetrics=long
    set_raw(f,'hmtx',(struct.pack('>Hh',600,0)*4 if long==4 else struct.pack('>Hh',600,0)+struct.pack('>hhh',0,0,0))+bytes(padding))
    out=io.BytesIO();f.save(out);return out.getvalue()

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args();cases=[]
    def emit(path,data):
        if args.check:assert path.read_bytes()==data,path
        else:path.write_bytes(data)
    for cff in [False,True]:
        for long in [1,4]:
            name=f'cache-cff{int(cff)}-long{long}';emit(HERE/(name+'.otf'),make(name,cff,long))
            for gid in range(4):cases.append({'id':name+'-glyph'+str(gid),'font':name+'.otf','text':chr(0xE000+gid),'script':'Latn','direction':'ltr','engine':'graphite2','expected_glyph':gid,'cff':cff,'long_metric_count':long,'padding':0,'category':'header/outline diagnostic; isolate cache metrics'})
    for name,glyf in [('cache-neither-padding1',False),('cache-glyf-padding0',True),('cache-glyf-padding1',True)]:
        padding=int(name[-1]);emit(HERE/(name+'.otf'),make(name,False,1,padding,glyf))
        cases.append({'id':name+'-glyph3','font':name+'.otf','text':chr(0xE003),'script':'Latn','direction':'ltr','engine':'graphite2','expected_glyph':3,'cff':False,'long_metric_count':1,'padding':padding,'category':'ordinary glyf positive'if glyf else'header/outline diagnostic'})
    for padding in [0,1]:
        for metric in range(11):
            name=f'cache-edge-padding{padding}-metric{metric}';emit(HERE/(name+'.otf'),make(name,False,1,padding,True,metric))
            cases.append({'id':name,'font':name+'.otf','text':chr(0xE003),'script':'Latn','direction':'ltr','engine':'graphite2','expected_glyph':3,'cff':False,'long_metric_count':1,'padding':padding,'metric':metric,'category':'ordinary glyf positive; VM queries raw last-glyph metric at level0'})
    raw=[{**case,'id':case['id']+'-mode'+str(mode),'face_options':mode}for case in cases if 'metric'in case for mode in [0,6]]
    emit(HERE/'cache-raw-cases.jsonc',(json.dumps({'schema':1,'cases':raw},indent=2)+'\n').encode())
    emit(HERE/'cache-cases.jsonc',(json.dumps({'schema':1,'about':'Reference edge-case evidence, kept separate from normative package38. All effective OT advances are600.','cases':cases},indent=2)+'\n').encode())
    print('29 short-metric fonts,41 public HB cases', 'reproduced'if args.check else'generated')
if __name__=='__main__':main()
