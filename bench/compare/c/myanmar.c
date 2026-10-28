/* Myanmar/Burmese HarfBuzz comparison for bench/myanmar.py.
 *
 * Reads one case file from stdin (see bench/roc/FontBench.roc):
 *   <operation>\n<font length>\n<font bytes><text bytes>
 * prepares it outside the timed region, runs the operation `iterations`
 * times (the last argument) inside it, and prints one JSON line:
 *   {"iterations", "elapsed_ns", "successes", "checksum"}
 *
 * Operations:
 *   read     create a blob, face and font, and force HarfBuzz to load and
 *            sanitize the tables the Roc reader checks (cmap, hmtx, GSUB,
 *            GPOS), since HarfBuzz otherwise loads them lazily on first use.
 *            Sanitizing bounds-checks arrays of fixed-size records as one
 *            range, and nothing is copied, so this stays far cheaper than a
 *            reader that builds indexes; it is not a like-for-like read.
 *   cmap     hb_font_get_nominal_glyph for every code point of the text.
 *   advance  hb_font_get_glyph_h_advance for the glyph of every code point.
 *   shape    hb_buffer_add_utf8 then hb_shape with Mymr/my and default features.
 * Kerning on its own has no HarfBuzz equivalent and exits 3 (unsupported).
 *
 * The font's scale is left at units per em, so advances are in font units.
 */
#include <hb-ot.h>
#include <hb.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static uint64_t now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

static unsigned char *read_all(FILE *f, size_t *len) {
    size_t cap = 1 << 16, n = 0;
    unsigned char *buf = malloc(cap);
    for (;;) {
        if (n == cap) {
            cap *= 2;
            buf = realloc(buf, cap);
        }
        size_t got = fread(buf + n, 1, cap - n, f);
        if (got == 0) break;
        n += got;
    }
    *len = n;
    return buf;
}

/* Code points of UTF-8 text, U+FFFD for a malformed byte (as FontBench). */
static size_t decode_utf8(const unsigned char *s, size_t len, uint32_t *out) {
    size_t i = 0, n = 0;
    while (i < len) {
        uint32_t b0 = s[i];
        size_t width = b0 < 0x80 ? 1 : (b0 >= 0xC2 && b0 < 0xE0) ? 2 : (b0 >= 0xE0 && b0 < 0xF0) ? 3
                                                               : (b0 >= 0xF0 && b0 < 0xF5)  ? 4
                                                                                             : 0;
        if (width == 0 || i + width > len) {
            out[n++] = 0xFFFD;
            i++;
            continue;
        }
        uint32_t cp = width == 1 ? b0 : width == 2 ? (b0 & 0x1F) : width == 3 ? (b0 & 0x0F) : (b0 & 0x07);
        int ok = 1;
        for (size_t k = 1; k < width; k++) {
            if ((s[i + k] & 0xC0) != 0x80) ok = 0;
            cp = cp * 64 + (s[i + k] & 0x3F);
        }
        uint32_t min = width == 2 ? 0x80 : width == 3 ? 0x800 : 0x10000;
        if (ok && (width == 1 || cp >= min) && cp <= 0x10FFFF && !(cp >= 0xD800 && cp <= 0xDFFF)) {
            out[n++] = cp;
            i += width;
        } else {
            out[n++] = 0xFFFD;
            i++;
        }
    }
    return n;
}

int main(int argc, char **argv) {
    if (argc == 2 && !strcmp(argv[1], "--version")) { puts(hb_version_string()); return 0; }
    uint64_t iterations = argc > 1 ? strtoull(argv[argc - 1], NULL, 10) : 1;
    size_t len;
    unsigned char *input = read_all(stdin, &len);
    unsigned char *nl1 = memchr(input, '\n', len);
    if (!nl1) return 2;
    unsigned char *nl2 = memchr(nl1 + 1, '\n', len - (size_t)(nl1 + 1 - input));
    if (!nl2) return 2;
    char op[32] = {0};
    memcpy(op, input, (size_t)(nl1 - input) < sizeof op - 1 ? (size_t)(nl1 - input) : sizeof op - 1);
    size_t font_len = strtoull((char *)nl1 + 1, NULL, 10);
    unsigned char *font_bytes = nl2 + 1;
    size_t data_len = len - (size_t)(font_bytes - input);
    if (font_len > data_len) return 2;
    const unsigned char *text = font_bytes + font_len;
    size_t text_len = data_len - font_len;

    hb_blob_t *blob = hb_blob_create((const char *)font_bytes, (unsigned)font_len, HB_MEMORY_MODE_READONLY, NULL, NULL);
    hb_face_t *face = hb_face_create(blob, 0);
    hb_font_t *font = hb_font_create(face);
    uint32_t *cps = malloc(sizeof(uint32_t) * (text_len + 1));
    size_t cp_count = decode_utf8(text, text_len, cps);
    hb_codepoint_t *glyphs = malloc(sizeof(hb_codepoint_t) * (cp_count + 1));
    for (size_t i = 0; i < cp_count; i++) {
        if (!hb_font_get_nominal_glyph(font, cps[i], &glyphs[i])) glyphs[i] = 0;
    }
    hb_buffer_t *buf = hb_buffer_create();

    int which = strcmp(op, "read") == 0 ? 0 : strcmp(op, "cmap") == 0 ? 1 : strcmp(op, "advance") == 0 ? 2
                                          : strcmp(op, "shape") == 0  ? 3
                                                                      : -1;
    if (which < 0) {
        fprintf(stderr, "unsupported operation %s\n", op);
        return 3;
    }

    uint64_t checksum = 0, successes = 0;
    volatile uint64_t sink = 0;
    uint64_t start = now_ns();
    for (uint64_t it = 0; it < iterations; it++) {
        uint64_t sum = 0;
        int ok = 1;
        switch (which) {
        case 0: {
            hb_blob_t *b = hb_blob_create((const char *)font_bytes, (unsigned)font_len, HB_MEMORY_MODE_READONLY, NULL, NULL);
            hb_face_t *fc = hb_face_create(b, 0);
            hb_font_t *f = hb_font_create(fc);
            hb_codepoint_t g = 0;
            hb_font_get_nominal_glyph(f, 'a', &g);
            /* The loads are kept observable through `sink`; the checksum
             * is glyph count plus units per em, as in FontBench. */
            sink += (uint64_t)hb_font_get_glyph_h_advance(f, g);
            sink += hb_ot_layout_table_get_lookup_count(fc, HB_OT_TAG_GSUB);
            sink += hb_ot_layout_table_get_lookup_count(fc, HB_OT_TAG_GPOS);
            sum = hb_face_get_glyph_count(fc) + hb_face_get_upem(fc);
            ok = hb_face_get_glyph_count(fc) > 0;
            hb_font_destroy(f);
            hb_face_destroy(fc);
            hb_blob_destroy(b);
            break;
        }
        case 1:
            for (size_t i = 0; i < cp_count; i++) {
                hb_codepoint_t g;
                if (hb_font_get_nominal_glyph(font, cps[i], &g)) sum += (uint64_t)g + 1;
            }
            break;
        case 2:
            for (size_t i = 0; i < cp_count; i++) sum += (uint64_t)hb_font_get_glyph_h_advance(font, glyphs[i]);
            break;
        case 3: {
            hb_buffer_clear_contents(buf);
            hb_buffer_add_utf8(buf, (const char *)text, (int)text_len, 0, (int)text_len);
            hb_buffer_set_direction(buf, HB_DIRECTION_LTR);
            hb_buffer_set_script(buf, HB_SCRIPT_MYANMAR);
            hb_buffer_set_language(buf, hb_language_from_string("my", -1));
            hb_shape(font, buf, NULL, 0);
            unsigned n;
            hb_glyph_info_t *info = hb_buffer_get_glyph_infos(buf, &n);
            hb_glyph_position_t *pos = hb_buffer_get_glyph_positions(buf, &n);
            for (unsigned i = 0; i < n; i++) sum += info[i].codepoint + info[i].cluster + (uint64_t)(int64_t)pos[i].x_advance;
            break;
        }
        }
        checksum += sum;
        successes += ok;
    }
    uint64_t elapsed = now_ns() - start;
    (void)sink;
    printf("{\"iterations\":%llu,\"elapsed_ns\":%llu,\"successes\":%llu,\"checksum\":%llu}\n",
           (unsigned long long)iterations, (unsigned long long)elapsed, (unsigned long long)successes,
           (unsigned long long)checksum);
    hb_buffer_destroy(buf);
    hb_font_destroy(font);
    hb_face_destroy(face);
    hb_blob_destroy(blob);
    free(glyphs);
    free(cps);
    free(input);
    return 0;
}
