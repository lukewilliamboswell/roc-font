/* Invoke pinned HarfBuzz in a native loop, without per-call FFI overhead. */
#include <stdint.h>
#include <time.h>
typedef void (*clear_t)(void*);
typedef void (*set_t)(void*,unsigned);
typedef void (*add_t)(void*,const char*,int,unsigned,int);
typedef void (*shape_t)(void*,void*,const void*,unsigned);
typedef void* (*infos_t)(void*,unsigned*);
uint64_t measure_shapes(uintptr_t clear_ptr, uintptr_t add_ptr,
 uintptr_t shape_ptr, uintptr_t infos_ptr, uintptr_t script_ptr, uintptr_t direction_ptr, void*font,void*buffer,
 const char*text,unsigned length,unsigned repetitions,unsigned script,uint64_t*elapsed) {
 clear_t clear=(clear_t)clear_ptr;add_t add=(add_t)add_ptr;
 shape_t shape=(shape_t)shape_ptr;infos_t infos=(infos_t)infos_ptr;
 set_t set_script=(set_t)script_ptr,set_direction=(set_t)direction_ptr;
 struct timespec start,end;uint64_t sum=0;unsigned count=0;
 clock_gettime(CLOCK_MONOTONIC,&start);
 for(unsigned i=0;i<repetitions;i++) {
  clear(buffer);set_script(buffer,script);set_direction(buffer,5);add(buffer,text,length,0,length);shape(font,buffer,0,0);
  infos(buffer,&count);sum+=count;
 }
 clock_gettime(CLOCK_MONOTONIC,&end);
 *elapsed=(uint64_t)end.tv_sec*1000000000+end.tv_nsec-
 ((uint64_t)start.tv_sec*1000000000+start.tv_nsec);return sum;
}
