Original UPL Graphite pass-condition controls, constructed from documented GTF
and OpCodes formats. The eight positive fonts use proper Silf 5 class maps,
full hmtx metrics, and a numeric feature 100 with declared settings 0 and 1.
The collision geometry comes from our original neutral four-subbox fixture.

Both ordinary and rule-free passes cover absent, false, true and feature-based
conditions. Rule-free passes still have one current slot for their condition;
their empty rule input map must not hide its feature value. A false condition
suppresses the collision phase as well as bytecode actions. The two invalid
fonts address a preceding/following slot from a pass condition: Graphite2
rejects their faces. These are reader tests, excluded from the shaping cases.

The 384 full public answers use pinned HarfBuzz 14.6 with Graphite2 1.3.14.
Twelve raw public C API controls independently establish feature choices and
collision movement; explicit settings are asserted accepted. All eight
positive files pass OTS 9.3.0. No engine implementation source was translated.
Run generate.py --check with --base pointing to benchmark-shift/shifting-parts.ttf,
then check.py and record_raw.py --check. The original base hash is in base.json.
