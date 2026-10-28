/* Run the actual pinned HarfBuzz functions in a native loop. */
#include <stdint.h>
#include <time.h>
typedef struct {unsigned tag;float value;} variation;
typedef int (*advance_fn)(void*,unsigned);
typedef void (*set_fn)(void*,const variation*,unsigned);
typedef const int* (*coords_fn)(void*,unsigned*);
uint64_t measure(uintptr_t advance_ptr,uintptr_t set_ptr,uintptr_t coords_ptr,
 void*font,unsigned axis,unsigned repetitions,uint64_t*elapsed) {
 advance_fn advance=(advance_fn)advance_ptr;set_fn set=(set_fn)set_ptr;coords_fn coords=(coords_fn)coords_ptr;
 variation v[2]={{axis==2?0x77676874:0x30303030,0.5f},{0x77647468,0.5f}};uint64_t checksum=0;unsigned count=0;
 struct timespec start,end;clock_gettime(CLOCK_MONOTONIC,&start);
 for(unsigned i=0;i<repetitions;i++) {
  if(axis) {set(font,v,axis==2?2:1);const int*p=coords(font,&count);for(unsigned j=0;j<count;j++)checksum+=(int64_t)p[j];}
  else checksum+=(int64_t)advance(font,1);
 }
 clock_gettime(CLOCK_MONOTONIC,&end);
 *elapsed=(uint64_t)end.tv_sec*1000000000+end.tv_nsec-((uint64_t)start.tv_sec*1000000000+start.tv_nsec);return checksum;
}
