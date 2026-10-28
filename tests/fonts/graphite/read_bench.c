/* Original C-API oracle benchmark: no reference implementation code copied. */
#include <graphite2/Font.h>
#include <stdint.h>
#include <stddef.h>
#include <time.h>
typedef struct { const uint8_t *bytes; size_t length; } Input;
static uint32_t u32(const uint8_t *p) { return (uint32_t)p[0]<<24 | (uint32_t)p[1]<<16 | (uint32_t)p[2]<<8 | p[3]; }
static const void *table(const void *app,unsigned tag,size_t *length) {
 const Input *in=app;*length=0;if(in->length<12)return NULL;
 unsigned count=(unsigned)in->bytes[4]<<8 | in->bytes[5];if(count>(in->length-12)/16)return NULL;
 for(unsigned i=0;i<count;i++){const uint8_t *p=in->bytes+12+16*i;if(u32(p)==tag){size_t at=u32(p+8),n=u32(p+12);if(at>in->length||n>in->length-at)return NULL;*length=n;return in->bytes+at;}}
 return NULL;
}
uint64_t graphite_read_elapsed(const uint8_t *bytes,size_t length,unsigned iterations,uint64_t *checksum) {
 Input input={bytes,length};gr_face_ops ops={sizeof(gr_face_ops),table,NULL};struct timespec a,b;*checksum=0;clock_gettime(CLOCK_MONOTONIC,&a);
 for(unsigned i=0;i<iterations;i++){gr_face *face=gr_make_face_with_ops(&input,&ops,0);if(!face)return UINT64_MAX;*checksum+=gr_face_n_glyphs(face);gr_face_destroy(face);}
 clock_gettime(CLOCK_MONOTONIC,&b);return (uint64_t)(b.tv_sec-a.tv_sec)*1000000000+(b.tv_nsec-a.tv_nsec);
}
