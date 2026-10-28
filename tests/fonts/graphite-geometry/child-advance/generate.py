"""Original positive/zero/negative child-advance witnesses, UPL."""
import argparse
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import generate as geometry


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    cases = []
    for rtl in (False, True):
        for position in (-1000, 1000):
            for advance in (-601, -1, 0, 1, 601):
                key = f'child-advance-x{position}-a{advance}-' + ('rtl' if rtl else 'ltr')
                action = geometry.attach() + geometry.set_attr(3, position) + geometry.set_attr(8, 0) + geometry.set_attr(0, advance)
                data = geometry.font(key, action, True, False, 2, rtl)
                path = HERE / (key + '.ttf')
                if args.check:
                    assert path.read_bytes() == data, path
                else:
                    path.write_bytes(data)
                cases.append({'id': key, 'font': 'child-advance/' + path.name, 'text': 'ab', 'direction': 'rtl' if rtl else 'ltr', 'script': 'Arab' if rtl else 'Latn', 'action': list(action), 'child_advance': advance, 'attachment_x': position})
    cases.append({'id': 'child-advance-real-charis-acute', 'font': '../graphite/Charis5_eursub.ttf', 'text': 'a\u0301', 'direction': 'ltr', 'script': 'Latn'})
    text = json.dumps({'schema': 1, 'cases': cases}, ensure_ascii=False, indent=2) + '\n'
    path = HERE / 'cases.jsonc'
    if args.check:
        assert path.read_text() == text
    else:
        path.write_text(text)
    print(f'{len(cases)} child-advance cases reproduce')


if __name__ == '__main__':
    main()
