#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# chain-inject.sh — доказательство шаблона цепочки посадок scripts/autoland/chain.sh (ws#1289 (б)).
#
# Настоящий git (origin — голый репозиторий, клон, ветка PR), двойники лишь у gh, отправки
# слота, генератора тела, демона вливания и detach.sh status (швы CHAIN_* шапки chain.sh).
# Сцены (каждая судится по исходу И по журналу вызовов):
#   C1 зелёная без догона: тело генератором ПОСЛЕ сверки головы на origin, Refs строки спеки
#      перед закрывающими, правка тела, демон с KACHO_TASK задачи; код 0;
#   C2 генератор тела вышел 3 — ни правки, ни демона; со stop — код 1;
#   C3 догон: отправка с KACHO_TASK раньше генератора, генератор — на новой голове; копия снята;
#   C4 догон, демон красный (без stop) — копия догона снята ловушкой и на отказе;
#   C5 срок службы короче строк × (демон + гейт + 600) — 64 до первого вызова; C6 срок не задан — 64;
#   C7 --after: предшественник с кодом 1 — 3, вызовов ноль; близнец — код 0, цепочка идёт;
#   C8 правка тела не прошла — демона нет; C9 отправка догона «прошла», а голова на origin прежняя —
#      тела и демона нет;
#   C11 --after: предшественник идёт (status 3), затем 0 — цепочка дождалась и пошла, status
#      спрошен дважды (приёмка check-verifier @e91dbdb60: мутант «идёт — стоп» сцены C7 не ловила).
# Затем мутанты chain.sh — каждый обязан покрасить свою сцену.
# Коды: 0 — всё прошло; 1 — провал; 2 — предпосылки нет (git).
# shellcheck disable=SC2317,SC2329  # сцены зовутся косвенно ("$c"), мутанты — через CH
# shellcheck source-path=SCRIPTDIR
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CHAIN="$HERE/chain.sh"
command -v git > /dev/null || { echo "[VOID] chain-inject: git нет"; exit 2; }
T="$(mktemp -d)" || exit 2
trap 'rm -rf "$T"' EXIT
# Подпись песочницы — корневая учётка вызывающего в своём HOME (scripts/lib/sandbox-git-home.sh,
# tooling-gate check-16); посев и сама цепочка (её слияние догона) идут под этим HOME.
# shellcheck source=../lib/sandbox-git-home.sh
. "$HERE/../lib/sandbox-git-home.sh"
sandbox_git_home "$T/home" || { echo "[VOID] chain-inject: корневой подписи нет"; exit 2; }
git() { sandbox_git "$@"; }
pass=0; fail=0
ok() { if [ "$2" = 0 ]; then echo "  [OK]   $1"; pass=$((pass + 1)); else echo "  [FAIL] $1${3:+ — $3}"; fail=$((fail + 1)); fi; }

mkdir -p "$T/bin"
cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >> "$CALLS"
case "$1 $2" in
  "pr view") br="$(cat "$FX/pr-$3")"; h="$(git -C "$FX/origin.git" rev-parse "refs/heads/$br")"; printf 'OPEN\t%s\t%s\n' "$h" "$br" ;;
  "pr edit") cp "$7" "$FX/edited-$3"; exit "${GH_EDIT_RC:-0}" ;;
  "run list") ;;
esac
EOF
cat > "$T/bin/push" <<'EOF'
#!/usr/bin/env bash
echo "push task=${KACHO_TASK:-нет}" >> "$CALLS"
[ "${PUSH_NOOP:-}" != 1 ] || exit 0
exec "$@"
EOF
cat > "$T/bin/body" <<'EOF'
#!/usr/bin/env bash
o="$(git -C "$RITUAL_REPO_DIR" ls-remote origin | grep -c "^$3")"
echo "body task=${KACHO_TASK:-нет} head=$3 onorigin=$o" >> "$CALLS"
[ "${BODY_RC:-0}" = 0 ] || { echo "отказ генератора" >&2; exit "$BODY_RC"; }
printf 'Состав\n\nCloses #7\nCloses #5\n'
EOF
cat > "$T/bin/autoland" <<'EOF'
#!/usr/bin/env bash
h=""; while [ $# -gt 0 ]; do [ "$1" = --head ] && h="$2"; shift; done
echo "daemon task=${KACHO_TASK:-нет} head=$h" >> "$CALLS"
exit "${DAEMON_RC:-0}"
EOF
cat > "$T/bin/detach" <<'EOF'
#!/usr/bin/env bash
exit "$(cat "$2")"
EOF
# detach-then-0: первый вызов status — 3 (предшественник идёт), следующие — 0; счёт — в <.rc>.n
cat > "$T/bin/detach-then-0" <<'EOF'
#!/usr/bin/env bash
n="$(cat "$2.n" 2> /dev/null || echo 0)"; echo $((n + 1)) > "$2.n"; [ "$n" -ge 1 ] && exit 0; exit 3
EOF
chmod +x "$T/bin/"*

# fixture <имя> <отставание да|нет> — origin, клон, ветка PR 5-x (PR 1)
fixture() {
    local d="$T/$1"; rm -rf "$d"; mkdir -p "$d/ws/tmp/autoland"
    git init -q --bare "$d/origin.git"
    git clone -q "$d/origin.git" "$d/clone" 2> /dev/null; git -C "$d/clone" checkout -q -B main
    echo a > "$d/clone/a"; git -C "$d/clone" add a; git -C "$d/clone" commit -qm "#1 база"; git -C "$d/clone" push -q origin HEAD:main
    git -C "$d/clone" checkout -qb 5-x; echo b > "$d/clone/b"; git -C "$d/clone" add b; git -C "$d/clone" commit -qm "#5 правка"
    git -C "$d/clone" push -q origin 5-x; git -C "$d/clone" checkout -q main
    if [ "$2" = да ]; then echo c > "$d/clone/c"; git -C "$d/clone" add c; git -C "$d/clone" commit -qm "#2 ствол ушёл"; git -C "$d/clone" push -q origin main; fi
    git -C "$d/clone" checkout -q --detach
    echo 5-x > "$d/pr-1"; : > "$d/calls"
    printf '1|5|#5 merge #1: правка|%s|%s|%s\n' "" "${3:-}" "${4:-7}" > "$d/spec"
    FX="$d"
}
run() {  # [env…] — цепочка над фикстурой FX; код
    sandbox_run env CALLS="$FX/calls" FX="$FX" CHAIN_WS="$FX/ws" CHAIN_GH="$T/bin/gh" CHAIN_PUSH="$T/bin/push" CHAIN_PR_BODY="$T/bin/body" \
        CHAIN_AUTOLAND="$T/bin/autoland" CHAIN_DETACH="$T/bin/detach" CHAIN_TIMEOUT=10 CHAIN_GATE_TIMEOUT=10 CHAIN_LS_PAUSE=0 CHAIN_AFTER_POLL=0 \
        KACHO_DETACHED_UNTIL="$(( $(date +%s) + 100000 ))" "$@" bash "${CH:-$CHAIN}" PRO-Robotech/kaname "$FX/clone" main "$FX/spec" ${AFTER:+--after "$AFTER"} > "$FX/out" 2>&1
}
line_no() { grep -n "^$1" "$FX/calls" | head -n1 | cut -d: -f1; }

c1() { fixture c1 нет; run; local rc=$?; local b d; b="$(line_no body)"; d="$(line_no daemon)"
    [ "$rc" = 0 ] && grep -q '^body task=5 .* onorigin=1$' "$FX/calls" && [ -n "$d" ] && [ "$b" -lt "$d" ] \
        && grep -q '^daemon task=5 ' "$FX/calls" && [ "$(tail -n2 "$FX/edited-1" | tr '\n' ' ')" = "Refs #7 Closes #5 " ]; }
c2() { fixture c2 нет stop; run env BODY_RC=3; local rc=$?
    [ "$rc" = 1 ] && ! grep -q '^gh pr edit' "$FX/calls" && ! grep -q '^daemon' "$FX/calls" && grep -q 'pr-body.sh код 3 — PR не вливается' "$FX/out"; }
c3() { fixture c3 да; run; local rc=$?; local p b nh
    p="$(line_no push)"; b="$(line_no body)"; nh="$(git -C "$FX/origin.git" rev-parse refs/heads/5-x)"
    [ "$rc" = 0 ] && grep -q '^push task=5$' "$FX/calls" && [ -n "$p" ] && [ -n "$b" ] && [ "$p" -lt "$b" ] \
        && grep -q "^body task=5 head=$nh onorigin=1\$" "$FX/calls" && grep -q "^daemon task=5 head=$nh\$" "$FX/calls" && [ ! -e "$FX/ws/tmp/land-kaname-1" ]; }
c4() { fixture c4 да; run env DAEMON_RC=1; local wl; wl="$(git -C "$FX/clone" worktree list)"; [ ! -e "$FX/ws/tmp/land-kaname-1" ] && [[ "$wl" != *land-kaname* ]] && grep -q "^daemon" "$FX/calls"; }
c5() { fixture c5 нет; run env KACHO_DETACHED_UNTIL="$(( $(date +%s) + 5 ))"; local rc=$?; [ "$rc" = 64 ] && [ ! -s "$FX/calls" ] && grep -q 'срок службы' "$FX/out"; }
c6() { fixture c6 нет; run env -u KACHO_DETACHED_UNTIL; local rc=$?; [ "$rc" = 64 ] && [ ! -s "$FX/calls" ]; }
c7() { fixture c7 нет; echo 1 > "$FX/pred.rc"; AFTER="$FX/pred.rc" run; local rc=$?; [ "$rc" = 3 ] && [ ! -s "$FX/calls" ] || return 1
    fixture c7b нет; echo 0 > "$FX/pred.rc"; AFTER="$FX/pred.rc" run; rc=$?; [ "$rc" = 0 ] && grep -q '^daemon' "$FX/calls"; }
c8() { fixture c8 нет; run env GH_EDIT_RC=1; grep -q '^gh pr edit' "$FX/calls" && ! grep -q '^daemon' "$FX/calls"; }
c9() { fixture c9 да; run env PUSH_NOOP=1; ! grep -q "^body" "$FX/calls" && ! grep -q "^daemon" "$FX/calls" && grep -q "голова не на origin" "$FX/out"; }
c11() { fixture c11 нет; echo x > "$FX/pred.rc"; AFTER="$FX/pred.rc" run env CHAIN_DETACH="$T/bin/detach-then-0"; local rc=$?
    [ "$rc" = 0 ] && grep -q '^daemon' "$FX/calls" && [ "$(cat "$FX/pred.rc.n" 2> /dev/null)" = 2 ]; }

echo "== сцены chain.sh"
for c in c1 c2 c3 c4 c5 c6 c7 c8 c9 c11; do "$c"; ok "$c" "$?" "$(tail -n3 "$FX/out" 2> /dev/null | tr '\n' ' ')"; done

echo "== мутанты chain.sh (каждый обязан покрасить свою сцену)"
mutant() {  # <имя> <сцена> <было> <стало>
    local m="$T/mut-$1.sh"
    awk -v a="$3" -v b="$4" 'BEGIN{n=0} { i=index($0,a); if (i) { n++; $0=substr($0,1,i-1) b substr($0,i+length(a)) } print } END{ if (n!=1) exit 3 }' "$CHAIN" > "$m" \
        || { ok "мутант $1: якорь не единствен" 1; return; }
    if CH="$m" "$2"; then ok "мутант $1: выжил ($2 зелена)" 1; else ok "мутант $1 убит сценой $2" 0; fi
}
mutant body-rc-ignored c2 'body "$PR" "$TASK" "$br" "$head" || { rc=1; break; }' 'body "$PR" "$TASK" "$br" "$head" || true'
mutant refs-filter-dropped c1 '    refs_filter "$b" $REFS' '    :'
mutant push-task-dropped c3 'env KACHO_TASK="$task" "${PUSH[@]}"' 'env "${PUSH[@]}"'
mutant body-task-dropped c1 'env KACHO_TASK="$task" RITUAL_REPO_DIR' 'env RITUAL_REPO_DIR'
mutant deadline-unchecked c5 '[ "$left" -ge "$need" ] ||' 'true ||'
mutant cleanup-dropped c4 'trap cleanup EXIT' ':'
mutant after-ignored c7 '[ "$arc" -eq 0 ] || {' 'true || {'
mutant edit-rc-ignored c8 '> /dev/null 2>&1 || { log "PR#$pr: gh pr edit не прошёл' '> /dev/null 2>&1; true || { log "PR#$pr: gh pr edit не прошёл'
mutant body-before-origin c9 '    on_origin "$br" "$head" || {' '    true || {'
mutant after-no-wait c11 '[ "$arc" -eq 3 ] || break' 'break'

echo "chain-inject: проверок $((pass + fail)), прошло $pass, провалено $fail"
[ "$fail" -eq 0 ]
