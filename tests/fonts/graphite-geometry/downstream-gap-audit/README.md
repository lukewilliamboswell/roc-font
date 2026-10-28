# Ordered finite and empty collision-kerning comparisons

These 27 original UPL fonts use proper Silf 5 data and documented GTF/OpCodes structures. No Graphite2 implementation source was read or translated. Single-pass programs set every advance to zero, avoiding prior SHIFT ties, attachment-prefix movement and mixed final-position timing. One controlled future child has zero attachment coordinates. All fonts pass OTS 9.3 with Graphite table bytes unchanged.

LTR comparison order is observable. A finite comparison followed by an eligible empty one produces target advance 120; reversing their logical order produces -210, with identical physical geometry. Two later empty neighbors preserve the larger bound regardless of their order. Eligible-empty-only runs retain the sentinel clamp; outside-vector neighbors are skipped.

The observed reduction is ordered: ordinary finite comparisons reduce the running gap; an LTR empty comparison can raise it. “Empty” here refers to the WHOLE neighbor's vertical bin interval containing no finite target cells. It is not a test of only the neighbor's actual parts, and not merely disjointness from the target's overall occupied span:

- A target with two separated Y parts has an internal unoccupied hole. A whole neighbor inside that hole triggers the update despite lying inside the overall span.
- A whole neighbor spanning target cells does not trigger it when that neighbor's sole actual part misses every target cell. Mixed finite/empty neighbor parts give the ordinary result in both part orders.
- Cropping an empty neighbor's actual xMin leaves the update unchanged: its WHOLE left edge is used.

The numeric LTR bound fits `max(finite cached targetEdge) + margin - neighborWholeLeftWorld`. TargetEdge already includes the first margin. A cropped target yields advance -29.411758422851562, whereas its unchanged whole bbox would give 120. A diagonal-trimmed target has sampled bound approximately 565.274 and yields 475.27447509765625, distinct from rectangular-bbox prediction 720. A future target child outside the allocated Y vector does not affect the bound (advance 120); moving only its Y into the vector yields 620. Thus conservative all-part bounds must not replace the sampled finite-edge bound.

RTL controls retain their ordinary result: positive and negative finite gaps, exact mirrored geometry, both neighbor orders and eligible-empty-only versus outside-vector cases are preserved. No symmetric RTL update is inferred. Width/margin controls independently support the LTR numeric rule. Exact binary32 associations beyond these witnesses remain unseparated; no epsilon or tolerance is used.

Every raw result matches bit for bit in face modes 0/6 and with logging OFF/ON on the SAME tracing library. Direct true HarfBuzz 14.6 Graphite runs retain full glyphs/clusters/advances/offsets/flags. Public trace text is normalized only for ephemeral IDs. The preserved pre-fix query passes 12/27; every actual/reference answer is retained in `before-public-proof.json` without filtering.

Run `python tests/fonts/graphite-geometry/downstream-gap-audit/check.py` from the repository root. It reproduces fonts/cases, checks all oracle/OTS keys and mode/logging equality, and verifies the exact directional, order, part, hole and sampled-bound observations without oracle libraries. Generation used fontTools 4.61.1; versions and binary/library hashes are pinned.

Adjacent `record.py`, `record_hb.py`, `record_ots.py` and `record_logging.py` refresh their respective records. Parent `record_traces.py --cases downstream-gap-audit/cases.jsonc --output downstream-gap-audit/traces.json` refreshes public traces. No core source, selector, generated Roc expected source or deliberate behavioral exception is included.

`target_right_midpoint.py --check` independently decodes the diagonal font and uses the PUBLIC observed occupied-cell set. At cell 46 the diagonal intersection Y300 lies above midpoint 299 but below HIGH302.33331298828125. Choosing DIFF at the midpoint and evaluating it at HIGH gives sampled peak 565.27447509765625, predicting advance 475.27447509765625 with EXACT public binary32 bits. Taking the minimum of both facets at HIGH instead gives peak 560.60784912109375 and advance 470.60784912109375. The proof pins font/raw/trace hashes and preserves every computed cell; it does not claim to derive the occupied-cell set or generalize RTL/point behavior. No oracle tolerance is introduced.
