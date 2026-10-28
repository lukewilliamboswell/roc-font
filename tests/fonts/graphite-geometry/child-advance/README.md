# Attached-child advances

These 20 original UPL programs and the licensed real Charis acute-accent case
pin which child metrics contribute to a cluster's advance. Both native font
directions are included. The explicit public script follows that native
direction; separate Latin/RTL cases test the adapter's script-direction reversal.

For LTR root advance 602 and attached child at x = 1000, child advances −601, −1 and 0
leave cluster advance 602; advance 1 gives 1001 and advance 601 gives 1601. At
x = −1000 every child still contributes to left rebasing, producing advance 1602.
Thus the right extent includes only strictly positive child advances; physical
placement and left rebasing retain nonpositive children.

The real Charis `a + U+0301` case has root glyph 68 advance 1042, child 634 advance 0
at physical x = 1067, and segment advance 1042. Including that zero-advance child's
right edge incorrectly widens the root by 25 and loses the public mark offset.
Raw results are recorded through Graphite2 1.3.14's public ABI, without opening
or using engine implementation source. Direct HB14.6 public glyph-run records
are also included in the parent public matrix. Native Roc agreement is a
separate gate.

Run the generator with `--check`, then the parent `record.py --check` with
`--cases child-advance/cases.jsonc --output child-advance/records.json`.
Original generated fonts use the parent UPL license. Charis uses the existing
licensed caller font under `../graphite/` with its license text.
