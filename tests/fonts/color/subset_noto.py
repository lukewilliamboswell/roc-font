"""Create the test-only emoji subset with pinned fontTools4.61.1.

Usage: python subset_noto.py PATH_TO_ORIGINAL_Noto-COLRv1.ttf
The original is official Noto Emoji v2.051 at commit
f3ae03f5e9b3b8516fa151f7168159ca1a3e7515; its unmodified SHA256 is checked.
"""
from pathlib import Path
import hashlib,sys
from fontTools import subset
from fontTools.ttLib import TTFont

source=Path(sys.argv[1])
assert hashlib.sha256(source.read_bytes()).hexdigest()=='0ae57fe58645638523ba35f388d93739d292539a9acb84df5700c81b1e1a28d2'
font=TTFont(source,recalcTimestamp=False)
options=subset.Options()
options.layout_features=['*']
options.name_IDs=['*']
options.name_legacy=True
options.name_languages=['*']
options.notdef_glyph=True
options.notdef_outline=True
options.recalc_timestamp=False
sub=subset.Subsetter(options=options)
sub.populate(text='😀👩\u200d💻❤️')
sub.subset(font)
# OFL allows modification; retain its full notices and distinguish the
# derivative's naming from the original's product name.
font['name'].setName('Roc Noto Emoji Test Subset',1,3,1,0x409)
font['name'].setName('Roc Noto Emoji Test Subset',4,3,1,0x409)
font['name'].setName('RocNotoEmojiTestSubset',6,3,1,0x409)
font.save(Path(__file__).resolve().parent/'noto-emoji-subset.ttf',reorderTables=True)
