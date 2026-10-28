# Isolated frame candidate replay

The active geometry implementation remains the verified prefix/broad fix from `1d2cb0b`. The isolated frame candidate is `cb95122`, composed from shared `5e5c31d` plus `f303044` and `9440bb9`. It is not activated by this evidence commit.

The public native query was built with explicit `--opt=dev`, the recorded October 27 compiler, an immutable served bundle and a source-sentinel mirror. The full replay uses 1,374 geometry cases. The independently cached face-0 baseline is 1,368/1,374. The candidate improves this to 1,370/1,374 in both modes, with the same 425 precisely declared default-preload differences. It fixes `sample--603` and `negative-upper--12`. Reset, the unrestricted second-pass SHIFT discrepancy and two unattached downstream controls remain strict failures; no tolerance or exception was added.

All previously passing shared matrices remain green. Main real-font agreement stays 1,024/1,069 with the same 45 Awami failure IDs. Only two already-failing text-17 LTR outputs change numerically: one space advance moves from 643 to 621 toward the expected 512; another moves from 2 to 15 away from the expected -141. Unresolved NSM geometry remains unchanged. These results do not establish a real-font fix.

`combined-report.json` retains every matrix result and failure list; `build-provenance.json` records the exact source, artifact, compiler, native binary and module hashes. The reports use cached independent references without loading an oracle. This is dev semantic evidence, not optimized timing, fuzz, release validation or a claim of complete Graphite support.
