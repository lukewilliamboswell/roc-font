/* Native HarfBuzz14.6 comparator. Every callback consumes its coordinates. */
#include <hb.h>
#include <hb-ot.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static void move(hb_draw_funcs_t *f, void *data, hb_draw_state_t *s,
                 float x, float y, void *user) {
  (void)f; (void)s; (void)user; *(double *)data += (double)x + y;
}
static void line(hb_draw_funcs_t *f, void *data, hb_draw_state_t *s,
                 float x, float y, void *user) {
  move(f,data,s,x,y,user);
}
static void quadratic(hb_draw_funcs_t *f, void *data, hb_draw_state_t *s,
                      float x1,float y1,float x2,float y2,void *user) {
  move(f,data,s,x1,y1,user); move(f,data,s,x2,y2,user);
}
static void cubic(hb_draw_funcs_t *f, void *data, hb_draw_state_t *s,
                  float x1,float y1,float x2,float y2,float x3,float y3,void *user) {
  move(f,data,s,x1,y1,user); move(f,data,s,x2,y2,user); move(f,data,s,x3,y3,user);
}
static void close_path(hb_draw_funcs_t *f,void *data,hb_draw_state_t *s,void *user) {
  (void)f; (void)data; (void)s; (void)user;
}
int main(int argc,char **argv) {
  if (argc==2) { puts(hb_version_string()); return 0; }
  if (argc!=4) return 2;
  uint64_t count=strtoull(argv[2],NULL,10);
  int mode=atoi(argv[3]);
  if(count>1000000) return 2;
  hb_blob_t *blob=hb_blob_create_from_file_or_fail(argv[1]);
  if(!blob) return 3;
  hb_face_t *face=hb_face_create(blob,0);
  hb_font_t *font=hb_font_create(face);
  hb_ot_font_set_funcs(font);
  unsigned upem=hb_face_get_upem(face);
  hb_font_set_scale(font,(int)upem,(int)upem);
  /* Nondefault coordinates ensure CFF2 draw actually executes blends;
     HB14.6's all-zero draw shortcut omits constant-region contributions. */
  if (mode==1 || mode==2) {
    /* Font.from_bytes selects Regular400; outline timing explicitly500. */
    hb_variation_t variation = {HB_TAG('w','g','h','t'),mode==2 ? 500 : 400};
    hb_font_set_variations(font,&variation,1);
  }
  hb_draw_funcs_t *draw=hb_draw_funcs_create();
  hb_draw_funcs_set_move_to_func(draw,move,NULL,NULL);
  hb_draw_funcs_set_line_to_func(draw,line,NULL,NULL);
  hb_draw_funcs_set_quadratic_to_func(draw,quadratic,NULL,NULL);
  hb_draw_funcs_set_cubic_to_func(draw,cubic,NULL,NULL);
  hb_draw_funcs_set_close_path_func(draw,close_path,NULL,NULL);
  double sum=0;
  for(uint64_t i=0;i<count;i++) {
    if(mode==1) {
      hb_glyph_extents_t box;
      if(hb_font_get_glyph_extents(font,2,&box))
        sum += (double)box.x_bearing*2 + box.width + (double)box.y_bearing*2 + box.height;
    } else hb_font_draw_glyph(font,2,draw,&sum);
  }
  printf("%.0f\n",sum);
  hb_draw_funcs_destroy(draw);hb_font_destroy(font);hb_face_destroy(face);hb_blob_destroy(blob);
  return 0;
}
