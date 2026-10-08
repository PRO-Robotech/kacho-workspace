#!/usr/bin/env bash
# skills-gate #08 — каждый `.claude/skills/<скил>/evals/evals.json` держит схему
# состязательных evals (ws#973).
#
# ЧТО УТВЕРЖДАЕТ. Файл разбирается; ключи на каждом уровне ровно известные; `skill`
# равен имени каталога; кейсов и ловушек не меньше минимумов прогонщика (`MIN_CASES`,
# `MIN_TRAPS` в `scripts/skill-evals/skill_evals.py`); у каждого кейса есть
# положительное утверждение `must`; выражения компилируются и не совпадают с пустой
# строкой; в `evals/` нет посторонних файлов; рядом лежит `SKILL.md`.
#
# ПОЧЕМУ ГЕЙТ, А НЕ ПРОГОН. Прогон зовёт модель и стоит денег и минут — на отправке его
# не гоняют. Испорченный файл при этом ломает замер МОЛЧА: кейс из одних `must_not`
# засчитывается пустому ответу, `.*` в `must` — любому, файл без ловушек меряет то,
# что модель и так знает, и таблица «с навыком против без» перестаёт различать.
#
# ОДИН КОДЕК. Схему судит та же функция, которой прогонщик проверяет файл перед
# прогоном (`validate_doc`): вторая копия правил схемы разошлась бы с первой молча.
#
# Коды: 0 — файлы есть и схема выдержана; 1 — находка с координатой; 2 — VOID: файлов
# нет (предмета нет) либо git не ответил.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

NAME="08-skill-evals-schema"
WS="$(skills_gate_workspace_root)" || exit 2
VALIDATOR="$SCRIPT_DIR/../skill-evals/skill_evals.py"

[ -f "$VALIDATOR" ] || { skills_gate_fail "$NAME" "нет кодека схемы $VALIDATOR — судить нечем"; exit 1; }

python3 -I "$VALIDATOR" validate --root "$WS"
rc=$?
case "$rc" in
    0) skills_gate_pass "$NAME" "схема evals выдержана" ;;
    2) skills_gate_void "$NAME" "evals.json в дереве нет либо git не ответил" ;;
    *) skills_gate_fail "$NAME" "схема evals нарушена"; rc=1 ;;
esac
exit "$rc"
