"""Original UPL origin-crossing controls and a licensed Scheherazade case."""
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
        for prefix in (0,10,26,27,28,604):
            if rtl:
                action = geometry.attach() + geometry.set_attr(3,30) + geometry.set_attr(8,0) + geometry.set_attr(0,0)
                action += geometry.NEXT + geometry.attach() + geometry.set_attr(3,-27) + geometry.set_attr(8,0) + geometry.set_attr(0,0)
                action += geometry.NEXT + geometry.NEXT + geometry.set_attr(0,prefix)
            else:
                action = geometry.set_attr(0,prefix) + geometry.NEXT
                action += geometry.attach() + geometry.set_attr(3,30) + geometry.set_attr(8,0) + geometry.set_attr(0,0)
                action += geometry.NEXT + geometry.attach() + geometry.set_attr(3,-27) + geometry.set_attr(8,0) + geometry.set_attr(0,0)
            key = f'segment-origin-prefix-{prefix}-' + ('rtl' if rtl else 'ltr')
            path = HERE / (key + '.ttf')
            data = geometry.font(key,action,True,False,4,rtl)
            if args.check:
                assert path.read_bytes() == data,path
            else:
                path.write_bytes(data)
            cases.append({'id':key,'font':'segment-origin/'+path.name,'text':'abcd','direction':'rtl'if rtl else'ltr','script':'Arab'if rtl else'Latn','action':list(action),'prefix_advance':prefix})
    for rtl in (False, True):
        for advance in (-1, 0, 1, 601):
            child = geometry.attach() + geometry.set_attr(3,-601) + geometry.set_attr(8,0) + geometry.set_attr(0,advance)
            action = child + geometry.NEXT + geometry.NEXT + geometry.set_attr(0,602) if rtl else geometry.set_attr(0,602) + geometry.NEXT + child
            key = f'segment-origin-positive-child-{advance}-' + ('rtl' if rtl else 'ltr')
            path = HERE / (key + '.ttf')
            data = geometry.font(key,action,True,False,3,rtl)
            if args.check:
                assert path.read_bytes() == data,path
            else:
                path.write_bytes(data)
            cases.append({'id':key,'font':'segment-origin/'+path.name,'text':'abc','direction':'rtl'if rtl else'ltr','script':'Arab'if rtl else'Latn','action':list(action),'prefix_advance':602,'child_advance':advance})
    cases.append({'id':'segment-origin-real-scheherazade','font':'../graphite/Scheherazadegr.ttf','text':'اللَّه','direction':'rtl','script':'Arab'})
    text = json.dumps({'schema':1,'cases':cases},ensure_ascii=False,indent=2)+'\n'
    path = HERE/'cases.jsonc'
    if args.check:
        assert path.read_text() == text
    else:
        path.write_text(text)
    print(f'{len(cases)} segment-origin cases reproduce')


if __name__ == '__main__':
    main()
