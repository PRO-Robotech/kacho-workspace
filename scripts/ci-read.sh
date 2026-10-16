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
#              [--head <sha40>] [--draft true|false] [--from-state]
# Для PR база и голова берутся из запроса; для sha база — --base, без него —
# ветка по умолчанию репозитория. --base, --head, --draft — ожидание вызывающего:
# запрос не таков — VOID (код 2), а не вердикт о другой голове.
#
# --from-state (ws#1113) — ответ из снимка демона scripts/ci-state/ci-stated.py без
# единого вызова gh. Снимок — вывод ЭТОГО ЖЕ сценария, исполненного демоном живьём
# (решатель один), и печатается побайтно с его кодом. Годен, только когда:
#   · каталог состояния и снимок — мои, 0700 и 0600 (чужой или открытый не доверяется);
#   · демон подтвердил снимок не раньше 180 с назад (checked_at — последний опрос, на
#     котором ключ и отпечаток свода совпали с теми, на которых вердикт вынесен);
#   · ключ совпал ЦЕЛИКОМ — repo, pr, head, base, draft: и с тем, что демон видел на
#     последнем опросе, и с --head/--base/--draft вызывающего, если названы.
# Иначе — живое чтение, а первой строкой REASON STATE-STALE (снимка нет, старше 180 с,
# права, не разбирается) либо STATE-KEY-MISMATCH (поле и оба значения). Эти строки о
# снимке, а не о голове: в вердикт и «причин N» не входят. Посадка (landing-precheck.sh,
# merge-readiness.sh) снимок не читает — только живьём.
#
# УСЛОВНОЕ ЧТЕНИЕ (ws#1113): запрос, статус, защита, наборы правил, ветка базы,
# сравнение и аннотации читаются с If-None-Match по ETag прошлого ответа; ответ 304
# лимит площадки не расходует, тело берётся из кэша $CI_STATE_DIR/etag (каталог 0700,
# файл 0600: первая строка — ETag, дальше тело; заголовков ответа не хранится). Кэш
# недоступен или чужой — чтение без условия. Счёт — строкой stderr «условных чтений N,
# не изменилось M»: в stdout её нет, иначе вывод снимка и живой разошлись бы на ней.
#
# ЧТО СУДИТСЯ — строка REASON<TAB><код><TAB><пояснение> на причину:
#   (а) полнота:
#       CHECKS-INCOMPLETE — различных проверок на голове меньше ожидаемого по
#                           ведомости scripts/ci-read-expected.tsv (пара
#                           репозиторий/база); пары нет — VOID, не зелёное;
#       CI-PENDING        — судимая проверка имени (выбор — (е2): последняя по
#                           started_at, красная побеждает) не завершена либо
#                           commit status pending;
#       RUNS-PENDING      — ПОСЛЕДНИЙ workflow run своего workflow на этой sha
#                           не completed;
#       CI-FAILED         — судимая проверка имени завершена failure, cancelled,
#                           timed_out, action_required, startup_failure, stale;
#                           commit status failure/error. skipped и neutral не
#                           красные, но и не success — печатаются в CENSUS и не
#                           засчитываются обязательному контексту;
#       ВЫТЕСНЕНИЕ (ws#1019; урок kaname#709) — в счёт идёт только ПОСЛЕДНИЙ
#                           workflow run каждого workflow и события на голове
#                           (по created_at, при равенстве — по id). run_attempt
#                           прогоны не упорядочивает: перезапуск — тот же прогон
#                           (тот же id, created_at и check_suite), список отдаёт
#                           его один раз с последней попыткой, а проверки прежних
#                           попыток лежат в том же check_suite и судятся по имени —
#                           последняя по started_at. Ключ workflow — workflow_id
#                           (при его отсутствии path, затем name): одноимённые
#                           workflow разных файлов друг друга не вытесняют; check-run
#                           вытесненного прогона (его check_suite_id) не судится
#                           вовсе. Без этого сводная проверка прежнего целевого
#                           прогона черновика, завершённая failure, оставалась
#                           «последней по имени», пока одноимённая проверка
#                           полного прогона после перевода в ready не стартовала, —
#                           и голова читалась красной (1) вместо «идёт» (3).
#                           Событие входит в ключ: прогон push и прогон
#                           pull_request одного workflow отвечают на разные
#                           вопросы и друг друга не вытесняют. check-run вне
#                           workflow run (сторонние приложения) судится по имени;
#   (б) защита ветки базы:
#       REQUIRED-NOT-SUCCESS — обязательный контекст (branch protection и
#                           rulesets) завершён не success;
#       REQUIRED-MISSING  — обязательного контекста на голове нет, а всё
#                           остальное завершено и набор полон (иначе это ещё
#                           CI-PENDING: контекст мог не стартовать);
#   (в) свежесть базы:
#       BASE-STALE        — merge-base головы и базы ≠ голова базы: зелёное
#                           получено на прежней базе и о слиянии не говорит.
#   (г) черновик — ЦЕЛЕВОЙ прогон (ws#1013; kacho#3148, kaname#707):
#       на черновике запроса в ветку эпика конвейер исполняет только задания,
#       выбранные картой путей репозитория, прочие — skipped, а сводный вердикт
#       черновика красный по построению и несёт аннотацию «черновик не вливается».
#       Такой сводный вердикт — СТРАЖ, а не отказ: он не судится как CI-FAILED, а
#       обязательные контексты и полнота набора на черновике не судятся (пропуск
#       матрицы даёт одну проверку вместо ног). Стража нет либо он не вынесен —
#       DRAFT-GUARD-PENDING (ждать).
#   (д) целевой прогон на НЕ-черновике (ws#1019, остаток приёмки): запрос, переведённый
#       в черновик и обратно, несёт поздний целевой прогон того же workflow; по (а) он
#       вытеснил бы красное прежнего ПОЛНОГО. Поэтому на не-черновике последним
#       считается последний ПОЛНЫЙ прогон workflow: прогон, в check_suite которого
#       есть проверка failure с аннотацией стража, — целевой и в последние не идёт,
#       пока у workflow есть полный. Полного нет — последним остаётся целевой, и его
#       страж судится как CI-FAILED (не черновик). СЛЕПАЯ ЗОНА, оставшаяся открытой:
#       целевой прогон, ещё не вынесший стража (идёт), целевым не распознаётся —
#       он последний, и голова читается RUNS-PENDING (3): ожидание, а не зелёное.
#   (е) ручной прогон на голове запроса (ws#1049; урок kaname#765): прогон
#       workflow_dispatch того же workflow — другое событие, (а) его не вытесняет, а
#       сводный вердикт запроса в нём skipped по условию на событие и стартует позже
#       — «последний по имени» читал бы голову красной. Правило, fail-closed:
#       (е1) отбрасывается ТОЛЬКО check-run, у которого есть workflow run, событие
#            этого прогона не pull_request, а исход skipped, neutral или success, — и
#            только если у того же имени есть check-run из прогона pull_request на этой
#            голове. Check-run без workflow run (стороннее приложение, check_suite
#            null) не отбрасывается никогда. Отброшенное печатается CENSUS;
#       (е2) failure, cancelled, timed_out, action_required (весь FAILSET) любого
#            события и любого источника того же имени не отбрасываются и краснят
#            голову, даже при success из pull_request и в каком бы порядке ни стояли:
#            из оставшихся у имени судится последняя проверка каждого check_suite, а
#            среди них — красная, если она есть; иначе незавершённая; иначе последняя.
#            Поздний красный ручного, push или pull_request_target прогона — красный;
#       (е3) success другого события не перекрывает failure из pull_request (он
#            отброшен по (е1), а failure судится по (е2)). Без проверки того же имени
#            из pull_request ничто не отбрасывается: skipped ручного — не success
#            (обязательный контекст — REQUIRED-NOT-SUCCESS), failure — CI-FAILED.
#
# ИСХОДЫ — код возврата и строка VERDICT; при нескольких причинах побеждает
# старшая в порядке 2 > 1 > 4 > 3 > 5 > 0, остальные напечатаны всё равно; ИСКЛЮЧЕНИЕ
# (ws#1110, владелец 2026-10-16): красное при идущих заданиях — 3, а не 1: ожидание не
# прерывается на первом красном, VERDICT называет число уже красных:
#   0 green    — полный набор, всё завершено, обязательные success, база свежая;
#   1 red      — CI-FAILED, REQUIRED-NOT-SUCCESS, REQUIRED-MISSING (перепись имён), всё завершено;
#   2 unread   — VOID: площадка не ответила, ответ не разбирается, пары нет в
#                ведомости, лимит площадки ниже 100 (REASON RATE-LIMIT со временем
#                сброса, lib/gh-rate.sh). Это НЕ «зелёное» и НЕ «красное»;
#   3 running  — CI-PENDING, RUNS-PENDING, CHECKS-INCOMPLETE: ждать, не провал;
#   4 stale    — BASE-STALE: влить свежую базу и читать заново;
#   5 targeted-green — черновик: исполненное зелёное, страж вынес «целевой
#              зелёный». Это НЕ «полный зелёный»: вливать по нему нельзя — перевод
#              запроса в ready заводит полный прогон того же состава, читать заново.
# Перепись печатается всегда строками CENSUS — «причин 0» отличимо от «не прочитано».
#
# ВХОД ПОДМЕНЯЕМ — ради доказательства (scripts/ci-read-inject.sh):
#   CI_READ_GH       — вместо `gh` (зовётся только `gh api [--paginate | -i [-H
#                      If-None-Match:…]] <путь>`);
#   CI_READ_EXPECTED — путь ведомости вместо scripts/ci-read-expected.tsv;
#   CI_STATE_DIR     — каталог состояния вместо ~/.cache/kacho-ci-state (снимки и кэш
#                      условного чтения; пробы дают свой);
#   CI_READ_GH_CONDITIONAL=1 — подставной gh знает `-i` и If-None-Match (двойник
#                      scripts/ci-read-fixtures/gh-twin.sh); без него — чтение без условия.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GH="${CI_READ_GH:-gh}"
LEDGER="${CI_READ_EXPECTED:-$HERE/ci-read-expected.tsv}"
# красные заключения проверки: судятся CI-FAILED и побеждают при выборе судимой по (е2)
FAILSET='["failure","cancelled","timed_out","action_required","startup_failure","stale"]'

void() { printf 'VOID\t%s\n' "$1"; printf 'VERDICT\tunread\tкод 2\n'; exit 2; }

REPO="${1:-}"; REF="${2:-}"
shift 2 2>/dev/null || true
BASE=""; WANT_HEAD=""; WANT_DRAFT=""; FROM_STATE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --base) BASE="${2:-}"; [ -n "$BASE" ] || void "--base без ветки"; shift 2 ;;
        --head) WANT_HEAD="${2:-}"; [[ "$WANT_HEAD" =~ ^[0-9a-f]{40}$ ]] || void "--head «$WANT_HEAD» не sha40"; shift 2 ;;
        --draft) WANT_DRAFT="${2:-}"; [[ "$WANT_DRAFT" =~ ^(true|false)$ ]] || void "--draft «$WANT_DRAFT» не true|false"; shift 2 ;;
        --from-state) FROM_STATE=1; shift ;;
        *) void "неизвестный довод «$1»" ;;
    esac
done
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || void "репозиторий «$REPO» не формы <владелец>/<имя>"
[[ "$REF" =~ ^[0-9]+$ || "$REF" =~ ^[0-9a-f]{40}$ ]] || void "«$REF» не номер PR и не sha40"
command -v jq >/dev/null 2>&1 || void "нет jq в PATH"
[ -n "${CI_READ_GH:-}" ] || command -v gh >/dev/null 2>&1 || void "нет gh в PATH"
[ -r "$LEDGER" ] || void "ведомость ожидаемого «$LEDGER» не читается"
STATE_DIR="${CI_STATE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/kacho-ci-state}"
STATE_MAX_AGE=180

# --- ответ из снимка демона (ws#1113): ни одного вызова gh, см. шапку
state_key_check() {  # <поле> <чьё ожидание> <ожидание> <снимок> — 0 совпало; иначе REASON, 1
    local field="$1" who="$2" want="$3" have="$4"
    [ "$want" = "$have" ] && return 0
    printf 'REASON\tSTATE-KEY-MISMATCH\t%s: вердикт снимка вынесен при «%s», %s «%s» — живое чтение\n' "$field" "$have" "$who" "$want"
    return 1
}
state_read() {  # 0 — ответ снимка напечатан, код в SCODE; 1 — причина напечатана, читать живьём
    local f="$STATE_DIR/snap/${REPO%%/*}__${REPO#*/}__$REF.json" sage smode swant k last
    stale() { printf 'REASON\tSTATE-STALE\t%s — живое чтение\n' "$1"; }
    [[ "$REF" =~ ^[0-9]+$ ]] || { state_key_check pr "вызывающий назвал" "sha $REF" "номер запроса"; return 1; }
    [ -f "$f" ] || { stale "снимка $f нет (демон ci-stated не запущен либо запрос не открыт)"; return 1; }
    smode="$(stat -c '%u %a' "$STATE_DIR" "$STATE_DIR/snap" "$f" 2>/dev/null | tr '\n' ' ')"
    swant="$(id -u) 700 $(id -u) 700 $(id -u) 600 "
    [ "$smode" = "$swant" ] || { stale "права снимка «$smode» ≠ «$swant»: чужой или открытый снимок не доверяется"; return 1; }
    jq -e '(.key|type)=="object" and (.seen|type)=="object" and (.checked_at|type)=="number"
        and (.code|type)=="number" and (.out|type)=="string"' "$f" >/dev/null 2>&1 \
        || { stale "снимок $f не разбирается"; return 1; }
    sage=$(( $(date +%s) - $(jq -r '.checked_at | floor' "$f") ))
    [ "$sage" -ge 0 ] || { stale "снимок подтверждён в будущем ($sage с)"; return 1; }
    if [ "$sage" -gt "$STATE_MAX_AGE" ]; then stale "снимок подтверждён $sage с назад, годен не старше $STATE_MAX_AGE с"; return 1; fi
    for k in repo pr head base draft; do   # демон видел ровно то, на чём вердикт вынесен
        state_key_check "$k" "демон на последнем опросе видел" "$(jq -r ".seen.$k | tostring" "$f")" "$(jq -r ".key.$k | tostring" "$f")" || return 1
    done
    state_key_check repo "вызывающий назвал" "$REPO" "$(jq -r '.key.repo | tostring' "$f")" || return 1
    state_key_check pr "вызывающий назвал" "$REF" "$(jq -r '.key.pr | tostring' "$f")" || return 1
    [ -z "$WANT_HEAD" ] || state_key_check head "вызывающий назвал" "$WANT_HEAD" "$(jq -r '.key.head | tostring' "$f")" || return 1
    [ -z "$BASE" ] || state_key_check base "вызывающий назвал" "$BASE" "$(jq -r '.key.base | tostring' "$f")" || return 1
    [ -z "$WANT_DRAFT" ] || state_key_check draft "вызывающий назвал" "$WANT_DRAFT" "$(jq -r '.key.draft | tostring' "$f")" || return 1
    SCODE="$(jq -r '.code' "$f")"
    last="$(jq -j '.out' "$f" | tail -n 1)"   # в переменную: grep -q в трубе под pipefail — 141
    [[ "$last" =~ ^VERDICT$'\t'[^[:space:]]+$'\t'"код $SCODE"(\;|$) ]] \
        || { stale "последняя строка снимка — не VERDICT с кодом $SCODE"; return 1; }
    jq -j '.out' "$f"
    printf 'ci-read: ответ из снимка демона, подтверждён %s с назад, вызовов gh 0\n' "$sage" >&2
    return 0
}
[ "$FROM_STATE" = 1 ] && state_read && exit "$SCODE"

# Лимит площадки — ДО первого чтения (урок 2026-10-16, ws#1110): исчерпан — 2 со временем
# сброса и REASON RATE-LIMIT, а не красное и не тайм-аут.
# shellcheck source=lib/gh-rate.sh
. "$HERE/lib/gh-rate.sh" || void "нет $HERE/lib/gh-rate.sh — лимит не проверить"
if ! RL="$(gh_rate_short "$GH" 100)"; then
    printf 'REASON\tRATE-LIMIT\t%s\n' "$RL"
    void "$RL — не выполнилось, не красное: читать после сброса"
fi

W="$(mktemp -d "${TMPDIR:-/tmp}/ci-read.XXXXXX")" || void "временный каталог не создан"
trap 'rm -rf "$W"' EXIT

api() { "$GH" api "$1" 2>"$W/api.err"; }
apip() { "$GH" api --paginate "$1" 2>"$W/api.err" | jq -s '.' 2>/dev/null; }
apierr() { head -c 300 "$W/api.err" | tr '\n' ' '; }
# Условное чтение (ws#1113, см. шапку). Кэш — только свой каталог 0700 и файл 0600.
# Подставной gh (CI_READ_GH) получает условное чтение, только заявив его
# CI_READ_GH_CONDITIONAL=1: заглушки чужих проб (landing-precheck-inject) форм
# `-i`/`-H` не знают, а свой кэш в доме пользователя им не положен. Заглушка в PATH
# (check-09) не видна по CI_READ_GH: её отказ на `-i` переводит чтение в безусловное.
# Кэш — каталог 0700 и мой: в него не пишет никто другой, поэтому файл судится лишь
# каталогом (одна проверка на чтение, а не на каждый ответ). Файлы — umask 077.
EC=""; CONDN=0; CONDHIT=0
umask 077
if { [ -z "${CI_READ_GH:-}" ] || [ "${CI_READ_GH_CONDITIONAL:-0}" = 1 ]; } \
    && mkdir -p "$STATE_DIR/etag" 2>/dev/null \
    && [ "$(stat -c '%u %a' "$STATE_DIR" "$STATE_DIR/etag" 2>/dev/null)" = "$EUID 700"$'\n'"$EUID 700" ]; then
    EC="$STATE_DIR/etag"
fi
apic() {  # apic <путь> — тело в stdout; 304 — тело из кэша; без кэша — api
    local p="$1" f e st rc hdr=()
    [ -n "$EC" ] || { api "$p"; return; }
    CONDN=$((CONDN + 1))
    f="${GH_HOST:-github.com}/$p"; f="${f//_/__}"; f="$EC/${f//[^A-Za-z0-9._=-]/_}"   # совпадение имён безопасно: 304 — лишь при том же ETag
    if [ -f "$f" ] && IFS= read -r e < "$f"; then hdr=(-H "If-None-Match: $e"); fi
    "$GH" api -i "${hdr[@]}" "$p" > "$W/c.raw" 2>"$W/api.err"; rc=$?
    IFS= read -r st < "$W/c.raw"; st="${st%$'\r'}"
    case "$st" in
        HTTP/*' 304'*)
            [ "${#hdr[@]}" -gt 0 ] || return 1
            CONDHIT=$((CONDHIT + 1)); sed 1d "$f"; return 0 ;;
        HTTP/*)
            # одним проходом: тело — в c.body, ETag заголовка — в stdout
            e="$(awk -v out="$W/c.body" 'b {print > out; next} /^\r?$/ {b = 1; printf "" > out; next}
                !b && tolower($0) ~ /^etag:/ {sub(/^[^:]*:[ \t]*/, ""); sub(/\r$/, ""); print}' "$W/c.raw")"
            [ -f "$W/c.body" ] || : > "$W/c.body"
            if [ "$rc" -eq 0 ] && [ -n "$e" ]; then
                { printf '%s\n' "$e"; cat "$W/c.body"; } > "$f.$$" && mv -f "$f.$$" "$f"
            fi
            cat "$W/c.body"; rm -f "$W/c.body"; return "$rc" ;;
        *)  # gh без `-i` (заглушка иной пробы, check-09 — в PATH): отказал — чтение без
            # условия до конца прогона; ответил телом — тело
            if [ "$rc" -ne 0 ]; then EC=""; api "$p"; return; fi
            cat "$W/c.raw"; return "$rc" ;;
    esac
}

# --- голова и база
if [[ "$REF" =~ ^[0-9]+$ ]]; then
    apic "repos/$REPO/pulls/$REF" > "$W/pull.json" || void "площадка не отдала PR $REPO#$REF: $(apierr)"
    jq -e '(.head.sha|type=="string") and (.base.ref|type=="string")' "$W/pull.json" >/dev/null 2>&1 \
        || void "ответ о PR $REPO#$REF не разбирается (нет head.sha или base.ref)"
    HEAD_SHA="$(jq -r .head.sha "$W/pull.json")"
    PR_BASE="$(jq -r .base.ref "$W/pull.json")"
    [ -z "$BASE" ] || [ "$BASE" = "$PR_BASE" ] || void "--base $BASE ≠ базе запроса $PR_BASE"
    BASE="$PR_BASE"
    DRAFT="$(jq -r 'if .draft == true then "true" else "false" end' "$W/pull.json")"
    [ -z "$WANT_HEAD" ] || [ "$WANT_HEAD" = "$HEAD_SHA" ] || void "--head $WANT_HEAD ≠ голове запроса $HEAD_SHA"
    [ -z "$WANT_DRAFT" ] || [ "$WANT_DRAFT" = "$DRAFT" ] || void "--draft $WANT_DRAFT ≠ черновику запроса $DRAFT"
    printf 'CENSUS\tзапрос %s#%s: состояние %s, голова %s, база %s, черновик %s\n' "$REPO" "$REF" "$(jq -r '.state // "?"' "$W/pull.json")" "$HEAD_SHA" "$BASE" "$DRAFT"
else
    HEAD_SHA="$REF"
    DRAFT=false
    [ -z "$WANT_HEAD" ] || [ "$WANT_HEAD" = "$HEAD_SHA" ] || void "--head $WANT_HEAD ≠ sha $HEAD_SHA"
    [ -z "$WANT_DRAFT" ] || [ "$WANT_DRAFT" = false ] || void "--draft true при чтении по sha"
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
{ apic "repos/$REPO/commits/$HEAD_SHA/status" > "$W/st.json" \
    && jq -e '.statuses|type=="array"' "$W/st.json" >/dev/null 2>&1; } \
    || void "commit status на $HEAD_SHA не прочитан: $(apierr)"
{ apip "repos/$REPO/actions/runs?head_sha=$HEAD_SHA&per_page=100" > "$W/runs.json" \
    && jq -e 'type=="array" and all(.[]; .workflow_runs|type=="array")' "$W/runs.json" >/dev/null 2>&1; } \
    || void "workflow runs на $HEAD_SHA не прочитаны: $(apierr)"

# Аннотация стража — признак целевого прогона (см. (г) и (д)). Судится аннотацией, а
# не именем: имя стража у репозиториев разное, и вторая копия имени здесь разошлась
# бы с конвейером молча.
# На площадке аннотация есть у КАЖДОЙ упавшей проверки (выход раннера: failure с
# пустым title, «Process completed with exit code 1.»), поэтому стражем делает только
# title стража, а не наличие аннотации (ws#1019, N1 check-verifier).
GUARD_TITLE="черновик не вливается"
guarded() {  # guarded <id проверки> <имя> — 0 страж, 1 нет; ответ не прочитан — VOID
    apic "repos/$REPO/check-runs/$1/annotations" > "$W/ann.json" || void "аннотации проверки $2 не прочитаны: $(apierr)"
    jq -e --arg t "$GUARD_TITLE" 'type=="array" and any(.[]; .title==$t)' "$W/ann.json" >/dev/null 2>&1
}
# (д) не-черновик: check_suite с проверкой-стражем — целевой прогон
NARROW='[]'
if [ "$DRAFT" != true ]; then
    while IFS=$'\t' read -r gid gsuite gname; do
        [ -n "$gid" ] && [ "$gid" != null ] && [ "$gsuite" != null ] || continue
        if guarded "$gid" "$gname"; then
            NARROW="$(jq -c --argjson s "$gsuite" '. + [$s] | unique' <<<"$NARROW")"
            printf 'CENSUS\tцелевой прогон на не-черновике (страж %s, check_suite %s): последним не считается, пока у workflow есть полный\n' "$gname" "$gsuite"
        fi
    done < <(jq -r '[.[].check_runs[]] | .[] | select(.status=="completed" and .conclusion=="failure") | "\(.id)\t\(.check_suite.id // null)\t\(.name)"' "$W/cr.json")
fi
# последний workflow run каждого workflow и события — последний ПОЛНЫЙ, если он есть;
# прочие — вытеснены (ws#1019)
jq --argjson nar "$NARROW" '[.[].workflow_runs[]] | group_by([(.workflow_id // .path // .name), .event])
    | map(sort_by([(.created_at // ""), .id])
        | (map(select(.check_suite_id as $c | $nar | index($c) | not))) as $full
        | (if ($full | length) > 0 then ($full | last) else last end) as $l
        | {l: $l, s: map(select(.id != $l.id))})
    | {latest: map(.l), superseded: (map(.s) | add // [])}' "$W/runs.json" > "$W/runsel.json"
SUPERSEDED="$(jq -c '[.superseded[].check_suite_id]' "$W/runsel.json")"
jq --argjson s "$SUPERSEDED" '[.[].check_runs[] | select((.check_suite.id // null) as $i | $s | index($i) | not)]' "$W/cr.json" > "$W/crl.json"
# (е) ручной прогон (ws#1049): событие проверки — событие прогона её check_suite; у
# проверки без workflow run (стороннее приложение, check_suite null) события нет. Правило:
# (е1) отбрасывается ТОЛЬКО проверка с прогоном (ev != null) события не pull_request,
#      завершённая skipped, neutral или success, — и лишь когда у того же имени есть
#      проверка из прогона pull_request на этой голове; проверка без прогона не
#      отбрасывается никогда;
# (е2) из оставшихся у имени берётся последняя по started_at в каждом check_suite; если
#      среди них есть красная (FAILSET) — судится она, в каком бы событии и порядке ни
#      стояла; иначе — незавершённая; иначе — последняя по started_at.
SUITE_EV="$(jq -c '[.[].workflow_runs[] | select(.check_suite_id != null) | {key: (.check_suite_id | tostring), value: .event}] | from_entries' "$W/runs.json")"
jq --argjson ev "$SUITE_EV" 'map(.ev = $ev[(.check_suite.id // null) | tostring]) | group_by(.name)
    | map(any(.[]; .ev == "pull_request") as $pr
        | map(.drop = ($pr and .ev != null and .ev != "pull_request" and .status == "completed" and ((.conclusion // "") | IN("skipped", "neutral", "success")))))
    | add // []' "$W/crl.json" > "$W/crm.json"
MANUAL_DROP="$(jq -r '[.[] | select(.drop) | "\(.name) (\(.ev), \(.conclusion), check-run \(.id))"] | join("; ")' "$W/crm.json")"
[ -z "$MANUAL_DROP" ] || printf 'CENSUS\tskipped/neutral/success прогона не-pull_request при проверке того же имени из pull_request не судится: %s\n' "$MANUAL_DROP"
# судимая проверка каждого имени среди невытесненных и не отброшенных по (е1) — по (е2);
# commit status — уже последний по контексту
jq --argjson f "$FAILSET" '[.[] | select(.drop | not)] | group_by(.name)
    | map(group_by(.check_suite.id // null) | map(sort_by(.started_at // "") | last) as $src
        | ($src | map(select(.status == "completed" and ((.conclusion // "") as $c | $f | index($c))))) as $red
        | ($src | map(select(.status != "completed"))) as $run
        | if ($red | length) > 0 then ($red | sort_by(.started_at // "") | last)
          elif ($run | length) > 0 then ($run | sort_by(.started_at // "") | last)
          else ($src | sort_by(.started_at // "") | last) end)
    | map({name, id, done: (.status=="completed"), c: (.conclusion // "")})' "$W/crm.json" > "$W/latest.json"
# Черновик: страж — проверка, завершённая failure с аннотацией «черновик не вливается».
GUARDS=0
if [ "$DRAFT" = true ]; then
    while IFS=$'\t' read -r gid gname; do
        [ -n "$gid" ] && [ "$gid" != null ] || continue
        if guarded "$gid" "$gname"; then
            GUARDS=$((GUARDS + 1))
            jq --arg n "$gname" 'map(.c = (if .name==$n then "draft-guard" else .c end))' "$W/latest.json" > "$W/latest.n" && mv "$W/latest.n" "$W/latest.json"
            printf 'CENSUS\tстраж черновика: %s\n' "$gname"
        fi
    done < <(jq -r '.[]|select(.done and .c=="failure")|"\(.id)\t\(.name)"' "$W/latest.json")
fi
jq '[.statuses[] | {name: .context, done: (.state!="pending"),
     c: (if .state=="success" then "success" elif .state=="pending" then "" else "failure" end)}]' "$W/st.json" > "$W/stl.json"
# Обе формы (ws#1113): у имени может быть и check-run, и commit status (сводный вердикт
# переводится с задания-опроса на commit status). Запись на имя одна: красное из двух
# побеждает, затем незавершённое, затем check-run — одна форма не закрывает другую.
jq -s --argjson f "$FAILSET" '(.[0] + .[1]) | group_by(.name) | map(
        (map(select(.done and (.c as $c | $f | index($c))))) as $bad
        | (map(select(.done | not))) as $open
        | if ($bad | length) > 0 then $bad[0] elif ($open | length) > 0 then $open[0] else .[0] end)' \
    "$W/latest.json" "$W/stl.json" > "$W/all.json"
RAW="$(jq 'length' "$W/crl.json")"
DROPPED=$(( $(jq '[.[].check_runs[]]|length' "$W/cr.json") - RAW ))
NAMES="$(jq 'length' "$W/all.json")"
printf 'CENSUS\tпроверок на голове: различных %s (check-run прогонов %s, commit status %s; check-run вытесненных прогонов не судится %s), ожидается не меньше %s\n' \
    "$NAMES" "$RAW" "$(jq length "$W/stl.json")" "$DROPPED" "$EXPECT"

R="$W/reasons"; : > "$R"
reason() { printf 'REASON\t%s\t%s\n' "$1" "$2" >> "$R"; }

while IFS= read -r n; do reason CI-PENDING "не завершена: $n"; done < <(jq -r '.[]|select(.done|not)|.name' "$W/all.json")
while IFS=$'\t' read -r n c; do reason CI-FAILED "$c: $n"; done < <(jq -r --argjson f "$FAILSET" '.[]|select(.done and (.c as $c | $f | index($c)))|"\(.name)\t\(.c)"' "$W/all.json")
OTHER="$(jq -r --argjson f "$FAILSET" '[.[]|select(.done and .c!="success" and .c!="draft-guard" and (.c as $c | $f | index($c) | not))|"\(.name) (\(.c))"]|join("; ")' "$W/all.json")"
[ -z "$OTHER" ] || printf 'CENSUS\tзавершены не success и не красные: %s\n' "$OTHER"
RUNS="$(jq '[.[].workflow_runs[]]|length' "$W/runs.json")"
while IFS= read -r n; do reason RUNS-PENDING "workflow run не завершён: $n"; done < <(jq -r '.latest[]|select(.status!="completed")|"\(.name) (\(.status), run \(.id))"' "$W/runsel.json")
SUPN="$(jq '.superseded|length' "$W/runsel.json")"
printf 'CENSUS\tworkflow runs на голове: %s; последних по workflow и событию %s, вытеснено %s; из последних не завершено %s\n' \
    "$RUNS" "$(jq '.latest|length' "$W/runsel.json")" "$SUPN" "$(jq '[.latest[]|select(.status!="completed")]|length' "$W/runsel.json")"
[ "$SUPN" -eq 0 ] || printf 'CENSUS\tвытесненные прогоны (не судятся): %s\n' "$(jq -r '[.superseded[]|"\(.name) run \(.id) (\(.status)/\(.conclusion // "-"))"]|join("; ")' "$W/runsel.json")"
if [ "$DRAFT" = true ]; then
    EXEC="$(jq '[.[]|select(.done and .c!="skipped" and .c!="draft-guard")]|length' "$W/all.json")"
    SKIP="$(jq '[.[]|select(.done and .c=="skipped")]|length' "$W/all.json")"
    printf 'CENSUS\tчерновик — целевой прогон: исполнено проверок %s, пропущено %s, стражей %s; полнота и обязательные контексты на черновике не судятся\n' "$EXEC" "$SKIP" "$GUARDS"
    [ "$GUARDS" -gt 0 ] || reason DRAFT-GUARD-PENDING "сводный вердикт черновика ещё не вынесен (нет проверки с аннотацией «$GUARD_TITLE»)"
elif [ "$NAMES" -lt "$EXPECT" ]; then reason CHECKS-INCOMPLETE "проверок $NAMES из $EXPECT ожидаемых: набор на голове неполон (не все workflow стартовали)"; fi

# --- обязательные контексты защиты ветки базы
: > "$W/req.txt"
if apic "repos/$REPO/branches/$BASE/protection/required_status_checks" > "$W/prot.json"; then
    jq -e 'type=="object"' "$W/prot.json" >/dev/null 2>&1 || void "ответ о защите $BASE не разбирается"
    jq -r '[(.contexts // [])[], ((.checks // [])[] | .context)] | unique[]' "$W/prot.json" >> "$W/req.txt"
elif grep -qE 'not protected|Required status checks not enabled' "$W/api.err"; then
    printf 'CENSUS\tзащиты ветки %s нет — обязательных контекстов по защите 0\n' "$BASE"
else
    void "защита ветки $BASE не прочитана: $(apierr)"
fi
if apic "repos/$REPO/rules/branches/$BASE" > "$W/rules.json"; then
    jq -r '.[]? | select(.type=="required_status_checks") | .parameters.required_status_checks[]?.context' "$W/rules.json" >> "$W/req.txt" 2>/dev/null \
        || void "ответ о наборах правил $BASE не разбирается"
else
    void "наборы правил ветки $BASE не прочитаны: $(apierr)"
fi
sort -u -o "$W/req.txt" "$W/req.txt"
REQN="$(grep -c . "$W/req.txt")"
# неполный набор — тоже «ещё идёт»: недостающий обязательный контекст мог не стартовать
PENDING_ANY="$(grep -cP '^REASON\t(CI-PENDING|RUNS-PENDING|CHECKS-INCOMPLETE)\t' "$R")"
[ "$DRAFT" != true ] || : > "$W/req.txt"   # черновик: обязательные не судятся (см. (г))
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
apic "repos/$REPO/branches/$BASE" > "$W/branch.json" || void "ветка базы $BASE не прочитана: $(apierr)"
BASE_SHA="$(jq -r '.commit.sha // empty' "$W/branch.json")"
[[ "$BASE_SHA" =~ ^[0-9a-f]{40}$ ]] || void "голова базы $BASE не прочитана"
apic "repos/$REPO/compare/$BASE_SHA...$HEAD_SHA" > "$W/cmp.json" || void "сравнение $BASE...голова не прочитано: $(apierr)"
MB="$(jq -r '.merge_base_commit.sha // empty' "$W/cmp.json")"
[[ "$MB" =~ ^[0-9a-f]{40}$ ]] || void "merge-base головы и $BASE не прочитан"
printf 'CENSUS\tбаза %s @%s, merge-base %s, отставание %s\n' "$BASE" "$BASE_SHA" "$MB" "$(jq -r '.behind_by // "?"' "$W/cmp.json")"
[ "$MB" = "$BASE_SHA" ] || reason BASE-STALE "merge-base $MB ≠ голове базы $BASE $BASE_SHA: отставание $(jq -r '.behind_by // "?"' "$W/cmp.json") — влить свежую базу и читать заново"

# --- вердикт
cat "$R"
has() { grep -qP "^REASON\t($1)\t" "$R"; }
PEND='CI-PENDING|RUNS-PENDING|CHECKS-INCOMPLETE'
# красное при идущих — «идёт» (3), а не «красное» (1): чтение не прерывается на первом
# красном, пока идут задания (владелец 2026-10-16, ai-tooling.md#at-red-ci-one-round) —
# перепись корней снимается с ЗАВЕРШЁННОГО набора, иначе круг чинит часть красноты;
# DRAFT-GUARD-PENDING красного не держит: страж не вынесен при завершённых заданиях
REDN="$(grep -cP '^REASON\t(CI-FAILED|REQUIRED-NOT-SUCCESS|REQUIRED-MISSING)\t' "$R")"
if [ "$REDN" -gt 0 ] && ! has "$PEND"; then code=1; v=red
elif has 'BASE-STALE'; then code=4; v=stale
elif has "$PEND|DRAFT-GUARD-PENDING"; then code=3; v=running
elif [ "$DRAFT" = true ]; then code=5; v=targeted-green
else code=0; v=green; fi
HINT=""; [ "$code" != 5 ] || HINT="; ЦЕЛЕВОЙ, не полный: вливать нельзя — перевод в ready заводит полный прогон"
[ "$code" != 3 ] || [ "$REDN" -eq 0 ] || HINT="; красных уже $REDN, задания идут — итог и перепись корней по завершении ВСЕХ"
[ -z "$EC" ] || printf 'ci-read: условных чтений %s, не изменилось %s\n' "$CONDN" "$CONDHIT" >&2
printf 'VERDICT\t%s\tкод %s; причин %s; проверок %s из %s; голова %s%s\n' "$v" "$code" "$(grep -c . "$R")" "$NAMES" "$EXPECT" "$HEAD_SHA" "$HINT"
exit "$code"
