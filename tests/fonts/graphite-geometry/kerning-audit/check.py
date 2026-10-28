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
