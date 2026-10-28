Original UPL public observations of deletion-time attachment pruning. The
independent three-pass originals under graphite-geometry/deleted-leaf-audit
establish the complete tree before selecting deletion order. Eight
variants change just the documented ATTR_SET operand User0→ShiftY in their
second pass, making the retained attachment reference visible in glyph runs.
The input bytes and exact changed Silf offsets are pinned in facts.json.

Deleting the first child A unlinks it from B's children but preserves the deleted slot's
own attachment status: a post-DELETE AttachTo getter writes ShiftY1 on live B. The detached
control writes0; constant123 proves cursor/storage. Both native directions
are covered with matching caller script direction, so the RTL cases execute
the authored ABCD rule rather than reversing its input in the HB frontend.

All thirteen variants pass OTS9.3 with Graphite tables unchanged. The 100 cached
true HarfBuzz14.6/Graphite2 1.3.14 runs compare complete glyphs, advances,
offsets, clusters and flags; they also cover the ten independent deletion-order
originals at both cluster levels. No library implementation source was read
or translated. check.py needs only fontTools and cached records; the native
replay uses the shared public query and served package.

Four additional two-child stars change the first relative attachment from1 to2,
making A and D siblings. Deleting first child A unlinks it; deleting later D
retains its inactive node as A.sibling and still reserves its advance. These
original counterexamples reject an overbroad previous-sibling unlink rule.
Independent separate-pass three-sibling controls also confirm head-only
pruning, with middle/tail inactive nodes remaining linked. AttachTo returns
a boolean attached status, not a numeric parent glyph ID.

A separate NEXT;DELETE;RET_ONE rule is valid despite its one-slot match:
text `ab` supplies B to DELETE and succeeds, while text `a` reaches a missing
current slot and aborts the whole segment. Empty text succeeds. Fifty-six cached
complete answers cover five texts, two selected ranges, all caller directions
and both cluster levels; this is ProgramAborted, not a work-limit stop or an engine fallback.
