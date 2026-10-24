#!/usr/bin/env python3
"""Check the default fonts in package/fonts/ against tools/default-fonts/pins.json.

    python3 tools/default-fonts/verify.py           check committed files (offline)
    python3 tools/default-fonts/verify.py --fetch   also download every upstream
                                                    archive and file and prove the
                                                    committed bytes came from it

Standard library only. Offline mode checks each font and licence file's size
and SHA-256 and that package/fonts/ holds nothing unpinned. --fetch downloads
each pinned release archive into memory, checks the archive's size and
SHA-256, reads the pinned member (after checking its declared size, so a
hostile archive cannot make us inflate more than the pin allows) and compares
it with the committed file; it does the same for licence URLs, archive
licence members and direct file URLs. Downloads are only hashed and read as
zip data; nothing from them is executed or written to disk.

Exit status 0 when everything matches, 1 otherwise. Every mismatch is
reported, not only the first.
"""

import argparse
import hashlib
import io
import json
import os
import sys
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


def zip_member(archive, member, size):
    with zipfile.ZipFile(io.BytesIO(archive)) as z:
        info = z.getinfo(member)
        if info.file_size != size:
            raise ValueError(f"member {member} declares {info.file_size} bytes, pinned {size}")
        return z.read(member)


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


def check_upstream(pins, problems):
    for face in pins["faces"]:
        family = face["family"]
        up = face["upstream"]
        lic = face["licence"]
        committed = read(os.path.join(ROOT, face["file"]))
        committed_licence = read(os.path.join(ROOT, lic["file"]))
        archive = up.get("archive")
        if archive:
            print(f"fetching {archive['url']}", file=sys.stderr)
            try:
                data = fetch(archive["url"], archive["size"])
                check_bytes(problems, f"{family} archive", data, archive["sha256"], archive["size"])
                member = zip_member(data, archive["member"], face["size"])
                if member != committed:
                    problems.append(f"{family}: archive member {archive['member']} differs from {face['file']}")
                if lic.get("archive_member"):
                    text = zip_member(data, lic["archive_member"], lic["size"])
                    if text != committed_licence:
                        problems.append(f"{family}: archive member {lic['archive_member']} differs from {lic['file']}")
            except Exception as error:  # report and continue with the next check
                problems.append(f"{family} archive: {error}")
        url = up.get("file_url")
        if url:
            print(f"fetching {url}", file=sys.stderr)
            try:
                if fetch(url, face["size"]) != committed:
                    problems.append(f"{family}: {url} differs from {face['file']}")
            except Exception as error:
                problems.append(f"{family} file_url: {error}")
        print(f"fetching {lic['url']}", file=sys.stderr)
        try:
            if fetch(lic["url"], lic["size"]) != committed_licence:
                problems.append(f"{family}: {lic['url']} differs from {lic['file']}")
        except Exception as error:
            problems.append(f"{family} licence url: {error}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--fetch", action="store_true", help="also download every upstream and compare")
    args = parser.parse_args()
    with open(PINS, encoding="utf-8") as f:
        pins = json.load(f)
    problems = []
    check_offline(pins, problems)
    if args.fetch and not problems:
        check_upstream(pins, problems)
    elif args.fetch:
        problems.append("skipped --fetch: committed files do not match their pins")
    total = sum(face["size"] + face["licence"]["size"] for face in pins["faces"])
    for problem in problems:
        print(f"MISMATCH {problem}")
    if problems:
        return 1
    print(f"ok: {len(pins['faces'])} default fonts match their pins ({total} bytes with licences)"
          + ("; upstream provenance confirmed" if args.fetch else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
