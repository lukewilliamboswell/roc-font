#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
__attribute__((noinline)) float source_expression(float x,float y,float a,float b) { return x*a+y*b; }
__attribute__((noinline)) float explicit_unfused(float x,float y,float a,float b) { volatile float p=x*a,q=y*b;return p+q; }
__attribute__((noinline)) float explicit_fused(float x,float y,float a,float b) { volatile float q=y*b;return fmaf(x,a,q); }
static uint32_t bits(float f) {uint32_t u;memcpy(&u,&f,sizeof u);return u;}
int main(void) {
 float m[4]={13107.f/16384.f,4915.f/16384.f,-3277.f/16384.f,14746.f/16384.f};
 float p[4][2]={{70295.f,-483.f},{70363.5f,-483.f},{70388.5f,1337.f},{70290.f,1337.f}};
 for (int i=0;i<4;i++) for (int axis=0;axis<2;axis++) {
  float x=p[i][0],y=p[i][1],a=m[axis],b=m[axis+2];
  float def=source_expression(x,y,a,b),un=explicit_unfused(x,y,a,b),fu=explicit_fused(x,y,a,b);
  printf("point%d axis%d source=%a(%08x) unfused=%a(%08x) fused=%a(%08x)\n",i,axis,def,bits(def),un,bits(un),fu,bits(fu));
 }
}
