#!/usr/bin/env python3
"""Check the default fonts in package/fonts/ against tools/default-fonts/pins.json.

    python3 tools/default-fonts/verify.py           check committed files (offline)
    python3 tools/default-fonts/verify.py --fetch   also download every upstream
                                                    archive and file and prove the
                                                    committed bytes came from it

Standard library only. Offline mode checks each font and licence file's size
and SHA-256 and that package/fonts/ holds nothing unpinned. --fetch streams
each distinct pinned release archive into temporary storage, checks its size and
SHA-256, reads the pinned member (after checking its declared size, so a
hostile archive cannot make us inflate more than the pin allows) and compares
it with the committed file. Licence URLs are checked separately. Nothing
from a download is executed. Temporary downloads are removed. --install
reproduces the pinned font and licence files after verifying their hashes.

Exit status 0 when everything matches, 1 otherwise. Every mismatch is
reported, not only the first.
"""

import argparse
import hashlib
import json
import os
import sys
import tempfile
import urllib.request
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
PINS = os.path.join(HERE, "pins.json")
FONT_DIR = os.path.join(ROOT, "package", "fonts")
# Files in package/fonts/ that are not fonts or licences.
ALLOWED_EXTRA = {".gitattributes"}
# Downloads larger than this are refused before they are read in full.
MAX_DOWNLOAD = 64 * 1024 * 1024


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def read(path):
    with open(path, "rb") as f:
        return f.read()


def fetch(url, expected_size=None):
    request = urllib.request.Request(url, headers={"User-Agent": "roc-font-default-fonts-verify"})
    limit = MAX_DOWNLOAD if expected_size is None else min(MAX_DOWNLOAD, expected_size + 1)
    with urllib.request.urlopen(request, timeout=120) as response:
        data = response.read(limit + 1)
    if len(data) > limit:
        raise ValueError(f"download exceeds {limit} bytes")
    return data


def check_bytes(problems, what, data, sha, size):
    if len(data) != size:
        problems.append(f"{what}: size {len(data)}, pinned {size}")
    if sha256(data) != sha:
        problems.append(f"{what}: sha256 {sha256(data)}, pinned {sha}")


def check_offline(pins, problems):
    pinned = set()
    for face in pins["faces"]:
        for entry, label in ((face, face["family"]), (face["licence"], f"{face['family']} licence")):
            rel = entry["file"]
            pinned.add(os.path.basename(rel))
            path = os.path.join(ROOT, rel)
            if not os.path.isfile(path):
                problems.append(f"{label}: {rel} is missing")
                continue
            check_bytes(problems, f"{label} ({rel})", read(path), entry["sha256"], entry["size"])
    if os.path.isdir(FONT_DIR):
        for name in sorted(os.listdir(FONT_DIR)):
            if name not in pinned and name not in ALLOWED_EXTRA:
                problems.append(f"package/fonts/{name} is not pinned in tools/default-fonts/pins.json")


def check_upstream(pins, problems, install=False):
    # Stream each archive once to temporary storage, checking its complete digest
    # before trusting members. The large upstream serif archive is not held in RAM.
    with tempfile.TemporaryDirectory() as directory:
        archives = {}
        for face in pins["faces"]:
            up = face["upstream"]
            archive = up["archive"]
            url = archive["url"]
            if url not in archives:
                path = os.path.join(directory, str(len(archives)))
                try:
                    digest = hashlib.sha256()
                    count = 0
                    with urllib.request.urlopen(url, timeout=120) as response, open(path, "wb") as output:
                        while True:
                            chunk = response.read(1024 * 1024)
                            if not chunk:
                                break
                            count += len(chunk)
                            if count > archive["size"]:
                                raise ValueError("archive exceeds pinned size")
                            digest.update(chunk)
                            output.write(chunk)
                    if count != archive["size"] or digest.hexdigest() != archive["sha256"]:
                        raise ValueError("archive does not match its size and SHA-256")
                    archives[url] = path
                except Exception as error:
                    problems.append(f"{url}: {error}")
                    archives[url] = None
            path = archives[url]
            if path is None:
                continue
            try:
                with zipfile.ZipFile(path) as z:
                    info = z.getinfo(archive["member"])
                    if info.file_size != face["size"]:
                        raise ValueError("member differs from pinned size")
                    data = z.read(info)
                    if sha256(data) != face["sha256"]:
                        raise ValueError("member differs from pinned digest")
                    target = os.path.join(ROOT, face["file"])
                    if install:
                        with open(target, "wb") as output:
                            output.write(data)
                    elif data != read(target):
                        raise ValueError("member differs from committed font")
            except Exception as error:
                problems.append(f"{face['id']}: {error}")
        licences = {f["licence"]["file"]: f["licence"] for f in pins["faces"]}
        for lic in licences.values():
            try:
                data = fetch(lic["url"], lic["size"])
                if len(data) != lic["size"] or sha256(data) != lic["sha256"]:
                    raise ValueError("licence differs from pin")
                target = os.path.join(ROOT, lic["file"])
                if install:
                    with open(target, "wb") as output:
                        output.write(data)
                elif data != read(target):
                    raise ValueError("licence differs from upstream")
            except Exception as error:
                problems.append(f"{lic['file']}: {error}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--fetch", action="store_true", help="also download every upstream and compare")
    parser.add_argument("--install", action="store_true", help="acquire exact pinned fonts and licences from upstream")
    args = parser.parse_args()
    with open(PINS, encoding="utf-8") as f:
        pins = json.load(f)
    problems = []
    if args.install:
        check_upstream(pins, problems, install=True)
    check_offline(pins, problems)
    if args.fetch and not args.install:
        if not problems:
            check_upstream(pins, problems)
        else:
            problems.append("skipped --fetch: committed files do not match their pins")
    entries = {e["file"]: e for f in pins["faces"] for e in (f, f["licence"])}
    total = sum(e["size"] for e in entries.values())
    for problem in problems:
        print(f"MISMATCH {problem}")
    if problems:
        return 1
    print(f"ok: {len(pins['faces'])} default fonts match their pins ({total} bytes with licences)"
          + ("; upstream provenance confirmed" if args.fetch else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
