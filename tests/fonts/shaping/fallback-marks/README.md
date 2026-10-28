Original UPL-licensed no-layout font, derived from the adjacent original
Windows-heuristic-negative fixture. Regenerate after `arabic-fallback` using
`generate.py`. OTS9.3.0 accepts it. The232 pinned HarfBuzz14.6.0 cases isolate
Hebrew, Arabic and Syriac fallback placement, including stacking, both
requested directions and cluster levels. The helper must interpret the
modified combining-class aliases used by normalization, rather than their
original canonical numbers. Arabic damma/kasra and Hebrew hiriq/rafe expose
the distinction in public positions without requiring a complex real font.
