#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# ci-read.sh — ЕДИНСТВЕННОЕ чтение вердикта конвейера в оснастке (ws#1006).
#
# ЗАЧЕМ. Урок 2026-10-11: kacho#3142 влит при прочтении «зелёно 30 из 30», когда на
# голове было 68 проверок и 3 ещё шли; признак устаревшей базы шаблон не учёл.
# Чтение держалось вниманием: «всё, что вижу, зелёное» не сверялось с тем, СКОЛЬКО
# проверок обязано быть, незавершённый workflow не отличался от отсутствующего, а
# свежесть базы не спрашивалась. Здесь каждое из трёх условий — код.
#
# ИСПОЛЬЗОВАНИЕ
#   ci-read.sh <владелец/репозиторий> <номер PR | sha40> [--base <ветка>]
# Для PR база и голова берутся из запроса; для sha база — --base, без него —
# ветка по умолчанию репозитория.
#
# ЧТО СУДИТСЯ — строка REASON<TAB><код><TAB><пояснение> на причину:
#   (а) полнота:
#       CHECKS-INCOMPLETE — различных проверок на голове меньше ожидаемого по
#                           ведомости scripts/ci-read-expected.tsv (пара
#                           репозиторий/база); пары нет — VOID, не зелёное;
#       CI-PENDING        — последний прогон проверки (по имени, наибольший
#                           started_at) не завершён либо commit status pending;
#       RUNS-PENDING      — workflow run на этой sha не completed;
#       CI-FAILED         — последний прогон проверки завершён failure, cancelled,
#                           timed_out, action_required, startup_failure, stale;
#                           commit status failure/error. skipped и neutral не
#                           красные, но и не success — печатаются в CENSUS и не
#                           засчитываются обязательному контексту;
#   (б) защита ветки базы:
#       REQUIRED-NOT-SUCCESS — обязательный контекст (branch protection и
#                           rulesets) завершён не success;
#       REQUIRED-MISSING  — обязательного контекста на голове нет, а всё
#                           остальное завершено и набор полон (иначе это ещё
#                           CI-PENDING: контекст мог не стартовать);
#   (в) свежесть базы:
#       BASE-STALE        — merge-base головы и базы ≠ голова базы: зелёное
#                           получено на прежней базе и о слиянии не говорит.
#
# ИСХОДЫ — код возврата и строка VERDICT; при нескольких причинах побеждает
# старшая в порядке 2 > 1 > 4 > 3 > 0, остальные напечатаны всё равно:
#   0 green    — полный набор, всё завершено, обязательные success, база свежая;
#   1 red      — CI-FAILED, REQUIRED-NOT-SUCCESS, REQUIRED-MISSING (перепись имён);
#   2 unread   — VOID: площадка не ответила, ответ не разбирается, пары нет в
#                ведомости. Это НЕ «зелёное» и НЕ «красное»;
#   3 running  — CI-PENDING, RUNS-PENDING, CHECKS-INCOMPLETE: ждать, не провал;
#   4 stale    — BASE-STALE: влить свежую базу и читать заново.
# Перепись печатается всегда строками CENSUS — «причин 0» отличимо от «не прочитано».
#
# ВХОД ПОДМЕНЯЕМ — ради доказательства (scripts/ci-read-inject.sh):
#   CI_READ_GH       — вместо `gh` (зовётся только `gh api [--paginate] <путь>`);
#   CI_READ_EXPECTED — путь ведомости вместо scripts/ci-read-expected.tsv.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GH="${CI_READ_GH:-gh}"
LEDGER="${CI_READ_EXPECTED:-$HERE/ci-read-expected.tsv}"

void() { printf 'VOID\t%s\n' "$1"; printf 'VERDICT\tunread\tкод 2\n'; exit 2; }

REPO="${1:-}"; REF="${2:-}"
shift 2 2>/dev/null || true
BASE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --base) BASE="${2:-}"; [ -n "$BASE" ] || void "--base без ветки"; shift 2 ;;
        *) void "неизвестный довод «$1»" ;;
    esac
done
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || void "репозиторий «$REPO» не формы <владелец>/<имя>"
[[ "$REF" =~ ^[0-9]+$ || "$REF" =~ ^[0-9a-f]{40}$ ]] || void "«$REF» не номер PR и не sha40"
command -v jq >/dev/null 2>&1 || void "нет jq в PATH"
[ -n "${CI_READ_GH:-}" ] || command -v gh >/dev/null 2>&1 || void "нет gh в PATH"
[ -r "$LEDGER" ] || void "ведомость ожидаемого «$LEDGER» не читается"

W="$(mktemp -d "${TMPDIR:-/tmp}/ci-read.XXXXXX")" || void "временный каталог не создан"
trap 'rm -rf "$W"' EXIT

api() { "$GH" api "$1" 2>"$W/api.err"; }
apip() { "$GH" api --paginate "$1" 2>"$W/api.err" | jq -s '.' 2>/dev/null; }
apierr() { head -c 300 "$W/api.err" | tr '\n' ' '; }

# --- голова и база
if [[ "$REF" =~ ^[0-9]+$ ]]; then
    api "repos/$REPO/pulls/$REF" > "$W/pull.json" || void "площадка не отдала PR $REPO#$REF: $(apierr)"
    jq -e '(.head.sha|type=="string") and (.base.ref|type=="string")' "$W/pull.json" >/dev/null 2>&1 \
        || void "ответ о PR $REPO#$REF не разбирается (нет head.sha или base.ref)"
    HEAD_SHA="$(jq -r .head.sha "$W/pull.json")"
    PR_BASE="$(jq -r .base.ref "$W/pull.json")"
    [ -z "$BASE" ] || [ "$BASE" = "$PR_BASE" ] || void "--base $BASE ≠ базе запроса $PR_BASE"
    BASE="$PR_BASE"
    printf 'CENSUS\tзапрос %s#%s: состояние %s, голова %s, база %s\n' "$REPO" "$REF" "$(jq -r '.state // "?"' "$W/pull.json")" "$HEAD_SHA" "$BASE"
else
    HEAD_SHA="$REF"
    if [ -z "$BASE" ]; then
        api "repos/$REPO" > "$W/repo.json" || void "площадка не отдала репозиторий $REPO: $(apierr)"
        BASE="$(jq -r '.default_branch // empty' "$W/repo.json")"
        [ -n "$BASE" ] || void "ветка по умолчанию $REPO не прочитана"
    fi
    printf 'CENSUS\tsha %s в %s, база %s\n' "$HEAD_SHA" "$REPO" "$BASE"
fi
[[ "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]] || void "голова «$HEAD_SHA» не 40 hex"

# --- ожидаемое по ведомости
EXPECT="$(awk -F'\t' -v r="$REPO" -v b="$BASE" '!/^#/ && $1==r && $2==b {print $3; exit}' "$LEDGER")"
[[ "$EXPECT" =~ ^[1-9][0-9]*$ ]] || void "пары $REPO / $BASE нет в ведомости $(basename "$LEDGER") — ожидаемое не известно; строка заводится замером"

# --- проверки на голове
{ apip "repos/$REPO/commits/$HEAD_SHA/check-runs?per_page=100" > "$W/cr.json" \
    && jq -e 'type=="array" and length>0 and all(.[]; .check_runs|type=="array")' "$W/cr.json" >/dev/null 2>&1; } \
    || void "check-runs на $HEAD_SHA не прочитаны: $(apierr)"
{ api "repos/$REPO/commits/$HEAD_SHA/status" > "$W/st.json" \
    && jq -e '.statuses|type=="array"' "$W/st.json" >/dev/null 2>&1; } \
    || void "commit status на $HEAD_SHA не прочитан: $(apierr)"
{ apip "repos/$REPO/actions/runs?head_sha=$HEAD_SHA&per_page=100" > "$W/runs.json" \
    && jq -e 'type=="array" and all(.[]; .workflow_runs|type=="array")' "$W/runs.json" >/dev/null 2>&1; } \
    || void "workflow runs на $HEAD_SHA не прочитаны: $(apierr)"

# последний прогон каждого имени; commit status — уже последний по контексту
jq '[.[].check_runs[]] | group_by(.name) | map(sort_by(.started_at // "") | last)
    | map({name, done: (.status=="completed"), c: (.conclusion // "")})' "$W/cr.json" > "$W/latest.json"
jq '[.statuses[] | {name: .context, done: (.state!="pending"),
     c: (if .state=="success" then "success" elif .state=="pending" then "" else "failure" end)}]' "$W/st.json" > "$W/stl.json"
jq -s '(.[0] | map(.name)) as $c | .[0] + (.[1] | map(select(.name as $n | $c | index($n) | not)))' "$W/latest.json" "$W/stl.json" > "$W/all.json"
RAW="$(jq '[.[].check_runs[]]|length' "$W/cr.json")"
NAMES="$(jq 'length' "$W/all.json")"
printf 'CENSUS\tпроверок на голове: различных %s (check-run прогонов %s, commit status %s), ожидается не меньше %s\n' \
    "$NAMES" "$RAW" "$(jq length "$W/stl.json")" "$EXPECT"

R="$W/reasons"; : > "$R"
reason() { printf 'REASON\t%s\t%s\n' "$1" "$2" >> "$R"; }
FAILSET='["failure","cancelled","timed_out","action_required","startup_failure","stale"]'

while IFS= read -r n; do reason CI-PENDING "не завершена: $n"; done < <(jq -r '.[]|select(.done|not)|.name' "$W/all.json")
while IFS=$'\t' read -r n c; do reason CI-FAILED "$c: $n"; done < <(jq -r --argjson f "$FAILSET" '.[]|select(.done and (.c as $c | $f | index($c)))|"\(.name)\t\(.c)"' "$W/all.json")
OTHER="$(jq -r --argjson f "$FAILSET" '[.[]|select(.done and .c!="success" and (.c as $c | $f | index($c) | not))|"\(.name) (\(.c))"]|join("; ")' "$W/all.json")"
[ -z "$OTHER" ] || printf 'CENSUS\tзавершены не success и не красные: %s\n' "$OTHER"
RUNS="$(jq '[.[].workflow_runs[]]|length' "$W/runs.json")"
while IFS= read -r n; do reason RUNS-PENDING "workflow run не завершён: $n"; done < <(jq -r '.[].workflow_runs[]|select(.status!="completed")|"\(.name) (\(.status), run \(.id))"' "$W/runs.json")
printf 'CENSUS\tworkflow runs на голове: %s, не завершено %s\n' "$RUNS" "$(jq '[.[].workflow_runs[]|select(.status!="completed")]|length' "$W/runs.json")"
[ "$NAMES" -ge "$EXPECT" ] || reason CHECKS-INCOMPLETE "проверок $NAMES из $EXPECT ожидаемых: набор на голове неполон (не все workflow стартовали)"

# --- обязательные контексты защиты ветки базы
: > "$W/req.txt"
if api "repos/$REPO/branches/$BASE/protection/required_status_checks" > "$W/prot.json"; then
    jq -e 'type=="object"' "$W/prot.json" >/dev/null 2>&1 || void "ответ о защите $BASE не разбирается"
    jq -r '[(.contexts // [])[], ((.checks // [])[] | .context)] | unique[]' "$W/prot.json" >> "$W/req.txt"
elif grep -qE 'not protected|Required status checks not enabled' "$W/api.err"; then
    printf 'CENSUS\tзащиты ветки %s нет — обязательных контекстов по защите 0\n' "$BASE"
else
    void "защита ветки $BASE не прочитана: $(apierr)"
fi
if api "repos/$REPO/rules/branches/$BASE" > "$W/rules.json"; then
    jq -r '.[]? | select(.type=="required_status_checks") | .parameters.required_status_checks[]?.context' "$W/rules.json" >> "$W/req.txt" 2>/dev/null \
        || void "ответ о наборах правил $BASE не разбирается"
else
    void "наборы правил ветки $BASE не прочитаны: $(apierr)"
fi
sort -u -o "$W/req.txt" "$W/req.txt"
REQN="$(grep -c . "$W/req.txt")"
# неполный набор — тоже «ещё идёт»: недостающий обязательный контекст мог не стартовать
PENDING_ANY="$(grep -cP '^REASON\t(CI-PENDING|RUNS-PENDING|CHECKS-INCOMPLETE)\t' "$R")"
while IFS= read -r ctx; do
    [ -n "$ctx" ] || continue
    st="$(jq -r --arg n "$ctx" 'map(select(.name==$n))|if length==0 then "absent" elif (.[0].done|not) then "pending" else .[0].c end' "$W/all.json")"
    case "$st" in
        success) ;;
        pending) ;;   # уже названа строкой CI-PENDING
        absent) if [ "$PENDING_ANY" -gt 0 ]; then reason CI-PENDING "обязательный контекст ещё не появился: $ctx"
                else reason REQUIRED-MISSING "обязательного контекста нет на голове при завершённом остальном: $ctx"; fi ;;
        *) reason REQUIRED-NOT-SUCCESS "обязательный контекст $st: $ctx" ;;
    esac
done < "$W/req.txt"
printf 'CENSUS\tобязательных контекстов базы %s: %s\n' "$BASE" "$REQN"

# --- свежесть базы
api "repos/$REPO/branches/$BASE" > "$W/branch.json" || void "ветка базы $BASE не прочитана: $(apierr)"
BASE_SHA="$(jq -r '.commit.sha // empty' "$W/branch.json")"
[[ "$BASE_SHA" =~ ^[0-9a-f]{40}$ ]] || void "голова базы $BASE не прочитана"
api "repos/$REPO/compare/$BASE_SHA...$HEAD_SHA" > "$W/cmp.json" || void "сравнение $BASE...голова не прочитано: $(apierr)"
MB="$(jq -r '.merge_base_commit.sha // empty' "$W/cmp.json")"
[[ "$MB" =~ ^[0-9a-f]{40}$ ]] || void "merge-base головы и $BASE не прочитан"
printf 'CENSUS\tбаза %s @%s, merge-base %s, отставание %s\n' "$BASE" "$BASE_SHA" "$MB" "$(jq -r '.behind_by // "?"' "$W/cmp.json")"
[ "$MB" = "$BASE_SHA" ] || reason BASE-STALE "merge-base $MB ≠ голове базы $BASE $BASE_SHA: отставание $(jq -r '.behind_by // "?"' "$W/cmp.json") — влить свежую базу и читать заново"

# --- вердикт
cat "$R"
has() { grep -qP "^REASON\t($1)\t" "$R"; }
if has 'CI-FAILED|REQUIRED-NOT-SUCCESS|REQUIRED-MISSING'; then code=1; v=red
elif has 'BASE-STALE'; then code=4; v=stale
elif has 'CI-PENDING|RUNS-PENDING|CHECKS-INCOMPLETE'; then code=3; v=running
else code=0; v=green; fi
printf 'VERDICT\t%s\tкод %s; причин %s; проверок %s из %s; голова %s\n' "$v" "$code" "$(grep -c . "$R")" "$NAMES" "$EXPECT" "$HEAD_SHA"
exit "$code"
