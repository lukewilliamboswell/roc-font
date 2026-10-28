# Positioning numerical change evidence

This compares the unchanged pair path with LayoutVar `0809d47` and
LayoutKerning `04101f1` on Roc nightly 2026-10-27-de79a0f. Both native consumers
import immutable served bundles; JSON records bundle, source, consumer and
binary hashes. The after bundle captured the LK diff before its commit;
the bundled source hash identifies the exact override.

All 64 preserved ordinary/corpus/adversarial benchmark cases have identical
allocation counts, leaks, results and checksums before/after. No allocation
baseline update is needed for this matrix. Inter shape uses 21 allocation
calls at 505 / 4088 / 32761 UTF-8 bytes, with zero leaks.

Three increasing optimized native shape cases have same-run HB 14.6.0 ratios
3.90/3.53/3.83 before and 4.00/3.44/3.57 after. The numerical change retains
the measured allocation behavior; these timings amid integration builds
do not establish a speedup. Reading/planning and process startup are
outside the timed region. Each of five samples repeats 128 operations;
checksums agree with the independently version-checked native comparator.

Both existing narrow targets were rebuilt with --fuzz --opt=speed against
the after bundle: font-gpos passed 1000 inputs with seed 266; font-layout-var
passed 1000 inputs with seed 267. Their generated two-size allocation/leak
contracts pass. Source closure has 212 expects, including private signed 32-bit
boundaries, stored/device cancellation, absolute-base pair positioning and
legacy odd-negative kerning. Public extreme-font oracle verification is
part of the integrator's separate GPOS numerical fixture gate.

roc-fuzz 0.4.3 cannot report requested bytes or peak live bytes. No RSS
substitute is presented. Full attachment propagation and anchor arithmetic
are integrated separately and are not attributed to this LV/LK-only run.
