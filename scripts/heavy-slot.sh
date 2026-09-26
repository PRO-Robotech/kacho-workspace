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
#   heavy-slot.sh --budget <класс>  бюджет класса в МиБ (читает session-memcap.sh)
#   heavy-slot.sh --status      занятые слоты, память машины, хвост журнала
#
# ВХОД — строгая очередь по билету под flock на каталоге слотов, ОДНОМ на машину:
#   (MemTotal − MemAvailable) + недобранное занятыми + бюджет ≤ потолок.
# Недобранное = Σ max(0, бюджет − текущая память) по занятым слотам (memory.current
# их cgroup и их контейнеров). Без этого слагаемого вход повторял бы исходный отказ.
# Места нет — опрос раз в 30 с до 1800 с, затем код 75. Голову очереди держит лишь
# билет, который влез бы под СВОЙ потолок, будь занятые слоты пусты: (MemTotal −
# MemAvailable) − память слотов + бюджет ≤ потолок билета. Прочий ждёт памяти не
# от слотов — её очередь не освободит, и держать за ним соседей незачем (опыт ws#832,
# круг 3: потолок 1 ГиБ на 99999 с стоял головой строгой очереди).
# Потолок — в ГиБ, в тех единицах, что печатает `free -g` (MemTotal здесь 60,7).
#
# ГРАНИЦА: предел держит cgroup слота, а из неё уводит перенос процесса в другой
# unit. Команда, в чьих словах argv стоит `systemd-run` или `--scope`, — отказ 64
# (опыт ws#832, круг 3: `systemd-run --user --scope …` уходил из слота). Мимо слов
# argv — не видно: скрипт, внутри которого стоит systemd-run; `systemctl --user
# start`, `busctl`/`dbus-send` StartTransientUnit; tmux и screen к уже идущему
# серверу; `ssh localhost`; `docker exec` в живой контейнер; `at`. Перенос уводит и
# из-под потолка сессии (scripts/session-memcap.sh): предела ядра у них нет, их видят
# лишь вход и сторож слотов по памяти машины да systemd-oomd.
#
# ИСПОЛНЕНИЕ
#   · systemd-run --user --scope -p MemoryMax=<бюджет> -p MemorySwapMax=0 — предел
#     ядра. Внутри слота он СВЕРЯЕТСЯ с memory.max до запуска команды: не совпал —
#     предела нет, и слот уходит в запасной путь, а не верит объявлению;
#   · docker run/create — --memory/--memory-swap=<бюджет> и --cidfile: контейнер —
#     потомок dockerd, cgroup слота до него не доходит. Подставляет их `docker` в
#     PATH команды — ссылка на этот файл, — поэтому предел получает КАЖДЫЙ вызов
#     дерева: за timeout, в bash -c, в рецепте make, у kind (опыт ws#832: `timeout
#     60 docker run` и `docker create` шли без предела). Мимо — абсолютный путь к
#     docker внутри команды и docker API (testcontainers, compose): их держит сторож;
#   · запасной путь (нет systemd --user либо контроллера memory): сторож суммирует
#     RSS дерева процессов раз в секунду и убивает дерево сверх бюджета. Предел
#     МЯГКИЙ — пик между опросами проходит. prlimit не взят (замер 2026-09-24):
#     под RLIMIT_AS=2 ГиБ клиента docker контейнер занял 3 ГиБ — предел до него не
#     доходит; под 1 ГиБ упал сам клиент — адресное пространство Go не память;
#   · сторож машины: пока команда идёт, раз в 2 с; занято больше
#     потолка и этот слот — младший из занятых → команда и её контейнеры
#     обрываются; следующий обрыв — не раньше чем через 10 с: память
#     убитого освобождается не мгновенно, и без паузы сторож снимал бы старших за
#     чужой хвост. Он держит то, до чего предел слота не дотягивается: контейнеры
#     testcontainers и узлы kind живут в cgroup dockerd, а стенд остаётся в памяти
#     после выхода команды — его память входит в «занято» при каждом следующем входе.
#
# РУЧКИ HEAVY_SLOT_*. Над настоящей памятью (/proc/meminfo) ручек нет: потолок 45 ГиБ,
# ожидание 1800 с, общий каталог, бюджет, ограничитель и сторож — как в классе; любая
# ручка — 64 до первой записи (опыт ws#832, круги 2–3: переменная снимала потолок или
# очередь). Ручки — только режиму проб, синтетическому HEAVY_SLOT_MEMINFO в своём
# каталоге, и тяжёлым прогоном он быть не способен: бюджет ≤ 512 МиБ, сторож раз в 1–2 с. Страж видит
# ручки лишь в строке команды, скрипт с ними он пропускает — их держит слот. Сторож
# машины в режиме проб судит синтетическую память: docker мимо подмены (абсолютный
# путь, API) под ним без предела.
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

# Общий каталог — от домашнего каталога учётки, а не от $HOME: иначе HOME=… был бы
# ещё одной ручкой, уводящей вызов из общей очереди.
SHARED="$(getent passwd "$(id -u)" | cut -d: -f6)/.cache/heavy-slots"
DIR="${HEAVY_SLOT_DIR:-$SHARED}"
CAP_MIB=46080  # 45 ГиБ — решение владельца 2026-09-24
PROBE_MIB=512  # потолок бюджета в режиме проб: пробы берут ≤ 301 МиБ
# Рабочие величины; ручки HEAVY_SLOT_* их меняют только в режиме проб (ниже).
LIMIT_MIB="$CAP_MIB"; POLL_S=30; WAIT_S=1800; GUARD_S=2; GRACE_S=10; LIMITER=auto
MEMINFO="${HEAVY_SLOT_MEMINFO:-/proc/meminfo}"
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

# docker_limit <бюджет MiB> <cidfile> <аргументы docker…> — в DARGS аргументы, где
# run/create (и container run/create) несут предел бюджета; прочее — как было.
# Код 64 — у вызова свои флаги памяти: второе значение молча перекрыло бы бюджет.
docker_limit() {
    local budget="$1" cidf="$2" i=0 sub at j a k step
    shift 2
    DARGS=("$@")
    while [ "$i" -lt "${#DARGS[@]}" ]; do
        case "${DARGS[$i]}" in
            --context|-c|-H|--host|--config|-l|--log-level|--tlscacert|--tlscert|--tlskey) i=$(( i + 2 )) ;;
            -*) i=$(( i + 1 )) ;;
            *) break ;;
        esac
    done
    sub="${DARGS[$i]:-}"; at=$(( i + 1 ))
    if [ "$sub" = container ]; then sub="${DARGS[$at]:-}"; at=$(( at + 1 )); fi
    case "$sub" in run|create) ;; *) return 0 ;; esac
    # Флаги самого docker кончаются на образе; дальше — аргументы команды
    # контейнера, и её «-m» слоту не принадлежит. Значение отдельным словом
    # берут длинные флаги вне списка булевых и короткие a c e h l m p u v w.
    j="$at"
    while [ "$j" -lt "${#DARGS[@]}" ]; do
        a="${DARGS[$j]}"
        case "$a" in
            -m|-m?*|--memory|--memory=*|--memory-swap|--memory-swap=*|--cidfile|--cidfile=*)
                say "docker $sub несёт «$a» — слот ставит --memory/--memory-swap/--cidfile сам; сними флаг (бюджет класса: $(mib "$budget"))"
                return 64 ;;
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
    DARGS=("${DARGS[@]:0:$at}" "--memory=${budget}m" "--memory-swap=${budget}m" "--cidfile=$cidf" "${DARGS[@]:$at}")
}

# Вызван как `docker` из PATH команды слота — подставить предел и отдать настоящему.
if [ "${0##*/}" = docker ]; then
    if [ -z "${HEAVY_SLOT_P:-}" ] || [ -z "${HEAVY_SLOT_B:-}" ] || [ -z "${HEAVY_SLOT_REAL_DOCKER:-}" ]; then
        say "docker-подмена слота вызвана вне слота (нет HEAVY_SLOT_P/_B/_REAL_DOCKER)"; exit 69
    fi
    mkdir -p "$HEAVY_SLOT_P.cid.d" 2>/dev/null
    docker_limit "$HEAVY_SLOT_B" "$(mktemp -u "$HEAVY_SLOT_P.cid.d/XXXXXX")" "$@" || exit 64
    exec "$HEAVY_SLOT_REAL_DOCKER" "${DARGS[@]}"
fi

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

# used_mib [meminfo] — (MemTotal − MemAvailable) в MiB; пусто, если не прочитать.
used_mib() {
    awk '/^MemTotal:/ { t = $2 } /^MemAvailable:/ { a = $2; h = 1 }
         END { if (t > 0 && h) printf "%d\n", (t - a) / 1024 }' "${1:-$MEMINFO}" 2>/dev/null
}

cg_bytes() { local v; v="$(cat "$1" 2>/dev/null)" && [ -n "$v" ] && printf '%s\n' "$v" || echo 0; }

# field <файл> <ключ> — значение key=value из записи слота.
field() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n 1; }

# slot_cids <префикс записи> — контейнеры, созданные командой слота, по строке.
slot_cids() {
    local f
    for f in "$1".cid.d/*; do [ -s "$f" ] && printf '%s\n' "$(cat "$f")"; done
}

# slot_current_mib <префикс записи> — текущая память слота: его cgroup, его
# контейнеры, либо RSS дерева по отчёту сторожа запасного пути.
slot_current_mib() {
    local p="$1" b=0 cg cid rss
    cg="$(cat "$p.cg" 2>/dev/null)"
    [ -n "$cg" ] && b=$(( b + $(cg_bytes "$CGROOT$cg/memory.current") ))
    for cid in $(slot_cids "$p"); do
        b=$(( b + $(cg_bytes "$CGROOT/system.slice/docker-$cid.scope/memory.current") ))
    done
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
        rm -rf "${f%.slot}".*
    done
}

# slots_mib — текущая память всех занятых слотов.
slots_mib() {
    local f sum=0
    for f in "$DIR"/active/*.slot; do
        [ -e "$f" ] && sum=$(( sum + $(slot_current_mib "${f%.slot}") ))
    done
    echo "$sum"
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
    --budget)  class_budget "${2:-}" || { say "класса «${2:-}» нет"; exit 64; }; exit 0 ;;
    --status)  mkdir -p "$DIR/active" 2>/dev/null; print_status; exit 0 ;;
    ''|-h|--help)
        sed -n '13,17p' "$0" >&2; exit 64 ;;
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

# Ручки — до первой записи: отказ не оставляет следа в общем каталоге.
KNOBS="HEAVY_SLOT_LIMIT_GIB HEAVY_SLOT_LIMIT_MIB HEAVY_SLOT_WAIT_S HEAVY_SLOT_POLL_S HEAVY_SLOT_BUDGET_MIB HEAVY_SLOT_LIMITER HEAVY_SLOT_GUARD_S HEAVY_SLOT_GUARD_GRACE_S"
if [ "$MEMINFO" = /proc/meminfo ]; then
    knob=""
    [ "$DIR" = "$SHARED" ] || [ "$DIR" -ef "$SHARED" ] || knob="свой каталог слотов $DIR — отдельная очередь, соседей общей он не видит"
    for v in $KNOBS; do
        [ -n "${!v+x}" ] && knob="$v=${!v} — потолок 45 ГиБ, ожидание 1800 с, бюджет и сторож класса не переопределяются"
    done
    if [ -n "$knob" ]; then
        say "над настоящей памятью машины ручка не принимается: $knob. Решение владельца 2026-09-24 — ≤ 45 ГиБ на машину; ручки — только пробам над синтетическим HEAVY_SLOT_MEMINFO"
        exit 64
    fi
else
    if [ "$DIR" = "$SHARED" ] || [ "$DIR" -ef "$SHARED" ]; then
        say "синтетический HEAVY_SLOT_MEMINFO — режим проб, и он идёт только в своём каталоге (HEAVY_SLOT_DIR): в общей очереди билет пробы стоял бы среди настоящих"
        exit 64
    fi
    for v in $KNOBS; do
        [ "$v" = HEAVY_SLOT_LIMITER ] || [ -z "${!v+x}" ] || [[ "${!v}" =~ ^[0-9]+$ ]] || { say "$v=«${!v}» — не число"; exit 64; }
    done
    LIMIT_MIB="${HEAVY_SLOT_LIMIT_MIB:-$(( ${HEAVY_SLOT_LIMIT_GIB:-45} * 1024 ))}"
    POLL_S="${HEAVY_SLOT_POLL_S:-$POLL_S}"; WAIT_S="${HEAVY_SLOT_WAIT_S:-$WAIT_S}"
    GUARD_S="${HEAVY_SLOT_GUARD_S:-$GUARD_S}"; GRACE_S="${HEAVY_SLOT_GUARD_GRACE_S:-$GRACE_S}"
    LIMITER="${HEAVY_SLOT_LIMITER:-$LIMITER}"
    if [ "$BUDGET" -gt "$PROBE_MIB" ] || ! [[ "$GUARD_S" =~ ^[12]$ ]]; then
        say "синтетический HEAVY_SLOT_MEMINFO — режим проб: бюджет ≤ $(mib "$PROBE_MIB") (здесь $(mib "$BUDGET")), сторож раз в 1–2 с (здесь «$GUARD_S»). Настоящий прогон — без HEAVY_SLOT_MEMINFO и ручек"
        exit 64
    fi
fi
if [ "$BUDGET" -gt "$LIMIT_MIB" ]; then
    say "бюджет $(mib "$BUDGET") больше потолка машины $(mib "$LIMIT_MIB") — такой слот не выдаётся никогда"
    exit 64
fi

# Перенос процесса в другой unit уводит команду из cgroup слота: предел ядра до
# неё не дотянулся бы (опыт ws#832, круг 3). Судятся слова argv, в том числе
# строка `bash -c "…"`; граница — в шапке.
for a in "$@"; do
    if [[ "$a" =~ (^|[^A-Za-z0-9_.-])(systemd-run|--scope)($|[^A-Za-z0-9_.-]) ]]; then
        say "команда несёт «${BASH_REMATCH[2]}» — перенос в другой unit уводит её из cgroup слота, и предел $(mib "$BUDGET") до неё не дотянется. Слот сам ставит scope с пределом: heavy-slot.sh $CLASS -- <команда без systemd-run>"
        exit 64
    fi
done

ID="$(now)-$$"
P="$DIR/active/$ID"
UNIT="heavy-slot-$CLASS-$$-$(now).scope"
CMD=("$@")

# docker первым словом — через ту же подмену, что и внутри команды; флаги
# памяти у вызова — отказ ДО очереди, а не после получаса ожидания.
SELF="$(readlink -f -- "${BASH_SOURCE[0]}")"
REAL_DOCKER="${HEAVY_SLOT_REAL_DOCKER:-$(command -v docker 2>/dev/null)}"
if [ "$(basename -- "${CMD[0]}")" = docker ]; then
    docker_limit "$BUDGET" - "${CMD[@]:1}" || exit 64
    [ "${CMD[0]}" = docker ] || REAL_DOCKER="${CMD[0]}"
    [ -n "$REAL_DOCKER" ] && CMD[0]="$P.bin/docker"
fi

if ! { mkdir -p "$DIR/active" && touch "$DIR/journal.log" "$DIR/lock"; } 2>/dev/null; then
    say "каталог слотов $DIR недоступен на запись — слот не выдан (не выполнилось)"; exit 69
fi
command -v flock >/dev/null || { say "нет flock — вход без замка повторил бы исходный отказ (не выполнилось)"; exit 69; }
[ -n "$(used_mib)" ] || { say "не прочитать MemTotal/MemAvailable из $MEMINFO (не выполнилось)"; exit 69; }

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
printf 'pid=%s\npid_start=%s\nclass=%s\nbudget=%s\nlimit=%s\nmeminfo=%s\nwho=%s\n' "$$" "$(pid_start $$)" "$CLASS" "$BUDGET" "$LIMIT_MIB" "$MEMINFO" "$WHO" > "$TICKET"
unlock
trap 'rm -f "$TICKET"' EXIT
t0="$(now)"; waited=0
while :; do
    lock
    reap
    held="$(exclusive_holder)"
    ahead=0; aside=0; smib="$(slots_mib)"
    for f in "$DIR"/queue/*; do
        [ -e "$f" ] || continue
        if [ "$(pid_start "$(field "$f" pid)")" != "$(field "$f" pid_start)" ]; then
            journal "reap ticket=$(basename "$f") class=$(field "$f" class) pid=$(field "$f" pid)"; rm -f "$f"; continue
        fi
        [[ "$f" < "$TICKET" ]] || continue
        # Ждущий исключительного класса при занятом линтере очередь не держит:
        # иначе десять минут ci-local стояли бы и newman, и go-race за ним.
        if [ -n "$held" ] && is_exclusive "$(field "$f" class)"; then continue; fi
        # Не влезет под свой потолок и при пустых слотах — ждёт не очереди.
        tu="$(used_mib "$(field "$f" meminfo)")"
        tb=$(( ${tu:-0} - smib )); [ "$tb" -gt 0 ] || tb=0
        if [ -z "$tu" ] || [ $(( tb + $(field "$f" budget) )) -gt "$(field "$f" limit)" ]; then
            aside=$(( aside + 1 )); continue
        fi
        ahead=$(( ahead + 1 ))
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
    [ "$aside" -gt 0 ] && why="$why; впереди $aside не влезут под свой потолок и при пустых слотах — голову не держат"
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
# kill_containers — снять контейнеры слота: они потомки dockerd, и смерть
# клиента их не останавливает.
kill_containers() {
    local c
    for c in $(slot_cids "$P"); do docker kill "$c" >/dev/null 2>&1; done
}
# shellcheck disable=SC2329  # зовётся ловушкой
cleanup() {
    [ -n "$WPID" ] && kill "$WPID" 2>/dev/null
    rm -rf "$P".*
}
# shellcheck disable=SC2329  # зовётся ловушкой
on_signal() {
    if [ -n "$UNIT" ] && systemctl --user kill --signal=SIGTERM "$UNIT" 2>/dev/null; then
        for _ in 1 2 3 4 5 6; do systemctl --user is-active --quiet "$UNIT" 2>/dev/null || break; sleep 0.5; done
        systemctl --user kill --signal=SIGKILL "$UNIT" 2>/dev/null
    fi
    [ -n "$RPID" ] && kill "$RPID" 2>/dev/null
    [ -n "$CPID" ] && tree_kill "$CPID"
    kill_containers
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

# watcher <root pid, если предел мягкий> — сторож машины, пик контейнеров,
# мягкий предел запасного пути. Пишет только в свои файлы записи слота.
watcher() {
    local root="${1:-}" used cid cpeak=0 v rss
    while [ -e "$P.slot" ]; do
        v=0
        for cid in $(slot_cids "$P"); do
            v=$(( v + $(cg_bytes "$CGROOT/system.slice/docker-$cid.scope/memory.peak") ))
        done
        [ "$v" -gt "$cpeak" ] && cpeak="$v" && echo "$cpeak" > "$P.cpeak"
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
            kill_containers
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

# Окружение команды: `docker` из PATH — эта же программа, она ставит предел.
CENV=()
if [ -n "$REAL_DOCKER" ] && mkdir -p "$P.bin" && ln -sf "$SELF" "$P.bin/docker"; then
    CENV=(HEAVY_SLOT_P="$P" HEAVY_SLOT_B="$BUDGET" HEAVY_SLOT_REAL_DOCKER="$REAL_DOCKER" PATH="$P.bin:$PATH")
fi

t_run="$(now)"; rc=0
if [ "$LIMITER" != watch ] && command -v systemd-run >/dev/null; then
    watcher & WPID=$!
    # Фоном и через wait: ловушка сигнала срабатывает посреди wait, а не после
    # выхода команды переднего плана — иначе TERM слоту ждал бы конца прогона.
    env "${CENV[@]}" systemd-run --user --scope --quiet --collect --expand-environment=no --unit="$UNIT" \
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
    env "${CENV[@]}" "${CMD[@]}" 0<&0 & CPID=$!
    watcher "$CPID" & WPID=$!
    wait "$CPID"; rc=$?
fi
kill "$WPID" 2>/dev/null; wait "$WPID" 2>/dev/null; WPID=""
dur=$(( $(now) - t_run ))

# ── итог ─────────────────────────────────────────────────────────────────────
peak=0; oom=0; cpeak=0; coom=0; cut_by=""; alive=""
if { read -r KIND _ peak oom < "$P.res"; } 2>/dev/null && [ "$KIND" = rc ]; then :; else peak=0; oom=0; fi
[ -s "$P.cpeak" ] && cpeak="$(cat "$P.cpeak")"
cids="$(slot_cids "$P")"
if [ -n "$cids" ]; then
    filt=(); for c in $cids; do filt+=(--filter "container=$c"); done
    docker events --since "$(( t_run - 5 ))" --until "$(( $(now) + 1 ))" "${filt[@]}" \
        --filter event=oom --format '{{.Action}}' 2>/dev/null | grep -q oom && coom=1
fi
[ "${oom:-0}" -gt 0 ] && cut_by="OOM в cgroup слота (oom_kill=$oom)"
[ "$coom" -gt 0 ] && cut_by="OOM контейнера (--memory=$(mib "$BUDGET"))"
[ -s "$P.soft" ] && cut_by="мягкий предел: $(cat "$P.soft") > бюджета"
[ -s "$P.guard" ] && cut_by="сторож машины: $(cat "$P.guard") > потолка $(mib "$LIMIT_MIB"), слот младший"
if [ -z "$cut_by" ] && [ ! -s "$P.res" ] && [ "$LIMITER" != watch ]; then
    say "итог слота не записан: дерево команды убито целиком снаружи (сигнал либо systemd-oomd), код $rc"
fi
# Оборванная команда не оставляет контейнеров: клиент снят, а контейнер — потомок
# dockerd и жил бы дальше. «Оборвана» говорится, только если остановлены и они.
if [ -n "$cut_by" ]; then
    for c in $cids; do
        [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" = true ] || continue
        docker kill "$c" >/dev/null 2>&1
        for _ in 1 2 3 4 5; do [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" = true ] || break; sleep 1; done
        [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" = true ] && alive="$alive ${c:0:12}"
    done
fi
peak_mib=$(( peak / 1024 / 1024 )); cpeak_mib=$(( cpeak / 1024 / 1024 ))
[ "$LIMITER" = watch ] && peak_mib="$(cat "$P.rsspeak" 2>/dev/null || echo 0)"
journal "leave id=$ID class=$CLASS budget=${BUDGET}MiB rc=$rc peak=${peak_mib}MiB container_peak=${cpeak_mib}MiB containers=$(printf '%s' "$cids" | grep -c .) limiter=${LIMITER/auto/systemd} dur=${dur}s cut=${cut_by:-—}${alive:+ alive=${alive# }} who=$WHO"
if [ -n "$alive" ]; then
    say "НЕ ВЫПОЛНИЛОСЬ — $cut_by: клиент снят, но контейнер(ы)$alive РАБОТАЮТ, docker kill их не остановил; память не освобождена — docker kill$alive"
    exit 76
fi
if [ -n "$cut_by" ]; then
    say "НЕ ВЫПОЛНИЛОСЬ — команда оборвана пределом памяти: $cut_by; код команды $rc${cids:+; контейнеры слота остановлены}."
    say "это исчерпание ресурса, а не красное: вердикта по предмету нет. Бюджет класса «$CLASS» — $(mib "$BUDGET"); пик — в журнале $DIR/journal.log"
    exit 76
fi
exit "$rc"
}
