# Composite glyph metrics after DELETE

These 22 original UPL fonts query metrics after deleting an attachment node. They use the separate original deleted-leaf/sibling builders, documented GTF/OpCodes structures and proper Silf 5 data. No Graphite2 implementation source was read or translated. All pass OTS 9.3 with every Graphite table retained unchanged.

Setup and deletion occupy separate substitution passes. A final positioning pass queries the root's `PUSH_GLYPH_METRIC`, stores its result in a declared User0 attribute, then copies that captured value into the independent trailing root's advance. Thus raw C API observations can distinguish the VM metric from authored slot advances, while an ordinary public glyph-run oracle also detects incorrect metric traversal. The queried attachment cluster itself is not changed to encode the answer.

| Case | Advance metric 8 level 0/1 | Top metric 2 level 0/1 | Right metric 5 level 0/1 |
|---|---:|---:|---:|
| Retained dead intermediate | 603 / 5080 | 600 / 940 | 300 / 460 |
| Retained dead middle sibling | 604 / 9080 | 600 / 770 | 300 / 380 |
| Retained dead tail sibling | 604 / 9080 | 600 / 770 | 300 / 380 |
| Pruned head sibling | 604 / 604 | 600 / 770 | 300 / 380 |

Level 0 uses nominal glyph metrics. Level 1 includes nodes still linked into the composite, including deleted nodes. A pruned head's advance is excluded; its active sibling geometry still explains the extended top/right bounds. The intermediate's active descendant also contributes beyond the dead node. Native RTL advance controls reproduce the same values.

Direct public Graphite2 1.3.14 mode 0/6 and unlogged tracing-library results agree bit for bit. Full true HarfBuzz 14.6 Graphite runs are cached. The preserved before query passes 14/22 and fails exactly the retained-deleted-node metric witnesses; `before-public-proof.json` retains all actual/reference runs. No failure is filtered from the oracle.

Logging queries are isolated per font. Seventeen complete and agree exactly with unlogged results. The five pruned-head cases encounter the previously recorded reference logger SIGSEGV (-11); binary/font hashes, status and actual partial trace text are retained, with no fabricated successful record. All 22 remain valid unlogged behavioral cases.

Run `python tests/fonts/graphite-geometry/deleted-metric-audit/check.py` from the repository root. It reproduces fonts/cases, verifies all keys and OTS retention, and checks raw User0 versus public trailing advances, mode equality and logging outcomes without oracle libraries. Generation used fontTools 4.61.1; library/binary versions and hashes are pinned. Adjacent `record.py`, `record_hb.py`, `record_ots.py` and `record_logging.py` refresh the separate evidence.

No core source, selector, generated Roc expectation, tolerance or deliberate behavioral exception is included.
