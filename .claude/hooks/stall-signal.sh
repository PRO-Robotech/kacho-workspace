#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# stall-signal.sh — застой полос доходит до диспетчера сам (ws#1001).
#
# Решение владельца 2026-10-11: «И реши проблему раз и навсегда что таски уходят в
# часовые таймауты и ничего не делают а мы ждем». Замер ws#1001: диспетчер узнавал
# о застое живого workflow только по goal check-in, отложенному на 30–305 мин.
#
# События главного потока (адресат — диспетчер, у которого нет Bash):
#   UserPromptSubmit — находки `scripts/stall-census.sh` строкой «⏱ ЗАСТОЙ» в
#                      контекст (код 1), либо «детектор не прочитал» (код 2,
#                      иной код, либо код 1 без единой строки STALL-/UNREACTED-);
#   Stop             — при коде 1 ход НЕ заканчивается: выход 2, перечень в stderr,
#                      диспетчер получает его и действует (база §10). Повторно в
#                      том же ходе (`stop_hook_active`) не держит — петли нет.
#                      Код 2 на Stop молчит: его несёт UserPromptSubmit.
# Без находок молчит. Сессию не роняет: сбой самого хука — строка, а не отказ.
# Шов инъекции: STALL_CENSUS_EXTRA — доводы прибору (`--ps <файл>`), только для
# scripts/stall-census-inject.sh.
set -uo pipefail

ws="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
census="$ws/scripts/stall-census.sh"
input="$(timeout 2 cat 2> /dev/null || true)"
event="$(printf '%s' "$input" | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: d={}
print(d.get("hook_event_name",""), "active" if d.get("stop_hook_active") else "")' 2> /dev/null)"
active="${event#* }"; event="${event%% *}"

if [ ! -r "$census" ]; then
    [ "$event" = Stop ] && exit 0
    echo "⏱ ЗАСТОЙ НЕ ПРОВЕРЕН: нет $census → tooling-maintainer; молчание не «чисто»."
    exit 0
fi
# shellcheck disable=SC2086
out="$(printf '%s' "$input" | timeout 8 bash "$census" ${STALL_CENSUS_EXTRA:-} 2>&1)"; rc=$?
head_line="⏱ ЗАСТОЙ (scripts/stall-census.sh): маршрут — база диспетчера §10: TaskStop застрявшего, остаток — новым коротким шагом с исходом «идёт» и сроком."
body="$(printf '%s\n' "$out" | grep -E '^(STALL-|UNREACTED-)' | head -12)"
# Код 1 без единой названной строки застоя — не застой, а сбой прибора (опыт
# check-verifier по #1002): ход им не держится, диспетчер видит «не проверен».
[ "$rc" = 1 ] && [ -z "$body" ] && rc=3
case "$rc" in
    0) exit 0 ;;
    1)
        body="$(printf '%s\n' "$out" | grep -E '^(STALL-|UNREACTED-|UNREAD )' | head -16)"
        if [ "$event" = Stop ]; then
            [ "$active" = active ] && exit 0
            { echo "$head_line"; printf '%s\n' "$body"; } >&2
            exit 2
        fi
        echo "$head_line"; printf '%s\n' "$body"
        ;;
    *)
        [ "$event" = Stop ] && exit 0
        why="$(printf '%s\n' "$out" | grep -E 'VOID|Error|Traceback' | tail -1)"
        [ -n "$why" ] || why="$(printf '%s' "$out" | tail -1)"
        echo "⏱ ЗАСТОЙ НЕ ПРОВЕРЕН (код $rc): $(printf '%s' "$why" | cut -c1-200) → tooling-maintainer; это не «чисто»."
        ;;
esac
exit 0
