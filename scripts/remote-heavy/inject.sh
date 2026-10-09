#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# inject.sh — доказательство, что `run.sh` снимает своё ns на каждом исходе,
# передаёт код команды, не печатает адрес кластера и отказывает на чужом ns.
#
# Кластер — двойник kubectl в PATH пробы: он хранит ns, Job и доставку в своём
# каталоге и отвечает тем, что даёт настоящий API (pod с фазами контейнеров,
# AlreadyExists, предупреждение в stderr). Исходники — настоящий git-клон пробы,
# bundle собирается и «доставляется» настоящим потоком stdin. Двойник печатает в
# stderr адрес сервера и IPv4 на КАЖДОМ вызове — как kubectl с предупреждением и
# ошибкой соединения, — поэтому маска run.sh судится настоящим входом; что двойник
# их действительно печатает, утверждает отдельный случай (L0), иначе проба утечки
# была бы пустой.
#
#   K1 команда кодом 0                     → код 0; ns снято; метки и срок на ns
#   K2 команда кодом 42                    → код 42; ns снято
#   K3 TERM посреди идущей команды         → код 143; ns снято; выход ≤ 20 с
#   K4 контейнер OOMKilled                 → код 76; ns снято
#   K6 подготовка pod не удалась            → 69; ns снято; близнец K6b — код 125 команды
#   K5 --keep 2                            → код команды; ns НЕ снято; срок ≈ +2 ч
#   R1 NS=kacho                            → 64; к кластеру ни одного обращения
#   R2 --ns kacho                          → 64; к кластеру ни одного обращения
#   R3 --ns вне формы t<задача>-heavy-…    → 64; к кластеру ни одного обращения
#   X1 current-context файла = infra       → прогон в client: каждый вызов kubectl
#      несёт --context client, current-context не изменён (решение владельца
#      2026-10-09 «тебе можно ставить только в client»)
#   X2 KACHO_REMOTE_CONTEXT не на -client  → 64; к kubectl ни одного обращения;
#      близнец X2b — на client → 0; X2c названного нет → 69
#   X3 в файле нет контекста -client       → 69, run и --available, шаг назван
#   X4 контекстов -client два              → 69, шаг назван
#   R4 ns уже есть (близнец K1)            → 64; чужое ns НЕ снято
#   A1 Job — в своём ns t<N>-heavy-*, условий узла по стенду нет: ни
#      podAntiAffinity, ни nodeAffinity, ни упоминания ns kacho в affinity
#      (решение владельца 2026-10-09 «не запускать в NS качо а не на узлах»);
#      каждый созданный объект — в ns прогона; запросы и пределы — числом
#   U0 pod в своём пространстве пользователей (hostUsers: false)
#   U1 профиль с dind: privileged нет нигде, dind на crun без cgroup (F1)
#   S0 сервер добавил законные умолчания   → 0 (близнец S1–S3)
#   S1 API снял hostUsers (Job и pod)       → 69; ns снято и при --keep; доставки нет
#   S2 вебхук снял procMount dind в pod     → 69 до доставки
#   S3 вебхук сделал fetch privileged       → 69 до доставки
#   U2 проверка userns — первой строкой dind и run одним текстом; над поддельным
#      /proc (sh и bash): «0 0 4294967295», 0→0 узла, 0 узла второй строкой,
#      тождественный gid_map —
#      125 и запись в termination-log; законное отображение — 0
#   U3 двойник: dind с тождественным uid_map отказал → 69; ns снято; доставки нет
#   U4 run отказал той же проверкой (код 125) → 69, а не код команды (ср. K6b)
#   N1 NetworkPolicy ns: входящих нет; исходящие — DNS (53) и мир без частных
#      диапазонов, адресов узлов, диапазона служб и управления кластера (F2)
#   P1 проба закрытости в pod — служба kacho, не закрытая политикой kacho;
#      близнец (закрытая) не выбран
#   C1 идущих 2 при пределе 2              → 75, create не звался (F3)
#   C2 близнец: их Job завершены           → 0
#   C3 близнец: срок ns в прошлом          → 0
#   C4 гонка: чужое ns создано раньше      → 75, своё ns снято, Job нет
#   C4b близнец без гонки                  → 0
#   C5 гонка при --keep                    → 75, ns всё равно снято
#   V2 --available при занятом кластере    → 75; близнец V2b → 0
#   M1 KACHO_REMOTE_HEAVY_MAX=0            → 64
#   Q1 стенд (pod ns kacho) на всех узлах, место есть → --available 0 и прогон 0
#      (стенд узел не запирает); Q1d два go-race рядом со стендом замера
#      2026-10-09 на ОДНОМ узле — второй тоже встаёт → 0
#   Q3 единственный узел не готов / закрыт / taint NoSchedule → 69; прогон 69 без ns
#   Q2 места под go-race нет ни на одном узле → 75 и прогон 75 без ns; близнец Q2b
#      тот же кластер, профиль lint → 0 и прогон 0; Q2c профиля нет → 64
#   Q5 перепись pod кластера > 128 КиБ (строка аргумента) → разбирается, 0
#   Q4 pod ждёт планирования, чужой pod занял последнее место → 75 сразу, ns снято
#      и при --keep; близнец Q4b место есть → run.sh ждёт дальше
#   O1 строки run.sh после выбора ns несут его имя
#   O2 stderr — файл, в который пишет посторонний живой процесс → предупреждение с
#      его pid; близнец O2b файл держат только предки прогона → молчание
#   G1 остатки kill -9 (каталог, процесс, ns, ссылка) мёртвого владельца → сняты
#   G2 близнецы: живой владелец и ns с чужой меткой — не тронуты
#   L0 двойник сам печатает адрес и IPv4   → да (контроль пробы утечки)
#   L0b двойник печатает адреса pod в stdout лога → да (контроль F4)
#   L1 вывод всех случаев без адреса сервера, IPv4/IPv6 узлов и pod, токена,
#      имён контекстов и пути кубконфига (F4: stdout лога тоже)
#   V1 кластер не отвечает (--available)   → 69, причина без адреса
#   W1 узлы с -infra-                       → 69, run и --available, записей ноль, шаг
#      назван (решение владельца 2026-10-10 «По префиксу нод можешь понять тот
#      кластер или нет, куб конфет мог меняться»)
#   W2 узлы смешанные (client и infra)      → 69, записей ноль
#   W3 узлов ноль                           → 69, run и --available, записей ноль
#   W4 узлы чужого профиля (-client-)       → 69, записей ноль
#   W5 узлы профиля → 0, и перепись узлов — раньше первой записи
#   W6 профиль из имени файла <учётка>--<профиль>.yaml без переменной → 0;
#      близнец W6b тот же файл, узлы чужого профиля → 69
#   W7 профиль не выводится (ни имени, ни переменной) → 69 до кластера
#   W8 переменная и имя файла расходятся     → 69 до кластера
#   W9 файл подменён после создания ns, узлы стали infra → 69 до сети ns; ns НЕ
#      снято (оно в прежнем кластере), шаг назван; близнец W9b — файл сменился,
#      узлы те же → 0, узлы переписаны заново
#   W10 узлы с -infra- при остатках мёртвого владельца → 69, уборка ns не звалась
#
# Запуск: bash scripts/remote-heavy/inject.sh   (код 0 — все случаи сошлись)
set -uo pipefail
export LC_ALL=C

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN="$SELF_DIR/run.sh"
BOX="$(mktemp -d)" || { echo "inject: каталог пробы не создан" >&2; exit 2; }
trap 'rm -rf -- "$BOX"' EXIT

SERVER_HOST="sentinel-cluster.invalid"
SERVER_IP="203.0.113.7"
TOKEN="SENTINEL-TOKEN-5f1c"
# Адреса, которые настоящий кластер отдаёт в выводе: узла (в сеть ns) и pod/dind
# (в лог команды). Ни один не должен дойти до вывода run.sh.
export FAKE_NODE_IP="198.51.100.10" FAKE_NODE_IP6="2001:db8::10" FAKE_API_IP="198.51.100.77"
export FAKE_POD_IP="192.0.2.44" FAKE_POD_IP6="2001:db8:0:1::44"
PASS=0; FAIL=0; ALL_OUT="$BOX/all.out"; : > "$ALL_OUT"

mkdir -p "$BOX/bin" "$BOX/state"
# kubeconfig_with <current> <контекст>… — кубконфиг пробы (JSON — тоже кубконфиг):
# current-context смотрит на <current>, как файл профиля, который владелец вручную
# переключил на infra (опыт 2026-10-09).
kubeconfig_with() {
    local cur="$1"; shift
    jq -n --arg s "https://$SERVER_HOST:6443" --arg t "$TOKEN" --arg cur "$cur" '{apiVersion: "v1", kind: "Config",
      clusters: [{name: "c", cluster: {server: $s}}], users: [{name: "u", user: {token: $t}}],
      contexts: [$ARGS.positional[] | {name: ., context: {cluster: "c", user: "u"}}], "current-context": $cur}' --args "$@"
}
CTX_CLIENT="lab-a1-client"; CTX_INFRA="lab-a1-infra"
# Профиль кластера пробы (СТРАЖ run.sh): узлы двойника — «lab1-client-<пул>-…».
# Случаи W снимают переменную и выводят профиль из имени файла.
export KACHO_REMOTE_PROFILE=lab1
NODE_PFX="lab1-client-p00l-"
export FAKE_NODE_PFX="$NODE_PFX"
kubeconfig_with "$CTX_INFRA" "$CTX_INFRA" "$CTX_CLIENT" > "$BOX/kubeconfig"

# ── двойник kubectl ──────────────────────────────────────────────────────────
cat > "$BOX/bin/kubectl" <<'FAKE'
#!/usr/bin/env bash
set -uo pipefail
S="$FAKE_STATE"
mkdir -p "$S/ns" "$S/jobs"
mkdir -p "$S/ns" "$S/jobs"
echo "$*" >> "$S/calls"
echo "Warning: cluster https://$FAKE_HOST:6443 ($FAKE_IP) answered slowly" >&2
ns=""; sel=""; all=0; ctx=""; kcfg=""
args=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --kubeconfig) kcfg="$2"; shift 2 ;;
        --context) ctx="$2"; shift 2 ;;
        --request-timeout=*|--field-selector=*|--wait=*|--timeout=*) shift ;;
        -n) ns="$2"; shift 2 ;;
        -l) sel="$2"; shift 2 ;;
        -o) shift 2 ;;
        -A) all=1; shift ;;
        *) args+=("$1"); shift ;;
    esac
done
set -- "${args[@]}"
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
# spec_of job|pod — spec pod из сохранённого Job, как его вернул бы «сервер»:
# FAKE_DROP_HOSTUSERS=1 — API без поддержки userns молча снял hostUsers (и в Job,
# и в pod); FAKE_POD_MUT — вебхук правит pod: procmount (снят у dind), privileged
# (fetch привилегирован), defaults (законные умолчания сервера — близнец).
spec_of() {
    jq -c --arg w "$1" '.spec.template.spec
      | if ($ENV.FAKE_DROP_HOSTUSERS // "") == "1" then del(.hostUsers) else . end
      | if $w != "pod" then .
        elif ($ENV.FAKE_POD_MUT // "") == "procmount" then (.initContainers[] | select(.name == "dind") | .securityContext) |= del(.procMount)
        elif ($ENV.FAKE_POD_MUT // "") == "privileged" then (.initContainers[] | select(.name == "fetch") | .securityContext) |= ((. // {}) + {privileged: true})
        elif ($ENV.FAKE_POD_MUT // "") == "defaults" then
          (.initContainers, .containers) |= map(.securityContext = ({procMount: "Default", allowPrivilegeEscalation: true} + (.securityContext // {})) | .terminationMessagePath = "/dev/termination-log")
          | .dnsPolicy = "ClusterFirst" | .hostNetwork = false
        else . end' "$S/job.json"
}
# pods <status> — список из одного pod со spec «сервера».
pods() { jq -nc --argjson sp "$(spec_of pod)" --argjson st "$1" '{items: [{metadata: {name: "run-x"}, spec: $sp, status: $st}]}'; }
# Без --context kubectl берёт current-context файла; контекст не -client ведёт себя
# как infra 2026-10-09: изменяющий запрос отклоняет политика допуска.
[ -n "$ctx" ] || [ -z "$kcfg" ] || ctx="$(jq -r '."current-context"' "$kcfg")"
case "$1" in
    create|apply|delete|exec|patch|label|annotate)
        case "$ctx" in *-client) ;; *)
            echo "Error from server (Forbidden): admission webhook denied the request: policy host-access-allowlist (context $ctx)" >&2; exit 1 ;;
        esac ;;
esac
case "$1 ${2:-}" in
    "config get-contexts") jq -r '.contexts[].name' "$kcfg" ;;
    "config view") printf 'https://%s:6443' "$FAKE_HOST" ;;
    "auth can-i")
        if [ "${FAKE_DOWN:-0}" = 1 ]; then
            echo "Unable to connect to the server: dial tcp $FAKE_IP:6443: i/o timeout" >&2; exit 1
        fi
        echo yes ;;
    "create -f")
        kind="$(jq -r .kind "$3")"
        if [ "$kind" = Namespace ]; then
            name="$(jq -r .metadata.name "$3")"
            if [ -e "$S/ns/$name" ]; then
                echo "Error from server (AlreadyExists): namespaces \"$name\" already exists" >&2; exit 1
            fi
            mkdir -p "$S/ns"
            # FAKE_SWAP_FILE — файл кубконфига подменён сразу после создания ns (опыт
            # 2026-10-10); FAKE_NODES_AFTER_NS — узлы, которые с этого мига видны.
            if [ -n "${FAKE_SWAP_FILE:-}" ]; then echo ' ' >> "$FAKE_SWAP_FILE"; touch "$S/swapped"; fi
            jq --arg t "$(now)" '.metadata.creationTimestamp = $t | .status.phase = "Active"' "$3" > "$S/ns/$name"
            # гонка: другой запуск создал своё ns мгновением раньше
            if [ -n "${FAKE_RACE:-}" ]; then
                jq -n --arg n "$FAKE_RACE" --arg t "$(date -u -d '-1 second' +%Y-%m-%dT%H:%M:%SZ)" --arg e "$(date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%SZ)" \
                    '{kind: "Namespace", metadata: {name: $n, creationTimestamp: $t, labels: {"kacho.io/kind": "heavy"}, annotations: {"kacho.io/expires": $e}}, status: {phase: "Active"}}' > "$S/ns/$FAKE_RACE"
            fi
        elif [ "$kind" = NetworkPolicy ]; then
            cp "$3" "$S/netpol.json"
        else
            cp "$3" "$S/job.json"
        fi ;;
    "apply -f") cp "$3" "$S/applied.json" ;;
    "get ns")
        if [ -n "${3:-}" ]; then
            [ -f "$S/ns/$3" ] || { echo "Error from server (NotFound): namespaces \"$3\" not found" >&2; exit 1; }
            cat "$S/ns/$3"
        else
            find "$S/ns" -type f -exec cat {} + 2>/dev/null | jq -s --arg sel "$sel" '{items: [.[] | select(($sel == "") or (.metadata.labels["kacho.io/kind"] == "heavy"))]}'
        fi ;;
    "get jobs") find "$S/jobs" -type f -exec cat {} + 2>/dev/null | jq -s '{items: .}' ;;
    "get svc")
        if [ "$all" = 1 ]; then
            echo '{"items":[{"metadata":{"namespace":"dns-sys","name":"dns"},"spec":{"selector":{"k8s-app":"dns"},"ports":[{"port":53,"protocol":"UDP"},{"port":53,"protocol":"TCP"}]}},
                            {"metadata":{"namespace":"dns-sys","name":"dns-metrics"},"spec":{"selector":{"k8s-app":"dns"},"ports":[{"port":9153,"protocol":"TCP"}]}}]}'
        else
            echo '{"items":[{"metadata":{"name":"edge"},"spec":{"type":"ClusterIP","clusterIP":"10.96.0.20","selector":{"app":"edge"},"ports":[{"port":8080}]}},
                            {"metadata":{"name":"svc-a"},"spec":{"type":"ClusterIP","clusterIP":"10.96.0.21","selector":{"app":"svc-a"},"ports":[{"port":9090}]}}]}'
        fi ;;
    "get netpol") echo '{"items":[{"spec":{"podSelector":{"matchLabels":{"app":"edge"}}}}]}' ;;
    "get nodes")
        # FAKE_NODES — список узлов случая размещения; иначе один готовый узел.
        if [ -e "$S/swapped" ] && [ -n "${FAKE_NODES_AFTER_NS:-}" ]; then printf '%s\n' "$FAKE_NODES_AFTER_NS"; exit 0; fi
        if [ -n "${FAKE_NODES:-}" ]; then printf '%s\n' "$FAKE_NODES"; exit 0; fi
        jq -n --arg e "$FAKE_NODE_IP" --arg v6 "$FAKE_NODE_IP6" --arg n "${FAKE_NODE_PFX}n1" '{items: [{metadata: {name: $n},
          status: {addresses: [{type: "ExternalIP", address: $e}, {type: "InternalIP", address: "10.0.0.5"}, {type: "InternalIP", address: $v6}, {type: "Hostname", address: $n}],
                   conditions: [{type: "Ready", status: "True"}], allocatable: {cpu: "15500m", memory: "30913596Ki"}}}]}' ;;
    "get endpointslices") jq -n --arg a "$FAKE_API_IP" '{items: [{endpoints: [{addresses: [$a]}]}]}' ;;
    "get servicecidrs") echo '{"items":[{"spec":{"cidrs":["10.96.0.0/12"]}}]}' ;;
    "get pods")
        # -A — перепись pod кластера для размещения: FAKE_CLUSTER_PODS, а после
        # создания Job — FAKE_PODS_AFTER_JOB (стенд встал на узел, пока pod ждал).
        if [ "$all" = 1 ]; then
            none='{"items":[]}'
            if [ -e "$S/job.json" ] && [ -n "${FAKE_PODS_AFTER_JOB:-}" ]; then printf '%s\n' "$FAKE_PODS_AFTER_JOB"
            elif [ -n "${FAKE_CLUSTER_PODS_FILE:-}" ]; then cat "$FAKE_CLUSTER_PODS_FILE"
            else printf '%s\n' "${FAKE_CLUSTER_PODS:-$none}"; fi
            exit 0
        fi
        if [ ! -e "$S/job.json" ]; then echo '{"items":[]}'; exit 0; fi
        # FAKE_UNSCHED — планировщик не находит узла: pod ждёт, условие PodScheduled False.
        if [ "${FAKE_UNSCHED:-0}" = 1 ]; then
            pods '{"phase":"Pending","conditions":[{"type":"PodScheduled","status":"False","message":"0/1 nodes are available: 1 node(s) didn'"'"'t match pod anti-affinity rules."}]}'
            exit 0
        fi
        # FAKE_USERNS_DIND — dind отказал проверкой userns и перезапускается: fetch не
        # начинается никогда, отказ — в lastState бокового.
        if [ -n "${FAKE_USERNS_DIND:-}" ]; then
            pods "$(jq -nc --arg m "$FAKE_USERNS_DIND" '{phase: "Pending", initContainerStatuses: [
                {name: "dind", state: {waiting: {reason: "CrashLoopBackOff"}}, lastState: {terminated: {exitCode: 125, message: $m}}},
                {name: "fetch", state: {waiting: {reason: "PodInitializing"}}}], containerStatuses: [{name: "run", state: {waiting: {reason: "PodInitializing"}}}]}')"
            exit 0
        fi
        if [ ! -e "$S/delivered" ]; then
            pods '{"phase":"Pending","initContainerStatuses":[{"name":"fetch","state":{"running":{}}}],"containerStatuses":[{"name":"run","state":{"waiting":{"reason":"PodInitializing"}}}]}'
            exit 0
        fi
        if [ "${FAKE_HANG:-0}" = 1 ]; then
            pods '{"phase":"Running","initContainerStatuses":[{"name":"fetch","state":{"terminated":{"exitCode":0}}}],"containerStatuses":[{"name":"run","state":{"running":{}}}]}'
            exit 0
        fi
        reason=Completed; [ "${FAKE_OOM:-0}" = 1 ] && reason=OOMKilled
        pods "$(jq -nc --argjson rc "${FAKE_EXIT:-0}" --arg r "$reason" --arg m "${FAKE_MSG:-}" '{phase:(if $rc == 0 then "Succeeded" else "Failed" end),
            initContainerStatuses:[{name:"fetch",state:{terminated:{exitCode:0}}}],
            containerStatuses:[{name:"run",state:{terminated:{exitCode:$rc,reason:$r,message:$m}}}]}')" ;;
    "exec -i") cat > "$S/bundle"; touch "$S/delivered" ;;
    "logs -f")
        echo "строка лога команды: pod $FAKE_POD_IP, dind $FAKE_POD_IP6"
        touch "$S/logging"
        # Висит, пока жив вызвавший run.sh: срок — предикат, а не время.
        if [ "${FAKE_HANG:-0}" = 1 ]; then
            for _ in $(seq 1 600); do kill -0 "$PPID" 2>/dev/null || exit 0; sleep 0.1; done
        fi ;;
    "logs run-x") : ;;
    "get events") echo '{"items":[]}' ;;
    "delete ns") rm -f "$S/ns/$3"; echo "$3" >> "$S/deleted" ;;
    "get job")
        [ -e "$S/job.json" ] || { echo "Error from server (NotFound): jobs.batch \"run\" not found" >&2; exit 1; }
        jq -c --argjson sp "$(spec_of job)" '.spec.template.spec = $sp | .status = {}' "$S/job.json" ;;
    *) echo "двойник: вызов «$*» не знаком" >&2; exit 9 ;;
esac
FAKE
chmod +x "$BOX/bin/kubectl"

# ── клон пробы ───────────────────────────────────────────────────────────────
SRC="$BOX/src"
git init -q "$SRC"
mkdir -p "$SRC/.github/workflows"
printf 'module example.com/x\n\ngo 1.26.0\n\ntoolchain go1.26.8\n' > "$SRC/go.mod"
printf 'jobs:\n  lint:\n    steps:\n      - run: go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.12.2\n' > "$SRC/.github/workflows/ci.yaml"
git -C "$SRC" add -A
# shellcheck source=scripts/lib/sandbox-git-home.sh
. "$SELF_DIR/../lib/sandbox-git-home.sh"
sandbox_git_home "$BOX/ghome" || { echo "inject: корневой подписи нет — клон пробы не построен (не выполнилось)" >&2; exit 2; }
sandbox_git -C "$SRC" commit -q -m probe

fresh() { rm -rf "$BOX/state"; mkdir -p "$BOX/state/ns"; }

# go <имя> — запуск run.sh в окружении двойника; код — в RC, вывод — в OUT.
go_run() {
    local name="$1"; shift
    OUT="$BOX/$name.out"
    # Срок — чтобы дефект, на котором run.sh ждёт свои 900 с, краснел, а не висел.
    timeout 90 env PATH="$BOX/bin:$PATH" FAKE_STATE="$BOX/state" FAKE_HOST="$SERVER_HOST" FAKE_IP="$SERVER_IP" \
        KACHO_REMOTE_KUBECONFIG="$BOX/kubeconfig" TMPDIR="$BOX" "$@" > "$OUT" 2>&1
    RC=$?
    cat "$OUT" >> "$ALL_OUT"
}
base() { printf '%s\n' bash "$RUN" --task 1 --repo kaname --ref HEAD --src "$SRC" --profile lint; }

ok() { PASS=$((PASS + 1)); }
bad() { printf 'ПРОВАЛ %s: %s\n' "$1" "$2"; [ -n "${OUT:-}" ] && sed 's/^/    /' "$OUT"; FAIL=$((FAIL + 1)); }
expect_rc() { if [ "$RC" -eq "$2" ]; then ok; else bad "$1" "код $RC, ждали $2"; fi; }
ns_left() { find "$BOX/state/ns" -type f | wc -l; }
expect_ns_gone() {
    if [ "$(ns_left)" -eq 0 ] && grep -qx "$2" "$BOX/state/deleted" 2>/dev/null; then ok; else bad "$1" "ns $2 не снято (осталось $(ns_left))"; fi
}

mapfile -t B < <(base)

# K1
fresh
go_run k1 env FAKE_EXIT=0 "${B[@]}" --short k1 -- true
expect_rc K1 0
expect_ns_gone K1 t1-heavy-k1
# A1 — стенд держит пространство, а не узел (решение владельца 2026-10-09): Job в
# своём ns, без условий узла по стенду, ресурсы run — числом.
J="$BOX/state/job.json"
if [ "$(jq -r '.metadata.namespace' "$J" 2>/dev/null)" = t1-heavy-k1 ]; then ok
else OUT="$J"; bad A1 "Job не в ns прогона t1-heavy-k1"; fi
if jq -e '.spec.template.spec | (has("affinity") or has("nodeSelector") or has("nodeName"))' "$J" >/dev/null 2>&1; then
    OUT="$J"; bad A1 "в Job есть условие узла (affinity/nodeSelector/nodeName) — стенд держит ns, а не узел"
else ok; fi
if jq -e '[.. | strings | select(. == "kacho")] | length > 0' "$J" >/dev/null 2>&1; then
    OUT="$J"; bad A1 "Job называет ns kacho"
else ok; fi
if jq -e '.spec.template.spec.containers[0].resources | (.requests.cpu and .requests.memory and .limits.cpu and .limits.memory)' "$J" >/dev/null 2>&1; then ok
else OUT="$J"; bad A1 "у run нет запросов и пределов cpu и памяти числом"; fi
# A1 — ни одна изменяющая команда не адресована ns kacho (чтение служб для пробы
# закрытости — законно); близнец — изменяющие команды прогона в его ns были
grep -E '(^| )(create|apply|delete|exec|patch|label|annotate)( |$)' "$BOX/state/calls" > "$BOX/mutating.calls"
if grep -qE '(-n kacho( |$)|ns kacho( |$))' "$BOX/mutating.calls"; then
    bad A1 "изменяющая команда адресована ns kacho"
else ok; fi
grep -E '(^| )(exec|delete)( |$)' "$BOX/state/calls" > "$BOX/own.calls"
if grep -qE '(-n t1-heavy-k1 |ns t1-heavy-k1)' "$BOX/own.calls"; then ok
else bad A1 "изменяющих команд в ns прогона не видно — проверка выше пуста"; fi
# X1 — current-context файла смотрит на infra (опыт 2026-10-09), прогон K1 всё
# равно в client: КАЖДЫЙ вызов kubectl, кроме чтения списка контекстов, несёт
# --context <client>; ни одного без него и ни одного в infra. Двойник в контексте
# не -client отклоняет изменяющие запросы, как политика допуска infra, — K1 с кодом 0
# уже это подтверждает; здесь — перепись вызовов.
n_calls="$(grep -vc ' config get-contexts ' "$BOX/state/calls")"
n_client="$(grep -v ' config get-contexts ' "$BOX/state/calls" | grep -c -- "--context $CTX_CLIENT ")"
if [ "$n_calls" -gt 0 ] && [ "$n_calls" -eq "$n_client" ]; then ok
else bad X1 "вызовов kubectl $n_calls, с --context client $n_client"; fi
if grep -q -- "$CTX_INFRA" "$BOX/state/calls"; then bad X1 "вызов в контексте infra"; else ok; fi
if [ "$(jq -r '."current-context"' "$BOX/kubeconfig")" = "$CTX_INFRA" ]; then ok; else bad X1 "current-context кубконфига изменён"; fi
# N1 — сеть ns: входящих нет, исходящие — DNS и мир без частных, узлов и служб (F2)
NP="$BOX/state/netpol.json"
if jq -e --arg n4 "$FAKE_NODE_IP/32" --arg n6 "$FAKE_NODE_IP6/128" --arg a4 "$FAKE_API_IP/32" '
     .spec.podSelector == {} and (.spec.policyTypes | sort) == ["Egress", "Ingress"] and (.spec.ingress // []) == []
     and ([.spec.egress[].to[]] | all(.ipBlock or (.namespaceSelector.matchLabels["kubernetes.io/metadata.name"] == "dns-sys" and .podSelector.matchLabels["k8s-app"] == "dns")))
     and ([.spec.egress[] | select(any(.to[]; .namespaceSelector)) | .ports[] | "\(.protocol)/\(.port)"] | sort) == ["TCP/53", "UDP/53"]
     and ([.spec.egress[].to[] | .ipBlock | select(.cidr == "0.0.0.0/0") | .except[]] as $e
          | (["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10", "169.254.0.0/16", $n4, $a4, "10.96.0.0/12"] - $e) == [])
     and ([.spec.egress[].to[] | .ipBlock | select(.cidr == "::/0") | .except[]] as $e | (["fc00::/7", "fe80::/10", $n6] - $e) == [])' "$NP" >/dev/null 2>&1; then ok
else OUT="$NP"; bad N1 "сетевой политики ns нет либо она пропускает кластер"; fi
# P1 — проба закрытости в pod: служба ns kacho, НЕ закрытая собственной политикой kacho
# (edge закрыта политикой kacho — близнец, который выбран быть не должен)
if [ "$(jq -r '.spec.template.spec.containers[0].env[] | select(.name == "HEAVY_DENY_PROBE") | .value' "$J" 2>/dev/null)" = "svc-a.kacho.svc:9090" ]; then ok
else OUT="$J"; bad P1 "HEAVY_DENY_PROBE не svc-a.kacho.svc:9090"; fi
# U0 — профиль без dind: pod тоже в своём пространстве пользователей
if jq -e '.spec.template.spec.hostUsers == false' "$J" >/dev/null 2>&1; then ok; else OUT="$J"; bad U0 "hostUsers не false"; fi

# U1 — профиль с dind: privileged нет ни у одного контейнера, pod в userns, dind на crun без cgroup (F1)
fresh
go_run u1 env FAKE_EXIT=0 bash "$RUN" --task 1 --repo kaname --ref HEAD --src "$SRC" --profile integration --short u1 -- true
expect_rc U1 0
if jq -e '.spec.template.spec.hostUsers == false
          and ([.. | objects | select(has("privileged")) | .privileged] | all(. == false))
          and ([.spec.template.spec.initContainers[] | select(.name == "dind")] | length == 1)
          and (.spec.template.spec.initContainers[] | select(.name == "dind") | .securityContext.privileged == false
               and (.command | join(" ") | test("crun.*--cgroup-manager=disabled")))' "$J" >/dev/null 2>&1; then ok
else OUT="$J"; bad U1 "dind привилегирован либо pod не в своём пространстве пользователей"; fi
cp "$J" "$BOX/u1-job.json"

# ── пространство пользователей ИСПОЛНЕНИЕМ (ревью ws#984, N1) ───────────────
# no_delivery <случай> — исходники в pod не ушли: кода ветки там не было.
no_delivery() { if [ -e "$BOX/state/bundle" ]; then bad "$1" "исходники доставлены до отказа"; else ok; fi; }
# S0 — законный близнец: сервер добавил свои умолчания (procMount Default и пр.) → 0
fresh
go_run s0 env FAKE_EXIT=0 FAKE_POD_MUT=defaults bash "$RUN" --task 1 --repo kaname --ref HEAD --src "$SRC" --profile integration --short s0 -- true
expect_rc S0 0
# S1 — API-сервер молча снял hostUsers (в Job и pod) → 69, ns снято и при --keep, доставки нет
fresh
go_run s1 env FAKE_EXIT=0 FAKE_DROP_HOSTUSERS=1 bash "$RUN" --task 1 --repo kaname --ref HEAD --src "$SRC" --profile integration --short s1 --keep 2 -- true
expect_rc S1 69
expect_ns_gone S1 t1-heavy-s1
no_delivery S1
if grep -q 'hostUsers снято' "$OUT"; then ok; else bad S1 "причина не названа (hostUsers)"; fi
# S2 — вебхук снял procMount у dind в pod (Job цел) → 69 до доставки
fresh
go_run s2 env FAKE_EXIT=0 FAKE_POD_MUT=procmount bash "$RUN" --task 1 --repo kaname --ref HEAD --src "$SRC" --profile integration --short s2 -- true
expect_rc S2 69
expect_ns_gone S2 t1-heavy-s2
no_delivery S2
if grep -q 'контейнер dind: securityContext.procMount' "$OUT"; then ok; else bad S2 "причина не названа (procMount dind)"; fi
# S3 — вебхук сделал fetch привилегированным → 69 до доставки
fresh
go_run s3 env FAKE_EXIT=0 FAKE_POD_MUT=privileged bash "$RUN" --task 1 --repo kaname --ref HEAD --src "$SRC" --profile integration --short s3 -- true
expect_rc S3 69
no_delivery S3
if grep -q 'контейнер fetch: privileged без запроса' "$OUT"; then ok; else bad S3 "причина не названа (privileged fetch)"; fi

# U2 — проверка в pod: текст берётся из Job (команда dind и run), стоит ПЕРВЫМ и
# исполняется над поддельным /proc: sh — как busybox dind, bash — как run.
UJ="$BOX/u1-job.json"; UP="$BOX/uproc"; mkdir -p "$UP"
jq -r '.spec.template.spec.initContainers[] | select(.name == "dind") | .command[2]' "$UJ" > "$BOX/dind.cmd"
jq -r '.spec.template.spec.containers[] | select(.name == "run") | .command[2]' "$UJ" > "$BOX/run.cmd"
sed -n '1,/^# userns-end$/p' "$BOX/dind.cmd" > "$BOX/userns.sh"
if grep -q '^# userns-end$' "$BOX/userns.sh" && [ "$(sed -n '1,/^# userns-end$/p' "$BOX/run.cmd")" = "$(cat "$BOX/userns.sh")" ] \
   && [[ "$(head -n 1 "$BOX/userns.sh")" == 'uf() '* ]]; then ok
else OUT="$BOX/dind.cmd"; bad U2 "проверка userns не стоит первой строкой dind и run одним текстом"; fi
sed -e "s#/proc/self/#$UP/#g" -e "s#/dev/termination-log#$UP/tl#g" "$BOX/userns.sh" > "$BOX/userns-fake.sh"
# userns_case <случай> <оболочка> <uid_map> <gid_map> <код>
userns_case() {
    printf '%s\n' "$3" > "$UP/uid_map"; printf '%s\n' "$4" > "$UP/gid_map"; rm -f "$UP/tl"
    OUT="$BOX/$1.out"; "$2" "$BOX/userns-fake.sh" > "$OUT" 2>&1; RC=$?
    expect_rc "$1" "$5"
    if [ "$5" -ne 0 ]; then
        if grep -q '^remote-heavy-userns: ' "$UP/tl" 2>/dev/null; then ok; else bad "$1" "отказ не записан в termination-log"; fi
    fi
}
LEGIT="0 1879048192 65536"
for sh_ in sh bash; do
    userns_case "U2-$sh_-identity" "$sh_" "0 0 4294967295" "$LEGIT" 125
    userns_case "U2-$sh_-root" "$sh_" "0 0 65536" "$LEGIT" 125
    userns_case "U2-$sh_-gid" "$sh_" "$LEGIT" "         0          0 4294967295" 125
    userns_case "U2-$sh_-tail" "$sh_" "$(printf '0 1879048192 65536\n65536 0 1')" "$LEGIT" 125
    userns_case "U2-$sh_-legit" "$sh_" "         0 1879048192      65536" "$LEGIT" 0
done
printf '0 0 4294967295\n' > "$UP/uid_map"; rm -f "$UP/tl"; sh "$BOX/userns-fake.sh" >/dev/null 2>&1
USERNS_MSG="$(cat "$UP/tl" 2>/dev/null)"
# U3 — двойник: dind с тождественным uid_map отказал (его текст из U2) → 69, ns снято, доставки нет
fresh
go_run u3 env FAKE_EXIT=0 FAKE_USERNS_DIND="$USERNS_MSG" bash "$RUN" --task 1 --repo kaname --ref HEAD --src "$SRC" --profile integration --short u3 --keep 2 -- true
expect_rc U3 69
expect_ns_gone U3 t1-heavy-u3
no_delivery U3
if grep -q 'пространство пользователей pod не изолировано — dind: remote-heavy-userns:' "$OUT"; then ok; else bad U3 "отказ dind не прочитан"; fi
# U4 — run отказал той же проверкой (код 125, как у K6b) → 69, а не код команды
fresh
go_run u4 env FAKE_EXIT=125 FAKE_MSG="$USERNS_MSG" "${B[@]}" --short u4 -- true
expect_rc U4 69
expect_ns_gone U4 t1-heavy-u4

# K2
fresh
go_run k2 env FAKE_EXIT=42 "${B[@]}" --short k2 -- false
expect_rc K2 42
expect_ns_gone K2 t1-heavy-k2

# K3 — TERM посреди команды
fresh
(
    env PATH="$BOX/bin:$PATH" FAKE_STATE="$BOX/state" FAKE_HOST="$SERVER_HOST" FAKE_IP="$SERVER_IP" FAKE_HANG=1 \
        KACHO_REMOTE_KUBECONFIG="$BOX/kubeconfig" TMPDIR="$BOX" "${B[@]}" --short k3 -- true > "$BOX/k3.out" 2>&1 &
    pid=$!
    for _ in $(seq 1 100); do [ -e "$BOX/state/logging" ] && break; sleep 0.1; done
    t0=$(date +%s)
    kill -TERM "$pid"
    wait "$pid"; rc=$?
    echo "$rc $(( $(date +%s) - t0 ))" > "$BOX/k3.rc"
)
OUT="$BOX/k3.out"; cat "$OUT" >> "$ALL_OUT"
read -r RC took < "$BOX/k3.rc"
expect_rc K3 143
if [ -e "$BOX/state/logging" ]; then ok; else bad K3 "команда не дошла до лога — TERM пришёл не посреди команды"; fi
if [ "$took" -le 20 ]; then ok; else bad K3 "выход через $took с после TERM"; fi
expect_ns_gone K3 t1-heavy-k3

# K4 — OOMKilled
fresh
go_run k4 env FAKE_EXIT=137 FAKE_OOM=1 "${B[@]}" --short k4 -- true
expect_rc K4 76
expect_ns_gone K4 t1-heavy-k4

# K6 — подготовка pod не удалась (termination-log): 69, не код 125 команды
fresh
go_run k6 env FAKE_EXIT=125 FAKE_MSG="remote-heavy-prep: jq не поставлен" "${B[@]}" --short k6 -- true
expect_rc K6 69
expect_ns_gone K6 t1-heavy-k6
# близнец K6: тот же код 125 без строки подготовки — код команды
fresh
go_run k6b env FAKE_EXIT=125 "${B[@]}" --short k6b -- true
expect_rc K6b 125

# K5 — --keep 2: ns остаётся, срок ≈ +2 ч, метки на месте
fresh
t0=$(date +%s)
go_run k5 env FAKE_EXIT=0 "${B[@]}" --short k5 --keep 2 -- true
expect_rc K5 0
f="$BOX/state/ns/t1-heavy-k5"
if [ -f "$f" ]; then
    ok
    exp="$(jq -r '.metadata.annotations["kacho.io/expires"]' "$f")"
    d=$(( $(date -u -d "$exp" +%s) - t0 - 7200 )); [ "$d" -lt 0 ] && d=$(( -d ))
    if [ "$d" -le 60 ]; then ok; else bad K5 "kacho.io/expires=$exp, ждали ≈ +2 ч"; fi
    labels="$(jq -r '.metadata.labels | "\(.["kacho.io/task"]) \(.["kacho.io/stand"]) \(.["kacho.io/kind"])"' "$f")"
    if [ "$labels" = "1 test heavy" ]; then ok; else bad K5 "метки «$labels», ждали «1 test heavy»"; fi
else
    bad K5 "ns с --keep снято"
fi
if [ -e "$BOX/state/deleted" ]; then bad K5 "delete ns звался при --keep"; else ok; fi

# R1, R2, R3 — отказ до кластера
# no_cluster_call <случай> — отказ до любого создания: к двойнику ни одного обращения.
no_cluster_call() {
    if [ -s "$BOX/state/calls" ]; then bad "$1" "к кластеру обращались: $(head -n 1 "$BOX/state/calls")"; else ok; fi
}
fresh
go_run r1 env NS=kacho "${B[@]}" -- true
expect_rc R1 64
if [ "$(ns_left)" -eq 0 ]; then ok; else bad R1 "ns создано"; fi
no_cluster_call R1
fresh
go_run r2 "${B[@]}" --ns kacho -- true
expect_rc R2 64
if [ "$(ns_left)" -eq 0 ]; then ok; else bad R2 "ns создано"; fi
no_cluster_call R2
for bad_ns in t2-heavy-x t1-stand-x kacho-heavy t1-heavy- default; do
    fresh
    go_run "r3-$bad_ns" "${B[@]}" --ns "$bad_ns" -- true
    expect_rc "R3 $bad_ns" 64
    no_cluster_call "R3 $bad_ns"
done

# cluster_calls — вызовов kubectl, кроме чтения списка контекстов (локальная операция)
cluster_calls() { [ -e "$BOX/state/calls" ] || { echo 0; return; }; grep -vc ' config get-contexts ' "$BOX/state/calls"; }
# X2 — KACHO_REMOTE_CONTEXT на infra → 64 до любого обращения, и к kubectl тоже
for ov in "$CTX_INFRA" lab-a1; do
    fresh
    go_run "x2-$ov" env KACHO_REMOTE_CONTEXT="$ov" FAKE_EXIT=0 "${B[@]}" --short x2 -- true
    expect_rc "X2 $ov" 64
    no_cluster_call "X2 $ov"
    if grep -q 'только в контекст -client' "$OUT"; then ok; else bad "X2 $ov" "шаг «что сделать» не назван"; fi
done
fresh
go_run x2a env KACHO_REMOTE_CONTEXT="$CTX_INFRA" bash "$RUN" --available
expect_rc X2a 64
no_cluster_call X2a
# X2b — близнец: KACHO_REMOTE_CONTEXT на client → 0
fresh
go_run x2b env KACHO_REMOTE_CONTEXT="$CTX_CLIENT" FAKE_EXIT=0 "${B[@]}" --short x2b -- true
expect_rc X2b 0
# X2c — названного -client в файле нет → 69, к кластеру ни одного обращения
fresh
go_run x2c env KACHO_REMOTE_CONTEXT=lab-zz-client FAKE_EXIT=0 "${B[@]}" --short x2c -- true
expect_rc X2c 69
if [ "$(cluster_calls)" -gt 0 ]; then bad X2c "к кластеру обращались"; else ok; fi
# X3 — в файле нет контекста -client (только infra) → 69 и с --available; X4 — два -client → 69
kubeconfig_with "$CTX_INFRA" "$CTX_INFRA" > "$BOX/kc-noclient"
kubeconfig_with "$CTX_INFRA" "$CTX_INFRA" "$CTX_CLIENT" lab-b2-client > "$BOX/kc-twoclient"
for cs in "noclient:X3:нет контекста с суффиксом -client" "twoclient:X4:выбор неоднозначен"; do
    IFS=: read -r f nm why <<< "$cs"
    for mode in run avail; do
        fresh
        if [ "$mode" = run ]; then
            go_run "$nm-$mode" env KACHO_REMOTE_KUBECONFIG="$BOX/kc-$f" FAKE_EXIT=0 "${B[@]}" --short x3 -- true
        else
            go_run "$nm-$mode" env KACHO_REMOTE_KUBECONFIG="$BOX/kc-$f" bash "$RUN" --available
        fi
        expect_rc "$nm $mode" 69
        if [ "$(cluster_calls)" -gt 0 ]; then bad "$nm $mode" "к кластеру обращались"; else ok; fi
        if grep -q "$why" "$OUT" && grep -q 'KACHO_REMOTE_CONTEXT\|добавь контекст' "$OUT"; then ok; else bad "$nm $mode" "причина или шаг не названы"; fi
    done
done

# R4 — ns уже есть: отказ, и чужое не снято (близнец K1 по имени)
fresh
echo '{"kind":"Namespace"}' > "$BOX/state/ns/t1-heavy-k1"
go_run r4 env FAKE_EXIT=0 "${B[@]}" --short k1 -- true
expect_rc R4 64
if [ -f "$BOX/state/ns/t1-heavy-k1" ]; then ok; else bad R4 "существовавшее ns снято"; fi
if [ -e "$BOX/state/deleted" ]; then bad R4 "delete ns звался для чужого ns"; else ok; fi

# ── предел одновременных прогонов (F3) ──────────────────────────────────────
# seed_ns <имя> <срок: +1 hour | -1 hour> — чужое идущее тяжёлое ns
seed_ns() {
    jq -n --arg n "$1" --arg t "$(date -u -d '-10 minutes' +%Y-%m-%dT%H:%M:%SZ)" --arg e "$(date -u -d "$2" +%Y-%m-%dT%H:%M:%SZ)" \
        '{kind: "Namespace", metadata: {name: $n, creationTimestamp: $t, labels: {"kacho.io/kind": "heavy"}, annotations: {"kacho.io/expires": $e}}, status: {phase: "Active"}}' > "$BOX/state/ns/$1"
}
seed_done_job() {
    mkdir -p "$BOX/state/jobs"
    jq -n --arg n "$1" '{metadata: {namespace: $n, name: "run"}, status: {conditions: [{type: "Complete", status: "True"}]}}' > "$BOX/state/jobs/$1"
}
own_gone() {
    if [ ! -e "$BOX/state/ns/$2" ] && grep -qx "$2" "$BOX/state/deleted" 2>/dev/null; then ok; else bad "$1" "своё ns $2 не снято"; fi
}
no_job() { if [ -e "$BOX/state/job.json" ]; then bad "$1" "Job создан"; else ok; fi; }

# C1 — идущих 2 при пределе 2 → 75 до создания ns
fresh; seed_ns t7-heavy-a '+1 hour'; seed_ns t8-heavy-b '+1 hour'
go_run c1 env FAKE_EXIT=0 "${B[@]}" --short c1 -- true
expect_rc C1 75
if grep -qE '(^| )create -f ' "$BOX/state/calls"; then bad C1 "create звался при занятом кластере"; else ok; fi
# C2 — близнец C1: те же ns, их Job завершены → не идущие → 0
fresh; seed_ns t7-heavy-a '+1 hour'; seed_ns t8-heavy-b '+1 hour'; seed_done_job t7-heavy-a; seed_done_job t8-heavy-b
go_run c2 env FAKE_EXIT=0 "${B[@]}" --short c2 -- true
expect_rc C2 0
# C3 — близнец C1: ns со сроком в прошлом (остаток kill -9) не идущее → 0
fresh; seed_ns t7-heavy-a '-1 hour'; seed_ns t8-heavy-b '-1 hour'
go_run c3 env FAKE_EXIT=0 "${B[@]}" --short c3 -- true
expect_rc C3 0
# C4 — гонка: первая перепись видит 1 из 2, второй запуск создал ns мгновением раньше → 75, своё ns снято, Job нет
fresh; seed_ns t7-heavy-a '+1 hour'
go_run c4 env FAKE_EXIT=0 FAKE_RACE=t9-heavy-racer "${B[@]}" --short c4 -- true
expect_rc C4 75
own_gone C4 t1-heavy-c4
no_job C4
# C4b — близнец C4 без гонки → 0
fresh; seed_ns t7-heavy-a '+1 hour'
go_run c4b env FAKE_EXIT=0 "${B[@]}" --short c4b -- true
expect_rc C4b 0
# C5 — --keep не спасает ns запуска, вышедшего сверх предела
fresh; seed_ns t7-heavy-a '+1 hour'
go_run c5 env FAKE_EXIT=0 FAKE_RACE=t9-heavy-racer "${B[@]}" --short c5 --keep 2 -- true
expect_rc C5 75
own_gone C5 t1-heavy-c5
# V2 — --available при занятом кластере → 75; близнец с одним идущим → 0
fresh; seed_ns t7-heavy-a '+1 hour'; seed_ns t8-heavy-b '+1 hour'
go_run v2 bash "$RUN" --available
expect_rc V2 75
fresh; seed_ns t7-heavy-a '+1 hour'
go_run v2b bash "$RUN" --available
expect_rc V2b 0
# M1 — предел вне 1..8 → 64
fresh
go_run m1 env KACHO_REMOTE_HEAVY_MAX=0 "${B[@]}" -- true
expect_rc M1 64

# ── размещение: место под профиль, без условия по стенду (ws#991) ─────────
# node_j <имя> <готов 1|0> <закрыт 1|0> <taint-эффект|""> — узел 15,5 CPU и 29,5 ГиБ;
# pod_j <ns> <узел> <фаза> <cpu> <память> — pod с запросами; items — список.
node_j() {
    jq -nc --arg n "$NODE_PFX$1" --arg r "$2" --arg c "$3" --arg t "$4" --arg e "$FAKE_NODE_IP" '{metadata: {name: $n},
      spec: ((if $c == "1" then {unschedulable: true} else {} end) + (if $t != "" then {taints: [{key: "k", effect: $t}]} else {} end)),
      status: {addresses: [{type: "InternalIP", address: $e}], conditions: [{type: "Ready", status: (if $r == "1" then "True" else "False" end)}],
               allocatable: {cpu: "15500m", memory: "30913596Ki"}}}'
}
pod_j() {
    jq -nc --arg ns "$1" --arg n "$NODE_PFX$2" --arg ph "$3" --arg c "$4" --arg m "$5" '{metadata: {namespace: $ns, name: "p"},
      spec: {nodeName: $n, containers: [{name: "c", resources: {requests: {cpu: $c, memory: $m}}}]}, status: {phase: $ph}}'
}
items() { jq -sc '{items: .}'; }
created() { grep -qE '(^| )create -f ' "$BOX/state/calls" 2>/dev/null && echo да || echo нет; }
NODES1="$(node_j n1 1 0 "" | items)"
NODES12="$( { node_j n1 1 0 ""; node_j n2 1 0 ""; } | items)"
# Стенд замера 2026-10-09 (kubectl describe nodes): запросы 450m CPU и 2 756 МиБ.
STAND_ALL="$( { pod_j kacho n1 Running 450m 2756Mi; pod_j kacho n2 Running 450m 2756Mi; } | items)"
# Q1 — стенд на всех узлах, место есть → 0: стенд узел не запирает (опыт 2026-10-09:
# прежнее условие давало здесь 69, а прогон шёл локально)
fresh
go_run q1 env FAKE_NODES="$NODES12" FAKE_CLUSTER_PODS="$STAND_ALL" bash "$RUN" --available --profile go-race
expect_rc Q1 0
fresh
go_run q1r env FAKE_EXIT=0 FAKE_NODES="$NODES12" FAKE_CLUSTER_PODS="$STAND_ALL" bash "$RUN" --task 1 --repo kaname --ref HEAD --src "$SRC" --profile go-race --short q1r -- true
expect_rc Q1r 0
if [ "$(created)" = да ]; then ok; else bad Q1r "ns не создавалось при стенде на всех узлах и месте под профиль"; fi
expect_ns_gone Q1r t1-heavy-q1r
# Q1d — ПРЕДЕЛ 2: единственный узел со стендом и одним идущим go-race — второй
# go-race тоже встаёт (запросы профиля подобраны под это) → 0
IFS='|' read -r _ gcpu _ gmib _ <<< "$(sed -n "s/^PROFILES='\\(go-race|.*\\)/\\1/p" "$RUN")"
IFS='|' read -r dind_cpu _ dind_gi _ <<< "$(sed -n "s/^DIND_RES='\\(.*\\)'$/\\1/p" "$RUN")"
dind_gi="${dind_gi%Gi}"
if [ -n "$gcpu" ] && [ -n "$dind_cpu" ] && [ -n "$dind_gi" ]; then
    one_run="$(pod_j t9-heavy-a n1 Running "$(( gcpu + dind_cpu ))" "$(( ${gmib%Gi} + dind_gi ))Gi")"
    fresh
    go_run q1d env FAKE_NODES="$NODES1" FAKE_CLUSTER_PODS="$( { pod_j kacho n1 Running 450m 2756Mi; echo "$one_run"; } | items)" bash "$RUN" --available --profile go-race
    expect_rc Q1d 0
else bad Q1d "запрос go-race и dind не прочитаны из run.sh"; fi
# Q3 — единственный узел не готов / закрыт / с taint NoSchedule → 69; прогон 69 без ns
for q in "0 0 :не-готов" "1 1 :закрыт" "1 0 NoSchedule:taint"; do
    read -r rdy cord rest <<< "$q"; eff="${rest%%:*}"; nm="${rest#*:}"
    fresh
    go_run "q3-$nm" env FAKE_NODES="$(node_j n1 "$rdy" "$cord" "$eff" | items)" bash "$RUN" --available
    expect_rc "Q3-$nm" 69
    if grep -q 'открытого для планирования узла нет' "$OUT"; then ok; else bad "Q3-$nm" "причина не названа"; fi
done
fresh
go_run q3r env FAKE_EXIT=0 FAKE_NODES="$(node_j n1 1 1 "" | items)" "${B[@]}" --short q3r -- true
expect_rc Q3r 69
if [ "$(created)" = нет ]; then ok; else bad Q3r "ns создавалось без открытого узла"; fi
# Q2 — оба узла заняты: 20 ГиБ запрошено чужими pod → go-race не встаёт → 75 до ns
BUSY="$( { pod_j kacho n1 Running 450m 2756Mi; pod_j other n1 Running 2 20Gi; pod_j other n2 Running 2 20Gi; } | items)"
fresh
go_run q2 env FAKE_NODES="$NODES12" FAKE_CLUSTER_PODS="$BUSY" bash "$RUN" --available --profile go-race
expect_rc Q2 75
if grep -q 'места' "$OUT"; then ok; else bad Q2 "причина не названа (места нет)"; fi
fresh
go_run q2r env FAKE_EXIT=0 FAKE_NODES="$NODES12" FAKE_CLUSTER_PODS="$BUSY" bash "$RUN" --task 1 --repo kaname --ref HEAD --src "$SRC" --profile go-race --short q2r -- true
expect_rc Q2r 75
if [ "$(created)" = нет ]; then ok; else bad Q2r "ns создавалось без места под профиль"; fi
# Q2b — близнец: тот же кластер, профиль lint (6 ГиБ) встаёт → 0 и прогон исполняется
fresh
go_run q2b env FAKE_NODES="$NODES12" FAKE_CLUSTER_PODS="$BUSY" bash "$RUN" --available --profile lint
expect_rc Q2b 0
fresh
go_run q2br env FAKE_EXIT=0 FAKE_NODES="$NODES12" FAKE_CLUSTER_PODS="$BUSY" "${B[@]}" --short q2br -- true
expect_rc Q2br 0
# Q2c — профиля нет → 64
fresh
go_run q2c bash "$RUN" --available --profile nope
expect_rc Q2c 64
# Q5 — перепись pod кластера больше строки аргумента (128 КиБ) → разбирается, 0
# (опыт 2026-10-09: настоящий кластер, jq не запускался)
fresh
{ for i in $(seq 1 700); do pod_j "ns-$i-$(printf '%0120d' 0)" n2 Running 10m 16Mi; done; pod_j kacho n2 Running 100m 256Mi; } | items > "$BOX/bigpods.json"
go_run q5 env FAKE_NODES="$NODES12" FAKE_CLUSTER_PODS_FILE="$BOX/bigpods.json" bash "$RUN" --available --profile go-race
expect_rc Q5 0
if [ "$(stat -c %s "$BOX/bigpods.json")" -gt 131072 ]; then ok; else bad Q5 "перепись меньше 128 КиБ — случай пуст"; fi
# Q4 — pod ждёт планирования, а чужой pod занял последнее место → 75 сразу, а не
# через 900 с; ns снято и при --keep
fresh
t0=$(date +%s)
go_run q4 env FAKE_EXIT=0 FAKE_UNSCHED=1 FAKE_PODS_AFTER_JOB="$(pod_j other n1 Running 15 28Gi | items)" "${B[@]}" --short q4 --keep 2 -- true
expect_rc Q4 75
if [ $(( $(date +%s) - t0 )) -le 30 ]; then ok; else bad Q4 "выход через $(( $(date +%s) - t0 )) с"; fi
expect_ns_gone Q4 t1-heavy-q4
if grep -q 'места под запрос' "$OUT"; then ok; else bad Q4 "причина не названа"; fi
# Q4b — близнец: pod ждёт, место есть (стенд на узле не мешает) → run.sh ждёт дальше
fresh
OUT="$BOX/q4b.out"
timeout 15 env PATH="$BOX/bin:$PATH" FAKE_STATE="$BOX/state" FAKE_HOST="$SERVER_HOST" FAKE_IP="$SERVER_IP" FAKE_EXIT=0 FAKE_UNSCHED=1 \
    FAKE_PODS_AFTER_JOB="$(pod_j kacho n1 Running 450m 2756Mi | items)" \
    KACHO_REMOTE_KUBECONFIG="$BOX/kubeconfig" TMPDIR="$BOX" "${B[@]}" --short q4b -- true > "$OUT" 2>&1
RC=$?; cat "$OUT" >> "$ALL_OUT"
expect_rc Q4b 124

# ── вывод прогона (ws#991) ──────────────────────────────────────────────────
# O1 — каждая строка run.sh после выбора ns несёт его имя (K1 — тот же прогон)
fresh
go_run o1 env FAKE_EXIT=0 "${B[@]}" --short o1 -- true
expect_rc O1 0
n_all="$(grep -c '^remote-heavy: ' "$OUT")"; n_tag="$(grep -c '^remote-heavy: \[t1-heavy-o1\] ' "$OUT")"
if [ "$n_all" -gt 0 ] && [ "$n_all" -eq "$n_tag" ]; then ok; else bad O1 "строк run.sh $n_all, с именем ns $n_tag"; fi
# O2 — stderr прогона — файл, в который пишет посторонний живой процесс → строка-предупреждение
fresh
: > "$BOX/o2.out"
( exec 3>> "$BOX/o2.out"; exec sleep 60 ) & holder=$!
for _ in $(seq 1 50); do [ -e "/proc/$holder/fd/3" ] && break; sleep 0.1; done
go_run o2 env FAKE_EXIT=0 "${B[@]}" --short o2 -- true
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
expect_rc O2 0
if grep -q 'пишет и другой процесс' "$OUT" && grep -q "pid $holder" "$OUT"; then ok; else bad O2 "общий файл вывода не назван"; fi
# O2b — близнец: файл держат только предки прогона (timeout, env) → молчание
if grep -q 'пишет и другой процесс' "$BOX/o1.out"; then OUT="$BOX/o1.out"; bad O2b "предупреждение без постороннего писателя"; else ok; fi

# ── локальная уборка после kill -9 ──────────────────────────────────────────
# shellcheck disable=SC2086  # поля stat — слова
pstart() { local st; st="$(cat "/proc/$1/stat")"; st="${st##*) }"; set -- $st; echo "${20}"; }
sleep 0 & dead_pid=$!; wait "$dead_pid"
DEAD="$dead_pid.1.dead"
LIVE="$$.$(pstart $$).live"
fresh
mkdir -p "$BOX/remote-heavy.dead1" "$BOX/remote-heavy.dead2" "$BOX/remote-heavy.live1"
printf '%s\nt1-heavy-old\n1\n\n' "$DEAD" > "$BOX/remote-heavy.dead1/owner"
echo bundle > "$BOX/remote-heavy.dead1/src.bundle"
printf '%s\nt1-heavy-other\n1\n\n' "$DEAD" > "$BOX/remote-heavy.dead2/owner"
printf '%s\nt1-heavy-live\n1\n\n' "$LIVE" > "$BOX/remote-heavy.live1/owner"
for n in old other; do seed_ns "t1-heavy-$n" '+1 hour'; done
jq --arg o "$DEAD" '.metadata.annotations["kacho.io/owner"] = $o' "$BOX/state/ns/t1-heavy-old" > "$BOX/x.json" && mv "$BOX/x.json" "$BOX/state/ns/t1-heavy-old"
jq '.metadata.annotations["kacho.io/owner"] = "someone-else"' "$BOX/state/ns/t1-heavy-other" > "$BOX/x.json" && mv "$BOX/x.json" "$BOX/state/ns/t1-heavy-other"
env REMOTE_HEAVY_OWNER="$DEAD" tail -f /dev/null & orphan=$!   # стоит до kill — подобие kubectl logs -f
env REMOTE_HEAVY_OWNER="$LIVE" tail -f /dev/null & liveproc=$!
git -C "$SRC" update-ref "refs/remote-heavy/$DEAD" HEAD
git -C "$SRC" update-ref "refs/remote-heavy/$LIVE" HEAD
go_run g1 env FAKE_EXIT=0 KACHO_REMOTE_HEAVY_MAX=3 "${B[@]}" --short g1 -- true
expect_rc G1 0
if [ ! -e "$BOX/remote-heavy.dead1" ] && [ ! -e "$BOX/remote-heavy.dead2" ]; then ok; else bad G1 "каталог мёртвого владельца остался"; fi
if kill -0 "$orphan" 2>/dev/null; then bad G1 "процесс мёртвого владельца жив"; kill "$orphan"; else ok; fi
if grep -qx t1-heavy-old "$BOX/state/deleted" 2>/dev/null; then ok; else bad G1 "ns мёртвого владельца не снято"; fi
if git -C "$SRC" show-ref --verify --quiet "refs/remote-heavy/$DEAD"; then bad G1 "ссылка мёртвого владельца осталась"; else ok; fi
if grep -q 'уборка прежних запусков' "$OUT"; then ok; else bad G1 "перепись уборки не напечатана"; fi
# G2 — близнецы: живой владелец и чужое ns того же вида не тронуты
if [ -f "$BOX/remote-heavy.live1/owner" ]; then ok; else bad G2 "каталог живого владельца снят"; fi
if kill -0 "$liveproc" 2>/dev/null; then ok; else bad G2 "процесс живого владельца убит"; fi
if git -C "$SRC" show-ref --verify --quiet "refs/remote-heavy/$LIVE"; then ok; else bad G2 "ссылка живого владельца снята"; fi
if grep -qx t1-heavy-other "$BOX/state/deleted" 2>/dev/null; then bad G2 "снято ns с чужой меткой владельца"; else ok; fi
kill "$liveproc" 2>/dev/null; wait "$liveproc" "$orphan" 2>/dev/null
rm -rf "$BOX/remote-heavy.live1"; git -C "$SRC" update-ref -d "refs/remote-heavy/$LIVE"

# ── страж кластера по узлам (решение владельца 2026-10-10) ──────────────────
# writes — изменяющие вызовы двойника (can-i — чтение).
writes() { [ -e "$BOX/state/calls" ] || { echo 0; return; }; grep -v 'auth can-i' "$BOX/state/calls" | grep -cE '(^| )(create|apply|delete|exec|patch|label|annotate) '; }
# wnode <имя> — узел, годный для размещения, с полным именем
wnode() { jq -nc --arg n "$1" --arg e "$FAKE_NODE_IP" '{metadata: {name: $n}, spec: {},
    status: {addresses: [{type: "InternalIP", address: $e}], conditions: [{type: "Ready", status: "True"}], allocatable: {cpu: "15500m", memory: "30913596Ki"}}}'; }
N_INFRA="$( { wnode lab1-infra-q11-a; wnode lab1-infra-q11-b; } | items)"
N_MIXED="$( { wnode lab1-client-p00l-a; wnode lab1-infra-q11-b; } | items)"
N_ZERO='{"items":[]}'
N_FOREIGN="$( { wnode lab2-client-p00l-a; wnode lab2-client-p00l-b; } | items)"
N_CLIENT="$( { wnode lab1-client-p00l-a; wnode lab1-client-zz9-b; } | items)"
for cs in "w1:$N_INFRA:с -infra- 2" "w2:$N_MIXED:с -infra- 1" "w3:$N_ZERO:узлов в контексте ноль" "w4:$N_FOREIGN:с префиксом <профиль>-client- 0"; do
    nm="${cs%%:*}"; rest="${cs#*:}"; nodes="${rest%:*}"; why="${rest##*:}"; NM="${nm^^}"
    for mode in run avail; do
        fresh
        if [ "$mode" = run ]; then
            go_run "$nm-$mode" env FAKE_EXIT=0 FAKE_NODES="$nodes" "${B[@]}" --short "$nm" -- true
        else
            go_run "$nm-$mode" env FAKE_NODES="$nodes" bash "$RUN" --available
        fi
        expect_rc "$NM $mode" 69
        if [ "$(writes)" -eq 0 ]; then ok; else bad "$NM $mode" "изменяющих вызовов $(writes) при узлах не того кластера"; fi
        if grep -qF -- "$why" "$OUT" && grep -q 'что сделать:' "$OUT"; then ok; else bad "$NM $mode" "причина «$why» или шаг не названы"; fi
    done
done
# W5 — узлы профиля (хвосты пула разные: хэш не зашит) → 0; get nodes раньше первой записи
fresh
go_run w5 env FAKE_EXIT=0 FAKE_NODES="$N_CLIENT" "${B[@]}" --short w5 -- true
expect_rc W5 0
first_nodes="$(grep -nE '(^| )get nodes' "$BOX/state/calls" | head -n 1 | cut -d: -f1)"
first_write="$(grep -nE '(^| )(create|apply|delete|exec) ' "$BOX/state/calls" | grep -v 'auth can-i' | head -n 1 | cut -d: -f1)"
if [ -n "$first_nodes" ] && [ -n "$first_write" ] && [ "$first_nodes" -lt "$first_write" ]; then ok; else bad W5 "перепись узлов (строка ${first_nodes:-нет}) не раньше первой записи (строка ${first_write:-нет})"; fi
# W6 — профиль из имени файла, переменной нет → 0; W6b — тот же файл, узлы чужого профиля → 69
cp "$BOX/kubeconfig" "$BOX/probe--lab1.yaml"
fresh
go_run w6 env -u KACHO_REMOTE_PROFILE KACHO_REMOTE_KUBECONFIG="$BOX/probe--lab1.yaml" FAKE_EXIT=0 FAKE_NODES="$N_CLIENT" "${B[@]}" --short w6 -- true
expect_rc W6 0
fresh
go_run w6b env -u KACHO_REMOTE_PROFILE KACHO_REMOTE_KUBECONFIG="$BOX/probe--lab1.yaml" FAKE_EXIT=0 FAKE_NODES="$N_FOREIGN" "${B[@]}" --short w6 -- true
expect_rc W6b 69
if [ "$(writes)" -eq 0 ]; then ok; else bad W6b "изменяющие вызовы при чужом профиле"; fi
# W7 — профиль не выводится → 69 до кластера; W8 — переменная и имя файла расходятся → 69
fresh
go_run w7 env -u KACHO_REMOTE_PROFILE FAKE_EXIT=0 "${B[@]}" --short w7 -- true
expect_rc W7 69
if [ "$(cluster_calls)" -eq 0 ] && grep -q 'KACHO_REMOTE_PROFILE=<профиль>' "$OUT"; then ok; else bad W7 "к кластеру обращались либо шаг не назван"; fi
fresh
go_run w8 env KACHO_REMOTE_PROFILE=lab2 KACHO_REMOTE_KUBECONFIG="$BOX/probe--lab1.yaml" FAKE_EXIT=0 FAKE_NODES="$N_FOREIGN" "${B[@]}" --short w8 -- true
expect_rc W8 69
if [ "$(cluster_calls)" -eq 0 ] && grep -q 'расходятся' "$OUT"; then ok; else bad W8 "к кластеру обращались либо причина не названа"; fi
# W9 — файл подменён после создания ns, узлы стали infra → 69 до сети ns; ns не снято
cp "$BOX/kubeconfig" "$BOX/kc-swap"
fresh
go_run w9 env KACHO_REMOTE_KUBECONFIG="$BOX/kc-swap" FAKE_SWAP_FILE="$BOX/kc-swap" FAKE_NODES_AFTER_NS="$N_INFRA" FAKE_EXIT=0 "${B[@]}" --short w9 -- true
expect_rc W9 69
if [ -e "$BOX/state/swapped" ]; then ok; else bad W9 "подмена файла не случилась — случай пуст"; fi
if [ ! -e "$BOX/state/netpol.json" ] && [ ! -e "$BOX/state/job.json" ]; then ok; else bad W9 "запись после подмены кластера"; fi
if [ -e "$BOX/state/deleted" ]; then bad W9 "delete ns звался в чужом кластере"; else ok; fi
if grep -q 'фаза «сетевая политика ns» не начата' "$OUT" && grep -q 'НЕ снято' "$OUT" && grep -q 'delete ns t1-heavy-w9' "$OUT"; then ok; else bad W9 "фаза, неснятое ns или шаг не названы"; fi
# W9b — близнец: файл сменился, узлы те же → 0, узлы переписаны заново
cp "$BOX/kubeconfig" "$BOX/kc-swap"
fresh
go_run w9b env KACHO_REMOTE_KUBECONFIG="$BOX/kc-swap" FAKE_SWAP_FILE="$BOX/kc-swap" FAKE_EXIT=0 "${B[@]}" --short w9b -- true
expect_rc W9b 0
expect_ns_gone W9b t1-heavy-w9b
nb="$(grep -nE ' create -f ' "$BOX/state/calls" | head -n 1 | cut -d: -f1)"
na="$(tail -n +"$(( ${nb:-1} + 1 ))" "$BOX/state/calls" | grep -cE '(^| )get nodes')"
if [ "${na:-0}" -ge 1 ]; then ok; else bad W9b "после смены файла узлы не переписаны"; fi
# W10 — узлы с -infra- при остатках мёртвого владельца → 69, его ns не снимается
fresh
mkdir -p "$BOX/remote-heavy.deadw"
printf '%s\nt1-heavy-oldw\n1\n\n' "$DEAD" > "$BOX/remote-heavy.deadw/owner"
seed_ns t1-heavy-oldw '+1 hour'
jq --arg o "$DEAD" '.metadata.annotations["kacho.io/owner"] = $o' "$BOX/state/ns/t1-heavy-oldw" > "$BOX/x.json" && mv "$BOX/x.json" "$BOX/state/ns/t1-heavy-oldw"
go_run w10 env FAKE_EXIT=0 FAKE_NODES="$N_INFRA" "${B[@]}" --short w10 -- true
expect_rc W10 69
if [ -e "$BOX/state/deleted" ] || [ "$(writes)" -ne 0 ]; then bad W10 "уборка писала в кластер с узлами infra"; else ok; fi
rm -rf "$BOX/remote-heavy.deadw"

# V1 — кластер не отвечает
fresh
go_run v1 env FAKE_DOWN=1 bash "$RUN" --available
expect_rc V1 69
if grep -q 'не отвечает' "$OUT"; then ok; else bad V1 "причина не названа"; fi

# L0 — двойник печатает адрес и IPv4 (иначе L1 пуста)
OUT="$BOX/l0.out"
env FAKE_STATE="$BOX/state" FAKE_HOST="$SERVER_HOST" FAKE_IP="$SERVER_IP" FAKE_DOWN=1 \
    "$BOX/bin/kubectl" auth can-i create namespaces > "$OUT" 2>&1
if grep -q "$SERVER_HOST" "$OUT" && grep -q "$SERVER_IP" "$OUT"; then ok; else bad L0 "двойник не печатает адрес — проба утечки пуста"; fi
# L0b — двойник печатает адреса pod (IPv4 и IPv6) в STDOUT лога команды
env FAKE_STATE="$BOX/state" FAKE_HOST="$SERVER_HOST" FAKE_IP="$SERVER_IP" "$BOX/bin/kubectl" logs -f run-x 2>/dev/null > "$OUT"
if grep -qF "$FAKE_POD_IP" "$OUT" && grep -qF "$FAKE_POD_IP6" "$OUT"; then ok; else bad L0b "двойник не печатает адрес pod в stdout — проба F4 пуста"; fi

# L1 — ни адреса, ни IPv4, ни токена, ни пути кубконфига в выводе run.sh
OUT="$ALL_OUT"
for s in "$SERVER_HOST" "$SERVER_IP" "$TOKEN" "$BOX/kubeconfig" "$BOX/probe--lab1.yaml" "$BOX/kc-swap" lab1-client- lab1-infra- lab2-client- "$CTX_CLIENT" "$CTX_INFRA" "$FAKE_NODE_IP" "$FAKE_NODE_IP6" "$FAKE_API_IP" "$FAKE_POD_IP" "$FAKE_POD_IP6"; do
    if grep -qF -- "$s" "$ALL_OUT"; then bad L1 "в выводе run.sh — «$s»"; else ok; fi
done
if [ -s "$ALL_OUT" ]; then ok; else bad L1 "вывод пуст — судить нечего"; fi

printf 'remote-heavy inject: утверждений %d · сошлось %d · разошлось %d\n' $((PASS + FAIL)) "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
