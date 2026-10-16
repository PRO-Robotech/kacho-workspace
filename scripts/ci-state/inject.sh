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
# СЦЕНЫ (каждая меняет ровно один факт против законного близнеца 5):
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
#   (4) keyring недоступен (токен из файла настроек | gh auth status не отвечает)
#       → отказ старта, код 4, снимка нет;
#   (5) законный близнец: свежий снимок, ключ совпал целиком → ответ из снимка,
#       вызовов gh 0.
# Сверяется код И напечатанное (строка причины), а не только «покраснел».
#
# МУТАНТЫ — копия ci-read.sh или ci-stated.py с одним дефектом обязана уронить
# хотя бы одну сцену: age-dropped (возраст не судится), key-dropped (ключ не
# сверяется), always-live (снимок не читается), mutation-dropped (страж пропускает
# mutation), literal-dropped (страж пропускает не-литерал), method-dropped (страж
# пропускает не-GET), keyring-dropped (источник токена не судится), perms-dropped
# (права снимка не судятся). Правка, не легшая в текст, — VOID.
#
# ИСХОДЫ: 0 — контроль зелёный по всем сценам, все мутанты убиты; 1 — сцена
# разошлась либо мутант выжил; 2 — судить нечем (нет jq, python3, фикстуры).
set -uo pipefail
# shellcheck disable=SC2016,SC2034  # условие chk — текст для eval: переменные читаются в нём

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

# ответ GraphQL демону: <голова> <черновик> <state свода>
poll() {
    jq -n --arg h "$1" --argjson d "$2" --arg s "$3" --arg b "$BASE_SHA" --argjson n "$PR" \
        '{data: {repository: {pullRequests: {nodes: [{number: $n, isDraft: $d, headRefOid: $h, baseRefName: "1266",
          baseRef: {target: {oid: $b}}, commits: {nodes: [{commit: {statusCheckRollup: {state: $s,
          contexts: {totalCount: 70, checkRunCountsByState: [{state: "SUCCESS", count: 70}], statusContextCountsByState: []}}}}]}}]}}},
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
age() {  # age <каталог> <секунд> — снимок «подтверждён» N секунд назад, права прежние
    local f="$1/state/$SNAP_REL"
    jq --argjson t "$(( $(date +%s) - $2 ))" '.checked_at = $t' "$f" > "$f.n" && chmod 600 "$f.n" && mv "$f.n" "$f"
}
running_fx() { jq '.check_runs |= (sort_by(.name) | (.[0:1] | map(.status="in_progress" | .conclusion=null | .started_at="2099-01-01T00:00:00Z")) + .[1:])' \
    "$1/fx/check-runs.json" > "$1/fx/c.n" && mv "$1/fx/c.n" "$1/fx/check-runs.json"; }

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
    fresh "$cr" "$d" "$w"; running_fx "$w"; age "$w" 181
    rd "$cr" "$w" --from-state
    chk "STATE-STALE и код 3 из фикстуры" '[ "$code" -eq 3 ] && grep -qP "^REASON\tSTATE-STALE\t.*181" <<<"$out" && [ "$calls" -gt 0 ]'
    fresh "$cr" "$d" "$w"; running_fx "$w"; age "$w" 170
    rd "$cr" "$w" --from-state
    chk "близнец: 170 с — из снимка, код 0, вызовов 0" '[ "$code" -eq 0 ] && [ "$calls" -eq 0 ]'
    fresh "$cr" "$d" "$w"; running_fx "$w"; chmod 644 "$w/state/$SNAP_REL"
    rd "$cr" "$w" --from-state
    chk "снимок 0644 — не доверяется: STATE-STALE, живое 3" '[ "$code" -eq 3 ] && grep -qP "^REASON\tSTATE-STALE\t.*права" <<<"$out"'

    echo "== (2) чужой ключ — живое чтение"
    fresh "$cr" "$d" "$w"; running_fx "$w"
    poll 1111111111111111111111111111111111111111 false PENDING > "$w/poll.json"
    CI_READ_FX="$w/fx" CI_STATE_DIR="$w/state" CI_STATED_CI_READ="$cr" python3 "$d" --once --repos "$REPO" --poll-file "$w/poll.json" >/dev/null 2>&1
    rd "$cr" "$w" --from-state
    chk "(а) демон видел другую голову: STATE-KEY-MISMATCH head, живое 3" '[ "$code" -eq 3 ] && grep -qP "^REASON\tSTATE-KEY-MISMATCH\t.*head" <<<"$out"'
    fresh "$cr" "$d" "$w"; running_fx "$w"
    poll "$HEAD_SHA" true PENDING > "$w/poll.json"
    CI_READ_FX="$w/fx" CI_STATE_DIR="$w/state" CI_STATED_CI_READ="$cr" python3 "$d" --once --repos "$REPO" --poll-file "$w/poll.json" >/dev/null 2>&1
    rd "$cr" "$w" --from-state
    chk "(б) демон видел черновик: STATE-KEY-MISMATCH draft, живое 3" '[ "$code" -eq 3 ] && grep -qP "^REASON\tSTATE-KEY-MISMATCH\t.*draft" <<<"$out"'
    fresh "$cr" "$d" "$w"; running_fx "$w"
    rd "$cr" "$w" --from-state --head 2222222222222222222222222222222222222222
    chk "(в) --head другой: STATE-KEY-MISMATCH head, живое — VOID 2 (голова запроса другая)" '[ "$code" -eq 2 ] && grep -qP "^REASON\tSTATE-KEY-MISMATCH\t.*head" <<<"$out" && grep -qP "^VOID\t--head " <<<"$out" && [ "$calls" -gt 0 ]'
    rd "$cr" "$w" --from-state --base main
    chk "(г) --base другая: STATE-KEY-MISMATCH base, живое (VOID 2: база запроса другая)" '[ "$code" -eq 2 ] && grep -qP "^REASON\tSTATE-KEY-MISMATCH\t.*base" <<<"$out" && [ "$calls" -gt 0 ]'
    rd "$cr" "$w" --from-state --draft true
    chk "(д) --draft другой: STATE-KEY-MISMATCH draft, живое — VOID 2 (черновик запроса другой)" '[ "$code" -eq 2 ] && grep -qP "^REASON\tSTATE-KEY-MISMATCH\t.*draft" <<<"$out" && grep -qP "^VOID\t--draft " <<<"$out" && [ "$calls" -gt 0 ]'

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
    for s in oauth_token GH_TOKEN down; do
        rm -rf "$w"; mkdir -p "$w/fx"; cp "$FX"/*.json "$w/fx/"; poll "$HEAD_SHA" false SUCCESS > "$w/poll.json"
        AUTH_SRC="$s" CI_READ_FX="$w/fx" CI_STATE_DIR="$w/state" CI_STATED_CI_READ="$cr" \
            python3 "$d" --once --repos "$REPO" --poll-file "$w/poll.json" > "$w/d.out" 2>&1; code=$?; out="$(cat "$w/d.out")"; calls=-
        chk "источник токена $s: отказ старта, код 4, снимка нет" '[ "$code" -eq 4 ] && grep -q "keyring" <<<"$out" && [ ! -e "$w/state/$SNAP_REL" ]'
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
