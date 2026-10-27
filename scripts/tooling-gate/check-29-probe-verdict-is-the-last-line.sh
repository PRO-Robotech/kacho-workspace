#!/usr/bin/env bash
# check-29 — итог пробы с мутантами стоит ПОСЛЕДНЕЙ исполняемой строкой (ws#1460).
#
# Признак (⛔ check-verifier ws#1460 @c2fc827cf): в `wave-template-inject.sh` пять вызовов
# `mutant` дописаны ПОСЛЕ итоговой строки `[ "$rc" -eq 0 ] && [ "$fail" -eq 0 ]`. Код возврата
# скрипта — код последней команды, а `mutant` возвращает 0: контроль с кодом 1 и 2 упавших
# утверждения дали rc 0 — маскировались все 317 мутантов и контроль.
#
# ПРЕДМЕТ — каждый отслеживаемый git `*.sh`, объявляющий функцию `mutant()` либо `twin()`
# (перечень выводится из индекса обходом, не выписывается). Последняя исполняемая строка —
# вне комментария, пустой строки и тела heredoc — обязана быть итогом: начинаться с `[`, `[[`
# либо `exit`. Вызов пробы, `echo`, `fi` последней строкой — находка с координатой файл:строка.
#
# ГРАНИЦА (названа): итог внутри функции, вызванной последней строкой, и `exit` из ловушки не
# разбираются — форма с последней строкой-вызовом всё равно находка; `<<МЕТКА` внутри кавычек
# одной строки — текст (так пишет no-wait-guard/prove.sh), литерал, растянутый на несколько
# строк, построчно не отслеживается; файлы-части, которые
# подключаются точкой (`. part`) и не объявляют `mutant()`/`twin()`, вне предмета.
#
# ПРЕДПОСЫЛКА (VOID, код 2): предмет не пуст — хотя бы один файл объявляет `mutant()`/`twin()`.
# Коды: 0 — находок нет; 1 — находка с координатой; 2 — предмета нет.
set -uo pipefail

name="$(basename "${BASH_SOURCE[0]}" .sh)"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$here/_lib.sh"
root="$(tooling_gate_workspace_root)" || exit 2

python3 - "$root" "$name" <<'PY'
import os, re, subprocess, sys
root, name = sys.argv[1], sys.argv[2]
DECL = re.compile(r'^(?:mutant|twin)\(\)\s*\{', re.M)
TAG = re.compile(r'([\'"]?)([A-Za-z_][A-Za-z0-9_]*)\1')
VERDICT = re.compile(r'^(?:\[\[?\s|exit(?:\s|$))')


def heredoc(line):
    """Открывающий heredoc ВНЕ кавычек и комментария: (с дефисом?, метка) либо None.
    `<<EOF` внутри строкового литерала (`$'bash <<EOF\\n…'`) — текст, а не heredoc."""
    i, n = 0, len(line)
    while i < n:
        c = line[i]
        if c == '#' and (i == 0 or line[i - 1] in ' \t;|&('):
            return None
        if line.startswith('<<<', i):
            i += 3
            continue
        if line.startswith('<<', i):
            j = i + 2
            dash = j < n and line[j] == '-'
            j += dash
            while j < n and line[j] in ' \t':
                j += 1
            m = TAG.match(line, j)
            if m:
                return dash, m.group(2)
            i = j
            continue
        if c == '\\':
            i += 2
            continue
        if c == "'" or (c == '$' and line[i + 1:i + 2] == "'"):
            j = i + (2 if c == '$' else 1)
            while j < n and line[j] != "'":
                j += 2 if (c == '$' and line[j] == '\\') else 1
            i = j + 1
            continue
        if c == '"':
            j = i + 1
            while j < n and line[j] != '"':
                j += 2 if line[j] == '\\' else 1
            i = j + 1
            continue
        i += 1
    return None
ls = subprocess.run(['git', '-C', root, 'ls-files', '-z', '--', '*.sh'], capture_output=True)
if ls.returncode != 0:
    print('[VOID] %s — индекс git не прочитан: %s' % (name, ls.stderr.decode('utf-8', 'replace').strip()[:200]),
          file=sys.stderr)
    sys.exit(2)
paths = [p for p in ls.stdout.decode('utf-8').split('\0') if p]
subj, finds = 0, []
for p in paths:
    try:
        t = open(os.path.join(root, p), encoding='utf-8').read()
    except (OSError, UnicodeDecodeError):
        continue
    if not DECL.search(t):
        continue
    subj += 1
    last, tag, dash = None, None, False
    for n, l in enumerate(t.splitlines(), 1):
        if tag is not None:
            if (l.lstrip('\t') if dash else l) == tag:
                tag = None
            continue
        s = l.strip()
        if s and not s.startswith('#'):
            last = (n, s)
        h = heredoc(l)
        if h:
            dash, tag = h
    if last is None:
        finds.append('%s: исполняемых строк нет' % p)
    elif not VERDICT.match(last[1]):
        finds.append('%s:%d: последняя исполняемая строка «%s» — не итог: код скрипта отдаст она, а не '
                     'вердикт пробы (ждём `[ … ]`, `[[ … ]]` либо `exit`)' % (p, last[0], last[1][:100]))
print('[CENSUS] %s: файлов *.sh в индексе %d, из них проб с mutant()/twin() %d; находок %d'
      % (name, len(paths), subj, len(finds)))
if subj == 0:
    print('[VOID] %s — ни один файл не объявляет mutant()/twin(): судить нечего' % name, file=sys.stderr)
    sys.exit(2)
for f in finds:
    print('[FAIL] %s — %s' % (name, f), file=sys.stderr)
if finds:
    sys.exit(1)
print('[PASS] %s — итог каждой пробы с мутантами — её последняя исполняемая строка' % name)
PY
