# Positioning fixtures

Original, deterministic TrueType fonts for positioning lookup families.
Run `generate.py` with the pinned oracle Python (fontTools 4.61.1).
Every font includes contours and complete ordinary metadata so an invalid
container cannot mask a positioning failure. Cases include both horizontal
directions, attachments through ligature components, stacked marks, cursive
chains, contextual calls and variable anchors.

The fixtures and generator are under the repository's Universal Permissive
License 1.0, copied here as `LICENSE`. No third-party font data is included.
