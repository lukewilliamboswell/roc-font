/* Invoke pinned HarfBuzz in a native loop, without per-call FFI overhead. */
#include <stdint.h>
#include <time.h>
typedef void (*clear_t)(void*);
typedef void (*set_t)(void*,unsigned);
typedef void (*add_t)(void*,const char*,int,unsigned,int);
typedef void (*shape_t)(void*,void*,const void*,unsigned);
typedef void* (*infos_t)(void*,unsigned*);
uint64_t measure_shapes(uintptr_t clear_ptr, uintptr_t add_ptr,
 uintptr_t shape_ptr, uintptr_t infos_ptr, uintptr_t positions_ptr, uintptr_t script_ptr, uintptr_t direction_ptr, void*font,void*buffer,
 const char*text,unsigned length,unsigned repetitions,unsigned script,uint64_t*elapsed) {
 clear_t clear=(clear_t)clear_ptr;add_t add=(add_t)add_ptr;
 shape_t shape=(shape_t)shape_ptr;infos_t infos=(infos_t)infos_ptr;
 infos_t positions=(infos_t)positions_ptr;
 set_t set_script=(set_t)script_ptr,set_direction=(set_t)direction_ptr;
 struct timespec start,end;uint64_t sum=0;unsigned count=0;
 clock_gettime(CLOCK_MONOTONIC,&start);
 for(unsigned i=0;i<repetitions;i++) {
  clear(buffer);set_script(buffer,script);set_direction(buffer,4);add(buffer,text,length,0,length);shape(font,buffer,0,0);
  typedef struct { uint32_t glyph,mask,cluster,var1,var2; } glyph_info;
  typedef struct { int32_t ax,ay,dx,dy; uint32_t var; } glyph_position;
  glyph_info *info=(glyph_info*)infos(buffer,&count);
  glyph_position *pos=(glyph_position*)positions(buffer,0);
  for(unsigned j=0;j<count;j++) sum+=(uint64_t)info[j].glyph+info[j].cluster+
   (uint64_t)(int64_t)pos[j].ax+(uint64_t)(int64_t)pos[j].ay+
   (uint64_t)(int64_t)pos[j].dx+(uint64_t)(int64_t)pos[j].dy;
 }
 clock_gettime(CLOCK_MONOTONIC,&end);
 *elapsed=(uint64_t)end.tv_sec*1000000000+end.tv_nsec-
 ((uint64_t)start.tv_sec*1000000000+start.tv_nsec);return sum;
}
