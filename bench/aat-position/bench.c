/* Native HB14.6 shaping loop. Function pointers identify the actual binary. */
#include <stdint.h>
#include <time.h>
typedef void (*clear_fn)(void*);
typedef void (*set_fn)(void*,unsigned);
typedef void (*add_fn)(void*,const char*,int,unsigned,int);
typedef void (*shape_fn)(void*,void*,const void*,unsigned);
typedef struct {uint32_t glyph,mask,cluster,var1,var2;} info;
typedef struct {int32_t xa,ya,xo,yo;uint32_t var;} position;
typedef info* (*infos_fn)(void*,unsigned*);
typedef position* (*pos_fn)(void*,unsigned*);
uint64_t measure(uintptr_t clearptr,uintptr_t addptr,uintptr_t shapeptr,uintptr_t infoptr,uintptr_t posptr,uintptr_t scriptptr,uintptr_t dirptr,void*font,void*buffer,const char*text,unsigned length,unsigned reps,uint64_t*elapsed) {
 clear_fn clear=(clear_fn)clearptr;add_fn add=(add_fn)addptr;shape_fn shape=(shape_fn)shapeptr;infos_fn infos=(infos_fn)infoptr;pos_fn positions=(pos_fn)posptr;set_fn script=(set_fn)scriptptr,direction=(set_fn)dirptr;
 struct timespec start,end;uint64_t sum=0;unsigned count=0;
 clock_gettime(CLOCK_MONOTONIC,&start);
 for(unsigned i=0;i<reps;i++) {
  clear(buffer);script(buffer,0x4c61746e);direction(buffer,4);add(buffer,text,length,0,length);shape(font,buffer,0,0);
  info*ii=infos(buffer,&count);position*pp=positions(buffer,&count);
  for(unsigned j=0;j<count;j++)sum+=ii[j].glyph+ii[j].cluster+(int64_t)pp[j].xa+(int64_t)pp[j].ya+(int64_t)pp[j].xo+(int64_t)pp[j].yo;
 }
 clock_gettime(CLOCK_MONOTONIC,&end);*elapsed=(uint64_t)end.tv_sec*1000000000+end.tv_nsec-((uint64_t)start.tv_sec*1000000000+start.tv_nsec);return sum;
}
