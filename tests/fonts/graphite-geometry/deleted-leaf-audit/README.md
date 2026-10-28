# DELETE-time attachment pruning

These 18 original UPL fonts use documented GTF/OpCodes structures, proper Silf 5 tables and original geometry/programs. No Graphite2 implementation source was read or translated. All pass OTS 9.3 with every Graphite table retained byte for byte. Collision stages are disabled so unrelated SHIFT choices cannot explain the widths.

The first pass establishes the complete attachment chain A(glyph1) → D(glyph2) → root(glyph3), with an independent trailing root(glyph4). A advances 1; D advances 5000; the roots advance 603/604. The second pass selects the deletion order. Only the third pass positions the remaining run. Both deletion orders therefore start with the same established tree.

Public Graphite2 1.3.14 results agree in native LTR and RTL:

| Deletion | Active slots | Root's first attachment | D's retained child | Segment width |
|---|---|---|---|---:|
| None | A,D,root,tail | D | A | 5684 |
| D only | A,root,tail | inactive D | A | 5684 |
| A only | D,root,tail | D | none | 5684 |
| D then A | root,tail | inactive D | none | 5684 |
| A then D | root,tail | none | unreachable | 1207 |

After D-then-A, the now-childless dead D remains attached and its advance still contributes. Final dead-leaf skipping or pruning based on currently active descendants would lose that result. The observations instead distinguish leaf unlinking at DELETE time. Removing A first makes D a leaf when D is later deleted; deleting D while it has A retains the intermediate link even after A is subsequently removed.

The raw extractor preserves active slots separately from every node reachable through public parent/first-child/sibling pointers, while the segment is alive. A visited-pointer set and hard bound prevent cycles. It never manufactures pointers to pruned nodes. Retained dead D itself still reports parent=root and child=None in the D-then-A case.

The separate getter controls pin an unreachable leaf's own parent reference. Pass0 establishes leaf A→live B. Pass1 executes `DELETE A; PUSH_SLOT_ATTR AttachTo offset0; NEXT; ATTR_SET User0`, with one declared user attribute. B's first-child link is empty afterward, but its stored result is 1. The detached-A control stores 0; an otherwise identical constant123 control stores 123, proving cursor/storage. Both directions agree. Thus unlinking from the parent's child list does not clear A's own observable attach.to reference. No unobserved claim is made about pruned sibling fields.

Unlogged mode0/6 records, the same tracing library with logging disabled, and direct true HarfBuzz 14.6 Graphite results are cached. The raw modes match bit for bit. Each logging-enabled query runs in a separate subprocess: 12 complete and match the unlogged public result exactly; six (A-only, D-then-A, A-then-D in both directions) terminate with SIGSEGV (-11) in the reference process. Those failures are preserved with binary/font hashes, exit status and only the actually written partial trace text. No successful result or complete trace is invented for them. This is a reference instrumentation failure, not a package waiver or font-program abort. All 18 fonts remain in the unlogged behavioral corpus.

`check.py` reproduces fonts/cases, verifies every key, checks actual SFNT action bytes and pass boundaries, validates OTS retention and asserts widths, links, getter values and logging outcomes without any oracle installed. Generation uses fontTools 4.61.1. Every reference version and library/binary hash is pinned in the caches. `record_logging.py` normalizes only ephemeral public trace identifiers and retains partial text explicitly as incomplete.

Run `python tests/fonts/graphite-geometry/deleted-leaf-audit/check.py` from the repository root. `record.py` refreshes raw data; select mode6 paths and the tracing library for the matching unlogged record. `record_hb.py`, `record_ots.py` and `record_logging.py` refresh their separate evidence. No core change, selector, generated Roc expected source, tolerance or deliberate behavioral exception is included.
