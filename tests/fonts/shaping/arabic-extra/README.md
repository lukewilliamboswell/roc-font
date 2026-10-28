Unmodified OFL fonts from the pinned official Google Fonts repository:
`ddf386ba1b9fbc6b2c818f1ddcd9148f54ced94b`. `sources.json` records each direct
source URL, size and SHA256; each family has its own complete OFL text.

The Syriac families are Noto Sans Syriac3.000, Eastern3.001 and Western3.001.
Noto Nastaliq Urdu3.009 exercises connected Arabic forms and mark attachments.
Only Noto Sans Syriac has the real `stch` feature. All four files pass OTS9.3.0.

Run `python3 cases.py` to regenerate the case matrix and verify pinned hashes.
Cached HarfBuzz14.6.0 records include positions, clusters and unsafe-break flags,
both directions/cluster levels, variation locations and selected paragraph
ranges. Long marks intentionally expose attachment propagation bounds; they
are retained unchanged when they find an implementation difference.
