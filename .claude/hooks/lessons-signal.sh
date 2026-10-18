#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# lessons-signal.sh — уроки полос доходят до диспетчера сами (ws#1199, новый флоу, часть 8).
#
# Событие Stop главного потока: `scripts/lessons/collect.sh signal` дописывает новые уроки
# журналов в ведомость (бюджет LESSONS_BUDGET, 5 с; недочитанное — в следующий ход) и, если
# есть что делать — класс с повтором без задачи, открытый старше суток, повтор после влитого
# механизма, урок без ключа, — печатает строку «📚 УРОКИ: …» с перечнем в stderr и выходит 2:
# ход не заканчивается, диспетчер ставит полосы (база §10). Защита от бесконечного хода — как
# у stall-signal: повторно в том же ходе (`stop_hook_active`) не держит; сверх того тот же
# перечень — не чаще раза в сутки (`lessons-scan.json`). Делать нечего (код 0) — молчит.
# Сбой сборщика отличим от «делать нечего»: любой код, кроме 0 и 1 со строкой сигнала, и
# таймаут LESSONS_TIMEOUT (10 с) — строка «📚 УРОКИ НЕ СОБРАНЫ: <причина>», та же причина —
# не чаще раза в сутки (`lessons-hook-void` рядом с ведомостью).
# Швы пробы (scripts/lessons/inject.sh): LESSONS_COLLECT, LESSONS_TIMEOUT, LESSONS_NOW.
set -uo pipefail

ws="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
collect="${LESSONS_COLLECT:-$ws/scripts/lessons/collect.sh}"
lim="${LESSONS_TIMEOUT:-10}"
now="${LESSONS_NOW:-$(date +%s)}"
input="$(timeout 2 cat 2> /dev/null || true)"
case "$input" in *'"stop_hook_active":true'* | *'"stop_hook_active": true'*) exit 0 ;; esac

void() {  # void <причина> — сбой сборщика; та же причина не чаще раза в сутки
    local dir="${LESSONS_DIR:-$ws/tmp/reports}" sig s t
    sig="$(printf '%s' "$1" | cksum | cut -d' ' -f1)"
    if read -r s t 2> /dev/null < "$dir/lessons-hook-void" && [ "$s" = "$sig" ] \
        && [[ "$t" =~ ^[0-9]+$ ]] && [ $((${now%.*} - t)) -lt 86400 ]; then
        exit 0
    fi
    mkdir -p "$dir" 2> /dev/null && printf '%s %s\n' "$sig" "${now%.*}" > "$dir/lessons-hook-void" 2> /dev/null
    echo "📚 УРОКИ НЕ СОБРАНЫ: $1 → tooling-maintainer; это не «делать нечего»." >&2
    exit 2
}

[ -r "$collect" ] || void "нет сборщика $collect"
err="$(mktemp 2> /dev/null)" || void "нет временного файла"
trap 'rm -f "$err"' EXIT
out="$(timeout -k 2 "$lim" bash "$collect" signal --budget "${LESSONS_BUDGET:-5}" 2> "$err")"; rc=$?
why="$(grep -E 'VOID|Error|Traceback' "$err" | tail -1)"
[ -n "$why" ] || why="$(tail -1 "$err")"
why="$(printf '%s' "$why" | cut -c1-200)"
case "$rc" in
    0) exit 0 ;;
    1) case "$out" in '📚 УРОКИ'*) ;; *) void "код 1 без строки сигнала${why:+: $why}" ;; esac ;;
    124 | 137) void "таймаут ${lim} с" ;;
    *) void "код $rc${why:+: $why}" ;;
esac
{
    printf '%s\n' "$out" | head -1
    echo "Маршрут — база диспетчера §10: git-operator заводит задачи «нужен механизм» по перечню и отмечает «collect.sh mark <ключ> mechanism <репо>#N»; пачку берёт tooling-maintainer."
    printf '%s\n' "$out" | tail -n +2
} >&2
exit 2
