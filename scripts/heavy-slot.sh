#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# heavy-slot.sh — тяжёлый прогон входит в машину только через слот памяти.
#
# ПРЕДМЕТ. Решение владельца 2026-09-24: «контроль за оперативной памятью не
# должна переваливать за 45гб». Повод: машина упала по памяти — полосы разом
# подняли -race в docker, testcontainers и стенд kind, и каждая по отдельности
# видела «памяти хватает». Отказ был в МОМЕНТЕ: «хватает ли» и «занял» — два
# шага, между ними проходили соседи, а вошедший секунду назад памяти ещё не набрал.
#
# ФОРМА
#   heavy-slot.sh <класс> -- <команда> [аргументы…]
#   heavy-slot.sh --classes     классы, бюджеты и основание каждого
#   heavy-slot.sh --status      занятые слоты, память машины, хвост журнала
#
# ВХОД — строгая очередь по билету под flock на каталоге слотов, ОДНОМ на машину:
#   (MemTotal − MemAvailable) + недобранное занятыми + бюджет ≤ потолок.
# Недобранное = Σ max(0, бюджет − текущая память) по занятым слотам (memory.current
# их cgroup и их контейнера). Без этого слагаемого вход повторял бы исходный отказ.
# Места нет — опрос раз в HEAVY_SLOT_POLL_S до HEAVY_SLOT_WAIT_S, затем код 75.
# Потолок — в ГиБ, в тех единицах, что печатает `free -g` (MemTotal здесь 60,7).
#
# ИСПОЛНЕНИЕ
#   · systemd-run --user --scope -p MemoryMax=<бюджет> -p MemorySwapMax=0 — предел
#     ядра. Внутри слота он СВЕРЯЕТСЯ с memory.max до запуска команды: не совпал —
#     предела нет, и слот уходит в запасной путь, а не верит объявлению;
#   · docker run — подставляются --memory/--memory-swap=<бюджет> и --cidfile:
#     контейнер — потомок dockerd, а не клиента, cgroup слота до него не доходит;
#   · запасной путь (нет systemd --user либо контроллера memory): сторож суммирует
#     RSS дерева процессов раз в секунду и убивает дерево сверх бюджета. Предел
#     МЯГКИЙ — пик между опросами проходит. prlimit не взят (замер 2026-09-24):
#     под RLIMIT_AS=2 ГиБ клиента docker контейнер занял 3 ГиБ — предел до него не
#     доходит; под 1 ГиБ упал сам клиент — адресное пространство Go не память;
#   · сторож машины: пока команда идёт, раз в HEAVY_SLOT_GUARD_S; занято больше
#     потолка и этот слот — младший из занятых → команда обрывается; следующий
#     обрыв — не раньше HEAVY_SLOT_GUARD_GRACE_S: память убитого освобождается не
#     мгновенно, и без паузы сторож снимал бы старших за чужой хвост. Он держит то,
#     до чего предел слота не дотягивается: контейнеры testcontainers и узлы kind
#     живут в cgroup dockerd, а стенд остаётся в памяти после выхода команды —
#     его память входит в «занято» при каждом следующем входе.
#
# КОДЫ: код команды, если она исполнилась; 64 — вызов неверен; 69 — механизм
# недоступен; 75 — слот не выдан за время ожидания; 76 — команда оборвана
# пределом памяти. 69, 75 и 76 — «не выполнилось», а не красное: вердикта по
# предмету команды нет. Своё слово слот печатает строкой «heavy-slot: …» в stderr.
#
# ЖУРНАЛ: $HEAVY_SLOT_DIR/journal.log — вход, ожидание, выход с пиком памяти,
# обрыв. Пик — основание для пересмотра бюджетов: `grep ' leave ' journal.log`.
#
# Тело — одной группой { … }: bash разбирает её целиком до исполнения, и правка
# файла на месте не ломает идущие слоты. Без группы часовой прогон дочитывал бы
# уже другой текст — так 2026-09-24 потерян замер: слот вышел кодом 2 без записи.
{
set -uo pipefail

DIR="${HEAVY_SLOT_DIR:-$HOME/.cache/heavy-slots}"
LIMIT_MIB="${HEAVY_SLOT_LIMIT_MIB:-$(( ${HEAVY_SLOT_LIMIT_GIB:-45} * 1024 ))}"
POLL_S="${HEAVY_SLOT_POLL_S:-30}"
WAIT_S="${HEAVY_SLOT_WAIT_S:-1800}"
GUARD_S="${HEAVY_SLOT_GUARD_S:-2}"
GRACE_S="${HEAVY_SLOT_GUARD_GRACE_S:-10}"
MEMINFO="${HEAVY_SLOT_MEMINFO:-/proc/meminfo}"
LIMITER="${HEAVY_SLOT_LIMITER:-auto}"
CGROOT=/sys/fs/cgroup

# класс|бюджет MiB|что покрывает|основание бюджета. Замеры 2026-09-24 — через сам
# слот: пик — memory.peak cgroup, отметка ядра, а не выборка; у контейнера её читают
# раз в 2 с, и последние ≤ 2 с до выхода не видны.
CLASSES='go-race|16384|go test -race; make test, test-unit, test-service, test-service-short|go test -race -short ./... по монорепо (288 пакетов) в golang:1.26.8, -p 32, холодный кэш — 13,6 ГиБ; свои пакеты services/vpc (49) — 3,5 ГиБ
integration|8192|go test -tags=integration (testcontainers); make test-integration, test-pg-outside-selection|форма make test-integration SVC=vpc (-race, -p 1, холодный кэш) — 1,2 ГиБ тестов + 0,2 ГиБ Postgres; запас — на -p по умолчанию своего сервиса
ci-local|10240|scripts/ci-local.sh; git push в клон, чей pre-push зовёт ci-local|scripts/ci-local.sh go (23 проверки: build, vet, go test -short ./..., golangci-lint, gosec; кэш сборки тёплый, линтера холодный) — 5,2 ГиБ; прочие группы идут после неё по одной, не замерены
lint|8192|golangci-lint run, govulncheck, gosec, make lint|golangci-lint run ./... по монорепо, холодный кэш линтера — 4,5 ГиБ
docker|4096|docker run/create/start/build, docker compose up/run/build|общий класс — предел, а не прогноз: docker run получает --memory=бюджет
stand|8192|kind create cluster; make dev-up, reload-svc*; helm install/upgrade|узел kind — до 2,9 ГиБ (9 показаний docker stats в журналах сессий); сборка образов dev-up последовательная, её память в BuildKit не замерена
newman|2048|newman run; make e2e-newman, e2e-test; newman-e2e.sh, newman-parallel.sh|newman run самой большой коллекции (2,7 МБ, отчёт json) — 0,4 ГиБ; JOBS=1'

say() { printf 'heavy-slot: %s\n' "$*" >&2; }
now() { date +%s; }
mib() { awk -v m="$1" 'BEGIN { if (m < 1024) printf "%d МиБ", m; else printf "%.1f ГиБ", m / 1024 }'; }

class_budget() {
    local c="$1" line
    while IFS= read -r line; do
        [ "${line%%|*}" = "$c" ] || continue
        line="${line#*|}"
        printf '%s\n' "${line%%|*}"
        return 0
    done <<< "$CLASSES"
    return 1
}

print_classes() {
    local line name rest budget covers basis
    printf 'потолок машины: %s — (MemTotal − MemAvailable) + недобранное + бюджет\n' "$(mib "$LIMIT_MIB")"
    while IFS= read -r line; do
        name="${line%%|*}"; rest="${line#*|}"
        budget="${rest%%|*}"; rest="${rest#*|}"
        basis="${rest##*|}"; covers="${rest%|*}"
        printf '%-12s %8s  %s\n%-12s %8s  основание: %s\n' "$name" "$(mib "$budget")" "$covers" "" "" "$basis"
    done <<< "$CLASSES"
}

# used_mib — (MemTotal − MemAvailable) в MiB; пусто, если не прочитать.
used_mib() {
    awk '/^MemTotal:/ { t = $2 } /^MemAvailable:/ { a = $2; h = 1 }
         END { if (t > 0 && h) printf "%d\n", (t - a) / 1024 }' "$MEMINFO" 2>/dev/null
}

cg_bytes() { local v; v="$(cat "$1" 2>/dev/null)" && [ -n "$v" ] && printf '%s\n' "$v" || echo 0; }

# field <файл> <ключ> — значение key=value из записи слота.
field() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n 1; }

# slot_current_mib <префикс записи> — текущая память слота: его cgroup, его
# контейнер, либо RSS дерева по отчёту сторожа запасного пути.
slot_current_mib() {
    local p="$1" b=0 cg cid rss
    cg="$(cat "$p.cg" 2>/dev/null)"
    [ -n "$cg" ] && b=$(( b + $(cg_bytes "$CGROOT$cg/memory.current") ))
    cid="$(cat "$p.cid" 2>/dev/null)"
    [ -n "$cid" ] && b=$(( b + $(cg_bytes "$CGROOT/system.slice/docker-$cid.scope/memory.current") ))
    rss="$(cat "$p.rss" 2>/dev/null)"
    [ -n "$rss" ] && b=$(( b + rss * 1024 * 1024 ))
    echo $(( b / 1024 / 1024 ))
}

pid_start() { awk '{ print $22 }' "/proc/$1/stat" 2>/dev/null; }

slot_alive() {
    local f="$1" pid st unit
    pid="$(field "$f" pid)"; st="$(field "$f" pid_start)"; unit="$(field "$f" unit)"
    if [ -n "$pid" ] && [ "$(pid_start "$pid")" = "$st" ]; then return 0; fi
    [ -n "$unit" ] && systemctl --user is-active --quiet "$unit" 2>/dev/null
}

journal() {
    printf '%s %s\n' "$(date -Is)" "$*" >> "$DIR/journal.log" 2>/dev/null
}

# reap — снять записи слотов, чей держатель умер (SIGKILL не даёт trap).
reap() {
    local f
    for f in "$DIR"/active/*.slot; do
        [ -e "$f" ] || continue
        slot_alive "$f" && continue
        journal "reap id=$(basename "$f" .slot) class=$(field "$f" class) pid=$(field "$f" pid)"
        rm -f "${f%.slot}".*
    done
}

# reserved_mib [кроме id] — недобранное занятыми слотами.
reserved_mib() {
    local skip="${1:-}" f id b cur sum=0
    for f in "$DIR"/active/*.slot; do
        [ -e "$f" ] || continue
        id="$(basename "$f" .slot)"; [ "$id" = "$skip" ] && continue
        b="$(field "$f" budget)"; cur="$(slot_current_mib "${f%.slot}")"
        [ "${b:-0}" -gt "$cur" ] && sum=$(( sum + b - cur ))
    done
    echo "$sum"
}

# Классы, гоняющие golangci-lint: по одному на машину — общий кэш и замок линтера
# (второй ждёт или падает «parallel golangci-lint is running»).
EXCLUSIVE=" lint ci-local "
is_exclusive() { [[ "$EXCLUSIVE" == *" $1 "* ]]; }
exclusive_holder() {
    local f c
    for f in "$DIR"/active/*.slot; do
        [ -e "$f" ] || continue
        c="$(field "$f" class)"
        is_exclusive "$c" && { printf '%s pid %s\n' "$c" "$(field "$f" pid)"; return; }
    done
}

youngest_id() {
    local f best="" bs=-1 s
    for f in "$DIR"/active/*.slot; do
        [ -e "$f" ] || continue
        s="$(field "$f" seq)"
        if [ "${s:-0}" -gt "$bs" ]; then bs="$s"; best="$(basename "$f" .slot)"; fi
    done
    echo "$best"
}

print_status() {
    local used f p
    used="$(used_mib)"
    printf 'потолок %s · занято машиной %s · недобрано слотами %s\n' \
        "$(mib "$LIMIT_MIB")" "$(mib "${used:-0}")" "$(mib "$(reserved_mib)")"
    for f in "$DIR"/active/*.slot; do
        [ -e "$f" ] || continue
        p="${f%.slot}"
        printf '  %-11s бюджет %-9s сейчас %-9s pid %-8s с %s  %s\n    %s\n' \
            "$(field "$f" class)" "$(mib "$(field "$f" budget)")" "$(mib "$(slot_current_mib "$p")")" \
            "$(field "$f" pid)" "$(date -d "@$(field "$f" start)" +%H:%M:%S)" "$(field "$f" who)" \
            "$(field "$f" cmd | cut -c1-160)"
    done
    for f in "$DIR"/queue/*; do
        [ -e "$f" ] || continue
        printf '  ждёт: %-11s бюджет %-9s pid %-8s %s\n' "$(field "$f" class)" "$(mib "$(field "$f" budget)")" "$(field "$f" pid)" "$(field "$f" who)"
    done
    [ -f "$DIR/journal.log" ] && { echo "журнал ($DIR/journal.log), последние 10:"; tail -n 10 "$DIR/journal.log" | cut -c1-220; }
}

# ── разбор вызова ────────────────────────────────────────────────────────────
case "${1:-}" in
    --classes) print_classes; exit 0 ;;
    --status)  mkdir -p "$DIR/active" 2>/dev/null; print_status; exit 0 ;;
    ''|-h|--help)
        sed -n '13,16p' "$0" >&2; exit 64 ;;
esac

CLASS="$1"; shift
if ! BUDGET="$(class_budget "$CLASS")"; then
    say "класса «$CLASS» нет. Классы: $(cut -d'|' -f1 <<< "$CLASSES" | tr '\n' ' ')— см. --classes"
    exit 64
fi
BUDGET="${HEAVY_SLOT_BUDGET_MIB:-$BUDGET}"
if [ "${1:-}" != "--" ] || [ "$#" -lt 2 ]; then
    say "форма вызова: heavy-slot.sh $CLASS -- <команда> [аргументы…]"
    exit 64
fi
shift
if [ "$BUDGET" -gt "$LIMIT_MIB" ]; then
    say "бюджет $(mib "$BUDGET") больше потолка машины $(mib "$LIMIT_MIB") — такой слот не выдаётся никогда"
    exit 64
fi

if ! { mkdir -p "$DIR/active" && touch "$DIR/journal.log" "$DIR/lock"; } 2>/dev/null; then
    say "каталог слотов $DIR недоступен на запись — слот не выдан (не выполнилось)"; exit 69
fi
command -v flock >/dev/null || { say "нет flock — вход без замка повторил бы исходный отказ (не выполнилось)"; exit 69; }
[ -n "$(used_mib)" ] || { say "не прочитать MemTotal/MemAvailable из $MEMINFO (не выполнилось)"; exit 69; }

ID="$(now)-$$"
P="$DIR/active/$ID"
UNIT="heavy-slot-$CLASS-$$-$(now).scope"
CMD=("$@")

# docker run: предел — контейнеру, а не клиенту. Флаги памяти у вызова — отказ:
# слот ставит их сам, и второе значение молча перекрыло бы бюджет.
DOCKER_RUN=0
if [ "$(basename -- "${CMD[0]}")" = docker ]; then
    i=1
    while [ "$i" -lt "${#CMD[@]}" ]; do
        case "${CMD[$i]}" in
            --context|-H|--host|--config|-l|--log-level) i=$(( i + 2 )) ;;
            -*) i=$(( i + 1 )) ;;
            *) break ;;
        esac
    done
    sub="${CMD[$i]:-}"; at=$(( i + 1 ))
    if [ "$sub" = container ] && [ "${CMD[$at]:-}" = run ]; then sub=run; at=$(( at + 1 )); fi
    if [ "$sub" = run ]; then
        # Флаги самого docker кончаются на образе; дальше — аргументы команды
        # контейнера, и её «-m» слоту не принадлежит. Значение отдельным словом
        # берут длинные флаги вне списка булевых и короткие a c e h l m p u v w.
        j="$at"
        while [ "$j" -lt "${#CMD[@]}" ]; do
            a="${CMD[$j]}"
            case "$a" in
                -m|-m?*|--memory|--memory=*|--memory-swap|--memory-swap=*|--cidfile|--cidfile=*)
                    say "docker run несёт «$a» — слот ставит --memory/--memory-swap/--cidfile сам; сними флаг (бюджет класса: $(mib "$BUDGET"))"
                    exit 64 ;;
                --) break ;;
                --*=*) j=$(( j + 1 )) ;;
                --rm|--detach|--interactive|--tty|--init|--privileged|--read-only|--publish-all|--oom-kill-disable|--no-healthcheck|--quiet|--disable-content-trust|--use-api-socket|--help)
                    j=$(( j + 1 )) ;;
                --*) j=$(( j + 2 )) ;;
                -?*)
                    k=1; step=1
                    while [ "$k" -lt "${#a}" ]; do
                        case "${a:$k:1}" in
                            [acehlmpuvw]) [ "$k" -eq $(( ${#a} - 1 )) ] && step=2; break ;;
                        esac
                        k=$(( k + 1 ))
                    done
                    j=$(( j + step )) ;;
                *) break ;;
            esac
        done
        CMD=("${CMD[@]:0:$at}" "--memory=${BUDGET}m" "--memory-swap=${BUDGET}m" "--cidfile=$P.cidfile" "${CMD[@]:$at}")
        DOCKER_RUN=1
    fi
fi

WHO="$(git -C "$PWD" branch --show-current 2>/dev/null)@$PWD"
CMDLINE="$(printf '%q ' "$@")"

# ── вход ─────────────────────────────────────────────────────────────────────
# Очередь строгая, по билету: малый слот не обгоняет ждущий большой. С обгоном
# поток мелких прогонов держал бы большой в ожидании до кода 75 — голодание.
lock() {
    exec {LK}>>"$DIR/lock"
    flock -w 120 "$LK" && return 0
    say "замок $DIR/lock не взят за 120 с — кто-то держит его вне формы (не выполнилось)"; exit 69
}
unlock() { flock -u "$LK"; exec {LK}>&-; }
mkdir -p "$DIR/queue"
lock
tk=$(( $(cat "$DIR/ticket" 2>/dev/null || echo 0) + 1 )); echo "$tk" > "$DIR/ticket"
TICKET="$DIR/queue/$(printf '%012d' "$tk")"
printf 'pid=%s\npid_start=%s\nclass=%s\nbudget=%s\nwho=%s\n' "$$" "$(pid_start $$)" "$CLASS" "$BUDGET" "$WHO" > "$TICKET"
unlock
trap 'rm -f "$TICKET"' EXIT
t0="$(now)"; waited=0
while :; do
    lock
    reap
    held="$(exclusive_holder)"
    ahead=0
    for f in "$DIR"/queue/*; do
        [ -e "$f" ] || continue
        if [ "$(pid_start "$(field "$f" pid)")" != "$(field "$f" pid_start)" ]; then
            journal "reap ticket=$(basename "$f") class=$(field "$f" class) pid=$(field "$f" pid)"; rm -f "$f"; continue
        fi
        # Ждущий исключительного класса при занятом линтере очередь не держит:
        # иначе десять минут ci-local стояли бы и newman, и go-race за ним.
        if [ -n "$held" ] && is_exclusive "$(field "$f" class)"; then continue; fi
        [[ "$f" < "$TICKET" ]] && ahead=$(( ahead + 1 ))
    done
    used="$(used_mib)"; resv="$(reserved_mib)"
    blocked=""
    is_exclusive "$CLASS" && [ -n "$held" ] && blocked="$held"
    if [ "$ahead" -eq 0 ] && [ -z "$blocked" ] && [ $(( used + resv + BUDGET )) -le "$LIMIT_MIB" ]; then
        rm -f "$TICKET"
        seq=$(( $(cat "$DIR/seq" 2>/dev/null || echo 0) + 1 )); echo "$seq" > "$DIR/seq"
        if [ "$(stat -c %s "$DIR/journal.log" 2>/dev/null || echo 0)" -gt 4194304 ]; then
            tail -n 10000 "$DIR/journal.log" > "$DIR/journal.log.new" && mv "$DIR/journal.log.new" "$DIR/journal.log"
        fi
        {
            echo "class=$CLASS"; echo "budget=$BUDGET"; echo "pid=$$"; echo "pid_start=$(pid_start $$)"
            echo "unit=$UNIT"; echo "start=$(now)"; echo "seq=$seq"; echo "who=$WHO"; echo "cmd=$CMDLINE"
        } > "$P.slot"
        journal "enter id=$ID class=$CLASS budget=${BUDGET}MiB used=${used}MiB reserved=${resv}MiB waited=${waited}s who=$WHO cmd=$CMDLINE"
        unlock
        break
    fi
    unlock
    why="занято $(mib "$used") + недобрано $(mib "$resv") + бюджет $(mib "$BUDGET") $( [ $(( used + resv + BUDGET )) -le "$LIMIT_MIB" ] && echo '≤' || echo '>') потолка $(mib "$LIMIT_MIB")"
    [ "$ahead" -gt 0 ] && why="в очереди впереди $ahead; $why"
    [ -n "$blocked" ] && why="golangci-lint по одному на машину, занят: $blocked; $why"
    waited=$(( $(now) - t0 ))
    if [ "$waited" -ge "$WAIT_S" ]; then
        journal "timeout class=$CLASS budget=${BUDGET}MiB used=${used}MiB reserved=${resv}MiB ahead=$ahead waited=${waited}s who=$WHO cmd=$CMDLINE"
        say "НЕ ВЫПОЛНИЛОСЬ — слот «$CLASS» не выдан за ${waited} с: $why."
        say "команда НЕ запускалась; кто занял — heavy-slot.sh --status"
        exit 75
    fi
    [ "$waited" -eq 0 ] && journal "wait class=$CLASS budget=${BUDGET}MiB used=${used}MiB reserved=${resv}MiB ahead=$ahead who=$WHO"
    say "ждёт слота «$CLASS»: $why; ждёт ${waited} с из ${WAIT_S}"
    sleep "$(( POLL_S < WAIT_S - waited ? POLL_S : WAIT_S - waited ))"
done

WPID=""; KIND=""; CPID=""; RPID=""
# shellcheck disable=SC2329  # зовётся ловушкой
cleanup() {
    [ -n "$WPID" ] && kill "$WPID" 2>/dev/null
    rm -f "$P".*
}
# shellcheck disable=SC2329  # зовётся ловушкой
on_signal() {
    if [ -n "$UNIT" ] && systemctl --user kill --signal=SIGTERM "$UNIT" 2>/dev/null; then
        for _ in 1 2 3 4 5 6; do systemctl --user is-active --quiet "$UNIT" 2>/dev/null || break; sleep 0.5; done
        systemctl --user kill --signal=SIGKILL "$UNIT" 2>/dev/null
    fi
    [ -n "$RPID" ] && kill "$RPID" 2>/dev/null
    [ -n "$CPID" ] && tree_kill "$CPID"
    [ -s "$P.cidfile" ] && docker kill "$(cat "$P.cidfile")" >/dev/null 2>&1
    journal "signal id=$ID class=$CLASS"
    cleanup; exit 143
}
trap cleanup EXIT
trap on_signal INT TERM HUP

# tree_rss_mib <pid> — сумма RSS дерева процессов от корня.
tree_rss_mib() {
    ps -e -o pid=,ppid=,rss= 2>/dev/null | awk -v root="$1" '
        { par[$1] = $2; rss[$1] = $3 }
        END { for (p in par) { q = p; while (q != "" && q != 0 && q != 1) { if (q == root) { s += rss[p]; break } q = par[q] } }
              printf "%d\n", s / 1024 }'
}
tree_kill() {
    local pids
    pids="$(ps -e -o pid=,ppid= | awk -v root="$1" '{ par[$1] = $2 }
        END { for (p in par) { q = p; while (q != "" && q != 0 && q != 1) { if (q == root) { print p; break } q = par[q] } } }')"
    # shellcheck disable=SC2086
    [ -n "$pids" ] && kill -KILL $pids 2>/dev/null
}

# watcher <root pid, если предел мягкий> — сторож машины, пик контейнера,
# мягкий предел запасного пути. Пишет только в свои файлы записи слота.
watcher() {
    local root="${1:-}" used cid cpeak=0 v rss
    while [ -e "$P.slot" ]; do
        if [ ! -s "$P.cid" ] && [ -s "$P.cidfile" ]; then cp "$P.cidfile" "$P.cid"; fi
        cid="$(cat "$P.cid" 2>/dev/null)"
        if [ -n "$cid" ]; then
            v="$(cg_bytes "$CGROOT/system.slice/docker-$cid.scope/memory.peak")"
            [ "$v" -gt "$cpeak" ] && cpeak="$v" && echo "$cpeak" > "$P.cpeak"
        fi
        if [ -n "$root" ]; then
            rss="$(tree_rss_mib "$root")"; echo "$rss" > "$P.rss"
            [ "$rss" -gt "$(cat "$P.rsspeak" 2>/dev/null || echo 0)" ] && echo "$rss" > "$P.rsspeak"
            if [ "$rss" -gt "$BUDGET" ]; then
                echo "rss=${rss}MiB" > "$P.soft"; tree_kill "$root"
            fi
        fi
        used="$(used_mib)"
        if [ -n "$used" ] && [ "$used" -gt "$LIMIT_MIB" ] && [ "$(youngest_id)" = "$ID" ] &&
           [ $(( $(now) - $(cat "$DIR/guard-at" 2>/dev/null || echo 0) )) -ge "$GRACE_S" ]; then
            now > "$DIR/guard-at"; echo "used=${used}MiB" > "$P.guard"
            systemctl --user kill --signal=SIGKILL "$UNIT" 2>/dev/null
            [ -n "$cid" ] && docker kill "$cid" >/dev/null 2>&1
            [ -n "$root" ] && tree_kill "$root"
        fi
        sleep "$GUARD_S"
    done
}

# ── исполнение ───────────────────────────────────────────────────────────────
# Обёртка внутри слота: до команды сверяет memory.max с бюджетом; после —
# пишет код, пик памяти cgroup и счёт OOM. Второй аргумент ждётся в байтах.
# shellcheck disable=SC2016
INNER='p="$1"; want="$2"; shift 2
cg="$(sed -n "s/^0:://p" /proc/self/cgroup)"; printf "%s\n" "$cg" > "$p.cg"
have="$(cat "/sys/fs/cgroup$cg/memory.max" 2>/dev/null)"
if [ "$have" != "$want" ]; then printf "nolimit %s\n" "${have:-нет}" > "$p.res"; exit 70; fi
"$@"; rc=$?
peak="$(cat "/sys/fs/cgroup$cg/memory.peak" 2>/dev/null || echo 0)"
oom="$(awk "\$1 == \"oom_kill\" { print \$2 }" "/sys/fs/cgroup$cg/memory.events" 2>/dev/null)"
printf "rc %s %s %s\n" "$rc" "$peak" "${oom:-0}" > "$p.res"
exit "$rc"'

t_run="$(now)"; rc=0
if [ "$LIMITER" != watch ] && command -v systemd-run >/dev/null; then
    watcher & WPID=$!
    # Фоном и через wait: ловушка сигнала срабатывает посреди wait, а не после
    # выхода команды переднего плана — иначе TERM слоту ждал бы конца прогона.
    systemd-run --user --scope --quiet --collect --expand-environment=no --unit="$UNIT" \
        -p MemoryMax="${BUDGET}M" -p MemorySwapMax=0 -p OOMPolicy=continue \
        -- bash -c "$INNER" heavy-slot "$P" "$(( BUDGET * 1024 * 1024 ))" "${CMD[@]}" 0<&0 &
    RPID=$!; wait "$RPID"; rc=$?; RPID=""
    { read -r KIND _ < "$P.res"; } 2>/dev/null || KIND=""
    if [ "$KIND" = nolimit ] || { [ -z "$KIND" ] && [ "$rc" -ne 0 ] && [ ! -e "$P.cg" ]; }; then
        say "предел ядра НЕ в силе ($( [ "$KIND" = nolimit ] && cut -d' ' -f2 "$P.res" || echo "systemd-run --user отказал, код $rc")) — запасной путь: мягкий предел по RSS"
        journal "nolimit id=$ID class=$CLASS rc=$rc"
        kill "$WPID" 2>/dev/null; wait "$WPID" 2>/dev/null; WPID=""
        rm -f "$P.res" "$P.cg"; UNIT=""; LIMITER=watch; rc=0
    fi
fi
if [ "$LIMITER" = watch ] || ! command -v systemd-run >/dev/null; then
    [ "$LIMITER" = watch ] || say "systemd-run не найден — запасной путь: мягкий предел по RSS"
    UNIT=""; LIMITER=watch
    "${CMD[@]}" 0<&0 & CPID=$!
    watcher "$CPID" & WPID=$!
    wait "$CPID"; rc=$?
fi
kill "$WPID" 2>/dev/null; wait "$WPID" 2>/dev/null; WPID=""
dur=$(( $(now) - t_run ))

# ── итог ─────────────────────────────────────────────────────────────────────
peak=0; oom=0; cpeak=0; coom=0; cut_by=""
if { read -r KIND _ peak oom < "$P.res"; } 2>/dev/null && [ "$KIND" = rc ]; then :; else peak=0; oom=0; fi
[ -s "$P.cpeak" ] && cpeak="$(cat "$P.cpeak")"
if [ "$DOCKER_RUN" -eq 1 ] && [ -s "$P.cidfile" ]; then
    cid="$(cat "$P.cidfile")"
    docker events --since "$(( t_run - 5 ))" --until "$(( $(now) + 1 ))" --filter "container=$cid" \
        --filter event=oom --format '{{.Action}}' 2>/dev/null | grep -q oom && coom=1
fi
[ "${oom:-0}" -gt 0 ] && cut_by="OOM в cgroup слота (oom_kill=$oom)"
[ "$coom" -gt 0 ] && cut_by="OOM контейнера (--memory=$(mib "$BUDGET"))"
[ -s "$P.soft" ] && cut_by="мягкий предел: $(cat "$P.soft") > бюджета"
[ -s "$P.guard" ] && cut_by="сторож машины: $(cat "$P.guard") > потолка $(mib "$LIMIT_MIB"), слот младший"
if [ -z "$cut_by" ] && [ ! -s "$P.res" ] && [ "$LIMITER" != watch ]; then
    say "итог слота не записан: дерево команды убито целиком снаружи (сигнал либо systemd-oomd), код $rc"
fi
peak_mib=$(( peak / 1024 / 1024 )); cpeak_mib=$(( cpeak / 1024 / 1024 ))
[ "$LIMITER" = watch ] && peak_mib="$(cat "$P.rsspeak" 2>/dev/null || echo 0)"
journal "leave id=$ID class=$CLASS budget=${BUDGET}MiB rc=$rc peak=${peak_mib}MiB container_peak=${cpeak_mib}MiB limiter=${LIMITER/auto/systemd} dur=${dur}s cut=${cut_by:-—} who=$WHO"
if [ -n "$cut_by" ]; then
    say "НЕ ВЫПОЛНИЛОСЬ — команда оборвана пределом памяти: $cut_by; код команды $rc."
    say "это исчерпание ресурса, а не красное: вердикта по предмету нет. Бюджет класса «$CLASS» — $(mib "$BUDGET"); пик — в журнале $DIR/journal.log"
    exit 76
fi
exit "$rc"
}
