"""Independent IEEE binary32 FMA goldens and actual composite regression.
Run --record to refresh fma-oracle.json through native libm.fmaf; ordinary
runs verify every cached kernel result. C companion demonstrates compiler
contraction of the pinned HarfBuzz contour_point_t matrix expression.
"""
from pathlib import Path
import argparse,ctypes as C,ctypes.util,json,struct,sys
HERE=Path(__file__).resolve().parent
library='/usr/lib/libSystem.B.dylib' if sys.platform=='darwin' else C.util.find_library('m')
fmaf=C.CDLL(library).fmaf;fmaf.argtypes=[C.c_float]*3;fmaf.restype=C.c_float
f32=lambda bits:struct.unpack('>f',struct.pack('>I',bits))[0]
bits=lambda value:struct.unpack('>I',struct.pack('>f',value))[0]
VECTORS=[
 ('single-rounding-residual',0x3f800001,0x3f7ffffe,0xbf800000),
 ('negative-zero-sum',0x80000000,0x3f800000,0x80000000),
 ('opposite-zero-signs',0x80000000,0xbf800000,0x80000000),
 ('exact-cancellation',0xbf800000,0x3f800000,0x3f800000),
 ('underflow-tie-to-zero',1,0x3f000000,0),
 ('subnormal-halfway-even',1,0x3f000000,1),
 ('negative-underflow-zero',1,0x3f000000,0x80000001),
 ('normal-to-subnormal',0x00800000,0x3f000000,1),
 ('cancel-overflowing-product',0x7f7fffff,0x40000000,0xff7fffff),
 ('far-addend-breaks-tie-up',0x3fc00000,0x3f800001,1),
 ('far-addend-breaks-tie-down',0x3fc00000,0x3f800001,0x80000001),
 ('far-product-positive',1,1,0x3f800000),
 ('far-product-negative',0x80000001,1,0xbf800000),
 ('outline040-point0-y',0x47894b80,0x3e999800,0xc3d95b1c),
 ('outline040-point1-y',0x47896dc0,0x3e999800,0xc3d95b1c),
 ('outline040-point3-x-before-phantom',0x47894900,0x3f4ccc00,0xc385b54a),
]
def records():
 return [{'id':name,'a':f'{a:08x}','b':f'{b:08x}','c':f'{c:08x}','result':f'{bits(fmaf(f32(a),f32(b),f32(c))):08x}'} for name,a,b,c in VECTORS]
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--record',action='store_true');args=parser.parse_args()
 output={'contract':'IEEE754 binary32 round-to-nearest ties-to-even, exact product plus addend then one rounding; finite inputs','outline_reference':'HarfBuzz14.6 ARM64 wheel, contour_point_t::transform contracts x*mX + round32(y*mY)','cases':records(),'composite_regression':{'font':'var-outlines.ttf','glyph':4,'weight':650,'width':87.5,'normalized':[0.5,-0.5],'varied_box_points':[[70255,-503],[70323.5,-503],[70348.5,1317],[70250,1317]],'scaled_offset':[40,20],'matrix_fixed2dot14':[13107,4915,-3277,14746],'parent_left_phantom':-32,'exact_final_differences':[{'coordinate':'point0.y','unfused':'46a159dd','fused_reference':'46a159dc'},{'coordinate':'point1.y','unfused':'46a182f6','fused_reference':'46a182f5'},{'coordinate':'point3.x','unfused':'475abbb9','fused_reference':'475abbba'}]}}
 if args.record:(HERE/'fma-oracle.json').write_text(json.dumps(output,indent=2)+'\n')
 else:
  cached=json.loads((HERE/'fma-oracle.json').read_text());assert cached==output,'FMA golden mismatch'
  print(f'{len(VECTORS)} exact native libm FMA goldens agree')
 return 0
if __name__=='__main__':raise SystemExit(main())
