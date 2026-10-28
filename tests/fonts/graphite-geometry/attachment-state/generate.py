"""Original insertion-boundary and inherited-collision controls, UPL."""
import argparse
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import generate as geometry
import collision_generate as collision


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    cases = []
    def save(key, data, rtl, **extra):
        path = HERE / (key + '.ttf')
        if args.check:
            assert path.read_bytes() == data, path
        else:
            path.write_bytes(data)
        cases.append({'id': key, 'font': 'attachment-state/' + path.name, 'text': extra.pop('text', 'ab'), 'direction': 'rtl' if rtl else 'ltr', 'script': 'Arab' if rtl else 'Latn', **extra})
    for rtl in (False, True):
        suffix = '-rtl' if rtl else '-ltr'
        for value in (0, 1):
            key = f'attachment-state-insert{value}' + suffix
            action = geometry.set_attr(17, value) + geometry.attach()
            save(key, geometry.font(key, action, True, False, 2, rtl), rtl, action=list(action), authored_insert_before=bool(value))
        for second in ('none', 'position', 'metric-advance', 'metric-left', 'metric-right'):
            key = 'collision-attachment-state-parent-' + second + suffix
            params = {'attachment': 'forward', 'flags_a': 0, 'flags_b': 1}
            if second != 'none':
                params['second'] = second
            data, action = collision.make(key, params, rtl)
            save(key, data, rtl, action=list(action), collision=params)
        for label, params, text in [
            ('ignored-root', {'attachment': 'forward', 'group_flags': [0, 1, 2]}, 'abc'),
            ('own-child', {'attachment': 'forward', 'flags_a': 1, 'flags_b': 0}, 'ab'),
        ]:
            key = 'collision-attachment-state-' + label + suffix
            data, action = collision.make(key, params, rtl)
            save(key, data, rtl, text=text, action=list(action), collision=params)
    text = json.dumps({'schema': 1, 'cases': cases}, ensure_ascii=False, indent=2) + '\n'
    path = HERE / 'cases.jsonc'
    if args.check:
        assert path.read_text() == text
    else:
        path.write_text(text)
    print(f'{len(cases)} insertion/inherited-state cases reproduce')


if __name__ == '__main__':
    main()
