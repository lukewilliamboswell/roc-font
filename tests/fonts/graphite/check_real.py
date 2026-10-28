"""Verify unmodified licensed oracle inputs; optionally verify pinned archive."""
from pathlib import Path
import argparse,hashlib,json,tarfile
HERE=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--archive',type=Path);args=p.parse_args()
pin=json.loads((HERE/'real-fonts.json').read_text())
def sha(data):return hashlib.sha256(data).hexdigest()
archive=None
if args.archive:
 assert sha(args.archive.read_bytes())==pin['archive_sha256']
 archive=tarfile.open(args.archive)
for item in pin['fonts']:
 data=(HERE/item['file']).read_bytes();assert sha(data)==item['sha256'],item['file']
 assert (HERE/(item['file']+'.LICENSE.txt')).stat().st_size>1000
 if archive:assert archive.extractfile(item['source']).read()==data,item['file']
print(f"{len(pin['fonts'])} unmodified licensed Graphite inputs verified")
