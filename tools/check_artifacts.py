"""Inspect generated API HTML and tar/zstd package assets without compiling code.

The Roc check runner owns compilation and step orchestration. This independent
artifact verifier uses Python's HTML/JSON, archive and SHA-256 facilities.
"""
from __future__ import annotations
import io, json, re, shutil, subprocess, sys, tarfile
from dataclasses import dataclass
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
PUBLIC_API = ROOT / "scripts/public_api.json"
FONT_SUFFIXES = (".ttf", ".otf", ".ttc", ".otc", ".woff", ".woff2", ".dfont", ".pfb")
FONT_MAGICS = (b"\x00\x01\x00\x00", b"OTTO", b"true", b"ttcf", b"wOFF", b"wOF2", b"typ1")
@dataclass
class Result:
    status: str
    detail: str = ""
    output: str = ""
DOC_ITEM_RE = re.compile(r'class="sidebar-(?:value|type|type-name)" href="#([A-Za-z0-9_.]+)"')
DOC_MODULE_RE = re.compile(r'data-module-name="([A-Za-z0-9_.]+)"')


def check_docs(out: Path) -> Result:
    output = ""
    pages = sorted(out.rglob("*.html"))
    html = "".join(page.read_text(encoding="utf-8", errors="replace") for page in pages)
    shown = set(DOC_ITEM_RE.findall(html)) | set(DOC_MODULE_RE.findall(html))
    if not shown:
        return Result("FAIL", "found no documented items; the docs HTML layout may have changed", output)
    api = json.loads(PUBLIC_API.read_text(encoding="utf-8"))
    public, known = set(api["public"]), set(api["known_internal"])
    unexpected = sorted(shown - public - known)
    missing = sorted(public - shown)
    stale = sorted(known - shown)
    leaking = sorted(shown & known)
    lines = [f"{len(shown)} items shown: {len(shown & public)} public, {len(leaking)} known internal leaks"]
    if unexpected:
        lines.append("not public and not listed as a known leak: " + ", ".join(unexpected))
    if missing:
        lines.append("public but not documented: " + ", ".join(missing))
    if stale:
        lines.append("listed as known leaks but no longer shown (remove from scripts/public_api.json): " + ", ".join(stale))
    if leaking:
        lines.append("known internal leaks: " + ", ".join(leaking))
    report = "\n".join(lines)
    if unexpected or missing or stale:
        return Result("FAIL", lines[0] + "; see output", report)
    if leaking:
        return Result("KNOWN", f"{len(leaking)} internal helpers appear as items of Font "
                      "(listed in scripts/public_api.json known_internal)", report)
    return Result("PASS", lines[0], report)


def decompress_zstd(path: Path) -> bytes | None:
    try:
        from compression import zstd  # type: ignore  # Python 3.14+
        return zstd.decompress(path.read_bytes())
    except ImportError:
        pass
    if shutil.which("zstd") is None:
        return None
    completed = subprocess.run(["zstd", "-dc", str(path)], capture_output=True, check=False)
    return completed.stdout if completed.returncode == 0 else None


PINS = ROOT / "tools" / "default-fonts" / "pins.json"
# `roc build` refuses a dependency larger than this, decompressed (its
# --max-package-mb default).
MAX_PACKAGE_BYTES = 10 * 1024 * 1024


def pinned_files() -> dict[str, str]:
    """The pinned default fonts and licences, by their path in the bundle
    (relative to package/), with their SHA-256."""
    pins = json.loads(PINS.read_text(encoding="utf-8"))
    out: dict[str, str] = {}
    for face in pins["faces"]:
        for entry in (face, face["licence"]):
            path = Path(entry["file"])
            out[str(path.relative_to("package"))] = entry["sha256"]
    return out


def check_bundle(out: Path) -> Result:
    import hashlib
    output = ""
    archives = sorted(out.glob("*.tar.zst"))
    if len(archives) != 1:
        return Result("FAIL", f"expected one .tar.zst, found {len(archives)}", output)
    data = decompress_zstd(archives[0])
    if data is None:
        return Result("FAIL", "cannot decompress zstd: needs Python 3.14 or the zstd command", output)
    pinned = pinned_files()
    problems: list[str] = []
    names: list[str] = []
    seen: set[str] = set()
    total = 0
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        for member in archive.getmembers():
            names.append(member.name)
            if not member.isfile():
                continue
            name = member.name.removeprefix("./")
            base = Path(name).name
            content = archive.extractfile(member).read()  # type: ignore[union-attr]
            total += len(content)
            if name in pinned:
                seen.add(name)
                if hashlib.sha256(content).hexdigest() != pinned[name]:
                    problems.append(f"{member.name} differs from its pin in tools/default-fonts/pins.json")
                continue
            if base.lower().endswith(FONT_SUFFIXES) or content[:4] in FONT_MAGICS:
                problems.append(f"{member.name} is a font that is not pinned")
            if base.endswith("Tests.roc") or base == "FontBuild.roc" or base.startswith("fuzz"):
                problems.append(f"{member.name} is a test module or fuzz target")
            if not base.endswith(".roc"):
                problems.append(f"{member.name} is neither a Roc module nor a pinned default font or licence")
    for name in sorted(set(pinned) - seen):
        problems.append(f"{name} is pinned but missing from the bundle (is it imported?)")
    if total > MAX_PACKAGE_BYTES:
        problems.append(f"the bundle holds {total} bytes, over roc's {MAX_PACKAGE_BYTES}-byte package limit")
    report = f"{archives[0].name}: {total} bytes decompressed, " + ", ".join(sorted(names))
    if problems:
        return Result("FAIL", "; ".join(problems), report)
    return Result("PASS", f"{len(names)} files, {total} bytes ({archives[0].stat().st_size} compressed), {len(seen)} pinned font and licence files", report)



if __name__ == "__main__":
    mode, directory = sys.argv[1:]
    result = {"docs": check_docs, "bundle": check_bundle}[mode](Path(directory))
    print(f"{result.status}: {result.detail}\n{result.output}")
    raise SystemExit(0 if result.status == "PASS" else 1)
