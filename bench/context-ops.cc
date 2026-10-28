// UPL-licensed diagnostic for the pinned HarfBuzz14.6 internal budget.
// Compile with matching Meson config and src include paths, and link the
// same pinned shared library. This is an oracle probe, not package code.
#include "hb-buffer.hh"
#include "hb-ot.h"
#include <cstdio>
#include <cstdlib>
#include <string>
static hb_bool_t message(hb_buffer_t*b,hb_font_t*,const char*m,void*){
 if (!strncmp(m,"start",5)||!strncmp(m,"end",3)) fprintf(stderr,"ops=%d len=%u idx=%u out=%u %s\n",b->max_ops,b->len,b->idx,b->out_len,m);
 return true;
}
int main(int argc,char**argv){
 if(argc!=3){fprintf(stderr,"usage: context-ops FONT PADDING\n");return 2;}
 fprintf(stderr,"HarfBuzz %s\n",hb_version_string());
 hb_blob_t*blob=hb_blob_create_from_file_or_fail(argv[1]);hb_face_t*face=hb_face_create(blob,0);hb_font_t*font=hb_font_create(face);hb_ot_font_set_funcs(font);
 std::string text="a\xcc\x81";text+=std::string(atoi(argv[2]),' ');
 hb_buffer_t*b=hb_buffer_create();hb_buffer_add_utf8(b,text.data(),text.size(),0,text.size());hb_buffer_set_direction(b,HB_DIRECTION_LTR);hb_buffer_set_script(b,HB_SCRIPT_LATIN);hb_buffer_set_language(b,hb_language_from_string("en",-1));hb_buffer_set_message_func(b,message,nullptr,nullptr);
 fprintf(stderr,"before ops=%d len=%u\n",b->max_ops,b->len);hb_shape(font,b,nullptr,0);fprintf(stderr,"after ops=%d successful=%d\n",b->max_ops,b->successful);
 hb_buffer_destroy(b);hb_font_destroy(font);hb_face_destroy(face);hb_blob_destroy(blob);
}
