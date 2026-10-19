#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# detach.sh — долгий шаг отсоединённо, исход — отдельным коротким шагом (ws#1225).
#
# ЗАЧЕМ. Норма `CLAUDE.md` «Не жди»: ни один вызов не держит ожидание дольше 10 минут.
# Уроки «ожидание-в-вызове» 18–19.10 (6 случаев): исполнитель дежурил паузами sleep в
# вызовах — no-wait-guard их отказывает, — задание называло предел паузы (270 с) и предел
# вызова (60 с) разными числами, `.rc` в пределах 10 мин был недостижим, полный хук отправки
# шёл дольше двух пауз. Форма отсоединения жила строкой в тексте стража и заданий, и каждый
# исполнитель собирал её заново. Здесь она — одна команда: пауза не нужна вовсе.
#
# ФОРМА
#   detach.sh start <каталог> [--deadline <с>] -- <команда> [доводы…]
#       — setsid + env --default-signal=PIPE, stdin /dev/null; файлы <каталог>/<метка>.log,
#         .rc (код команды, пишется атомарно по её выходу) и .pid; метка уникальна: время UTC,
#         pid вызова, 8 знаков sha256 команды; .rc снимается до старта. Печатает строку
#         «идёт: pid N; журнал …; rc …; срок <UTC>» и строку дочитки исхода.
#         Код 0 — запущено; 64 — вызов неверен (в том числе строка `sh|bash -c`, чья последняя
#         команда echo или printf: в .rc лёг бы её код, ws#1242; каталог внутри рабочего дерева
#         git, где файлы шага не игнорируются: они делают копию грязной, kacho#3251);
#         69 — не запущено (нет setsid, каталог не заводится, pid не записан за 5 с).
#   detach.sh status <файл .rc | .log | .pid | <журнал>.log.rc | путь без расширения>
#       — 0: команда вышла кодом 0; 1: вышла не нулём (код назван); 3: идёт; 2: не
#         выполнилось — процесса нет, а .rc нет, либо файлов шага нет; 4: внешний шаг (без
#         .pid) без .rc, журнал не держит ни один процесс — не судим как идущий. По выходу команды —
#         хвост журнала (5 строк). Живость — pid из .pid И метка DETACH_TAG в его окружении:
#         чужой процесс на переиспользованном pid «идущим» не считается.
# Срок (--deadline, с; по умолчанию 3600) — KACHO_DETACHED_UNTIL окружения шага: перепись
# застоя (scripts/stall-census.sh, ws#1154) сироту в сроке застоем не судит.
#
# ЧЕГО НЕ ДЕЛАЕТ: не ждёт и не опрашивает — status читает один раз. Тяжёлое (docker,
# линтер, -race, стенд) по-прежнему идёт слотом: `detach.sh start <каталог> -- $WS/scripts/
# heavy-slot.sh <класс> -- …`; очередь слота дольше 300 с — `heavy-slot.sh --enqueue`.
# Держит scripts/detach-inject.sh (исходы, уникальность, переиспользованный pid, страж).
set -uo pipefail

say() { printf 'detach: %s\n' "$*" >&2; }
usage() { say "форма: detach.sh start <каталог> [--deadline <с>] -- <команда…> | detach.sh status <файл шага>"; exit 64; }

# alive <pid> <метка> — процесс жив и несёт метку шага в окружении.
alive() {
    local e; local -a env=()
    [[ "$1" =~ ^[0-9]+$ ]] || return 1
    { mapfile -d '' -t env < "/proc/$1/environ"; } 2>/dev/null || return 1
    for e in "${env[@]}"; do [ "$e" = "DETACH_TAG=$2" ] && return 0; done
    return 1
}

case "${1:-}" in
start)
    shift
    [ $# -ge 1 ] || usage
    dir="$1"; shift
    deadline=3600
    if [ "${1:-}" = --deadline ]; then
        [[ "${2:-}" =~ ^[1-9][0-9]*$ ]] || { say "--deadline «${2:-}» — не секунды"; exit 64; }
        deadline="$2"; shift 2
    fi
    [ "${1:-}" = -- ] || usage
    shift
    [ $# -ge 1 ] || { say "после «--» команды нет"; exit 64; }
    # Код шага — код ПОСЛЕДНЕЙ команды: строка оболочки (`sh|bash -c '…'`), кончающаяся echo или
    # printf, пишет в .rc код echo — 0 при любом исходе (ws#1242: «…; echo rc=$?» дважды за полосу).
    # Судится лишь САМА команда шага (sh|bash … -c '<строка>'), не доводы внутри неё: шаг
    # цепочки (push-then.sh … -- sh -c 'printf …') — код цепочки, а не строки.
    prev=""; case "${1##*/}" in sh | bash | dash) ;; *) prev=stop ;; esac
    for a in "$@"; do
        [ "$prev" = stop ] && break
        [ "$prev" != -c ] && [ "$prev" != "" ] && [ "${prev:0:1}" != - ] && [ "$prev" != "$1" ] && break
        if [ "$prev" = -c ]; then
            s="${a%"${a##*[![:space:];]}"}"; last="${s##*[;&|$'
']}"; last="${last#"${last%%[![:space:]({]*}"}"
            if [[ "$last" =~ ^(echo|printf)([[:space:]]|$) ]]; then
                say "строка оболочки кончается «${last:0:60}» — в .rc лёг бы код echo, а не прогона. Код сохрани и верни: «…; rc=\$?; echo …; exit \$rc»"
                exit 64
            fi
        fi
        prev="$a"
    done
    command -v setsid > /dev/null 2>&1 || { say "нет setsid — не запущено"; exit 69; }
    mkdir -p "$dir" 2>/dev/null || { say "каталог «$dir» не заводится — не запущено"; exit 69; }
    dir="$(cd "$dir" && pwd -P)"
    ign=1
    for x in x.log x.rc x.pid x.rc.tmp; do git -C "$dir" check-ignore -q "$dir/$x" 2>/dev/null || ign=0; done
    if [ "$(git -C "$dir" rev-parse --is-inside-work-tree 2>/dev/null)" = true ] && [ "$ign" = 0 ]; then
        say "каталог «$dir» — внутри рабочего дерева git, и файлы шага там не игнорируются: копия стала бы грязной (kacho#3251). Каталог шагов — вне копии, например \$WS/tmp/<полоса>/"
        exit 64
    fi
    tag="$(date -u +%Y%m%dT%H%M%SZ)-$$-$(printf '%s\0' "$@" | sha256sum | cut -c1-8)"
    base="$dir/$tag"
    rm -f "$base.rc" "$base.pid"
    until_ts=$(( $(date +%s) + deadline ))
    # Внутренняя оболочка пишет СВОЙ pid (setsid без форка сохраняет pid, с форком — нет;
    # $! вызова тогда был бы pid уже вышедшего setsid), затем код команды — атомарно.
    setsid env --default-signal=PIPE DETACH_TAG="$tag" KACHO_DETACHED_UNTIL="$until_ts" \
        bash -c 'echo $$ > "$0.pid"; "$@"; rc=$?; printf "%s\n" "$rc" > "$0.rc.tmp" && mv -f "$0.rc.tmp" "$0.rc"' "$base" "$@" \
        >> "$base.log" 2>&1 < /dev/null &
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        [ -s "$base.pid" ] && break
        sleep 0.25
    done
    [ -s "$base.pid" ] || { say "pid шага не записан за 5 с — не запущено либо вышел сразу; журнал $base.log"; exit 69; }
    printf 'идёт: pid %s; журнал %s; rc %s; срок %s\n' "$(cat "$base.pid")" "$base.log" "$base.rc" \
        "$(date -u -d "@$until_ts" +%Y-%m-%dT%H:%M:%SZ)"
    printf 'исход — одним шагом: bash %s status %s\n' "$(readlink -f -- "${BASH_SOURCE[0]}")" "$base.rc"
    exit 0 ;;
status)
    [ $# -eq 2 ] || usage
    base="${2%.rc}"; base="${base%.log}"; base="${base%.pid}"
    tag="${base##*/}"; rcf="$base.rc"; logf="$base.log"
    # Форма вызывающих «<журнал>.log.rc» (код рядом с журналом, ws#1242: chain-3296-3292-r2.sh) —
    # .rc берётся тем именем, которым назван; «<журнал>.log» при таком .rc — тоже.
    case "$2" in
        *.log.rc) rcf="$2"; logf="${2%.rc}" ;;
        *.log) [ -f "$2.rc" ] && [ ! -f "$rcf" ] && { rcf="$2.rc"; logf="$2"; } ;;
    esac
    if [ -f "$rcf" ]; then
        code="$(head -n 1 "$rcf")"
        [[ "$code" =~ ^[0-9]+$ ]] || { echo "не выполнилось: .rc «$code» не код — журнал $logf"; exit 2; }
        echo "исход: код $code; журнал $logf"
        tail -n 5 "$logf" 2>/dev/null | sed 's/^/  | /'
        [ "$code" -eq 0 ] && exit 0
        exit 1
    fi
    pid="$(cat "$base.pid" 2>/dev/null)"
    if alive "$pid" "$tag"; then
        echo "идёт: pid $pid; журнал $logf"
        exit 3
    fi
    # Внешний шаг (не detach.sh start: ни .pid, ни метки DETACH_TAG) — живость по журналу:
    # процесс, держащий его открытым (/proc/*/fd), — «идёт»; не держит никто — «не судим как
    # идущий» (4): цепочка, дописывающая журнал наездами, его не держит (ws#1242, check-verifier).
    if [ ! -e "$base.pid" ] && [ -e "$logf" ]; then
        lp="$(readlink -f -- "$logf")"; lg="$(printf '%s' "$lp" | sed 's/[][*?\\]/\\&/g')"
        # Один find по всем fd (не readlink на каждый: тысячи вызовов — минуты).
        holder="$(find /proc/[0-9]*/fd -maxdepth 1 -lname "$lg" -print -quit 2>/dev/null)"
        holder="${holder#/proc/}"; holder="${holder%%/*}"
        if [ -n "$holder" ]; then echo "идёт: внешний шаг без .pid — журнал держит pid $holder; журнал $logf"; exit 3; fi
        echo "не судим как идущий: внешний шаг без .pid и метки, журнал $logf не держит ни один процесс — .rc нет; исход — status позже либо по журналу"
        exit 4
    fi
    if [ -e "$base.pid" ] || [ -e "$logf" ]; then
        echo "не выполнилось: процесса ${pid:-—} нет, а .rc нет — шаг оборван; журнал $logf"
    else
        echo "не выполнилось: файлов шага $rcf, $logf, $base.pid нет"
    fi
    exit 2 ;;
*) usage ;;
esac
