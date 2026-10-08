#!/usr/bin/env bash
# skills-gate #09 — прогонщик состязательных evals различает режимы одним фактом и
# отличает «не выполнилось» от ответа (ws#973).
#
# ЧТО УТВЕРЖДАЕТ. `scripts/skill-evals/selftest.py` зовёт прогонщик СУДИМОГО дерева на
# синтетическом скиле с подменённым `claude` и требует: доля «с навыком» 1.0 и «без
# навыка» 0.0 (текст скила доезжает ровно в один режим); вызов с `is_error` — третья
# категория, вне знаменателя, прогон выходит кодом «без предмета»; модель и ревизии записаны; `regrade`
# воспроизводит сводку из сохранённых ответов; каталоги вызовов сняты; повторов
# меньше минимума — отказ. Модель не вызывается ни разу.
#
# ПОЧЕМУ ЗДЕСЬ. Замер, чей прогонщик подал текст скила в оба режима, отдаёт таблицу
# «эффекта нет» — правдоподобную и ложную. Проба стоит секунды и ловит это на отправке.
#
# Коды: 0 — пробы сошлись; 1 — расхождение; 2 — VOID: в судимом дереве нет прогонщика.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

NAME="09-skill-evals-runner-selftest"
WS="$(skills_gate_workspace_root)" || exit 2
RUNNER="$WS/scripts/skill-evals/skill_evals.py"
SELFTEST="$SCRIPT_DIR/../skill-evals/selftest.py"

if [ ! -f "$RUNNER" ]; then
    skills_gate_void "$NAME" "в судимом дереве нет scripts/skill-evals/skill_evals.py — пробовать нечего"
    exit 2
fi
[ -f "$SELFTEST" ] || { skills_gate_fail "$NAME" "нет пробы $SELFTEST"; exit 1; }

python3 -I "$SELFTEST" "$RUNNER"
rc=$?
case "$rc" in
    0) skills_gate_pass "$NAME" "прогонщик различает режимы и третий исход" ;;
    *) skills_gate_fail "$NAME" "проба прогонщика разошлась (код $rc)"; exit 1 ;;
esac
