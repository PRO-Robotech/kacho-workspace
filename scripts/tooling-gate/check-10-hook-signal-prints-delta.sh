#!/usr/bin/env bash
# check-10 — печатающий сигнал ГЛАВНОГО ПОТОКА доходит до признака дельты.
#
# Что проверяется. Хук, зарегистрированный на событие главного потока
# (`UserPromptSubmit`, `Stop`) и что-либо ПЕЧАТАЮЩИЙ, обязан доходить до общего
# механизма `.claude/hooks/lib/hook_signal.py` — сам либо через передачу одному
# файлу оснастки, который до него доходит. Иначе его текст выходит СОСТОЯНИЕМ, а не
# дельтой: повторённый сигнал неотличим от новой находки, и новая находка теряется в
# фоне. Адресат этих событий — диспетчер: у него нет ни `Read`, ни `Bash`, он обязан
# верить напечатанному и перепроверить его не может.
#
# Перечень ВЫВОДИТСЯ из `.claude/settings.json` — из регистрации, а не из списка в
# этом файле. Список внутри проверки устаревал бы ровно тогда, когда заводят новый
# хук, то есть в единственный момент, когда проверка нужна. Ноль цели — отказ (VOID),
# а не успех.
#
# # Граница проверки, объявленная, а не умолчанная
#
# 1. `PostToolUse` НЕ судится: его текст читает ИСПОЛНИТЕЛЬ, у которого есть и
#    `Read`, и `Bash`, — он перепроверяет сам, и адресат сигнала другой. Что эти
#    хуки печатают состояние — открытый долг #714, не предмет этой проверки.
# 2. «Печатает» опознаётся по исполняемой части строки (комментарий отброшен), а не
#    разбором; форма проверки — слово `echo`/`printf`/`cat <<` и питоновские
#    `sys.stdout.write`/`sys.stderr.write`/`print(`. Печать, собранную иначе, она НЕ
#    ловит и этого не утверждает.
# 3. Что у КАЖДОГО вызова названы агент-адресат и машинно проверяемый предикат
#    снятия, держит не эта проверка, а сам механизм: `hook_signal.gate` без любого из
#    двух полей отказывается печатать и выходит кодом 2 (проба — в `inject.sh`).
#    Здесь это не переписывается: два места об одном предмете расходятся молча.
set -euo pipefail

# shellcheck source=_lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

WS="$(tooling_gate_workspace_root)"
NAME="check-10-hook-signal-prints-delta"
MECH=".claude/hooks/lib/hook_signal.py"
SETTINGS=".claude/settings.json"

if [ ! -f "$WS/$SETTINGS" ]; then
    tooling_gate_void "$NAME" "нет $SETTINGS — регистрацию хуков выводить не из чего"
    exit 2
fi

# Пути хуков главного потока — из регистрации. `$CLAUDE_PROJECT_DIR` в команде
# раскрывается в корень дерева: он и есть координата этого репозитория.
mapfile -t HOOKS < <(python3 - "$WS/$SETTINGS" <<'PY'
import json, re, sys
MAIN = ("UserPromptSubmit", "Stop")
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(0)
out = []
for event, groups in (d.get("hooks") or {}).items():
    if event not in MAIN:
        continue
    for g in groups or []:
        for h in g.get("hooks") or []:
            cmd = h.get("command") or ""
            for m in re.finditer(r'\$(?:CLAUDE_PROJECT_DIR|\{CLAUDE_PROJECT_DIR\})/([^"\s]+)', cmd):
                out.append(m.group(1))
for p in sorted(set(out)):
    print(p)
PY
)

if [ "${#HOOKS[@]}" -eq 0 ]; then
    tooling_gate_void "$NAME" "в $SETTINGS не зарегистрировано ни одного хука главного потока — предмета нет"
    exit 2
fi

# `reaches <относительный путь>` — доходит ли файл до механизма сам или передачей.
# Глубина передачи ОДНА и названа: цепочку длиннее эта проверка не прослеживает и
# этого не утверждает.
reaches() {
    local rel="$1" f="$WS/$1" dep
    [ -f "$f" ] || return 1
    grep -q 'hook_signal' "$f" && return 0
    while read -r dep; do
        [ -n "$dep" ] || continue
        [ -f "$WS/$dep" ] || continue
        grep -q 'hook_signal' "$WS/$dep" && return 0
    # `|| true` у КАЖДОГО шага — не косметика. Подоболочка наследует `set -e`, и
    # первый шаблон, не нашедший ничего, обрывал её МОЛЧА: второй шаблон не исполнялся
    # вовсе, и передача через переменную каталога не опознавалась. Найдено прогоном:
    # `docfresh.sh` объявлялся не доходящим до механизма, хотя доходит.
    done < <({ grep -oE '\.claude/hooks/[A-Za-z0-9_./-]+\.(sh|py)' "$f" | sort -u || true
               # Передача через переменную каталога: `exec "$PY" "$GUARD"`, где GUARD
               # собран из каталога скрипта. Разрешается по имени файла в присваивании.
               grep -oE '[A-Za-z0-9_]+/[A-Za-z0-9_.-]+\.(sh|py)"?$' "$f" \
                 | tr -d '"' | sed "s|^|.claude/hooks/|" | sort -u || true; })
    return 1
}

examined=0; printing=0; reached=0; findings=0
for rel in "${HOOKS[@]}"; do
    if [ ! -f "$WS/$rel" ]; then
        tooling_gate_fail "$NAME" "$SETTINGS регистрирует $rel — файла в дереве НЕТ; событие главного потока обслуживает пустоту"
        findings=$((findings + 1))
        continue
    fi
    examined=$((examined + 1))
    # Комментарий отброшен: слово `echo` в шапке печатью не является.
    if ! sed -E 's/(^|[[:space:]])#.*$//' "$WS/$rel" \
         | grep -qE '(^|[^[:alnum:]_])(echo|printf)([[:space:]]|$)|cat[[:space:]]*<<|sys\.(stdout|stderr)\.write|(^|[^[:alnum:]_])print\('; then
        continue
    fi
    printing=$((printing + 1))
    if reaches "$rel"; then
        reached=$((reached + 1))
    else
        tooling_gate_fail "$NAME" "$rel печатает в окно главного потока и НЕ доходит до $MECH — текст выходит состоянием, повтор неотличим от новой находки"
        findings=$((findings + 1))
    fi
done

if [ ! -f "$WS/$MECH" ]; then
    tooling_gate_fail "$NAME" "нет $MECH — признака дельты в дереве не существует, ссылки на него у хуков ведут в пустоту"
    findings=$((findings + 1))
fi

tooling_gate_census "$NAME: зарегистрировано хуков главного потока ${#HOOKS[@]}, прочитано $examined, из них печатают $printing, доходят до признака дельты $reached"

if [ "$examined" -eq 0 ]; then
    tooling_gate_void "$NAME" "ни один зарегистрированный хук не прочитан — предикат остался без предмета"
    exit 2
fi
if [ "$findings" -gt 0 ]; then
    tooling_gate_fail "$NAME" "находок $findings"
    exit 1
fi
if [ "$printing" -eq 0 ]; then
    tooling_gate_void "$NAME" "прочитано $examined хуков, НИ ОДИН из них не печатает — судить нечего, и это не «всё в порядке»"
    exit 2
fi

tooling_gate_pass "$NAME" "печатающих $printing, все доходят до признака дельты"
