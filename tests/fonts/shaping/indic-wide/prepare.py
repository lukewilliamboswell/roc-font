#!/usr/bin/env python3
"""Rebuild renamed static Indic subsets using pinned fontTools 4.61.1.
Original source downloads stay outside the checkout. Every source, licence
and generated subset is pinned; --check reproduces without modifying files.
"""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import urllib.request
import fontTools
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--update', action='store_true')
    args = parser.parse_args()
    assert fontTools.version == '4.61.1', fontTools.version
    pins = json.loads((HERE/'pins.json').read_text())
    cache = Path(os.environ.get('ROC_FONT_INDIC_WIDE_SOURCES', '/private/tmp/roc-font-indic-wide-sources'))
    cache.mkdir(parents=True, exist_ok=True)
    for family in pins['families']:
        for source in family['sources']:
            path = cache/source['file']
            if not path.exists():
                path.write_bytes(urllib.request.urlopen(source['url']).read())
            raw = path.read_bytes()
            assert len(raw) == source['size'] and hashlib.sha256(raw).hexdigest() == source['sha256'], path
        source = family['sources'][0]
        f = TTFont(cache/source['file'], recalcTimestamp=False)
        axes = {a.axisTag: (400 if a.axisTag == 'wght' else 100 if a.axisTag == 'wdth' else a.defaultValue) for a in f['fvar'].axes} if 'fvar' in f else {}
        if axes:
            f = instantiateVariableFont(f, axes, inplace=True)
        options = subset.Options()
        options.layout_features = ['*']
        options.name_IDs = ['*']
        options.name_legacy = True
        options.name_languages = ['*']
        options.recalc_timestamp = False
        sub = subset.Subsetter(options=options)
        block = family['block']
        sub.populate(unicodes=list(range(block, block+128))+list(range(0x20, 0x7F))+list(range(0x1CD0, 0x1D00))+[0xA0, 0x034F, 0x200C, 0x200D, 0x25CC])
        sub.subset(f)
        label = 'Wide'+family['script']+family['style']
        for name in f['name'].names:
            if name.nameID in (1, 2, 3, 4, 6, 16, 17, 25):
                value = 'Regular' if name.nameID in (2, 17) else label+'-Regular' if name.nameID in (3, 4, 6, 25) else label
                name.string = value.encode(name.getEncoding())
        f.recalcTimestamp = False
        f['head'].created = f['head'].modified = 0x7C25B080
        target = label+'.ttf'
        output = io.BytesIO()
        f.save(output)
        data = output.getvalue()
        result = {'file': target, 'sha256': hashlib.sha256(data).hexdigest(), 'size': len(data), 'source_axes': axes,
                  'ot_scripts': [r.ScriptTag for r in f['GSUB'].table.ScriptList.ScriptRecord] if 'GSUB' in f else []}
        if args.update:
            family['subset'] = result
        else:
            assert family['subset'] == result, target+' changed'
        if args.check:
            assert (HERE/target).read_bytes() == data, target+' does not reproduce'
        else:
            (HERE/target).write_bytes(data)
        assert (HERE/(label+'-OFL.txt')).read_bytes() == (cache/family['sources'][1]['file']).read_bytes()
        print(target, len(data), result['ot_scripts'], flush=True)
    if args.update:
        (HERE/'pins.json').write_text(json.dumps(pins, indent=2)+'\n')


if __name__ == '__main__':
    main()
