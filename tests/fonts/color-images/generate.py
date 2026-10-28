"""Original synthetic color tables; pinned fontTools4.61.1 builds sfnt.
All synthetic artwork is a single original red pixel or geometric SVG.
Rebuild the optional real subset with --noto /path/to/pinned/source.ttf.
"""
from pathlib import Path
import struct,gzip,zlib,hashlib,json,argparse
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib.tables.DefaultTable import DefaultTable
from fontTools.ttLib import TTFont
from fontTools import subset
HERE=Path(__file__).resolve().parent
U16=lambda x:struct.pack('>H',x)
U32=lambda x:struct.pack('>I',x)

def raw(tag,data):
    t=DefaultTable(tag);t.data=data;return t

def png():
    def chunk(tag,data):return U32(len(data))+tag+data+U32(zlib.crc32(tag+data)&0xffffffff)
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',1,1,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(b'\x00\xff\x00\x00\xff'))+chunk(b'IEND',b'')
PNG=png()
SVG=b'<svg xmlns="http://www.w3.org/2000/svg"><rect id="glyph1" width="10" height="20" fill="red"/></svg>'

def svg_table():
    compressed=gzip.compress(SVG,mtime=0)
    start=2+3*12
    records=struct.pack('>HHII',1,2,start,len(SVG))+struct.pack('>HHII',3,3,start+len(SVG),len(compressed))+struct.pack('>HHII',6,6,start,len(SVG))
    return struct.pack('>HIIH',0,10,0,3)+records+SVG+compressed

def sbix_table(glyph_count=8):
    # PNG and duplicate placement get independent FreeType/HB checks.
    # The other records test format dispatch and opaque byte preservation,
    # deliberately without claiming image/XML decoder validation.
    payloads=[b'',struct.pack('>hh4s',2,-3,b'png ')+PNG,struct.pack('>hh4sH',99,99,b'dupe',1),struct.pack('>hh4sH',88,88,b'dupe',2),struct.pack('>hh4s',4,-5,b'jpg ')+b'\xff\xd8\xff\xd9',struct.pack('>hh4s',5,-6,b'tiff')+b'II\x2a\x00\x08\x00\x00\x00\x00\x00\x00\x00\x00\x00',struct.pack('>hh4s',6,-7,b'pdf ')+b'%PDF-1.4\n%%EOF\n',struct.pack('>hh4s',7,-8,b'mask')+b'\x00\x80\xff']
    def strike(ppem):
        offsets=[4+4*(glyph_count+1)]
        for blob in payloads:offsets.append(offsets[-1]+len(blob))
        return struct.pack('>HH',ppem,72)+b''.join(map(U32,offsets))+b''.join(payloads)
    strikes=[strike(16),strike(32)]
    offsets=[8+4*len(strikes)]
    for blob in strikes:offsets.append(offsets[-1]+len(blob))
    return struct.pack('>HHI',1,3,len(strikes))+b''.join(U32(x) for x in offsets[:-1])+b''.join(strikes)

SMALL=struct.pack('>BBbbB',1,1,-2,4,7)
BIG=struct.pack('>BBbbBbbB',1,1,-2,4,7,-3,5,8)
LINE=struct.pack('>bbBbbbbbbbbb',8,-2,9,1,0,0,-1,-1,8,-2,0,0)

def bitmap_tables():
    data=bytearray(U32(0x30000));subtables=[];size_records=[]
    for index_format in [1,2,3,4,5]:
        image_format={1:17,2:19,3:18,4:17,5:19}[index_format]
        ids=[1,2,3] if index_format in (1,2,3) else [1,3]
        def image():return (SMALL if image_format==17 else BIG if image_format==18 else b'')+U32(len(PNG))+PNG
        images=[image() for _ in ids]
        image_base=len(data)
        for blob in images:data+=blob
        header=struct.pack('>HHI',index_format,image_format,image_base)
        offsets=[0]
        for blob in images:offsets.append(offsets[-1]+len(blob))
        if index_format in (1,3):
            sub=header+b''.join((U32 if index_format==1 else U16)(x) for x in offsets)
        elif index_format==2:
            sub=header+U32(len(images[0]))+BIG
        elif index_format==4:
            sub=header+U32(len(ids))+b''.join(struct.pack('>HH',gid,off) for gid,off in zip(ids+[0],offsets))
        else:
            sub=header+U32(len(images[0]))+BIG+U32(len(ids))+b''.join(map(U16,ids))
        sub+=bytes((-len(sub))%4)
        array=struct.pack('>HHI',1,3,8)+sub
        subtables.append(array)
    offset=8+48*5
    for i,array in enumerate(subtables):
        record=struct.pack('>IIII',offset,len(array),1,0)+LINE+LINE+struct.pack('>HHBBBB',1,3,16+i*8,16+i*8,32,1)
        assert len(record)==48
        size_records.append(record);offset+=len(array)
    return U32(0x30000)+U32(5)+b''.join(size_records)+b''.join(subtables),bytes(data)

def base():
    fb=FontBuilder(1000,isTTF=True)
    names=['.notdef']+[f'g{i}' for i in range(1,8)]
    fb.setupGlyphOrder(names);fb.setupCharacterMap({64+i:n for i,n in enumerate(names) if i})
    glyphs={}
    for name in names:
        pen=TTGlyphPen(None)
        if name!='.notdef':
            pen.moveTo((0,0));pen.lineTo((400,0));pen.lineTo((400,700));pen.lineTo((0,700));pen.closePath()
        glyphs[name]=pen.glyph()
    fb.setupGlyf(glyphs);fb.setupHorizontalMetrics({n:(600,0) for n in names})
    fb.setupHorizontalHeader(ascent=800,descent=-200)
    fb.setupNameTable({'familyName':'RocColorImageFixture','styleName':'Regular','fullName':'RocColorImageFixture Regular','uniqueFontIdentifier':'RocColorImageFixture','psName':'RocColorImageFixture-Regular'})
    fb.setupOS2(sTypoAscender=800,sTypoDescender=-200,usWinAscent=800,usWinDescent=200)
    fb.setupPost();fb.setupHead(unitsPerEm=1000,created=2082844800,modified=2082844800)
    fb.font.recalcTimestamp=False
    return fb

def make_synthetic():
    cblc,cbdt=bitmap_tables();svg=svg_table();sbix=sbix_table()
    tables={'SVG ':svg,'sbix':sbix,'CBLC':cblc,'CBDT':cbdt}
    def save(name,changed):
        fb=base()
        for tag,data in changed.items():fb.font[tag]=raw(tag,data)
        fb.save(HERE/name)
    save('images.ttf',tables)
    save('cbdt-alone.ttf',{'CBDT':cbdt})
    save('cblc-alone.ttf',{'CBLC':cblc})
    for label,tag,at,replacement in [
      ('bad-svg-range','SVG ',12,U16(7)+U16(1)),
      ('bad-svg-offset','SVG ',16,U32(0xffffffff)),
      ('bad-sbix-reference','sbix',16+4+4*9+len(struct.pack('>hh4s',2,-3,b'png ')+PNG)+8,U16(65535)),
      ('bad-cblc-offset','CBLC',8,U32(0xffffffff)),
      ('bad-cbdt-length','CBDT',4+5,U32(0xffffffff)),
    ]:
        changed=dict(tables);blob=bytearray(changed[tag]);blob[at:at+len(replacement)]=replacement;changed[tag]=bytes(blob);save(label+'.ttf',changed)
    # Glyph2 points at3, which points back at2.
    changed=dict(tables);blob=bytearray(sbix)
    first=struct.unpack_from('>I',blob,8)[0]
    glyph2=first+struct.unpack_from('>I',blob,first+4+2*4)[0]
    struct.pack_into('>H',blob,glyph2+8,3)
    changed['sbix']=bytes(blob);save('bad-sbix-cycle.ttf',changed)
    # Independent malformed tables must aggregate, leaving good CBDT data.
    changed=dict(tables);changed['SVG ']=svg[:4];changed['sbix']=sbix[:4]
    save('multiple-bad.ttf',changed)
    # Vertical small metrics and format19 constant-index2/5 variants.
    changed=dict(tables);blob=bytearray(cblc);blob[8+47]=2;changed['CBLC']=bytes(blob)
    save('vertical.ttf',changed)

def make_noto(path):
    source=Path(path)
    font=TTFont(source,recalcTimestamp=False)
    options=subset.Options();options.recalc_timestamp=False;options.layout_features=['*'];options.name_IDs=['*'];options.name_legacy=True
    worker=subset.Subsetter(options=options)
    worker.populate(text='\U0001F469\u200D\U0001F4BB\u2764\uFE0F\U0001F600\U0001F44D\U0001F3FD\U0001F1E6\U0001F1FA')
    worker.subset(font)
    for entry in font['name'].names:
        if entry.nameID in (1,3,4,6,16):
            name='RocEmojiAssetFixture-Regular' if entry.nameID==6 else 'Roc Emoji Asset Fixture'
            entry.string=name.encode(entry.getEncoding())
    font.save(HERE/'emoji-subset.ttf')
    pin={'repository':'https://github.com/googlefonts/noto-emoji','revision':'99701e07d3d1fe1bdbcdb14964547f0fd592966f','path':'2D/fonts/NotoColorEmoji.ttf','source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'subset_sha256':hashlib.sha256((HERE/'emoji-subset.ttf').read_bytes()).hexdigest(),'fontTools':'4.61.1','texts':['👩\u200d💻','❤️','😀','👍🏽','🇦🇺'],'note':'Subset and renamed derivative under OFL1.1; original font licence retained.'}
    (HERE/'emoji-pin.json').write_text(json.dumps(pin,ensure_ascii=False,indent=2)+'\n')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--noto');args=parser.parse_args()
    make_synthetic()
    if args.noto:make_noto(args.noto)
