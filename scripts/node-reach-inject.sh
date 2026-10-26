#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# node-reach-inject.sh — доказательство того, что `scripts/node-reach.sh` СПОСОБЕН назвать
# полномочие, достижимое с узла, — каждое из перечня, кластерное и по пространству, — и не путает
# «судить нечем» с «доступа нет» (ws#1418; ⛔ check-verifier на 9ca63883c: проба не краснела на
# однофактных дефектах nodes-log, pods-exec, sa-token, на снятом селекторе и «yes - …»).
#
# Вход — двойник `kubectl` (шов KUBECTL), строгий как API-сервер:
#   · поды — только по `--field-selector spec.nodeName=n1`; без селектора — и поды ЧУЖОГО узла
#     (SA evil/admin со всеми правами): снятый селектор даёт лишнее «да»;
#   · RoleBinding — файл сцены; не прочитаны — отказ;
#   · can-i — «yes» лишь на вопрос С `--as` нужной SA и ровно с тем набором слов (глагол, ресурс,
#     подресурс, `-A` либо `-n <ns>`): `-A` и `-n` — разные вопросы; строка «!» — ответ
#     «yes - <причина>» (так отвечает вебхук-авторизатор); без `--as` — «no».
# Сцены — по одной на каждый вопрос перечня (5 кластерных, 3 по пространству: субъект SA, субъект
# SA без namespace — ns привязки, группа system:serviceaccounts:<ns>), «yes - …», чужой узел,
# ns без привязки не спрашивается, SA без имени — default; «не судимо» (2): имперсонация
# запрещена, узла нет, подов 0, RoleBinding не прочитаны; довода нет — 64; под целиком не снят.
# Мутанты скрипта (по одной правке) обязаны покраснеть; близнец той же формы — молчать.
# Коды: 0 — все утверждения сошлись; 1 — хотя бы одно нет; 2 — утверждений 0.
# Образцы мутантов — текст скрипта: `$` в них не раскрывается намеренно.
# shellcheck disable=SC2016
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBJ="$HERE/node-reach.sh"
W="$(mktemp -d)"
# shellcheck disable=SC2154
trap '_rc=$?; rm -rf "$W" 2>/dev/null || rm -rf "$W" || echo "ПРЕДУПРЕЖДЕНИЕ: временный каталог $W не снят; код проверки $_rc сохранён" >&2; exit $_rc' EXIT
pass=0 fail=0

assert() {
    if [ "$1" = "$2" ]; then echo "  [OK]   $3"; pass=$((pass + 1))
    else echo "  [FAIL] $3 — ожидалось «$1», получено «$2»" >&2; fail=$((fail + 1)); fi
}

# Двойник kubectl: сцена — каталог $SCENE (nodes, pods, pods-other, rbs, yes, forbid, norbs); журнал — log.
cat > "$W/kubectl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SCENE/log"
case "$1 $2" in
    "get node") grep -qxF -- "$3" "$SCENE/nodes" 2> /dev/null; exit $? ;;
    "get pods")
        sel=""
        for ((i = 3; i <= $#; i++)); do [ "${!i}" = "--field-selector" ] && { j=$((i + 1)); sel="${!j}"; }; done
        [ "$sel" = "spec.nodeName=n1" ] || [ -z "$sel" ] || exit 0
        cat "$SCENE/pods" 2> /dev/null
        [ -n "$sel" ] || cat "$SCENE/pods-other" 2> /dev/null
        exit 0 ;;
    "get rolebindings") [ -f "$SCENE/norbs" ] && { echo "Error from server (Forbidden)" >&2; exit 1; }; cat "$SCENE/rbs" 2> /dev/null; exit 0 ;;
    "auth can-i")
        shift 2
        as="" q=()
        for a in "$@"; do case "$a" in --as=*) as="${a#--as=}" ;; *) q+=("$a") ;; esac; done
        if [ -f "$SCENE/forbid" ]; then echo "Error from server (Forbidden): cannot impersonate" >&2; exit 1; fi
        [ -n "$as" ] || { echo no; exit 1; }
        if grep -qxF -- "$as|${q[*]}" "$SCENE/yes" 2> /dev/null; then echo yes; exit 0; fi
        if grep -qxF -- "!$as|${q[*]}" "$SCENE/yes" 2> /dev/null; then echo "yes - granted by webhook"; exit 0; fi
        echo no; exit 1 ;;
esac
echo "двойник: обращение вне сцены: $*" >&2
exit 3
SH
chmod +x "$W/kubectl"

R='system:serviceaccount:ci:runner'
# scene <имя> — новая сцена: узел n1, две SA (runner у двух подов), чужой узел — evil/admin со всеми правами.
scene() {
    SCENE="$W/s-$1"; export SCENE
    mkdir -p "$SCENE"
    echo n1 > "$SCENE/nodes"
    printf 'kube-system\tkube-proxy\nci\trunner\nci\trunner\n' > "$SCENE/pods"
    printf 'evil\tadmin\n' > "$SCENE/pods-other"
    : > "$SCENE/rbs"
    printf 'system:serviceaccount:evil:admin|%s\n' 'list secrets -A' 'get nodes --subresource=proxy' 'get nodes --subresource=log' \
        'create pods --subresource=exec -A' 'create serviceaccounts --subresource=token -A' > "$SCENE/yes"
}
yes_() { printf '%s\n' "$@" >> "$SCENE/yes"; }
run() { local s="$1"; shift; KUBECTL="$W/kubectl" bash "$s" "$@" > "$W/out" 2> "$W/err"; echo $?; }
census() { sed -n 's/.*SA \([0-9]*\), ns с привязками \([0-9]*\), вопросов \([0-9]*\), «да» \([0-9]*\).*/\1 \2 \3 \4/p' "$W/out"; }
reach() { grep -qxF "$(printf 'REACH\t%s\t%s' "$1" "$2")" "$W/out" && echo да || echo нет; }

# Сцены — функциями: те же сцены служат мутантам.
s_control() { scene control; }
s_secrets_all() { scene secrets-all; yes_ "$R|list secrets -A"; }
s_nodes_proxy() { scene nodes-proxy; yes_ "$R|get nodes --subresource=proxy"; }
s_nodes_log() { scene nodes-log; yes_ "$R|get nodes --subresource=log"; }
s_pods_exec() { scene pods-exec; yes_ "$R|create pods --subresource=exec -A"; }
s_sa_token() { scene sa-token; yes_ "$R|create serviceaccounts --subresource=token -A"; }
s_ns_secrets() { scene ns-secrets; printf 'kube-system\tServiceAccount/ci/runner \n' > "$SCENE/rbs"; yes_ "$R|list secrets -n kube-system"; }
s_ns_token() { scene ns-token; printf 'ci\tServiceAccount//runner \n' > "$SCENE/rbs"; yes_ "$R|create serviceaccounts --subresource=token -n ci"; }
s_ns_exec_group() { scene ns-exec; printf 'apps\tGroup//system:serviceaccounts:ci \n' > "$SCENE/rbs"; yes_ "$R|create pods --subresource=exec -n apps"; }
s_unbound() { scene unbound; yes_ "$R|list secrets -n kube-system"; }
s_yes_reason() { scene yes-reason; yes_ "!$R|get nodes --subresource=proxy"; }
s_default() { scene default; printf 'ci\t\n' > "$SCENE/pods"; yes_ 'system:serviceaccount:ci:default|list secrets -A'; }
s_forbid() { scene forbid; : > "$SCENE/forbid"; }
s_nopods() { scene nopods; : > "$SCENE/pods"; }
s_norbs() { scene norbs; : > "$SCENE/norbs"; }

echo "== сцены"
s_control
assert "0 2 0 10 0" "$(run "$SUBJ" n1) $(census)" "контроль: «да» нет — 0; SA 2 (у двух подов одна), ns с привязками 0, вопросов 10; чужой узел не спрошен"
assert "нет" "$(grep -qE -- '-o ?(json|yaml)( |$)' "$SCENE/log" && echo да || echo нет)" "под ни разу не снят целиком: env не читается"
for c in secrets-all nodes-proxy nodes-log pods-exec sa-token; do
    "s_${c//-/_}"
    assert "1 да" "$(run "$SUBJ" n1) $(reach ci/runner "$c")" "кластерный вопрос $c у SA раннера — 1, REACH называет SA и вопрос"
done
s_ns_secrets
assert "1 да 2 1 13 1" "$(run "$SUBJ" n1) $(reach ci/runner ns-secrets@kube-system) $(census)" "секреты в kube-system по RoleBinding на SA — 1, вопрос с -n kube-system (с -A не видно)"
s_ns_token
assert "1 да" "$(run "$SUBJ" n1) $(reach ci/runner ns-sa-token@ci)" "субъект SA без namespace — ns привязки: токены в ci — 1"
s_ns_exec_group
assert "1 да" "$(run "$SUBJ" n1) $(reach ci/runner ns-pods-exec@apps)" "группа system:serviceaccounts:ci в apps — exec в apps — 1"
s_unbound
assert "0 0" "$(run "$SUBJ" n1) $(census | cut -d' ' -f2)" "ns без привязки не спрашивается: -n kube-system без RoleBinding — 0 (граница: право мимо rbac)"
s_yes_reason
assert "1 да" "$(run "$SUBJ" n1) $(reach ci/runner nodes-proxy)" "ответ «yes - причина» (вебхук) — «да», а не «не судимо»"
s_default
assert "1 да" "$(run "$SUBJ" n1) $(reach ci/default secrets-all)" "SA пода без имени — default своего пространства"
s_forbid
assert "2 да" "$(run "$SUBJ" n1) $(grep -qF 'нет права имперсонации' "$W/err" && echo да || echo нет)" "имперсонация запрещена — 2 «не судимо», а не «доступа нет»"
scene nonode
assert "2" "$(run "$SUBJ" n9)" "узла нет — 2"
s_nopods
assert "2 да" "$(run "$SUBJ" n1) $(grep -qF 'подов 0' "$W/err" && echo да || echo нет)" "подов на узле 0 — 2, а не «доступа нет»"
s_norbs
assert "2 да" "$(run "$SUBJ" n1) $(grep -qF 'RoleBinding не прочитаны' "$W/err" && echo да || echo нет)" "RoleBinding не прочитаны — 2"
assert "64" "$(run "$SUBJ")" "довода нет — 64"

echo "== мутанты node-reach.sh"
# mut|twin <имя> <было> <стало> <сцена> — мутант меняет исход сцены, близнец — нет.
apply() {
    local a="$2" b="$3" f="$4"
    [ "$(grep -cF -- "$a" "$SUBJ")" = 1 ] || return 1
    awk -v a="$a" -v b="$b" '{ i = index($0, a); if (i) $0 = substr($0, 1, i - 1) b substr($0, i + length(a)); print }' "$SUBJ" > "$f"
}
outcome() { "$2"; echo "$(run "$1" n1)|$(cat "$W/out")"; }
mut() {
    if ! apply "$1" "$2" "$3" "$W/mut.sh"; then echo "  [FAIL] мутант «$1»: образец не единственный" >&2; fail=$((fail + 1)); return; fi
    if [ "$(outcome "$SUBJ" "$4")" != "$(outcome "$W/mut.sh" "$4")" ]; then echo "  [OK]   мутант «$1» красный"; pass=$((pass + 1))
    else echo "  [FAIL] мутант «$1» выжил" >&2; fail=$((fail + 1)); fi
}
twin() {
    if ! apply "$1" "$2" "$3" "$W/twin.sh"; then echo "  [FAIL] близнец «$1»: образец не единственный" >&2; fail=$((fail + 1)); return; fi
    if [ "$(outcome "$SUBJ" "$4")" = "$(outcome "$W/twin.sh" "$4")" ]; then echo "  [OK]   близнец «$1» молчит"; pass=$((pass + 1))
    else echo "  [FAIL] близнец «$1» красный" >&2; fail=$((fail + 1)); fi
}
mut "secrets-all без -A"                  'secrets-all|list secrets -A' 'secrets-all|list secrets' s_secrets_all
mut "nodes-proxy без подресурса"          'nodes-proxy|get nodes --subresource=proxy' 'nodes-proxy|get nodes' s_nodes_proxy
mut "nodes-log без подресурса"            'nodes-log|get nodes --subresource=log' 'nodes-log|get nodes' s_nodes_log
mut "pods-exec: create → get"             '|create pods --subresource=exec -A' '|get pods --subresource=exec -A' s_pods_exec
mut "sa-token без подресурса"             'sa-token|create serviceaccounts --subresource=token -A' 'sa-token|create serviceaccounts -A' s_sa_token
mut "ns-secrets: не тот ресурс"           'ns-secrets|list secrets' 'ns-secrets|list configmaps' s_ns_secrets
mut "ns-pods-exec: create → get"          'ns-pods-exec|create pods' 'ns-pods-exec|get pods' s_ns_exec_group
mut "ns-sa-token без подресурса"          'ns-sa-token|create serviceaccounts --subresource=token' 'ns-sa-token|create serviceaccounts' s_ns_token
mut "вопрос по ns без -n"                 '[ -z "$at" ] || qa+=(-n "$at")' ':' s_ns_secrets
mut "группа субъекта не читается"         '(f[1] == "Group" &&' '(0 &&' s_ns_exec_group
mut "namespace субъекта пуст — не ns привязки" 'sns = (f[2] == "" ? $1 : f[2])' 'sns = f[2]' s_ns_token
mut "селектор узла снят"                  ' --field-selector "spec.nodeName=$NODE"' '' s_control
mut "«yes - причина» — не «да»"           'yes | "yes - "*)' 'yes)' s_yes_reason
mut "вопрос о себе, без --as"             ' --as="system:serviceaccount:$ns:$sa"' '' s_nodes_proxy
mut "непонятный ответ — «нет»"            '        *) void "can-i' '        *) : "can-i' s_forbid
mut "подов 0 — «доступа нет»"             '[ -n "$sas" ] || void' '[ -n "$sas" ] || true' s_nopods
mut "RoleBinding не прочитаны — молча"    '    void "RoleBinding не прочитаны' '    true "RoleBinding не прочитаны' s_norbs
mut "SA без дедупликации"                 "| sort -u)\"" "| sort)\"" s_control
twin "дедупликация записана sort | uniq"  "| sort -u)\"" "| sort | uniq)\"" s_control

total=$((pass + fail))
echo "[CENSUS] node-reach-inject: утверждений $total, сошлось $pass, разошлось $fail"
[ "$total" -gt 0 ] || { echo "[VOID] node-reach-inject: утверждений 0" >&2; exit 2; }
[ "$fail" -eq 0 ]
