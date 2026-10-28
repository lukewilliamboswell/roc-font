"""Record source/data hashes; --check requires neither fonts tools nor oracles."""
import argparse
import hashlib
import json
from pathlib import Path
HERE = Path(__file__).resolve().parent
p = argparse.ArgumentParser()
p.add_argument('--check', action='store_true')
a = p.parse_args()
# Parent builders/extractors are dependencies, not copied engine algorithms.
parents = ['../generate.py', '../collision_generate.py', '../kerning-audit/generate.py', '../kern-frame-audit/generate.py', '../record_traces.py']
paths = sorted([path.name for path in HERE.iterdir() if path.is_file() and path.name != 'provenance.json'] + parents)
hashes = {path: hashlib.sha256((HERE / path).read_bytes()).hexdigest() for path in paths}
output = HERE / 'provenance.json'
if a.check:
    saved = json.loads(output.read_text())
    assert saved['sha256'] == hashes, 'audit sources/data changed; explicitly refresh provenance after review'
    print('Original asset/helper provenance hashes current')
else:
    import fontTools
    output.write_text(json.dumps({'about': 'Original UPL synthetic controls, documented formats and public APIs only. No reference implementation source was read. Engine library hashes and exact record keys are in each record cache.', 'fonttools': fontTools.__version__, 'sha256': hashes}, indent=2) + '\n')
