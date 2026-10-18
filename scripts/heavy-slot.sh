#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# heavy-slot.sh — тяжёлый прогон входит в машину только через слот памяти.
#
# ПРЕДМЕТ. Решение владельца 2026-09-24: «контроль за оперативной памятью не
# должна переваливать за 45гб»; 2026-10-02 — «я расширил память еще на 32»: всего
# ≤ 70 ГБ, тяжёлое — 3 слота по 10 ГБ, старт при свободных ≥ 15 ГБ (ws#1087). Повод: машина упала по памяти — полосы разом
# подняли -race в docker, testcontainers и стенд kind, и каждая по отдельности
# видела «памяти хватает». Отказ был в МОМЕНТЕ: «хватает ли» и «занял» — два
# шага, между ними проходили соседи, а вошедший секунду назад памяти ещё не набрал.
#
# ФОРМА
#   heavy-slot.sh [--wait N] [--resume <билет>] [--local "<причина>"] <класс> -- <команда> …   (занято — 74 сразу)
#   heavy-slot.sh --enqueue <каталог> [--local "<причина>"] <класс> -- <команда> …   (поставить ОДИН раз, ниже)
#   heavy-slot.sh --classes     классы, бюджеты и основание каждого
#   heavy-slot.sh --budget <класс>  бюджет класса в МиБ (читает session-memcap.sh)
#   heavy-slot.sh --status      занятые слоты, память машины, хвост журнала
#   heavy-slot.sh --prune-tmp   снять TMPDIR копий класса ci-local, не тронутые > 7 суток
#
# ВХОД — строгая очередь по билету под flock на каталоге слотов, ОДНОМ на машину;
# условий четыре, все разом:
#   (MemTotal − MemAvailable) + недобранное занятыми + бюджет ≤ потолок 70 ГиБ;
#   MemAvailable − недобранное ≥ 15 ГиБ (свободные до старта);
#   занятых слотов < 3; Σ бюджетов занятых + бюджет ≤ 3 × 10 ГиБ.
# Недобранное = Σ max(0, бюджет − текущая память) по занятым слотам (memory.current
# их cgroup, их контейнеров и cgroup, куда их команда ушла сама — ниже). Без этого
# слагаемого вход повторял бы исходный отказ.
# Ушедшая сама cgroup: команда слота переносит себя `systemd-run --scope` изнутри
# скрипта (хук kaname, scripts/hooks/pre-push:194, MemoryMax=10G). Её pid остаётся
# потомком корня слота, а память — в чужой scope: cgroup слота показывала ≈ 1 МиБ при
# пике scope 3 ГиБ, и бюджет резервировался дважды. Своей считается cgroup, где есть
# потомок корня слота и нет ни одного чужого процесса; её память — память слота, сторож
# машины снимает её вместе со слотом. Предела слота у неё нет: держит её свой предел.
# Места нет — СРАЗУ код 74 «слот занят, очередь K» (ws#1004, решение владельца
# 2026-10-11 «максимальная оперативность и минимум простоя»: ожидание слота в переднем
# плане — 116,4 агент-ч замера ws#1001). Билет при этом снимается: очередь держит лишь
# тот, кто ждёт явно — `--wait N`, N ≤ 300 с, опрос раз в 30 с, по истечении код 75.
# Ждать дольше 300 с — `--enqueue <каталог>`: слот сам уходит в отсоединённый прогон
# (setsid, env --default-signal=PIPE) и ждёт ОДНИМ билетом до 2 ч, вызов сразу печатает
# строку ENQUEUED с pid, журналом и .rc — имена уникальны (класс, время, pid), .rc
# снимается до запуска; исход дочитывает короткий шаг. Повтор без билета ставит в КОНЕЦ
# очереди: 2026-10-16 так пять попыток newman за час слота не получили (урок ws#1110).
# Поэтому 74 и 75 ОТКЛАДЫВАЮТ билет на 120 с и называют его: повтор `--resume <билет>`
# того же класса встаёт на прежнее место — впереди вставших позже (ws#1115). Отложенный
# билет без владельца голову не держит (свободный слот не простаивает) и снимается по
# сроку; просроченный, чужого класса или неизвестный — в конец, это сказано. Голову очереди держит лишь
# билет, который влез бы под СВОЙ потолок, будь занятые слоты пусты: (MemTotal −
# MemAvailable) − память слотов + бюджет ≤ потолок билета. Прочий ждёт памяти не
# от слотов — её очередь не освободит, и держать за ним соседей незачем (опыт ws#832,
# круг 3: потолок 1 ГиБ на 99999 с стоял головой строгой очереди).
# Потолок — в ГиБ, в тех единицах, что печатает `free -g` (MemTotal здесь 92,2).
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
# РУЧКИ HEAVY_SLOT_*. Над настоящей памятью (/proc/meminfo) ручек нет: потолок 70 ГиБ,
# ожидание — только явным --wait ≤ 300 с, общий каталог, бюджет, ограничитель и сторож — как в классе; любая
# ручка — 64 до первой записи (опыт ws#832, круги 2–3: переменная снимала потолок или
# очередь). Ручки — только режиму проб, синтетическому HEAVY_SLOT_MEMINFO в своём
# каталоге, и тяжёлым прогоном он быть не способен: бюджет ≤ 512 МиБ, сторож раз в 1–2 с. Страж видит
# ручки лишь в строке команды, скрипт с ними он пропускает — их держит слот. Сторож
# машины в режиме проб судит синтетическую память: docker мимо подмены (абсолютный
# путь, API) под ним без предела.
#
# КОДЫ: код команды, если она исполнилась; 64 — вызов неверен; 69 — механизм
# недоступен; 74 — слот занят, ожидания не было (очередь K названа); 75 — слот не
# выдан за --wait N; 76 — команда оборвана пределом памяти; 77 — кластер доступен, и
# команде место там: локально она не запускалась, текст «во внешний кластер: <как>».
# 69, 74, 75, 76 и 77 — «не выполнилось», а не красное: вердикта по предмету команды
# нет. Своё слово слот печатает строкой «heavy-slot: …» в stderr.
#
# ВНЕШНИЙ КЛАСТЕР (ws#984, ws#1105; норма — testing-verdict.md#external-cluster-first):
# классы go-race, integration, lint и ci-local при отвечающем кластере уходят Job-ом
# в scripts/remote-heavy/run.sh и слота машины не занимают; код — код команды там.
# Локальный подъём стенда и неопознанная нагрузка при отвечающем кластере — 77;
# кластер занят — 74/75, локально не идёт. Локально — с причиной в журнале
# (local … why=…, при недоступном — и proof=… вывода проверки), либо флагом --local
# с причиной (bypass-local, «локально по флагу» в --status); условия — у блока
# «внешний кластер» ниже.
#
# ХУК ОТПРАВКИ (ws#1106, ws#1115): `git push` классом ci-local в клоне продукта при
# принимающем кластере идёт без слота машины: git звано с core.hooksPath на переходник,
# чей pre-push отдаёт вход git (строки отправки) настоящему хуку клона
# (scripts/hooks/pre-push отправляемой головы) Job-ом run.sh профиля ci-local; локально —
# лишь сама отправка, итог хука — тот же контракт, код хука там — код отправки. Вход git
# уходит и в run.sh (--push-input): по нему Job ставит зависимости консоли до хука,
# когда правка её трогает (ws#1115, ЗАВИСИМОСТИ КОНСОЛИ в шапке run.sh). Прочие
# хуки клона переходник берёт ссылками. Отправка не головы копии (иная вершина, их
# несколько) переходник отклоняет кодом 78, и слот гонит ту же команду локально с
# причиной; Job не состоялся (69, 75) — тот код, «не выполнилось».
#
# ЖУРНАЛ: $HEAVY_SLOT_DIR/journal.log — вход, ожидание (занято слотов, свободно), уход
# во внешний кластер (remote … до запуска Job), выход с пиком памяти, обрыв. Пик —
# основание для пересмотра бюджетов: `grep ' leave ' journal.log`.
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
CAP_MIB=71680       # 70 ГиБ — решение владельца 2026-10-02 (было 45 — 2026-09-24)
SLOTS_MAX=3         # тяжёлое — 3 слота по 10 ГБ (2026-10-02)
SLOTS_SUM_MIB=30720 # Σ бюджетов занятых ≤ 3 × 10 ГиБ: go-race (16 ГиБ) берёт место полутора
FREE_MIN_MIB=15360  # старт при свободных ≥ 15 ГБ (2026-10-02)
PROBE_MIB=512  # потолок бюджета в режиме проб: пробы берут ≤ 301 МиБ
# Рабочие величины; ручки HEAVY_SLOT_* их меняют только в режиме проб (ниже).
RESUME_TTL_S=120  # срок отложенного билета 74/75 (ws#1115)
LIMIT_MIB="$CAP_MIB"; POLL_S=30; WAIT_S=0; WAIT_MAX_S=300; ENQ_MAX_S=7200; GUARD_S=2; GRACE_S=10; LIMITER=auto
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

# docker_mem_bytes <значение> — байты величины памяти docker (форма RAMInBytes:
# число, дробь — тоже, суффикс b k m g t p, двоичные кратные, «i» и «b» после
# — необязательны). Не разобрано — код 1: такую величину слот не судит и не отдаёт.
docker_mem_bytes() {
    awk -v v="$1" 'BEGIN {
        if (v !~ /^[0-9]+(\.[0-9]+)? ?[kKmMgGtTpP]?[iI]?[bB]?$/) exit 1
        n = v; sub(/ ?[kKmMgGtTpP]?[iI]?[bB]?$/, "", n)
        u = substr(v, length(n) + 1); gsub(/[ iIbB]/, "", u); u = tolower(u)
        p = index("kmgtp", u); m = 1; if (u != "") for (q = 0; q < p; q++) m *= 1024
        printf "%.0f\n", n * m
    }'
}

# docker_limit <бюджет MiB> <cidfile> <аргументы docker…> — в DARGS аргументы, где
# run/create (и container run/create) несут предел бюджета; прочее — как было.
# Свой предел вызова (--memory, -m, --memory-swap) — законен, если он не больше
# бюджета класса: тогда он и остаётся пределом контейнера, второго значения слот
# не пишет (docker взял бы последнее, и одно молча перекрыло бы другое), а
# недостающую половину дописывает — swap = память вызова (сверх неё swap нет),
# память = swap вызова. Предел больше бюджета, 0 и -1 (без предела), неразобранная
# величина и свой --cidfile (по нему слот снимает контейнер) — код 64 с причиной.
# Основание — ws#1110: стенд kaname (`.github/scripts/stand-own.sh`) ставит
# службе --memory 1280m, законный в конвейере флаг, а отказ 64 ронял подъём стенда.
docker_limit() {
    local budget="$1" cidf="$2" i=0 sub at j a w k step v="" mem="" swap="" b lim
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
        a="${DARGS[$j]}"; w="$a"
        case "$a" in
            --cidfile|--cidfile=*)
                say "docker $sub несёт «$a» — слот ставит --cidfile сам (по нему он снимает контейнер); сними флаг"
                return 64 ;;
            --memory|--memory-swap) v="${DARGS[$(( j + 1 ))]:-}"; j=$(( j + 2 )) ;;
            --memory=*|--memory-swap=*) v="${a#*=}"; a="${a%%=*}"; j=$(( j + 1 )) ;;
            --) break ;;
            --*=*) j=$(( j + 1 )) ;;
            --rm|--detach|--interactive|--tty|--init|--privileged|--read-only|--publish-all|--oom-kill-disable|--no-healthcheck|--quiet|--disable-content-trust|--use-api-socket|--help)
                j=$(( j + 1 )) ;;
            --*) j=$(( j + 2 )) ;;
            -?*)
                # Короткие флаги склеиваются (-dm 1g, -dm1g, -m=1g): значение берёт
                # первая буква со значением, остаток слова либо следующее слово.
                k=1; step=1
                while [ "$k" -lt "${#a}" ]; do
                    case "${a:$k:1}" in
                        m)
                            if [ "$k" -eq $(( ${#a} - 1 )) ]; then v="${DARGS[$(( j + 1 ))]:-}"; step=2
                            else v="${a:$(( k + 1 ))}"; v="${v#=}"; fi
                            a=--memory; break ;;
                        [acehlpuvw]) [ "$k" -eq $(( ${#a} - 1 )) ] && step=2; break ;;
                    esac
                    k=$(( k + 1 ))
                done
                j=$(( j + step )) ;;
            *) break ;;
        esac
        case "$a" in
            --memory|--memory-swap)
                lim="$(mib "$budget")"
                if [ "$v" = -1 ]; then b=0; else b="$(docker_mem_bytes "$v")" || b=x; fi
                case "$b" in
                    x) say "docker $sub несёт «$w» со значением «$v», которое не разбирается как величина памяти; бюджет класса $lim"; return 64 ;;
                    0) say "docker $sub несёт «$w» со значением «$v» — это предел «без предела»; законен предел не больше бюджета класса $lim"; return 64 ;;
                esac
                if [ "$b" -gt $(( budget * 1048576 )) ]; then
                    say "docker $sub несёт «$w» со значением «$v» — больше бюджета класса $lim; законен предел не больше бюджета"
                    return 64
                fi
                if [ "$a" = --memory ]; then mem="$v"; else swap="$v"; fi ;;
        esac
    done
    local add=()
    if [ -z "$mem" ] && [ -z "$swap" ]; then add=("--memory=${budget}m" "--memory-swap=${budget}m")
    elif [ -z "$swap" ]; then add=("--memory-swap=$mem")
    elif [ -z "$mem" ]; then add=("--memory=$swap"); fi
    DARGS=("${DARGS[@]:0:$at}" "${add[@]}" "--cidfile=$cidf" "${DARGS[@]:$at}")
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
    printf 'потолок машины: %s — (MemTotal − MemAvailable) + недобранное + бюджет; свободных до старта ≥ %s; слотов ≤ %s, Σ бюджетов ≤ %s\n' \
        "$(mib "$LIMIT_MIB")" "$(mib "$FREE_MIN_MIB")" "$SLOTS_MAX" "$(mib "$SLOTS_SUM_MIB")"
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

# avail_mib [meminfo] — MemAvailable в MiB; пусто, если не прочитать.
avail_mib() {
    awk '/^MemAvailable:/ { printf "%d\n", $2 / 1024 }' "${1:-$MEMINFO}" 2>/dev/null
}

cg_bytes() { local v; v="$(cat "$1" 2>/dev/null)" && [ -n "$v" ] && printf '%s\n' "$v" || echo 0; }

# field <файл> <ключ> — значение key=value из записи слота.
field() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n 1; }

# slot_cids <префикс записи> — контейнеры, созданные командой слота, по строке.
slot_cids() {
    local f
    for f in "$1".cid.d/*; do [ -s "$f" ] && printf '%s\n' "$(cat "$f")"; done
}

# slot_escaped <префикс записи> — cgroup, куда команда слота ушла сама: в ней есть
# потомок корня слота ($p.root) и нет чужих процессов. Пути — по строке. У запасного
# пути (cgroup слота нет) пусто: RSS дерева уже считает этих потомков.
slot_escaped() {
    local p="$1" root cg d c pid own
    root="$(cat "$p.root" 2>/dev/null)"; cg="$(cat "$p.cg" 2>/dev/null)"
    [ -n "$root" ] && [ -n "$cg" ] || return 0
    d=" $(ps -e -o pid=,ppid= 2>/dev/null | awk -v root="$root" '{ par[$1] = $2 }
        END { for (p in par) { q = p; while (q != "" && q != 0 && q != 1) { if (q == root) { printf "%s ", p; break } q = par[q] } } }')"
    for c in $(for pid in $d; do sed -n 's/^0:://p' "/proc/$pid/cgroup" 2>/dev/null; done | sort -u); do
        { [ "$c" = "$cg" ] || [[ "$c" == "$cg"/* ]]; } && continue
        own=1
        while read -r pid; do [[ "$d" == *" $pid "* ]] || { own=0; break; }; done < "$CGROOT$c/cgroup.procs"
        [ "$own" = 1 ] && printf '%s\n' "$c"
    done
}

# kill_escaped <префикс записи> — снять ушедшие сами cgroup слота (cgroup.kill).
kill_escaped() {
    local c
    for c in $(slot_escaped "$1"); do echo 1 > "$CGROOT$c/cgroup.kill" 2>/dev/null; done
}

# slot_current_mib <префикс записи> — текущая память слота: его cgroup, ушедшие сами
# cgroup, его контейнеры, либо RSS дерева по отчёту сторожа запасного пути.
slot_current_mib() {
    local p="$1" b=0 cg cid rss x
    cg="$(cat "$p.cg" 2>/dev/null)"
    [ -n "$cg" ] && b=$(( b + $(cg_bytes "$CGROOT$cg/memory.current") ))
    for x in $(slot_escaped "$p"); do b=$(( b + $(cg_bytes "$CGROOT$x/memory.current") )); done
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

# Класс lint — по одному на машину: общий кэш и замок линтера (второй ждёт или падает
# «parallel golangci-lint is running», код 3). Замок лежит в TMPDIR, кэш ci-local
# ставит на копию (kacho scripts/ci-local.sh, kaname pre-push), поэтому ci-local
# исключителен лишь по TMPDIR — и слот даёт ему свой, постоянный на копию (ws#1087).
EXCLUSIVE=" lint "
is_exclusive() { [[ "$EXCLUSIVE" == *" $1 "* ]]; }
exclusive_holder() {
    local f c
    for f in "$DIR"/active/*.slot; do
        [ -e "$f" ] || continue
        c="$(field "$f" class)"
        is_exclusive "$c" && { printf '%s pid %s\n' "$c" "$(field "$f" pid)"; return; }
    done
}

# occupied — «<число занятых> <Σ их бюджетов MiB>».
occupied() {
    local f n=0 sum=0
    for f in "$DIR"/active/*.slot; do
        [ -e "$f" ] || continue
        n=$(( n + 1 )); sum=$(( sum + $(field "$f" budget) ))
    done
    echo "$n $sum"
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
    printf 'потолок %s · занято машиной %s · недобрано слотами %s · свободно %s (вход от %s) · слотов, Σ бюджетов: %s из %s, %s\n' \
        "$(mib "$LIMIT_MIB")" "$(mib "${used:-0}")" "$(mib "$(reserved_mib)")" "$(mib "$(avail_mib)")" "$(mib "$FREE_MIN_MIB")" \
        "$(occupied | cut -d' ' -f1)" "$SLOTS_MAX" "$(mib "$SLOTS_SUM_MIB")"
    for f in "$DIR"/active/*.slot; do
        [ -e "$f" ] || continue
        p="${f%.slot}"
        printf '  %-11s бюджет %-9s сейчас %-9s pid %-8s с %s  %s\n    %s\n' \
            "$(field "$f" class)" "$(mib "$(field "$f" budget)")" "$(mib "$(slot_current_mib "$p")")" \
            "$(field "$f" pid)" "$(date -d "@$(field "$f" start)" +%H:%M:%S)" "$(field "$f" who)" \
            "$(field "$f" cmd | cut -c1-160)"
        [ -n "$(field "$f" local)" ] && printf '    локально %s\n' "$(field "$f" local | cut -c1-200)"
    done
    for f in "$DIR"/queue/*; do
        [ -e "$f" ] || continue
        if [ -n "$(field "$f" resume_until)" ]; then
            printf '  отложен: %-8s билет %s до %s (--resume)  %s\n' "$(field "$f" class)" "$((10#${f##*/}))" "$(date -d "@$(field "$f" resume_until)" +%H:%M:%S)" "$(field "$f" who)"
            continue
        fi
        printf '  ждёт: %-11s бюджет %-9s pid %-8s %s\n' "$(field "$f" class)" "$(mib "$(field "$f" budget)")" "$(field "$f" pid)" "$(field "$f" who)"
    done
    if [ -f "$DIR/journal.log" ]; then
        # Обходы внешнего кластера флагом видны отдельно: в хвосте из 10 строк их
        # вытеснили бы входы и выходы соседей (ws#1105).
        local nb
        nb="$(grep -c ' bypass-local ' "$DIR/journal.log")"
        [ "${nb:-0}" -gt 0 ] && { echo "локально по флагу --local (обход внешнего кластера), всего $nb, последние 5:"; grep ' bypass-local ' "$DIR/journal.log" | tail -n 5 | cut -c1-220; }
        echo "журнал ($DIR/journal.log), последние 10:"; tail -n 10 "$DIR/journal.log" | cut -c1-220
    fi
}

# TMPDIR класса ci-local — постоянный, свой на копию (ws#1087). Ключ — путь корня
# копии git (вне копии — рабочий каталог); метка времени каталога — последний вход
# слота. Снимает его prune_tmp: не занят ни одним слотом и не тронут дольше
# TMP_KEEP_D суток. Каталог — вне всякого репозитория: pre-push kaname отказывает
# кодом 2, когда TMPDIR лежит внутри дерева (scripts/hooks/pre-push:434).
TMPROOT="$DIR/tmp"; TMP_KEEP_D=7
copy_key() {
    local top
    top="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)" || top="$PWD"
    printf '%s' "$top" | sha256sum | cut -c1-16
}
# prune_tmp — снять TMPDIR копий старше срока; занятые слотами не трогает.
prune_tmp() {
    local d f busy
    for d in "$TMPROOT"/*; do
        [ -d "$d" ] || continue
        busy=""
        for f in "$DIR"/active/*.slot; do
            [ -e "$f" ] && [ "$(field "$f" tmp)" = "$d" ] && busy=1 && break
        done
        [ -n "$busy" ] && continue
        [ -n "$(find "$d" -maxdepth 0 -mmin +$(( TMP_KEEP_D * 1440 )) 2>/dev/null)" ] || continue
        rm -rf -- "$d" "$d.copy"
        journal "prune-tmp dir=$d keep=${TMP_KEEP_D}d"
    done
}

# ── разбор вызова ────────────────────────────────────────────────────────────
# --wait N — единственное ожидание слота, явное и ≤ 300 с (ws#1004); без него занятый
# слот — код 74 сразу. Значение судится до класса: «--wait 2400» — 64, а не полчаса.
# --local "<причина>" — обход внешнего кластера (ws#1105): маршрут не судится, причина
# пишется в журнал строкой bypass-local и видна в --status. Причина — не короче 12
# символов: пустой обход был бы тем же молчаливым «локально».
# --enqueue <каталог> — поставить в очередь ОДИН раз отсоединённо (шапка); --queued <база> —
# его внутренняя форма: принимается лишь у ребёнка --enqueue (stdout — <база>.log, родитель —
# лидер своего сеанса), иначе 64.
# --resume <билет> — повтор после 74/75 на месте отложенного билета (шапка, ws#1115).
WAIT_ARG=""; LOCAL_WHY=""; LOCAL_SET=""; ENQ_DIR=""; QUEUED=""; RESUME=""
while :; do
    case "${1:-}" in
        --resume)
            RESUME="${2:-}"
            [[ "$RESUME" =~ ^[0-9]{1,12}$ ]] || { say "--resume «$RESUME» — номер билета из отказа 74/75 (целое)"; exit 64; }
            RESUME=$((10#$RESUME)); shift 2 ;;
        --enqueue)
            ENQ_DIR="${2:-}"
            if [ -z "$ENQ_DIR" ] || ! [ -d "$ENQ_DIR" ] || ! [ -w "$ENQ_DIR" ]; then
                say "--enqueue «$ENQ_DIR» — каталог журналов, существующий и доступный на запись: журнал, .rc и pid задания — в нём"
                exit 64
            fi
            shift 2 ;;
        --queued) QUEUED="${2:-}"; shift 2 ;;
        --wait)
            WAIT_ARG="${2:-}"
            if ! [[ "$WAIT_ARG" =~ ^[0-9]+$ ]] || [ "$WAIT_ARG" -gt "$WAIT_MAX_S" ]; then
                say "--wait «$WAIT_ARG» — целое от 0 до $WAIT_MAX_S с: дольше вызов не ждёт (CLAUDE.md «Не жди», ws#1004); долгое — отсоединённо, повтор — коротким шагом"
                exit 64
            fi
            shift 2 ;;
        --local)
            LOCAL_SET=1; LOCAL_WHY="$(printf '%s' "${2:-}" | tr '[:cntrl:]' ' ')"
            if [ "${#LOCAL_WHY}" -lt 12 ]; then
                say "--local «$LOCAL_WHY» — обход внешнего кластера только с причиной (≥ 12 символов): она пишется в журнал и видна в --status (ws#1105)"
                exit 64
            fi
            shift 2 ;;
        *) break ;;
    esac
done
case "${1:-}" in
    --classes) print_classes; exit 0 ;;
    --budget)  class_budget "${2:-}" || { say "класса «${2:-}» нет"; exit 64; }; exit 0 ;;
    --status)  mkdir -p "$DIR/active" 2>/dev/null; print_status; exit 0 ;;
    --prune-tmp)
        { mkdir -p "$DIR/active" && touch "$DIR/lock"; } 2>/dev/null || { say "каталог слотов $DIR недоступен на запись"; exit 69; }
        exec {LK}>>"$DIR/lock"; flock -w 120 "$LK" || { say "замок $DIR/lock не взят за 120 с"; exit 69; }
        prune_tmp; exit 0 ;;
    ''|-h|--help)
        sed -n '14,19p' "$0" >&2; exit 64 ;;
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

# Отправка слотом ci-local (урок 2026-10-16, ws#1110): git push открывает ssh ДО хука
# отправки, хук идёт минутами, и простаивающее соединение площадка снимает — push
# умирал PIPE кодом 141 уже после зелёного хука (журнал слотов: 26 из 26 таких выходов
# — после ≥ 368 с). Слот держит соединение живым, не трогая заданного вызывающим:
# GIT_SSH_COMMAND, GIT_SSH и core.sshCommand (любого слоя), если есть, сильнее: git
# предпочёл бы поставленный слотом GIT_SSH_COMMAND заданному вызывающим GIT_SSH.
if [ "$CLASS" = ci-local ] && [ -z "${GIT_SSH_COMMAND:-}" ] && [ -z "${GIT_SSH:-}" ] && [ -z "$(git -C "$PWD" config core.sshCommand 2>/dev/null)" ]; then
    export GIT_SSH_COMMAND="ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=40"
fi

# Ручки — до первой записи: отказ не оставляет следа в общем каталоге.
KNOBS="HEAVY_SLOT_LIMIT_GIB HEAVY_SLOT_LIMIT_MIB HEAVY_SLOT_WAIT_S HEAVY_SLOT_ENQ_S HEAVY_SLOT_POLL_S HEAVY_SLOT_BUDGET_MIB HEAVY_SLOT_LIMITER HEAVY_SLOT_GUARD_S HEAVY_SLOT_GUARD_GRACE_S HEAVY_SLOT_REMOTE_RUN HEAVY_SLOT_SLOTS_SUM_MIB"
if [ "$MEMINFO" = /proc/meminfo ]; then
    knob=""
    [ "$DIR" = "$SHARED" ] || [ "$DIR" -ef "$SHARED" ] || knob="свой каталог слотов $DIR — отдельная очередь, соседей общей он не видит"
    for v in $KNOBS; do
        [ -n "${!v+x}" ] && knob="$v=${!v} — потолок 70 ГиБ, ожидание (только --wait ≤ $WAIT_MAX_S с), бюджет и сторож класса не переопределяются"
    done
    if [ -n "$knob" ]; then
        say "над настоящей памятью машины ручка не принимается: $knob. Решения владельца 2026-09-24 и 2026-10-02 — ≤ 70 ГиБ на машину; ручки — только пробам над синтетическим HEAVY_SLOT_MEMINFO"
        exit 64
    fi
else
    if [ "$DIR" = "$SHARED" ] || [ "$DIR" -ef "$SHARED" ]; then
        say "синтетический HEAVY_SLOT_MEMINFO — режим проб, и он идёт только в своём каталоге (HEAVY_SLOT_DIR): в общей очереди билет пробы стоял бы среди настоящих"
        exit 64
    fi
    for v in $KNOBS; do
        [ "$v" = HEAVY_SLOT_LIMITER ] || [ "$v" = HEAVY_SLOT_REMOTE_RUN ] || [ -z "${!v+x}" ] || [[ "${!v}" =~ ^[0-9]+$ ]] || { say "$v=«${!v}» — не число"; exit 64; }
    done
    LIMIT_MIB="${HEAVY_SLOT_LIMIT_MIB:-$(( ${HEAVY_SLOT_LIMIT_GIB:-$(( CAP_MIB / 1024 ))} * 1024 ))}"
    POLL_S="${HEAVY_SLOT_POLL_S:-$POLL_S}"; WAIT_S="${HEAVY_SLOT_WAIT_S:-$WAIT_S}"; ENQ_MAX_S="${HEAVY_SLOT_ENQ_S:-$ENQ_MAX_S}"
    [ "$WAIT_S" -le "$WAIT_MAX_S" ] || { say "HEAVY_SLOT_WAIT_S=$WAIT_S — больше $WAIT_MAX_S с не ждёт и проба"; exit 64; }
    GUARD_S="${HEAVY_SLOT_GUARD_S:-$GUARD_S}"; GRACE_S="${HEAVY_SLOT_GUARD_GRACE_S:-$GRACE_S}"
    LIMITER="${HEAVY_SLOT_LIMITER:-$LIMITER}"
    SLOTS_SUM_MIB="${HEAVY_SLOT_SLOTS_SUM_MIB:-$SLOTS_SUM_MIB}"
    if [ "$BUDGET" -gt "$PROBE_MIB" ] || ! [[ "$GUARD_S" =~ ^[12]$ ]]; then
        say "синтетический HEAVY_SLOT_MEMINFO — режим проб: бюджет ≤ $(mib "$PROBE_MIB") (здесь $(mib "$BUDGET")), сторож раз в 1–2 с (здесь «$GUARD_S»). Настоящий прогон — без HEAVY_SLOT_MEMINFO и ручек"
        exit 64
    fi
fi
# Явное --wait берёт верх над ручкой проб: оно часть формы вызова, а не ручка.
[ -n "$WAIT_ARG" ] && WAIT_S="$WAIT_ARG"
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

# ── постановка одним билетом (урок 2026-10-16, ws#1110; шапка) ──────────────────
if [ -n "$ENQ_DIR" ] && { [ -n "$WAIT_ARG" ] || [ -n "$QUEUED" ]; }; then
    say "--enqueue ждёт сам до $(( ENQ_MAX_S / 60 )) мин — --wait и --queued с ним не ставятся"
    exit 64
fi
if [ -n "$QUEUED" ]; then
    if [ "$(readlink -f "/proc/$$/fd/1" 2>/dev/null)" != "$(readlink -f "$QUEUED.log" 2>/dev/null)" ] ||
        [ "$(ps -o sid= -p "$PPID" 2>/dev/null | tr -d ' ')" != "$PPID" ]; then
        say "--queued — внутренняя форма --enqueue (отсоединённый ребёнок, вывод в <база>.log); вызывай --enqueue <каталог>"
        exit 64
    fi
    WAIT_S="$ENQ_MAX_S"
fi
if [ -n "$ENQ_DIR" ]; then
    SELF="$(readlink -f -- "${BASH_SOURCE[0]}")"
    EB="$(cd "$ENQ_DIR" && pwd -P)/hs-$CLASS-$(date +%Y%m%dT%H%M%S)-$$"
    rm -f -- "$EB.rc" "$EB.rc.tmp" "$EB.pid"
    fwd=(); [ -n "$LOCAL_SET" ] && fwd=(--local "$LOCAL_WHY")
    [ -n "$RESUME" ] && fwd+=(--resume "$RESUME")
    # shellcheck disable=SC2016  # строка дочерней оболочки, $1… раскрывает она
    # KACHO_DETACHED_UNTIL — срок билета для переписи застоя (ws#1154): предел ожидания
    # слота; сирота своей сессии в сроке не судится как застой.
    setsid -f env --default-signal=PIPE KACHO_DETACHED_UNTIL="$(( $(now) + ENQ_MAX_S ))" bash -c 'echo $$ > "$2.pid"; bash "$1" --queued "$2" "${@:3}"; rc=$?; printf "%s
" "$rc" > "$2.rc.tmp" && mv -f "$2.rc.tmp" "$2.rc"' \
        heavy-slot "$SELF" "$EB" "${fwd[@]+"${fwd[@]}"}" "$CLASS" -- "$@" > "$EB.log" 2>&1 < /dev/null ||
        { say "отсоединённый прогон не запущен (setsid) — не выполнилось"; exit 69; }
    printf 'ENQUEUED\tlog=%s\trc=%s\tpid=%s\tdeadline=%s\n' "$EB.log" "$EB.rc" "$EB.pid" "$(date -d "@$(( $(now) + ENQ_MAX_S ))" +%H:%M)"
    say "идёт: «$CLASS» поставлен в очередь ОДНИМ билетом до $(( ENQ_MAX_S / 60 )) мин; исход — код в $EB.rc (появится по выходу), журнал $EB.log. Дочитывает короткий шаг; повторно не ставить"
    exit 0
fi

# ── внешний кластер (решения владельца 2026-10-07, 2026-10-08, 2026-10-16; ws#984, ws#1105) ─
# Норма — testing-verdict.md#external-cluster-first; владелец 2026-10-16 дословно:
# «пропиши в рулах явно что тяжелые тесты только на внешнем кластере, если он
# недоступен тогда локально». Тяжёлые классы go-race, integration, lint и ci-local
# при отвечающем кластере уходят Job-ом туда (scripts/remote-heavy/run.sh) и слота
# машины не занимают. Нагрузка судится ЗА обёртками (env, nice, ionice, timeout,
# nohup, setsid, stdbuf, command, time — функция payload): обёртка тяжёлое локально не
# уводит. Удалённый прогон судит КОММИТ, поэтому условий пять: нагрузка переносима
# (go, make, линтеры, ci-local.sh), каталог — клон kacho, kaname или corelib,
# отслеживаемые файлы без правок, номер задачи — из KACHO_TASK либо ведущих цифр
# имени ветки, кластер принимает (`run.sh --available --profile <класс>`, ws#991).
# Без внешнего пути вообще — хук отправки (`git push`, ws#1106) и клон не продукта —
# локально с причиной, кластер не спрашивается. Устранимое вызывающим — правки, номер
# задачи, НЕОПОЗНАННАЯ нагрузка (строка `bash -c`, ключ обёртки вне разбора, иная
# команда) — при принимающем кластере 77 «во внешний кластер: <как>», команда не
# запускается: неопознанное тихо локально не идёт.
# Класс stand: подъём ЛОКАЛЬНОГО стенда (dev-up, dev-prod-up, own-up, stack-up,
# cert-manager-up, `kind … create`, create-cluster.sh любым путём — словом argv либо
# словом строки оболочки) и строка оболочки без внешней формы stand-ns-* при
# принимающем кластере — 77 с формой своего ns; прочие команды стенда (stand-ns-*,
# reload-svc, dev-down, helm идущего стенда) маршрут не судит.
# Проверка кластера — `timeout 10 run.sh --available`: current-context она не читает
# и не меняет (контекст — явный, шапка run.sh). Занят (75) — НЕ недоступен (решение
# диспетчера 2026-10-16): место ждётся до --wait N, затем 74 либо 75, локально не
# идёт. Не ответила (124) либо иной отказ — недоступен: локально, вывод проверки — в
# журнал строкой «local … proof=…». Причина КАЖДОГО локального запуска — в журнале
# («local … why=…»). Обход — только --local с причиной перед классом (bypass-local).
# В режиме проб маршрут судится лишь с HEAVY_SLOT_REMOTE_RUN — двойником run.sh; над
# настоящей памятью эта ручка — 64, как прочие.
REMOTE_RUN="$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/remote-heavy/run.sh"
REMOTE_ON=1
if [ "$MEMINFO" != /proc/meminfo ]; then
    if [ -n "${HEAVY_SLOT_REMOTE_RUN:-}" ]; then REMOTE_RUN="$HEAVY_SLOT_REMOTE_RUN"; else REMOTE_ON=0; fi
fi
PROOF=""; CL_OUT=""
# journal_early — запись журнала до входа в очередь (каталог может быть ещё не заведён).
journal_early() { mkdir -p "$DIR" 2>/dev/null; journal "$@"; }
# cluster_once [профиль] — один опрос: код run.sh --available, его вывод — в CL_OUT.
cluster_once() {
    local out rc
    out="$(timeout 10 bash "$REMOTE_RUN" --available ${1:+--profile "$1"} 2>&1)"; rc=$?
    [ "$rc" -eq 124 ] && out="проверка доступности не ответила за 10 с (сеть до кластера)${out:+; $out}"
    CL_OUT="$(printf '%s' "$out" | tr '[:cntrl:]' ' ' | cut -c1-400)"
    return "$rc"
}
# cluster_check [профиль] — 0, если кластер принимает прогон. Занят (75) — НЕ
# недоступен (решение диспетчера 2026-10-16: «занятость — не недоступность»): место
# ждётся до --wait N опросом раз в POLL_S, затем выход 74 (ожидания не было) либо 75 —
# локально команда не идёт. Иной код — недоступен: 1, PROOF — вывод проверки с кодом.
cluster_check() {
    local rc t0
    t0="$(now)"
    while :; do
        cluster_once "${1:-}"; rc=$?
        [ "$rc" -eq 0 ] && return 0
        [ "$rc" -eq 75 ] || break
        [ $(( $(now) - t0 + POLL_S )) -le "$WAIT_S" ] || busy_exit "$t0"
        sleep "$POLL_S"
    done
    PROOF="rc=$rc $CL_OUT"
    WHY_LOCAL="кластер недоступен: ${CL_OUT#remote-heavy: }"
    return 1
}
busy_exit() {
    local code=74
    [ "$WAIT_S" -gt 0 ] && code=75
    journal_early "busy-external class=$CLASS waited=$(( $(now) - $1 ))s proof=rc=75 $CL_OUT who=$(git -C "$PWD" branch --show-current 2>/dev/null)@$PWD cmd=$(printf '%q ' "${CMD_R[@]}")"
    say "кластер занят: ${CL_OUT#remote-heavy: } — команда НЕ запускалась ни там, ни локально (код $code, не выполнилось, не красное): занятость — не недоступность."
    say "повтори коротким шагом; ожидание места — --wait N (≤ $WAIT_MAX_S с) перед классом (testing-verdict.md#external-cluster-first)"
    exit "$code"
}
task_of() {
    local branch
    branch="$(git -C "${GDIR:-$PWD}" branch --show-current 2>/dev/null)"
    TASK="${KACHO_TASK:-}"
    [ -n "$TASK" ] || { [[ "$branch" =~ ^(issue-)?([0-9]+)([-_/].*)?$ ]] && TASK="${BASH_REMATCH[2]}"; }
    BRANCH="$branch"
}
refuse_external() {
    journal_early "external class=$CLASS how=$1 who=$(git -C "$PWD" branch --show-current 2>/dev/null)@$PWD cmd=$(printf '%q ' "${CMD_R[@]}")"
    say "кластер доступен — команда НЕ запускалась (код 77, не выполнилось, не красное)."
    say "во внешний кластер: $1"
    say "локально — лишь при недоступном кластере (доказательство пишет сам слот) либо --local \"<причина>\" перед классом (testing-verdict.md#external-cluster-first)"
    exit 77
}
# payload — слово полезной нагрузки за обёртками env, nice, ionice, timeout, nohup,
# setsid, stdbuf, command, time (ws#1105: обёртка не уводит тяжёлое локально). PAY —
# имя (basename) команды либо файла скрипта оболочки; PAY_SH — строка `sh -c`,
# которую исполнит дочерняя оболочка (её слов разбор не судит); ключ обёртки, разбору
# неизвестный (env -C, env -S, …), — PAY «?<обёртка> <ключ>»: нагрузка не опознана.
payload() {
    local i=0 n=${#CMD_R[@]} w
    PAY=""; PAY_SH=""
    while [ "$i" -lt "$n" ]; do
        w="$(basename -- "${CMD_R[$i]}")"; i=$(( i + 1 ))
        case "$w" in
            env)
                while [ "$i" -lt "$n" ]; do
                    case "${CMD_R[$i]}" in
                        --) i=$(( i + 1 )); break ;;
                        -i|-|--ignore-environment|-0|--null) i=$(( i + 1 )) ;;
                        -u|--unset) i=$(( i + 2 )) ;;
                        -u?*|--unset=*) i=$(( i + 1 )) ;;
                        -*) PAY="?env ${CMD_R[$i]}"; return ;;
                        *=*) i=$(( i + 1 )) ;;
                        *) break ;;
                    esac
                done ;;
            nice|ionice|nohup|setsid|stdbuf|command|time|timeout)
                while [ "$i" -lt "$n" ]; do
                    case "$w:${CMD_R[$i]}" in
                        nice:-n|nice:--adjustment|ionice:-c|ionice:-n|ionice:--class|ionice:--classdata|stdbuf:-i|stdbuf:-o|stdbuf:-e|timeout:-s|timeout:-k|timeout:--signal|timeout:--kill-after) i=$(( i + 2 )) ;;
                        *:--) i=$(( i + 1 )); break ;;
                        *:-*) i=$(( i + 1 )) ;;
                        *) break ;;
                    esac
                done
                [ "$w" = timeout ] && i=$(( i + 1 )) ;;  # длительность
            bash|sh|dash|zsh|ksh)
                while [ "$i" -lt "$n" ]; do
                    case "${CMD_R[$i]}" in
                        --rcfile|--init-file|-o|+o|-O|+O) i=$(( i + 2 )) ;;
                        --) i=$(( i + 1 )); break ;;
                        --*) i=$(( i + 1 )) ;;
                        -*c*) PAY="$w -c"; PAY_SH="${CMD_R[$(( i + 1 ))]:-}"; return ;;
                        -*|+*) i=$(( i + 1 )) ;;
                        *) break ;;
                    esac
                done
                if [ "$i" -lt "$n" ]; then PAY="$(basename -- "${CMD_R[$i]}")"; else PAY="?$w без скрипта"; fi
                return ;;
            *) PAY="$w"; return ;;
        esac
    done
    PAY="?обёртка без команды"
}
# stand_route — класс stand: подъём ЛОКАЛЬНОГО стенда судится по словам argv И по
# словам строки дочерней оболочки; строка оболочки без внешней формы (stand-ns-*) —
# не опознана: цель может прийти переменной (`bash -c 'make "$G"'`).
stand_route() {
    local a tok prev="" mk="" safe="" toks
    for a in "${CMD_R[@]}"; do
        mapfile -t toks < <(printf '%s\n' "$a" | tr ' \t;&|()"'"'"'`' '\n')
        for tok in "${toks[@]}"; do
            [ -n "$tok" ] || continue
            case "$(basename -- "$tok")" in
                dev-up|dev-prod-up|own-up|stack-up|cert-manager-up|create-cluster.sh) mk=1 ;;
                create) [ "$(basename -- "$prev")" = kind ] && mk=1 ;;
                stand-ns-*) safe=1 ;;
            esac
            [ "${tok#-}" = "$tok" ] && prev="$tok"
        done
    done
    payload
    if [ -z "$mk" ] && { [ -z "$PAY_SH" ] && [ "${PAY#\?}" = "$PAY" ] || [ -n "$safe" ]; }; then
        WHY_LOCAL="команда стенда не поднимает локальный стенд"; return 1
    fi
    cluster_check || return 1
    task_of
    [[ "$TASK" =~ ^[1-9][0-9]*$ ]] || TASK="<задача>"
    [ -n "$mk" ] || refuse_external "строку оболочки «${PAY_SH:-$PAY}» слот не судит (цель стенда может прийти переменной) — дай команду словами argv; стенд — в deploy/ продукта make stand-ns-up NS=t$TASK-<коротко>"
    refuse_external "в deploy/ продукта make stand-ns-up NS=t$TASK-<коротко> (либо stand-ns-run NS=… CMD='…' — снятие само), снятие — make stand-ns-down NS=… этой же задачей, после — stand-ns-census и residue-census 0"
}
remote_route() {
    local top url repo rel fix="" known=""
    case "$CLASS" in go-race|integration|lint|ci-local) ;; stand) stand_route; return 1 ;; *) WHY_LOCAL="класс «$CLASS» внешнего пути не имеет"; return 1 ;; esac
    payload
    case "$PAY" in
        go|make|golangci-lint|gosec|govulncheck|ci-local.sh) known=1 ;;
        git)
            if [ "$CLASS" != ci-local ] || ! git_push_form; then
                WHY_LOCAL="команда «git» без push (не хук отправки) внешнего пути не имеет"; return 1
            fi
            known=1 ;;
    esac
    top="$(git -C "$GDIR" rev-parse --show-toplevel 2>/dev/null)" || { WHY_LOCAL="рабочий каталог — не клон git: внешнего пути нет"; return 1; }
    url="$(git -C "$top" remote get-url origin 2>/dev/null)"
    repo="${url%.git}"; repo="${repo##*/}"
    case "$url" in
        *PRO-Robotech/kacho|*PRO-Robotech/kacho.git|*PRO-Robotech/kaname|*PRO-Robotech/kaname.git|*PRO-Robotech/corelib|*PRO-Robotech/corelib.git) ;;
        *) WHY_LOCAL="клон не kacho, kaname или corelib: внешнего пути нет"; return 1 ;;
    esac
    [ -n "$(git -C "$top" status --porcelain --untracked-files=no 2>/dev/null)" ] &&
        fix="закоммить правки отслеживаемых файлов (кластер судит коммит) и повтори ту же команду — слот уведёт её Job-ом"
    task_of
    [[ "$TASK" =~ ^[1-9][0-9]*$ ]] ||
        fix="${fix:+$fix; }задай номер задачи: KACHO_TASK=<N> heavy-slot.sh $CLASS -- … (ведущих цифр в имени ветки «$BRANCH» нет)"
    cluster_check "$CLASS" || return 1
    [ -n "$known" ] || refuse_external "нагрузка «${PAY_SH:-$PAY}» за обёрткой не опознана как переносимая (go, make, golangci-lint, gosec, govulncheck, ci-local.sh) — дай её словами argv: heavy-slot.sh $CLASS -- go …; слот уведёт её Job-ом"
    [ -n "$fix" ] && refuse_external "$fix"
    if [ -n "$GIT_IDX" ]; then
        HOOKS_ORIG="$(cd "$GDIR" && cd "$(git rev-parse --git-path hooks 2>/dev/null)" 2>/dev/null && pwd -P)"
        if [ ! -x "$HOOKS_ORIG/pre-push" ] || ! git -C "$top" cat-file -e HEAD:scripts/hooks/pre-push 2>/dev/null; then
            WHY_LOCAL="у клона нет хука отправки scripts/hooks/pre-push за .git/hooks/pre-push — Job-у нечего исполнять"; return 1
        fi
        PUSH_TOP="$top"; PUSH_REPO="$repo"; PUSH_HEAD="$(git -C "$top" rev-parse HEAD)"
        return 0
    fi
    rel="$(realpath --relative-to="$top" "$PWD")"
    ROUTE=(bash "$REMOTE_RUN" --task "$TASK" --repo "$repo" --ref "$(git -C "$top" rev-parse HEAD)" --src "$top" --workdir "$rel" --profile "$CLASS" --)
    return 0
}
# git_push_form — команда — `git … push` с хуком (без --no-verify); GIT_IDX — индекс
# слова git, GDIR — каталог клона с учётом -C. --git-dir и --work-tree не разбираются:
# такая отправка идёт локально.
git_push_form() {
    local i=0 n=${#CMD_R[@]} w sub=""
    GDIR="$PWD"; GIT_IDX=""
    while [ "$i" -lt "$n" ] && [ "$(basename -- "${CMD_R[$i]}")" != git ]; do i=$(( i + 1 )); done
    [ "$i" -lt "$n" ] || return 1
    local gi="$i"; i=$(( i + 1 ))
    while [ "$i" -lt "$n" ]; do
        w="${CMD_R[$i]}"
        case "$w" in
            -C) GDIR="$(cd "$GDIR" 2>/dev/null && cd "${CMD_R[$(( i + 1 ))]:-}" 2>/dev/null && pwd)" || return 1; i=$(( i + 2 )) ;;
            -c) i=$(( i + 2 )) ;;
            --git-dir|--git-dir=*|--work-tree|--work-tree=*) return 1 ;;
            -*) i=$(( i + 1 )) ;;
            *) sub="$w"; break ;;
        esac
    done
    [ "$sub" = push ] || return 1
    for w in "${CMD_R[@]:$(( i + 1 ))}"; do [ "$w" = --no-verify ] && return 1; done
    GIT_IDX="$gi"
}
# push_remote — отправка с хуком Job-ом (шапка, «ХУК ОТПРАВКИ»). Возвращает 0, если
# переходник отклонил отправку кодом 78 (не голова копии) — тогда слот идёт локально;
# иначе выходит кодом отправки либо Job-а, который не состоялся.
push_remote() {
    local sh rcf h rc hrc t0
    sh="$DIR/push/$(now)-$$"; rcf="$sh/rc"
    mkdir -p "$sh/hooks" || { WHY_LOCAL="каталог переходника $sh не создан"; return 0; }
    for h in "$HOOKS_ORIG"/*; do
        case "${h##*/}" in pre-push|*.sample) continue ;; esac
        [ -f "$h" ] && [ -x "$h" ] && ln -s "$h" "$sh/hooks/${h##*/}"
    done
    # shellcheck disable=SC2016  # текст переходника раскрывает он сам
    printf '%s\n' '#!/usr/bin/env bash' 'set -uo pipefail' 'lines="$(cat)"' \
        'tips="$(printf "%s\n" "$lines" | awk '"'"'NF >= 4 && $2 !~ /^0+$/ { print $2 }'"'"' | sort -u)"' \
        'if [ -z "$tips" ]; then printf "%s\n" "$lines" | exec "$HS_ORIG" "$@"; fi' \
        'if [ "$tips" != "$HS_HEAD" ]; then echo 78 > "$HS_RC"; echo "heavy-slot: отправка несёт не голову копии ($(printf "%s" "$tips" | cut -c1-8 | tr "\n" " ")) — Job судит голову; слот повторит отправку локально" >&2; exit 1; fi' \
        'bash "$HS_RUN" --task "$HS_TASK" --repo "$HS_REPO" --ref "$tips" --src "$HS_TOP" --workdir . --profile ci-local --push-input "$lines" -- bash -c '"'"'printf "%s\n" "$0" | bash scripts/hooks/pre-push "$1" "$2"'"'"' "$lines" "$@"' \
        'rc=$?; echo "$rc" > "$HS_RC"; exit "$rc"' > "$sh/hooks/pre-push"
    chmod +x "$sh/hooks/pre-push"
    local cmd=("${CMD_R[@]:0:$(( GIT_IDX + 1 ))}" -c "core.hooksPath=$sh/hooks" "${CMD_R[@]:$(( GIT_IDX + 1 ))}")
    journal_early "remote class=$CLASS route=push task=$TASK repo=$PUSH_REPO ref=$PUSH_HEAD who=$(git -C "$PUSH_TOP" branch --show-current 2>/dev/null)@$PWD cmd=$(printf '%q ' "${CMD_R[@]}")"
    say "хук отправки уходит во внешний кластер Job-ом (задача $TASK, $PUSH_REPO @${PUSH_HEAD:0:8}); локально — лишь отправка, слот машины не занимается"
    t0="$(now)"
    env HS_ORIG="$HOOKS_ORIG/pre-push" HS_HEAD="$PUSH_HEAD" HS_RC="$rcf" HS_RUN="$REMOTE_RUN" HS_TASK="$TASK" \
        HS_REPO="$PUSH_REPO" HS_TOP="$PUSH_TOP" "${cmd[@]}"
    rc=$?; hrc="$(cat "$rcf" 2>/dev/null)"; rm -rf -- "$sh"
    journal_early "remote-done class=$CLASS route=push rc=$rc hook_rc=${hrc:-—} dur=$(( $(now) - t0 ))s"
    case "$hrc" in
        78) WHY_LOCAL="отправка несёт не голову копии — Job судит голову"; return 0 ;;
        69|74|75|124|125)
            say "Job хука отправки не состоялся (код $hrc) — отправка остановлена; не выполнилось, не красное: вердикта по хуку нет"
            exit "$( [ "$hrc" = 69 ] && echo 69 || echo 75 )" ;;
    esac
    exit "$rc"
}
CMD_R=("$@"); WHY_LOCAL=""; ROUTE=(); GIT_IDX=""; GDIR="$PWD"
if [ -n "$LOCAL_SET" ]; then
    say "локально по флагу --local: $LOCAL_WHY — маршрут во внешний кластер не судился"
elif [ "$REMOTE_ON" = 1 ]; then
    if remote_route; then
        if [ -n "$GIT_IDX" ]; then
            push_remote
        else
            journal_early "remote class=$CLASS route=job task=$TASK repo=$(printf '%s' "${ROUTE[@]:5:1}") ref=$(printf '%s' "${ROUTE[@]:7:1}") who=$(git -C "$PWD" branch --show-current 2>/dev/null)@$PWD cmd=$(printf '%q ' "${CMD_R[@]}")"
            say "класс «$CLASS» уходит во внешний кластер: $(printf '%q ' "${ROUTE[@]:3:6}")— слот машины не занимается"
            exec "${ROUTE[@]}" "$@"
        fi
    fi
    case "$CLASS" in go-race|integration|lint|ci-local|stand) say "локально — $WHY_LOCAL" ;; esac
else
    WHY_LOCAL="режим проб без двойника run.sh — маршрут не судился"
fi

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
# Локальный запуск тяжёлого — с доказательством в журнале (ws#1105): вывод проверки
# кластера (local … proof=…) либо причина флага (bypass-local … why=…).
# Причина пишется у КАЖДОГО локального запуска, не только в stderr (решение
# диспетчера 2026-10-16): строка «local class=… [proof=…] why=…».
LOCAL_NOTE=""
if [ -n "$LOCAL_SET" ]; then
    LOCAL_NOTE="по флагу: $LOCAL_WHY"
    journal "bypass-local class=$CLASS why=$LOCAL_WHY who=$WHO cmd=$CMDLINE"
else
    [ -n "$PROOF" ] && LOCAL_NOTE="кластер не принял: $PROOF"
    journal "local class=$CLASS${PROOF:+ proof=$PROOF} why=${WHY_LOCAL:-причина не выведена} who=$WHO cmd=$CMDLINE"
fi
SLOT_TMP=""
if [ "$CLASS" = ci-local ] && [ -z "${TMPDIR:-}" ]; then
    SLOT_TMP="$TMPROOT/$(copy_key)"
    if mkdir -p "$SLOT_TMP" 2>/dev/null && touch "$SLOT_TMP"; then
        git -C "$PWD" rev-parse --show-toplevel > "$SLOT_TMP.copy" 2>/dev/null || printf '%s\n' "$PWD" > "$SLOT_TMP.copy"
    else
        say "TMPDIR копии $SLOT_TMP не создан — ci-local идёт с TMPDIR по умолчанию"; SLOT_TMP=""
    fi
fi

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
tk=""
if [ -n "$RESUME" ]; then
    rf="$DIR/queue/$(printf '%012d' "$RESUME")"; ru="$(field "$rf" resume_until)"
    if [ -n "$ru" ] && [ "$ru" -ge "$(now)" ] && [ "$(field "$rf" class)" = "$CLASS" ]; then
        tk="$RESUME"; journal "resume ticket=$tk class=$CLASS who=$WHO"
    else
        miss="просрочен либо не выдавался: в очереди его нет (просроченный снимает первый же осмотр очереди)"
        [ -n "$ru" ] && miss="просрочен (срок $RESUME_TTL_S с)"
        [ -n "$ru" ] && [ "$ru" -ge "$(now)" ] && miss="другого класса ($(field "$rf" class))"
        say "билет $RESUME $miss — место не сохранено, билет в конец очереди"
        journal "resume-miss ticket=$RESUME class=$CLASS why=$miss who=$WHO"
    fi
fi
[ -n "$tk" ] || { tk=$(( $(cat "$DIR/ticket" 2>/dev/null || echo 0) + 1 )); echo "$tk" > "$DIR/ticket"; }
TICKET="$DIR/queue/$(printf '%012d' "$tk")"
printf 'pid=%s\npid_start=%s\nclass=%s\nbudget=%s\nlimit=%s\nmeminfo=%s\nwho=%s\n' "$$" "$(pid_start $$)" "$CLASS" "$BUDGET" "$LIMIT_MIB" "$MEMINFO" "$WHO" > "$TICKET"
unlock
KEEP_TICKET=""
trap '[ -n "$KEEP_TICKET" ] || rm -f "$TICKET"' EXIT
# defer_ticket — отказ 74/75: билет откладывается на RESUME_TTL_S, владелец снят (шапка).
defer_ticket() {
    lock
    printf 'class=%s\nbudget=%s\nlimit=%s\nmeminfo=%s\nwho=%s\nresume_until=%s\n' "$CLASS" "$BUDGET" "$LIMIT_MIB" "$MEMINFO" "$WHO" "$(( $(now) + RESUME_TTL_S ))" > "$TICKET.tmp" &&
        mv -f "$TICKET.tmp" "$TICKET" && KEEP_TICKET=1
    unlock
}
RETRY_HINT="повтор — ОДИН коротким шагом: heavy-slot.sh --resume $tk [--wait N] $CLASS -- … в течение $RESUME_TTL_S с держит место (билет $tk); без билета — в конец очереди"
t0="$(now)"; waited=0
while :; do
    lock
    reap
    held="$(exclusive_holder)"
    ahead=0; aside=0; smib="$(slots_mib)"
    for f in "$DIR"/queue/*; do
        [ -e "$f" ] || continue
        # Отложенный билет (74/75, ждёт --resume) голову не держит; просроченный снимается.
        ru="$(field "$f" resume_until)"
        if [ -n "$ru" ]; then
            [ "$ru" -lt "$(now)" ] && { journal "reap ticket=$(basename "$f") class=$(field "$f" class) expired=resume"; rm -f "$f"; }
            continue
        fi
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
    used="$(used_mib)"; resv="$(reserved_mib)"; free=$(( $(avail_mib) - resv ))
    read -r nocc socc <<< "$(occupied)"
    blocked=""; full=""
    is_exclusive "$CLASS" && [ -n "$held" ] && blocked="$held"
    [ "$nocc" -ge "$SLOTS_MAX" ] && full="занято слотов $nocc из $SLOTS_MAX"
    [ -z "$full" ] && [ $(( socc + BUDGET )) -gt "$SLOTS_SUM_MIB" ] &&
        full="бюджеты занятых $(mib "$socc") + $(mib "$BUDGET") > $(mib "$SLOTS_SUM_MIB")"
    [ "$free" -lt "$FREE_MIN_MIB" ] && full="${full:+$full; }свободно $(mib "$free") < $(mib "$FREE_MIN_MIB") до старта"
    if [ "$ahead" -eq 0 ] && [ -z "$blocked" ] && [ -z "$full" ] && [ $(( used + resv + BUDGET )) -le "$LIMIT_MIB" ]; then
        rm -f "$TICKET"
        seq=$(( $(cat "$DIR/seq" 2>/dev/null || echo 0) + 1 )); echo "$seq" > "$DIR/seq"
        if [ "$(stat -c %s "$DIR/journal.log" 2>/dev/null || echo 0)" -gt 4194304 ]; then
            tail -n 10000 "$DIR/journal.log" > "$DIR/journal.log.new" && mv "$DIR/journal.log.new" "$DIR/journal.log"
        fi
        {
            echo "class=$CLASS"; echo "budget=$BUDGET"; echo "pid=$$"; echo "pid_start=$(pid_start $$)"
            echo "unit=$UNIT"; echo "start=$(now)"; echo "seq=$seq"; echo "who=$WHO"; echo "cmd=$CMDLINE"
            [ -n "$SLOT_TMP" ] && echo "tmp=$SLOT_TMP"
            [ -n "$LOCAL_NOTE" ] && echo "local=$LOCAL_NOTE"
        } > "$P.slot"
        # Уборка старых TMPDIR копий — шагом входа под замком, а не выходом слота:
        # каталог переживает прогон, снимается лишь неиспользуемый дольше срока.
        prune_tmp
        journal "enter id=$ID class=$CLASS budget=${BUDGET}MiB used=${used}MiB reserved=${resv}MiB free=${free}MiB slots=$nocc waited=${waited}s who=$WHO cmd=$CMDLINE"
        unlock
        break
    fi
    unlock
    why="занято $(mib "$used") + недобрано $(mib "$resv") + бюджет $(mib "$BUDGET") $( [ $(( used + resv + BUDGET )) -le "$LIMIT_MIB" ] && echo '≤' || echo '>') потолка $(mib "$LIMIT_MIB")"
    [ "$ahead" -gt 0 ] && why="в очереди впереди $ahead; $why"
    [ "$aside" -gt 0 ] && why="$why; впереди $aside не влезут под свой потолок и при пустых слотах — голову не держат"
    [ -n "$full" ] && why="$full; $why"
    [ -n "$blocked" ] && why="golangci-lint по одному на машину, занят: $blocked; $why"
    waited=$(( $(now) - t0 ))
    if [ "$WAIT_S" -eq 0 ]; then
        defer_ticket
        journal "busy class=$CLASS budget=${BUDGET}MiB used=${used}MiB reserved=${resv}MiB free=${free}MiB slots=$nocc ahead=$ahead ticket=$tk who=$WHO cmd=$CMDLINE"
        say "СЛОТ ЗАНЯТ, очередь $ahead — «$CLASS» не выдан сразу: $why."
        say "команда НЕ запускалась (не выполнилось, не красное). $RETRY_HINT; ожидание — --wait N (N ≤ $WAIT_MAX_S), дольше — ОДИН раз --enqueue <каталог>; кто занял — heavy-slot.sh --status"
        exit 74
    fi
    if [ "$waited" -ge "$WAIT_S" ]; then
        defer_ticket
        journal "timeout class=$CLASS budget=${BUDGET}MiB used=${used}MiB reserved=${resv}MiB free=${free}MiB slots=$nocc ahead=$ahead waited=${waited}s ticket=$tk who=$WHO cmd=$CMDLINE"
        say "НЕ ВЫПОЛНИЛОСЬ — слот «$CLASS» не выдан за ${waited} с: $why."
        say "команда НЕ запускалась; $RETRY_HINT; дольше $WAIT_MAX_S с — ОДИН раз --enqueue <каталог>; кто занял — heavy-slot.sh --status"
        exit 75
    fi
    [ "$waited" -eq 0 ] && journal "wait class=$CLASS budget=${BUDGET}MiB used=${used}MiB reserved=${resv}MiB free=${free}MiB slots=$nocc ahead=$ahead ticket=$tk who=$WHO"
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
    kill_escaped "$P"   # до unit: со смертью корня потомки уходят к другому родителю
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
    local root="${1:-}" used cid cpeak=0 v rss x xpeak=0
    while [ -e "$P.slot" ]; do
        v=0
        for x in $(slot_escaped "$P"); do v=$(( v + $(cg_bytes "$CGROOT$x/memory.peak") )); done
        [ "$v" -gt "$xpeak" ] && xpeak="$v" && echo "$xpeak" > "$P.xpeak"
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
            kill_escaped "$P"
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
cg="$(sed -n "s/^0:://p" /proc/self/cgroup)"; printf "%s\n" "$cg" > "$p.cg"; printf "%s\n" "$$" > "$p.root"
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
# ci-local — свой TMPDIR, если вызывающий его не задал: замок golangci-lint лежит в
# TMPDIR, и две копии под общим получали код 3 «parallel golangci-lint is running»
# (ws#1087). Каталог ПОСТОЯННЫЙ и свой на копию ($TMPROOT/<ключ копии>): из TMPDIR
# потребители выводят пути, которые обязаны пережить прогон, — kacho ci-local.sh
# кладёт туда логи и кэш (scripts/ci-local.sh:214, 221). Выход слота его не снимает,
# снимает prune_tmp по возрасту. Две ci-local одной копии разом делят его — граница.
if [ "$CLASS" = ci-local ] && [ -z "${TMPDIR:-}" ] && [ -n "$SLOT_TMP" ]; then
    CENV+=(TMPDIR="$SLOT_TMP")
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
    # Чтение и поиск разведены (ws#395): `grep -q` в конце трубы под pipefail
    # рвёт писателя на первом совпадении, и труба отвечала бы «не нашёл» именно
    # тогда, когда OOM был.
    devents="$(docker events --since "$(( t_run - 5 ))" --until "$(( $(now) + 1 ))" "${filt[@]}" \
        --filter event=oom --format '{{.Action}}' 2>/dev/null)"
    grep -q oom <<<"$devents" && coom=1
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
peak_mib=$(( peak / 1024 / 1024 )); cpeak_mib=$(( cpeak / 1024 / 1024 )); xpeak_mib=$(( $(cat "$P.xpeak" 2>/dev/null || echo 0) / 1024 / 1024 ))
[ "$LIMITER" = watch ] && peak_mib="$(cat "$P.rsspeak" 2>/dev/null || echo 0)"
journal "leave id=$ID class=$CLASS budget=${BUDGET}MiB rc=$rc peak=${peak_mib}MiB container_peak=${cpeak_mib}MiB escaped_peak=${xpeak_mib}MiB containers=$(printf '%s' "$cids" | grep -c .) limiter=${LIMITER/auto/systemd} dur=${dur}s cut=${cut_by:-—}${alive:+ alive=${alive# }} who=$WHO"
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
