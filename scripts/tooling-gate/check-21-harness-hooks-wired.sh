#!/usr/bin/env bash
# check-21 — ХУКИ ХАРНЕССА ПРОВЯЗАНЫ В `.claude/settings.json` В ОБЕ СТОРОНЫ.
#
# Предмет (ws#801). Пробы и проверки зовут хуки напрямую, поэтому провязку их в
# `.claude/settings.json` не судил никто: снять запись хука из события — и наборы
# остаются зелёными, а хук перестаёт срабатывать молча. Обратное тоже молчит:
# хук зовёт соседний файл, который уехал (ws#710 — `rag-session-start.sh` звал
# `rag-freshness.sh`, снятый в архив, и `SessionStart` выходил кодом 127).
#
# Три оси:
#   A. запись без файла   — команда события называет путь `.claude/hooks/…`,
#                           которого в дереве нет;
#   B. хук без записи      — исполняемый файл верхнего уровня `.claude/hooks/`
#                           (`*.sh`, `*.py`), до которого не доходит ни одна запись:
#                           ни прямо, ни через файл, который запись зовёт;
#   C. вызов без файла     — провязанный (прямо или передачей) хук зовёт соседний
#                           файл `…/<имя>.sh|py`, которого нет.
#
# Исключения ВЫВОДЯТСЯ из дерева, а не выписываются. «Вспомогательный» — файл, до
# которого провязанный хук доходит своим кодом (по имени файла в исполняемой части,
# замыкание по передаче). Подкаталоги `.claude/hooks/<x>/` в ось B не входят: это
# разбор, библиотека, пробы и состояние хука верхнего уровня, а не точки входа
# харнесса. Архив (`.claude/backup/`) вне `.claude/hooks/` и не судится.
#
# Формы записи команды — все законные, и каждая доказана близнецом в inject.sh:
#   bash "$CLAUDE_PROJECT_DIR/.claude/hooks/x.sh" · $CLAUDE_PROJECT_DIR/.claude/hooks/x.sh ·
#   bash "${CLAUDE_PROJECT_DIR}/.claude/hooks/x.sh" · "$CLAUDE_PROJECT_DIR"/.claude/hooks/x.sh ·
#   .claude/hooks/x.sh (от корня).
# Судится исполняемая часть файла: комментарий отброшен, имя соседа в строке
# `# …` провязкой не является. Ось C читает шелл-файлы: вызов вида
# `$(dirname …)/x.sh`, `$ПЕРЕМЕННАЯ/x.sh` (от каталога скрипта) и `.claude/hooks/x.sh`
# (от корня). Вызов, собранный иначе (имя из переменной, из массива, объект пути
# в python), ось C не различает и этого не утверждает.
#
# Вердикт — в КОДЕ ВЫХОДА: 0 молчит, 1 находка, 2 отказ (нет настроек, не
# разбираются, ни одной записи хука — судить не о чем, и это не «находок 0»).
set -euo pipefail

# shellcheck source=_lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

WS="$(tooling_gate_workspace_root)"
NAME="check-21-harness-hooks-wired"

set +e
out="$(python3 - "$WS" <<'PY'
import json, os, re, subprocess, sys

ws = sys.argv[1]
S = os.path.join(ws, ".claude", "settings.json")
H = ".claude/hooks"
if not os.path.isfile(S):
    print("VOID нет .claude/settings.json — провязку выводить не из чего")
    sys.exit(2)
try:
    d = json.load(open(S, encoding="utf-8"))
except ValueError as e:
    print(f"VOID .claude/settings.json не разбирается как JSON: {e}")
    sys.exit(2)

FORM = re.compile(r'(?:\$\{?CLAUDE_PROJECT_DIR\}?"?/|(?:^|(?<=[\s"\']))(?=\.claude/))'
                  r'(\.claude/hooks/[^"\'\s;|&]+)')
records = []    # (событие, путь)
for event, groups in (d.get("hooks") or {}).items():
    for g in groups or []:
        for h in (g or {}).get("hooks") or []:
            for m in FORM.finditer(h.get("command") or ""):
                records.append((event, m.group(1)))
if not records:
    print("VOID в .claude/settings.json нет ни одной записи хука `.claude/hooks/…` — судить не о чем")
    sys.exit(2)

tree = set(subprocess.run(["git", "-C", ws, "ls-files", "--cached", "--others", "--exclude-standard", H],
                          capture_output=True, text=True).stdout.split("\n")) - {""}
entry = sorted(p for p in tree if re.fullmatch(r"\.claude/hooks/[^/]+\.(sh|py)", p))


def code(path):
    try:
        t = open(os.path.join(ws, path), encoding="utf-8").read()
    except (OSError, UnicodeDecodeError):
        return ""
    # Комментарий отброшен: имя соседа в `# …` провязкой не является.
    return "\n".join(re.sub(r'(^|\s)#(?![!{]).*$', r'\1', ln) for ln in t.split("\n"))


CALL = re.compile(r'(\$\(dirname[^)]*\)|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?|\.claude/hooks)'
                  r'/([A-Za-z0-9_][A-Za-z0-9_./-]*\.(?:sh|py))\b')

findings = []
wired = set()
for ev, p in records:
    if p in tree:
        wired.add(p)
    else:
        findings.append(f"A {ev}: запись зовёт {p} — файла в дереве НЕТ; событие обслуживает пустоту")

# Замыкание по передаче: провязанный файл доходит до соседа по имени в исполняемой части.
reach = set(wired)
frontier = list(wired)
calls_seen = 0
while frontier:
    f = frontier.pop()
    src = code(f)
    base_dir = os.path.dirname(f)
    # Ось C читает ШЕЛЛ: вызов соседа там — путь от каталога скрипта либо от корня.
    # В python вызов идёт объектом пути, а не строкой такой формы; его ось C не
    # различает (граница объявлена), для оси B файл по-прежнему читается по имени.
    for m in (CALL.finditer(src) if f.endswith(".sh") else ()):
        prefix, rel = m.group(1), m.group(2)
        calls_seen += 1
        if prefix == ".claude/hooks":
            tgt = os.path.normpath(".claude/hooks/" + rel)
        else:
            tgt = os.path.normpath(os.path.join(base_dir, rel))
        if tgt not in tree:
            # `$X/...` может звать не соседа, а чужой каталог: судим только цель внутри хуков.
            if tgt.startswith(H + "/"):
                findings.append(f"C {f}: зовёт {tgt} — файла НЕТ; хук упадёт на вызове (127)")
            continue
        if tgt not in reach:
            reach.add(tgt)
            frontier.append(tgt)
    for e in entry:
        if e not in reach and re.search(r'(?<![A-Za-z0-9_.-])' + re.escape(os.path.basename(e)) + r'\b', src):
            reach.add(e)
            frontier.append(e)

for e in entry:
    if e not in reach:
        findings.append(f"B {e}: хук верхнего уровня, до которого не доходит НИ ОДНА запись "
                        f".claude/settings.json — ни прямо, ни передачей; он не срабатывает")

print(f"CENSUS записей хука {len(records)} (событий {len({e for e, _ in records})}), "
      f"файлов верхнего уровня {len(entry)}, провязано прямо {len(wired)}, "
      f"доходит передачей {len(reach & set(entry)) - len(wired & set(entry))}, "
      f"вызовов соседа прочитано {calls_seen}")
for f in findings:
    print("FIND " + f)
sys.exit(1 if findings else 0)
PY
)"
rc=$?
set -e

while IFS= read -r ln; do
    case "$ln" in
        CENSUS\ *) tooling_gate_census "$NAME: ${ln#CENSUS }" ;;
        FIND\ *)   tooling_gate_fail "$NAME" "${ln#FIND }" ;;
        VOID\ *)   tooling_gate_void "$NAME" "${ln#VOID }" ;;
        *)         [ -n "$ln" ] && echo "$ln" ;;
    esac
done <<< "$out"

case "$rc" in
    0) tooling_gate_pass "$NAME" "каждая запись ведёт в файл, каждый хук верхнего уровня провязан, каждый вызов соседа резолвится"; exit 0 ;;
    1) tooling_gate_fail "$NAME" "провязка хуков харнесса разошлась с деревом"; exit 1 ;;
    2) exit 2 ;;
    *) tooling_gate_void "$NAME" "разбор упал кодом $rc — вердикта нет"; exit 2 ;;
esac
