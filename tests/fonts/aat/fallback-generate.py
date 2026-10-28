"""Original UPL Apple-program/mark-fallback fixtures, based on direct-logical.ttf."""
import argparse,io,json
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.pens.ttGlyphPen import TTGlyphPen
HERE=Path(__file__).resolve().parent
SCRIPTS=[('Hebr','סְ'),('Arab','بَ'),('Syrc','ܒܰ'),('Hang','가〮'),('Thai','ก่'),('Laoo','ກ່'),('Deva','क़'),('Khmr','ក៉'),('Mymr','က့'),('Tibt','ཀཱ'),('Latn','á')]

def make(expanded, mark_advance=0, dflt=False, gdef=False):
    f=TTFont(HERE/'direct-logical.ttf');f.recalcTimestamp=False
    mapping={0x5e1:'g1',0x5b0:'g7',0x628:'g1',0x64e:'g7'}
    if expanded:
        for _,text in SCRIPTS:mapping.update({ord(text[0]):'g1',ord(text[1]):'g7'})
    for table in f['cmap'].tables:
        if table.isUnicode():table.cmap.update(mapping)
    for name,width,height in [('g1',600,600),('g7',100,100)]:
        pen=TTGlyphPen(None);pen.moveTo((0,0));pen.lineTo((width,0));pen.lineTo((width,height));pen.lineTo((0,height));pen.closePath();f['glyf'][name]=pen.glyph();f['hmtx'].metrics[name]=(700 if name=='g1' else mark_advance,0)
    f['morx'].table.MorphChain[0].MorphSubtable[0].SubStruct.Substitution={'g1':'g1','g2':'g2','g3':'g3'}
    for nid,text in [(1,'Roc AAT Fallback'),(4,'Roc AAT Fallback'),(6,'RocAATFallback')]:f['name'].setName(text,nid,3,1,0x409)
    if dflt:addOpenTypeFeaturesFromString(f,'languagesystem DFLT dflt; feature calt { sub g2 by g2; } calt;' + (' table GDEF { GlyphClassDef [g1], , [g7], ; } GDEF;'if gdef else''))
    out=io.BytesIO();f.save(out);return out.getvalue()

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    def emit(path,data):
        if args.check:assert path.read_bytes()==data,path
        else:path.write_bytes(data)
    for filename,expanded in [('fallback-marks.ttf',False),('fallback-script-marks.ttf',True),('fallback-nonzero-marks.ttf',True)]:emit(HERE/filename,make(expanded,230 if 'nonzero'in filename else 0))
    for filename,gdef in [('fallback-dflt-marks.ttf',False),('fallback-gdef-dflt-marks.ttf',True)]:emit(HERE/filename,make(True,230,True,gdef))
    cases=[]
    for variant in ['zero','nonzero','dflt','gdef-dflt']:
        for script,text in SCRIPTS:
            for direction in ['ltr','rtl','ttb','btt']:
                cases.append({'id':variant+'-'+script+'-'+direction,'font':'fallback-'+('script'if variant=='zero'else variant)+'-marks.ttf','text':text,'options':{'script':script,'direction':direction,'hb_options':['--show-flags']},'expected':'oracle'})
    emit(HERE/'fallback-cases.jsonc',(json.dumps({'schema':1,'cases':cases},indent=2,ensure_ascii=False)+'\n').encode())
    print(len(cases),'script/direction cases reproduced'if args.check else'script/direction cases generated')
if __name__=='__main__':main()
