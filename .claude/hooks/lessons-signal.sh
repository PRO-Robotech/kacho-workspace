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
# ход не заканчивается, диспетчер ставит полосы (база §10). Тот же перечень повторяется не
# чаще раза в сутки (`lessons-scan.json`), повторно в том же ходе (`stop_hook_active`) не
# держит. Делать нечего — молчит. Журналов нет — строка «📚 УРОКИ НЕ СОБРАНЫ» (не «уроков 0»),
# тем же правилом раз в сутки. Сбой самого хука сессию не роняет и ход не держит.
# Шов пробы: LESSONS_COLLECT — путь сборщика (scripts/lessons/inject.sh).
set -uo pipefail

ws="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
collect="${LESSONS_COLLECT:-$ws/scripts/lessons/collect.sh}"
input="$(timeout 2 cat 2> /dev/null || true)"
case "$input" in *'"stop_hook_active":true'* | *'"stop_hook_active": true'*) exit 0 ;; esac
[ -r "$collect" ] || exit 0
out="$(timeout 10 bash "$collect" signal --budget "${LESSONS_BUDGET:-5}" 2> /dev/null)"; rc=$?
[ "$rc" = 1 ] && [ -n "$out" ] || exit 0
{
    printf '%s\n' "$out" | head -1
    echo "Маршрут — база диспетчера §10: git-operator заводит задачи «нужен механизм» по перечню и отмечает «collect.sh mark <ключ> mechanism <репо>#N»; пачку берёт tooling-maintainer."
    printf '%s\n' "$out" | tail -n +2
} >&2
exit 2
