"""Build the explicitly non-default HB14.6 Graphite2 reference variant.

Only an MIT HarfBuzz adapter factory argument changes. Graphite2 remains an
unchanged externally linked library; its implementation is not read or ported.
The upstream preloadAll6 reference remains the default compatibility oracle.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--compiler', default='clang++')
    parser.add_argument('--include', type=Path, default=Path('/opt/homebrew/include'))
    parser.add_argument('--library-directory', type=Path, default=Path('/opt/homebrew/lib'))
    args = parser.parse_args()
    pin = json.loads((HERE / 'face0-configuration.json').read_text())
    relative = Path('src/hb-graphite2.cc')
    original = (args.source / relative).read_bytes()
    assert sha(original) == pin['original_file_sha256'], 'requires the pinned unmodified HB14.6 adapter'
    assert not args.work.exists(), 'choose a fresh reference work directory'
    shutil.copytree(args.source, args.work)
    old, new = pin['replacement']['from'].encode(), pin['replacement']['to'].encode()
    assert original.count(old) == 1
    patched = original.replace(old, new)
    assert sha(patched) == pin['patched_file_sha256']
    (args.work / relative).write_bytes(patched)
    command = [args.compiler, '-O2', '-std=c++17', '-fPIC', '-dynamiclib' if sys.platform == 'darwin' else '-shared', '-DHAVE_GRAPHITE2', '-I' + str(args.include), 'src/harfbuzz.cc', '-L' + str(args.library_directory), '-lgraphite2', '-o', str(args.output.resolve())]
    subprocess.run(command, cwd=args.work, check=True)
    print(json.dumps({'configuration': pin['name'], 'patched_file_sha256': sha(patched), 'library_sha256': sha(args.output.read_bytes()), 'command': command}, indent=2))


if __name__ == '__main__':
    main()
