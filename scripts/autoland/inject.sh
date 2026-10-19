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
#                  ветку на origin хостинг не снял — демон снимает её сам; prune-busy (ws#1244 L5):
#                  в чистой копии идёт процесс (cwd внутри) либо открыт её файл — копия и ветка
#                  на месте, в .state «оставлено: процессы <pid>»; близнец — prune; exe (ws#1250):
#                  процесс исполняет файл копии при cwd вне её — оставлена; prune-busy-glob: копия
#                  «w[1]» с процессом внутри оставлена, процесс в чужом «w1» её не держит (шаблон);
#   empty-code   — landing-precheck 1 с причиной БЕЗ кода (REASON<TAB><TAB>текст) — red и без
#                  --allow, и с непустым --allow;
#   lp-head      — landing-precheck судил другую голову (его CENSUS) → head-moved; строки
#                  судимой головы нет → void;
#   prune-origin-ahead — ветка на origin ушла вперёд после вливания → не снимается;
#   prune-not-in-base  — хостинг сказал merged, а влитой головы в базе нет → ничего не снято;
#   ff           — PR в main воркспейса влит: голова основного клона равна origin/main,
#                  локальная правка вне входящих и неотслеживаемый файл целы (ws#1200);
#                  ff-overlap: локальная правка пересекает входящий файл — отказ ff с
#                  именем файла в журнале и исходе, исход merged, голова и правка на месте;
#                  ff-worktree: AUTOLAND_WS — копия, не основной клон — не догоняется;
#                  ff-foreign: origin клона — другой репозиторий — клон не тронут;
#                  ff-hang: сеть fetch висит — merged и «ff отказ — fetch …» в пределе;
#                  ff-epic: запрос в ветку эпика, origin/main впереди — клон не тронут;
#   lag          — main-clone-lag.sh: отставания нет — молчит (0); на N — строка с N (1),
#                  из копии судится основной клон, не клон — «не установлено» (2); хук
#                  SessionStart (session-memcap.sh --hook) несёт строку, после догона — нет;
#                  хук — КОПИЯ рядом с текущей (мутируемой) main-clone-lag.sh;
#   lag-nofetch  — fetch не прошёл: известное отставание 0 — код 2, больше 0 — код 1 с
#                  «fetch не прошёл»; lag-hang: сеть висит — хук укладывается в бюджет
#                  SessionStart из settings.json и несёт «не установлено»;
#   lag-own      — main-clone-lag.sh --own <выписка> -- <пути> (ws#1228): ствол впереди по пути —
#                  TOOLING-LAG с числом и путём (1); путь не тронут — молчит; копия на origin/main
#                  при отставшем основном клоне — судится копия; «--» без путей — 2;
#   start-stale  — дерево скрипта отстаёт по scripts/autoland/ — start 4, демона нет; близнец:
#                  ствол впереди лишь вне оснастки — start 0; fetch не прошёл при нуле — 4;
#   head-sync    — площадка два чтения отдаёт прежнюю голову — повтор, merged (ws#1227); близнец:
#                  голова иная всё время — head-moved по окну; ушла ПОСЛЕ совпадения — сразу;
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
# ожидание FIFO без timeout, без ожидания вовсе, кэш — настоящий (CI_STATE_DIR не читается),
# шаг ff выключен, отказ ff как red, пересечение не названо, копия как основной клон,
# чужой репозиторий как свой, fetch догона без предела, база запроса не судится; у
# main-clone-lag.sh — ноль говорит, число не печатается, копия как клон, «не
# установлено» молчит, неудачный fetch при нуле молчит и при числе не назван, fetch без предела,
# --own судит основной клон, пути не судятся; у start — сверки копии нет; окно головы снято,
# совпадение не запоминается, окно без предела.
# Обход git заперт GIT_CEILING_DIRECTORIES над $T: проба зелена и при TMPDIR внутри клона.
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
LAG_REAL="$(cd "$HERE/.." && pwd)/main-clone-lag.sh"; LAG="$LAG_REAL"   # нет файла — сцена lag красная, не VOID
MEMCAP="$(cd "$HERE/.." && pwd)/session-memcap.sh"
[ -r "$LP_REAL" ] || { echo "VOID: нет $LP_REAL (метки рецепта «ЗАПУСК»)" >&2; exit 2; }

T="$(mktemp -d "${TMPDIR:-/tmp}/autoland-inject.XXXXXX")" || exit 2
# Обход git не выходит из песочницы: при TMPDIR внутри клона каталог «не клон» иначе
# нашёл бы настоящий клон и сделал бы в нём fetch (ws#1200, круг 1).
GIT_CEILING_DIRECTORIES="$(dirname "$T")"; export GIT_CEILING_DIRECTORIES
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
      repos/*/pulls/*)
        # pull.lag «<k> <голова>» — первые k чтений отдают прежнюю голову (площадка ещё не видит push)
        if [ -s "$FX/pull.lag" ]; then
          read -r k old < "$FX/pull.lag"; i=$(( $(cat "$FX/pull.lag.n" 2>/dev/null || echo 0) + 1 )); echo "$i" > "$FX/pull.lag.n"
          if [ "$i" -le "$k" ]; then jq --arg h "$old" '.head.sha = $h' "$FX/pull.json"; exit 0; fi
        fi
        cat "$FX/pull.json" ;;
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
        --arg base "${PULL_BASE:-main}" \
        '{state: $s, merged: $m, merge_commit_sha: (if $m then $ms else null end), draft: false,
          head: {sha: $h, ref: $ref}, base: {ref: $base, sha: $b}}' > "$FX/pull.json"
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
        AUTOLAND_HEAD_SYNC="${HEAD_SYNC:-0}" AUTOLAND_HEAD_SYNC_POLL=1 \
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
    mk_tooling_tree "$FX/tt"
    out="$(AUTOLAND_GH="$T/gh" AUTOLAND_GATES="$T/gates" AUTOLAND_DIR="$FX/run" AUTOLAND_WS="$T/ws0" AUTOLAND_CLONES="" \
        AUTOLAND_TOOLING_TREE="$FX/tt/ws" AUTOLAND_LAG="$LAG" \
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
# ── копия демона сверяется со стволом при start (ws#1228) ─────────────────────
mk_tooling_tree() {  # <каталог> — голый origin, выписка main (ws) и клон для толчков ствола (up)
    local d="$1"; mkdir -p "$d"
    git init -q --bare -b main "$d/origin.git"
    git clone -q "$d/origin.git" "$d/ws" 2>/dev/null; git -C "$d/ws" symbolic-ref HEAD refs/heads/main
    mkdir -p "$d/ws/scripts/autoland" "$d/ws/docs"
    echo a > "$d/ws/scripts/autoland/autoland.sh"; echo a > "$d/ws/scripts/main-clone-lag.sh"; echo a > "$d/ws/docs/x.md"
    git -C "$d/ws" add -A; sandbox_run git -C "$d/ws" commit -qm base; git -C "$d/ws" push -q origin main
    git clone -q "$d/origin.git" "$d/up" 2>/dev/null
}
tt_push() {  # <каталог дерева> <путь> — коммит в origin/main, трогающий путь
    echo "$RANDOM" >> "$1/up/$2"; git -C "$1/up" add -A; sandbox_run git -C "$1/up" commit -qm "$2"; git -C "$1/up" push -q origin HEAD:main
}
start_tt() {  # <дерево> <файл вывода> — start с этим деревом оснастки; код в RC
    AL_FX="$FX" AUTOLAND_GH="$T/gh" AUTOLAND_GATES="$T/gates" AUTOLAND_DIR="$FX/run" AUTOLAND_WS="$T/ws0" AUTOLAND_CLONES="" \
        AUTOLAND_TOOLING_TREE="$1" AUTOLAND_LAG="$LAG" CI_STATE_DIR="$FX/cs" AUTOLAND_INTERIM_LOCK="$T/interim.lock" \
        bash "$AL" start --repo "$REPO" --pr "$PR" --head "$HEAD_A" --subject "$SUBJ" --poll 1 --timeout 30 > "$2" 2>&1
    RC=$?
    local pid; pid="$(awk -F'\t' '$1 == "pid" {print $2}' "$2")"; [[ "$pid" =~ ^[0-9]+$ ]] && PIDS+=("$pid")
}
s_start_stale() {
    new_fx start-stale; echo 3 > "$FX/ci-read.sh.seq"; mk_tooling_tree "$FX/tt"
    tt_push "$FX/tt" scripts/autoland/autoland.sh
    start_tt "$FX/tt/ws" "$FX/s1"; ST="$(head -c 300 "$FX/s1")"
    ok start-stale "дерево скрипта отстаёт по scripts/autoland/ на 1 — код 4, число и пути названы" \
        eval '[ "$RC" -eq 4 ] && grep -qF "отстаёт от origin/main на 1 коммит(ов) по путям scripts/autoland/ scripts/main-clone-lag.sh" "$FX/s1"'
    ok start-stale "демон не запущен: ни .state, ни .pid, ни копии" eval '! ls "$FX"/run/*.state "$FX"/run/*.pid "$FX"/run/*.autoland.sh >/dev/null 2>&1'
    git -C "$FX/tt/ws" merge -q --ff-only origin/main; tt_push "$FX/tt" docs/x.md
    start_tt "$FX/tt/ws" "$FX/s2"; ST="$(head -c 300 "$FX/s2")"
    ok start-stale "близнец: ствол впереди лишь вне оснастки (docs/) — start код 0, демон идёт" eval '[ "$RC" -eq 0 ] && grep -q "^pid" "$FX/s2"'
    reap; rm -rf "$FX/run"
    git -C "$FX/tt/ws" merge -q --ff-only origin/main; git -C "$FX/tt/ws" remote set-url origin "$FX/tt/absent.git"
    start_tt "$FX/tt/ws" "$FX/s3"; ST="$(head -c 300 "$FX/s3")"
    ok start-stale "fetch не прошёл при нуле — «не установлено», код 4, демон не запущен" \
        eval '[ "$RC" -eq 4 ] && grep -qF "не установлено" "$FX/s3" && ! ls "$FX"/run/*.pid >/dev/null 2>&1'
    reap
}
s_head_sync() {
    local t0 dt
    new_fx head-sync; printf '2 %s\n' "$HEAD_B" > "$FX/pull.lag"
    t0=$(date +%s); HEAD_SYNC=20 run_al; dt=$(( $(date +%s) - t0 ))
    ok head-sync "площадка два чтения отдаёт прежнюю голову — повтор, затем merged, код 0" eval '[ "$RC" -eq 0 ] && st_is merged'
    ok head-sync "повтор назван в журнале демона" eval 'grep -qF "площадка ещё не видит отправку" "$FX"/run/*.log "$FX/out" 2>/dev/null'
    new_fx head-sync-twin "$HEAD_B"; RUN_HEAD="$HEAD_A"
    t0=$(date +%s); RUN_LIMIT=25 HEAD_SYNC=3 run_al; dt=$(( $(date +%s) - t0 ))
    ok head-sync "близнец: голова иная всё время — head-moved, код 5, за предел окна ($dt с, окно 3)" \
        eval '[ "$RC" -eq 5 ] && [ "$ST" = "head-moved $HEAD_A $HEAD_B" ] && [ "$dt" -ge 2 ] && [ "$dt" -lt 15 ]'
    new_fx head-seen; echo 3 > "$FX/ci-read.sh.seq"; move_head_hook "$FX/ci-read.sh.hook"
    t0=$(date +%s); HEAD_SYNC=20 run_al --timeout 60; dt=$(( $(date +%s) - t0 ))
    ok head-sync "голова ушла ПОСЛЕ совпадения — head-moved сразу ($dt с < 10), окно не ждётся" \
        eval '[ "$RC" -eq 5 ] && st_is head-moved && [ "$dt" -lt 10 ]'
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
s_prune_busy() {  # ws#1244 L5: 2026-10-18 снята копия, где шли 6 процессов integration (cwd внутри)
    local bp bf
    new_fx prune-busy; mk_git
    (cd "$G/wt" && exec sleep 60) & bp=$!
    run_al
    ok prune-busy "merged, копия с процессом (cwd внутри) оставлена, pid назван" eval 'st_is merged && st_has "оставлено: процессы $bp"'
    ok prune-busy "копия и ветка на месте" eval '[ -d "$G/wt" ] && has_branch'
    kill "$bp" 2>/dev/null; wait "$bp" 2>/dev/null
    new_fx prune-busy-fd; mk_git
    ( exec 7< "$G/wt/g"; exec sleep 60 ) & bf=$!
    run_al
    ok prune-busy-fd "merged, копия с открытым файлом (cwd вне) оставлена, pid назван" eval 'st_is merged && st_has "оставлено: процессы $bf" && [ -d "$G/wt" ]'
    kill "$bf" 2>/dev/null; wait "$bf" 2>/dev/null
    # ws#1250 K4: исполняемый файл из копии при cwd вне её и без открытых файлов в ней.
    local bx _
    new_fx prune-busy-exe; mk_git
    # Копия bash, а не sleep: sleep здесь — многовызовный двоичный файл, под чужим именем он не
    # исполняется. read ждёт на очереди вне копии — exe единственная связь процесса с копией.
    cp "$(command -v bash)" "$G/wt/xs"; mkfifo "$FX/exe.fifo"
    # shellcheck disable=SC2016  # тело -c раскрывает исполняемая копия bash
    (cd / && exec "$G/wt/xs" -c 'read -r -t 60 <> "$0"' "$FX/exe.fifo") < /dev/null > /dev/null 2>&1 & bx=$!
    for _ in $(seq 1 25); do [ "$(readlink "/proc/$bx/exe" 2>/dev/null)" = "$G/wt/xs" ] && break; sleep 0.1; done
    run_al
    ok prune-busy-exe "merged, копия с исполняемым файлом процесса (cwd вне) оставлена, pid назван" eval 'st_is merged && st_has "оставлено: процессы $bx" && [ -d "$G/wt" ]'
    kill "$bx" 2>/dev/null; wait "$bx" 2>/dev/null
}
s_prune_busy_glob() {  # ws#1250 K4: путь копии со знаками шаблона — свой процесс виден, чужой «a1» нет
    local bo bf
    new_fx prune-busy-glob; mk_git
    git -C "$G/clone" worktree move "$G/wt" "$G/w[1]"; mkdir -p "$G/w1"
    (cd "$G/w1" && exec sleep 60) & bf=$!
    run_al
    ok prune-busy-glob "близнец: процесс в чужом каталоге w1 копию w[1] не держит — снята" eval 'st_is merged && [ ! -d "$G/w[1]" ] && ! st_has "процессы $bf"'
    kill "$bf" 2>/dev/null; wait "$bf" 2>/dev/null
    new_fx prune-busy-glob-own; mk_git
    git -C "$G/clone" worktree move "$G/wt" "$G/w[1]"
    (cd "$G/w[1]" && exec sleep 60) & bo=$!
    run_al
    ok prune-busy-glob-own "копия w[1] с процессом внутри оставлена, pid назван" eval 'st_is merged && st_has "оставлено: процессы $bo" && [ -d "$G/w[1]" ]'
    kill "$bo" 2>/dev/null; wait "$bo" 2>/dev/null
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
# ── основной клон воркспейса догоняется после вливания (ws#1200) ──────────────
mk_ws_main() {  # [<имя репозитория origin>] — origin …/PRO-Robotech/<имя>.git, основной клон ws на main; G, OLD_MAIN
    G="$FX/wsm"; local o="$G/PRO-Robotech/${1:-kacho-workspace}.git"
    ORIGIN_DIR="$o"; mkdir -p "$G/PRO-Robotech"
    git init -q --bare -b main "$o"
    git clone -q "$o" "$G/ws" 2>/dev/null; git -C "$G/ws" symbolic-ref HEAD refs/heads/main
    echo base > "$G/ws/incoming.txt"; echo keep > "$G/ws/local.txt"; git -C "$G/ws" add incoming.txt local.txt
    sandbox_run git -C "$G/ws" commit -qm base; git -C "$G/ws" push -q origin main
    git clone -q "$o" "$G/dev" 2>/dev/null; git -C "$G/dev" checkout -qb 4000-probe
    echo task > "$G/dev/incoming.txt"; git -C "$G/dev" add incoming.txt
    sandbox_run git -C "$G/dev" commit -qm '#4000 предмет'; git -C "$G/dev" push -q origin 4000-probe
    HEAD_P="$(git -C "$G/dev" rev-parse HEAD)"; OLD_MAIN="$(git -C "$G/ws" rev-parse HEAD)"
    git clone -q "$o" "$G/merger" 2>/dev/null
    { printf 'set -e; m=%q; export HOME=%q XDG_CONFIG_HOME=%q\n' "$G/merger" "$SANDBOX_GIT_HOME" "$SANDBOX_GIT_HOME/.config"
      echo 'git -C "$m" fetch -q origin; git -C "$m" checkout -q main; git -C "$m" reset -q --hard origin/main'
      echo 'git -C "$m" merge -q --no-ff origin/4000-probe -m "#4000 merge #4242: проба"'
      echo 'git -C "$m" push -q origin main; git -C "$m" push -q origin --delete 4000-probe'; } > "$FX/merged.hook"
    pull "$HEAD_P" open false; RUN_HEAD="$HEAD_P"; CLONES=""
}
origin_main() { git -C "$ORIGIN_DIR" rev-parse main; }
head_of() { git -C "$1" rev-parse HEAD; }
s_ff() {
    new_fx ff; mk_ws_main; echo changed > "$G/ws/local.txt"; echo u > "$G/ws/untracked.txt"
    WS0="$G/ws" run_al; unset WS0
    ok ff "merged, код 0" eval '[ "$RC" -eq 0 ] && st_is merged && st_has "$MSHA"'
    ok ff "после merged голова основного клона равна origin/main" eval '[ "$(origin_main)" != "$OLD_MAIN" ] && [ "$(head_of "$G/ws")" = "$(origin_main)" ]'
    ok ff "исход называет догон «основной клон: <было> → <стало>»" st_has "основной клон: ${OLD_MAIN:0:12} → "
    ok ff "локальная правка вне входящих и неотслеживаемый файл целы" eval '[ "$(cat "$G/ws/local.txt")" = changed ] && [ -f "$G/ws/untracked.txt" ]'
}
s_ff_overlap() {
    new_fx ff-overlap; mk_ws_main; echo mine > "$G/ws/incoming.txt"
    WS0="$G/ws" run_al; unset WS0
    ok ff-overlap "отказ ff исход не портит: merged <sha>, код 0" eval '[ "$RC" -eq 0 ] && st_is merged && st_has "$MSHA"'
    ok ff-overlap "исход называет отказ ff и перечень пересечения" st_has "основной клон: ff отказ — пересекаются с локальной правкой: incoming.txt;"
    ok ff-overlap "журнал демона называет отказ ff и перечень пересечения" grep -qF "основной клон: ff отказ — пересекаются с локальной правкой: incoming.txt;" "$FX/out"
    ok ff-overlap "голова не сдвинута, правка цела, stash пуст" eval '[ "$(head_of "$G/ws")" = "$OLD_MAIN" ] && [ "$(cat "$G/ws/incoming.txt")" = mine ] && [ -z "$(git -C "$G/ws" stash list)" ]'
}
s_ff_worktree() {
    new_fx ff-worktree; mk_ws_main; git -C "$G/ws" worktree add -q --detach "$G/wt" 2>/dev/null
    WS0="$G/wt" run_al; unset WS0
    ok ff-worktree "merged; копия — не основной клон, причина названа" eval '[ "$RC" -eq 0 ] && st_is merged && st_has "не основной клон"'
    ok ff-worktree "ни копия, ни основной клон не сдвинуты" eval '[ "$(head_of "$G/wt")" = "$OLD_MAIN" ] && [ "$(head_of "$G/ws")" = "$OLD_MAIN" ]'
}
s_ff_foreign() {
    new_fx ff-foreign; mk_ws_main kacho
    WS0="$G/ws" run_al; unset WS0
    ok ff-foreign "запрос не в репозиторий клона — merged, клон не тронут" eval '[ "$RC" -eq 0 ] && st_is merged && ! st_has "основной клон" && [ "$(head_of "$G/ws")" = "$OLD_MAIN" ]'
}
HANG_URL="ssh://hang.invalid/PRO-Robotech/kacho-workspace.git"   # с GIT_SSH_COMMAND «sleep N #» — сеть висит
s_ff_hang() {
    local t0 dt
    new_fx ff-hang; mk_ws_main; git -C "$G/ws" remote set-url origin "$HANG_URL"
    export GIT_SSH_COMMAND="sleep 300 #"
    t0=$(date +%s); WS0="$G/ws" RUN_LIMIT=40 run_al; dt=$(( $(date +%s) - t0 )); unset WS0 GIT_SSH_COMMAND
    ok ff-hang "сеть висит — исход merged <sha>, код 0, за $dt с (предел пробы 40)" eval '[ "$RC" -eq 0 ] && st_is merged && st_has "$MSHA"'
    ok ff-hang "исход называет отказ fetch догона" st_has "основной клон: ff отказ — fetch origin main"
    ok ff-hang "голова основного клона не сдвинута" eval '[ "$(head_of "$G/ws")" = "$OLD_MAIN" ]'
}
s_ff_epic() {
    new_fx ff-epic; mk_ws_main; PULL_BASE=1266-epic pull "$HEAD_P" open false
    WS0="$G/ws" run_al; unset WS0
    ok ff-epic "запрос в ветку эпика — merged, origin/main впереди, основной клон не тронут" eval '[ "$RC" -eq 0 ] && st_is merged && ! st_has "основной клон" && [ "$(origin_main)" != "$OLD_MAIN" ] && [ "$(head_of "$G/ws")" = "$OLD_MAIN" ]'
}
hook_copy() {  # копия хука SessionStart рядом с ТЕКУЩЕЙ (возможно мутантом) main-clone-lag.sh → путь session-memcap.sh
    local d="$FX/hook/scripts"; mkdir -p "$d"
    cp "$MEMCAP" "$d/session-memcap.sh"; cp "$HERE/../heavy-slot.sh" "$d/heavy-slot.sh"; cp "$LAG" "$d/main-clone-lag.sh"
    printf 'MemTotal: 62914560 kB\nMemAvailable: 52428800 kB\n' > "$FX/meminfo"
    printf '%s\n' "$d/session-memcap.sh"
}
lag_ctx() {  # вывод хука SessionStart → additionalContext (пусто — хук молчал)
    python3 -c 'import json,sys
t = sys.stdin.read().strip()
print(json.loads(t)["hookSpecificOutput"]["additionalContext"] if t else "")'
}
s_lag() {
    local out rc n ctx hk
    new_fx lag; mk_ws_main; ST="сигнал SessionStart"; RC=-
    out="$(bash "$LAG" "$G/ws" 2>&1)"; rc=$?
    ok lag "отставания нет — молчит, код 0 (код $rc, вывод «$out»)" eval '[ "$rc" -eq 0 ] && [ -z "$out" ]'
    bash "$FX/merged.hook" > /dev/null 2>&1
    n="$(git -C "$ORIGIN_DIR" rev-list --count "$OLD_MAIN..main")"
    out="$(bash "$LAG" "$G/ws" 2>&1)"; rc=$?
    ok lag "отстаёт на $n — строка с числом, код 1 (код $rc)" eval '[ "$rc" -eq 1 ] && [ "$n" -gt 0 ] && grep -qF "отстаёт от origin/main на $n " <<< "$out"'
    git -C "$G/ws" worktree add -q --detach "$G/wt" 2>/dev/null
    out="$(bash "$LAG" "$G/wt" 2>&1)"; rc=$?
    ok lag "из копии судится основной клон (код $rc)" eval '[ "$rc" -eq 1 ] && grep -qF "клон $G/ws " <<< "$out" && ! grep -qF "$G/wt" <<< "$out"'
    mkdir -p "$FX/plain"; out="$(bash "$LAG" "$FX/plain" 2>&1)"; rc=$?
    ok lag "не клон — «не установлено» строкой, код 2 (код $rc)" eval '[ "$rc" -eq 2 ] && grep -qF "не установлено" <<< "$out"'
    hk="$(hook_copy)"
    ctx="$(SESSION_MEMCAP_MEMINFO="$FX/meminfo" CLAUDE_PROJECT_DIR="$G/wt" bash "$hk" --hook 2>/dev/null | lag_ctx)"
    ok lag "хук SessionStart (session-memcap --hook) несёт строку отставания на $n" eval 'grep -qF "MAIN-CLONE-LAG: основной клон $G/ws " <<< "$ctx" && grep -qF "на $n " <<< "$ctx"'
    git -C "$G/ws" merge -q --ff-only origin/main
    ctx="$(SESSION_MEMCAP_MEMINFO="$FX/meminfo" CLAUDE_PROJECT_DIR="$G/wt" bash "$hk" --hook 2>/dev/null | lag_ctx)"
    ok lag "после догона хук строки отставания не несёт" eval '! grep -qF MAIN-CLONE-LAG <<< "$ctx"'
}
s_lag_own() {  # --own и пути (ws#1228): судится выписка каталога, счёт — по путям
    local out rc
    new_fx lag-own; mk_ws_main; ST="--own"; RC=-
    bash "$FX/merged.hook" > /dev/null 2>&1
    out="$(bash "$LAG" --own "$G/ws" -- incoming.txt 2>&1)"; rc=$?
    ok lag-own "ствол впереди по incoming.txt — TOOLING-LAG с числом и путём, код 1 (код $rc)" \
        eval '[ "$rc" -eq 1 ] && grep -qF "TOOLING-LAG: выписка $G/ws (main) отстаёт от origin/main на " <<< "$out" && grep -qF "по путям incoming.txt" <<< "$out"'
    out="$(bash "$LAG" --own "$G/ws" -- scripts/autoland/ 2>&1)"; rc=$?
    ok lag-own "близнец: путь, которого ствол не трогал, — молчит, код 0 (код $rc)" eval '[ "$rc" -eq 0 ] && [ -z "$out" ]'
    git -C "$G/ws" worktree add -q -b 4001-own "$G/wto" origin/main 2>/dev/null
    out="$(bash "$LAG" --own "$G/wto" -- incoming.txt 2>&1)"; rc=$?
    ok lag-own "копия на origin/main при отставшем основном клоне — судится копия, молчит (код $rc)" eval '[ "$rc" -eq 0 ] && [ -z "$out" ]'
    out="$(bash "$LAG" --own "$G/ws" -- 2>&1)"; rc=$?
    ok lag-own "«--» без путей — «не установлено», код 2 (код $rc)" eval '[ "$rc" -eq 2 ] && grep -qF "не установлено" <<< "$out"'
}
s_lag_nofetch() {
    local out rc absent="$FX/absent/PRO-Robotech/kacho-workspace.git"
    new_fx lag-nofetch; mk_ws_main; ST="сигнал при неудачном fetch"; RC=-
    git -C "$G/ws" remote set-url origin "$absent"
    out="$(bash "$LAG" "$G/ws" 2>&1)"; rc=$?
    ok lag-nofetch "fetch не прошёл, известное отставание 0 — «не установлено», код 2 (код $rc)" eval '[ "$rc" -eq 2 ] && grep -qF "MAIN-CLONE-LAG: отставание не установлено" <<< "$out"'
    git -C "$G/ws" remote set-url origin "$ORIGIN_DIR"; bash "$FX/merged.hook" > /dev/null 2>&1; git -C "$G/ws" fetch -q origin
    git -C "$G/ws" remote set-url origin "$absent"
    out="$(bash "$LAG" "$G/ws" 2>&1)"; rc=$?
    ok lag-nofetch "fetch не прошёл, известное отставание > 0 — строка с «fetch не прошёл», код 1 (код $rc)" eval '[ "$rc" -eq 1 ] && grep -qF "отстаёт от origin/main на " <<< "$out" && grep -qF "fetch не прошёл" <<< "$out"'
}
s_lag_hang() {
    local hk t0 dt ctx budget
    new_fx lag-hang; mk_ws_main; ST="хук SessionStart, сеть висит"; RC=-
    budget="$(jq -r '[.hooks.SessionStart[].hooks[] | select(.command | test("session-memcap.sh")) | .timeout] | first // empty' "$HERE/../../.claude/settings.json" 2>/dev/null)"
    git -C "$G/ws" remote set-url origin "$HANG_URL"; hk="$(hook_copy)"
    t0=$(date +%s)
    ctx="$(GIT_SSH_COMMAND="sleep 45 #" SESSION_MEMCAP_MEMINFO="$FX/meminfo" CLAUDE_PROJECT_DIR="$G/ws" timeout 35 bash "$hk" --hook 2>/dev/null | lag_ctx 2>/dev/null)"
    dt=$(( $(date +%s) - t0 ))
    ok lag-hang "сеть висит — хук за $dt с, бюджет SessionStart «${budget:-не прочитан}» с (settings.json), несёт «не установлено»" \
        eval '[[ "$budget" =~ ^[0-9]+$ ]] && [ "$dt" -lt "$budget" ] && grep -qF "MAIN-CLONE-LAG: отставание не установлено" <<< "$ctx"'
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
    ok static "базу не догоняет: нет git rebase/pull, merge — лишь ff основного клона до origin/main" eval '! grep -qP -- "git( -C \"[^\"]*\")? (rebase|pull|merge(?! --ff-only -q origin/main))([[:space:]]|$)" <<< "$code"'
    ok static "gh api только GET" eval '! grep -E -- "GH\" api" <<< "$code" | grep -qE -- "(-X|--method|[[:space:]]-[fF][[:space:]])"' 
}

ALL=(s_green s_red s_moved_start s_moved_gates s_moved_merge s_allow_ok s_allow_bad s_stale s_mr_red s_timeout
     s_void s_void_twin s_ratelimit s_pr_unread s_draft s_closed s_already s_fifo s_fifo_nowriter s_args s_detach s_recipe
     s_prune s_prune_dirty s_prune_ahead s_prune_remote s_prune_origin_ahead s_prune_not_in_base s_prune_busy s_prune_busy_glob
     s_ff s_ff_overlap s_ff_worktree s_ff_foreign s_ff_hang s_ff_epic s_lag s_lag_own s_lag_nofetch s_lag_hang
     s_start_stale s_head_sync
     s_status s_empty_code s_lp_head s_census s_guard s_static)

AL="$AL_REAL"
echo "== контроль: сцен ${#ALL[@]}"
for s in "${ALL[@]}"; do before=$fails; "$s"; [ "$fails" -ne "$before" ] || echo "  [ok] ${s#s_}"; done
control_fails=$fails
echo "== контроль: провалов $control_fails"

# ── мутанты: <имя> <сцены через запятую> <было> <стало> ───────────────────────
mutants=0; survived=0; voidm=0
mutant() {  # … [<исходник: autoland.sh по умолчанию либо main-clone-lag.sh>]
    local name="$1" scenes="$2" from="$3" to="$4" src="${5:-$AL_REAL}" m="$T/mut.$RANDOM.sh" s
    python3 - "$src" "$m" "$from" "$to" <<'PY' || { echo "  [VOID] мутант $name: правка не легла в текст"; voidm=$((voidm + 1)); return; }
import sys
src, dst, a, b = sys.argv[1:5]
t = open(src, encoding="utf-8").read()
if t.count(a) != 1:
    sys.exit(1)
open(dst, "w", encoding="utf-8").write(t.replace(a, b))
PY
    mutants=$((mutants + 1))
    local saved=$fails
    if [ "$src" = "$LAG_REAL" ]; then LAG="$m"; else AL="$m"; fi
    IFS=, read -ra list <<< "$scenes"
    : > "$T/mut.out"
    for s in "${list[@]}"; do "$s" >> "$T/mut.out"; done
    AL="$AL_REAL"; LAG="$LAG_REAL"
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
mutant prune-busy-unchecked s_prune_busy 'busy="$(wt_procs "$wt")"' 'busy=""'
mutant prune-busy-fd-unchecked s_prune_busy 'find /proc/[0-9]*/fd -mindepth 1' 'false /proc/[0-9]*/fd -mindepth 1'
mutant prune-busy-exe-unchecked s_prune_busy 'find /proc/[0-9]*/cwd /proc/[0-9]*/exe -maxdepth 0' 'find /proc/[0-9]*/cwd -maxdepth 0'
mutant prune-busy-glob-unescaped s_prune_busy_glob "e=\"\$(printf '%s' \"\$d\" | sed 's/[][*?\\\\]/\\\\&/g')\"" 'e="$d"'
mutant prune-base-ancestor-dropped s_prune_not_in_base 'if ! git -C "$c" merge-base --is-ancestor "$HEAD" "origin/$base" 2>/dev/null; then' 'if false; then'
mutant status-stale-as-merged s_status 'stale-base) exit 4 ;;' 'stale-base) exit 0 ;;'
mutant status-moved-as-merged s_status 'head-moved) exit 5 ;;' 'head-moved) exit 0 ;;'
mutant status-timeout-as-merged s_status 'timeout) exit 6 ;;' 'timeout) exit 0 ;;'
mutant fifo-wait-without-timeout s_fifo_nowriter 'timeout "$t" head -n1 "$fifo"' 'head -n1 "$fifo"'
mutant fifo-wait-dropped s_fifo_nowriter 'timeout "$t" head -n1 "$fifo" > "$W/fifo.line" 2>/dev/null & BG=$!; wait "$BG"; BG=""' 'true'
mutant cache-is-real s_fifo 'CI_STATE="${CI_STATE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/kacho-ci-state}"' 'CI_STATE="${XDG_CACHE_HOME:-$HOME/.cache}/kacho-ci-state"'
mutant ratelimit-as-void s_ratelimit "if grep -qP '^REASON\\tRATE-LIMIT\\t'" 'if false'
mutant ff-step-dropped s_ff 'prune "$PR_REF" "$PR_BASE"; sync_main_clone' 'prune "$PR_REF" "$PR_BASE"'
mutant ff-refusal-is-red s_ff_overlap 'log "$SYNC"; return 0  # отказ ff' 'finish red "$SYNC"'
mutant ff-overlap-unnamed s_ff_overlap 'пересекаются с локальной правкой: ${both:-—}' 'пересекаются с локальной правкой: —'
mutant ff-main-clone-unchecked s_ff_worktree 'if [ "$common" != "$top/.git" ]; then' 'if false; then'
mutant ff-not-fast-forward s_static 'merge --ff-only -q origin/main >' 'merge -q origin/main >'
mutant ff-repo-unchecked s_ff_foreign '[ "$PR_BASE" = main ] && origin_is_repo "$WS" || return 0' '[ "$PR_BASE" = main ] || return 0'
mutant ff-fetch-unbounded s_ff_hang 'timeout "$FF_FETCH_TIMEOUT" git -C "$WS" fetch' 'git -C "$WS" fetch'
mutant ff-base-unchecked s_ff_epic '[ "$PR_BASE" = main ] && origin_is_repo "$WS" || return 0' 'origin_is_repo "$WS" || return 0'
mutant lag-nofetch-silent s_lag_nofetch 'if [ "$fetched" -eq 0 ] && [ "$n" -eq 0 ]; then' 'if false; then' "$LAG_REAL"
mutant lag-nofetch-unannotated s_lag_nofetch "\"\$([ \"\$fetched\" -eq 1 ] || echo ' (fetch не прошёл — по известному origin/main)')\"" '""' "$LAG_REAL"
mutant lag-fetch-unbounded s_lag_hang 'timeout "${MAIN_CLONE_LAG_FETCH_TIMEOUT:-8}" git' 'git' "$LAG_REAL"
mutant lag-zero-speaks s_lag '[ "$n" -gt 0 ] || exit 0' 'true' "$LAG_REAL"
mutant lag-count-dropped s_lag '"$main" "$br" "$n"' '"$main" "$br" "?"' "$LAG_REAL"
mutant lag-worktree-as-clone s_lag 'rev-parse --path-format=absolute --git-common-dir' 'rev-parse --absolute-git-dir' "$LAG_REAL"
mutant lag-unknown-is-silent s_lag 'unknown() { printf' 'unknown() { exit 0; printf' "$LAG_REAL"
mutant lag-own-judges-main-clone s_lag_own 'main="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)"' 'main="$(dirname "$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir)")"' "$LAG_REAL"
mutant lag-paths-dropped s_lag_own,s_start_stale '${paths[0]+-- "${paths[@]}"}' '' "$LAG_REAL"
mutant start-lag-unchecked s_start_stale 'lag="$(bash "$lag_sh" --own' 'lag="$(true "$lag_sh" --own'
mutant head-sync-dropped s_head_sync '[ "$HEAD_SEEN" = 0 ] && [ $(( $(date +%s) - RUN_T0 )) -lt "$HEAD_SYNC" ]' 'false'
mutant head-seen-ignored s_head_sync '[ "$HEAD_SEEN" = 0 ] && [ $(( $(date +%s)' '[ $(( $(date +%s)'
mutant head-sync-unbounded s_head_sync ' -lt "$HEAD_SYNC" ]; then' ' -ge 0 ]; then' 

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
