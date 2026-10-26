#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# node-reach-inject.sh — доказательство того, что `scripts/node-reach.sh` СПОСОБЕН назвать
# полномочие, достижимое с узла, и не путает «судить нечем» с «доступа нет» (ws#1418).
#
# Вход — двойник `kubectl` (шов KUBECTL): поды узла и решения SubjectAccessReview из файлов
# сцены, каждое обращение пишется в журнал. Двойник отвечает «yes» лишь на вопрос С `--as`
# нужной SA, как API-сервер; без `--as` — «no» (вопрос о себе не о той личности).
# Сцены:
#   контроль — две SA (одна у двух подов), «да» нет → 0, SA 2, вопросов 10;
#   nodes/proxy у SA раннера (настоящая форма урока 2a3dbd9d: подресурс, `--list` его не видит)
#     → 1, строка REACH называет SA и вопрос;
#   SA пода без имени — default своего пространства;
#   имперсонация запрещена (ответ пуст, ошибка) → 2, а не «доступа нет»; узла нет → 2;
#     подов на узле 0 → 2; довода нет → 64;
#   двойник ни разу не спрошен о `-o json|yaml` пода: env не читается.
# Мутанты скрипта (по одной правке) обязаны покраснеть; близнец той же формы — молчать.
# Коды: 0 — все утверждения сошлись; 1 — хотя бы одно нет.
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

# Двойник kubectl: сцена — каталог $SCENE (nodes, pods, yes, forbid); журнал — $SCENE/log.
cat > "$W/kubectl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SCENE/log"
case "$1 $2" in
    "get node") grep -qxF -- "$3" "$SCENE/nodes" 2> /dev/null; exit $? ;;
    "get pods") cat "$SCENE/pods" 2> /dev/null; exit 0 ;;
    "auth can-i")
        shift 2
        as="" q=()
        for a in "$@"; do case "$a" in --as=*) as="${a#--as=}" ;; *) q+=("$a") ;; esac; done
        if [ -f "$SCENE/forbid" ]; then echo "Error from server (Forbidden): cannot impersonate" >&2; exit 1; fi
        if [ -n "$as" ] && grep -qxF -- "$as|${q[*]}" "$SCENE/yes" 2> /dev/null; then echo yes; exit 0; fi
        echo no; exit 1 ;;
esac
echo "двойник: обращение вне сцены: $*" >&2
exit 3
SH
chmod +x "$W/kubectl"

# scene <имя> — новый каталог сцены с узлом n1 и двумя SA (runner у двух подов).
scene() {
    SCENE="$W/s-$1"; export SCENE
    mkdir -p "$SCENE"
    echo n1 > "$SCENE/nodes"
    printf 'kube-system\tkube-proxy\nci\trunner\nci\trunner\n' > "$SCENE/pods"
    : > "$SCENE/yes"
}
# run <скрипт> [довод…] — код; вывод в $W/out, ошибки в $W/err.
run() { local s="$1"; shift; KUBECTL="$W/kubectl" bash "$s" "$@" > "$W/out" 2> "$W/err"; echo $?; }
census() { sed -n 's/.*SA \([0-9]*\), вопросов \([0-9]*\), «да» \([0-9]*\).*/\1 \2 \3/p' "$W/out"; }

echo "== сцены"
scene control
assert "0 2 10 0" "$(run "$SUBJ" n1) $(census)" "контроль: «да» нет — 0; SA 2 (у двух подов одна), вопросов 10"
assert "нет" "$(grep -qE -- '-o ?(json|yaml)( |$)' "$SCENE/log" && echo да || echo нет)" "под ни разу не снят целиком: env не читается"

scene proxy
echo 'system:serviceaccount:ci:runner|get nodes --subresource=proxy' > "$SCENE/yes"
rc="$(run "$SUBJ" n1)"
assert "1 да 2 10 1" "$rc $(grep -qxF "$(printf 'REACH\tci/runner\tnodes-proxy')" "$W/out" && echo да || echo нет) $(census)" "nodes/proxy у SA раннера (урок 2a3dbd9d) — 1, REACH называет SA и вопрос"

scene default
printf 'ci\t\n' > "$SCENE/pods"
echo 'system:serviceaccount:ci:default|list secrets -A' > "$SCENE/yes"
assert "1 да" "$(run "$SUBJ" n1) $(grep -qF "$(printf 'REACH\tci/default\tsecrets-all')" "$W/out" && echo да || echo нет)" "SA пода без имени — default своего пространства"

scene forbid
: > "$SCENE/forbid"
assert "2 да" "$(run "$SUBJ" n1) $(grep -qF 'нет права имперсонации' "$W/err" && echo да || echo нет)" "имперсонация запрещена — 2 «не судимо», а не «доступа нет»"

scene nonode
assert "2" "$(run "$SUBJ" n9)" "узла нет — 2"
scene nopods
: > "$SCENE/pods"
assert "2 да" "$(run "$SUBJ" n1) $(grep -qF 'подов 0' "$W/err" && echo да || echo нет)" "подов на узле 0 — 2, а не «доступа нет»"
assert "64" "$(run "$SUBJ")" "довода нет — 64"

echo "== мутанты node-reach.sh"
# mutant <имя> <было> <стало> <сцена-функция> <ожидаемый код контроля> — мутант меняет исход.
mut() {
    local name="$1" a="$2" b="$3" setup="$4" f="$W/mut.sh" want got
    if [ "$(grep -cF -- "$a" "$SUBJ")" != 1 ]; then echo "  [FAIL] мутант «$name»: образец не единственный" >&2; fail=$((fail + 1)); return; fi
    awk -v a="$a" -v b="$b" '{ i = index($0, a); if (i) $0 = substr($0, 1, i - 1) b substr($0, i + length(a)); print }' "$SUBJ" > "$f"
    "$setup"
    want="$(run "$SUBJ" n1)|$(cat "$W/out")"
    "$setup"
    got="$(run "$f" n1)|$(cat "$W/out")"
    if [ "$want" != "$got" ]; then echo "  [OK]   мутант «$name» красный"; pass=$((pass + 1))
    else echo "  [FAIL] мутант «$name» выжил" >&2; fail=$((fail + 1)); fi
}
twin() {
    local name="$1" a="$2" b="$3" setup="$4" f="$W/twin.sh" want got
    if [ "$(grep -cF -- "$a" "$SUBJ")" != 1 ]; then echo "  [FAIL] близнец «$name»: образец не единственный" >&2; fail=$((fail + 1)); return; fi
    awk -v a="$a" -v b="$b" '{ i = index($0, a); if (i) $0 = substr($0, 1, i - 1) b substr($0, i + length(a)); print }' "$SUBJ" > "$f"
    "$setup"
    want="$(run "$SUBJ" n1)|$(cat "$W/out")"
    "$setup"
    got="$(run "$f" n1)|$(cat "$W/out")"
    if [ "$want" = "$got" ]; then echo "  [OK]   близнец «$name» молчит"; pass=$((pass + 1))
    else echo "  [FAIL] близнец «$name» красный" >&2; fail=$((fail + 1)); fi
}
s_proxy() { scene proxy; echo 'system:serviceaccount:ci:runner|get nodes --subresource=proxy' > "$SCENE/yes"; }
s_control() { scene control; }
s_forbid() { scene forbid; : > "$SCENE/forbid"; }
s_nopods() { scene nopods; : > "$SCENE/pods"; }
mut "вопрос nodes/proxy снят" 'nodes-proxy|get nodes --subresource=proxy' 'nodes-proxy|get nodes' s_proxy
mut "вопрос о себе, без --as" ' --as="system:serviceaccount:$ns:$sa"' '' s_proxy
mut "непонятный ответ — «нет»" '            *) void "can-i' '            *) : "can-i' s_forbid
mut "подов 0 — «доступа нет»" '[ -n "$sas" ] || void' '[ -n "$sas" ] || true' s_nopods
mut "SA без дедупликации" "| sort -u)\"" "| sort)\"" s_control
twin "дедупликация записана sort | uniq" "| sort -u)\"" "| sort | uniq)\"" s_control

total=$((pass + fail))
echo "[CENSUS] node-reach-inject: утверждений $total, сошлось $pass, разошлось $fail"
[ "$total" -gt 0 ] || { echo "[VOID] node-reach-inject: утверждений 0" >&2; exit 2; }
[ "$fail" -eq 0 ]
