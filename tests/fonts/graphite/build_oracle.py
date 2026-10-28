"""Build the separate MIT HarfBuzz14.6 adapter with installed Graphite2.
This tool produces an oracle library, never code linked into the Roc package.
"""
from pathlib import Path
import argparse,subprocess
p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--output',type=Path,default=Path('/private/tmp/libroc-font-hb14-graphite.dylib'));p.add_argument('--graphite-prefix',type=Path,default=Path('/opt/homebrew'));args=p.parse_args()
version=(args.source/'src/hb-version.h').read_text();assert '#define HB_VERSION_STRING "14.6.0"' in version
subprocess.run(['clang++','-O2','-std=c++17','-fPIC','-dynamiclib','-DHAVE_GRAPHITE2','-I'+str(args.graphite_prefix/'include'),str(args.source/'src/harfbuzz.cc'),'-L'+str(args.graphite_prefix/'lib'),'-lgraphite2','-o',str(args.output)],check=True)
print(args.output)
