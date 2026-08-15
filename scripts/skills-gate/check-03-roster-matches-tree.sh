#!/usr/bin/env bash
# skills-gate #03 — перечень канонических скилов сходится с деревом.
#
# ЧТО УТВЕРЖДАЕТ. Множество имён, перечисленных в `.claude/rules/ai-tooling.md`
# §Канонические скилы, побайтово совпадает с множеством **отслеживаемых git**
# директорий `.claude/skills/*/`. Строка без директории и директория без строки —
# обе находки, и обе печатаются отдельно.
#
# ПОЧЕМУ. Перечень — утверждение о дереве, а утверждение о дереве устаревает
# молча. Заведённый скил не попадает в перечень (его никто не найдёт), снятый —
# остаётся в нём просроченным объявлением. Оба состояния уже наблюдались: перечень
# объявлял одно число, на диске лежало другое.
#
# ПРЕДПОСЫЛКА ГЕЙТА (проверяется здесь же). Запрет опирается на форму перечня:
# имена объявлены как `- \`<имя>\` (workspace)`. Сменится форма — гейт останется
# без предмета, поэтому «нашёл 0 имён» — отдельный исход (VOID), а не успех.
#
# Коды выхода: 0 — множества совпали; 1 — расхождение; 2 — VOID.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

WS="$(skills_gate_workspace_root)"
NAME="03-roster-matches-tree"
RULE="$WS/.claude/rules/ai-tooling.md"

[ -f "$RULE" ] || { skills_gate_void "$NAME" "нет $RULE"; exit 2; }

# Тело перечня: от заголовка «## Канонические скилы» до следующего «## »/«### ».
roster="$(awk '
    /^## Канонические скилы/ {inside=1; next}
    inside && /^#{2,3} / {exit}
    inside {print}
' "$RULE" | sed -nE 's/^- `([a-z0-9<>/-]+)`.*/\1/p' | sort -u)"

# `<svc>-load-testing` живёт в репозитории сервиса, а не здесь — в счёт не входит.
roster="$(printf '%s\n' "$roster" | grep -v '^<svc>' || true)"

tracked="$(git -C "$WS" ls-files '.claude/skills/*/SKILL.md' | cut -d/ -f3 | sort -u)"

n_roster="$(printf '%s\n' "$roster" | grep -c . || true)"
n_tracked="$(printf '%s\n' "$tracked" | grep -c . || true)"

if [ "$n_roster" -eq 0 ]; then
    skills_gate_void "$NAME" "в §Канонические скилы не разобрано ни одного имени — форма перечня сменилась, гейт без предмета"
    exit 2
fi
if [ "$n_tracked" -eq 0 ]; then
    skills_gate_void "$NAME" "в индексе git нет ни одного скила — проверять нечего"
    exit 2
fi

only_roster="$(comm -23 <(printf '%s\n' "$roster") <(printf '%s\n' "$tracked"))"
only_tree="$(comm -13 <(printf '%s\n' "$roster") <(printf '%s\n' "$tracked"))"

echo "перепись: имён в перечне — $n_roster; отслеживаемых директорий скилов — $n_tracked"

rc=0
if [ -n "$only_roster" ]; then
    echo "  в перечне есть, в дереве нет (просроченное объявление):" >&2
    printf '    %s\n' $only_roster >&2
    rc=1
fi
if [ -n "$only_tree" ]; then
    echo "  в дереве есть, в перечне нет (скил, которого никто не найдёт):" >&2
    printf '    %s\n' $only_tree >&2
    rc=1
fi

if [ "$rc" -ne 0 ]; then
    skills_gate_fail "$NAME" "перечень разошёлся с деревом"
    exit 1
fi

skills_gate_pass "$NAME" "перечень и дерево совпали: $n_tracked скилов"
exit 0
