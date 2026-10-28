# Three-sibling DELETE linkage

These 18 original UPL fonts independently extend the separate two-sibling controls under `tests/fonts/graphite/delete-leaf`. They use documented GTF/OpCodes structures, proper Silf 5 tables and original geometry/programs. No Graphite2 implementation source was read or translated. Every font passes OTS 9.3 with all Graphite tables retained byte for byte.

Pass 0 establishes root 4's complete child chain 1→2→3. Pass 1 optionally deletes one child. Pass 2 positions the run. Setup and deletion are therefore separated, and matching no-deletion cases retain the complete before tree. Collision stages are disabled.

In each fixture, ONLY the child selected for deletion advances 9000; the other two children advance 1. Root4 advances 604 and the trailing root 5 advances 605. This per-fixture metric choice makes each deletion's linkage effect visible in the width.

| Deleted child | Root's first child | Remaining child-chain links | Width |
|---|---|---|---:|
| None | 1 | 1→2→3 | 9685 |
| Head 1 | 2 | 2→3 | 1209 |
| Middle 2 | 1 | 1→inactive2→3 | 9685 |
| Tail 3 | 1 | 1→2→inactive3 | 9685 |

Both native directions agree. Deleting the head advances the root's first-child link to the former sibling 2; it does NOT drop the remaining chain. Active 2/3 retain parent 4. LTR positions after head deletion are children(80,170), root(0,0), tail(604,0). RTL positions are children(685,170), root(605,0), tail(0,0).

The deleted middle remains observable through live 1's sibling pointer; its own parent is 4 and sibling is 3. The deleted tail remains through live 2's sibling pointer, with parent 4 and no next sibling. Thus a generic predecessor search that unlinks every deleted leaf would change valid reference results. The bounded observation is head-only unlinking, retaining non-first dead nodes. This directory proposes no generalized repair or normative reinterpretation.

The isolated head getter pins an own-parent fact after head unlinking. `DELETE head; PUSH_SLOT_ATTR AttachTo offset0; NEXT; ATTR_SET User0` stores 1 on live sibling 2. A detached-head control stores 0; an otherwise identical constant 123 control stores 123. One user attribute is declared. Every getter/control preserves the final root child 2→3 chain and width 1209. The stored 1 is an observable AttachTo value, not a parent glyph ID or claimed numeric distance. No assertion is invented for the unreachable head's own sibling field.

Raw public C API records preserve active nodes separately from every inactive node reachable through returned parent/child/sibling pointers while the segment is alive. The traversal has a visited set and hard bound. Modes 0/6 and unlogged release/tracing results match bit for bit. Direct true HarfBuzz 14.6 Graphite records retain full positioned runs.

Logging is isolated per case. Sixteen logging-enabled queries complete and agree exactly with unlogged results. The two head-deletion cases without the getter's shared NEXT terminate with reference SIGSEGV (-11). Their binary/font hashes, exit status and only the actually written partial trace text are retained. No complete trace or answer is fabricated for these failures. All 18 valid fonts stay in the unlogged behavioral corpus; this is an instrumentation limitation, not a package exception.

Run `python tests/fonts/graphite-geometry/deleted-sibling-audit/check.py` from the repository root. It reproduces fonts/cases, checks actual SFNT programs/pass boundaries and all oracle keys, verifies OTS retention, and asserts the exact links, widths, positions, getter values and logging outcomes without oracle libraries. Generation used fontTools 4.61.1. `record.py`, `record_hb.py`, `record_ots.py` and `record_logging.py` refresh the separate evidence.

No shared source, selector, generated Roc expectation, tolerance or deliberate behavioral divergence is included.
