#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# session-memcap.sh — потолок памяти сессии держит ядро: MemoryMax на её scope.
#
# ПРЕДМЕТ. Решение владельца 2026-09-24: «контроль за оперативной памятью не должна
# переваливать за 45гб». Повод: systemd-oomd снял scope терминала сессии целиком на
# 41,7 ГБ (10:35:19Z; давление user@1000.service 76,75 % > 50 % дольше 20 с). Слот
# (heavy-slot.sh) держит то, что идёт через него, страж heavy-guard — напоминание;
# всё прочее, что запускает сессия, живёт в её scope, и потолок ему ставит ядро.
#
# ФОРМА
#   session-memcap.sh                   потолок и omit на scope, где исполняется (/proc/self/cgroup)
#   session-memcap.sh --show            посчитать и напечатать, ничего не меняя
#   session-memcap.sh --hook            SessionStart: поставить; отказ — строкой диспетчеру
#   session-memcap.sh --launch -- <команда…>   запустить команду (claude) в новом scope,
#                                       где потолок ставится: OOMPolicy=continue
#
# ФОРМУЛА (МиБ): потолок = max(8192, 46080 − вне − docker), где
#   вне    = max(0, (MemTotal − MemAvailable) − anon scope) — занятое машиной вне scope;
#   docker = бюджет класса docker слота (`heavy-slot.sh --budget docker`, 4096):
#            контейнеры живут в system.slice, мимо scope, и их держит --memory слота;
#   8192   — нижняя граница: быстрое своих пакетов (go test -race services/vpc — 3,5 ГиБ,
#            основание класса go-race слота) плюс процесс сессии; ниже работать нельзя.
# Потолок — снимок на старте: сосед, поднятый позже, видит занятое этой сессией, а не
# её потолок. Сумму сверх 45 ГиБ тогда держат вход и сторож слота.
#
# ОТКАЗ ПРИМЕНЕНИЯ — код 1, потолок не ставится, причина печатается; метка omit (ниже)
# ставится и при отказе:
#   · anon scope + 4096 ≥ потолка — ядро сразу снимало бы процессы сессии;
#   · OOMPolicy scope ≠ continue. Замер 2026-09-24 (одноразовые scope, 64 МиБ): при
#     OOMPolicy=stop первое OOM-убийство под MemoryMax останавливает ВЕСЬ scope
#     («Failed with result 'oom-kill'») — так же и при записи memory.max мимо systemd;
#     при continue убит один процесс за 0,0 с, давление 68 мкс, прочие живы. Терминал
#     (vte-spawn-*.scope) заводится со stop, и на живом scope OOMPolicy не меняется
#     («Cannot set property OOMPolicy»): потолок получает сессия, запущенная --launch.
#
# ЧТО СТАВИТСЯ И ПОЧЕМУ (systemctl --user set-property --runtime, сверка по cgroup):
#   · MemoryMax — потолок; MemoryHigh=infinity: без троттлинга над high нет долгой
#     остановки, на которую реагирует oomd;
#   · MemorySwapMax=0: у потолка ядро снимает процесс, а не гоняет swap. Замер: 64 МиБ
#     со swap, 512 МиБ в цикле — 14,8 с пробуксовки вместо OOM за 0,0 с без swap;
#   · ManagedOOMMemoryPressure=auto: scope сам не цель слежения oomd.
#
# МЕТКА OMIT (решение диспетчера 2026-09-24): xattr user.oomd_omit=1 на cgroup своего
# scope — прямой записью, со сверкой чтением; ставится ВСЕГДА, и при отказе потолка:
# кандидатом на снятие oomd scope с omit не выбирает вовсе. Повод — терминал 41,7 ГБ был
# листом под user@1000.service, за которым oomd тогда следил по давлению (kill, 50 %, 20 с).
# Замер 2026-09-24: `set-property ManagedOOMPreference=omit` живого scope возвращает 0,
# а метки не пишет, — поэтому свойство не трогается, а читается метка; запись без root
# работает, oomd её соблюдает (session-memcap-inject.sh: срез kill 1 %/2 с — scope с
# omit дожил, соседа снял oomd по журналу; близнец — omit на соседе, снят давящий).
# Следствие: сессия без потолка (терминал со stop) под omit oomd не снимается, под
# давлением он снимет соседа; её саму держат лишь слот и OOM ядра машины.
# Надзор oomd по давлению за user@UID.service объявлен, но в oomctl его бывает не видно
# (2026-09-24 — не было; вероятно, снят перезагрузками менеджера пользователя —
# гипотеза); надзора по подкачке нет: ManagedOOMSwap=auto на всех срезах.
#
# ГРАНИЦА: мимо scope — слоты (свой scope и предел), контейнеры docker (--memory
# слота; узлы kind — `docker update --memory` при подъёме), `systemd-run --user`,
# процессы других терминалов: ни потолка, ни метки omit у них нет — метку получает
# только scope сессии, запустившей хук. Scope не под user@UID.service (ssh:
# session-N.scope) — 69: менеджер пользователя его не правит.
#
# РУЧКИ SESSION_MEMCAP_* — только режиму проб: синтетический SESSION_MEMCAP_MEMINFO и
# одноразовый scope session-memcap-probe-*; живую сессию режим проб не трогает. Над
# настоящей памятью ручка — 64.
#
# КОДЫ: 0 — потолок и omit в силе (сверены по cgroup); 1 — отказ потолка, omit в силе;
# 64 — вызов неверен; 69 — механизм недоступен, в том числе метка omit не сверилась
# чтением. --hook всегда 0: сессию он не роняет, отказ —
# additionalContext «SESSION-MEMCAP: …». Журнал — journal.log каталога слотов.
{
set -uo pipefail

say() { printf 'session-memcap: %s\n' "$*" >&2; }
mib() { awk -v m="$1" 'BEGIN { if (m < 1024) printf "%d МиБ", m; else printf "%.1f ГиБ", m / 1024 }'; }

SELF="$(readlink -f -- "${BASH_SOURCE[0]}")"
HERE="$(dirname -- "$SELF")"
CAP=46080; FLOOR=8192; MARGIN=4096; DOCKER=""
MEMINFO="${SESSION_MEMCAP_MEMINFO:-/proc/meminfo}"
KNOBS="SESSION_MEMCAP_CAP_MIB SESSION_MEMCAP_FLOOR_MIB SESSION_MEMCAP_MARGIN_MIB SESSION_MEMCAP_DOCKER_MIB"

usage() { sed -n '13,18p' "$SELF" >&2; exit 64; }

MODE=apply
case "${1:-}" in
    '') ;;
    --show) MODE=show ;;
    --hook) MODE=hook ;;
    --launch)
        MODE=launch; shift
        [ "${1:-}" = -- ] && [ "$#" -ge 2 ] || usage
        shift ;;
    *) usage ;;
esac

if [ "$MODE" = hook ]; then
    out="$(bash "$SELF" 2>&1)"; rc=$?
    [ "$rc" -eq 0 ] && exit 0
    msg="SESSION-MEMCAP: потолок памяти сессии НЕ поставлен (код $rc) — $(printf '%s' "$out" | sed 's/^session-memcap: //' | tr '\n' ' ')Тяжёлое — только слотом (scripts/heavy-slot.sh); ОТКАЗ по OOMPolicy снимается перезапуском сессии: scripts/session-memcap.sh --launch -- claude; иное — tooling-maintainer."
    if command -v python3 >/dev/null; then
        python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": sys.argv[1]}}, ensure_ascii=False))' "$msg"
    else
        printf '%s\n' "$msg"
    fi
    exit 0
fi

if [ "$MEMINFO" = /proc/meminfo ]; then
    for v in $KNOBS; do
        [ -n "${!v+x}" ] && { say "над настоящей памятью ручка не принимается: $v=${!v} — потолок 45 ГиБ, граница 8 ГиБ, запас 4 ГиБ и бюджет docker не переопределяются (решение владельца 2026-09-24); ручки — только пробам над синтетическим SESSION_MEMCAP_MEMINFO"; exit 64; }
    done
else
    for v in $KNOBS; do
        [ -z "${!v+x}" ] || [[ "${!v}" =~ ^[0-9]+$ ]] || { say "$v=«${!v}» — не число"; exit 64; }
    done
    CAP="${SESSION_MEMCAP_CAP_MIB:-$CAP}"; FLOOR="${SESSION_MEMCAP_FLOOR_MIB:-$FLOOR}"
    MARGIN="${SESSION_MEMCAP_MARGIN_MIB:-$MARGIN}"; DOCKER="${SESSION_MEMCAP_DOCKER_MIB:-}"
fi
[ -n "$DOCKER" ] || DOCKER="$(bash "$HERE/heavy-slot.sh" --budget docker 2>/dev/null)"
[[ "$DOCKER" =~ ^[0-9]+$ ]] || { say "бюджет класса docker не прочитан из $HERE/heavy-slot.sh --budget docker (не выполнилось)"; exit 69; }

USED="$(awk '/^MemTotal:/ { t = $2 } /^MemAvailable:/ { a = $2; h = 1 }
             END { if (t > 0 && h) printf "%d\n", (t - a) / 1024 }' "$MEMINFO" 2>/dev/null)"
[ -n "$USED" ] || { say "не прочитать MemTotal/MemAvailable из $MEMINFO (не выполнилось)"; exit 69; }
command -v systemctl >/dev/null || { say "нет systemctl — потолок ставить нечем (не выполнилось)"; exit 69; }

# formula <anon МиБ> — OUTSIDE, RAW, LIMIT, FLOORED.
formula() {
    OUTSIDE=$(( USED - $1 )); [ "$OUTSIDE" -gt 0 ] || OUTSIDE=0
    RAW=$(( CAP - OUTSIDE - DOCKER )); LIMIT="$RAW"; FLOORED=""
    [ "$RAW" -ge "$FLOOR" ] || { LIMIT="$FLOOR"; FLOORED=1; }
}
show_formula() {
    printf 'потолок = max(%s, %s − вне %s − docker %s) = %s%s\n' "$(mib "$FLOOR")" "$(mib "$CAP")" \
        "$(mib "$OUTSIDE")" "$(mib "$DOCKER")" "$(mib "$LIMIT")" \
        "${FLOORED:+ — нижняя граница: сумма машины может превысить $(mib "$CAP"), её держат вход и сторож слота}"
    printf '  вне = (MemTotal − MemAvailable) %s − anon scope %s\n' "$(mib "$USED")" "$(mib "$1")"
}
journal() {
    [ "$MEMINFO" = /proc/meminfo ] || return 0
    local d; d="$(getent passwd "$(id -u)" | cut -d: -f6)/.cache/heavy-slots"
    mkdir -p "$d" 2>/dev/null && printf '%s memcap %s\n' "$(date -Is)" "$*" >> "$d/journal.log" 2>/dev/null
}
probe_unit() { [[ "$1" == session-memcap-probe-* ]]; }

# ── --launch: новый scope, где потолок ставится ───────────────────────────────
if [ "$MODE" = launch ]; then
    command -v systemd-run >/dev/null || { say "нет systemd-run (не выполнилось)"; exit 69; }
    formula 0
    if [ "$MEMINFO" = /proc/meminfo ]; then UNIT="memcap-session-$(date +%s)-$$.scope"
    else UNIT="session-memcap-probe-$$-$(date +%s).scope"; fi
    say "запуск в $UNIT: $(show_formula 0 | head -n 1); OOMPolicy=continue, omit, swap 0"
    journal "launch unit=$UNIT limit=${LIMIT}MiB used=${USED}MiB docker=${DOCKER}MiB cmd=$*"
    exec systemd-run --user --scope --quiet --collect --unit="$UNIT" \
        -p OOMPolicy=continue -p ManagedOOMPreference=omit -p ManagedOOMMemoryPressure=auto \
        -p MemoryMax="${LIMIT}M" -p MemoryHigh=infinity -p MemorySwapMax=0 -- "$@"
fi

# ── scope, где исполняется скрипт ────────────────────────────────────────────
CG="$(sed -n 's/^0:://p' /proc/self/cgroup)"
PREFIX="/user.slice/user-$(id -u).slice/user@$(id -u).service/"
UNIT="${CG##*/}"
if [[ "$CG" != "$PREFIX"* ]] || [[ "$UNIT" != *.scope && "$UNIT" != *.service ]]; then
    say "scope $CG не под менеджером пользователя: systemctl --user его не правит (не выполнилось)"; exit 69
fi
if [ "$MEMINFO" != /proc/meminfo ] && ! probe_unit "$UNIT"; then
    say "режим проб — только на одноразовом scope session-memcap-probe-*, а здесь $UNIT: живую сессию проба не трогает"; exit 64
fi
CGD="/sys/fs/cgroup$CG"
ANON="$(awk '$1 == "anon" { printf "%d\n", $2 / 1048576 }' "$CGD/memory.stat" 2>/dev/null)"
[ -n "$ANON" ] && [ -e "$CGD/memory.max" ] || { say "у $CGD нет контроллера memory (не выполнилось)"; exit 69; }
POLICY="$(systemctl --user show -p OOMPolicy --value "$UNIT" 2>/dev/null)"
[ -n "$POLICY" ] || { say "OOMPolicy $UNIT не прочитан у менеджера пользователя (не выполнилось)"; exit 69; }

formula "$ANON"
echo "scope $UNIT · OOMPolicy=$POLICY"
show_formula "$ANON"

why=""
[ $(( ANON + MARGIN )) -lt "$LIMIT" ] || why="anon scope $(mib "$ANON") + запас $(mib "$MARGIN") ≥ потолка $(mib "$LIMIT"): ядро сразу снимало бы процессы сессии"
[ "$POLICY" = continue ] || why="${why:+$why; }OOMPolicy=$POLICY: первое OOM-убийство под потолком остановило бы весь scope (замер в шапке), а на живом scope OOMPolicy не меняется — потолок получает сессия, запущенная $SELF --launch -- claude"
if [ "$MODE" = show ]; then
    [ -z "$why" ] || { say "ОТКАЗ — потолок не ставился бы: $why; метка omit ставилась бы"; exit 1; }
    echo "поставил бы: MemoryMax=$(mib "$LIMIT"), swap 0, high max; user.oomd_omit=1"; exit 0
fi

if [ -z "$why" ] && ! systemctl --user set-property --runtime "$UNIT" MemoryMax="${LIMIT}M" MemoryHigh=infinity \
        MemorySwapMax=0 ManagedOOMMemoryPressure=auto 2>/dev/null; then
    say "systemctl --user set-property $UNIT отказал (не выполнилось)"; exit 69
fi
# Метка omit — прямой записью xattr (set-property её не пишет, замер в шапке); сверка
# чтением — после set-property, по итоговому состоянию cgroup.
python3 -c 'import os, sys; os.setxattr(sys.argv[1], "user.oomd_omit", b"1")' "$CGD" 2>/dev/null
omit="$(python3 -c 'import os, sys; print(os.getxattr(sys.argv[1], "user.oomd_omit").decode())' "$CGD" 2>/dev/null)"
if [ "$omit" != 1 ]; then
    say "метка user.oomd_omit на $CGD не в силе: запись xattr не сверилась чтением, прочитано «${omit:-нет}» (не выполнилось)${why:+; потолок тоже не ставится: $why}"
    journal "noomit unit=$UNIT omit=${omit:-нет}"
    exit 69
fi
if [ -n "$why" ]; then
    say "ОТКАЗ — потолок не ставится: $why. Метка user.oomd_omit=1 в силе (сверена чтением)"
    journal "refuse unit=$UNIT limit=${LIMIT}MiB used=${USED}MiB anon=${ANON}MiB policy=$POLICY omit=1"
    exit 1
fi
got="$(cat "$CGD/memory.max") $(cat "$CGD/memory.swap.max" 2>/dev/null) $(cat "$CGD/memory.high")"
if [ "$got" != "$(( LIMIT * 1048576 )) 0 max" ]; then
    say "потолок объявлен, но НЕ в силе: memory.max/swap.max/high = «$got» (не выполнилось); метка omit в силе"
    journal "nolimit unit=$UNIT got=$got omit=1"
    exit 69
fi
echo "в силе: memory.max $(mib "$LIMIT"), swap.max 0, high max, user.oomd_omit=1"
journal "set unit=$UNIT limit=${LIMIT}MiB used=${USED}MiB anon=${ANON}MiB outside=${OUTSIDE}MiB docker=${DOCKER}MiB omit=1${FLOORED:+ floored}"
exit 0
}
