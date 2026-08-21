#!/usr/bin/env bash
# Dead-UI scan — fails the build on buttons with no handler, TODO markers
# or placeholder copy in production code.
set -euo pipefail
cd "$(dirname "$0")/../frontend/src"
python3 - <<'PY'
import re, pathlib, sys
dead=[]
for p in pathlib.Path('pages').glob('*.jsx'):
    s=p.read_text()
    for m in re.finditer(r'<button\b((?:[^>]|\n)*?)>((?:(?!</button>).)*)</button>', s, re.S):
        attrs=m.group(1)
        if 'onClick' not in attrs and 'type="submit"' not in attrs and 'disabled' not in attrs:
            label=re.sub(r'\s+',' ',m.group(2)).strip()[:40]
            if label and not label.startswith('{'):
                dead.append(f"{p.name}: {label}")
bad=[]
for p in list(pathlib.Path('.').rglob('*.jsx'))+list(pathlib.Path('.').rglob('*.js')):
    t=p.read_text()
    for kw in ['TODO','FIXME','coming soon','lorem ipsum']:
        if kw.lower() in t.lower(): bad.append(f"{p}: {kw}")
print(f"dead buttons: {len(dead)}")
for d in dead: print("  -",d)
print(f"placeholder markers: {len(bad)}")
for b in bad: print("  -",b)
sys.exit(1 if (dead or bad) else 0)
PY
