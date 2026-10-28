"""Record independent fontTools color facts; no Roc source is generated.

Requires fontTools4.61.1 and uharfbuzz0.56.3 (HarfBuzz14.6.0). Variable
fields evaluate in binary32 in format units, then widen exactly to binary64.
HarfBuzz independently checks palette/layer metadata and real emoji shaping.
"""
from pathlib import Path
import hashlib,json,math,struct,sys
from fontTools.ttLib import TTFont
from fontTools.varLib.varStore import VarStoreInstancer
import uharfbuzz as hb
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parents[2]/'scripts'))
from _common import load_jsonc

def f32(v):return struct.unpack('>f',struct.pack('>f',v))[0]
def ref(v):return 'f' if v==65535 else f'p:{v}'
def name(f,id):return None if id==65535 else f['name'].getDebugName(id)
MODES=['Clear','Source','Destination','SourceOver','DestinationOver','SourceIn','DestinationIn','SourceOut','DestinationOut','SourceAtop','DestinationAtop','Xor','Plus','Screen','Overlay','Darken','Lighten','ColorDodge','ColorBurn','HardLight','SoftLight','Difference','Exclusion','Multiply','HslHue','HslSaturation','HslColor','HslLuminosity']

class Facts:
 def __init__(self,path,weight):
  self.f=TTFont(path);self.t=self.f['COLR'].table if self.f['COLR'].version else None
  self.names=self.f.getGlyphOrder();self.ids=self.f.getReverseGlyphMap()
  self.roots={} if not self.t else {r.BaseGlyph:r.Paint for r in self.t.BaseGlyphList.BaseGlyphPaintRecord}
  self.clips={} if not self.t or not self.t.ClipList else self.t.ClipList.clips
  self.store=None
  if self.t and self.t.VarStore:
   axis=self.f['fvar'].axes[0];coord=(weight-axis.defaultValue)/(axis.maxValue-axis.defaultValue) if weight>=axis.defaultValue else (weight-axis.defaultValue)/(axis.defaultValue-axis.minValue)
   self.store=VarStoreInstancer(self.t.VarStore,self.f['fvar'].axes,{a.axisTag:coord for a in self.f['fvar'].axes})
 def delta(self,obj,i):
  base=getattr(obj,'VarIndexBase',0xffffffff)
  if not self.store or base==0xffffffff:return 0
  index=base+i
  if self.t.VarIndexMap:
   m=self.t.VarIndexMap.mapping;index=m[min(index,len(m)-1)]
  return f32(self.store[index])
 def value(self,obj,key,i,div=1,angle=False,biased=False):
  original=getattr(obj,key)
  # fontTools converts Fixed/F2Dot14/Angle values; return to stored units.
  raw=round((original-180 if biased else original)*16384/180) if angle else round(original*div)
  value=f32(f32(raw)+self.delta(obj,i))
  if biased:value=f32(value+16384)
  return float(f32(value*f32(180/16384))) if angle else float(f32(value/f32(div)))
 def clip(self,g):
  if g not in self.clips:return None
  c=self.clips[g];v=[self.value(c,k,i) for i,k in enumerate(['xMin','yMin','xMax','yMax'])]
  return [float(math.floor(v[0])),float(math.floor(v[1])),float(math.ceil(v[2])),float(math.ceil(v[3]))]
 def graph(self,g):
  nodes=[]
  def add(p):
   fmt=p.Format;i=len(nodes);nodes.append(None);n={}
   val=lambda key,j,div=1:self.value(p,key,j,div)
   angle=lambda key,j,biased=False:self.value(p,key,j,angle=True,biased=biased)
   if fmt==1:n={'kind':'layers','children':[add(self.t.LayerList.Paint[p.FirstLayerIndex+j]) for j in range(p.NumLayers)]}
   elif fmt in (2,3):n={'kind':'solid','color':ref(p.PaletteIndex),'values':[min(1.,max(0.,val('Alpha',0,16384)))]}
   elif 4<=fmt<=9:
    stops=[]
    for s in p.ColorLine.ColorStop:
     stops.append([self.value(s,'StopOffset',0,16384),ref(s.PaletteIndex),min(1.,max(0.,self.value(s,'Alpha',1,16384)))])
    stops.sort(key=lambda s:s[0]) # Python's stable sort is the specification order.
    n={'kind':'linear' if fmt<=5 else 'radial' if fmt<=7 else 'sweep','extend':['Pad','Repeat','Reflect'][p.ColorLine.Extend] if p.ColorLine.Extend<3 else 'Pad','stops':stops}
    if fmt<=5:n['values']=[val(k,j) for j,k in enumerate(['x0','y0','x1','y1','x2','y2'])]
    elif fmt<=7:n['values']=[val(k,j) for j,k in enumerate(['x0','y0','r0','x1','y1','r1'])]
    else:n['values']=[val('centerX',0),val('centerY',1),angle('startAngle',2,True),angle('endAngle',3,True)]
   elif fmt==10:n={'kind':'glyph','glyph':self.ids[p.Glyph],'children':[add(p.Paint)]}
   elif fmt==11:n={'kind':'color-glyph','glyph':self.ids[p.Glyph],'children':[add(self.roots[p.Glyph])],'clip':self.clip(p.Glyph)}
   elif fmt==32:n={'kind':'composite','mode':MODES[p.CompositeMode] if p.CompositeMode<28 else 'Clear','children':[add(p.SourcePaint),add(p.BackdropPaint)]}
   else:
    n={'children':[add(p.Paint)]};plain=fmt-(fmt%2)
    if plain==12:
     n.update(kind='affine',values=[self.value(p.Transform,k,j,65536) for j,k in enumerate(['xx','yx','xy','yy','dx','dy'])])
    elif plain==14:n.update(kind='translate',values=[val('dx',0),val('dy',1)])
    elif plain in (16,18,20,22):
     uniform=plain in (20,22);x=val('scale' if uniform else 'scaleX',0,16384);y=x if uniform else val('scaleY',1,16384)
     center=[val('centerX',1 if uniform else 2),val('centerY',2 if uniform else 3)] if plain in (18,22) else [0.,0.]
     n.update(kind='scale',values=[x,y,*center])
    elif plain in (24,26):n.update(kind='rotate',values=[angle('angle',0),*([val('centerX',1),val('centerY',2)] if plain==26 else [0.,0.])])
    else:n.update(kind='skew',values=[angle('xSkewAngle',0),angle('ySkewAngle',1),*([val('centerX',2),val('centerY',3)] if plain==30 else [0.,0.])])
   nodes[i]=n;return i
  if g in self.roots:root=add(self.roots[g])
  elif not self.t and g in self.f['COLR'].ColorLayers:
   children=[];nodes.append(None)
   for layer in self.f['COLR'].ColorLayers[g]:
    child=len(nodes);children.append(child);nodes.extend([{'kind':'glyph','glyph':self.ids[layer.name],'children':[child+1]},{'kind':'solid','color':ref(layer.colorID),'values':[1.]}])
   nodes[0]={'kind':'layers','children':children};root=0
  else:return None
  return {'root':root,'nodes':nodes,'clip':self.clip(g)}
 def facts(self,emoji=False):
  p=self.f['CPAL'];palettes=[]
  for i,colors in enumerate(p.palettes):
   kind=p.paletteTypes[i] if p.version else 0
   palettes.append({'colors':[[c.red,c.green,c.blue,c.alpha] for c in colors],'light':bool(kind&1),'dark':bool(kind&2),'name':name(self.f,p.paletteLabels[i]) if p.version else None})
  result={'palettes':palettes,'entry_names':[name(self.f,id) for id in p.paletteEntryLabels] if p.version else [None]*p.numPaletteEntries,'glyphs':[],'shapes':[]}
  for i,g in enumerate(self.names):
   layers=[]
   if not self.t:
    layers=[[self.ids[l.name],ref(l.colorID)] for l in self.f['COLR'].ColorLayers.get(g,[])]
   result['glyphs'].append({'glyph':i,'layers':layers,'graph':self.graph(g)})
  if emoji:
   face=hb.Face(Path(self.f.reader.file.name).read_bytes());font=hb.Font(face)
   for text in ['😀','👩\u200d💻','❤️']:
    b=hb.Buffer();b.add_str(text);b.guess_segment_properties();hb.shape(font,b)
    result['shapes'].append({'text':text,'glyphs':[v.codepoint for v in b.glyph_infos]})
  return result

def crosscheck_harfbuzz(path,facts,case):
 face=hb.Face(path.read_bytes());font=hb.Font(face)
 variations={'wght':case['weight']}
 if case.get('precision'):variations.update({t:case['weight'] for t in ['AX02','AX03','AX04']})
 font.set_variations(variations)
 assert len(face.color_palettes)==len(facts['palettes'])
 for i,p in enumerate(facts['palettes']):
  got=face.get_color_palette(i)
  assert [[c.red,c.green,c.blue,c.alpha] for c in got.colors]==p['colors']
  assert bool(int(got.flags)&1)==p['light'] and bool(int(got.flags)&2)==p['dark']
 paints=[]
 def color(c,fg):return 'f' if fg else f'p:{c.green*256+c.blue}'
 def expected(g):
  out=[]
  def walk(i):
   n=g['nodes'][i];kind=n['kind'];children=n.get('children',[])
   if kind=='glyph':out.append({'kind':'glyph','glyph':n['glyph']})
   elif kind=='solid':out.append({'kind':kind,'color':n['color'],'alpha':n['values'][0]})
   elif kind in ['linear','radial','sweep']:out.append({k:n[k] for k in ['kind','values','extend','stops']})
   for child in (reversed(children) if kind=='composite' else children):walk(child)
  walk(g['root']);return out
 for glyph in facts['glyphs']:
  gid=glyph['glyph'];g=glyph['graph']
  assert [[l.glyph,ref(l.color_index)] for l in face.get_glyph_color_layers(gid)]==glyph['layers']
  if face.has_color_paint:assert face.glyph_has_color_paint(gid)==(g is not None)
  if not g:continue
  events=[];matrices=[];p=hb.PaintFuncs()
  p.set_custom_palette_color_func(lambda i,state:hb.Color(0,i>>8,i&255,255))
  p.set_push_clip_glyph_func(lambda gid,state:events.append({'kind':'glyph','glyph':gid}))
  p.set_color_func(lambda c,fg,state:events.append({'kind':'solid','color':color(c,fg),'alpha':c.alpha/255}))
  p.set_push_transform_func(lambda *a:matrices.append(list(a[:-1])))
  def gradient(kind,line,*args):
   values=list(args[:-1]);stops=[[s.offset,color(s.color,s.is_foreground),s.color.alpha/255] for s in line.color_stops];stops.sort(key=lambda s:s[0])
   if kind=='sweep':values[-2:]=[v*180/math.pi for v in values[-2:]]
   events.append({'kind':kind,'values':values,'extend':['Pad','Repeat','Reflect'][line.extend],'stops':stops})
  p.set_linear_gradient_func(lambda *a:gradient('linear',*a))
  p.set_radial_gradient_func(lambda *a:gradient('radial',*a))
  p.set_sweep_gradient_func(lambda *a:gradient('sweep',*a))
  font.paint_glyph(gid,p,foreground=hb.Color(255,255,255,255))
  want=expected(g);assert len(events)==len(want),(case['id'],gid,events,want)
  for a,e in zip(events,want):
   assert a['kind']==e['kind'],(a,e)
   if 'glyph' in e:assert a['glyph']==e['glyph']
   if 'color' in e:assert a['color']==e['color'] and abs(a['alpha']-e['alpha'])<=0.5/255+1e-9
   if 'values' in e:
    assert all(math.isclose(x,y,rel_tol=2e-6,abs_tol=2e-5) for x,y in zip(a['values'],e['values'])),(a,e)
    assert a['extend']==e['extend'] and len(a['stops'])==len(e['stops'])
    for x,y in zip(a['stops'],e['stops']):assert x[0]==y[0] and x[1]==y[1] and abs(x[2]-y[2])<=0.5/255+1e-9,(x,y)
  if case.get('precision'):
   affine=g['nodes'][0]['values'];assert affine in matrices,(affine,matrices)
  paints.append({'glyph':gid,'events':events})
 return paints

def main():
 records=[]
 for c in load_jsonc(HERE/'cases.jsonc')['cases']:
  path=HERE/c['font'];facts=Facts(path,c['weight']).facts(c.get('emoji',False));paint_checks=crosscheck_harfbuzz(path,facts,c)
  records.append({'id':c['id'],'font_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'oracle':'fontTools4.61.1; emoji shapes HarfBuzz14.6.0','facts':facts,'harfbuzz_paint_callbacks':paint_checks})
 (HERE/'oracle.jsonl').write_text(''.join(json.dumps(r,separators=(',',':'),ensure_ascii=False)+'\n' for r in records))
 print(f'Recorded {len(records)} color cases')
if __name__=='__main__':main()
