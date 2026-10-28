These 446 original UPL fonts exercise Graphite geometry through the documented
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
the reference and by OTS 9.3 with Silf/Glat/Gloc retained. Twelve reference cases
abort at execution: overwriting an attached destination from another input slot.
Copying an unrelated parent or child into an independent slot succeeds and has distinct tree semantics. Self-copy preserves live links.

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

Collision controls also pin the initialization boundary. Collision state is
absent during substitution and is initialized from the resulting glyphs just
before positioning. A subsequent glyph replacement in a positioning pass
retains that state. Coordinate fields use signed16 values; flags, classes and
weights use unsigned16 values. Collision-shift fields 62/63 are read-only to
bytecode, even though the collision solver stores fractional binary32 shifts.
The matrix includes writes of −1 and 65536 to every collision attribute.

`collision_generate.py` adds 288 original collision programs: movement limits,
margin ownership and weights, four projection directions, two-pass reads,
collision kerning, overlapping START/END groups, sub-boxes, and inherited
parent shifts after long prefixes. `collision-records.json` stores their public
C-API results. The 21 separate box-dependency controls distinguish Glat versions
and collision-pass flags. Graphite2 rejects ten Glat1/2 controls with collision
bits, while it accepts the remaining controls. `record_fonttools.py` separately
records their decoded attributes; this matters for Glat3 without octaboxes,
where the specification/fontTools and Graphite2 disagree about attribute bytes.

`collision-traces.json` comes from the documented `gr_start_logging` API of a
separately built, pinned Graphite2 1.3.14 release with tracing enabled. Pointer
identifiers are renamed by initial slot order. It records observations of
intervals and costs; runtime code is original, rather than a translation of the
reference implementation. `record_traces.py --check` validates cache keys
without the reference installed. All 755 public-C-API results also agree between
this tracing build and the normal reference build, including floating-point
origin bits and face/program rejection.

The independent source components currently cover octabox decoding, projected
forbidden regions, piecewise quadratic interval costs, and overlapping group
boundaries. A complete collision pass additionally needs sequencing, exclusion
glyphs, retry scheduling, and collision kerning. These components are not yet an
end-to-end collision-stage support claim. Native public replay, fuzzing and
performance measurements remain listed separately in `checks.json`.

OTS accepts all 755 font containers and retains every Graphite table in 748.
Its seven Glat2 controls are accepted only after the Graphite tables are
stripped; those results are a reader-policy comparison, not validation of their
Graphite semantics. OTS also warns about collision attributes in Silf3, while
retaining the tables. The GTF document explicitly permits reserved fields to
acquire their later meaning in an earlier-version table.
