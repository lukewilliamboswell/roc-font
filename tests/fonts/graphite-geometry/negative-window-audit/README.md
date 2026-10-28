Original UPL three-root negative-X collision regression. A is at (1967,170),
B at (1284,0), and C at (0,0). A has a 300×600 box; B and C have 1000×600
boxes. A is FIX, with X limits [-1000,0], Y limits [-1,1], and zero margin.

The near obstacle removes X interval [-983,317]. The farther obstacle removes
[-2267,-967], blocking the apparent escape at -983. The public reference
retains both constraints and returns zero shift. The old source guard drops
the farther obstacle because it reuses the displayed overlap box's symmetric
X minimum (0) as a projected movement minimum. The old native package takes
that escape, producing advances 1284/-300/1584 instead of 1284/683/601. No work
budget is exhausted. `before-proof.json` pins the exact consumer and answers.

A full subbox on unused glyph 0 neutralizes the separate preload defect.
Modes 0 and 6 produce identical raw public slot facts and results here; this
case receives no preload compatibility exception. Cached raw CAPI records,
public collision trace, and pinned HB14.6 glyph runs remain independent.
The fixture establishes the mismatch; it does not prove a general replacement
predicate. A candidate must also preserve the other boundary controls.

`generate.py --check` reproduces the font and cases. No engine implementation
source was inspected or ported.
