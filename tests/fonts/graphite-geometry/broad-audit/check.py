"""Check cached public records and font hashes using only the standard library."""
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
PARENT = HERE.parent
cases = json.loads((HERE / "cases.jsonc").read_text())["cases"]
assert len({case["id"] for case in cases}) == len(cases)
for file in ("records.json", "traces.json"):
    saved = json.loads((HERE / file).read_text())
    records = {record["id"]: record for record in saved["records"]}
    assert len(records) == len(cases), file
    for case in cases:
        font = hashlib.sha256((PARENT / case["font"]).read_bytes()).hexdigest()
        value = {"case": case, "font": font, "oracle": saved["oracle"]}
        canonical = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
        key = hashlib.sha256(canonical).hexdigest()
        assert records[case["id"]]["key"] == key, (file, case["id"])
    print(len(cases), file, "keys current")
# The renamed fixture fonts must retain the original public outputs and trace
# classification, not merely reproduce a new, self-consistent cache key.
recipes = json.loads((HERE / "recipes.json").read_text())["recipes"]
results = json.loads((HERE / "records.json").read_text())["records"]
traces = json.loads((HERE / "traces.json").read_text())["records"]
assert len(recipes) == len(results) == len(traces)
for recipe, result, trace in zip(recipes, results, traces):
    actual = result["result"]
    wanted = recipe["source_api_bits"]
    assert actual["advance_bits"][0] == wanted["advance_x_bits"], result["id"]
    assert len(actual["slots"]) == len(wanted["slots"])
    for a, b in zip(actual["slots"], wanted["slots"]):
        for key in ("glyph", "position_bits", "advance_bits", "collision_attributes"):
            assert a[key] == b[key], (result["id"], key)
    moves = [move for passes in trace["collisions"] for phase in passes for move in phase.get("moves", [])]
    mode = "missed" if "missed" in moves[-1] else "full"
    assert mode == recipe["source_expected_mode"], result["id"]
print(len(recipes), "original public results and full/missed classifications preserved")
