#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# inject.sh — доказательство демона состояния и чтения ci-read.sh --from-state
# ИСПОЛНЕНИЕМ (ws#1113). Вход — настоящий: ответы площадки о kacho#3140
# (scripts/ci-read-fixtures/kacho-3140, двойник gh — scripts/ci-read-fixtures/gh-twin.sh)
# и ответ GraphQL той же формы, что отдаёт площадка на запрос демона (замер 2026-10-16,
# PRO-Robotech/kacho). Демон пишет снимок ТЕМ ЖЕ кодом, что в службе: --once с
# --poll-file подменяет только сетевой ответ GraphQL, решатель — живой ci-read.sh.
#
# СЦЕНЫ (каждая меняет ровно один факт против законного близнеца: 5, у сцены 6 — свои):
#   (0) снимок пишется: каталог 0700, файл 0600; вывод снимка и живой вывод
#       совпадают ПОБАЙТНО, коды равны;
#   (1) снимок старше 180 с с зелёным вердиктом, голова на деле идёт → живое
#       чтение: REASON STATE-STALE и код 3 из фикстуры;
#   (2) чужой ключ → живое чтение, REASON STATE-KEY-MISMATCH: (а) демон видел
#       другую голову, чем та, на которой вынесен вердикт; (б) демон видел
#       черновик; (в) вызывающий назвал другую голову --head; (г) другую базу
#       --base; (д) другой черновик --draft (живое тогда — VOID: запрос не таков);
#   (3) демон получает текст с mutation | не-литерал | не-GET → отказ, код 3;
#       близнец: литерал демона проходит страж (дальше — отказ сети, код 5);
#   (4) токен из файла настроек | из переменной → отказ старта, код 4 (повтор
#       запрещён юнитом); keyring не отвечает → код 6 (повторимо: служба
#       перезапускается, ws#1151); снимка нет ни в одном случае;
#   (5) законный близнец: свежий снимок, ключ совпал целиком → ответ из снимка,
#       вызовов gh 0;
#   (6) ключ прежний, свод другой — снимок годен только при неизменном своде (ключ,
#       голова базы, state, счёт по состояниям): близнец — свод тот же, и снимок
#       старше 180 с подтверждён без чтения; (а) упала проверка (FAILURE) — перечитан,
#       из снимка 1, как живое; (б) завершённых больше при прежнем state — перечитан,
#       вывод равен живому; (в) ушла голова базы — перечитан, 4; (г) перечитывание
#       упёрлось в лимит — не подтверждён, STATE-STALE; (д) счёт сменился через 60 с
#       после чтения (рано перечитывать) и (е) остаток REST 999 < 1000 — не
#       подтверждён, STATE-STALE; близнецы (д) и (е): свод тот же — подтверждён,
#       остаток 1000 — перечитан. (д) и (е) — проходы one_pass() ОДНОГО процесса
#       ($T/passes.py) с управляемыми часами: бюджет перечитывания живёт в памяти
#       процесса, и --once до него не доходит; ответ об остатке REST подменяется в
#       процессе так же, как ответ GraphQL — файлом;
#   (7) последняя строка снимка — не VERDICT его кода (вывод пуст | «код 1» при коде
#       0) → STATE-STALE и живое 1, а не код снимка;
#   (8) ожидающий держит FIFO запроса (ws#1151): упала проверка — строка
#       «<репо> <PR> <голова> код 1» в FIFO и снимок с кодом 1 (из снимка, вызовов gh 0);
#       близнец — перечитан при том же коде и ключе: строки нет.
# Сверяется код И напечатанное (строка причины), а не только «покраснел».
#
# МУТАНТЫ — копия ci-read.sh или ci-stated.py с одним дефектом обязана уронить
# хотя бы одну сцену: age-dropped (возраст не судится), key-dropped (ключ не
# сверяется), always-live (снимок не читается), mutation-dropped (страж пропускает
# mutation), literal-dropped (страж пропускает не-литерал), method-dropped (страж
# пропускает не-GET), keyring-dropped (источник токена не судится), perms-dropped
# (права снимка не судятся); по своду (ws#1113, возврат check-verifier) — fp-dropped
# (подтверждение по одному ключу), counts-dropped и base-dropped (счёт и голова базы
# не в отпечатке), notdue-confirms, reserve-confirms, norefresh-fail-confirms
# (подтверждает ветка «рано», «резерв», «чтение не удалось»), lastline-dropped
# (последняя строка снимка не сверяется с кодом); по службе (ws#1151) — signal-dropped
# (строка в FIFO не пишется), signal-always (пишется без смены кода и ключа),
# keyring-down-final (недоступный keyring — код 4, повтор запрещён). Правка, не легшая
# в текст, — VOID.
#
# ИСХОДЫ: 0 — контроль зелёный по всем сценам, все мутанты убиты; 1 — сцена
# разошлась либо мутант выжил; 2 — судить нечем (нет jq, python3, фикстуры).
# shellcheck disable=SC2016,SC2034  # условие chk — текст для eval: переменные читаются в нём
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCR="$(dirname "$HERE")"
FX="$SCR/ci-read-fixtures/kacho-3140"
TWIN="$SCR/ci-read-fixtures/gh-twin.sh"
command -v jq >/dev/null 2>&1 || { echo "VOID: нет jq" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "VOID: нет python3" >&2; exit 2; }
[ -d "$FX" ] && [ -r "$TWIN" ] && [ -r "$SCR/ci-read.sh" ] || { echo "VOID: нет фикстуры $FX, двойника $TWIN или ci-read.sh" >&2; exit 2; }

T="$(mktemp -d "${TMPDIR:-/tmp}/ci-state-inject.XXXXXX")" || exit 2
trap 'rm -rf "$T"' EXIT

HEAD_SHA="$(jq -r .head.sha "$FX/pull.json")"; BASE_SHA="$(jq -r .base.sha "$FX/pull.json")"
REPO=PRO-Robotech/kacho; PR=3140
printf 'PRO-Robotech/kacho\t1266\t68\tфикстура kacho-3140\n' > "$T/ledger.tsv"

# Двойник gh для демона: auth status/token — по $AUTH_SRC; прочее — двойник площадки.
cat > "$T/authgh" <<'AG'
#!/usr/bin/env bash
case "$1 $2" in
  "auth status")
    [ "${AUTH_SRC:-keyring}" != down ] || { echo "error connecting to keyring" >&2; exit 1; }
    printf '{"hosts":{"github.com":[{"state":"success","active":true,"host":"github.com","login":"probe","tokenSource":"%s","token":"gho_hidden"}]}}\n' "${AUTH_SRC:-keyring}" ;;
  "auth token") echo "gho_probe_token" ;;
  *) exec "$CI_READ_GH" "$@" ;;
esac
AG
chmod +x "$T/authgh"
export CI_READ_GH_CONDITIONAL=1 CI_READ_GH="$TWIN" CI_READ_EXPECTED="$T/ledger.tsv" CI_STATED_GH="$T/authgh"

# Проходы демона в одном процессе (сцена 6 (д), (е)): one_pass() из проверяемого файла,
# часы стартуют <назад> секунд в прошлом. Шаги: poll=<ответ GraphQL> — проход;
# wait=<с> — часы вперёд; core=<остаток REST> — ответ площадки о лимите;
# fx=<каталог> — ответы площадки для живого чтения с этого прохода.
cat > "$T/passes.py" <<'PY'
import importlib.util, os, sys, time
spec = importlib.util.spec_from_file_location("ci_stated", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
class Clock:
    def __init__(self, t): self.t = t
    def time(self): return self.t
clock = Clock(time.time() - float(sys.argv[3]))
m.time = clock
d, last_refresh = m.state_dir(), {}
for step in sys.argv[4:]:
    k, _, v = step.partition("=")
    if k == "poll": m.one_pass([sys.argv[2]], d, "", v, last_refresh)
    elif k == "wait": clock.t += float(v)
    elif k == "core": m.core_remaining = lambda token, poll_file, n=int(v): n
    elif k == "fx": os.environ["CI_READ_FX"] = v
    else: sys.exit(f"шаг «{step}»: не poll=, wait=, core=, fx=")
if clock.t > time.time(): sys.exit("часы прохода ушли в будущее: возраст снимка не судим")
PY

# счёт проверок по состояниям в ответе GraphQL
C_GREEN='[{"state":"SUCCESS","count":70}]'
C_FAIL='[{"state":"SUCCESS","count":69},{"state":"FAILURE","count":1}]'
C_RUN2='[{"state":"SUCCESS","count":68},{"state":"IN_PROGRESS","count":2}]'
C_RUN1='[{"state":"SUCCESS","count":69},{"state":"IN_PROGRESS","count":1}]'
NEW_BASE=3333333333333333333333333333333333333333
# ответ GraphQL демону: <голова> <черновик> <state свода> [<счёт>] [<голова базы>]
poll() {
    jq -n --arg h "$1" --argjson d "$2" --arg s "$3" --argjson c "${4:-$C_GREEN}" --arg b "${5:-$BASE_SHA}" --argjson n "$PR" \
        '{data: {repository: {pullRequests: {nodes: [{number: $n, isDraft: $d, headRefOid: $h, baseRefName: "1266",
          baseRef: {target: {oid: $b}}, commits: {nodes: [{commit: {statusCheckRollup: {state: $s,
          contexts: {totalCount: 70, checkRunCountsByState: $c, statusContextCountsByState: []}}}}]}}]}}},
          rateLimit: {cost: 1, remaining: 4000, resetAt: "2026-10-16T13:00:00Z"}}'
}
SNAP_REL="snap/PRO-Robotech__kacho__3140.json"

# scene_fresh <ci-read> <демон> <каталог> — фикстура, демон --once, состояние готово
fresh() {
    local cr="$1" d="$2" w="$3"
    rm -rf "$w"; mkdir -p "$w/fx"; cp "$FX"/*.json "$w/fx/"
    poll "$HEAD_SHA" false SUCCESS > "$w/poll.json"
    CI_READ_FX="$w/fx" CI_STATE_DIR="$w/state" CI_STATED_CI_READ="$cr" \
        python3 "$d" --once --repos "$REPO" --poll-file "$w/poll.json" > "$w/d.out" 2>&1
}
# rd <ci-read> <каталог> <доводы…> — чтение со счётом вызовов gh; out, code, calls
rd() {
    local cr="$1" w="$2"; shift 2
    : > "$w/ghlog"
    out="$(GHLOG="$w/ghlog" CI_READ_FX="$w/fx" CI_STATE_DIR="$w/state" bash "$cr" "$REPO" "$PR" "$@" 2>"$w/rd.err")"; code=$?
    calls="$(grep -c . "$w/ghlog")"
}
tamper() {  # tamper <каталог> <выражение jq> — правка снимка, права прежние
    local f="$1/state/$SNAP_REL"
    jq "$2" "$f" > "$f.n" && chmod 600 "$f.n" && mv "$f.n" "$f"
}
age() { tamper "$1" ".checked_at = $(( $(date +%s) - $2 ))"; }  # снимок «подтверждён» N с назад
# once <ci-read> <демон> <каталог> — демон --once на ответе <каталог>/poll.json
once() { CI_READ_FX="$3/fx" CI_STATE_DIR="$3/state" CI_STATED_CI_READ="$1" \
    python3 "$2" --once --repos "$REPO" --poll-file "$3/poll.json" > "$3/once.out" 2>&1; }
# passes <ci-read> <демон> <каталог> <назад, с> <шаг>… — проходы одного процесса, см. passes.py
passes() { local cr="$1" d="$2" w="$3"; shift 3; rm -rf "$w/state"
    CI_READ_FX="$w/fx" CI_STATE_DIR="$w/state" CI_STATED_CI_READ="$cr" python3 -B "$T/passes.py" "$d" "$REPO" "$@" > "$w/passes.out" 2>&1; }
# правка ответов площадки в каталоге фикстуры: первые N проверок по имени идут | первая упала
running_fx() { jq --argjson n "${2:-1}" '.check_runs |= (sort_by(.name) | (.[0:$n] | map(.status="in_progress" | .conclusion=null | .started_at="2099-01-01T00:00:00Z")) + .[$n:])' \
    "$1/check-runs.json" > "$1/c.n" && mv "$1/c.n" "$1/check-runs.json"; }
fail_fx() { jq '.check_runs |= (sort_by(.name) | (.[0:1] | map(.status="completed" | .conclusion="failure")) + .[1:])' \
    "$1/check-runs.json" > "$1/c.n" && mv "$1/c.n" "$1/check-runs.json"; }
base_fx() { jq --arg b "$NEW_BASE" '.commit.sha = $b' "$1/branch.json" > "$1/b.n" && mv "$1/b.n" "$1/branch.json"; }  # голова базы ушла
rate_fx() { printf '{"resources":{"core":{"limit":5000,"remaining":50,"reset":4102444800},"graphql":{"limit":5000,"remaining":4000,"reset":4102444800}}}\n' > "$1/rate_limit.json"; }

fails=""
chk() {  # chk <имя> <условие оболочки>
    if eval "$2"; then echo "  [OK]   $1"; else echo "  [FAIL] $1 — код ${code:-?}, вызовов gh ${calls:-?}"; fails="$fails; $1"
        [ -z "${out:-}" ] || tail -3 <<<"$out" | sed 's/^/         /'; fi
}

scenes() {  # scenes <ci-read> <демон> <каталог> → печать; $fails — разошедшиеся
    local cr="$1" d="$2" root="$3" w="$3/w" live live_code
    fails=""
    echo "== (0) снимок пишется; снимок и живое — побайтно"
    fresh "$cr" "$d" "$w"; local drc=$?
    chk "демон --once: код 0" '[ "$drc" -eq 0 ]'
    chk "каталог 0700, снимок 0600, владелец — я" '[ "$(stat -c "%a %u" "$w/state" "$w/state/snap" "$w/state/$SNAP_REL" 2>/dev/null | tr "\n" " ")" = "700 $(id -u) 700 $(id -u) 600 $(id -u) " ]'
    rd "$cr" "$w"; live="$out"; live_code=$code
    chk "живое чтение: код 0, вызовов gh больше 0" '[ "$code" -eq 0 ] && [ "$calls" -gt 0 ]'
    rd "$cr" "$w" --from-state
    chk "снимок: тот же код, вывод побайтно равен живому" '[ "$code" -eq "$live_code" ] && [ "$out" = "$live" ] && [ -n "$out" ]'

    echo "== (5) близнец: свежий снимок, ключ целиком — из снимка, вызовов gh 0"
    rd "$cr" "$w" --from-state
    chk "код 0, вызовов gh 0" '[ "$code" -eq 0 ] && [ "$calls" -eq 0 ] && grep -qP "^VERDICT\tgreen\t" <<<"$out"'
    rd "$cr" "$w" --from-state --head "$HEAD_SHA" --base 1266 --draft false
    chk "ключ назван вызывающим и совпал — вызовов gh 0" '[ "$code" -eq 0 ] && [ "$calls" -eq 0 ]'

    echo "== (1) снимок старше 180 с — живое чтение"
    # 181 с при записи — к чтению под нагрузкой бывает 182: образец — любое число > 180
    fresh "$cr" "$d" "$w"; running_fx "$w/fx"; age "$w" 181
    rd "$cr" "$w" --from-state
    chk "STATE-STALE и код 3 из фикстуры" '[ "$code" -eq 3 ] && grep -qP "^REASON\tSTATE-STALE\t.*подтверждён (18[1-9]|19[0-9]|[2-9][0-9]{2}) с назад, годен не старше 180 с" <<<"$out" && [ "$calls" -gt 0 ]'
    fresh "$cr" "$d" "$w"; running_fx "$w/fx"; age "$w" 170
    rd "$cr" "$w" --from-state
    chk "близнец: 170 с — из снимка, код 0, вызовов 0" '[ "$code" -eq 0 ] && [ "$calls" -eq 0 ]'
    fresh "$cr" "$d" "$w"; running_fx "$w/fx"; chmod 644 "$w/state/$SNAP_REL"
    rd "$cr" "$w" --from-state
    chk "снимок 0644 — не доверяется: STATE-STALE, живое 3" '[ "$code" -eq 3 ] && grep -qP "^REASON\tSTATE-STALE\t.*права" <<<"$out"'

    echo "== (2) чужой ключ — живое чтение"
    fresh "$cr" "$d" "$w"; running_fx "$w/fx"
    poll 1111111111111111111111111111111111111111 false PENDING > "$w/poll.json"
    once "$cr" "$d" "$w"
    rd "$cr" "$w" --from-state
    chk "(а) демон видел другую голову: STATE-KEY-MISMATCH head, живое 3" '[ "$code" -eq 3 ] && grep -qP "^REASON\tSTATE-KEY-MISMATCH\t.*head" <<<"$out"'
    fresh "$cr" "$d" "$w"; running_fx "$w/fx"
    poll "$HEAD_SHA" true PENDING > "$w/poll.json"
    once "$cr" "$d" "$w"
    rd "$cr" "$w" --from-state
    chk "(б) демон видел черновик: STATE-KEY-MISMATCH draft, живое 3" '[ "$code" -eq 3 ] && grep -qP "^REASON\tSTATE-KEY-MISMATCH\t.*draft" <<<"$out"'
    fresh "$cr" "$d" "$w"; running_fx "$w/fx"
    rd "$cr" "$w" --from-state --head 2222222222222222222222222222222222222222
    chk "(в) --head другой: STATE-KEY-MISMATCH head, живое — VOID 2 (голова запроса другая)" '[ "$code" -eq 2 ] && grep -qP "^REASON\tSTATE-KEY-MISMATCH\t.*head" <<<"$out" && grep -qP "^VOID\t--head " <<<"$out" && [ "$calls" -gt 0 ]'
    rd "$cr" "$w" --from-state --base main
    chk "(г) --base другая: STATE-KEY-MISMATCH base, живое (VOID 2: база запроса другая)" '[ "$code" -eq 2 ] && grep -qP "^REASON\tSTATE-KEY-MISMATCH\t.*base" <<<"$out" && [ "$calls" -gt 0 ]'
    rd "$cr" "$w" --from-state --draft true
    chk "(д) --draft другой: STATE-KEY-MISMATCH draft, живое — VOID 2 (черновик запроса другой)" '[ "$code" -eq 2 ] && grep -qP "^REASON\tSTATE-KEY-MISMATCH\t.*draft" <<<"$out" && grep -qP "^VOID\t--draft " <<<"$out" && [ "$calls" -gt 0 ]'

    echo "== (6) ключ прежний, свод другой — снимок перечитан, а не подтверждён"
    fresh "$cr" "$d" "$w"; age "$w" 200
    GHLOG="$w/dlog" once "$cr" "$d" "$w"
    rd "$cr" "$w" --from-state
    chk "близнец: свод тот же — снимок старше 180 с подтверждён без чтения, из снимка 0" '[ ! -s "$w/dlog" ] && [ "$code" -eq 0 ] && [ "$calls" -eq 0 ]'
    fresh "$cr" "$d" "$w"; age "$w" 200; fail_fx "$w/fx"
    poll "$HEAD_SHA" false FAILURE "$C_FAIL" > "$w/poll.json"; once "$cr" "$d" "$w"
    rd "$cr" "$w"; live="$out"; live_code=$code
    rd "$cr" "$w" --from-state
    chk "(а) упала проверка (FAILURE): перечитан — из снимка 1, вывод равен живому" '[ "$live_code" -eq 1 ] && [ "$code" -eq 1 ] && [ "$calls" -eq 0 ] && [ "$out" = "$live" ]'
    rm -rf "$w"; mkdir -p "$w/fx"; cp "$FX"/*.json "$w/fx/"; running_fx "$w/fx" 2
    poll "$HEAD_SHA" false PENDING "$C_RUN2" > "$w/poll.json"; once "$cr" "$d" "$w"
    cp "$FX/check-runs.json" "$w/fx/"; running_fx "$w/fx" 1
    poll "$HEAD_SHA" false PENDING "$C_RUN1" > "$w/poll.json"; once "$cr" "$d" "$w"
    rd "$cr" "$w"; live="$out"; live_code=$code
    rd "$cr" "$w" --from-state
    chk "(б) завершённых больше, state прежний: перечитан — из снимка 3, вывод равен живому" '[ "$live_code" -eq 3 ] && [ "$code" -eq 3 ] && [ "$calls" -eq 0 ] && [ "$out" = "$live" ]'
    fresh "$cr" "$d" "$w"; base_fx "$w/fx"
    poll "$HEAD_SHA" false SUCCESS "$C_GREEN" "$NEW_BASE" > "$w/poll.json"; once "$cr" "$d" "$w"
    rd "$cr" "$w" --from-state
    chk "(в) ушла голова базы: перечитан — из снимка 4, BASE-STALE" '[ "$code" -eq 4 ] && [ "$calls" -eq 0 ] && grep -qP "^REASON\tBASE-STALE\t" <<<"$out"'
    fresh "$cr" "$d" "$w"; age "$w" 200; fail_fx "$w/fx"; rate_fx "$w/fx"
    poll "$HEAD_SHA" false FAILURE "$C_FAIL" > "$w/poll.json"; once "$cr" "$d" "$w"
    rd "$cr" "$w" --from-state
    chk "(г) упала проверка, перечитывание упёрлось в лимит: не подтверждён — STATE-STALE, живое 2" '[ "$code" -eq 2 ] && grep -qP "^REASON\tSTATE-STALE\t" <<<"$out" && grep -qP "^REASON\tRATE-LIMIT\t" <<<"$out" && [ "$calls" -gt 0 ]'
    rm -rf "$w"; mkdir -p "$w/fx" "$w/fx0"; cp "$FX"/*.json "$w/fx/"; cp "$FX"/*.json "$w/fx0/"
    running_fx "$w/fx0" 2; running_fx "$w/fx" 1
    poll "$HEAD_SHA" false PENDING "$C_RUN2" > "$w/p0.json"; poll "$HEAD_SHA" false PENDING "$C_RUN1" > "$w/p1.json"
    passes "$cr" "$d" "$w" 190 fx="$w/fx0" poll="$w/p0.json" wait=60 fx="$w/fx" poll="$w/p1.json"; local prc=$?
    rd "$cr" "$w" --from-state
    chk "(д) счёт сменился через 60 с после чтения: не перечитан и не подтверждён — STATE-STALE, живое 3" '[ "$prc" -eq 0 ] && [ "$code" -eq 3 ] && grep -qP "^REASON\tSTATE-STALE\t" <<<"$out" && [ "$calls" -gt 0 ]'
    passes "$cr" "$d" "$w" 190 fx="$w/fx0" poll="$w/p0.json" wait=60 poll="$w/p0.json"; prc=$?
    rd "$cr" "$w" --from-state
    chk "(д) близнец: свод тот же через 60 с — подтверждён, из снимка 3, вызовов 0" '[ "$prc" -eq 0 ] && [ "$code" -eq 3 ] && [ "$calls" -eq 0 ] && ! grep -qP "^REASON\tSTATE-" <<<"$out"'
    cp "$FX"/*.json "$w/fx/"; cp "$FX"/*.json "$w/fx0/"; fail_fx "$w/fx"
    poll "$HEAD_SHA" false SUCCESS > "$w/p0.json"; poll "$HEAD_SHA" false FAILURE "$C_FAIL" > "$w/p1.json"
    passes "$cr" "$d" "$w" 190 fx="$w/fx0" poll="$w/p0.json" wait=60 core=999 fx="$w/fx" poll="$w/p1.json"; prc=$?
    rd "$cr" "$w" --from-state
    chk "(е) упала проверка при остатке REST 999 < 1000: не перечитан и не подтверждён — STATE-STALE, живое 1" '[ "$prc" -eq 0 ] && [ "$code" -eq 1 ] && grep -qP "^REASON\tSTATE-STALE\t" <<<"$out" && [ "$calls" -gt 0 ]'
    passes "$cr" "$d" "$w" 190 fx="$w/fx0" poll="$w/p0.json" wait=60 core=1000 fx="$w/fx" poll="$w/p1.json"; prc=$?
    rd "$cr" "$w" --from-state
    chk "(е) близнец: остаток 1000 — перечитан, из снимка 1, вызовов 0" '[ "$prc" -eq 0 ] && [ "$code" -eq 1 ] && [ "$calls" -eq 0 ] && ! grep -qP "^REASON\tSTATE-" <<<"$out"'

    echo "== (7) последняя строка снимка — VERDICT его кода, иначе живое"
    fresh "$cr" "$d" "$w"; fail_fx "$w/fx"; tamper "$w" '.out = ""'
    rd "$cr" "$w" --from-state
    chk "(а) вывод снимка пуст при коде 0: STATE-STALE, живое 1" '[ "$code" -eq 1 ] && grep -qP "^REASON\tSTATE-STALE\t.*не VERDICT" <<<"$out" && [ "$calls" -gt 0 ]'
    fresh "$cr" "$d" "$w"; fail_fx "$w/fx"; tamper "$w" '.out |= sub("VERDICT\tgreen\tкод 0"; "VERDICT\tred\tкод 1")'
    rd "$cr" "$w" --from-state
    chk "(б) снимок «код 1» при коде 0: STATE-STALE, живое 1" '[ "$code" -eq 1 ] && grep -qP "^REASON\tSTATE-STALE\t.*не VERDICT" <<<"$out" && [ "$calls" -gt 0 ]'

    echo "== (8) смена свода — строка в FIFO ожидающего и снимок обновлён"
    local fifo="$w/state/wait/PRO-Robotech__kacho__3140.fifo" fd line lrc
    fresh "$cr" "$d" "$w"; fail_fx "$w/fx"
    [ -p "$fifo" ] || mkfifo -m 600 "$fifo"; exec {fd}<>"$fifo"   # ожидающий открыл FIFO до прохода
    poll "$HEAD_SHA" false FAILURE "$C_FAIL" > "$w/poll.json"; once "$cr" "$d" "$w"
    line="$(timeout 2 head -n1 <&"$fd")"; lrc=$?; exec {fd}>&-
    rd "$cr" "$w" --from-state
    chk "упала проверка: строка «$REPO $PR <голова> код 1» в FIFO, из снимка 1, вызовов gh 0" '[ "$lrc" -eq 0 ] && [ "$line" = "$REPO $PR $HEAD_SHA код 1" ] && [ "$code" -eq 1 ] && [ "$calls" -eq 0 ]'
    rm -rf "$w"; mkdir -p "$w/fx"; cp "$FX"/*.json "$w/fx/"; running_fx "$w/fx" 2
    poll "$HEAD_SHA" false PENDING "$C_RUN2" > "$w/poll.json"; once "$cr" "$d" "$w"
    cp "$FX/check-runs.json" "$w/fx/"; running_fx "$w/fx" 1
    [ -p "$fifo" ] || mkfifo -m 600 "$fifo"; exec {fd}<>"$fifo"
    poll "$HEAD_SHA" false PENDING "$C_RUN1" > "$w/poll.json"; GHLOG="$w/dlog" once "$cr" "$d" "$w"
    line="$(timeout 1 head -n1 <&"$fd")"; lrc=$?; exec {fd}>&-
    chk "близнец: перечитан при том же коде 3 и ключе — строки в FIFO нет" '[ -s "$w/dlog" ] && [ "$lrc" -eq 124 ] && [ -z "$line" ]'

    echo "== (3) страж записи демона"
    local q="$root/q"
    printf 'mutation { addComment(input: {subjectId: "x", body: "y"}) { clientMutationId } }' > "$q.mut"
    printf 'query { viewer { login } }' > "$q.foreign"
    python3 "$d" --print-query open_prs > "$q.lit" 2>/dev/null
    probe() { CI_STATED_API=http://127.0.0.1:9 python3 "$d" --probe-request "$@" > "$root/probe.out" 2>&1; code=$?; out="$(cat "$root/probe.out")"; calls=-; }
    probe POST /graphql "$q.mut"
    chk "текст с mutation: отказ, код 3, причина mutation" '[ "$code" -eq 3 ] && grep -q "mutation" <<<"$out"'
    probe POST /graphql "$q.foreign"
    chk "не литерал демона: отказ, код 3" '[ "$code" -eq 3 ] && grep -q "литерал" <<<"$out"'
    probe PATCH /repos/PRO-Robotech/kacho/pulls/3140
    chk "PATCH: отказ, код 3" '[ "$code" -eq 3 ] && grep -q "метод" <<<"$out"'
    probe POST /repos/PRO-Robotech/kacho/issues/3140/comments
    chk "POST вне /graphql: отказ, код 3" '[ "$code" -eq 3 ] && grep -q "метод" <<<"$out"'
    probe POST /graphql "$q.lit"
    chk "близнец: литерал демона проходит страж (дальше — сеть, код 5)" '[ "$code" -eq 5 ] && [ -s "$q.lit" ]'
    probe GET /rate_limit
    chk "близнец: GET проходит страж (дальше — сеть, код 5)" '[ "$code" -eq 5 ]'

    echo "== (4) keyring недоступен — отказ старта"
    local s
    local s want
    for s in oauth_token:4 GH_TOKEN:4 down:6; do
        want="${s#*:}"; s="${s%:*}"
        rm -rf "$w"; mkdir -p "$w/fx"; cp "$FX"/*.json "$w/fx/"; poll "$HEAD_SHA" false SUCCESS > "$w/poll.json"
        AUTH_SRC="$s" CI_READ_FX="$w/fx" CI_STATE_DIR="$w/state" CI_STATED_CI_READ="$cr" \
            python3 "$d" --once --repos "$REPO" --poll-file "$w/poll.json" > "$w/d.out" 2>&1; code=$?; out="$(cat "$w/d.out")"; calls=-
        chk "источник токена $s: отказ старта, код $want, снимка нет" '[ "$code" -eq "$want" ] && grep -q "keyring" <<<"$out" && [ ! -e "$w/state/$SNAP_REL" ]'
    done
}

# Одна прогонка сцен отдельным процессом: <ci-read> <демон> <каталог>; исход — <каталог>/fails
if [ "${1:-}" = --scene ]; then
    mkdir -p "$4"; scenes "$2" "$3" "$4" > "$4/out" 2>&1; printf '%s' "$fails" > "$4/fails"; exit 0
fi

echo "### контроль"
scenes "$SCR/ci-read.sh" "$HERE/ci-stated.py" "$T/control"
ctl_fails="$fails"
echo
[ -z "$ctl_fails" ] && echo "контроль: все сцены сошлись" || echo "контроль: разошлось —${ctl_fails#;}"

echo
echo "### мутанты — каждый обязан уронить сцену (процессов ${CI_STATE_INJECT_JOBS:-$(nproc 2>/dev/null || echo 4)})"
killed=0; survived=0; void=0
: > "$T/list"
while IFS=$'\t' read -r name file expr; do
    [ -n "$name" ] || continue
    m="$T/mut/$name"; mkdir -p "$m/lib"; cp -r "$SCR/lib/." "$m/lib/" 2>/dev/null
    cp "$SCR/ci-read.sh" "$m/ci-read.sh"; cp "$HERE/ci-stated.py" "$m/ci-stated.py"
    if [ "$file" = ci-read ]; then src="$SCR/ci-read.sh"; dst="$m/ci-read.sh"; else src="$HERE/ci-stated.py"; dst="$m/ci-stated.py"; fi
    sed -e "$expr" "$src" > "$dst"
    if cmp -s "$dst" "$src"; then void=$((void + 1)); echo "  MUTANT $name → RESULT VOID (правка не легла)"; continue; fi
    printf '%s\0%s\0%s\0' "$m/ci-read.sh" "$m/ci-stated.py" "$m/run" >> "$T/list"
done <<'MUT'
age-dropped	ci-read	s/\[ "\$sage" -gt "\$STATE_MAX_AGE" \]/false/
key-dropped	ci-read	/^state_key_check()/,/^}/s/\[ "\$want" = "\$have" \]/true/
always-live	ci-read	s/^\[ "\$FROM_STATE" = 1 \] && state_read/false \&\& state_read/
perms-dropped	ci-read	s/\[ "\$smode" = "\$swant" \]/true/
mutation-dropped	ci-stated	s/if MUTATION_RE.search(text):/if False:/
literal-dropped	ci-stated	s/if text not in LITERAL_TEXTS:/if False:/
method-dropped	ci-stated	s/if method != "GET":/if False:/
keyring-dropped	ci-stated	s/if src != "keyring":/if False:/
fp-dropped	ci-stated	s/ and snap.get("fp") == fp:/:/
counts-dropped	ci-stated	s/, "counts": counts}, sort_keys=True)/}, sort_keys=True)/
base-dropped	ci-stated	s/"base_oid": base_oid, //
notdue-confirms	ci-stated	/if not (changed_key or due):/,/continue/s/snap\["seen"\] = key$/snap["seen"] = key; snap["checked_at"] = now/
reserve-confirms	ci-stated	/< CORE_RESERVE:$/,/continue/s/snap\["seen"\] = key$/snap["seen"] = key; snap["checked_at"] = now/
norefresh-fail-confirms	ci-stated	/не вынесло вердикта/,/continue/s/snap\["seen"\] = key$/snap["seen"] = key; snap["checked_at"] = now/
lastline-dropped	ci-read	s/^    \[\[ "\$last" =~ .* \]\] \\$/    true \\/
signal-dropped	ci-stated	s/os.write(fd, (line + "\\n").encode())/pass/
signal-always	ci-stated	s/if not snap or snap.get("code") != code or snap.get("key") != got:/if True:/
keyring-down-final	ci-stated	/^class KeyringDown/,/code = 6/s/code = 6/code = 4/
MUT
xargs -0 -n 3 -P "${CI_STATE_INJECT_JOBS:-$(nproc 2>/dev/null || echo 4)}" bash "$HERE/inject.sh" --scene < "$T/list"
xs=$?
[ "$xs" -eq 0 ] || { echo "VOID: исполнитель мутантов вернул $xs" >&2; exit 2; }
for m in "$T"/mut/*/; do
    name="$(basename "$m")"; [ -d "$m/run" ] || continue
    if [ ! -f "$m/run/fails" ]; then void=$((void + 1)); echo "  MUTANT $name → RESULT VOID (прогонка не дописала исход)"
    elif [ -s "$m/run/fails" ]; then killed=$((killed + 1)); f="$(cat "$m/run/fails")"; echo "  MUTANT $name → RESULT KILLED (${f#; })"
    else survived=$((survived + 1)); echo "  MUTANT $name → RESULT SURVIVED"; fi
done

echo
echo "ci-state-inject: мутантов $((killed + survived + void)), убито $killed, выжило $survived, не легло $void"
[ -z "$ctl_fails" ] && [ "$survived" -eq 0 ] && [ "$void" -eq 0 ] && [ "$killed" -gt 0 ]
