"""Record actual HB14.6/fontTools/FreeType facts; never computes Roc answers."""
from pathlib import Path
import hashlib,json,subprocess,sys
import uharfbuzz as hb
from fontTools.ttLib import TTFont
from fontTools.varLib.models import normalizeLocation
import fontTools,freetype
HERE=Path(__file__).resolve().parent

def hbfacts(path,settings,ids,text,direction,vertical):
 data=path.read_bytes();f=hb.Font(hb.Face(data));f.scale=(f.face.upem,f.face.upem)
 # Sequential setters require full accumulated settings to keep last wins.
 f.set_variations(dict(settings))
 b=hb.Buffer();b.add_utf8(text.encode());b.direction=direction;b.script='Latn';b.language='en';hb.shape(f,b)
 out={'coords':[round(v*16384)for v in f.get_var_coords_normalized()], 'metrics':[f.get_glyph_h_advance(i)for i in ids], 'glyphs':[g.codepoint for g in b.glyph_infos], 'advances':[[p.x_advance,p.y_advance]for p in b.glyph_positions], 'offsets':[[p.x_offset,p.y_offset]for p in b.glyph_positions], 'clusters':[g.cluster for g in b.glyph_infos]}
 if vertical:
  out['vertical']=[-f.get_glyph_v_advance(i)for i in ids];out['origins']=[list(f.get_glyph_v_origin(i))for i in ids]
 return out

def ftfacts(path,settings,ids):
 """Independent FreeType unhinted/no-scale glyph advances where representable."""
 f=freetype.Face(str(path));f.set_var_design_coords([dict(settings).get(a.tag.decode()if isinstance(a.tag,bytes)else a.tag,a.default)for a in f.get_variation_info().axes])
 result=[]
 for g in ids:
  f.load_glyph(g,freetype.FT_LOAD_NO_SCALE|freetype.FT_LOAD_NO_HINTING|freetype.FT_LOAD_NO_BITMAP);result.append(f.glyph.metrics.horiAdvance)
 return result

def main():
 cases=[]
 def add(font,settings,ids=[1,2],text='ab',direction='ltr',vertical=False,label=None):
  path=HERE/font;ident=f'{font[:-4]}-{label or len(cases)}-{direction}'
  record={'id':ident,'font':font,'font_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'settings':settings,'glyphs':ids,'text':text,'direction':direction,'vertical':vertical,'hb':hbfacts(path,settings,ids,text,direction,vertical)}
  if not any(k in font for k in ['boundary','large','axes-','avar-','composite','metrics']):
   try:record['freetype_metrics']=ftfacts(path,settings,ids)
   except Exception as e:record['freetype_failure']=str(e)
  cases.append(record)
 for font in ['phantom-simple.ttf','phantom-mixed-tuples.ttf','phantom-composite.ttf','phantom-last-metrics.ttf','phantom-hvar-priority.ttf']:
  for value in [0,.25,.5,.75,1]:
   for direction in ['ltr','rtl']:
    composite='composite'in font or 'last-metrics'in font;add(font,[['wght',value]],[1,2,3,4]if composite else[1,2],'abcd'if composite else'ab',direction)
 for font in ['phantom-boundary.ttf','vertical-boundary.ttf','origin-boundary.ttf','origin-negative-boundary.ttf','vertical-large.ttf']:
  for value in [0,.5,1]:
   for direction in (['ttb','btt']if font!='phantom-boundary.ttf'else['ltr','rtl']):add(font,[['wght',value]],[1],'a',direction,font!='phantom-boundary.ttf')
 for font in ['avar-cross.ttf','avar-mapped.ttf','avar-empty-map.ttf','avar-null.ttf','avar-no-variation.ttf']:
  for x,y in [(0,0),(.5,.5),(.25,.75),(1,1)]:add(font,[['wght',x],['wdth',y]])
 add('avar-first-cache.ttf',[['AX01',1/16384],['AX02',1/16384],['AX03',.0625]])
 for value in [0,250,500,1000]:add('duplicate-axes.ttf',[['0001',value]],[2],'.')
 add('duplicate-axes.ttf',[['0001',1000],['0001',500]],[2],'.',label='last-wins')
 for font in ['phantom-sparse-4.ttf','phantom-sparse-64.ttf','phantom-sparse-512.ttf','phantom-all-4.ttf','phantom-all-64.ttf','phantom-all-512.ttf']:add(font,[['wght',1]])
 for count in [8,32,128,16382]:add(f'axes-{count}.ttf',[['0000',.5]])
 for font in ['InterVariable.ttf','RocVariationCorpus-noHVAR.ttf']:
  f=TTFont(HERE/font);ids=[f.getGlyphID(f.getBestCmap()[ord(c)])for c in 'AV\u00e9\u00c5\u00fc']
  for value in [100,400,650,900]:
   for direction in ['ltr','rtl']:add(font,[['wght',value],['opsz',24]],ids,'AVariable\u00e9\u00c5\u00fc',direction)
 f=TTFont(HERE/'Amstelvar-avar2.ttf');ids=[f.getGlyphID(f.getBestCmap()[ord(c)])for c in 'Test']
 for settings in [[],[['wght',500]],[['wdth',50],['opsz',72]],[['GRAD',100],['wght',700],['wdth',125]]]:
  add('Amstelvar-avar2.ttf',settings,ids,'Test')
  coords=normalizeLocation(dict(settings),{a.axisTag:(a.minValue,a.defaultValue,a.maxValue)for a in f['fvar'].axes})
  mapped=f['avar'].renormalizeLocation(coords,f)
  cases[-1]['fonttools_coords']=[round(mapped.get(a.axisTag,0)*16384)for a in f['fvar'].axes]
 tiny=TTFont(HERE/'avar-first-cache.ttf');loc={a.axisTag:v for a,(_,v)in zip(tiny['fvar'].axes,cases[100]['settings'])}if False else {'AX01':1/16384,'AX02':1/16384,'AX03':.0625}
 mapped=tiny['avar'].renormalizeLocation(loc,tiny)
 next(c for c in cases if c['font']=='avar-first-cache.ttf')['fonttools_coords']=[round(mapped[t]*16384)for t in ['AX01','AX02','AX03']]
 out={'oracles':{'harfbuzz':hb.version_string(),'uharfbuzz':hb.__version__,'fontTools':fontTools.__version__,'FreeType':'.'.join(map(str,freetype.version()))},'cases':cases}
 (HERE/'cases.jsonc').write_text('// Actual pinned reference outputs. Generated by oracle.py.\n'+json.dumps(out,ensure_ascii=False,indent=2)+'\n')
 print(f'Recorded {len(cases)} actual HB cases.')
if __name__=='__main__':main()
