"""Original numerical proof from fixture bytes and public outputs only."""
import argparse,hashlib,json,struct
from pathlib import Path
from fontTools.ttLib import TTFont
ROOT=Path(__file__).resolve().parent
parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
f=lambda x:struct.unpack('>f',struct.pack('>f',x))[0]
add=lambda a,b:f(a+b)
sub=lambda a,b:f(a-b)
mul=lambda a,b:f(a*b)
div=lambda a,b:f(a/b)
font=TTFont(ROOT/'collision-empty-gap-target-diagonal.ttf');glyph=font['glyf'][font.getGlyphName(1)];xmin,ymin,xmax,ymax=[getattr(glyph,n)for n in ['xMin','yMin','xMax','yMax']];raw=font.getTableData('Glat');loc=font.getTableData('Gloc');off=struct.unpack_from('>H',loc,10)[0];diag=list(raw[off+2:off+6]);span=(xmax-xmin)+(ymax-ymin);smax=add(xmin+ymin,div(mul(span,diag[1]),255));dmax=add(xmin-ymax,div(mul(span,diag[3]),255));margin=10.;c=-10.;w=div(mul(2,margin),3);corner=div(sub(smax,dmax),2)
trace=next(r for r in json.loads((ROOT/'traces.json').read_text())['records']if r['id']=='collision-empty-gap-target-diagonal');move=next(m for p in trace['collisions']for phase in p if phase.get('phase')=='3'for m in phase['moves']);rows=[]
for cell in move['slices']:
 if abs(cell['targetEdge'])>1e30:continue
 i=cell['i'];lo=sub(add(c,mul(i,w)),1);hi=add(lo,w);mid=add(lo,div(w,2));cap=add(xmax,margin);sum_edge=add(sub(smax,hi),margin);diff_edge=add(add(dmax,hi),margin);minimum=min(cap,sum_edge,diff_edge);selected=min(cap,diff_edge if corner>=mid else sum_edge)
 rows.append({'i':i,'low':lo,'high':hi,'midpoint':mid,'corner':corner,'sum_edge':sum_edge,'diff_edge':diff_edge,'min_at_high':minimum,'mid_selected':selected,'reference_printed_edge':cell['targetEdge']})
min_peak=max(r['min_at_high']for r in rows);selected_peak=max(r['mid_selected']for r in rows);raw_result=next(r for r in json.loads((ROOT/'records.json').read_text())['records']if r['id']=='collision-empty-gap-target-diagonal')['result'];advance=struct.unpack('>f',struct.pack('>I',raw_result['slots'][0]['advance_bits'][0]))[0];selected_result=sub(add(selected_peak,margin),100);old_result=sub(add(min_peak,margin),100)
report={'source':'original fixture bytes + observed public occupied-cell set + gr_slot_advance_X; no implementation source','font_sha256':hashlib.sha256((ROOT/'collision-empty-gap-target-diagonal.ttf').read_bytes()).hexdigest(),'raw_records_sha256':hashlib.sha256((ROOT/'records.json').read_bytes()).hexdigest(),'traces_sha256':hashlib.sha256((ROOT/'traces.json').read_bytes()).hexdigest(),'raw_bbox':[xmin,ymin,xmax,ymax],'diagonal_bytes':diag,'sum_max':smax,'diff_max':dmax,'rows':rows,'min_at_high_peak':min_peak,'mid_selected_peak':selected_peak,'old_predicted_advance':old_result,'mid_predicted_advance':selected_result,'actual_public_advance':advance,'exact_public_bits_match':struct.pack('>f',selected_result)==struct.pack('>f',advance)}
assert report['exact_public_bits_match']
path=ROOT/'target-right-midpoint-proof.json'
if args.check:assert json.loads(path.read_text())==report;print('Target RIGHT midpoint model reproduces exact public F32 bits; min-at-HIGH is distinguished')
else:path.write_text(json.dumps(report,indent=2)+'\n');print('Target RIGHT midpoint proof generated from pinned fixture/records')
