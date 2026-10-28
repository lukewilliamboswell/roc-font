"""Original modern/legacy/no-circle Myanmar fonts for stage boundaries.

Reproduce using fontTools4.61.1. UPL; no font code or outlines are copied.
"""
from pathlib import Path
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
HERE=Path(__file__).resolve().parent

def make(name,script='mym2',circle=True,copies=0):
 names=['.notdef','ka','nga','asat','halant','e','ya','ra','u','anusvara','circle','latin']+[f'stage{i}' for i in range(8)]
 b=FontBuilder(1000,isTTF=True);b.setupGlyphOrder(names);glyphs={}
 for i,n in enumerate(names):
  p=TTGlyphPen(None)
  if i:p.moveTo((0,0));p.lineTo((450,0));p.lineTo((450,650));p.lineTo((0,650));p.closePath()
  glyphs[n]=p.glyph()
 b.setupGlyf(glyphs);b.setupHorizontalMetrics({n:(500,0) for n in names});b.setupHorizontalHeader(ascent=800,descent=-200)
 cmap={0x1000:'ka',0x1004:'nga',0x103a:'asat',0x1039:'halant',0x1031:'e',0x103b:'ya',0x103c:'ra',0x102f:'u',0x1036:'anusvara',0x61:'latin'}
 if circle:cmap[0x25cc]='circle'
 b.setupCharacterMap(cmap);b.setupNameTable({'familyName':'Roc Myanmar Fixture','styleName':'Regular','uniqueFontIdentifier':'RocMyanmar-1','fullName':'Roc Myanmar Fixture','psName':'RocMyanmarFixture'});b.setupOS2(sTypoAscender=800,sTypoDescender=-200,usWinAscent=800,usWinDescent=200);b.setupPost();b.setupMaxp();b.font.recalcTimestamp=False;b.font['head'].created=b.font['head'].modified=3700000000
 lines=[f'languagesystem {script} dflt;','@marks=[asat halant e ya ra u anusvara];','table GDEF {GlyphClassDef [ka nga circle latin stage0 stage1 stage2 stage3 stage4 stage5 stage6 stage7],[],@marks,[];}GDEF;']
 if copies:lines.append('feature ccmp {sub ka by '+ ' '.join(['ka']*copies) +';}ccmp;')
 old='ka'
 for i,feature in enumerate(['rphf','pref','blwf','pstf','pres','abvs','blws','psts']):
  new=f'stage{i}';lines.append(f'feature {feature} {{sub {old} by {new};}}{feature};');old=new
 addOpenTypeFeaturesFromString(b.font,'\n'.join(lines));b.font.save(HERE/name,reorderTables=True)
if __name__=='__main__':
 make('modern.ttf');make('legacy.ttf',script='mymr');make('no-circle.ttf',circle=False)

if __name__=='__main__':
 for count in [8,32,64,256]:make(f'sort-{count}.ttf',copies=count)
