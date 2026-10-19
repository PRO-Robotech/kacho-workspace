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
#       — служба systemd --user `kacho-detach-<метка>` ВНЕ scope сессии (переживает её
#         перезапуск; scripts/detach-launch.sh), при недоступном systemd --user — setsid в
#         scope сессии с громким предупреждением; env --default-signal=PIPE, stdin /dev/null;
#         файлы <каталог>/<метка>.log, .rc (код команды, пишется атомарно по её выходу), .pid
#         .unit (имя службы) и .exit (исход службы — пишет она сам; на пути setsid их нет); метка
#         уникальна: время UTC, pid вызова, 8 знаков sha256 команды; .rc снимается до старта.
#         Печатает строку «идёт: pid N; журнал …; rc …; срок <UTC>; вид служба <юнит> | setsid
#         (не переживёт перезапуск сессии)» и строку дочитки исхода.
#         Код 0 — запущено; 64 — вызов неверен (в том числе каталог внутри рабочего дерева
#         git, где файлы шага не игнорируются: они делают копию грязной, kacho#3251);
#         69 — не запущено (нет ни службы, ни setsid; каталог не заводится; pid не записан за 5 с).
#   detach.sh status <файл .rc | .log | .pid | путь без расширения>
#       — 0: команда вышла кодом 0; 1: вышла не нулём (код назван); 3: идёт; 2: не
#         выполнилось — процесса нет, а .rc нет, либо файлов шага нет. По выходу команды —
#         хвост журнала (5 строк). Живость — pid из .pid И метка DETACH_TAG в его окружении:
#         чужой процесс на переиспользованном pid «идущим» не считается; вид шага (служба
#         или setsid) на живость не влияет. Оборванный шаг (2) назван причиной: перезагрузка
#         машины (.pid старше загрузки); служба остановлена менеджером служб либо процесс
#         убит сигналом — разными фразами (запись .exit, нет её — журнал юнита); процесса нет.
# Срок (--deadline, с; по умолчанию 3600) — KACHO_DETACHED_UNTIL окружения шага: перепись
# застоя (scripts/stall-census.sh, ws#1154) сироту в сроке застоем не судит.
#
# ЧЕГО НЕ ДЕЛАЕТ: не ждёт и не опрашивает — status читает один раз. Тяжёлое (docker,
# линтер, -race, стенд) по-прежнему идёт слотом: `detach.sh start <каталог> -- $WS/scripts/
# heavy-slot.sh <класс> -- …`; очередь слота дольше 300 с — `heavy-slot.sh --enqueue`.
# Держит scripts/detach-inject.sh (исходы, уникальность, переиспользованный pid, страж,
# служба переживает снятие scope вызова — близнец setsid убит, перезагрузка названа).
set -uo pipefail
# shellcheck source=scripts/detach-launch.sh
. "$(dirname "$(readlink -f -- "${BASH_SOURCE[0]}")")/detach-launch.sh" || { printf 'detach: нет detach-launch.sh рядом\n' >&2; exit 69; }

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
    mkdir -p "$dir" 2>/dev/null || { say "каталог «$dir» не заводится — не запущено"; exit 69; }
    dir="$(cd "$dir" && pwd -P)"
    ign=1
    for x in x.log x.rc x.pid x.rc.tmp x.unit x.exit; do git -C "$dir" check-ignore -q "$dir/$x" 2>/dev/null || ign=0; done
    if [ "$(git -C "$dir" rev-parse --is-inside-work-tree 2>/dev/null)" = true ] && [ "$ign" = 0 ]; then
        say "каталог «$dir» — внутри рабочего дерева git, и файлы шага там не игнорируются: копия стала бы грязной (kacho#3251). Каталог шагов — вне копии, например \$WS/tmp/<полоса>/"
        exit 64
    fi
    tag="$(date -u +%Y%m%dT%H%M%SZ)-$$-$(printf '%s\0' "$@" | sha256sum | cut -c1-8)"
    base="$dir/$tag"
    rm -f "$base.rc" "$base.pid" "$base.unit" "$base.exit"
    until_ts=$(( $(date +%s) + deadline ))
    unit="kacho-detach-$tag"
    # Внутренняя оболочка пишет СВОЙ pid (обёртка и env исполняются через exec — pid тот же;
    # $! вызова был бы pid обёртки setsid-пути), затем код команды — атомарно.
    # shellcheck disable=SC2016
    detach_launch "$unit" "$base.log" -- env --default-signal=PIPE DETACH_TAG="$tag" KACHO_DETACHED_UNTIL="$until_ts" \
        bash -c 'echo $$ > "$0.pid"; "$@"; rc=$?; printf "%s\n" "$rc" > "$0.rc.tmp" && mv -f "$0.rc.tmp" "$0.rc"' "$base" "$@" \
        || { say "${DETACH_WARN:-не запущено}"; exit 69; }
    if [ "$DETACH_MODE" = unit ]; then printf '%s\n' "$unit" > "$base.unit"; kind="служба $unit"
    else kind="setsid (не переживёт перезапуск сессии)"; fi
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        [ -s "$base.pid" ] && break
        sleep 0.25
    done
    [ -s "$base.pid" ] || { say "pid шага не записан за 5 с — не запущено либо вышел сразу; журнал $base.log"; exit 69; }
    printf 'идёт: pid %s; журнал %s; rc %s; срок %s; вид %s\n' "$(cat "$base.pid")" "$base.log" "$base.rc" \
        "$(date -u -d "@$until_ts" +%Y-%m-%dT%H:%M:%SZ)" "$kind"
    printf 'исход — одним шагом: bash %s status %s\n' "$(readlink -f -- "${BASH_SOURCE[0]}")" "$base.rc"
    exit 0 ;;
status)
    [ $# -eq 2 ] || usage
    base="${2%.rc}"; base="${base%.log}"; base="${base%.pid}"
    tag="${base##*/}"
    if [ -f "$base.rc" ]; then
        code="$(head -n 1 "$base.rc")"
        [[ "$code" =~ ^[0-9]+$ ]] || { echo "не выполнилось: .rc «$code» не код — журнал $base.log"; exit 2; }
        echo "исход: код $code; журнал $base.log"
        tail -n 5 "$base.log" 2>/dev/null | sed 's/^/  | /'
        [ "$code" -eq 0 ] && exit 0
        exit 1
    fi
    pid="$(cat "$base.pid" 2>/dev/null)"
    if alive "$pid" "$tag"; then
        u="$(cat "$base.unit" 2>/dev/null)"
        echo "идёт: pid $pid; журнал $base.log${u:+; служба $u}"
        exit 3
    fi
    if [ -e "$base.pid" ] || [ -e "$base.log" ]; then
        echo "не выполнилось: процесса ${pid:-—} нет, а .rc нет — шаг оборван: $(detach_gone_reason "$base.pid" "$base.unit"); журнал $base.log"
    else
        echo "не выполнилось: файлов шага $base.{rc,log,pid} нет"
    fi
    exit 2 ;;
*) usage ;;
esac
