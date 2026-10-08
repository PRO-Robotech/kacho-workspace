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
#   R1 NS=kacho                            → 64; ns не создавалось
#   R2 --ns kacho                          → 64; ns не создавалось
#   R3 --ns вне формы t<задача>-heavy-…    → 64
#   R4 ns уже есть (близнец K1)            → 64; чужое ns НЕ снято
#   A1 Job: podAntiAffinity required к pod ns kacho по узлу (ревью F1)
#   U0 pod в своём пространстве пользователей (hostUsers: false)
#   U1 профиль с dind: privileged нет нигде, dind на crun без cgroup (F1)
#   N1 NetworkPolicy ns: входящих нет; исходящие — DNS (53) и мир без частных
#      диапазонов, адресов узлов и диапазона служб (F2)
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
#   G1 остатки kill -9 (каталог, процесс, ns, ссылка) мёртвого владельца → сняты
#   G2 близнецы: живой владелец и ns с чужой меткой — не тронуты
#   L0 двойник сам печатает адрес и IPv4   → да (контроль пробы утечки)
#   L0b двойник печатает адреса pod в stdout лога → да (контроль F4)
#   L1 вывод всех случаев без адреса сервера, IPv4/IPv6 узлов и pod, токена
#      и пути кубконфига (F4: stdout лога тоже)
#   V1 кластер не отвечает (--available)   → 69, причина без адреса
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
export FAKE_NODE_IP="198.51.100.10" FAKE_NODE_IP6="2001:db8::10"
export FAKE_POD_IP="192.0.2.44" FAKE_POD_IP6="2001:db8:0:1::44"
PASS=0; FAIL=0; ALL_OUT="$BOX/all.out"; : > "$ALL_OUT"

mkdir -p "$BOX/bin" "$BOX/state"
cat > "$BOX/kubeconfig" <<EOF
apiVersion: v1
kind: Config
clusters: [{name: c, cluster: {server: "https://$SERVER_HOST:6443"}}]
users: [{name: u, user: {token: "$TOKEN"}}]
contexts: [{name: x, context: {cluster: c, user: u}}]
current-context: x
EOF

# ── двойник kubectl ──────────────────────────────────────────────────────────
cat > "$BOX/bin/kubectl" <<'FAKE'
#!/usr/bin/env bash
set -uo pipefail
S="$FAKE_STATE"
mkdir -p "$S/ns" "$S/jobs"
mkdir -p "$S/ns" "$S/jobs"
echo "$*" >> "$S/calls"
echo "Warning: cluster https://$FAKE_HOST:6443 ($FAKE_IP) answered slowly" >&2
ns=""; sel=""; all=0
args=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --kubeconfig) shift 2 ;;
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
case "$1 ${2:-}" in
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
        jq -n --arg e "$FAKE_NODE_IP" --arg v6 "$FAKE_NODE_IP6" '{items: [{status: {addresses: [{type: "ExternalIP", address: $e}, {type: "InternalIP", address: "10.0.0.5"}, {type: "InternalIP", address: $v6}, {type: "Hostname", address: "n1"}]}}]}' ;;
    "get servicecidrs") echo '{"items":[{"spec":{"cidrs":["10.96.0.0/12"]}}]}' ;;
    "get pods")
        if [ ! -e "$S/job.json" ]; then echo '{"items":[]}'; exit 0; fi
        if [ ! -e "$S/delivered" ]; then
            echo '{"items":[{"metadata":{"name":"run-x"},"status":{"phase":"Pending","initContainerStatuses":[{"name":"fetch","state":{"running":{}}}],"containerStatuses":[{"name":"run","state":{"waiting":{"reason":"PodInitializing"}}}]}}]}'
            exit 0
        fi
        if [ "${FAKE_HANG:-0}" = 1 ]; then
            echo '{"items":[{"metadata":{"name":"run-x"},"status":{"phase":"Running","initContainerStatuses":[{"name":"fetch","state":{"terminated":{"exitCode":0}}}],"containerStatuses":[{"name":"run","state":{"running":{}}}]}}]}'
            exit 0
        fi
        reason=Completed; [ "${FAKE_OOM:-0}" = 1 ] && reason=OOMKilled
        jq -nc --argjson rc "${FAKE_EXIT:-0}" --arg r "$reason" --arg m "${FAKE_MSG:-}" '{items:[{metadata:{name:"run-x"},status:{phase:(if $rc == 0 then "Succeeded" else "Failed" end),
            initContainerStatuses:[{name:"fetch",state:{terminated:{exitCode:0}}}],
            containerStatuses:[{name:"run",state:{terminated:{exitCode:$rc,reason:$r,message:$m}}}]}}]}' ;;
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
    "get job") echo '{"status":{}}' ;;
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
    env PATH="$BOX/bin:$PATH" FAKE_STATE="$BOX/state" FAKE_HOST="$SERVER_HOST" FAKE_IP="$SERVER_IP" \
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
# A1 — pod не встаёт на узел с pod ns kacho (ревью F1)
J="$BOX/state/job.json"
if jq -e '[.spec.template.spec.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[]?
          | select(.topologyKey == "kubernetes.io/hostname"
                   and .namespaceSelector.matchLabels["kubernetes.io/metadata.name"] == "kacho"
                   and .labelSelector == {})] | length == 1' "$J" >/dev/null 2>&1; then ok
else OUT="$J"; bad A1 "в Job нет podAntiAffinity required к pod ns kacho по kubernetes.io/hostname"; fi
# N1 — сеть ns: входящих нет, исходящие — DNS и мир без частных, узлов и служб (F2)
NP="$BOX/state/netpol.json"
if jq -e --arg n4 "$FAKE_NODE_IP/32" --arg n6 "$FAKE_NODE_IP6/128" '
     .spec.podSelector == {} and (.spec.policyTypes | sort) == ["Egress", "Ingress"] and (.spec.ingress // []) == []
     and ([.spec.egress[].to[]] | all(.ipBlock or (.namespaceSelector.matchLabels["kubernetes.io/metadata.name"] == "dns-sys" and .podSelector.matchLabels["k8s-app"] == "dns")))
     and ([.spec.egress[] | select(any(.to[]; .namespaceSelector)) | .ports[] | "\(.protocol)/\(.port)"] | sort) == ["TCP/53", "UDP/53"]
     and ([.spec.egress[].to[] | .ipBlock | select(.cidr == "0.0.0.0/0") | .except[]] as $e
          | ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10", "169.254.0.0/16", $n4, "10.96.0.0/12"] | all(. as $x | $e | index($x)))
     and ([.spec.egress[].to[] | .ipBlock | select(.cidr == "::/0") | .except[]] as $e | ["fc00::/7", "fe80::/10", $n6] | all(. as $x | $e | index($x)))' "$NP" >/dev/null 2>&1; then ok
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
fresh
go_run r1 env NS=kacho "${B[@]}" -- true
expect_rc R1 64
if [ "$(ns_left)" -eq 0 ]; then ok; else bad R1 "ns создано"; fi
if grep -q 'create' "$BOX/state/calls" 2>/dev/null; then bad R1 "create звался"; else ok; fi
fresh
go_run r2 "${B[@]}" --ns kacho -- true
expect_rc R2 64
if [ "$(ns_left)" -eq 0 ]; then ok; else bad R2 "ns создано"; fi
fresh
go_run r3 "${B[@]}" --ns t2-heavy-x -- true
expect_rc R3 64

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
if grep -q '^create' "$BOX/state/calls"; then bad C1 "create звался при занятом кластере"; else ok; fi
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
for s in "$SERVER_HOST" "$SERVER_IP" "$TOKEN" "$BOX/kubeconfig" "$FAKE_NODE_IP" "$FAKE_NODE_IP6" "$FAKE_POD_IP" "$FAKE_POD_IP6"; do
    if grep -qF -- "$s" "$ALL_OUT"; then bad L1 "в выводе run.sh — «$s»"; else ok; fi
done
if [ -s "$ALL_OUT" ]; then ok; else bad L1 "вывод пуст — судить нечего"; fi

printf 'remote-heavy inject: утверждений %d · сошлось %d · разошлось %d\n' $((PASS + FAIL)) "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
