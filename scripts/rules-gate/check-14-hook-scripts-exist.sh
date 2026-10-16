#!/usr/bin/env bash
# check-14 — КАЖДЫЙ СКРИПТ, КОТОРЫЙ ЗОВЁТ ХУК, СУЩЕСТВУЕТ.
#
# Предмет: хук, провязанный в `.claude/settings.json`, и скрипты, которые он зовёт
# дальше. Класс пришёл живым: `rag-freshness.sh` снят в архив 2026-09-20, а
# `rag-session-start.sh` и `rag-after-git.sh` звали его ещё месяц, гася ошибку
# (`2>/dev/null`, выход 0) — хук работал вхолостую на каждом старте сессии и каждом
# Bash, и ни один прогон этого не видел (сужение хранилища 2026-10-16).
#
# ЧТО ЧИТАЕТСЯ. (1) Команды хуков из `.claude/settings.json`: путь вида
# `$CLAUDE_PROJECT_DIR/<путь>` обязан быть файлом дерева. (2) Тело каждого такого
# `.sh`, затем — транзитивно — каждого `.sh`, на который оно ссылается: строка кода
# (не комментарий) с путём `<$переменная>/<путь>.sh|.py` резолвится от каталога
# ссылающегося скрипта либо от корня воркспейса — какую базу несёт переменная,
# скрипт объявляет сам, и обе формы в дереве есть (`$HOOK_DIR/…`, `$ws/scripts/…`).
#
# ГРАНИЦА ОБХОДА НАЗВАНА В ВЫВОДЕ: тела `.py` не читаются; путь без переменной в
# начале (`bash scripts/x.sh`) не распознаётся. Вердикт — в коде выхода: 0 молчит,
# 1 находка, 2 предмета нет (настроек нет либо в них ни одной команды хука).
#
# `--deps` печатает найденные файлы цепочки (по одному на строку) и выходит 0: по
# нему `inject.sh` кладёт в песочницу те скрипты вне `.claude/`, которые хуки зовут, —
# перечень выводится этим же обходом, а не выписывается.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(python3 "$SELF_DIR/../lib/gate_root.py" RULES_GATE_ROOT "${BASH_SOURCE[0]}")" || exit 2
cd "$root" 2>/dev/null || {
    echo "[VOID] check-14-hook-scripts-exist — корень «$root» не открывается; обходить нечего" >&2
    exit 2
}

exec python3 - "$root" "${1:-}" <<'PY'
import json, os, re, sys

root, mode = sys.argv[1], sys.argv[2]
S = ".claude/settings.json"
NAME = "check-14-hook-scripts-exist"
p = os.path.join(root, S)
if not os.path.isfile(p):
    print(f"[VOID] {NAME} — нет {S}: предмета нет, судить провязку хуков не в чем")
    sys.exit(2)
try:
    cfg = json.load(open(p, encoding="utf-8"))
except ValueError:
    print(f"[VOID] {NAME} — {S} не разбирается как JSON: вердикт был бы о форме, не о предмете")
    sys.exit(2)

commands = []
for event, groups in (cfg.get("hooks") or {}).items():
    for g in groups or []:
        for h in g.get("hooks") or []:
            if h.get("type") == "command" and h.get("command"):
                commands.append((event, h["command"]))
if not commands:
    print(f"[VOID] {NAME} — в {S} ни одной команды хука: обходить нечего")
    sys.exit(2)

findings = []
queue = []
found = set()
for event, cmd in commands:
    for rel in re.findall(r"\$\{?CLAUDE_PROJECT_DIR\}?/([A-Za-z0-9_./-]+)", cmd):
        if os.path.isfile(os.path.join(root, rel)):
            found.add(rel)
            if rel.endswith(".sh"):
                queue.append(rel)
        else:
            findings.append(f"СКРИПТА ХУКА НЕТ: {S} событие {event} зовёт «{rel}» — файла в дереве нет")

REF = re.compile(r"\$\{?\(?[A-Za-z_][^\s;|&\"'/]*[\"')}\]]*((?:/[A-Za-z0-9_.-]+)+\.(?:sh|py))\b")
seen = set()
refs = 0
while queue:
    rel = queue.pop()
    if rel in seen:
        continue
    seen.add(rel)
    here = os.path.dirname(rel)
    try:
        lines = open(os.path.join(root, rel), encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        continue
    for ln, line in enumerate(lines, 1):
        if line.lstrip().startswith("#"):
            continue
        for tail in REF.findall(line):
            tail = tail.lstrip("/")
            refs += 1
            hit = next((c for c in (os.path.normpath(os.path.join(here, tail)), os.path.normpath(tail))
                        if os.path.isfile(os.path.join(root, c))), None)
            if hit is None:
                findings.append(f"СКРИПТА, КОТОРЫЙ ЗОВЁТ ХУК, НЕТ: {rel}:{ln} зовёт «{tail}» — "
                                f"нет ни {os.path.normpath(os.path.join(here, tail))}, ни {tail}")
            else:
                found.add(hit)
                if hit.endswith(".sh"):
                    queue.append(hit)

if mode == "--deps":
    print("\n".join(sorted(found)))
    sys.exit(0)
census = (f"корень {root}; команд хуков {len(commands)}; скриптов прочитано {len(seen)}; "
          f"ссылок на скрипты {refs}; тела .py не читаются, путь без переменной не распознаётся")
for f in findings:
    print(f"КРАСНОЕ {f}")
print(f"{'[FAIL]' if findings else '[PASS]'} {NAME} — {census}; находок {len(findings)}")
sys.exit(1 if findings else 0)
PY
