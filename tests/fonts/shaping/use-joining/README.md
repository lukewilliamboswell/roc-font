Five renamed OFL subsets exercise the actual USE/Arabic-joining interaction:
Noto Sans NKo, Noto Sans NKo Unjoined, Noto Sans Mongolian, Noto Sans Adlam
and ADLaM Display. Every original file is pinned to the Google Fonts commit
and SHA-256 in `pins.json`; full OFL notices are beside the subsets.
`prepare.py --check`, using pinned fontTools4.61.1, reproduces every byte.
All five subsets pass OTS9.3.0. No package module imports these fonts.

`cases.py --check` reproduces788 JSONC cases. Cached HarfBuzz14.6.0 records
include all glyph ids, original clusters, positions and unsafe flags. Cases
cover both horizontal directions and cluster levels, joining forms, marks,
CGJ/ZWNJ filtering, Mongolian variation selectors/MVS/NNBSP, user features
including a range, paragraph context and65/257-character runs. Native replay
uses the repository's common served-bundle driver; no oracle is needed.

NKo and Adlam each have two real families, including a deliberately unjoined
NKo design. Mongolian currently has one family: the pinned Google Fonts
catalogue has no Noto Serif Mongolian entry, and an independent second family
has not been established here. These are horizontal shaping tests; they do
not imply vertical-layout support. Other USE scripts require their own font
and oracle evidence before script-specific claims are made.
