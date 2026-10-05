#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# wave-errors.sh — счётчик ошибок оркестровки волны: каждый возврат НЕ из-за
# кода — строкой с классом и потерянными часами; доля = часы таких возвратов /
# часы волны.
#
# ОСНОВАНИЕ. Цель владельца 2026-10-06: ошибок агентами меньше 5 %, а не 30–40.
# Замер того же дня (4811 вызовов, 494 журнала): классы а–д — 296 вызовов, 6,2 %;
# с возвратами ревью по существу — 716, 14,9 %. Возврат ревью по существу (класс
# «е») — работа ревью, а не ошибка оркестровки: сюда он не пишется, и счётчик
# такую строку отвергает.
#
# ФАЙЛ — `<WS>/tmp/wave-<N>/errors.md` (каталог — `WAVE_ERRORS_DIR`, иначе
# выводится `scripts/lib/ws-home.sh`: worktree и клон под `tmp/` пишут в одну
# волну): таблица markdown, строка на возврат. Пишет её исполнитель механики (лёгкая модель) по возврату шага.
#
# usage:
#   wave-errors.sh add  <волна> <класс> <часы> <полоса> <шаг> <заметка…>
#   wave-errors.sh rate <волна> <часы волны>
#
# КЛАССЫ — закрытый словарь (по замеру 2026-10-06):
#   false-fail          ложный провал или повтор на той же голове («идёт»,
#                       «уже сделано», «нечего отправлять» — не провал);
#   incomplete-task     неполное задание (нет сдачи, базы, разрешения);
#   wrong-premise       неверная посылка;
#   truncation          обрезка вывода или окна;
#   executor-mechanics  механика исполнителя: незакоммичено, не отправлено,
#                       преждевременный Closes, ложное тело PR, старый отпечаток;
#   new:<имя>           новый класс — правка шаблона или предпроверки В ТОТ ЖЕ
#                       ДЕНЬ; `rate` перечисляет такие строки отдельно.
# Отвергаются: `review` и любой класс вне словаря.
#
# Коды: add — 0 записано, 1 класс или часы вне формы, 2 файл не записать;
#       rate — 0 доля ≤ 5 %, 1 доля > 5 % либо строка таблицы вне формы,
#       2 вердикта нет (файла нет — счётчик не вёлся; часы волны не > 0).
# Держит `scripts/wave-errors-inject.sh`.
set -uo pipefail

LIMIT_PCT=5

usage() {
    echo "usage: wave-errors.sh add <волна> <класс> <часы> <полоса> <шаг> <заметка…> | rate <волна> <часы волны>" >&2
    exit 2
}

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/ws-home.sh
. "$HERE/lib/ws-home.sh"
dir_of() {
    if [ -n "${WAVE_ERRORS_DIR:-}" ]; then echo "$WAVE_ERRORS_DIR"; return; fi
    local ws
    ws="$(ws_home "$HERE")" || return 1
    echo "$ws/tmp/wave-$1"
}
num_re='^[0-9]+([.][0-9]+)?$'
class_ok() {
    case "$1" in
        false-fail | incomplete-task | wrong-premise | truncation | executor-mechanics) return 0 ;;
        new:?*) [[ "$1" =~ ^new:[a-z0-9][a-z0-9-]*$ ]] ;;
        *) return 1 ;;
    esac
}

[ $# -ge 1 ] || usage
cmd="$1"; shift
case "$cmd" in
    add)
        [ $# -ge 6 ] || usage
        wave="$1" cls="$2" hours="$3" lane="$4" step="$5"; shift 5
        note="$*"
        [[ "$wave" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "wave-errors: ОТКАЗ — имя волны «$wave» вне формы" >&2; exit 1; }
        if [ "$cls" = review ]; then
            echo "wave-errors: ОТКАЗ — возврат ревью по существу (класс «е») — не ошибка оркестровки; сюда не пишется" >&2
            exit 1
        fi
        class_ok "$cls" || { echo "wave-errors: ОТКАЗ — класс «$cls» вне словаря (false-fail, incomplete-task, wrong-premise, truncation, executor-mechanics, new:<имя>)" >&2; exit 1; }
        [[ "$hours" =~ $num_re ]] || { echo "wave-errors: ОТКАЗ — часы «$hours» не число" >&2; exit 1; }
        d="$(dir_of "$wave")" || { echo "wave-errors: каталог волны не выведен" >&2; exit 2; }
        f="$d/errors.md"
        mkdir -p "$d" || exit 2
        if [ ! -s "$f" ]; then
            printf '# Ошибки оркестровки волны %s\n\n| когда (UTC) | полоса | шаг | класс | часы | заметка |\n|---|---|---|---|---|---|\n' "$wave" > "$f" || exit 2
        fi
        printf '| %s | %s | %s | %s | %s | %s |\n' "$(date -u +%Y-%m-%dT%H:%MZ)" "${lane//|//}" "${step//|//}" "$cls" "$hours" "${note//|//}" >> "$f" || exit 2
        echo "wave-errors: записано в $f — $cls, $hours ч"
        ;;
    rate)
        [ $# -eq 2 ] || usage
        wave="$1" wh="$2"
        if ! [[ "$wh" =~ $num_re ]] || ! LC_ALL=C awk -v h="$wh" 'BEGIN { exit !(h > 0) }'; then
            echo "wave-errors: VOID — часы волны «$wh» не > 0: долю считать не от чего" >&2
            exit 2
        fi
        d="$(dir_of "$wave")" || { echo "wave-errors: каталог волны не выведен" >&2; exit 2; }
        f="$d/errors.md"
        [ -f "$f" ] || { echo "wave-errors: VOID — $f нет: счётчик волны не вёлся (это не «ошибок ноль»)" >&2; exit 2; }
        # Числа — под LC_ALL=C: в русской локали awk читает «0.25» как 0, и доля
        # выходила 0 % при любых часах (поймано wave-errors-inject.sh).
        LC_ALL=C awk -F'|' -v wh="$wh" -v lim="$LIMIT_PCT" '
            function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
            /^\|/ {
                if ($0 ~ /^\|[- |]+\|$/ || $0 ~ /когда \(UTC\)/) next
                rows++
                c = trim($5); h = trim($6)
                okc = (c ~ /^(false-fail|incomplete-task|wrong-premise|truncation|executor-mechanics)$/ || c ~ /^new:[a-z0-9][a-z0-9-]*$/)
                if (NF != 8 || !okc || h !~ /^[0-9]+([.][0-9]+)?$/) { bad++; badl = badl "\n  строка " NR ": " $0; next }
                sum += h; by[c] += h; cnt[c]++
                if (c ~ /^new:/) newc = newc "\n  NEW-CLASS " c " (" trim($3) " · " trim($4) ")"
            }
            END {
                pct = 100 * sum / wh
                printf "wave-errors: строк %d, вне формы %d; часов ошибок %.2f из %.2f — доля %.1f %% (предел %d %%)\n", rows, bad, sum, wh, pct, lim
                for (k in by) printf "  класс %s: строк %d, часов %.2f\n", k, cnt[k], by[k]
                if (newc != "") printf "новые классы — правка шаблона или предпроверки в тот же день:%s\n", newc
                if (bad) { printf "ОТКАЗ — строки вне формы:%s\n", badl; exit 1 }
                if (pct > lim) { printf "КРАСНОЕ — доля %.1f %% выше %d %%\n", pct, lim; exit 1 }
                exit 0
            }' "$f"
        ;;
    *) usage ;;
esac
