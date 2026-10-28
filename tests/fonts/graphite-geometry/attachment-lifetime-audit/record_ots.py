"""Cache pinned OTS structural acceptance; --check needs no sanitizer."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
HERE = Path(__file__).resolve().parent
sha = lambda data: hashlib.sha256(data).hexdigest()
p = argparse.ArgumentParser()
p.add_argument('--check', action='store_true')
p.add_argument('--binary', type=Path, default=Path('/private/tmp/roc-font-ots-build/ots-sanitize'))
a = p.parse_args()
cases = json.loads((HERE / 'cases.jsonc').read_text())['cases']
output = HERE / 'ots-proof.json'
if a.check:
    saved = json.loads(output.read_text())
    assert saved['version'] == '9.3.0' and saved['passed']
    assert len(saved['rows']) == len(cases)
    for case, row in zip(cases, saved['rows']):
        path = HERE.parent / case['font']
        assert row['font'] == path.name and row['font_sha256'] == sha(path.read_bytes())
        assert row['exit_code'] == 0
    print('23 cached OTS acceptance records current')
else:
    version = subprocess.run([str(a.binary), '--version'], text=True, capture_output=True, check=True).stdout.strip()
    assert '9.3.0' in version, version
    rows = []
    with tempfile.TemporaryDirectory(prefix='roc-attachment-lifetime-ots-') as tmp:
        for case in cases:
            path = HERE.parent / case['font']
            answer = subprocess.run([str(a.binary), str(path), str(Path(tmp) / 'sanitized.ttf')], text=True, capture_output=True)
            rows.append({'font': path.name, 'font_sha256': sha(path.read_bytes()), 'exit_code': answer.returncode, 'diagnostic': answer.stdout + answer.stderr})
    assert all(row['exit_code'] == 0 for row in rows), rows
    output.write_text(json.dumps({'oracle': 'OTS structural acceptance; shaping behavior checked separately through public Graphite APIs', 'version': '9.3.0', 'binary_sha256': sha(a.binary.read_bytes()), 'passed': True, 'rows': rows}, indent=2) + '\n')
    print('23 original fonts accepted by OTS9.3.0')
