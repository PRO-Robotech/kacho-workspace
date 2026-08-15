#!/usr/bin/env bash
# check-03 — агент не выписывает у себя внутрипроектную подмену модулей.
#
# Что запрещает эта проверка: конструкцию `replace <внутренний модуль>` в тексте
# агента. Норма (`.claude/rules/polyrepo.md` §Правило зависимостей при
# полирепо-топологии) запрещает такую подмену в закоммиченном `go.mod` без
# оговорок и объясняет, почему; агенту остаётся сослаться, а не переписывать.
#
# Почему запрещена именно ЗАПИСЬ конструкции, а не «инструкция её применить»:
# отличить наставление от цитаты механически нельзя, а попытка отличать по
# соседним словам («запрещено», «нельзя») даёт ровно тот класс, который правила
# ловят в коде, — проверку, которая читает объяснение защиты вместо самой
# защиты. Поэтому предикат прямой: у нормы один дом, агент на него ссылается.
# Законный близнец, на котором проверка обязана молчать, — ссылка именем раздела
# без выписанной конструкции.
set -euo pipefail

# shellcheck source=_lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

WS="$(tooling_gate_workspace_root)"
NAME="check-03-agents-no-module-substitution"

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
        tooling_gate_fail "$NAME" "$a:${hit%%:*} — подмена модуля выписана у себя вместо ссылки на норму: ${hit#*:}"
        findings=$((findings + 1))
    done < <(grep -nE 'replace[[:space:]]+(\.\./kacho-|github\.com/PRO-Robotech)' "$WS/$a" | sed -E 's/^([0-9]+):[[:space:]]*/\1:/' || true)
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
