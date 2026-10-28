"""Replay cached tracking records against the served public Roc package."""
from pathlib import Path
import argparse, hashlib, json, os, subprocess, sys
HERE = Path(__file__).resolve().parent; ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import flight

ap = argparse.ArgumentParser(); ap.add_argument('--binary', type=Path); args = ap.parse_args()
cases = json.loads((HERE / 'tracking-cases.jsonc').read_text())['cases']
binary = args.binary or ROOT / '.roc-font-tmp/tracking/query'
roc = os.environ.get('ROC', 'roc')
if not args.binary:
    binary.parent.mkdir(parents=True, exist_ok=True)
    with flight.flight(roc, work=binary.parent / 'flight') as dep:
        subprocess.run([roc, 'build', '--opt=speed', str(HERE / 'tracking-query.roc'),
                        f'--output={binary}', *dep], cwd=ROOT, check=True)
requests = []
for case in cases:
    assert hashlib.sha256((HERE / case['font']).read_bytes()).hexdigest() == case['sha256']
    requests.append('\t'.join([case['id'], str(HERE / case['font']), str(case['size']),
                               case['direction'], case['text']]))
request = '\n'.join(requests) + '\n'
answer = subprocess.run([str(binary.resolve())], input=request, text=True,
                        capture_output=True, check=True, timeout=120)
actual = {id: json.loads(row) for id, row in (line.split('\t', 1) for line in answer.stdout.splitlines())}
errors = [case for case in cases if actual.get(case['id']) != case['expected']]
for case in errors[:12]:
    print(case['id'], case['font'], case['size'], case['direction'], repr(case['text']),
          'expected', case['expected'], 'actual', actual.get(case['id']))
again = subprocess.run([str(binary.resolve())], input=request, text=True,
                       capture_output=True, check=True, timeout=120)
assert answer.stdout == again.stdout, 'tracking is not deterministic'
print(f'{len(cases) - len(errors)}/{len(cases)} tracking records agree; repeated output identical')
raise SystemExit(bool(errors))
