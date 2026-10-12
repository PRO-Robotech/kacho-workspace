#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# ws-home.sh — корень воркспейса (дом копий `<WS>/tmp/`) по расположению
# скрипта. ЕДИНСТВЕННЫЙ способ его вывести для `lane-precheck.sh` и
# `wave-errors.sh`. Source-only.
#
# ЗАЧЕМ. Прежний вывод брал корень общего каталога git скрипта. Для worktree он
# верен (общий каталог — `.git` основной копии), а для КЛОНА под `<WS>/tmp/` —
# нет: общий каталог клона — его собственный `.git`, корнем выходил сам клон, и
# предпроверка признавала MAIN-COPY любую копию полосы, а счётчик ошибок писал
# в `<клон>/tmp/wave-N` вместо общей волны (check-verifier ws#933, A-r1, п. 6).
#
# ПРАВИЛО. Старт — корень общего каталога git файла (worktree → основная
# копия). Затем подъём: если старт лежит под `<X>/tmp/` и `<X>` — рабочая копия
# git (есть `<X>/.git`), корень — `<X>`; из нескольких таких берётся ВНЕШНИЙ
# (клон в `tmp/` клона, лежащего в `tmp/`, принадлежит внешнему воркспейсу).
# Вывести не из чего — пустая строка и код 1: вызывающий говорит VOID, а не
# угадывает.
#
# Держат `scripts/lane-precheck-inject.sh` и `scripts/wave-errors-inject.sh`:
# копия скрипта в клоне под `tmp/` песочницы без переопределения.

# ws_home <каталог внутри рабочей копии git> — печатает корень воркспейса.
ws_home() {
    local common start a ws=""
    common="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2> /dev/null)" || return 1
    [ -n "$common" ] || return 1
    case "$common" in
        */.git) start="${common%/.git}" ;;
        *) start="$(git -C "$1" rev-parse --show-toplevel 2> /dev/null)" || return 1 ;;
    esac
    start="$(cd "$start" 2> /dev/null && pwd -P)" || return 1
    ws="$start"
    a="$start"
    while [ "$a" != / ] && [ -n "$a" ]; do
        if [ "$(basename "$a")" = tmp ] && [ -e "$(dirname "$a")/.git" ]; then
            ws="$(dirname "$a")"
        fi
        a="$(dirname "$a")"
    done
    printf '%s\n' "$ws"
}
