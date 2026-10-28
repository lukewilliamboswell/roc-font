These 324 original UPL fonts exercise Graphite geometry through the documented
GTF tables and bytecode language. No Graphite2 implementation source is copied
or translated. `generate.py` builds the bytes from scratch with fontTools
4.61.1; the adjacent licence covers the fonts and generator.

The oracle calls only Graphite2 1.3.14's public C ABI. Its engine version and
actual library SHA256 are cached with the records. Both directions are native
font directions, with `gr_nobidi` set, so these cases isolate shaping geometry
from Unicode bidi processing. Coordinates and advances are stored as exact
binary32 bits. Reference slots retain their authored advances; the segment's
advance is the separately computed attachment-cluster advance.

The matrix includes forward/backward attachments, self/cycle requests,
reattachment, deleted stable input targets, live copying, three-slot trees,
direction-dependent shifts, negative advances, justification widths,
attachment-level narrowing, composite metrics 0–10 at five levels, no-op point
attributes, and an action with one pre-context item. Every face is accepted by
the reference and by OTS 9.3 with Silf/Glat/Gloc retained. Four reference cases
abort at execution: copying directly between a parent and its attached child.
Copying an unrelated parent or child succeeds and has distinct tree semantics.

Self-attachment and attempted cycles are ignored, preserving the prior edge.
A deleted input target remains a valid stable reference. Its attached active
child is not an independent root, and therefore contributes no segment advance.
These are observed language behaviours, rather than substituted index-zero
fallbacks. A pre-context action's plain `ATTR_SET(AttTo)` uses the rule's full
input index; `ATTR_SET_SLOT` uses a relative input reference. Reading AttTo
through bytecode reports whether the slot has a parent; the C ABI's deprecated
AttTo accessor does not expose that value.

Regenerate and validate cache keys without an installed oracle:

```
python tests/fonts/graphite-geometry/generate.py --check
python tests/fonts/graphite-geometry/record.py --check
```

To replace the cached oracle, run `record.py` without `--check` using the pinned
library. `checks.json` distinguishes completed reader/source checks from pending
native integrated replay, fuzzing, and allocation measurements. Source checks
alone do not establish end-to-end shaping agreement.

The normative sources are the Graphite Binary Font Format and opcode documents
shipped with Graphite2 1.3.14 (`doc/GTF.asc`, `doc/OpCodes.asc`), and the
[SIL GDL reference](https://static-scripts.sil.org/cms/sites/projects/download/gdldocumentation/GDLdocumentation.pdf),
sections 4.6 and 6.8. Only the public API is used to resolve reference behaviour.
