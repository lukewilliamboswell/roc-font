/* Original timing loop over HarfBuzz's public ABI; no engine code copied. */
#include <stdint.h>
#include <time.h>
typedef struct { uint32_t glyph, mask, cluster, var1, var2; } Info;
typedef struct { int32_t ax, ay, dx, dy; uint32_t var; } Position;
uint64_t measure_graphite(uintptr_t resetp, uintptr_t addp, uintptr_t shapep,
 uintptr_t infop, uintptr_t positionp, uintptr_t scriptp, uintptr_t directionp,
 void *font, void *buffer, const char *text, unsigned length, unsigned iterations,
 unsigned script, unsigned direction, uint64_t *checksum) {
 void (*reset)(void*)=(void*)resetp;
 void (*add)(void*,const char*,int,unsigned,int)=(void*)addp;
 int (*shape)(void*,void*,const void*,unsigned,const char*const*)=(void*)shapep;
 Info*(*info)(void*,unsigned*)=(void*)infop;
 Position*(*position)(void*,unsigned*)=(void*)positionp;
 void(*setscript)(void*,unsigned)=(void*)scriptp;
 void(*setdirection)(void*,unsigned)=(void*)directionp;
 const char *shapers[]={"graphite2",0};struct timespec a,b;*checksum=0;
 clock_gettime(CLOCK_MONOTONIC,&a);
 for(unsigned r=0;r<iterations;r++){
  reset(buffer);add(buffer,text,(int)length,0,(int)length);setscript(buffer,script);setdirection(buffer,direction);
  if(!shape(font,buffer,0,0,shapers))return UINT64_MAX;
  unsigned n=0;Info *ii=info(buffer,&n);Position *pp=position(buffer,&n);
  for(unsigned i=0;i<n;i++)*checksum+=ii[i].glyph+ii[i].cluster+(uint64_t)(int64_t)pp[i].ax+(uint64_t)(int64_t)pp[i].ay+(uint64_t)(int64_t)pp[i].dx+(uint64_t)(int64_t)pp[i].dy;
 }
 clock_gettime(CLOCK_MONOTONIC,&b);
 return (uint64_t)(b.tv_sec-a.tv_sec)*1000000000+b.tv_nsec-a.tv_nsec;
}
