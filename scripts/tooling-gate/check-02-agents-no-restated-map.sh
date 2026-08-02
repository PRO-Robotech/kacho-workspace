#!/usr/bin/env bash
# check-02 — агент не держит У СЕБЯ копию нормативной карты «ресурс → сервис»
# или «сервис → сервис», а ссылается на неё именем раздела.
#
# Что запрещает эта проверка: стрелочную карту в тексте агента. Причина — не
# вкусовая. Карта владельцев живёт в `.claude/rules/data-integrity.md`, граф
# рёбер — в `.claude/rules/polyrepo.md`; каждая копия карты в чужом файле
# устаревает МОЛЧА, потому что правку владельца никто в копии не повторяет, а
# конфликта при мёрже копия не даёт. Этот же корень уже записан в `repos.sh`:
# рукописный перечень репозиториев жил в трёх копиях, они разошлись между собой,
# и расхождение было ненаблюдаемо. Ссылка вместо копии — единственная форма,
# которая не может разойтись.
#
# Граница предиката объявлена, а не умолчана: он ловит СТРЕЛОЧНУЮ форму
# («X → kacho-y»), потому что именно она встретилась в дереве, и НЕ ловит ту же
# карту, изложенную прозой. Проверка не утверждает, что карта нигде не
# переписана, — она утверждает, что нигде не переписана в этой форме.
set -euo pipefail

# shellcheck source=scripts/tooling-gate/_lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

WS="$(tooling_gate_workspace_root)"
NAME="check-02-agents-no-restated-map"

mapfile -t AGENTS < <(tooling_gate_files "$WS" '.claude/agents/*.md')
if [ "${#AGENTS[@]}" -eq 0 ]; then
    tooling_gate_void "$NAME" "агентов в дереве нет — проверять нечего"
    exit 2
fi

lines_read=0
findings=0
for a in "${AGENTS[@]}"; do
    n="$(wc -l < "$WS/$a")"
    lines_read=$((lines_read + n))
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        tooling_gate_fail "$NAME" "$a:${hit%%:*} — карта переписана у себя вместо ссылки на норму: ${hit#*:}"
        findings=$((findings + 1))
    done < <(grep -nE '(→|->)[[:space:]]*kacho-' "$WS/$a" | sed -E 's/^([0-9]+):[[:space:]]*/\1:/' || true)
done

tooling_gate_census "$NAME: прочитано агентов ${#AGENTS[@]}, строк $lines_read"

if [ "$lines_read" -eq 0 ]; then
    tooling_gate_void "$NAME" "агенты прочитаны, но пусты — предикат остался без предмета"
    exit 2
fi

if [ "$findings" -gt 0 ]; then
    tooling_gate_fail "$NAME" "находок $findings"
    exit 1
fi

tooling_gate_pass "$NAME" "прочитано строк $lines_read, находок 0"
