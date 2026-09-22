#!/usr/bin/env bash
# Прибор объёма и формы корпуса. НЕ гейт: код выхода всегда 0, вердикт — у check-06.
# Символы, не байты: кириллица в UTF-8 вдвое тяжелее, и `wc -c` дал бы вдвое больше.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
case "${1:-}" in
  --form)
    python3 - <<'PY'
import glob
rows = []
for f in sorted(glob.glob('.claude/rules/*.md')):
    rows += [l.rstrip('\n') for l in open(f, encoding='utf-8') if ' · ' in l]
nored = [l for l in rows if 'red:' not in l]
odd = [l for l in rows if l.count('`') % 2]
def field(l, i):
    parts = l.split(' · ')
    return parts[i].strip() if len(parts) > i else ''
empty = [l for l in rows if field(l, 2) in ('—', '')]
noimp = [l for l in rows if field(l, 1) in ('—', '')]
nosign = [l for l in rows if l.rstrip().endswith('red: —')]
held = sum(1 for f in glob.glob('.claude/rules/*.md')
           for l in open(f, encoding='utf-8') if 'держится' in l)
def debts(line):
    w = line.split()
    return [w[i + 1] for i, t in enumerate(w) if t == 'ЗАВЕСТИ' and i + 1 < len(w)]
todo = {d for f in glob.glob('.claude/rules/*.md')
        for l in open(f, encoding='utf-8') for d in debts(l)}
print('строк-норм: %d' % len(rows))
print('без поля red: %d (обязан быть 0)' % len(nored))
print('с нечётным backtick: %d (обязан быть 0)' % len(odd))
print('с пустым держателем: %d (обязан быть 0)' % len(empty))
print('с пустым императивом: %d (обязан быть 0)' % len(noimp))
print('с пустым признаком red: %d (обязан быть 0)' % len(nosign))
print('ЗАВЕСТИ, различных: %d' % len(todo))
print('слово «держится»: %d (обязан быть 0)' % held)
PY
    ;;
  '')
    python3 - <<'PY'
import glob, os
rows = [(len(open(f, encoding='utf-8').read()), os.path.basename(f))
        for f in sorted(glob.glob('.claude/rules/*.md'))]
for n, b in sorted(rows, reverse=True):
    print('%8d  %s' % (n, b))
t = sum(n for n, _ in rows)
print('%8d  ИТОГО, потолок 200000, запас %d' % (t, 200000 - t))
PY
    ;;
  *)
    python3 -c "import sys;print(len(open('.claude/rules/'+sys.argv[1],encoding='utf-8').read()))" "$1"
    ;;
esac
