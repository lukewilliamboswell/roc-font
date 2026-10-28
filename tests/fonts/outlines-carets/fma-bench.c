/* Native HarfBuzz inner-loop comparator. The callback is resolved from the
 * same pinned library as the recorded oracle; Python calls this once per
 * measurement, avoiding a ctypes crossing for every glyph query. */
#include <stdint.h>
#include <time.h>
typedef struct { int32_t x_bearing, y_bearing, width, height; } extents;
typedef int (*extents_fn)(void *, uint32_t, extents *);
int64_t measure_extents(uintptr_t function, void *font, uint64_t count,
                        uint64_t *elapsed_ns) {
    extents_fn get_extents = (extents_fn)function;
    extents box;
    struct timespec start, end;
    int64_t sum = 0;
    clock_gettime(CLOCK_MONOTONIC, &start);
    for (uint64_t i = 0; i < count; i++) {
        if (get_extents(font, 4, &box)) {
            sum += 2 * (int64_t)box.x_bearing + box.width
                 + 2 * (int64_t)box.y_bearing + box.height;
        }
    }
    clock_gettime(CLOCK_MONOTONIC, &end);
    *elapsed_ns = (uint64_t)end.tv_sec * 1000000000 + end.tv_nsec
                - ((uint64_t)start.tv_sec * 1000000000 + start.tv_nsec);
    return sum;
}
