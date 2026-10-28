"""Original UPL legacy AAT programs, including signed/context/ligature units."""
import argparse
import io
import json
from pathlib import Path
import struct
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib.tables.DefaultTable import DefaultTable

HERE = Path(__file__).resolve().parent
u16 = lambda *values: struct.pack(">" + "H" * len(values), *(value & 65535 for value in values))
u32 = lambda *values: struct.pack(">" + "I" * len(values), *values)

def lookup(first, values):
    return u16(8, first, len(values), *values)

def state(kind, *, first=1, zero=False, multi_store=False):
    columns = 6
    classes = u16(first, 2) + bytes([4, 5])
    header = {"rearrange":8, "context":10, "insertion":10, "ligature":14}[kind]
    class_at = header
    state_at = class_at + len(classes)
    rows = [[0, 0, 0, 0, 1, 0]] * 2
    if kind != "insertion":
        rows += [[0, 0, 0, 0, 1, 2]]
    entry_at = state_at + len(rows) * columns
    if kind == "rearrange":
        entries = [(state_at, 0), (state_at + 2 * columns, 0x8000), (state_at, 0x2003)]
        extra = b""
        tail = b""
    elif kind == "context":
        tail_at = entry_at + 3 * 8
        # Word offsets are relative to the state header, and signed.
        # Only offset0 means no action;0xFFFF is the ordinary offset−1.
        mark_offset = tail_at // 2 - first
        current_offset = tail_at // 2 + 1 - (first + 1)
        entries = [(state_at, 0, 0, 0), (state_at + 2 * columns, 0x8000, 0, 0),
                   (state_at, 0, mark_offset, current_offset)]
        extra = u16(tail_at)
        tail = u16(0 if zero else 5, 0 if zero else 6)
    elif kind == "insertion":
        tail_at = entry_at + 2 * 8
        entries = [(state_at, 0, 65535, 65535), (state_at, 0x0820, 0, 65535)]
        extra = u16(tail_at)
        tail = u16(5)
    else:
        action_at = (entry_at + 3 * 4 + 3) & ~3
        component_at = action_at + 8
        glyph_at = component_at + 9 * 2
        entries = [(state_at, 0), (state_at + 2 * columns, 0x8000), (state_at, 0x8000 | action_at)]
        component_base = component_at // 2
        if multi_store:
            actions = u32(0x40000000 | component_base, 0x80000000 | (component_base + 2))
            components = u16(0, 0, glyph_at, glyph_at + 2, 0, 0, 0, 0, 0)
        else:
            actions = u32(component_base, 0x80000000 | component_base)
            components = u16(0, 0, glyph_at, 0, 0, 0, 0, 0, 0)
        extra = u16(action_at, component_at, glyph_at)
        tail = bytes(action_at - (entry_at + 3 * 4)) + actions + components + u16(5, 6)
    return u16(columns, class_at, state_at, entry_at) + extra + classes + bytes(value for row in rows for value in row) + u16(*(value for entry in entries for value in entry)) + tail

def mort(body, kind, coverage, features=False):
    feature_data = (u16(1, 2) + u32(1, 0xFFFFFFFF) + u16(1, 3) + u32(0, 0xFFFFFFFE) + u16(0, 1) + u32(0, 0)) if features else b""
    sub = u16(8 + len(body), coverage | kind) + u32(1) + body
    sub += bytes(-len(sub) % 4)
    sub = u16(len(sub)) + sub[2:]
    chain = u32(1, 12 + len(feature_data) + len(sub)) + u16(3 if features else 0, 1) + feature_data + sub
    return u32(0x00010000, 1) + chain

def make_font(label, data, *, first=1, glyph_count=9, morx=None, advance=None):
    names = [".notdef"] + [f"g{i}" for i in range(1, glyph_count)]
    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder(names)
    fb.setupCharacterMap({32:"g4",97:f"g{first}",98:f"g{first+1}",99:"g3",0x301:"g7",0x915:f"g{first}",0x916:f"g{first+1}"})
    glyphs = {}
    for name in names:
        pen = TTGlyphPen(None)
        if name != "g4":
            pen.moveTo((0,0)); pen.lineTo((50,0)); pen.lineTo((50,300)); pen.lineTo((0,300)); pen.closePath()
        glyphs[name] = pen.glyph()
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics({name:(100 + i * 10 if advance is None else advance,0) for i,name in enumerate(names)})
    fb.setupHorizontalHeader(ascent=800,descent=-200)
    fb.setupNameTable({"familyName":"Original Mort " + label,"styleName":"Regular","psName":"OriginalMort-" + label})
    fb.setupOS2(sTypoAscender=800,sTypoDescender=-200,usWinAscent=800,usWinDescent=200)
    fb.setupPost(); fb.setupMaxp()
    table = DefaultTable("mort"); table.data = data; fb.font["mort"] = table
    if morx is not None:
        table = DefaultTable("morx"); table.data = morx; fb.font["morx"] = table
    if label.endswith("features"):
        table = DefaultTable("feat")
        table.data = u32(0x10000) + u16(1,0) + u32(0) + u16(1,2) + u32(24) + u16(0,256) + u16(2,257,3,258)
        fb.font["feat"] = table
        for id,text in [(256,"Ligatures"),(257,"On"),(258,"Off")]:
            fb.font["name"].setName(text,id,3,1,0x409)
    fb.font["head"].created = fb.font["head"].modified = 3406620153
    fb.font.recalcTimestamp = False
    output = io.BytesIO(); fb.font.save(output,reorderTables=True)
    return output.getvalue()

def narrow(states):
    state_at = 16
    entry_at = state_at + states * 6
    pool_at = entry_at + (states + 1) * 8
    body = u16(6,10,state_at,entry_at,pool_at,1,2) + bytes([4,5])
    body += b"".join(bytes([0,0,0,0,i+1,0]) for i in range(states))
    body += u16(state_at,0,0,0)
    # Expose the highest reachable row immediately: HarfBuzz's bounded
    # sanitizer need not repeatedly rescan one newly discovered row at a time.
    next_state = lambda i: states-1 if i == 0 else (1 if i == states-1 else (0 if i == states-2 else i+1))
    value = lambda i: 2 if i == 0 else (3 if i == states-1 else 2+(i+1)%2)
    body += b"".join(u16(state_at + next_state(i)*6,0,0,pool_at//2-1+i) for i in range(states))
    body += u16(*(value(i) for i in range(states)))
    return mort(body,1,0x3000)

def generate():
    fonts = []
    for kind, code in [("direct",4),("rearrange",0),("context",1),("ligature",2),("insertion",5)]:
        body = lookup(1,[5,6,0]) if kind == "direct" else state(kind)
        for order, coverage in [("logical",0x3000),("visual",0x2000),("reverse",0x6000),("features",0x3000)]:
            label = kind + "-" + order
            emit(label + ".ttf", make_font(label,mort(body,code,coverage,order == "features")))
            fonts.append(label)
    for label, body, first, count, code in [
        ("context-zero",state("context",zero=True),1,9,1),
        ("context-negative",state("context",first=49),49,64,1),
        ("context-minus-one",state("context",first=30),30,40,1),
        ("ligature-multistore",state("ligature",multi_store=True),1,9,2),
    ]:
        emit(label + ".ttf",make_font(label,mort(body,code,0x3000),first=first,glyph_count=count))
        fonts.append(label)
    old = mort(lookup(1,[5,6,0]),4,0x3000)
    new_body = lookup(1,[6,5,0])
    new_sub = u32(12 + len(new_body),0x30000004,1) + new_body
    modern = u32(0x20000,1,1,16 + len(new_sub),0,1) + new_sub
    for label, legacy, extended in [
        ("priority-morx",old,modern),
        ("priority-empty-morx",old,u32(0x20000,0)),
        ("broken-mort-with-morx",b"\0",modern),
        ("broken-morx-with-mort",old,b"\0"),
    ]:
        emit(label + ".ttf",make_font(label,legacy,morx=extended))
        fonts.append(label)
    emit("bad-mort-and-morx.ttf",make_font("bad-mort-and-morx",b"\0",morx=b"\0"))
    emit("bad-chain.ttf",make_font("bad-chain",u32(0x10000,1,1,1000) + u16(0,1)))
    scaling = []
    for states in (16,64,192):
        name = f"scaling-{states}.ttf"
        emit(name,make_font(f"scaling-{states}",narrow(states),glyph_count=257,advance=600))
        for index,text in enumerate(["A"*states,"A"*(2*states),"B"+"A"*states+"C"]):
            # The original SFNT maps lowercase input to glyphs1..3.
            scaling.append({"id":f"mort-scaling-{states}-{index}","font":name,"text":text.lower(),
                "options":{"script":"Latn","direction":"ltr","hb_options":["--show-flags"]},"expected":"oracle"})
    emit("scaling-cases.jsonc",(json.dumps({"schema":1,"about":"Fixed257glyph bodies; only16/64/192legacy states and overlapping substitution offsets grow.","cases":scaling},indent=2)+"\n").encode())
    cases = []
    for font in fonts:
        for text in ["","a","b","ab","aab","aba","ba","abc","aa","a\u0301b","a b"]:
            for direction in ["ltr","rtl","ttb","btt"]:
                cases.append({"id":font + "-" + direction + "-" + text.encode().hex(),"font":font + ".ttf","text":text,
                    "options":{"script":"Latn","direction":direction,"hb_options":["--show-flags"]},"expected":"oracle"})
        for script,text in [("Arab","ab"),("Deva","कख")]:
            for direction in ["ltr","rtl"]:
                cases.append({"id":font + "-" + script + "-" + direction,"font":font + ".ttf","text":text,
                    "options":{"script":script,"direction":direction,"hb_options":["--show-flags"]},"expected":"oracle"})
    for font in fonts:
        if not font.endswith("features"):
            continue
        for text in ["ab","aab","aba","abc","a b"]:
            for index,features in enumerate([["liga=0"],["liga=1"],["liga=0","liga=1"],["liga=1","liga=0"],
                ["liga[1:2]=0"],["liga[0:1]=0"],["liga[0:4294967295]=0","liga[1:2]=1"],
                ["liga[1:2]=0","liga[0:3]=1"],["liga[0:4294967295]=0","liga[0:4294967295]=1"],
                ["liga[0:4294967295]=1","liga[0:4294967295]=0"]]):
                for direction in ["ltr","rtl","ttb","btt"]:
                    cases.append({"id":font + "-setting" + str(index) + "-" + direction + "-" + text.encode().hex(),
                        "font":font + ".ttf","text":text,"options":{"script":"Latn","direction":direction,
                        "features":features,"hb_options":["--show-flags"]},"expected":"oracle"})
    for font in ["context-negative","ligature-multistore","insertion-logical","rearrange-logical"]:
        for index,text in enumerate(["a"*257,"ab"*129,"a\u0301b"*65]):
            for direction in ["ltr","rtl"]:
                cases.append({"id":font + "-long" + str(index) + "-" + direction,"font":font + ".ttf","text":text,
                    "options":{"script":"Latn","direction":direction,"hb_options":["--show-flags"]},"expected":"oracle"})
    emit("mort-cases.jsonc",(json.dumps({"schema":1,"about":"Original UPL legacy mort programs: all five types, signed offsets, zero semantics, multistore byte/index units, directions, features, clusters and long inputs.","cases":cases},indent=2,ensure_ascii=False)+"\n").encode())

if __name__ == "__main__":
    parser = argparse.ArgumentParser(); parser.add_argument("--check",action="store_true"); args = parser.parse_args()
    def emit(name,data):
        path = HERE / name
        if args.check:
            assert path.read_bytes() == data, path
        else:
            path.write_bytes(data)
    generate()
