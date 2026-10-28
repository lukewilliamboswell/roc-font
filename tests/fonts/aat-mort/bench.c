/* Native HB14.6 shape comparator; font and text size are runtime inputs. */
#include <hb.h>
#include <hb-ot.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc,char **argv) {
  if(argc==2){puts(hb_version_string());return 0;}
  if(argc!=4)return 2;
  uint64_t count=strtoull(argv[2],NULL,10);
  unsigned length=(unsigned)strtoul(argv[3],NULL,10);
  if(count>1000000 || length>1024)return 2;
  hb_blob_t *blob=hb_blob_create_from_file_or_fail(argv[1]);if(!blob)return 3;
  hb_face_t *face=hb_face_create(blob,0);hb_font_t *font=hb_font_create(face);hb_ot_font_set_funcs(font);
  unsigned upem=hb_face_get_upem(face);hb_font_set_scale(font,(int)upem,(int)upem);
  char *text=malloc(length+1);if(!text)return 4;memset(text,'a',length);text[length]=0;
  int64_t sum=0;const char *shapers[]={"ot",NULL};
  for(uint64_t iteration=0;iteration<count;iteration++) {
    hb_buffer_t *buffer=hb_buffer_create();hb_buffer_set_direction(buffer,HB_DIRECTION_LTR);
    hb_buffer_set_script(buffer,HB_SCRIPT_LATIN);hb_buffer_set_language(buffer,hb_language_from_string("und",-1));
    hb_buffer_add_utf8(buffer,text,(int)length,0,(int)length);
    if(!hb_shape_full(font,buffer,NULL,0,shapers))return 5;
    unsigned n;hb_glyph_info_t *info=hb_buffer_get_glyph_infos(buffer,&n);
    hb_glyph_position_t *pos=hb_buffer_get_glyph_positions(buffer,NULL);
    for(unsigned i=0;i<n;i++)sum+=info[i].codepoint+info[i].cluster+(int64_t)pos[i].x_advance+pos[i].y_advance+pos[i].x_offset+pos[i].y_offset+hb_glyph_info_get_glyph_flags(&info[i]);
    hb_buffer_destroy(buffer);
  }
  printf("%lld\n",(long long)sum);free(text);hb_font_destroy(font);hb_face_destroy(face);hb_blob_destroy(blob);return 0;
}
