#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# push-then.sh — цепочка «отправка → зависимый шаг» одной командой (ws#1242).
#
# ЗАЧЕМ. Шаг, зависящий от отсоединённой отправки (события одобрения, PR, ревью по дельте,
# autoland start), трижды за 2026-10-19 выдан раньше её .rc (kaname#297 ×2, ws#1238), и каждая
# цепочка писалась заново на голову (tmp/chain-*.sh, tmp/land-*.sh: свои паузы, свой разбор
# кода, своя сверка ls-remote). Здесь порядок держит ФАКТ, а не текст: шаг выдаётся лишь после
# кода 0 отправки И `lane-precheck.sh --premise` `pushed <репо> <ветка> <sha>` (голова на origin
# = отправленной, `git ls-remote`).
#
# ФОРМА
#   push-then.sh start <каталог шагов> <копия> <ветка> -- <зависимый шаг…>
#       — копия чистая (иначе 64), sha = HEAD копии; отсоединённая голова — лишь с KACHO_TASK
#         в окружении (иначе слот отдал бы 77; 64). Запуск — scripts/detach.sh start: печатает
#         «идёт: pid; журнал; rc; срок» и строку дочитки; исход — `detach.sh status <.rc>`
#         ОДНИМ шагом, код .rc — код цепочки (ниже). Внутри: отправка полным хуком слотом
#         `heavy-slot.sh --wait 300 ci-local -- git push origin HEAD:refs/heads/<ветка>` из
#         копии, затем `after`.
#   push-then.sh after <.rc отправки> <владелец/репо> <ветка> <sha40> -- <зависимый шаг…>
#       — короткий шаг для отправки, запущенной иначе (detach.sh start, --enqueue): шаг
#         выдаётся ТОЛЬКО при `detach.sh status` 0 и `pushed` 0.
# Шаг исполняется в копии (start) либо в текущем каталоге (after) с PUSHED_SHA=<sha> в
# окружении; это команда argv, не строка оболочки.
#
# КОДЫ (start — свой выход; .rc цепочки и after — по исходу):
#   0 — отправка доехала, шаг выдан и вышел 0; иначе — код шага, если шаг выдан
#   (коды 3, 10–14 ниже — исход цепочки, лишь если шага не было);
#   3 — отправка идёт (status 3): шаг НЕ выдан, повтор after — следующим шагом;
#   10 — отправка вышла не 0 (код и хвост журнала названы), 11 — отправка «не выполнилось»
#        (status 2), 12 — голова на origin не та (`PREMISE-FALSE`), 13 — origin не судим
#        (`VOID`), 14 — внешняя отправка не судима как идущая (status 4): во всех — шаг НЕ выдан; 74/75 — слот не выдан за 300 с, шаг не выдан;
#   64 — вызов неверен; 69 — detach.sh не запустил.
# Коды шага 3, 10–13 читаются как исход шага лишь по строке «шаг выдан» журнала.
#
# ЧЕГО НЕ ДЕЛАЕТ: не ждёт исхода в вызове агента (start возвращает «идёт»), не повторяет
# отправку и шаг, не обходит хук. Держит scripts/push-then-inject.sh.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
say() { printf 'push-then: %s\n' "$*"; }
usage() { say "форма: push-then.sh start <каталог шагов> <копия> <ветка> -- <шаг…> | after <.rc отправки> <владелец/репо> <ветка> <sha40> -- <шаг…>" >&2; exit 64; }

# gate <код статуса отправки> <репо> <ветка> <sha> <шаг…> — выдать шаг по факту.
gate() {
    local st="$1" repo="$2" br="$3" sha="$4" pf rc; shift 4
    case "$st" in
        0) ;;
        3) say "отправка идёт — шаг НЕ выдан; повтор after — следующим шагом"; return 3 ;;
        2) say "отправка не выполнилась (.rc нет) — шаг НЕ выдан"; return 11 ;;
        4) say "отправка не судима как идущая (внешний шаг без .pid, .rc нет) — шаг НЕ выдан"; return 14 ;;
        *) say "отправка вышла не 0 — шаг НЕ выдан"; return 10 ;;
    esac
    pf="$(mktemp)"; printf 'pushed %s %s %s\n' "$repo" "$br" "$sha" > "$pf"
    bash "$HERE/lane-precheck.sh" --premise "$pf" > "$pf.out" 2>&1; rc=$?
    sed 's/^/  | /' "$pf.out"; rm -f "$pf" "$pf.out"
    case "$rc" in
        0) ;;
        1) say "голова $br на origin не $sha — шаг НЕ выдан"; return 12 ;;
        *) say "предусловие pushed не судимо (код $rc) — шаг НЕ выдан"; return 13 ;;
    esac
    say "шаг выдан: $*"
    PUSHED_SHA="$sha" "$@"; rc=$?
    say "шаг вышел кодом $rc"
    return "$rc"
}

slug_of() {  # <копия> — владелец/репо origin
    local u; u="$(git -C "$1" config --get remote.origin.url 2>/dev/null)" || return 1   # как записан, без insteadOf
    u="${u%.git}"; u="${u#*github.com[:/]}"
    [[ "$u" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || return 1
    printf '%s\n' "$u"
}

case "${1:-}" in
start)
    [ $# -ge 6 ] && [ "$5" = -- ] || usage
    dir="$2" copy="$3" br="$4"; shift 5
    top="$(git -C "$copy" rev-parse --show-toplevel 2>/dev/null)" || { say "копии «$copy» нет" >&2; exit 64; }
    [[ "$br" =~ ^[A-Za-z0-9._/-]+$ ]] || { say "ветка «$br» — не имя ветки" >&2; exit 64; }
    repo="$(slug_of "$top")" || { say "origin копии $top — не github.com/<владелец>/<репо>" >&2; exit 64; }
    [ -z "$(git -C "$top" status --porcelain 2>/dev/null)" ] || { say "копия $top грязная — отправка из чистой копии" >&2; exit 64; }
    if ! git -C "$top" symbolic-ref -q HEAD > /dev/null 2>&1 && ! [[ "${KACHO_TASK:-}" =~ ^[1-9][0-9]*$ ]]; then
        say "голова копии отсоединена — номер задачи слот берёт лишь из KACHO_TASK=<N> окружения" >&2; exit 64
    fi
    sha="$(git -C "$top" rev-parse HEAD)"
    bash "$HERE/detach.sh" start "$dir" -- bash "$HERE/push-then.sh" _run "$top" "$repo" "$br" "$sha" -- "$@"
    rc=$?; [ "$rc" = 0 ] || [ "$rc" = 64 ] || exit 69
    exit "$rc" ;;
_run)
    # Внутренняя часть start — под detach.sh; агент её не зовёт.
    [ $# -ge 7 ] && [ "$6" = -- ] || usage
    top="$2" repo="$3" br="$4" sha="$5"; shift 6
    cd "$top" || exit 64
    [ "$(git rev-parse HEAD)" = "$sha" ] || { say "голова копии сдвинулась после start — не отправляю"; exit 64; }
    say "отправка $repo $br @$sha"
    bash "$HERE/heavy-slot.sh" --wait 300 ci-local -- git push origin "HEAD:refs/heads/$br"
    prc=$?; say "отправка вышла кодом $prc"
    case "$prc" in 74 | 75) say "слот не выдан — шаг НЕ выдан"; exit "$prc" ;; 0) st=0 ;; *) st=1 ;; esac
    gate "$st" "$repo" "$br" "$sha" "$@"; exit $? ;;
after)
    [ $# -ge 7 ] && [ "$6" = -- ] || usage
    rcf="$2" repo="$3" br="$4" sha="$5"; shift 6
    [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] && [[ "$br" =~ ^[A-Za-z0-9._/-]+$ ]] && [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || usage
    bash "$HERE/detach.sh" status "$rcf" | sed 's/^/  | /'
    gate "${PIPESTATUS[0]}" "$repo" "$br" "$sha" "$@"; exit $? ;;
*) usage ;;
esac
