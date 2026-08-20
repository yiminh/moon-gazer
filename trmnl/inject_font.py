#!/usr/bin/env python3
"""Embed a mono webfont into a TRMNL liquid as base64 @font-face.

TRMNL's cloud renderer bundles no monospace font, so a bare `font-family: mono`
falls back to whatever the renderer has (DejaVu Sans Mono). To pin an exact face
across the cloud preview and the device, embed the woff2 bytes directly.

Usage:
  inject_font.py <liquid> <family> <woff2-400> <woff2-700> [<woff2-500>]

- strips any existing @font-face blocks (safe to re-run)
- writes fresh 400 / 700 (and optional 500) @font-face at the `/* @@FONTFACE@@ */`
  anchor inside the <style> block
- points the first `font-family:` token at <family>

Fetch open woff2 files from e.g. fontsource:
  https://cdn.jsdelivr.net/npm/@fontsource/jetbrains-mono@5/files/jetbrains-mono-latin-400-normal.woff2
  https://cdn.jsdelivr.net/npm/@fontsource/jetbrains-mono@5/files/jetbrains-mono-latin-700-normal.woff2
(JetBrains Mono and IBM Plex Mono are both OFL-licensed.)
"""
import base64
import pathlib
import re
import sys

if len(sys.argv) < 5:
    sys.exit(__doc__)

liquid, family, w400, w700 = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
w500 = sys.argv[5] if len(sys.argv) > 5 else None  # optional Medium weight


def face(path, weight):
    b = base64.b64encode(pathlib.Path(path).read_bytes()).decode()
    return (f'  @font-face {{\n'
            f'    font-family: "{family}"; font-style: normal; font-weight: {weight}; font-display: block;\n'
            f'    src: url(data:font/woff2;base64,{b}) format("woff2");\n  }}')


blocks = [face(w400, 400)]
if w500:
    blocks.append(face(w500, 500))
blocks.append(face(w700, 700))
faces = "/* @@FONTFACE@@ */\n" + "\n".join(blocks)

p = pathlib.Path(liquid)
s = p.read_text()

# drop any previous @font-face blocks (base64 has no braces, so [^}]* is safe)
s = re.sub(r'@font-face\s*\{[^}]*\}\s*', '', s)
if '/* @@FONTFACE@@ */' in s:
    s = s.replace('/* @@FONTFACE@@ */', faces, 1)
else:
    s = s.replace('<style>\n', '<style>\n  ' + faces + '\n', 1)
s = re.sub(r'font-family:\s*"[^"]*"\s*,\s*ui-monospace',
           f'font-family: "{family}", ui-monospace', s, count=1)

p.write_text(s)
print(f'{p.name}: family="{family}"  @font-face={s.count("@font-face")}  KB={round(len(s)/1024,1)}')
