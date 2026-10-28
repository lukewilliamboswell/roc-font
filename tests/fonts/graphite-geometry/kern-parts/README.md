# Original phase3 subbox controls

These 36 UPL programs independently put a full, left, right, bottom, top or
split subbox set on the target, its neighbor or unused glyph 0. The authored
whole bounds and collision attributes remain unchanged. Both native directions
are covered. Bytes follow the documented Glat3 bitmap and eight-byte entries.

Target and neighbor parts both change reference kerning. In LTR, a half-left
target changes advance −110 to 40.58824157714844. In RTL, a half-right target
changes the physical origin 310 to 160.58824157714844; a half-left neighbor gives
159.41175842285156. A part on unused glyph 0 leaves non-preloaded geometry
unchanged while satisfying the separately observed preload-mode condition.

The bin frame stays anchored to the complete target-cluster bounds: even a
part restricted to its top half retains cache minY −10 and maxY 610. Parts supply
occupied ink within that frame. The implementation uses a flat target-edge
union cache followed by neighbor-part scans; it does not multiply target-parts
by neighbor-parts by bin count.

`generate.py --check`, the parent `record.py --check`, and
`record_traces.py --check` reproduce/check the original bytes, public C-API
results and documented public JSON observations. Use `--cases
kern-parts/cases.jsonc` and matching `--output kern-parts/records.json` or
`kern-parts/traces.json`. No engine implementation source was opened or used.
A recorded reference result is not a native Roc parity claim.
