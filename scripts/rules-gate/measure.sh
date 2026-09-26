#!/usr/bin/env bash
# Прибор объёма и формы корпуса. НЕ гейт: код выхода всегда 0, вердикт — у check-06.
# Символы, не байты: кириллица в UTF-8 вдвое тяжелее, и `wc -c` дал бы вдвое больше.
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# КОРЕНЬ — ИЗ СВОЕГО РАСПОЛОЖЕНИЯ, А НЕ ИЗ ТЕКУЩЕГО КАТАЛОГА (2026-09-22). Здесь
# стоял `cd "$(git rev-parse --show-toplevel)"`, и прибор, запущенный с cwd в
# соседнем worktree полосы, мерил ЧУЖОЕ дерево, ничего об этом не печатая. Для
# ПРИБОРА это хуже, чем для гейта: его число цитируют в отчётах и в шапках
# проверок, и разошедшееся число некому опровергнуть. Тот же класс — `check-11`.
root="${RULES_GATE_ROOT:-$(cd "$SELF_DIR/../.." && pwd)}"
cd "$root" 2>/dev/null || {
    echo "корень «$root» не открывается — мерить нечего" >&2
    exit 2
}
echo "корень $root" >&2
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
# Долг без имени — на гейт с именем САМОЙ строки (MANIFEST.md, mf-debt-names-its-row):
# `ЗАВЕСТИ` без следующего имени считается долгом с id строки, а не пропускается.
def debts(line):
    w = line.split()
    rid = line.split(' · ', 1)[0].strip()
    out = []
    for i, t in enumerate(w):
        if t.rstrip(':;,') != 'ЗАВЕСТИ':
            continue
        nxt = w[i + 1] if i + 1 < len(w) else ''
        named = t == 'ЗАВЕСТИ' and nxt[:1].isalnum()
        out.append(nxt if named else rid)
    return out
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
    # Потолок берётся У ПРОВЕРКИ, а не выписывается здесь: выписанный был бы
    # вторым домом одной величины и разошёлся бы с ней молча — измеритель
    # продолжал бы печатать «запас», меряя чужой потолок.
    python3 - "$(dirname "${BASH_SOURCE[0]}")/corpus_ceiling.py" <<'PY'
import glob, importlib.util, os, sys
spec = importlib.util.spec_from_file_location('c6src', sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
rows = [(len(open(f, encoding='utf-8').read()), os.path.basename(f))
        for f in sorted(glob.glob('.claude/rules/*.md'))]
for n, b in sorted(rows, reverse=True):
    print('%8d  %s' % (n, b))
t = sum(n for n, _ in rows)
print('%8d  ИТОГО, потолок %d, запас %d' % (t, mod.CEILING, mod.CEILING - t))
PY
    ;;
  *)
    python3 -c "import sys;print(len(open('.claude/rules/'+sys.argv[1],encoding='utf-8').read()))" "$1"
    ;;
esac
