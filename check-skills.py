"""Kontrola skill wrapperů v skills/*/SKILL.md.

- `description` ve frontmatteru <= 1024 znaků (limit Agent Skills spec, jinak se skill
  nemusí načíst) — vypíše délku každého skillu;
- notes soubor, na který skill odkazuje absolutní cestou C:\\WorkTasks\\BCALInsights\\<x>.md,
  existuje v kořeni repa;
- každý notes soubor v kořeni (bc-al-*.md, ew-mobile-ui-notes.md, kromě archivu) je zmíněn
  v Routeru skills/bc-al/SKILL.md.

Spuštění: `python check-skills.py` v kořeni repa (exit 1 při chybě).
"""
import glob
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
LIMIT = 1024
errors = []
try:
    sys.stdout.reconfigure(encoding='utf-8')  # Git Bash / cp1250 konzole
except AttributeError:
    pass

router = io.open(os.path.join(ROOT, 'skills', 'bc-al', 'SKILL.md'), encoding='utf-8').read()

for path in sorted(glob.glob(os.path.join(ROOT, 'skills', '*', 'SKILL.md'))):
    name = os.path.basename(os.path.dirname(path))
    text = io.open(path, encoding='utf-8').read()
    m = re.search(r'^description: >-\n((?:[ \t]+.*\n)+)', text, re.M)
    if not m:
        errors.append(f'{name}: chybí `description: >-` blok ve frontmatteru')
        continue
    desc = ' '.join(m.group(1).split())
    status = 'OK ' if len(desc) <= LIMIT else 'OVER'
    print(f'{status} {len(desc):5d}/{LIMIT}  {name}')
    if len(desc) > LIMIT:
        errors.append(f'{name}: description má {len(desc)} znaků (limit {LIMIT})')
    for ref in set(re.findall(r'C:\\WorkTasks\\BCALInsights\\([\w.\-]+\.md)', text)):
        if not os.path.exists(os.path.join(ROOT, ref)):
            errors.append(f'{name}: odkazuje na neexistující notes soubor {ref}')

notes = [f for f in os.listdir(ROOT)
         if (f.startswith('bc-al-') or f == 'ew-mobile-ui-notes.md')
         and f.endswith('.md') and 'archived' not in f]
for f in sorted(notes):
    if f not in router:
        errors.append(f'{f} není zmíněn v Routeru skills/bc-al/SKILL.md')

if errors:
    print('\nCHYBY:')
    for e in errors:
        print(' -', e)
    sys.exit(1)
print('\nvšechno OK')
