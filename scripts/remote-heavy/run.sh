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
#   run.sh --available      0 — кластер отвечает и ns создавать вправе; 69 — нет
#   run.sh --profiles       профили, их ресурсы и основание
#
# КЛАСТЕР. Кубконфиг берётся из KACHO_REMOTE_KUBECONFIG, иначе из первой строки
# личного файла ${XDG_CONFIG_HOME:-~/.config}/kacho/remote-kubeconfig. Окружение
# KUBECONFIG и текущий контекст НЕ берутся: они могут смотреть на локальный kind или
# на кластер с выкаткой, и прогон ушёл бы не туда молча. Путь, адрес сервера и имя
# контекста в вывод не попадают: репозиторий публичный, вывод уходит в задачи, —
# ошибки kubectl печатаются с адресом сервера, заменённым на «<кластер>».
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
# unix в общем томе pod, без TCP) — testcontainers поднимают контейнеры в нём; ns
# таких профилей получает pod-security enforce=privileged, прочие — baseline.
# Ryuk выключен: контейнеры живут не дольше pod, а pod — не дольше ns.
#
# КЭШ — emptyDir pod: модули и сборка холодные на каждом прогоне (PVC в кластере
# нет). Это плата переноса, она видна во времени прогона.
#
# КОДЫ: код команды, если она исполнилась; 64 — вызов неверен; 69 — механизм
# недоступен (кластер, образ, доставка, пин); 75 — pod не начал команду в срок либо
# Job снят по сроку; 76 — команда оборвана пределом памяти. 69, 75, 76 —
# «не выполнилось», а не красное: вердикта по предмету команды нет. Своё слово —
# строкой «remote-heavy: …» в stderr.
#
# Тело — одной группой { … }: правка файла на месте не ломает идущий прогон.
{
set -uo pipefail
export LC_ALL=C

say() { printf 'remote-heavy: %s\n' "$*" >&2; }
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

# mask — адрес сервера и IPv4 в выводе kubectl заменяются: ошибка соединения
# печатает их дословно.
mask() {
    if [ -n "${SERVER_HOST:-}" ]; then
        sed -E -e "s#${SERVER_HOST//./\\.}#<кластер>#g" -e 's#([0-9]{1,3}\.){3}[0-9]{1,3}#<адрес>#g'
    else
        sed -E 's#([0-9]{1,3}\.){3}[0-9]{1,3}#<адрес>#g'
    fi
}

# kc <аргументы kubectl…> — только этот кубконфиг; stderr — через mask.
kc() {
    kubectl --kubeconfig "$KCFG" --request-timeout=30s "$@" 2> >(mask >&2)
}
# kc_stream — то же для потока лога: срок запроса оборвал бы поток через 30 с
# (опыт 2026-10-08: переподключение каждые 30 с), поэтому срока у него нет.
kc_stream() {
    kubectl --kubeconfig "$KCFG" "$@" 2> >(mask >&2)
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

case "${1:-}" in
    --available)
        if available; then echo "remote-heavy: кластер отвечает, создавать ns вправе"; exit 0; fi
        say "$WHY"; exit 69 ;;
    --profiles)
        while IFS='|' read -r n cr cl mr ml eph d basis; do
            printf '%-12s cpu %s/%s  память %s/%s  диск %s  dind %s\n%-12s основание: %s\n' "$n" "$cr" "$cl" "$mr" "$ml" "$eph" "$([ "$d" = 1 ] && echo да || echo нет)" "" "$basis"
        done <<< "$PROFILES"
        exit 0 ;;
    ''|-h|--help) sed -n '13,20p' "$0" >&2; exit 64 ;;
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

# ── кластер и уборка ─────────────────────────────────────────────────────────
available || { say "$WHY (не выполнилось)"; exit 69; }

BOX="$(mktemp -d "${TMPDIR:-/tmp}/remote-heavy.XXXXXX")" || { say "рабочий каталог не создан"; exit 69; }
CREATED=0; BG=""; DONE=0; TMPREF=""
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

jq -n --arg ns "$NSNAME" --arg task "$TASK" --arg repo "$REPO" --arg exp "$EXPIRES" --arg psa "$PSA" '{
  apiVersion: "v1", kind: "Namespace",
  metadata: {name: $ns,
    labels: {"kacho.io/task": $task, "kacho.io/stand": "test", "kacho.io/kind": "heavy", "kacho.io/repo": $repo,
             "pod-security.kubernetes.io/enforce": $psa},
    annotations: {"kacho.io/expires": $exp}}}' > "$BOX/ns.json"
# create, а не apply: существующее ns create не трогает, а apply переписал бы его
# метки, и trap снял бы чужое.
if ! out="$(kc create -f "$BOX/ns.json" 2>&1 >/dev/null)"; then
    case "$out" in
        *AlreadyExists*|*"already exists"*) say "ns $NSNAME уже есть — run.sh не берёт чужое и не продолжает чужой прогон"; exit 64 ;;
    esac
    say "ns $NSNAME не создано: $(head -n 1 <<< "$out") (не выполнилось)"; exit 69
fi
CREATED=1
say "ns $NSNAME создано: задача $TASK, $REPO@${SHA:0:12}, профиль $PROFILE, срок $EXPIRES"

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
# Команда — JSON-массивом через NUL: позиционные аргументы jq разбирал бы как свои
# флаги (`bash -c …` терял `-c`, опыт 2026-10-08).
CMD_JSON="$(printf '%s\0' "${CMD[@]}" | jq -Rsc 'split("\u0000")[:-1]')" || { say "команда не переведена в JSON"; exit 69; }
# shellcheck disable=SC2016  # раскрывается в pod, не здесь
PREP='set -e; export PATH=/tools:/work/bin:$PATH; cd "/work/src/$HEAVY_WORKDIR"'
[ "$PROFILE" = lint ] || [ "$PROFILE" = ci-local ] && [ -n "$LINT_PIN" ] && \
    PREP="$PREP; echo \"remote-heavy: ставлю golangci-lint $LINT_PIN\" >&2; GOBIN=/work/bin go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@$LINT_PIN"
[ "$PROFILE" = ci-local ] && [ -n "$GOSEC_PIN" ] && \
    PREP="$PREP; echo \"remote-heavy: ставлю gosec $GOSEC_PIN\" >&2; GOBIN=/work/bin go install github.com/securego/gosec/v2/cmd/gosec@$GOSEC_PIN"
PREP="$PREP; set +e; exec \"\$@\""

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
    --argjson cmd "$CMD_JSON" '{
  apiVersion: "batch/v1", kind: "Job",
  metadata: {name: "run", namespace: $ns, labels: {"kacho.io/task": $task, "kacho.io/kind": "heavy"}},
  spec: {backoffLimit: 0, activeDeadlineSeconds: $deadline, ttlSecondsAfterFinished: 3600,
   template: {metadata: {labels: {"kacho.io/task": $task, "kacho.io/kind": "heavy"}},
    spec: ({restartPolicy: "Never", enableServiceLinks: false, automountServiceAccountToken: false,
     initContainers: ((if $dind == 1 then [
       {name: "tools", image: $cimg, command: ["cp", "/usr/local/bin/docker", "/tools/docker"],
        volumeMounts: [{name: "tools", mountPath: "/tools"}]},
       {name: "dind", image: $dimg, restartPolicy: "Always", securityContext: {privileged: true},
        command: ["dockerd-entrypoint.sh"],
        args: ["dockerd", "--host=unix:///run/dind/docker.sock", "--registry-mirror=https://mirror.gcr.io"],
        env: [{name: "DOCKER_TLS_CERTDIR", value: ""}],
        startupProbe: {exec: {command: ["docker", "-H", "unix:///run/dind/docker.sock", "info"]}, periodSeconds: 2, failureThreshold: 150},
        resources: {requests: {cpu: $dcr, memory: $dmr}, limits: {cpu: $dcl, memory: $dml}},
        volumeMounts: [{name: "dind-lib", mountPath: "/var/lib/docker"}, {name: "dind-sock", mountPath: "/run/dind"}]}]
      else [] end) + [
       {name: "fetch", image: $goimg, command: ["sh", "-c", $fetch],
        env: [{name: "HEAVY_SHA", value: $sha}, {name: "HEAVY_MAIN", value: $main}],
        resources: {requests: {cpu: "100m", memory: "256Mi"}, limits: {cpu: "2", memory: "2Gi"}},
        volumeMounts: [{name: "work", mountPath: "/work"}]}]),
     containers: [{name: "run", image: $goimg, command: (["bash", "-c", $prep, "run"] + $cmd),
       env: ([{name: "HEAVY_WORKDIR", value: $wd}, {name: "GOTOOLCHAIN", value: "local"},
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
say "Job создан: образ golang:$GOVER$([ -n "$LINT_PIN" ] && [ "$PROFILE" != go-race ] && [ "$PROFILE" != integration ] && echo ", golangci-lint $LINT_PIN"), cpu $CPU_REQ/$CPU_LIM, память $MEM_REQ/$MEM_LIM$([ "$DIND" = 1 ] && echo ', dind')"

# pod_state — «имя|фаза|fetch|run|код run|причина run|ожидание|планирование».
pod_state() {
    kc -n "$NSNAME" get pods -l job-name=run -o json 2>/dev/null | jq -r '
      (.items[0] // {}) as $p |
      def st($n): ([($p.status.initContainerStatuses // [])[], ($p.status.containerStatuses // [])[]] | map(select(.name == $n)) | .[0] // {});
      def kind($s): if $s.state.running then "running" elif $s.state.terminated then "terminated" elif $s.state.waiting then "waiting" else "none" end;
      [ ($p.metadata.name // ""), ($p.status.phase // ""), kind(st("fetch")), kind(st("run")),
        (st("run").state.terminated.exitCode // "" | tostring), (st("run").state.terminated.reason // ""),
        ([($p.status.initContainerStatuses // [])[], ($p.status.containerStatuses // [])[]] | map(.state.waiting.reason // empty) | map(select(test("^PodInitializing$") | not)) | join(",")),
        (($p.status.conditions // []) | map(select(.type == "PodScheduled" and .status == "False") | .message) | join(" ")) ] | join("|")'
}

# wait_bg <pid> — ждать фонового: wait прерывается сигналом, и trap снимает ns сразу.
wait_bg() { BG="$1"; wait "$1"; local rc=$?; BG=""; return "$rc"; }

# ── доставка ─────────────────────────────────────────────────────────────────
# Bundle без ссылки git не собирает, а ревизия бывает голым sha: временная ссылка
# в своём пространстве имён живёт до конца сборки bundle.
TMPREF="refs/remote-heavy/$$-$(now)"
git -C "$SRC" update-ref "$TMPREF" "$SHA" || { say "временная ссылка на $SHA не создана"; exit 69; }
git -C "$SRC" bundle create "$BOX/src.bundle" "$TMPREF" ${MAIN_SHA:+refs/remotes/origin/main} >/dev/null 2>&1; brc=$?
git -C "$SRC" update-ref -d "$TMPREF"; TMPREF=""
[ "$brc" -eq 0 ] || { say "bundle ревизии $SHA не собран"; exit 69; }
POD=""
while :; do
    IFS='|' read -r POD PHASE FETCH_ST RUN_ST _ _ WAITR SCHED <<< "$(pod_state)"
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
kc -n "$NSNAME" exec -i "$POD" -c fetch -- sh -c 'cat > /work/in.bundle && touch /work/in.done' < "$BOX/src.bundle" & wait_bg $! \
    || { say "исходники не доставлены в pod (не выполнилось)"; exit 69; }
say "исходники доставлены: $(( $(stat -c %s "$BOX/src.bundle") / 1048576 )) МиБ bundle за $(( $(now) - T0 )) с от создания Job"

# ── команда ──────────────────────────────────────────────────────────────────
while :; do
    IFS='|' read -r POD PHASE FETCH_ST RUN_ST _ _ WAITR _ <<< "$(pod_state)"
    [ "$RUN_ST" = running ] || [ "$RUN_ST" = terminated ] && break
    if [ "$PHASE" = Failed ] || [ -z "$POD" ]; then
        kc -n "$NSNAME" logs "$POD" -c fetch 2>/dev/null | tail -n 20 >&2
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
    IFS='|' read -r POD PHASE _ RUN_ST RUN_RC RUN_REASON _ _ <<< "$(pod_state)"
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
if [ "$RUN_REASON" = OOMKilled ]; then
    say "команда оборвана пределом памяти $MEM_LIM (OOMKilled) через $(( T2 - T1 )) с — не выполнилось"; exit 76
fi
[[ "$RUN_RC" =~ ^[0-9]+$ ]] || { say "код команды не прочитан («$RUN_RC») — не выполнилось"; exit 69; }
say "команда завершилась кодом $RUN_RC за $(( T2 - T1 )) с (всего $(( T2 - T0 )) с от создания Job)"
exit "$RUN_RC"
}
