# Segment-origin rebasing

Twelve original UPL programs place a zero-advance two-mark chain after a
separate root. The relative intermediate anchor is −27 and the leaf adds 30.
Preceding advances 0, 10 and 26 still cause the complete 27-unit relative rebase.
Advances 27, 28 and 604 put that negative-relative anchor at or after segment X = 0,
so no rebase occurs. This is an all-or-none origin-crossing condition, rather
than a partial shift just large enough to reach zero. Both native directions
are included.

The licensed real Scheherazade `اللَّه` case pins the same condition: an interior
base already has positive segment position, so its negative-relative marks do
not widen the run. Its original font and SIL license remain under `../graphite/`.
The synthetic font programs use the local UPL license.

`generate.py --check` reproduces bytes and cases; the parent raw extractor
checks cached public Graphite2 1.3.14 records with `--cases
segment-origin/cases.jsonc --output segment-origin/records.json --check`.
No engine implementation source was opened or used. Native Roc replay remains
a separate gate; these records are independent reference evidence.

Eight additional controls hold the preceding root at 602 and the child anchor
at −601 while varying its advance through −1, 0, 1, 601. Positive advances reserve
the full negative relative extent: child position 602, parent 1203. Zero and
negative advances permit the overlay: child position 1, parent 602. This applies
in both native directions and distinguishes the rule from origin crossing alone.
