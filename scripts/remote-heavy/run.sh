#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# run.sh — тяжёлый прогон Job-ом во внешнем кластере, в своём ns задачи.
#
# ПРЕДМЕТ. Решения владельца 2026-10-07 «если есть доступ к внешнему кластеру то
# тестируем там и по максимуму не нагружаем локальную тачку», 2026-10-08 «Размещай
# стенды в разных нс для тестов, в рамках задач потом подчищай» и «Тяжелые загрузки
# можем туда тоже перенести?» (ws#896). Локальная машина делит 32 ядра и 70 ГБ между
# полосами (scripts/heavy-slot.sh), кластер свободен; -race, линтер и
# testcontainers уходят туда, а локально остаётся то, что без машины не делается.
#
# ФОРМА
#   run.sh --task <N> --repo <kacho|kaname|corelib> --ref <ревизия>
#          [--profile go-race|integration|lint|ci-local] [--src <клон>]
#          [--workdir <путь в дереве>] [--short <слово>] [--ns <имя>]
#          [--timeout <с>] [--keep <часы ≤ 12>] -- <команда> [аргументы…]
#   run.sh --available      0 — кластер отвечает и ns создавать вправе; 69 — нет;
#                           75 — идущих тяжёлых прогонов уже предел (см. ПРЕДЕЛ)
#   run.sh --profiles       профили, их ресурсы и основание
#
# КЛАСТЕР. Кубконфиг берётся из KACHO_REMOTE_KUBECONFIG, иначе из первой строки
# личного файла ${XDG_CONFIG_HOME:-~/.config}/kacho/remote-kubeconfig. Окружение
# KUBECONFIG и текущий контекст НЕ берутся: они могут смотреть на локальный kind или
# на кластер с выкаткой, и прогон ушёл бы не туда молча. Путь, адрес сервера и имя
# контекста в вывод не попадают: репозиторий публичный, вывод уходит в задачи, —
# ОБА потока kubectl (ошибки и вывод команды из `logs -f`) и свои строки run.sh идут
# через маску: адрес сервера — «<кластер>», IPv4 и IPv6 — «<адрес>». Вывод команды
# несёт адреса pod и dind (ревью ws#984, F4), поэтому маскируется и он.
#
# NS. Имя — t<задача>-heavy-<слово>, метки kacho.io/task=<N>, kacho.io/stand=test,
# kacho.io/kind=heavy, kacho.io/repo, аннотация kacho.io/expires (RFC 3339, UTC) —
# те же, что у стендов задачи (цели stand-ns-* в deploy/ продукта), поэтому их
# перепись видит и тяжёлые ns. ns `kacho` и любое имя вне формы — отказ 64
# (NS=<имя> окружения — то же, что --ns). Уже существующее ns не берётся и не
# снимается: run.sh снимает только созданное им самим.
#
# СНЯТИЕ. trap на EXIT, INT и TERM снимает ns всегда — на успехе, на падении
# команды, на обрыве. --keep <ч> оставляет его для разбора с expires = сейчас + ч
# (≤ 12). kill -9 trap не ловит: такое ns ловит перепись по expires
# (`kubectl get ns -l kacho.io/kind=heavy` и аннотация).
#
# ЛОКАЛЬНАЯ УБОРКА. После kill -9 на машине остаются рабочий каталог
# $TMPDIR/remote-heavy.* (bundle исходников), процессы kubectl (`logs -f`) и
# временная ссылка refs/remote-heavy/* в клоне. Каждый запуск несёт метку владельца
# «<pid>.<время старта процесса>.<случайное>»: она записана в $BOX/owner, в
# окружении REMOTE_HEAVY_OWNER у всех его потомков, в имени временной ссылки и в
# аннотации kacho.io/owner его ns. Следующий запуск переписывает остатки и снимает
# те, чей владелец не жив (pid нет либо время старта другое — pid переиспользован):
# каталог, процессы с этой меткой в окружении, ссылки, и ns, если запись говорит
# «создано, не --keep» и аннотация ns совпадает с меткой (чужое ns того же имени
# не снимается). Каталог прежней формы, без записи владельца, снимается, когда он
# старше предельной жизни прогона. Ненулевая перепись печатается строкой
# «уборка прежних запусков: …».
#
# ПРЕДЕЛ. Квота стоит на одно ns, а общего предела в кластере нет (ревью ws#984,
# F3): число одновременных тяжёлых прогонов ограничено KACHO_REMOTE_HEAVY_MAX
# (по умолчанию 2 — на узле без стенда 29,5 ГиБ, профиль go-race запрашивает
# 14 ГиБ с dind). Идущим считается ns kacho.io/kind=heavy, не снимаемое, со сроком
# в будущем и без завершённого Job. Перепись — до создания ns (предел достигнут —
# 75, ns не создаётся) и после него: две гонки, прошедшие первую проверку разом,
# разрешаются по времени создания — запуск, оказавшийся сверх предела, снимает
# своё ns и выходит 75.
#
# ИЗОЛЯЦИЯ. pod — в своём пространстве пользователей (hostUsers: false): root
# контейнера — непривилегированный uid узла, возможности SYS_ADMIN, NET_ADMIN и
# SYS_PTRACE dind действуют только внутри него. privileged нет ни у одного
# контейнера (ревью ws#984, F1). Сверх этого pod не встаёт на узел, где идёт
# хотя бы один pod ns kacho (podAntiAffinity required, topologyKey
# kubernetes.io/hostname): исполняемый код ветки и сторонних модулей не делит
# узел со стендом. NetworkPolicy ns (F2): входящие запрещены; исходящие — к DNS
# кластера (служба с портом 53/UDP, выводится из кластера) и в мир, кроме частных
# диапазонов, адресов узлов, диапазонов служб и адресов управления кластера
# (конечные точки default/kubernetes и адреса имени сервера кубконфига). Предпосылка проверяется в pod до
# команды: DNS отвечает, мир (proxy.golang.org:443) доступен, а управление кластера
# (kubernetes.default.svc:443) и служба ns kacho — нет; иначе 69.
#
# Пространство пользователей — главный барьер, и потому оно проверяется ИСПОЛНЕНИЕМ,
# а не манифестом (ревью ws#984, N1): API-сервер без UserNamespacesSupport молча
# снимает hostUsers, вебхук — procMount или securityContext. Две проверки:
#   • после create — сверка фактического spec Job и затем pod (до доставки
#     исходников, то есть до первой строки кода ветки) с запрошенным: hostUsers
#     false, нет hostNetwork/hostPID/hostIPC, у каждого контейнера запрошенные поля
#     securityContext на месте, privileged и возможностей сверх запрошенного нет,
#     procMount — запрошенный; незапрошенный контейнер — без расширенных прав;
#   • первой строкой dind и run — /proc/self/uid_map и gid_map: uid 0 контейнера
#     отображён НЕ в 0 узла, отображения 0 узла и тождественного «0 0 4294967295»
#     нет. Отказ пишется в termination-log строкой «remote-heavy-userns: …»;
#     run.sh читает её у любого контейнера (dind — из lastState перезапуска).
# Расхождение и отказ — 69, ns снимается и при --keep.
#
# ИСХОДНИКИ — git bundle ревизии и ствола, переданный в pod потоком kubectl exec
# (тот же канал, что kubectl cp). Токена нет вовсе: ни git, ни реестра — в
# кластер не уходит ни одного секрета, а неотправленная ревизия доставляется так
# же, как отправленная. Bundle несёт историю, поэтому проверки, читающие git
# (`git ls-files`, предок ли ствол), видят дерево как в клоне конвейера.
#
# ВЕРСИИ — из дерева ревизии, а не из машины: go — строка toolchain (иначе go)
# в go.mod, golangci-lint и gosec — пин `go install …@vX` в .github/workflows/ci.y*ml.
# Образ golang:<go> берётся через зеркало Docker Hub (mirror.gcr.io) — у прямого
# docker.io предел анонимных скачиваний на адрес узла, а входа в реестр нет. Пин
# неоднозначен или не найден — 69, а не «какая-нибудь версия».
#
# DOCKER. Профили go-race, integration и ci-local несут боковой docker:dind (сокет
# unix в общем томе pod, без TCP) — testcontainers поднимают контейнеры в нём.
# dind БЕЗ privileged: dockerd в пространстве пользователей pod, среда исполнения —
# crun с --cgroup-manager=disabled (cgroup pod принадлежит root узла и в userns на
# запись закрыт; runc на нём падает), контейнеры testcontainers живут в пределе
# памяти самого dind. Опыт 2026-10-08 на кластере: alpine и postgres:16 с
# пробросом порта — да; без SYS_PTRACE, без procMount Unmasked, с seccomp или
# AppArmor RuntimeDefault — нет (зависание crun, keyctl, mount). Вложенный
# `docker run --privileged` в таком dind отказывает (sysfs не монтируется) — это
# свойство, а не дефект. Профили ns: с dind — pod-security enforce=privileged
# (возможности, Unconfined и procMount вне baseline; привилегированных контейнеров
# Job при этом нет), прочие — baseline. Ryuk выключен: контейнеры живут не дольше
# pod, а pod — не дольше ns.
#
# КЭШ — emptyDir pod: модули и сборка холодные на каждом прогоне (PVC в кластере
# нет). Это плата переноса, она видна во времени прогона.
#
# КОДЫ: код команды, если она исполнилась; 64 — вызов неверен; 69 — механизм
# недоступен (кластер, образ, доставка, пин, сеть pod); 75 — кластер занят (ПРЕДЕЛ),
# pod не начал команду в срок либо Job снят по сроку; 76 — команда оборвана
# пределом памяти. 69, 75, 76 —
# «не выполнилось», а не красное: вердикта по предмету команды нет. Своё слово —
# строкой «remote-heavy: …» в stderr.
#
# Тело — одной группой { … }: правка файла на месте не ломает идущий прогон.
{
set -uo pipefail
export LC_ALL=C

# say — своё слово в stderr, через ту же маску: в строку попадают тексты кластера
# (сообщения планировщика, событий), а они бывают с адресами.
say() { printf 'remote-heavy: %s\n' "$*" | mask >&2; }
now() { date +%s; }

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_common="$(git -C "$SELF_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
WS="$(dirname "${_common:-$SELF_DIR/../../.git}")"

REGISTRY="mirror.gcr.io/library"
DIND_IMAGE="$REGISTRY/docker:29-dind"
CLI_IMAGE="$REGISTRY/docker:29-cli"
WAIT_START_S=900     # образ, планирование и доставка — до начала команды
DEFAULT_TIMEOUT_S=5400
MAX_TIMEOUT_S=14400
MAX_KEEP_H=12
MAX_PAR="${KACHO_REMOTE_HEAVY_MAX:-2}"

# профиль|cpu req|cpu lim|mem req|mem lim|ephemeral|dind|основание. Узел кластера —
# 15,5 CPU и 29,5 ГиБ (замер 2026-10-08, kubectl get nodes); стенд kacho держит до
# 3,9 ГиБ запросов на одном из двух, поэтому запрос профиля ≤ 12 ГиБ встаёт на любой.
PROFILES='go-race|8|14|12Gi|20Gi|40Gi|1|go test -race по монорепо локально — 13,6 ГиБ (heavy-slot.sh, класс go-race); предел 20 ГиБ — с запасом на -p по числу ядер
integration|4|8|6Gi|12Gi|40Gi|1|make test-integration SVC=vpc локально — 1,4 ГиБ; контейнеры testcontainers — в dind, у него свой предел
lint|6|12|6Gi|12Gi|20Gi|0|golangci-lint run ./... по монорепо, холодный кэш — 4,5 ГиБ (heavy-slot.sh, класс lint)
ci-local|8|14|12Gi|20Gi|40Gi|1|scripts/ci-local.sh go локально — 5,2 ГиБ; группы вне go требуют инструментов, которых в образе нет'
DIND_RES='1|2|2Gi|8Gi'

profile_row() {
    local line
    while IFS= read -r line; do
        [ "${line%%|*}" = "$1" ] && { printf '%s\n' "$line"; return 0; }
    done <<< "$PROFILES"
    return 1
}

# ── кластер ──────────────────────────────────────────────────────────────────
resolve_kubeconfig() {
    local f
    if [ -n "${KACHO_REMOTE_KUBECONFIG:-}" ]; then
        KCFG="$KACHO_REMOTE_KUBECONFIG"
    else
        f="${XDG_CONFIG_HOME:-$(getent passwd "$(id -u)" | cut -d: -f6)/.config}/kacho/remote-kubeconfig"
        [ -r "$f" ] || { WHY="кластер не настроен: нет KACHO_REMOTE_KUBECONFIG и личного файла kacho/remote-kubeconfig"; return 1; }
        KCFG="$(head -n 1 "$f")"
        KCFG="${KCFG/#\~/$(getent passwd "$(id -u)" | cut -d: -f6)}"
    fi
    [ -r "$KCFG" ] || { WHY="кубконфиг, названный настройкой, не читается"; return 1; }
    command -v kubectl >/dev/null || { WHY="kubectl нет в PATH"; return 1; }
    command -v jq >/dev/null || { WHY="jq нет в PATH"; return 1; }
    SERVER="$(kubectl --kubeconfig "$KCFG" config view --minify -o 'jsonpath={.clusters[0].cluster.server}' 2>/dev/null)"
    SERVER_HOST="${SERVER#*://}"; SERVER_HOST="${SERVER_HOST%%/*}"; SERVER_HOST="${SERVER_HOST%%:*}"
    return 0
}

# mask — адрес сервера, IPv4 и IPv6 в выводе заменяются: ошибка соединения
# печатает их дословно, вывод команды — адреса pod и dind. IPv6 — полная форма
# (8 групп) и сжатая с группой по обе стороны «::»: время «12:34:56» и «std::» не
# задеваются, «::1» (петля) адресом узла не является.
MASK_V4='([0-9]{1,3}\.){3}[0-9]{1,3}'
MASK_V6='([0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}|([0-9A-Fa-f]{1,4}:){1,6}(:[0-9A-Fa-f]{1,4}){1,6}'
mask() {
    if [ -n "${SERVER_HOST:-}" ]; then
        sed -u -E -e "s#${SERVER_HOST//./\\.}#<кластер>#g" -e "s#$MASK_V6#<адрес>#g" -e "s#$MASK_V4#<адрес>#g"
    else
        sed -u -E -e "s#$MASK_V6#<адрес>#g" -e "s#$MASK_V4#<адрес>#g"
    fi
}

# kc <аргументы kubectl…> — только этот кубконфиг; stderr — через mask.
kc() {
    kubectl --kubeconfig "$KCFG" --request-timeout=30s "$@" 2> >(mask >&2)
}
# kc_stream — то же для потока лога: срок запроса оборвал бы поток через 30 с
# (опыт 2026-10-08: переподключение каждые 30 с), поэтому срока у него нет. Вывод
# команды — тоже через маску (F4). exec: зовётся фоном, и $! — сам kubectl, его и
# снимает trap.
kc_stream() {
    exec kubectl --kubeconfig "$KCFG" "$@" 2> >(mask >&2) > >(mask)
}

available() {
    local out err
    resolve_kubeconfig || return 1
    # stdout — ответ, stderr — предупреждения и ошибки: «Warning: … not namespace
    # scoped» печатается и при «yes».
    err="$(mktemp)" || { WHY="временный файл не создан"; return 1; }
    out="$(kubectl --kubeconfig "$KCFG" --request-timeout=10s auth can-i create namespaces 2>"$err")"
    if [ "$out" != yes ]; then
        WHY="кластер не отвечает либо создавать ns не вправе: ${out:-нет ответа} $(grep -v '^Warning:' "$err" | head -n 1 | mask)"
        rm -f "$err"
        return 1
    fi
    rm -f "$err"
    return 0
}

valid_max_par() {
    [[ "$MAX_PAR" =~ ^[1-8]$ ]] || { say "KACHO_REMOTE_HEAVY_MAX — от 1 до 8, получено «$MAX_PAR»"; return 1; }
}

# busy_heavy — идущие тяжёлые ns, старшие первыми (время создания, затем имя).
# Идущее — kacho.io/kind=heavy, не снимается, срок kacho.io/expires в будущем
# (ns без срока — идущее: не знаем, что оно не занято) и ни один его Job не
# завершён. Код 1 — перепись не прочитана.
busy_heavy() {
    local nsj jbj
    nsj="$(kc get ns -l kacho.io/kind=heavy -o json 2>/dev/null)" || return 1
    jbj="$(kc get jobs -A -l kacho.io/kind=heavy -o json 2>/dev/null)" || return 1
    jq -nr --argjson ns "$nsj" --argjson jb "$jbj" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
      [$jb.items[] | select([.status.conditions[]? | select(.status == "True" and (.type == "Complete" or .type == "Failed"))] | length > 0)
                   | .metadata.namespace] as $done
      | [$ns.items[]
         | select((.status.phase // "Active") != "Terminating")
         | select((.metadata.annotations["kacho.io/expires"] // "9999") > $now)
         | select(.metadata.name as $n | $done | any(. == $n) | not)]
      | sort_by(.metadata.creationTimestamp // "", .metadata.name) | .[].metadata.name'
}

case "${1:-}" in
    --available)
        valid_max_par || exit 64
        available || { say "$WHY"; exit 69; }
        busy="$(busy_heavy)" || { say "перепись идущих тяжёлых ns не прочитана"; exit 69; }
        n="$(grep -c . <<< "$busy")"
        if [ "$n" -ge "$MAX_PAR" ]; then say "кластер занят: идущих тяжёлых прогонов $n при пределе $MAX_PAR (KACHO_REMOTE_HEAVY_MAX)"; exit 75; fi
        echo "remote-heavy: кластер отвечает, создавать ns вправе; идущих тяжёлых прогонов $n из $MAX_PAR"; exit 0 ;;
    --profiles)
        while IFS='|' read -r n cr cl mr ml eph d basis; do
            printf '%-12s cpu %s/%s  память %s/%s  диск %s  dind %s\n%-12s основание: %s\n' "$n" "$cr" "$cl" "$mr" "$ml" "$eph" "$([ "$d" = 1 ] && echo да || echo нет)" "" "$basis"
        done <<< "$PROFILES"
        exit 0 ;;
    ''|-h|--help) sed -n '/^# ФОРМА/,/^#$/p' "$0" >&2; exit 64 ;;
esac

# ── разбор вызова ────────────────────────────────────────────────────────────
TASK=""; REPO=""; REF=""; PROFILE="go-race"; SRC=""; WORKDIR="."; SHORT=""
NSARG="${NS:-}"; TIMEOUT_S="$DEFAULT_TIMEOUT_S"; KEEP_H=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --task) TASK="${2:-}"; shift 2 ;;
        --repo) REPO="${2:-}"; shift 2 ;;
        --ref) REF="${2:-}"; shift 2 ;;
        --profile) PROFILE="${2:-}"; shift 2 ;;
        --src) SRC="${2:-}"; shift 2 ;;
        --workdir) WORKDIR="${2:-}"; shift 2 ;;
        --short) SHORT="${2:-}"; shift 2 ;;
        --ns) NSARG="${2:-}"; shift 2 ;;
        --timeout) TIMEOUT_S="${2:-}"; shift 2 ;;
        --keep) KEEP_H="${2:-}"; shift 2 ;;
        --) shift; break ;;
        *) say "неизвестный аргумент «$1»"; exit 64 ;;
    esac
done
[ "$#" -ge 1 ] || { say "нет команды: run.sh … -- <команда>"; exit 64; }
CMD=("$@")
[[ "$TASK" =~ ^[1-9][0-9]{0,6}$ ]] || { say "--task <N> — номер задачи, получено «$TASK»"; exit 64; }
case "$REPO" in kacho|kaname|corelib) ;; *) say "--repo kacho|kaname|corelib, получено «$REPO»"; exit 64 ;; esac
[ -n "$REF" ] || { say "--ref <ревизия> обязателен"; exit 64; }
ROW="$(profile_row "$PROFILE")" || { say "профиля «$PROFILE» нет: $(cut -d'|' -f1 <<< "$PROFILES" | tr '\n' ' ')"; exit 64; }
IFS='|' read -r _ CPU_REQ CPU_LIM MEM_REQ MEM_LIM EPH DIND _ <<< "$ROW"
[[ "$TIMEOUT_S" =~ ^[0-9]+$ ]] && [ "$TIMEOUT_S" -ge 60 ] && [ "$TIMEOUT_S" -le "$MAX_TIMEOUT_S" ] \
    || { say "--timeout — от 60 до $MAX_TIMEOUT_S с, получено «$TIMEOUT_S»"; exit 64; }
valid_max_par || exit 64
if [ -n "$KEEP_H" ]; then
    [[ "$KEEP_H" =~ ^[0-9]+$ ]] && [ "$KEEP_H" -ge 1 ] && [ "$KEEP_H" -le "$MAX_KEEP_H" ] \
        || { say "--keep — от 1 до $MAX_KEEP_H часов, получено «$KEEP_H»"; exit 64; }
fi
case "$WORKDIR" in /*|..|../*|*/../*|*/..) say "--workdir — путь внутри дерева, получено «$WORKDIR»"; exit 64 ;; esac
if [ -n "$SHORT" ]; then
    [[ "$SHORT" =~ ^[a-z0-9]([a-z0-9-]{0,18}[a-z0-9])?$ ]] || { say "--short — [a-z0-9-], до 20 знаков, получено «$SHORT»"; exit 64; }
else
    SHORT="$PROFILE-$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n')"
fi
NSNAME="${NSARG:-t$TASK-heavy-$SHORT}"
if [ "$NSNAME" = kacho ]; then
    say "ns kacho — ns выкатки стенда; тяжёлый прогон туда не идёт и снимать его run.sh не вправе"; exit 64
fi
if ! [[ "$NSNAME" =~ ^t${TASK}-heavy-[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || [ "${#NSNAME}" -gt 63 ]; then
    say "ns «$NSNAME» вне формы t$TASK-heavy-<слово> (≤ 63 знака) — run.sh создаёт и снимает только свои ns"; exit 64
fi

# ── ревизия и версии ─────────────────────────────────────────────────────────
SRC="${SRC:-$WS/project/$REPO}"
git -C "$SRC" rev-parse --git-dir >/dev/null 2>&1 || { say "клон $REPO не найден: $SRC (--src)"; exit 69; }
SHA="$(git -C "$SRC" rev-parse --verify --quiet "$REF^{commit}")" || { say "ревизии «$REF» в клоне $REPO нет"; exit 69; }
MAIN_SHA="$(git -C "$SRC" rev-parse --verify --quiet 'refs/remotes/origin/main^{commit}')" || MAIN_SHA=""
GOMOD="$(git -C "$SRC" show "$SHA:go.mod" 2>/dev/null)" || { say "go.mod на $SHA не прочитан"; exit 69; }
GOVER="$(sed -n 's/^toolchain go\([0-9][0-9.]*\)$/\1/p' <<< "$GOMOD" | head -n 1)"
[ -n "$GOVER" ] || GOVER="$(sed -n 's/^go \([0-9]*\.[0-9]*\.[0-9]*\)$/\1/p' <<< "$GOMOD" | head -n 1)"
[ -n "$GOVER" ] || { say "версия go на $SHA не выводится: нет строки toolchain и полной строки go в go.mod"; exit 69; }
WF=""
for f in .github/workflows/ci.yaml .github/workflows/ci.yml; do
    WF="$(git -C "$SRC" show "$SHA:$f" 2>/dev/null)" && break
done
# pin_of <путь модуля> — единственная версия `go install <путь>@vX` в конвейере ревизии.
# Код 1 — пина нет; 2 — версий больше одной (печатается).
pin_of() {
    local v
    v="$(grep -oE "$1@v[0-9]+\.[0-9]+\.[0-9]+" <<< "$WF" | sed 's/.*@//' | sort -u)"
    [ -n "$v" ] || return 1
    [ "$(wc -l <<< "$v")" -eq 1 ] || { say "пин $1 неоднозначен на $SHA: $(tr '\n' ' ' <<< "$v")"; return 2; }
    printf '%s\n' "$v"
}
LINT_PIN="$(pin_of 'golangci-lint/v2/cmd/golangci-lint')"; [ "$?" -eq 2 ] && exit 69
GOSEC_PIN="$(pin_of 'securego/gosec/v2/cmd/gosec')"; [ "$?" -eq 2 ] && exit 69
if [ "$PROFILE" = lint ] && [ -z "$LINT_PIN" ]; then
    say "профиль lint: пина golangci-lint в конвейере $REPO на $SHA нет — версию не выбрать"; exit 69
fi
GO_IMAGE="$REGISTRY/golang:$GOVER"

# ── владелец и уборка прежних запусков (ЛОКАЛЬНАЯ УБОРКА в шапке) ──────────────
# proc_start <pid> — время старта процесса (поле 22 /proc/<pid>/stat, в тиках).
proc_start() {
    local st
    st="$(cat "/proc/$1/stat" 2>/dev/null)" || return 1
    st="${st##*) }"
    # shellcheck disable=SC2086  # поля stat — слова
    set -- $st
    printf '%s\n' "${20}"
}
# owner_alive <метка> — жив ли запуск, поставивший метку «pid.старт.случайное».
owner_alive() {
    local pid="${1%%.*}" rest="${1#*.}"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    [ "$(proc_start "$pid")" = "${rest%%.*}" ]
}
OWNER="$$.$(proc_start $$).$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"

reap_local() {
    local d e o p tok ns created keep ref tail n_dir=0 n_proc=0 n_ref=0 n_ns=0 stale_min
    # процессы с меткой мёртвого владельца — kubectl logs -f и прочие потомки
    while IFS= read -r e; do
        o="$(tr '\0' '\n' < "$e" 2>/dev/null | sed -n 's/^REMOTE_HEAVY_OWNER=//p' | head -n 1)"
        [ -n "$o" ] || continue
        owner_alive "$o" && continue
        p="${e#/proc/}"; p="${p%/environ}"
        kill "$p" 2>/dev/null && n_proc=$((n_proc + 1))
    done < <(grep -lzas '^REMOTE_HEAVY_OWNER=' /proc/[0-9]*/environ 2>/dev/null)
    # рабочие каталоги
    stale_min=$(( (MAX_TIMEOUT_S + WAIT_START_S) / 60 + 10 ))
    for d in "${TMPDIR:-/tmp}"/remote-heavy.*; do
        [ -d "$d" ] || continue
        if [ -f "$d/owner" ]; then
            tok=""; ns=""; created=""; keep=""
            { read -r tok; read -r ns; read -r created; read -r keep; } < "$d/owner"
            owner_alive "$tok" && continue
            if [ "$created" = 1 ] && [ -z "$keep" ] && [ "$ns" != kacho ] && [[ "$ns" =~ ^t[1-9][0-9]*-heavy-[a-z0-9-]+$ ]] \
               && [ "$(kc get ns "$ns" -o json 2>/dev/null | jq -r '.metadata.annotations["kacho.io/owner"] // ""')" = "$tok" ]; then
                kc delete ns "$ns" --wait=false >/dev/null 2>&1 && n_ns=$((n_ns + 1))
            fi
        else
            [ -n "$(find "$d" -maxdepth 0 -mmin +"$stale_min" 2>/dev/null)" ] || continue
        fi
        rm -rf -- "$d" && n_dir=$((n_dir + 1))
    done
    # временные ссылки в клоне: «pid.старт.случайное» либо прежняя форма «pid-время»
    while IFS= read -r ref; do
        tail="${ref#refs/remote-heavy/}"
        if [[ "$tail" == *.* ]]; then owner_alive "$tail" && continue
        else kill -0 "${tail%%-*}" 2>/dev/null && continue; fi
        git -C "$SRC" update-ref -d "$ref" 2>/dev/null && n_ref=$((n_ref + 1))
    done < <(git -C "$SRC" for-each-ref --format='%(refname)' refs/remote-heavy/ 2>/dev/null)
    if [ $((n_dir + n_proc + n_ref + n_ns)) -gt 0 ]; then
        say "уборка прежних запусков (владелец не жив): каталогов $n_dir, процессов $n_proc, ссылок $n_ref, ns $n_ns"
    fi
}

# ── кластер и уборка ─────────────────────────────────────────────────────────
available || { say "$WHY (не выполнилось)"; exit 69; }
reap_local
export REMOTE_HEAVY_OWNER="$OWNER"
busy="$(busy_heavy)" || { say "перепись идущих тяжёлых ns не прочитана (не выполнилось)"; exit 69; }
n="$(grep -c . <<< "$busy")"
if [ "$n" -ge "$MAX_PAR" ]; then
    say "кластер занят: идущих тяжёлых прогонов $n при пределе $MAX_PAR (KACHO_REMOTE_HEAVY_MAX) — ns не создаётся (не выполнилось)"; exit 75
fi

BOX="$(mktemp -d "${TMPDIR:-/tmp}/remote-heavy.XXXXXX")" || { say "рабочий каталог не создан"; exit 69; }
CREATED=0; BG=""; DONE=0; TMPREF=""
record_owner() { printf '%s\n%s\n%s\n%s\n' "$OWNER" "$NSNAME" "$CREATED" "$KEEP_H" > "$BOX/owner"; }
record_owner || { say "запись владельца не сделана"; exit 69; }
# shellcheck disable=SC2329  # зовётся из trap
cleanup() {
    [ "$DONE" = 1 ] && return 0
    DONE=1
    [ -n "$BG" ] && kill "$BG" 2>/dev/null
    [ -n "$TMPREF" ] && git -C "$SRC" update-ref -d "$TMPREF" 2>/dev/null
    rm -rf -- "$BOX"
    [ "$CREATED" = 1 ] || return 0
    if [ -n "$KEEP_H" ]; then
        say "ns $NSNAME оставлено для разбора до $EXPIRES (--keep $KEEP_H); снять: kubectl delete ns $NSNAME"
        return 0
    fi
    if kc delete ns "$NSNAME" --wait=true --timeout=300s >/dev/null; then
        say "ns $NSNAME снято"
    else
        say "ns $NSNAME НЕ снято за 300 с — его поймает перепись по kacho.io/expires ($EXPIRES)"
    fi
}
# shellcheck disable=SC2329  # зовётся из trap
on_signal() { say "оборван сигналом $1 — снимаю ns"; cleanup; exit "$2"; }
trap cleanup EXIT
trap 'on_signal INT 130' INT
trap 'on_signal TERM 143' TERM

LIFE_S=$(( TIMEOUT_S + WAIT_START_S + 600 ))
[ -n "$KEEP_H" ] && LIFE_S=$(( KEEP_H * 3600 ))
EXPIRES="$(date -u -d "@$(( $(now) + LIFE_S ))" +%Y-%m-%dT%H:%M:%SZ)"
PSA=baseline; [ "$DIND" = 1 ] && PSA=privileged

jq -n --arg ns "$NSNAME" --arg task "$TASK" --arg repo "$REPO" --arg exp "$EXPIRES" --arg psa "$PSA" --arg owner "$OWNER" '{
  apiVersion: "v1", kind: "Namespace",
  metadata: {name: $ns,
    labels: {"kacho.io/task": $task, "kacho.io/stand": "test", "kacho.io/kind": "heavy", "kacho.io/repo": $repo,
             "pod-security.kubernetes.io/enforce": $psa},
    annotations: {"kacho.io/expires": $exp, "kacho.io/owner": $owner}}}' > "$BOX/ns.json"
# create, а не apply: существующее ns create не трогает, а apply переписал бы его
# метки, и trap снял бы чужое.
if ! out="$(kc create -f "$BOX/ns.json" 2>&1 >/dev/null)"; then
    case "$out" in
        *AlreadyExists*|*"already exists"*) say "ns $NSNAME уже есть — run.sh не берёт чужое и не продолжает чужой прогон"; exit 64 ;;
    esac
    say "ns $NSNAME не создано: $(head -n 1 <<< "$out") (не выполнилось)"; exit 69
fi
CREATED=1
record_owner
say "ns $NSNAME создано: задача $TASK, $REPO@${SHA:0:12}, профиль $PROFILE, срок $EXPIRES"

# Вторая перепись: гонка двух запусков, прошедших первую разом, решается временем
# создания — сверх предела выходит младший.
busy="$(busy_heavy)" || { say "перепись идущих тяжёлых ns не прочитана (не выполнилось)"; exit 69; }
pos="$(grep -nxF -- "$NSNAME" <<< "$busy" | cut -d: -f1)"
[ -n "$pos" ] || { say "своего ns $NSNAME в переписи идущих нет (не выполнилось)"; exit 69; }
if [ "$pos" -gt "$MAX_PAR" ]; then
    KEEP_H=""  # прогона не было — оставлять для разбора нечего
    say "кластер занят: прогон $pos-й по времени создания при пределе $MAX_PAR (KACHO_REMOTE_HEAVY_MAX) — снимаю своё ns (не выполнилось)"; exit 75
fi

# ── сеть ns (ИЗОЛЯЦИЯ в шапке) ───────────────────────────────────────────────
dns="$(kc get svc -A -o json 2>/dev/null | jq -c '[.items[]
    | select(any(.spec.ports[]?; .port == 53 and (.protocol // "TCP") == "UDP"))
    | select((.spec.selector // {}) | length > 0)
    | {ns: .metadata.namespace, sel: .spec.selector}]')" || dns='[]'
[ "$(jq length <<< "$dns")" = 1 ] || { say "служба DNS кластера не выводится однозначно (служб с 53/UDP и селектором: $(jq length <<< "$dns")) — сеть ns не построить (не выполнилось)"; exit 69; }
nodeaddr="$(kc get nodes -o json 2>/dev/null | jq -c '[.items[] | (.status.addresses[]? | select(.type == "InternalIP" or .type == "ExternalIP") | .address), (.spec.podCIDRs[]?)] | unique')" \
    || { say "адреса узлов не прочитаны — сеть ns не построить (не выполнилось)"; exit 69; }
[ "$(jq length <<< "$nodeaddr")" -gt 0 ] || { say "адресов узлов ноль — сеть ns не построить (не выполнилось)"; exit 69; }
svccidr="$(kc get servicecidrs -o json 2>/dev/null | jq -c '[.items[].spec.cidrs[]?]')" || svccidr='[]'
# Управление кластера бывает вне узлов (опыт 2026-10-08: конечная точка службы
# kubernetes — публичный адрес, не адрес узла, и без этого предпосылка в pod
# краснела): адреса конечных точек default/kubernetes и адреса имени сервера
# кубконфига — тоже в исключение.
apiaddr="$( { kc -n default get endpointslices -l kubernetes.io/service-name=kubernetes -o json 2>/dev/null \
              | jq -r '.items[].endpoints[]?.addresses[]?'
            [ -n "$SERVER_HOST" ] && getent ahosts "$SERVER_HOST" 2>/dev/null | awk '{print $1}'
          } | sort -u | jq -Rsc 'split("\n") | map(select(length > 0))')"
[ "$(jq length <<< "$apiaddr")" -gt 0 ] || { say "адреса управления кластера не выведены — сеть ns не построить (не выполнилось)"; exit 69; }
jq -n --arg ns "$NSNAME" --argjson dns "$dns" --argjson addr "$nodeaddr" --argjson svc "$svccidr" --argjson api "$apiaddr" '
  def cidr: if test("/") then "\(.)" elif test(":") then "\(.)/128" else "\(.)/32" end;
  ([$addr[], $svc[], $api[]] | map(cidr)) as $own |
  {apiVersion: "networking.k8s.io/v1", kind: "NetworkPolicy", metadata: {name: "heavy", namespace: $ns},
   spec: {podSelector: {}, policyTypes: ["Ingress", "Egress"], ingress: [],
    egress: [
     {to: [{namespaceSelector: {matchLabels: {"kubernetes.io/metadata.name": $dns[0].ns}}, podSelector: {matchLabels: $dns[0].sel}}],
      ports: [{protocol: "UDP", port: 53}, {protocol: "TCP", port: 53}]},
     {to: [{ipBlock: {cidr: "0.0.0.0/0", except: (["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10", "169.254.0.0/16"]
                                                   + ($own | map(select(test(":") | not))) | unique)}},
           {ipBlock: {cidr: "::/0", except: (["fc00::/7", "fe80::/10"] + ($own | map(select(test(":")))) | unique)}}]}]}}' > "$BOX/netpol.json"
kc create -f "$BOX/netpol.json" >/dev/null || { say "сетевая политика ns не поставлена (не выполнилось)"; exit 69; }
# Служба ns kacho для пробы закрытости в pod: ClusterIP с TCP-портом, чьи pod не
# закрыты собственной политикой ns kacho (иначе проба прошла бы и без нашей).
DENY_PROBE="$(jq -nr --argjson svc "$(kc get svc -n kacho -o json 2>/dev/null || echo '{"items":[]}')" \
                    --argjson np "$(kc get netpol -n kacho -o json 2>/dev/null || echo '{"items":[]}')" '
  def covers($s): (length == 0) or (to_entries | all(.[]; $s[.key] == .value));
  [$np.items[] | .spec.podSelector.matchLabels // {}] as $sel
  | [$svc.items[] | select((.spec.type // "ClusterIP") == "ClusterIP" and .spec.clusterIP != "None")
     | select((.spec.selector // {}) as $s | ($s | length > 0)
              and ($sel | any(.[]; covers($s)) | not))
     | {n: .metadata.name, p: ([.spec.ports[]? | select((.protocol // "TCP") == "TCP") | .port] | first)}
     | select(.p != null)] | sort_by(.n) | (first // empty) | "\(.n).kacho.svc:\(.p)"')"

# Квота — сумма запросов профиля с запасом на init: ns не способно занять больше
# одного прогона, даже если в нём появится второй pod.
IFS='|' read -r DCR DCL DMR DML <<< "$DIND_RES"
[ "$DIND" = 1 ] || { DCR=0; DCL=0; DMR=0Gi; DML=0Gi; }
gi() { printf '%s' "${1%Gi}"; }
jq -n --arg ns "$NSNAME" \
    --arg rc "$(( CPU_REQ + DCR + 1 ))" --arg lc "$(( CPU_LIM + DCL + 2 ))" \
    --arg rm "$(( $(gi "$MEM_REQ") + $(gi "$DMR") + 1 ))Gi" --arg lm "$(( $(gi "$MEM_LIM") + $(gi "$DML") + 2 ))Gi" \
    --arg eph "$EPH" --arg lephq "$(( $(gi "$EPH") + 8 ))Gi" '{apiVersion: "v1", kind: "List", items: [
  {apiVersion: "v1", kind: "ResourceQuota", metadata: {name: "heavy", namespace: $ns},
   spec: {hard: {pods: "2", "count/jobs.batch": "1", "requests.cpu": $rc, "limits.cpu": $lc,
                 "requests.memory": $rm, "limits.memory": $lm,
                 "requests.ephemeral-storage": $eph, "limits.ephemeral-storage": $lephq}}},
  {apiVersion: "v1", kind: "LimitRange", metadata: {name: "heavy", namespace: $ns},
   spec: {limits: [{type: "Container",
     defaultRequest: {cpu: "100m", memory: "128Mi", "ephemeral-storage": "64Mi"},
     default: {cpu: "1", memory: "1Gi", "ephemeral-storage": "1Gi"}}]}}]}' > "$BOX/limits.json"
kc apply -f "$BOX/limits.json" >/dev/null || { say "квота ns не поставлена (не выполнилось)"; exit 69; }

# ── Job ──────────────────────────────────────────────────────────────────────
# spec_drift <запрошенный spec pod> <фактический> — расхождения изоляции строками;
# пусто — сервер исполнил запрошенное (ИЗОЛЯЦИЯ в шапке). Поля, которые сервер
# добавил сам (procMount: Default и прочие умолчания), расхождением не являются;
# снятое, изменённое и расширенное — являются.
spec_drift() {
    jq -nr --argjson q "$1" --argjson a "$2" '
      def ctrs($s): [($s.initContainers // [])[], ($s.containers // [])[]];
      def sc($c): ($c.securityContext // {});
      def caps($s): (($s.capabilities // {}).add // []);
      def wide($s): ($s.privileged == true) or (caps($s) | length > 0) or (($s.procMount // "Default") != "Default");
      (ctrs($q) | map({key: .name, value: sc(.)}) | from_entries) as $qs
      | (if $a.hostUsers == false then empty else "hostUsers \($a.hostUsers // "снято") при запрошенном false" end),
        (["hostNetwork", "hostPID", "hostIPC"][] as $k | select($a[$k] == true) | "\($k) true без запроса"),
        ($qs | keys[] as $n | select([ctrs($a)[] | select(.name == $n)] | length != 1) | "контейнер \($n): в pod не ровно один"),
        (ctrs($a)[] as $c | sc($c) as $s | $qs[$c.name] as $r
         | if $r == null then (select(wide($s)) | "контейнер \($c.name) не запрошен и несёт расширенные права")
           else ($r | to_entries[] | select($s[.key] != .value)
                 | "контейнер \($c.name): securityContext.\(.key) запрошено \(.value | tojson), у сервера \($s[.key] | tojson)"),
                (select($s.privileged == true and $r.privileged != true) | "контейнер \($c.name): privileged без запроса"),
                ((caps($s) - caps($r)) | select(length > 0) | "контейнер \($c.name): возможности сверх запрошенных: \(join(","))"),
                (select(($s.procMount // "Default") != ($r.procMount // "Default"))
                 | "контейнер \($c.name): procMount \($s.procMount // "Default") при запрошенном \($r.procMount // "Default")")
           end)'
}
# verify_spec <что> <фактический spec> — расхождение либо непрочитанный spec — 69,
# ns снимается и при --keep: прогона не было.
verify_spec() {
    local d l
    if [ -z "$2" ]; then KEEP_H=""; say "$1: фактический spec не прочитан — изоляцию не сверить (не выполнилось)"; exit 69; fi
    d="$(spec_drift "$REQ_SPEC" "$2")" || { KEEP_H=""; say "$1: сверка spec не исполнилась (не выполнилось)"; exit 69; }
    if [ -z "$d" ]; then say "$1: spec сверен с запрошенным — hostUsers false, securityContext как запрошен"; return 0; fi
    KEEP_H=""
    while IFS= read -r l; do say "$1: $l"; done <<< "$d"
    say "$1: сервер исполнил не то, что запрошено, — изоляции нет; команда не запускается, ns снимается (не выполнилось)"; exit 69
}
# userns_refused <строка> — отказ проверки пространства пользователей в pod.
userns_refused() {
    KEEP_H=""
    say "пространство пользователей pod не изолировано — $1; команда не запускается, ns снимается (не выполнилось)"; exit 69
}

# Команда — JSON-массивом через NUL: позиционные аргументы jq разбирал бы как свои
# флаги (`bash -c …` терял `-c`, опыт 2026-10-08).
CMD_JSON="$(printf '%s\0' "${CMD[@]}" | jq -Rsc 'split("\u0000")[:-1]')" || { say "команда не переведена в JSON"; exit 69; }
# shellcheck disable=SC2016  # раскрывается в pod, не здесь
# Отказ подготовки — не код команды: он пишется в termination-log контейнера
# строкой «remote-heavy-prep: …» и читается как 69, а не как красное (код 125
# сам по себе не различим с кодом команды).
# Проверка пространства пользователей (ИЗОЛЯЦИЯ в шапке) — первой строкой dind и
# run, в sh busybox и в bash. Маркер «# userns-end» — граница, по которой inject.sh
# берёт этот текст из Job и исполняет его над поддельным /proc.
USERNS_SH="$(cat <<'USERNS'
uf() { echo "remote-heavy-userns: $1" | tee /dev/termination-log >&2; exit 125; }
for m in /proc/self/uid_map /proc/self/gid_map; do
  [ -r "$m" ] || uf "$m не читается"
  awk '$1 == 0 && $2 != 0 && $3 < 4294967295 { z = 1 } $2 == 0 || $3 >= 4294967295 { bad = 1 } END { exit !(z && !bad) }' "$m" \
    || uf "$m «$(tr -s ' ' < "$m" | tr '\n' ';')» — 0 контейнера отображён в 0 узла либо отображение тождественно: своего пространства пользователей нет"
done
echo "remote-heavy: пространство пользователей — uid 0 контейнера = uid $(awk '$1 == 0 { print $2 }' /proc/self/uid_map) узла" >&2
# userns-end
USERNS
)"
# shellcheck disable=SC2016  # раскрывается в pod, не здесь
PREP='pf() { echo "remote-heavy-prep: $1" | tee /dev/termination-log >&2; exit 125; }; export PATH=/tools:/work/bin:$PATH; cd "/work/src/$HEAVY_WORKDIR" || pf "каталог $HEAVY_WORKDIR в дереве не найден"'
# Предпосылка сети pod — до команды и до установки инструментов. Положительный
# контроль (DNS, мир) обязателен: без него «закрыто» читалось бы и при мёртвом DNS.
# shellcheck disable=SC2016  # раскрывается в pod, не здесь
PREP="$PREP"'; tcp() { timeout "$1" bash -c "</dev/tcp/$2/$3" 2>/dev/null; }
getent hosts kubernetes.default.svc >/dev/null || pf "сеть pod: DNS кластера не отвечает"
tcp 15 proxy.golang.org 443 || pf "сеть pod: мир недоступен (proxy.golang.org:443)"
! tcp 5 kubernetes.default.svc 443 || pf "сеть pod: управление кластера доступно — сетевая политика не исполняется"
if [ -n "$HEAVY_DENY_PROBE" ]; then
  getent hosts "${HEAVY_DENY_PROBE%:*}" >/dev/null || pf "сеть pod: имя ${HEAVY_DENY_PROBE%:*} не разрешается"
  ! tcp 5 "${HEAVY_DENY_PROBE%:*}" "${HEAVY_DENY_PROBE##*:}" || pf "сеть pod: служба ns kacho доступна — сетевая политика не исполняется"
fi
echo "remote-heavy: сеть pod — DNS и мир есть, управление кластера${HEAVY_DENY_PROBE:+ и служба ns kacho} закрыты" >&2'
# Инструменты, которые пробы зовут из PATH, а ранер конвейера несёт в образе
# (опыт 2026-10-08: internal/check kaname — «jq не исполняется», 2 пробы красные
# только в pod). Перепись `exec.Command("…")` по дереву kacho и kaname: git, go,
# bash, make, tar — в образе; jq, python3 с yaml, psql/pg_dump — ставятся здесь;
# helm, gh, buf, trivy, gitleaks — нет, их пробы в pod не равны конвейеру.
[ "$PROFILE" = lint ] || PREP="$PREP; command -v jq >/dev/null || { echo \"remote-heavy: ставлю jq, python3-yaml, postgresql-client\" >&2; apt-get -qq update >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get -qq install -y --no-install-recommends jq python3-yaml postgresql-client >/dev/null || pf \"jq, python3-yaml, postgresql-client не поставлены\"; }"
[ "$PROFILE" = lint ] || [ "$PROFILE" = ci-local ] && [ -n "$LINT_PIN" ] && \
    PREP="$PREP; echo \"remote-heavy: ставлю golangci-lint $LINT_PIN\" >&2; GOBIN=/work/bin go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@$LINT_PIN || pf \"golangci-lint $LINT_PIN не поставлен\""
[ "$PROFILE" = ci-local ] && [ -n "$GOSEC_PIN" ] && \
    PREP="$PREP; echo \"remote-heavy: ставлю gosec $GOSEC_PIN\" >&2; GOBIN=/work/bin go install github.com/securego/gosec/v2/cmd/gosec@$GOSEC_PIN || pf \"gosec $GOSEC_PIN не поставлен\""
PREP="$USERNS_SH
$PREP; exec \"\$@\""

# dind без privileged (DOCKER в шапке): crun с выключенным cgroup-менеджером —
# средой исполнения по умолчанию; отказ установки — код 1 бокового, и pod не
# начнёт команду (75 по сроку), а причина — в логе dind.
DIND_SH="$USERNS_SH
"'apk add -q --no-cache crun >/dev/null 2>&1 || { echo "remote-heavy: crun не поставлен" >&2; exit 1; }
mkdir -p /etc/docker
printf "%s" "{\"runtimes\":{\"crun\":{\"path\":\"/usr/bin/crun\",\"runtimeArgs\":[\"--cgroup-manager=disabled\"]}},\"default-runtime\":\"crun\"}" > /etc/docker/daemon.json
exec dockerd --host=unix:///run/dind/docker.sock --registry-mirror=https://mirror.gcr.io'

# shellcheck disable=SC2016  # раскрывается в pod, не здесь
FETCH='set -e; i=0; while [ ! -f /work/in.done ]; do i=$((i+1)); [ "$i" -le 600 ] || { echo "remote-heavy: исходники не доставлены за 600 с" >&2; exit 3; }; sleep 1; done
git init -q /work/src; cd /work/src; git bundle unbundle /work/in.bundle >/dev/null
git update-ref refs/heads/heavy-run "$HEAVY_SHA"
[ -z "$HEAVY_MAIN" ] || git update-ref refs/remotes/origin/main "$HEAVY_MAIN"
git -c advice.detachedHead=false checkout -q --detach "$HEAVY_SHA"
[ "$(git rev-parse HEAD)" = "$HEAVY_SHA" ]; rm -f /work/in.bundle /work/in.done
mkdir -p /work/bin; echo "remote-heavy: дерево $HEAVY_SHA" >&2'

jq -n --arg ns "$NSNAME" --arg task "$TASK" --arg goimg "$GO_IMAGE" --arg dimg "$DIND_IMAGE" --arg cimg "$CLI_IMAGE" \
    --arg sha "$SHA" --arg main "$MAIN_SHA" --arg wd "$WORKDIR" --arg prep "$PREP" --arg fetch "$FETCH" \
    --argjson deadline "$(( TIMEOUT_S + WAIT_START_S ))" --argjson dind "$DIND" \
    --arg cr "$CPU_REQ" --arg cl "$CPU_LIM" --arg mr "$MEM_REQ" --arg ml "$MEM_LIM" --arg eph "$EPH" \
    --arg dcr "$DCR" --arg dcl "$DCL" --arg dmr "$DMR" --arg dml "$DML" \
    --arg dindsh "$DIND_SH" --arg deny "$DENY_PROBE" \
    --argjson cmd "$CMD_JSON" '{
  apiVersion: "batch/v1", kind: "Job",
  metadata: {name: "run", namespace: $ns, labels: {"kacho.io/task": $task, "kacho.io/kind": "heavy"}},
  spec: {backoffLimit: 0, activeDeadlineSeconds: $deadline, ttlSecondsAfterFinished: 3600,
   template: {metadata: {labels: {"kacho.io/task": $task, "kacho.io/kind": "heavy"}},
    spec: ({restartPolicy: "Never", enableServiceLinks: false, automountServiceAccountToken: false, hostUsers: false,
     affinity: {podAntiAffinity: {requiredDuringSchedulingIgnoredDuringExecution: [
       {labelSelector: {}, namespaceSelector: {matchLabels: {"kubernetes.io/metadata.name": "kacho"}},
        topologyKey: "kubernetes.io/hostname"}]}},
     initContainers: ((if $dind == 1 then [
       {name: "tools", image: $cimg, command: ["cp", "/usr/local/bin/docker", "/tools/docker"],
        volumeMounts: [{name: "tools", mountPath: "/tools"}]},
       {name: "dind", image: $dimg, restartPolicy: "Always",
        securityContext: {privileged: false,
                          capabilities: {add: ["SYS_ADMIN", "NET_ADMIN", "SYS_PTRACE"]},
                          seccompProfile: {type: "Unconfined"}, appArmorProfile: {type: "Unconfined"}, procMount: "Unmasked"},
        command: ["sh", "-c", $dindsh],
        startupProbe: {exec: {command: ["docker", "-H", "unix:///run/dind/docker.sock", "info"]}, periodSeconds: 2, failureThreshold: 150},
        resources: {requests: {cpu: $dcr, memory: $dmr}, limits: {cpu: $dcl, memory: $dml}},
        volumeMounts: [{name: "dind-lib", mountPath: "/var/lib/docker"}, {name: "dind-sock", mountPath: "/run/dind"}]}]
      else [] end) + [
       {name: "fetch", image: $goimg, command: ["sh", "-c", $fetch],
        env: [{name: "HEAVY_SHA", value: $sha}, {name: "HEAVY_MAIN", value: $main}],
        resources: {requests: {cpu: "100m", memory: "256Mi"}, limits: {cpu: "2", memory: "2Gi"}},
        volumeMounts: [{name: "work", mountPath: "/work"}]}]),
     containers: [{name: "run", image: $goimg, command: (["bash", "-c", $prep, "run"] + $cmd),
       env: ([{name: "HEAVY_WORKDIR", value: $wd}, {name: "HEAVY_DENY_PROBE", value: $deny}, {name: "GOTOOLCHAIN", value: "local"},
              {name: "GOMODCACHE", value: "/cache/mod"}, {name: "GOCACHE", value: "/cache/build"},
              {name: "GOLANGCI_LINT_CACHE", value: "/cache/lint"}, {name: "CI", value: "true"}]
             + (if $dind == 1 then [{name: "DOCKER_HOST", value: "unix:///run/dind/docker.sock"},
                                    {name: "TESTCONTAINERS_RYUK_DISABLED", value: "true"}] else [] end)),
       resources: {requests: {cpu: $cr, memory: $mr, "ephemeral-storage": "1Gi"}, limits: {cpu: $cl, memory: $ml, "ephemeral-storage": $eph}},
       volumeMounts: ([{name: "work", mountPath: "/work"}, {name: "cache", mountPath: "/cache"}]
                      + (if $dind == 1 then [{name: "dind-sock", mountPath: "/run/dind"}, {name: "tools", mountPath: "/tools"}] else [] end))}],
     volumes: ([{name: "work", emptyDir: {}}, {name: "cache", emptyDir: {}}]
               + (if $dind == 1 then [{name: "dind-lib", emptyDir: {}}, {name: "dind-sock", emptyDir: {}}, {name: "tools", emptyDir: {}}] else [] end))})}}}' \
    > "$BOX/job.json"
kc create -f "$BOX/job.json" >/dev/null || { say "Job не создан (не выполнилось)"; exit 69; }
T0="$(now)"
REQ_SPEC="$(jq -c '.spec.template.spec' "$BOX/job.json")"
verify_spec Job "$(kc -n "$NSNAME" get job run -o json 2>/dev/null | jq -c '.spec.template.spec // empty' 2>/dev/null)"
say "Job создан: образ golang:$GOVER$([ -n "$LINT_PIN" ] && [ "$PROFILE" != go-race ] && [ "$PROFILE" != integration ] && echo ", golangci-lint $LINT_PIN"), cpu $CPU_REQ/$CPU_LIM, память $MEM_REQ/$MEM_LIM$([ "$DIND" = 1 ] && echo ', dind')"

# pod_state — «имя|фаза|fetch|run|код run|причина run|сообщение run|ожидание|
# планирование|отказ userns». Отказ userns — строка «remote-heavy-userns: …» в
# termination-log ЛЮБОГО контейнера, текущем или прежнем (боковой dind после отказа
# перезапускается, и его отказ — в lastState).
pod_state() {
    kc -n "$NSNAME" get pods -l job-name=run -o json 2>/dev/null | jq -r '
      (.items[0] // {}) as $p |
      def st($n): ([($p.status.initContainerStatuses // [])[], ($p.status.containerStatuses // [])[]] | map(select(.name == $n)) | .[0] // {});
      def kind($s): if $s.state.running then "running" elif $s.state.terminated then "terminated" elif $s.state.waiting then "waiting" else "none" end;
      [ ($p.metadata.name // ""), ($p.status.phase // ""), kind(st("fetch")), kind(st("run")),
        (st("run").state.terminated.exitCode // "" | tostring), (st("run").state.terminated.reason // ""),
        ((st("run").state.terminated.message // "") | gsub("[|\n]"; " ")),
        ([($p.status.initContainerStatuses // [])[], ($p.status.containerStatuses // [])[]] | map(.state.waiting.reason // empty) | map(select(test("^PodInitializing$") | not)) | join(",")),
        (($p.status.conditions // []) | map(select(.type == "PodScheduled" and .status == "False") | .message) | join(" ") | gsub("[|\n]"; " ")),
        ([($p.status.initContainerStatuses // [])[], ($p.status.containerStatuses // [])[]]
         | map(.name as $n | ((.state.terminated.message // ""), (.lastState.terminated.message // ""))
               | select(startswith("remote-heavy-userns:")) | "\($n): \(.)")
         | first // "" | gsub("[|\n]"; " ")) ] | join("|")'
}

# wait_bg <pid> — ждать фонового: wait прерывается сигналом, и trap снимает ns сразу.
wait_bg() { BG="$1"; wait "$1"; local rc=$?; BG=""; return "$rc"; }

# ── доставка ─────────────────────────────────────────────────────────────────
# Bundle без ссылки git не собирает, а ревизия бывает голым sha: временная ссылка
# в своём пространстве имён живёт до конца сборки bundle.
TMPREF="refs/remote-heavy/$OWNER"
git -C "$SRC" update-ref "$TMPREF" "$SHA" || { say "временная ссылка на $SHA не создана"; exit 69; }
git -C "$SRC" bundle create "$BOX/src.bundle" "$TMPREF" ${MAIN_SHA:+refs/remotes/origin/main} >/dev/null 2>&1; brc=$?
git -C "$SRC" update-ref -d "$TMPREF"; TMPREF=""
[ "$brc" -eq 0 ] || { say "bundle ревизии $SHA не собран"; exit 69; }
POD=""
while :; do
    IFS='|' read -r POD PHASE FETCH_ST RUN_ST _ _ _ WAITR SCHED USERNS <<< "$(pod_state)"
    [ -z "$USERNS" ] || userns_refused "$USERNS"
    [ "$FETCH_ST" = running ] && break
    case "$WAITR" in
        *ErrImagePull*|*ImagePullBackOff*|*InvalidImageName*|*CreateContainerConfigError*)
            say "pod не стартует: $WAITR (не выполнилось)"; exit 69 ;;
    esac
    if [ "$PHASE" = Failed ] || [ "$FETCH_ST" = terminated ]; then
        say "pod завершился до доставки исходников (фаза $PHASE) — не выполнилось"; exit 69
    fi
    # pod нет — Job не может его создать (квота, допуск): ждать срока незачем.
    if [ -z "$POD" ] && [ $(( $(now) - T0 )) -ge 20 ]; then
        fc="$(kc -n "$NSNAME" get events --field-selector involvedObject.kind=Job,reason=FailedCreate -o json 2>/dev/null | jq -r '.items[-1].message // ""')"
        [ -z "$fc" ] || { say "Job не создаёт pod: $(mask <<< "$fc") — не выполнилось"; exit 69; }
    fi
    if [ $(( $(now) - T0 )) -ge "$WAIT_START_S" ]; then
        say "pod не готов принять исходники за $WAIT_START_S с${SCHED:+: $SCHED}${WAITR:+ ($WAITR)} — не выполнилось"; exit 75
    fi
    sleep 3 & wait_bg $!
done
# Сверка pod — до доставки: без исходников в pod нет ни строки кода ветки.
verify_spec "pod $POD" "$(kc -n "$NSNAME" get pods -l job-name=run -o json 2>/dev/null \
                          | jq -c --arg p "$POD" '.items[] | select(.metadata.name == $p) | .spec' 2>/dev/null)"
kc -n "$NSNAME" exec -i "$POD" -c fetch -- sh -c 'cat > /work/in.bundle && touch /work/in.done' < "$BOX/src.bundle" & wait_bg $! \
    || { say "исходники не доставлены в pod (не выполнилось)"; exit 69; }
say "исходники доставлены: $(( $(stat -c %s "$BOX/src.bundle") / 1048576 )) МиБ bundle за $(( $(now) - T0 )) с от создания Job"

# ── команда ──────────────────────────────────────────────────────────────────
while :; do
    IFS='|' read -r POD PHASE FETCH_ST RUN_ST _ _ _ WAITR _ USERNS <<< "$(pod_state)"
    [ -z "$USERNS" ] || userns_refused "$USERNS"
    [ "$RUN_ST" = running ] || [ "$RUN_ST" = terminated ] && break
    if [ "$PHASE" = Failed ] || [ -z "$POD" ]; then
        kc -n "$NSNAME" logs "$POD" -c fetch 2>/dev/null | tail -n 20 | mask >&2
        say "подготовка дерева в pod не удалась (фаза ${PHASE:-нет pod}) — не выполнилось"; exit 69
    fi
    case "$WAITR" in *ErrImagePull*|*ImagePullBackOff*) say "образ не скачан: $WAITR (не выполнилось)"; exit 69 ;; esac
    [ $(( $(now) - T0 )) -lt "$WAIT_START_S" ] || { say "команда не начата за $WAIT_START_S с — не выполнилось"; exit 75; }
    sleep 2 & wait_bg $!
done
T1="$(now)"
say "команда начата через $(( T1 - T0 )) с после создания Job: $(printf '%q ' "${CMD[@]}")"

# Поток лога; обрыв потока при живом контейнере — переподключение, а не конец.
since=""
while :; do
    kc_stream -n "$NSNAME" logs -f "$POD" -c run ${since:+--since-time="$since"} & wait_bg $!
    # Поток кончается и вместе с контейнером, а статус «terminated» kubelet
    # публикует позже: без ожидания конец потока читался обрывом, и переподключение
    # повторяло хвост лога (опыт 2026-10-08: 68 строк дважды).
    for _ in 1 2 3 4 5 6; do
        IFS='|' read -r POD PHASE _ RUN_ST RUN_RC RUN_REASON RUN_MSG _ _ USERNS <<< "$(pod_state)"
        [ "$RUN_ST" = terminated ] && break
        sleep 2 & wait_bg $!
    done
    [ "$RUN_ST" = terminated ] && break
    if [ -z "$POD" ] || [ "$PHASE" = Failed ]; then break; fi
    since="$(date -u -d '-5 seconds' +%Y-%m-%dT%H:%M:%SZ)"
    say "поток лога оборвался при идущей команде — переподключаюсь (строки на стыке могут повториться)"
    sleep 2 & wait_bg $!
done
T2="$(now)"

if [ "$RUN_ST" != terminated ]; then
    reason="$(kc -n "$NSNAME" get job run -o json 2>/dev/null | jq -r '[.status.conditions[]? | select(.status == "True") | .reason] | join(",")')"
    case "$reason" in
        *DeadlineExceeded*) say "Job снят по сроку $(( TIMEOUT_S + WAIT_START_S )) с — команда не завершилась (не выполнилось)"; exit 75 ;;
    esac
    say "результат команды не прочитан: pod ${POD:-нет}, фаза ${PHASE:-нет}, Job ${reason:-без условия} — не выполнилось"; exit 69
fi
[ -z "$USERNS" ] || userns_refused "$USERNS"
if [[ "$RUN_MSG" == remote-heavy-prep:* ]]; then
    say "подготовка pod не удалась: ${RUN_MSG#remote-heavy-prep: } — команда не запускалась (не выполнилось)"; exit 69
fi
if [ "$RUN_REASON" = OOMKilled ]; then
    say "команда оборвана пределом памяти $MEM_LIM (OOMKilled) через $(( T2 - T1 )) с — не выполнилось"; exit 76
fi
[[ "$RUN_RC" =~ ^[0-9]+$ ]] || { say "код команды не прочитан («$RUN_RC») — не выполнилось"; exit 69; }
say "команда завершилась кодом $RUN_RC за $(( T2 - T1 )) с (всего $(( T2 - T0 )) с от создания Job)"
exit "$RUN_RC"
}
