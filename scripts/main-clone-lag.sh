#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# main-clone-lag.sh — сигнал «основной клон воркспейса отстаёт от origin/main на N» (ws#1200).
#
# ЗАЧЕМ. Исполнители берут скрипты из основного клона ($WS/scripts/…); клон, отставший
# от origin/main, держит на полосах прежние механизмы: 2026-10-18 отставание 27, затем 14
# коммитов через пару часов после догона. Догон после вливания делает демон
# scripts/autoland/autoland.sh; эта строка — для того, что мимо демона.
#
# ФОРМА
#   main-clone-lag.sh [<каталог внутри клона или копии>]   (по умолчанию — клон скрипта)
# Основной клон — каталог, чей `.git` есть `git rev-parse --git-common-dir`: из копии
# (worktree) судится основной клон, а не копия. Перед счётом — `git fetch origin main`
# с пределом MAIN_CLONE_LAG_FETCH_TIMEOUT с (по умолчанию 8): без него счёт шёл бы по
# устаревшему origin/main и молчал бы на отставании.
#
# ИСХОД — одна строка либо ничего:
#   0 — отставания нет: молчит;
#   1 — «MAIN-CLONE-LAG: основной клон <путь> (<ветка>) отстаёт от origin/main на N коммит(ов) …»;
#   2 — «MAIN-CLONE-LAG: отставание не установлено — <причина>»: нечего осмотреть либо
#       fetch не прошёл (ноль по устаревшему origin/main — не «отставания нет»).
# Хук SessionStart — session-memcap.sh --hook: печатает строку диспетчеру маршрутом.
set -uo pipefail

unknown() { printf 'MAIN-CLONE-LAG: отставание не установлено — %s\n' "$1"; exit 2; }

dir="${1:-$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")}"
[ -d "$dir" ] || unknown "каталога «$dir» нет"
common="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
    || unknown "«$dir» не в клоне git"
[ "$(basename -- "$common")" = .git ] || unknown "общий каталог git «$common» — не .git основного клона"
main="$(dirname -- "$common")"

fetched=1
GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes}" \
    timeout "${MAIN_CLONE_LAG_FETCH_TIMEOUT:-8}" git -C "$main" fetch -q origin main > /dev/null 2>&1 || fetched=0
git -C "$main" rev-parse -q --verify refs/remotes/origin/main > /dev/null || unknown "в $main нет origin/main"
n="$(git -C "$main" rev-list --count HEAD..refs/remotes/origin/main 2>/dev/null)" \
    || unknown "счёт HEAD..origin/main в $main не прошёл"
if [ "$fetched" -eq 0 ] && [ "$n" -eq 0 ]; then
    unknown "fetch origin main в $main не прошёл, по известному origin/main отставания нет"
fi
[ "$n" -gt 0 ] || exit 0
br="$(git -C "$main" symbolic-ref -q --short HEAD)" || br="отделённая голова"
printf 'MAIN-CLONE-LAG: основной клон %s (%s) отстаёт от origin/main на %s коммит(ов)%s — полосы берут отсюда старые scripts/. Маршрут: догон — git-operator, «git -C %s merge --ff-only origin/main» (без stash и reset; пересечение с локальной правкой — перечнем файлов диспетчеру); после вливания в main догоняет scripts/autoland/autoland.sh.\n' \
    "$main" "$br" "$n" "$([ "$fetched" -eq 1 ] || echo ' (fetch не прошёл — по известному origin/main)')" "$main"
exit 1
