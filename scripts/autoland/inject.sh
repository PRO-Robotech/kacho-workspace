#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# inject.sh — доказательство демона вливания scripts/autoland/autoland.sh ИСПОЛНЕНИЕМ
# (ws#1147). Площадка и гейты подставные: двойник gh (GET запроса и коммита слияния,
# `gh pr merge` со сверкой головы, как у хостинга) и двойники ci-read.sh,
# merge-readiness.sh, landing-precheck.sh, branch-audit.sh, отвечающие кодом по
# очереди сцены. Снятие ветки судится на настоящем git: голый origin, клон, копия
# (worktree), вливание коммитом слияния. Сверяется код И напечатанное в .state.
#
# СЦЕНЫ (каждая меняет один факт против зелёного близнеца):
#   green        — ci-read 3, 3, 0 → гейты 0 → вливание `--merge --match-head-commit
#                  <голова> --subject <…> --body "" --delete-branch`, исход merged <sha>;
#                  ci-read зван с --head и --from-state; запретных флагов в вызове нет;
#   red          — ci-read 1 → red с причиной ДОСЛОВНО, вливания нет;
#   moved-start  — голова запроса ≠ --head → head-moved, гейтов и вливания нет;
#   moved-gates  — голова ушла во время landing-precheck → head-moved, вливания нет;
#   moved-merge  — голова ушла в момент вливания (хостинг отказал) → head-moved;
#   allow-ok     — landing-precheck 1 с причиной из --allow → merged;
#   allow-bad    — причины из --allow и вне его → red с недопущенной, вливания нет;
#   stale        — ci-read 4 → stale-base, вливания нет (базу демон не догоняет);
#   mr-red       — merge-readiness 1 → red;
#   timeout      — ci-read 3 всё время → timeout по пределу;
#   void         — merge-readiness 2 трижды → void; близнец void-twin: 2, 2, 0 → merged;
#   ratelimit    — ci-read 2 с REASON RATE-LIMIT ×4, затем 0 → merged (лимит — не VOID);
#   pr-unread    — запрос не прочитан --void-limit раз подряд → void, гейтов нет;
#   draft        — ci-read 5 (черновик), затем 0 → merged;
#   closed       — запрос закрыт без вливания → red PR-NOT-OPEN, гейтов нет;
#   already      — запрос уже влит этой головой → merged, повторного вливания нет;
#   fifo         — пауза 20 с, строка демона состояния в FIFO будит раньше: исход < 10 с;
#   fifo-nowriter — демона состояния нет, FIFO без писателя: каждое ожидание кончается
#                  паузой (timeout), исход merged с кодом 0; пауза БЫЛА — прошло не меньше
#                  2·--poll − 1 с и меньше предела 20 с, время печатается и на зелёном;
#                  мутант без timeout виснет на открытии FIFO и ловится кодом 124 предела,
#                  мутант без ожидания вовсе — временем;
#   args         — неформенный --subject, --head не sha40, --stand-report без
#                  --stand-expect → код 2, .state нет;
#   detach       — start возвращается < 6 с, печатает pid, журнал, state; демон в
#                  другом сеансе, status 3; второй start — 3 (замок); TERM → void, status 2;
#                  мёртвый демон без исхода — status 2;
#   recipe       — гейты — рецептом «ЗАПУСК», вырезанным из origin/main песочницы → merged;
#                  близнец recipe-cut: меток рецепта в origin/main нет → void;
#   prune        — влитая ветка снята в клоне, чистая копия снята, origin пуст; prune-dirty:
#                  копия с неотслеживаемым файлом остаётся с веткой; prune-ahead: местная
#                  голова впереди влитой — ни ветка, ни копия не сняты; prune-remote:
#                  ветку на origin хостинг не снял — демон снимает её сам;
#   empty-code   — landing-precheck 1 с причиной БЕЗ кода (REASON<TAB><TAB>текст) — red и без
#                  --allow, и с непустым --allow;
#   lp-head      — landing-precheck судил другую голову (его CENSUS) → head-moved; строки
#                  судимой головы нет → void;
#   prune-origin-ahead — ветка на origin ушла вперёд после вливания → не снимается;
#   prune-not-in-base  — хостинг сказал merged, а влитой головы в базе нет → ничего не снято;
#   status       — коды status для каждого исхода (4, 5, 6 — тоже) и для слова вне перечня;
#   census       — перепись процессов судит СВОЁ по метке AUTOLAND_PROBE_ID: свой процесс
#                  с иным порядком доводов виден, чужой с «--pr N --head» — нет; reap снимает
#                  свой и не трогает чужой, даже когда чужой pid лежит в .pid под $T;
#   guard        — no-wait-guard пропускает команды start и status, а цикл ожидания
#                  агентом (until … sleep) — отказ;
#   static       — исполняемый текст демона без форсирующих флагов, обхода хуков, догона
#                  базы и изменяющего `gh api`.
#
# МУТАНТЫ — копия autoland.sh с одним дефектом обязана уронить свою сцену: без
# --match-head-commit, с --admin, без --delete-branch, допуск всех причин, без сверки
# головы перед вливанием, stale-base как ожидание, red как ожидание, без предела VOID,
# ci-read без --head, без сверки местной головы при снятии, закрытый как открытый, без
# сверки --subject, без FIFO, лимит площадки как VOID, пустой код допущен, голова
# landing-precheck не сверяется, строка его головы не требуется, origin-ветка снимается
# ушедшей вперёд, снятие без проверки «влитая — предок базы», status 4/5/6 как 0,
# ожидание FIFO без timeout, без ожидания вовсе, кэш — настоящий (CI_STATE_DIR не читается).
#
# СЛЕДОВ НЕТ (testing.md#no-residue). Песочница — на всю пробу: кэш (XDG_CACHE_HOME,
# CI_STATE_DIR), gh, гейты, клоны, замок — экспортом до первой сцены, поэтому и демон,
# отсоединённый под мутантом, машины не касается. Каждый демон пробы снимается по pid
# ловушкой EXIT (и на падении) — только свои: pid, записанные при запуске, и pid из .pid
# под $T с меткой пробы. Перепись до и после: файлы *__<PR пробы>.* в настоящем кэше
# демона состояния и живые процессы с меткой ЭТОЙ пробы; рост — код 1, кэш прочитан не
# весь — код 2 (не ноль). Правка, не легшая в текст, — VOID.
#
# ИСХОДЫ: 0 — все сцены зелёные, все мутанты убиты; 1 — сцена разошлась либо мутант
# выжил; 2 — судить нечем (нет jq, python3, git, setsid, flock, стража).
# shellcheck disable=SC2016,SC2034,SC2329  # тексты хуков и условия ok — для eval; сцены зовутся из массива ALL
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AL_REAL="$HERE/autoland.sh"
GUARD="$(cd "$HERE/../.." && pwd)/.claude/hooks/no-wait-guard/guard.py"
for t in jq python3 git setsid flock timeout; do
    command -v "$t" >/dev/null 2>&1 || { echo "VOID: нет $t" >&2; exit 2; }
done
[ -r "$AL_REAL" ] || { echo "VOID: нет $AL_REAL" >&2; exit 2; }
[ -r "$GUARD" ] || { echo "VOID: нет стража $GUARD" >&2; exit 2; }
LP_REAL="$(cd "$HERE/.." && pwd)/landing-precheck.sh"
[ -r "$LP_REAL" ] || { echo "VOID: нет $LP_REAL (метки рецепта «ЗАПУСК»)" >&2; exit 2; }

T="$(mktemp -d "${TMPDIR:-/tmp}/autoland-inject.XXXXXX")" || exit 2
PIDS=(); FOREIGN=()
# СВОЁ — по метке AUTOLAND_PROBE_ID=$T в окружении процесса (её экспортирует проба
# ниже, наследует всё, что проба порождает), а не по написанию доводов: образец
# «--pr N --head» видит демонов соседней пробы и не видит своего с иным порядком.
# Окружение читается встроенным mapfile — без дочернего процесса, который сам нёс бы метку.
own_pid() {
    local e; local -a env=()
    { mapfile -d '' -t env < "/proc/$1/environ"; } 2>/dev/null || return 1
    for e in "${env[@]}"; do [ "$e" = "AUTOLAND_PROBE_ID=$T" ] && return 0; done
    return 1
}
probe_procs() {  # число живых процессов ЭТОЙ пробы, кроме самой оболочки пробы
    local d p n=0
    for d in /proc/[0-9]*; do
        p="${d#/proc/}"
        [ "$p" != "$$" ] && [ "$p" != "${BASHPID:-}" ] && own_pid "$p" && n=$((n + 1))
    done
    echo "$n"
}
# Снимаются на любом исходе, и на падении, ТОЛЬКО свои: pid, записанные пробой при
# запуске (PIDS), и pid из .pid демонов под $T — если процесс несёт метку этой пробы.
reap() {
    local p f
    for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done
    for f in "$T"/*/run/*.pid "$T"/run-default/*.pid; do
        [ -f "$f" ] || continue
        p="$(cat "$f" 2>/dev/null)"
        [[ "$p" =~ ^[0-9]+$ ]] && own_pid "$p" && kill "$p" 2>/dev/null
    done
    return 0
}
cleanup() { local p; reap; for p in "${FOREIGN[@]}"; do kill "$p" 2>/dev/null; done; rm -rf "$T"; }
trap cleanup EXIT
# Подпись песочниц git — только из своего HOME с корневой подписью вызывающего
# (scripts/lib/sandbox-git-home.sh; tooling-gate check-16).
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/sandbox-git-home.sh
. "$HERE/../lib/sandbox-git-home.sh"
sandbox_git_home "$T/sghome" || { echo "VOID: подписи песочницы нет" >&2; exit 2; }

REPO=PRO-Robotech/kacho-workspace; PR=4242
# Перепись машины ДО: файлы пробы (номер её PR) в настоящем кэше демона состояния.
REAL_CS="${CI_STATE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/kacho-ci-state}"
real_cs_files() {  # число файлов пробы; «?» — каталог есть, а прочитан не весь (не ноль)
    local n
    [ -e "$REAL_CS" ] || { echo 0; return 0; }
    n="$(find "$REAL_CS" -name "*__${PR}.*" 2> "$T/cs-find.err" | wc -l)"
    if [ -s "$T/cs-find.err" ]; then echo "?"; else echo "$n"; fi
}
CS_BEFORE="$(real_cs_files)"
# Песочница — на ВСЮ пробу, а не на сцену: демон, запущенный любым вызовом (и под
# мутантом, пропустившим проверку доводов), не видит ни настоящего gh, ни кэша машины.
export AUTOLAND_PROBE_ID="$T" XDG_CACHE_HOME="$T/xdg" CI_STATE_DIR="$T/cs-none" AUTOLAND_GH="$T/gh" AUTOLAND_GATES="$T/gates" \
    AUTOLAND_WS="$T/ws0" AUTOLAND_CLONES="" AUTOLAND_INTERIM_LOCK="$T/interim.lock" AUTOLAND_DIR="$T/run-default"
SUBJ="#4000 merge #4242: проба демона"
HEAD_A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
HEAD_B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
MSHA=cccccccccccccccccccccccccccccccccccccccc
BASE=dddddddddddddddddddddddddddddddddddddddd
export MSHA BASE

# ── двойник площадки ───────────────────────────────────────────────────────────
cat > "$T/gh" <<'GH'
#!/usr/bin/env bash
FX="$AL_FX"
printf 'gh %s\n' "$*" >> "$FX/gh.calls"
case "$1" in
  api)
    case "$2" in
      repos/*/pulls/*) cat "$FX/pull.json" ;;
      repos/*/commits/*) printf '{"parents":[{"sha":"%s"},{"sha":"%s"}]}\n' "$BASE" "$(jq -r .head.sha "$FX/pull.json")" ;;
      *) echo "двойник: путь $2 не моделируется" >&2; exit 1 ;;
    esac ;;
  pr)
    [ "$2" = merge ] || { echo "двойник: gh pr $2 не моделируется" >&2; exit 1; }
    printf '%s\n' "$@" > "$FX/merge.args"
    [ ! -f "$FX/merge.hook" ] || bash "$FX/merge.hook"
    want=""; prev=""
    for a in "$@"; do [ "$prev" != --match-head-commit ] || want="$a"; prev="$a"; done
    cur="$(jq -r .head.sha "$FX/pull.json")"
    if [ -n "$want" ] && [ "$want" != "$cur" ]; then
      echo "GraphQL: Head branch was modified. Review and try the merge again. (mergePullRequest)" >&2; exit 1
    fi
    jq --arg m "$MSHA" '.state = "closed" | .merged = true | .merge_commit_sha = $m' "$FX/pull.json" > "$FX/pull.tmp" \
      && mv "$FX/pull.tmp" "$FX/pull.json"
    [ ! -f "$FX/merged.hook" ] || bash "$FX/merged.hook"
    echo "✓ Merged pull request #$3" ;;
  *) echo "двойник: gh $* не моделируется" >&2; exit 1 ;;
esac
GH
chmod +x "$T/gh"

# ── двойник гейта: код — по очереди .seq сцены (последний повторяется) ─────────
mkdir -p "$T/gates"
cat > "$T/gates/gate" <<'GATE'
#!/usr/bin/env bash
n="$(basename "$0")"; FX="$AL_FX"
printf '%s %s\n' "$n" "$*" >> "$FX/calls"
[ "$n" != branch-audit.sh ] || exit 0
i=$(( $(cat "$FX/$n.n" 2>/dev/null || echo 0) + 1 )); echo "$i" > "$FX/$n.n"
if [ "$n" = landing-precheck.sh ] && [ ! -f "$FX/lp.nohead" ]; then   # форма landing-precheck.sh: CENSUS судимой головы
  h="$(cat "$FX/lp.head" 2>/dev/null || jq -r .head.sha "$FX/pull.json")"
  printf 'CENSUS\t%s#%s голова %s (4000-probe → main)\n' "$1" "$2" "${h:0:12}"
fi
code="$(sed -n "${i}p" "$FX/$n.seq")"; [ -n "$code" ] || code="$(tail -n1 "$FX/$n.seq")"
if [ -f "$FX/$n.$code.out" ]; then cat "$FX/$n.$code.out"; else printf 'VERDICT\tдвойник\tкод %s\n' "$code"; fi
[ ! -f "$FX/$n.hook" ] || bash "$FX/$n.hook"
exit "$code"
GATE
for g in ci-read.sh merge-readiness.sh landing-precheck.sh branch-audit.sh; do cp "$T/gates/gate" "$T/gates/$g"; done
mkdir -p "$T/ws0"

pull() {  # <голова> <state> <merged>
    jq -n --arg h "$1" --arg s "$2" --argjson m "$3" --arg ms "$MSHA" --arg b "$BASE" --arg ref "${PULL_REF:-4000-probe}" \
        '{state: $s, merged: $m, merge_commit_sha: (if $m then $ms else null end), draft: false,
          head: {sha: $h, ref: $ref}, base: {ref: "main", sha: $b}}' > "$FX/pull.json"
}
new_fx() {  # <сцена>
    FX="$T/fx.$1.$RANDOM"; mkdir -p "$FX"
    PULL_REF=4000-probe; pull "${2:-$HEAD_A}" open false
    for g in ci-read.sh merge-readiness.sh landing-precheck.sh; do echo 0 > "$FX/$g.seq"; done
    CLONES=""; RUN_HEAD="${2:-$HEAD_A}"
}
move_head_hook() { printf 'jq %q "$AL_FX/pull.json" > "$AL_FX/p.t" && mv "$AL_FX/p.t" "$AL_FX/pull.json"\n' ".head.sha = \"$HEAD_B\"" > "$1"; }

RC=0; ST=""
run_al() {  # доводы сверх обязательных
    AL_FX="$FX" AUTOLAND_GH="$T/gh" AUTOLAND_GATES="${GATES-$T/gates}" AUTOLAND_DIR="$FX/run" \
        AUTOLAND_WS="${WS0:-$T/ws0}" AUTOLAND_CLONES="$CLONES" CI_STATE_DIR="$FX/cs" AUTOLAND_INTERIM_LOCK="$T/interim.lock" \
        timeout "${RUN_LIMIT:-120}" bash "$AL" run --repo "$REPO" --pr "$PR" --head "$RUN_HEAD" --subject "$SUBJ" --poll 1 "$@" \
        > "$FX/out" 2>&1
    RC=$?
    ST="$(cat "$FX"/run/*.state 2>/dev/null | head -n1)"
}

fails=0
ok() {  # <сцена> <что> <команда…>
    local s="$1" what="$2"; shift 2
    if "$@"; then return 0; fi
    printf '  [FAIL] %s: %s — исход «%s», код %s\n' "$s" "$what" "$ST" "$RC"
    fails=$((fails + 1))
}
st_is() { [ "${ST%% *}" = "$1" ]; }
st_has() { grep -qF -- "$1" <<< "$ST"; }
merge_called() { [ -s "$FX/merge.args" ]; }
not_merge_called() { ! merge_called; }
arg_after() {  # <флаг> <значение> — в вызове вливания значение идёт сразу за флагом
    awk -v f="$1" -v v="$2" 'p && $0 == v { found = 1 } { p = ($0 == f) } END { exit !found }' "$FX/merge.args"
}
no_forbidden_merge_flags() { ! grep -qxE -- '--(admin|force|auto|squash|rebase|no-verify)|-[asr]' "$FX/merge.args"; }
gate_called() { grep -q "^$1 " "$FX/calls" 2>/dev/null; }
no_gates() { [ ! -s "$FX/calls" ]; }

# ── сцены ──────────────────────────────────────────────────────────────────────
s_green() {
    new_fx green; printf '3\n3\n0\n' > "$FX/ci-read.sh.seq"; run_al
    ok green "исход merged <sha коммита слияния>, код 0" eval '[ "$RC" -eq 0 ] && st_is merged && st_has "$MSHA"'
    ok green "вливание вызвано" merge_called
    ok green "вливание --merge" grep -qx -- --merge "$FX/merge.args"
    ok green "вливание --match-head-commit <голова>" arg_after --match-head-commit "$HEAD_A"
    ok green "вливание --subject <заголовок>" arg_after --subject "$SUBJ"
    ok green "вливание --body \"\"" arg_after --body ""
    ok green "вливание --delete-branch" grep -qx -- --delete-branch "$FX/merge.args"
    ok green "в вызове вливания нет запретных флагов" no_forbidden_merge_flags
    ok green "ci-read зван с --head <голова> --from-state" grep -qF -- "ci-read.sh $REPO $PR --head $HEAD_A --from-state" "$FX/calls"
    ok green "ci-read зван трижды (3, 3, 0)" eval '[ "$(grep -c "^ci-read.sh " "$FX/calls")" -eq 3 ]'
    ok green "status merged — код 0" eval 'bash "$AL" status "$FX"/run/*.state >/dev/null; [ $? -eq 0 ]'
}
s_red() {
    new_fx red; echo 1 > "$FX/ci-read.sh.seq"
    printf 'REASON\tCI-FAILED\tпроверка «сводный вердикт» завершена failure\nVERDICT\tred\tкод 1\n' > "$FX/ci-read.sh.1.out"
    run_al --timeout 4
    ok red "исход red, код 1" eval '[ "$RC" -eq 1 ] && st_is red'
    ok red "причина дословно" st_has $'REASON\tCI-FAILED\tпроверка «сводный вердикт» завершена failure'
    ok red "вливания нет" not_merge_called
    ok red "status red — код 1" eval 'bash "$AL" status "$FX"/run/*.state >/dev/null; [ $? -eq 1 ]'
}
s_moved_start() {
    new_fx moved-start "$HEAD_B"; RUN_HEAD="$HEAD_A"; run_al
    ok moved-start "исход head-moved <ожидалась> <стала>, код 5" eval '[ "$RC" -eq 5 ] && [ "$ST" = "head-moved $HEAD_A $HEAD_B" ]'
    ok moved-start "гейтов нет" no_gates
    ok moved-start "вливания нет" not_merge_called
}
s_moved_gates() {
    new_fx moved-gates; move_head_hook "$FX/landing-precheck.sh.hook"; run_al
    ok moved-gates "исход head-moved, код 5" eval '[ "$RC" -eq 5 ] && st_is head-moved'
    ok moved-gates "вливания нет" not_merge_called
}
s_moved_merge() {
    new_fx moved-merge; move_head_hook "$FX/merge.hook"; run_al
    ok moved-merge "исход head-moved, код 5" eval '[ "$RC" -eq 5 ] && st_is head-moved'
    ok moved-merge "запрос не влит" eval '[ "$(jq -r .merged "$FX/pull.json")" = false ]'
}
s_allow_ok() {
    new_fx allow-ok; echo 1 > "$FX/landing-precheck.sh.seq"
    printf 'REASON\tSTAND-REPORT\tотчёта стенда нет\nVERDICT\tкод 1\n' > "$FX/landing-precheck.sh.1.out"
    run_al --allow TITLE-FORM,STAND-REPORT
    ok allow-ok "допущенная причина вливанию не мешает: merged" eval '[ "$RC" -eq 0 ] && st_is merged'
}
s_allow_bad() {
    new_fx allow-bad; echo 1 > "$FX/landing-precheck.sh.seq"
    printf 'REASON\tSTAND-REPORT\tотчёта стенда нет\nREASON\tBODY-MISSING-COMMIT\tкоммит 1234567 не назван\n' > "$FX/landing-precheck.sh.1.out"
    run_al --allow STAND-REPORT
    ok allow-bad "недопущенная причина — red, код 1" eval '[ "$RC" -eq 1 ] && st_is red'
    ok allow-bad "red называет недопущенную дословно" st_has $'REASON\tBODY-MISSING-COMMIT\tкоммит 1234567 не назван'
    ok allow-bad "допущенная в red не названа" eval '! st_has STAND-REPORT'
    ok allow-bad "вливания нет" not_merge_called
}
s_stale() {
    new_fx stale; echo 4 > "$FX/ci-read.sh.seq"
    printf 'REASON\tBASE-STALE\tmerge-base 1 ≠ голове базы main 2: отставание 3\n' > "$FX/ci-read.sh.4.out"
    run_al --timeout 4
    ok stale "исход stale-base с причиной, код 4" eval '[ "$RC" -eq 4 ] && st_is stale-base && st_has BASE-STALE'
    ok stale "вливания нет" not_merge_called
}
s_mr_red() {
    new_fx mr-red; echo 1 > "$FX/merge-readiness.sh.seq"; run_al
    ok mr-red "merge-readiness 1 — red" eval '[ "$RC" -eq 1 ] && st_is red && st_has merge-readiness'
    ok mr-red "landing-precheck не зван, вливания нет" eval '! gate_called landing-precheck.sh && not_merge_called'
}
s_timeout() {
    new_fx timeout; echo 3 > "$FX/ci-read.sh.seq"; run_al --timeout 3
    ok timeout "исход timeout, код 6, последнее — вердикт ci-read" eval '[ "$RC" -eq 6 ] && st_is timeout && st_has "ci-read код 3"'
    ok timeout "вливания нет" not_merge_called
}
s_void() {
    new_fx void; echo 2 > "$FX/merge-readiness.sh.seq"
    printf 'VOID\tплощадка не ответила\n' > "$FX/merge-readiness.sh.2.out"
    run_al --void-limit 3 --timeout 6
    ok void "три VOID подряд — исход void, код 2" eval '[ "$RC" -eq 2 ] && st_is void && st_has "3 раз подряд"'
    ok void "VOID дословно" st_has $'VOID\tплощадка не ответила'
    ok void "вливания нет" not_merge_called
}
s_void_twin() {
    new_fx void-twin; printf '2\n2\n0\n' > "$FX/merge-readiness.sh.seq"; run_al --void-limit 3
    ok void-twin "два VOID и 0 — merged" eval '[ "$RC" -eq 0 ] && st_is merged'
}
s_ratelimit() {
    new_fx ratelimit; printf '2\n2\n2\n2\n0\n' > "$FX/ci-read.sh.seq"
    printf 'REASON\tRATE-LIMIT\tостаток 12 из 5000, сброс 15:00\nVERDICT\tunread\tкод 2\n' > "$FX/ci-read.sh.2.out"
    run_al --void-limit 3
    ok ratelimit "лимит площадки не считается VOID: merged" eval '[ "$RC" -eq 0 ] && st_is merged'
}
s_pr_unread() {
    new_fx pr-unread; echo 'не JSON' > "$FX/pull.json"; run_al --void-limit 2 --timeout 5
    ok pr-unread "запрос не прочитан дважды — void, вливания и гейтов нет" eval '[ "$RC" -eq 2 ] && st_is void && st_has "запрос не прочитан 2 раз подряд" && no_gates && not_merge_called'
}
s_draft() {
    new_fx draft; printf '5\n0\n' > "$FX/ci-read.sh.seq"; run_al
    ok draft "черновик ждётся, затем merged" eval '[ "$RC" -eq 0 ] && st_is merged && [ "$(grep -c "^ci-read.sh " "$FX/calls")" -eq 2 ]'
}
s_closed() {
    new_fx closed; pull "$HEAD_A" closed false; run_al
    ok closed "закрытый без вливания — red PR-NOT-OPEN" eval '[ "$RC" -eq 1 ] && st_is red && st_has PR-NOT-OPEN'
    ok closed "гейтов и вливания нет" eval 'no_gates && not_merge_called'
}
s_already() {
    new_fx already; pull "$HEAD_A" closed true; run_al
    ok already "влит этой головой — merged <sha>" eval '[ "$RC" -eq 0 ] && st_is merged && st_has "$MSHA"'
    ok already "повторного вливания нет" not_merge_called
}
s_fifo() {
    new_fx fifo; printf '3\n0\n' > "$FX/ci-read.sh.seq"
    mkdir -p "$FX/cs/wait"; chmod 700 "$FX/cs" "$FX/cs/wait"
    local f="$FX/cs/wait/PRO-Robotech__kacho-workspace__$PR.fifo" t0 dt
    ( for _ in $(seq 1 100); do [ -p "$f" ] && break; sleep 0.1; done
      sleep 1; printf '%s %s %s код 0\n' "$REPO" "$PR" "$HEAD_A" > "$f" ) &
    PIDS+=("$!")
    t0=$(date +%s); run_al --poll 20; dt=$(( $(date +%s) - t0 ))
    ok fifo "строка демона состояния будит раньше паузы 20 с (прошло $dt с)" eval '[ "$RC" -eq 0 ] && st_is merged && [ "$dt" -lt 10 ]'
}
s_fifo_nowriter() {
    new_fx fifo-nowriter; printf '3\n3\n0\n' > "$FX/ci-read.sh.seq"
    mkdir -p "$FX/cs/wait"; chmod 700 "$FX/cs" "$FX/cs/wait"
    local t0 dt poll=2 waits=2 tol=1 limit=20
    t0=$(date +%s); RUN_LIMIT=$limit run_al --poll "$poll"; dt=$(( $(date +%s) - t0 ))
    # Пауза была: два ожидания по --poll — не меньше waits·poll − tol, но и не до предела.
    echo "  [время] fifo-nowriter: прошло $dt с при --poll $poll и $waits ожиданиях (норма ≥ $((waits * poll - tol)) и < $limit)"
    ok fifo-nowriter "демона состояния нет, FIFO без писателя — исход merged, код 0" eval '[ "$RC" -eq 0 ] && st_is merged'
    ok fifo-nowriter "демон продолжил после паузы: прошло $dt с, норма ≥ $((waits * poll - tol)) и < $limit" \
        eval '[ "$dt" -ge $((waits * poll - tol)) ] && [ "$dt" -lt "$limit" ]'
    ok fifo-nowriter "FIFO заведён демоном вливания (форма ожидания — FIFO, не sleep)" eval '[ -p "$FX/cs/wait/PRO-Robotech__kacho-workspace__$PR.fifo" ]'
}
s_args() {
    local rc
    new_fx args
    AUTOLAND_DIR="$FX/run" AUTOLAND_WS="$T/ws0" bash "$AL" start --repo "$REPO" --pr "$PR" --head "$HEAD_A" \
        --subject "#4000 влить" > "$FX/a1" 2>&1; rc=$?
    ok args "неформенный --subject — код 2" eval '[ "$rc" -eq 2 ] && grep -q "subject" "$FX/a1"'
    AUTOLAND_DIR="$FX/run" AUTOLAND_WS="$T/ws0" bash "$AL" start --repo "$REPO" --pr "$PR" --head abc \
        --subject "$SUBJ" > "$FX/a2" 2>&1; rc=$?
    ok args "--head не sha40 — код 2" eval '[ "$rc" -eq 2 ]'
    echo '{}' > "$FX/rep.json"
    AUTOLAND_DIR="$FX/run" AUTOLAND_WS="$T/ws0" bash "$AL" start --repo "$REPO" --pr "$PR" --head "$HEAD_A" \
        --subject "$SUBJ" --stand-report "$FX/rep.json" > "$FX/a3" 2>&1; rc=$?
    ok args "--stand-report без --stand-expect — код 2" eval '[ "$rc" -eq 2 ]'
    ok args ".state не заведён" eval '! ls "$FX"/run/*.state >/dev/null 2>&1'
    ok args "ни один демон не отсоединён" eval '! ls "$FX"/run/*.pid >/dev/null 2>&1'
    reap
}
s_detach() {
    local t0 dt out pid st rc sid_me sid_d
    new_fx detach; echo 3 > "$FX/ci-read.sh.seq"
    export AL_FX="$FX"
    t0=$(date +%s)
    out="$(AUTOLAND_GH="$T/gh" AUTOLAND_GATES="$T/gates" AUTOLAND_DIR="$FX/run" AUTOLAND_WS="$T/ws0" AUTOLAND_CLONES="" \
        CI_STATE_DIR="$FX/cs" AUTOLAND_INTERIM_LOCK="$T/interim.lock" bash "$AL" start --repo "$REPO" --pr "$PR" --head "$HEAD_A" \
        --subject "$SUBJ" --poll 1 --timeout 60)"; rc=$?
    dt=$(( $(date +%s) - t0 ))
    pid="$(awk -F'\t' '$1 == "pid" {print $2}' <<< "$out")"; st="$(awk -F'\t' '$1 == "state" {print $2}' <<< "$out")"
    [[ "$pid" =~ ^[0-9]+$ ]] && PIDS+=("$pid")
    ST="$(head -n1 "$st" 2>/dev/null)"; RC=$rc
    ok detach "start — код 0 за $dt с (< 6)" eval '[ "$rc" -eq 0 ] && [ "$dt" -lt 6 ]'
    ok detach "start печатает pid, журнал и state" eval '[[ "$pid" =~ ^[0-9]+$ ]] && grep -qP "^журнал\t" <<< "$out" && [ -f "$st" ]'
    ok detach "демон жив после возврата start" kill -0 "$pid"
    sid_me="$(ps -o sid= -p $$ | tr -d ' ')"; sid_d="$(ps -o sid= -p "$pid" 2>/dev/null | tr -d ' ')"
    ok detach "демон в своём сеансе ($sid_d ≠ $sid_me)" eval '[ -n "$sid_d" ] && [ "$sid_d" != "$sid_me" ]'
    sleep 2
    ok detach "status идущего — код 3" eval 'bash "$AL" status "$st" >/dev/null; [ $? -eq 3 ]'
    AUTOLAND_DIR="$FX/run" AUTOLAND_WS="$T/ws0" bash "$AL" start --repo "$REPO" --pr "$PR" --head "$HEAD_A" \
        --subject "$SUBJ" > "$FX/second" 2>&1; rc=$?
    ok detach "второй start того же PR — код 3 (замок)" eval '[ "$rc" -eq 3 ] && grep -q "уже ведёт" "$FX/second"'
    kill -TERM "$pid" 2>/dev/null
    for _ in $(seq 1 50); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
    ST="$(head -n1 "$st" 2>/dev/null)"
    ok detach "TERM — исход void «остановлен сигналом TERM»" eval 'st_is void && st_has "сигналом TERM"'
    ok detach "status остановленного — код 2" eval 'bash "$AL" status "$st" >/dev/null; [ $? -eq 2 ]'
    ok detach "копия демона в каталоге состояния снята" eval '! ls "$FX"/run/*.autoland.sh >/dev/null 2>&1'
    printf 'running ожидание CI\n' > "$FX/dead.state"; echo 999999999 > "$FX/dead.pid"
    ok detach "running без живого демона — status 2" eval 'bash "$AL" status "$FX/dead.state" >/dev/null; [ $? -eq 2 ]'
    unset AL_FX
}
mk_ws_sandbox() {  # <каталог> <с метками рецепта: 1|0> — origin/main несёт scripts/ с двойниками
    local d="$1" g
    git init -q --bare -b main "$d/origin.git"
    git clone -q "$d/origin.git" "$d/ws" 2>/dev/null
    git -C "$d/ws" symbolic-ref HEAD refs/heads/main
    mkdir -p "$d/ws/scripts"
    for g in ci-read.sh merge-readiness.sh branch-audit.sh; do cp "$T/gates/gate" "$d/ws/scripts/$g"; done
    { echo '#!/usr/bin/env bash'
      if [ "$2" = 1 ]; then sed -n '/^# >>> рецепт ЗАПУСК$/,/^# <<< рецепт ЗАПУСК$/p' "$LP_REAL"; fi
      sed 1d "$T/gates/gate"; } > "$d/ws/scripts/landing-precheck.sh"
    git -C "$d/ws" add -A && sandbox_run git -C "$d/ws" commit -qm base && git -C "$d/ws" push -q origin main
}
s_recipe() {
    new_fx recipe; mk_ws_sandbox "$FX/sb" 1
    GATES="" WS0="$FX/sb/ws" run_al; GATES=""; unset GATES WS0
    ok recipe "гейты рецептом «ЗАПУСК» из origin/main — merged" eval '[ "$RC" -eq 0 ] && st_is merged'
    ok recipe "все три гейта званы из архива origin/main" eval 'gate_called ci-read.sh && gate_called merge-readiness.sh && gate_called landing-precheck.sh'
    new_fx recipe-cut; mk_ws_sandbox "$FX/sb" 0
    GATES="" WS0="$FX/sb/ws" run_al --void-limit 2; unset GATES WS0
    ok recipe-cut "меток рецепта нет — void «рецепт не вырезан», вливания нет" eval 'st_is void && st_has "рецепт не вырезан" && not_merge_called'
}
mk_git() {  # песочница: origin, клон с веткой задачи, копия ветки; G, HEAD_P
    G="$FX/git"; mkdir -p "$G"
    git init -q --bare -b main "$G/origin.git"
    git clone -q "$G/origin.git" "$G/clone" 2>/dev/null
    git -C "$G/clone" symbolic-ref HEAD refs/heads/main
    echo base > "$G/clone/f"; git -C "$G/clone" add f; sandbox_run git -C "$G/clone" commit -qm base; git -C "$G/clone" push -q origin main
    git -C "$G/clone" checkout -qb 4000-probe; echo task > "$G/clone/g"; git -C "$G/clone" add g
    sandbox_run git -C "$G/clone" commit -qm '#4000 предмет'; git -C "$G/clone" push -q origin 4000-probe
    HEAD_P="$(git -C "$G/clone" rev-parse HEAD)"; git -C "$G/clone" checkout -q main
    git -C "$G/clone" worktree add -q "$G/wt" 4000-probe
    git clone -q "$G/origin.git" "$G/merger" 2>/dev/null
    { printf 'set -e; m=%q; export HOME=%q XDG_CONFIG_HOME=%q\n' "$G/merger" "$SANDBOX_GIT_HOME" "$SANDBOX_GIT_HOME/.config"
      echo 'git -C "$m" fetch -q origin; git -C "$m" checkout -q main; git -C "$m" reset -q --hard origin/main'
      echo 'git -C "$m" merge -q --no-ff origin/4000-probe -m "#4000 merge #4242: проба"'
      echo 'git -C "$m" push -q origin main'
      case "${1:-}" in
        keep-remote) ;;
        origin-ahead) echo 'git -C "$m" checkout -q -b ahead origin/4000-probe; echo ahead > "$m/ahead"; git -C "$m" add ahead'
                      echo 'git -C "$m" commit -qm "#4000 после вливания"; git -C "$m" push -q origin HEAD:4000-probe' ;;
        *) echo 'git -C "$m" push -q origin --delete 4000-probe' ;;
      esac; } > "$FX/merged.hook"
    [ "${1:-}" != not-in-base ] || : > "$FX/merged.hook"   # хостинг сказал merged, в базе коммита нет
    pull "$HEAD_P" open false; RUN_HEAD="$HEAD_P"; CLONES="$G/clone"
}
has_branch() { git -C "$G/clone" rev-parse -q --verify refs/heads/4000-probe >/dev/null; }
remote_empty() { [ -z "$(git -C "$G/clone" ls-remote --heads origin refs/heads/4000-probe)" ]; }
s_prune() {
    new_fx prune; mk_git; run_al
    ok prune "merged, снятие без остатка" eval '[ "$RC" -eq 0 ] && st_is merged && st_has "оставлено 0"'
    ok prune "ветка снята в клоне" eval '! has_branch'
    ok prune "чистая копия снята" eval '[ ! -d "$G/wt" ]'
    ok prune "ветки на origin нет" remote_empty
    ok prune "перепись branch-audit до и после" eval '[ "$(grep -c "^branch-audit.sh " "$FX/calls")" -eq 2 ]'
}
s_prune_dirty() {
    new_fx prune-dirty; mk_git; echo x > "$G/wt/untracked"; run_al
    ok prune-dirty "merged, копия оставлена с причиной" eval 'st_is merged && st_has "оставлено 1" && st_has "копия"'
    ok prune-dirty "грязная копия и ветка на месте" eval '[ -f "$G/wt/untracked" ] && has_branch'
}
s_prune_ahead() {
    new_fx prune-ahead; mk_git
    echo more > "$G/wt/h"; git -C "$G/wt" add h; sandbox_run git -C "$G/wt" commit -qm '#4000 ещё'
    run_al
    ok prune-ahead "merged, местная голова впереди — оставлено" eval 'st_is merged && st_has "не равна и не предок"'
    ok prune-ahead "ветка и копия на месте" eval 'has_branch && [ -d "$G/wt" ]'
}
s_prune_origin_ahead() {
    new_fx prune-origin-ahead; mk_git origin-ahead; run_al
    ok prune-origin-ahead "merged, origin-ветка ушла вперёд — оставлена с причиной" eval 'st_is merged && st_has "сдвинулась после вливания"'
    ok prune-origin-ahead "ветка на origin на месте" eval '! remote_empty'
}
s_prune_not_in_base() {
    new_fx prune-not-in-base; mk_git not-in-base; run_al
    ok prune-not-in-base "merged по хостингу, коммита в базе нет — ничего не снято" eval 'st_is merged && st_has "снято 0" && st_has "не предок origin/main"'
    ok prune-not-in-base "ветка, копия и origin-ветка на месте" eval 'has_branch && [ -d "$G/wt" ] && ! remote_empty'
}
s_prune_remote() {
    new_fx prune-remote; mk_git keep-remote; run_al
    ok prune-remote "ветку на origin демон снял сам" eval 'st_is merged && remote_empty && st_has "origin/4000-probe"'
}
guard_rc() {  # <команда> — код стража
    python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"agent_type":"git-operator"}))' "$1" \
        | python3 "$GUARD" >/dev/null 2>&1
    echo $?
}
s_status() {
    local f="$T/status.$RANDOM" w c
    new_fx status
    for w in "stale-base 4" "head-moved 5" "timeout 6" "merged 0" "red 1" "void 2"; do
        printf '%s подробность\n' "${w% *}" > "$f.state"
        bash "$AL" status "$f.state" > /dev/null; c=$?
        ST="${w% *}"; RC=$c
        ok status "status «${w% *}» — код ${w#* }" eval '[ "$c" -eq "${w#* }" ]'
    done
    printf 'новое-слово x\n' > "$f.state"; bash "$AL" status "$f.state" > /dev/null; c=$?; ST="новое-слово"; RC=$c
    ok status "исход не из перечня — код 2" eval '[ "$c" -eq 2 ]'
}
s_empty_code() {
    new_fx empty-code; echo 1 > "$FX/landing-precheck.sh.seq"
    printf 'REASON\t\tпричина без кода\n' > "$FX/landing-precheck.sh.1.out"
    run_al
    ok empty-code "пустой код без --allow — red, вливания нет" eval '[ "$RC" -eq 1 ] && st_is red && st_has "причина без кода" && not_merge_called'
    new_fx empty-code-allow; echo 1 > "$FX/landing-precheck.sh.seq"
    printf 'REASON\t\tпричина без кода\n' > "$FX/landing-precheck.sh.1.out"
    run_al --allow STAND-REPORT
    ok empty-code "пустой код при непустом --allow — red, вливания нет" eval '[ "$RC" -eq 1 ] && st_is red && not_merge_called'
}
s_lp_head() {
    new_fx lp-head; printf '%s\n' "$HEAD_B" > "$FX/lp.head"; run_al
    ok lp-head "landing-precheck судил другую голову — head-moved, вливания нет" eval '[ "$RC" -eq 5 ] && st_is head-moved && st_has "судил landing-precheck" && not_merge_called'
    new_fx lp-nohead; : > "$FX/lp.nohead"; run_al --void-limit 2 --timeout 6
    ok lp-head "landing-precheck без строки судимой головы — void, вливания нет" eval '[ "$RC" -eq 2 ] && st_is void && st_has "не напечатал судимую голову" && not_merge_called'
}
s_census() {  # перепись и снятие судят СВОЁ: иной порядок доводов виден, чужое — нет
    local own foreign c0 c1
    ST="перепись процессов"; RC=-
    mkdir -p "$T/census/run"
    c0="$(probe_procs)"
    ( exec -a "autoland.sh run --head $HEAD_A --repo $REPO --pr $PR" sleep 60 ) & own=$!; PIDS+=("$own")
    env -u AUTOLAND_PROBE_ID bash -c "exec -a 'autoland.sh run --repo $REPO --pr $PR --head $HEAD_A' sleep 60" & foreign=$!
    FOREIGN+=("$foreign")
    for _ in 1 2 3 4 5 6 7 8 9 10; do grep -qF -- "--pr $PR" "/proc/$own/cmdline" 2>/dev/null \
        && grep -qF -- "--pr $PR" "/proc/$foreign/cmdline" 2>/dev/null && break; sleep 0.1; done
    c1="$(probe_procs)"
    ok census "свой процесс с иным порядком доводов виден переписи ($c0 → $c1)" eval '[ "$c1" -eq $((c0 + 1)) ]'
    echo "$foreign" > "$T/census/run/stale.pid"   # чужой pid в .pid под $T — как после переиспользования
    reap
    sleep 0.3
    ok census "reap снял свой процесс" eval '! kill -0 "$own" 2>/dev/null'
    ok census "reap не тронул чужой процесс с «--pr $PR --head» в доводах" kill -0 "$foreign"
    ok census "чужой процесс переписью пробы не считается" eval '[ "$(probe_procs)" -eq "$c0" ]'
    kill "$foreign" 2>/dev/null; rm -f "$T/census/run/stale.pid"
}
s_guard() {
    local c1 c2 c3
    c1="$(guard_rc "bash scripts/autoland/autoland.sh start --repo $REPO --pr $PR --head $HEAD_A --subject '$SUBJ'")"
    c2="$(guard_rc "bash scripts/autoland/autoland.sh status tmp/autoland/x.state")"
    c3="$(guard_rc "until bash scripts/autoland/autoland.sh status tmp/autoland/x.state; do sleep 30; done")"
    ST="start $c1, status $c2, цикл $c3"; RC=-
    ok guard "страж пропускает start (0)" eval '[ "$c1" = 0 ]'
    ok guard "страж пропускает status (0)" eval '[ "$c2" = 0 ]'
    ok guard "страж отказывает циклу ожидания агентом (2)" eval '[ "$c3" = 2 ]'
}
s_static() {
    local code; code="$(grep -v '^[[:space:]]*#' "$AL")"
    ST="статика"; RC=-
    ok static "нет форсирующих флагов и обхода хуков" eval '! grep -qE -- "(^|[[:space:]])(--force|--force-with-lease|--admin|--no-verify|--auto|--squash|--rebase)([[:space:]]|$|\")" <<< "$code"'
    ok static "git push без -f" eval '! grep -qE -- "push[^|;]*[[:space:]]-f([[:space:]]|$)" <<< "$code"'
    ok static "базу не догоняет: нет git merge/rebase/pull" eval '! grep -qE -- "git( -C \"[^\"]*\")? (merge|rebase|pull)([[:space:]]|$)" <<< "$code"'
    ok static "gh api только GET" eval '! grep -E -- "GH\" api" <<< "$code" | grep -qE -- "(-X|--method|[[:space:]]-[fF][[:space:]])"' 
}

ALL=(s_green s_red s_moved_start s_moved_gates s_moved_merge s_allow_ok s_allow_bad s_stale s_mr_red s_timeout
     s_void s_void_twin s_ratelimit s_pr_unread s_draft s_closed s_already s_fifo s_fifo_nowriter s_args s_detach s_recipe
     s_prune s_prune_dirty s_prune_ahead s_prune_remote s_prune_origin_ahead s_prune_not_in_base
     s_status s_empty_code s_lp_head s_census s_guard s_static)

AL="$AL_REAL"
echo "== контроль: сцен ${#ALL[@]}"
for s in "${ALL[@]}"; do before=$fails; "$s"; [ "$fails" -ne "$before" ] || echo "  [ok] ${s#s_}"; done
control_fails=$fails
echo "== контроль: провалов $control_fails"

# ── мутанты: <имя> <сцены через запятую> <было> <стало> ───────────────────────
mutants=0; survived=0; voidm=0
mutant() {
    local name="$1" scenes="$2" from="$3" to="$4" m="$T/mut.$RANDOM.sh" s
    python3 - "$AL_REAL" "$m" "$from" "$to" <<'PY' || { echo "  [VOID] мутант $name: правка не легла в текст"; voidm=$((voidm + 1)); return; }
import sys
src, dst, a, b = sys.argv[1:5]
t = open(src, encoding="utf-8").read()
if t.count(a) != 1:
    sys.exit(1)
open(dst, "w", encoding="utf-8").write(t.replace(a, b))
PY
    mutants=$((mutants + 1))
    local saved=$fails
    AL="$m"
    IFS=, read -ra list <<< "$scenes"
    : > "$T/mut.out"
    for s in "${list[@]}"; do "$s" >> "$T/mut.out"; done
    AL="$AL_REAL"
    if [ "$fails" -gt "$saved" ]; then echo "  [убит] $name — $(grep -m1 -F '[FAIL]' "$T/mut.out" | sed 's/^ *\[FAIL\] //' | cut -c1-200)"
    else echo "  [ВЫЖИЛ] $name — сцены ${scenes} зелёные на дефекте"; survived=$((survived + 1)); fi
    fails=$saved
}
echo "== мутанты"
mutant match-head-dropped s_green ' --match-head-commit "$HEAD"' ''
mutant admin-added s_green,s_static '-R "$REPO" --merge --match-head-commit' '-R "$REPO" --merge --admin --match-head-commit'
mutant delete-branch-dropped s_green ' --delete-branch >' ' >'
mutant allow-all s_allow_bad 'index(allow, "," $2 ",") == 0' '0'
mutant head-check-before-merge-dropped s_moved_gates '[ "$PR_HEAD" = "$HEAD" ] || finish head-moved "$HEAD $PR_HEAD"  # голова перед вливанием' ':'
mutant stale-as-wait s_stale '4) finish stale-base' '4) wait_change; continue ;; 44) finish stale-base'
mutant red-as-wait s_red '1) finish red "ci-read' '1) wait_change; continue ;; 11) finish red "ci-read'
mutant void-limit-dropped s_void,s_pr_unread '[ "${VOIDS[$k]}" -lt "$VOID_LIMIT" ] ||' 'true ||'
mutant ci-read-without-head s_green '--head "$HEAD" --from-state' '--from-state'
mutant prune-ahead-predicate-dropped s_prune_ahead 'if ! { [ "$lh" = "$HEAD" ] || git -C "$c" merge-base --is-ancestor "$lh" "$HEAD" 2>/dev/null; }; then' 'if false; then'
mutant closed-as-open s_closed '[ "$PR_STATE" = open ] ||' 'true ||'
mutant subject-unchecked s_args '[[ "$SUBJECT" =~ ^#[0-9]+\ merge\ #${PR}:\ [^[:space:]] ]]' 'true'
mutant fifo-dropped s_fifo 'if [ -d "$CI_STATE/wait" ]' 'if false'
mutant empty-code-allowed s_empty_code '$2 == "" || index(allow' 'index(allow'
mutant lp-head-unchecked s_lp_head 'elif [ "$lph" != "${HEAD:0:12}" ]; then' 'elif false; then'
mutant lp-nohead-ignored s_lp_head 'if [ -z "$lph" ]; then' 'if false; then'
mutant prune-origin-ahead-dropped s_prune_origin_ahead 'if [ "$rh" = "$HEAD" ] || git -C "$c" merge-base --is-ancestor "$rh" "$HEAD" 2>/dev/null; then' 'if true; then'
mutant prune-base-ancestor-dropped s_prune_not_in_base 'if ! git -C "$c" merge-base --is-ancestor "$HEAD" "origin/$base" 2>/dev/null; then' 'if false; then'
mutant status-stale-as-merged s_status 'stale-base) exit 4 ;;' 'stale-base) exit 0 ;;'
mutant status-moved-as-merged s_status 'head-moved) exit 5 ;;' 'head-moved) exit 0 ;;'
mutant status-timeout-as-merged s_status 'timeout) exit 6 ;;' 'timeout) exit 0 ;;'
mutant fifo-wait-without-timeout s_fifo_nowriter 'timeout "$t" head -n1 "$fifo"' 'head -n1 "$fifo"'
mutant fifo-wait-dropped s_fifo_nowriter 'timeout "$t" head -n1 "$fifo" > "$W/fifo.line" 2>/dev/null & BG=$!; wait "$BG"; BG=""' 'true'
mutant cache-is-real s_fifo 'CI_STATE="${CI_STATE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/kacho-ci-state}"' 'CI_STATE="${XDG_CACHE_HOME:-$HOME/.cache}/kacho-ci-state"'
mutant ratelimit-as-void s_ratelimit "if grep -qP '^REASON\\tRATE-LIMIT\\t'" 'if false'

reap
for _ in 1 2 3 4 5 6 7 8 9 10; do [ "$(probe_procs)" -eq 0 ] && break; sleep 0.3; done
cs_after="$(real_cs_files)"; procs_after="$(probe_procs)"
echo "CENSUS	кэш машины $REAL_CS: файлов пробы (*__${PR}.*) до $CS_BEFORE, после $cs_after; процессов пробы после $procs_after"
residue=0
if ! [[ "$CS_BEFORE$cs_after" =~ ^[0-9]+$ ]]; then
    echo "VOID	кэш машины $REAL_CS прочитан не весь: $(head -c 200 "$T/cs-find.err" | tr '\n' ' ') — «следов 0» не установлено"
    exit 2
fi
[ "$cs_after" -le "$CS_BEFORE" ] || { echo "  [FAIL] след: проба завела файлы в кэше машины $REAL_CS"; residue=1; }
[ "$procs_after" -eq 0 ] || { echo "  [FAIL] след: живых демонов пробы $procs_after"; residue=1; }
echo "== итог: сцен ${#ALL[@]}, провалов контроля $control_fails; мутантов $mutants, выжило $survived, не легло $voidm; следов $residue"
[ "$voidm" -eq 0 ] || exit 2
[ "$control_fails" -eq 0 ] && [ "$survived" -eq 0 ] && [ "$residue" -eq 0 ] || exit 1
exit 0
