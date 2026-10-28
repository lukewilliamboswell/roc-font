# Attachment timing and deleted intermediate slots

These 23 original UPL fonts isolate attachment timing, SHIFT candidate collection and the geometry of a deleted attachment intermediate. They use documented GTF/OpCodes structures, original synthetic rectangles and public Graphite2 1.3.14 C APIs only. No reference implementation source was read or translated. The font generator calls the adjacent original builders; a full subbox on unused glyph 0 retains the preload-neutral control. Font timestamps and generation are deterministic with fontTools 4.61.1.

The assets are evidence, not a claimed general attachment/candidate algorithm. In particular, **unconditionally excluding a target's strict descendants is disproved by these controls**. They do not claim native Roc agreement.

## Seven family controls: stage-dependent candidate collection

The first positioning pass shifts the selected target upward 600 units. A second positioning rule then creates a direct descendant, a two-level descendant chain, an ancestor, or a sibling relation. The second collision pass uses those attachments and retains the prior collision offset.

For direct and two-level descendants, the second-pass trace contains only the external obstacle, returns delta zero, and leaves the target at Y 600. Ignoring the direct child or the intermediate child changes neither reference result. The active grandchild in the two-level ignored-middle control still has flags zero. In contrast, the ancestor and common-root sibling controls retain the related active slots as obstacles. Ignoring the sibling removes that obstacle and changes the completed target Y from 770 to 600.

This is not a universal descendant filter. Four complementary controls attach the chain `A -> D -> target` in a **substitution pass before positioning**. With all nodes live, the reference includes both descendants as obstacles and shifts the target to Y -430. Ignoring A leaves D as an obstacle and preserves that result. The difference in stage/prior state is intentional; these controls do not identify the complete condition explaining the earlier exclusions.

The original investigation began with an apparent choice between equal-cost +/-600 solutions. First-pass-only probes showed the original and Roc queries both selecting +600. The observed sign change arose in the later collision pass. The surviving corpus therefore describes a second-pass candidate discrepancy, not a proven tie-policy change.

## Deleted intermediates preserve geometry and reserve width

The other two substitution-stage controls delete D after creating `A -> D -> target`. DELETE occurs before the first positioning pass, where it is legal. D disappears from the active list but remains reachable through A's public `gr_slot_attached_to` result. With A active, the reference retains A as an obstacle: target Y -260, A Y 80. With A ignored, target Y is zero and A Y is 340. D's presence in the attachment transform survives deletion.

Six positive-width controls keep A ignored and vary only its authored advance (0/1) and D's authored advance (-5000/0/+5000). D remains positioned at (80,170), A at (160,340), and the target at (0,0). D's public advance remains the authored value. For D advance -5000 or zero, the following root starts at X 603 and segment advance is 1207. For D advance +5000, the following root starts at X **5080 = 80 + 5000** and segment advance is 5684. Thus this dead intermediate participates in positive right-edge reservation, not merely coordinate inheritance.

Six left-bound controls give D a relative X of -80 and A a relative X of +80, so A's pre-rebase X is zero. Raw attachment points are D.attachX=-60/withX=20 and A.attachX=100/withX=20. D advances -1/0/+1 crossed with A advances 0/1 all produce the same result: target X 80, D X zero, A X 80, following-root X 683, segment advance 1287. D's own negative origin reserves the left 80 units even with a nonpositive advance. These controls do not derive behavior at a nonzero preceding pen or all other combinations of deleted metrics.

## Immutable public records and validation

`records.json` and `mode6-records.json` preserve exact binary32 position/advance bits, active attachment links expressed as glyph ids, collision attributes and the deleted intermediate's position/advance/attributes queried through its stable public parent link. They contain no raw addresses. `record.py` is the small public C-ABI extractor; its separate `attachment_lifetime_extractor` version identifies the extra dead-node fields. Every record key hashes the complete case, font bytes and oracle metadata, including library hash.

`traces.json` contains normalized public `gr_start_logging` observations. `tracing-off-records.json` and `tracing-on-records.json` query the **same tracing-capable library**, with logging disabled/enabled respectively. All 23 results match each other and the release-library mode-0/mode-6 results exactly, including dead-node attributes. These are non-NSM ASCII controls; this observation makes no claim about logging neutrality for other text or programs.

`ots-proof.json` records acceptance of all 23 fonts by pinned OTS 9.3.0, with sanitizer hash, font hashes and diagnostics. OTS checks structure; the public records separately check shaping behavior. `provenance.json` hashes the local assets and original helper dependencies and records the generation version.

Run the complete offline checks from the repository root, using a Python environment with fontTools:

```sh
python -B tests/fonts/graphite-geometry/attachment-lifetime-audit/check.py
```

This regenerates fonts/cases in check mode, validates every cache key, proves mode/logging equality and the documented independent relations, and checks OTS/provenance hashes. It does not load an oracle or run a Roc compiler.

To refresh references deliberately, run `record.py` with its default mode-0 cases/output, then:

```sh
python -B tests/fonts/graphite-geometry/attachment-lifetime-audit/record.py --cases attachment-lifetime-audit/mode6-cases.jsonc --output attachment-lifetime-audit/mode6-records.json
python -B tests/fonts/graphite-geometry/record_traces.py --cases attachment-lifetime-audit/cases.jsonc --output attachment-lifetime-audit/traces.json
python -B tests/fonts/graphite-geometry/attachment-lifetime-audit/record_ots.py
```

For the logging pair, select the same tracing-capable library with `record.py --library`, use the mode-6 cases and the respective tracing-off/on output names, and pass a temporary `--log-dir` only for the on run. Do not commit raw pointer-bearing log files. Refresh `provenance.py` after reviewing changed assets, then rerun `check.py`.
