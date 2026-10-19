#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# ci-read-inject.sh — доказательство scripts/ci-read.sh ИСПОЛНЕНИЕМ (ws#1006).
#
# ВХОД — настоящий: ответы площадки о kacho#3140 (68 различных проверок, 70
# прогонов check-run — повтор «текст запроса» трижды, 10 workflow runs,
# обязательный контекст «сводный вердикт» защиты ветки 1266), снятые 2026-10-11 и
# урезанные до читаемых полей — scripts/ci-read-fixtures/kacho-3140/. branch.json
# и compare.json — синтетика той же формы (база = base.sha запроса). Поля, которые
# ci-read.sh читает и которые живой ответ несёт всегда, в фикстуре ЕСТЬ: id у
# check-run, workflow_id · path · created_at · run_attempt · run_number у workflow
# run, draft у запроса — доставлены 2026-10-12 из живого ответа о той же голове
# (сопоставление по имени, started_at и check_suite: 70 из 70, прочие поля совпали).
# Без id ci-read.sh пропускал бы каждую проверку в поиске стража, и случаи судили бы
# не живую форму (ws#1019, мутант D2 выжил). Предпосылка проверяется до случаев.
# Аннотации стража лежат у ОДНОЙ проверки (annotations.<id>.json), в живой форме —
# тройкой с аннотацией выхода и notice; прочим проверкам двойник отдаёт живую форму
# по заключению (см. двойник ниже). Сверка ключей с живым ответом (kaname,
# f11cbe7, 2026-10-12): из полей, которые читает ci-read.sh, в фикстуре недостаёт 0;
# недостающие (у check-run — app, output, html_url и др.; у run — actor, html_url,
# head_commit и др.; у status — sha, total_count и др.) ci-read.sh не читает.
# Существенное расхождение было одно — аннотации упавшей проверки — и закрыто двойником.
# Каждый случай меняет РОВНО один факт контроля:
#
#   контроль: полный зелёный, база свежая                         → 0 green
#   урок #3142: на голове 30 различных проверок из 68, остальные
#             ещё не стартовали, всё видимое зелёное               → 3 CHECKS-INCOMPLETE
#   урок #3142: 68 из 68, три последних ещё in_progress            → 3 CI-PENDING
#   workflow run ещё in_progress, check-runs все завершены         → 3 RUNS-PENDING
#   всё зелёное, голова базы ушла вперёд                           → 4 BASE-STALE
#   одна проверка failure                                          → 1 CI-FAILED
#   одна проверка cancelled | timed_out | action_required |
#             startup_failure | stale — каждое значение FAILSET
#             отдельным случаем                                    → 1 CI-FAILED
#   commit status failure вне check-runs                           → 1 CI-FAILED
#   одна проверка failure, другая (или workflow run) ещё идёт     → 3 running,
#             VERDICT «красных уже N» (ws#1110: ожидание не прерывается)
#   check-runs двумя страницами (100+9), поздний failure имени —
#             на второй: читается только с --paginate              → 1 CI-FAILED
#   обязательный контекст исчез при завершённом остальном          → 1 REQUIRED-MISSING
#   обязательный контекст skipped                                  → 1 REQUIRED-NOT-SUCCESS
#   последний по started_at прогон имени failure, прежний success  → 1 CI-FAILED
#   вытеснение (ws#1019; урок kaname#709) — workflow «сводный вердикт»
#             получает второй, более поздний прогон того же события:
#             прежний failure, новый идёт, его проверки ещё нет      → 3 running
#             прежний success, новый завершён failure (близнец)      → 1 CI-FAILED
#             прежний failure, новый завершён success (близнец)      → 0 green
#             то же, проверка прежнего с БОЛЕЕ ПОЗДНИМ started_at    → 0 green
#             прежний ещё идёт, новый завершён success               → 0 green
#             прежний — событие push и идёт: не вытеснен; его
#             failure красный по (е2)                               → 1 RUNS-PENDING
#             одноимённый workflow ДРУГОГО файла (workflow_id) позже:
#             не вытесняет, красное прежнего судится                → 1 CI-FAILED
#             новый позже по created_at, но с меньшим run_number      → 0 green
#             новый позже по created_at, но с меньшим id              → 0 green
#             последний прогон queued (не in_progress)               → 3 RUNS-PENDING
#   ручной прогон workflow_dispatch (ws#1049; урок kaname#765, (е) ci-read.sh) —
#             агрегат pull_request success, тот же из ручного skipped
#             позже                                                  → 0 green
#             то же, отброшенное напечатано CENSUS                   → 0 green
#             ручной neutral / success позже success из pull_request → 0 green
#             ручной failure позже success из pull_request           → 1 CI-FAILED
#             push failure РАНЬШЕ success из pull_request            → 1 CI-FAILED
#             pull_request_target failure позже success из PR        → 1 CI-FAILED
#             (3) pr-fail-disp-success-later: failure из pull_request,
#             ручной success позже — красное не закрыто           → 1 CI-FAILED
#             сторонний check-run failure того же имени (suite без
#             workflow run; check_suite null)                        → 1 CI-FAILED
#             сторонний skipped позже success из PR — не отброшен    → 1 REQUIRED-NOT-SUCCESS
#             ручной skipped, агрегат pull_request ещё идёт          → 3 CI-PENDING
#             близнец: skipped ручного без прогона pull_request      → 1 REQUIRED-NOT-SUCCESS
#             близнец: failure ручного без прогона pull_request      → 1 CI-FAILED
#   целевой прогон на НЕ-черновике (ws#1019, (д) ci-read.sh): прежний
#             ПОЛНЫЙ — build failure, поздний ЦЕЛЕВОЙ того же workflow
#             (проверки skipped, страж с аннотацией) не вытесняет его → 1 CI-FAILED build
#             близнец — тот же набор на черновике: судится целевой  → 5 targeted-green
#   черновик (ws#1013): исполненное зелёное, прочее skipped, страж
#             с аннотацией «черновик не вливается»                 → 5 targeted-green
#   не черновик: полный прогон того же workflow после зелёного
#             прежнего, проверка failure С id и БЕЗ аннотации стража
#             (целевым не считается, вытесняет прежний)             → 1 CI-FAILED
#   черновик: failure БЕЗ аннотации стража — настоящий отказ       → 1 CI-FAILED
#   черновик: failure, аннотация failure «Process completed with
#             exit code 1.» с пустым title, стража нет (N1)         → 1 CI-FAILED
#   черновик: страж есть, выбранное задание failure                → 1 CI-FAILED
#   черновик: страж ещё идёт                                       → 3 DRAFT-GUARD-PENDING
#   не черновик: та же аннотация стражем не делает                 → 1 CI-FAILED
#   площадка не отдала check-runs                                  → 2 VOID
#   лимит REST ниже порога 100 (урок 2026-10-16)                  → 2 RATE-LIMIT
#             близнец: остаток ровно на пороге                     → 0 green
#   пары репозиторий/база нет в ведомости                          → 2 VOID
#   сводный вердикт commit status вместо check-run (ws#1113), форма выводится из
#             фикстуры: success → 0; pending → 3; failure → 1 REQUIRED-NOT-SUCCESS;
#             error → 1 CI-FAILED; статуса ещё нет → 3 (не REQUIRED-MISSING)
#   обе формы одного имени: красное из двух побеждает, затем незавершённое → 1 | 3;
#             обе success — имя одно                                → 0 green
#   условное чтение: повтор тем же кэшем без смены — 304 у 6 из 6  → 0 green;
#             между чтениями сменились ветка базы | commit status |
#             черновик — кэш смену не прячет                       → 4 | 1 | 3;
#             заглушка без `-i` (check-09) — чтение без условия     → 0 green
#   вытеснение в группе concurrency (ws#1216): вход — захват kacho#3296 @5a586e18
#             (scripts/ci-read-fixtures/kacho-3296, снят 2026-10-19): последний прогон
#             production-posture cancelled, check-run его check_suite нет, 71 различных
#             при строке main = 68; файл workflow на голове урезан до jobs.*.{name,
#             strategy.matrix}:
#             как есть (сводный вердикт failure рядом)              → 1 RUN-DISPLACED,
#               три непоявившихся имени (матрица раскрыта)
#             сводный вердикт success — ОДИН факт: старый счёт «71 ≥ 68»
#               читал голову зелёной                               → 1 RUN-DISPLACED
#             файла workflow нет — причина та же, имена «не выведены» → 1
#             близнец: прогон с исходом, его три проверки есть       → 0 green
#             близнец: cancelled С проверками — судятся они          → 1 CI-FAILED,
#               cancelled без проверок 0
#   набор обязательных вызывающему (CI_READ_REQUIRED_OUT, ws#1215): контекст
#             защиты | пустой без защиты | контекст набора правил   → 0, файл;
#             наборы правил | защита (502, не «not protected») не
#             прочитаны                                → 2 VOID, файла нет
#   ведомость занижена (на голове 68, записано 67)        → 0 green + LEDGER-STALE;
#             близнецы: 68 при 68 и черновик — строки LEDGER-STALE нет
#   живая ведомость: запрос в main каждого ствола (kacho, kaname,
#             corelib, kacho-workspace) — строка есть             → 0 green
#   живая ведомость: запрос в базу КАЖДОЙ строки (стволы и эпики,
#             перечень — обходом ведомости, ws#1097): строка есть,
#             число = числу фикстуры                              → 0 green
#             число на 1 больше числа фикстуры (сверка числа)     → 3 CHECKS-INCOMPLETE
# ВЕДОМОСТЬ СЛУЧАЕВ — синтетическая ($FXL, одна строка kacho/1266 = 68 — число
# фикстуры), а не живая: живая строка kacho/1266 меряет ТЕКУЩИЙ набор workflow
# (74 на 2026-10-12) и обязана меняться вместе с ним, а фикстура снята при 68.
# Случаи, читавшие живую строку, краснели от честного перемера (ws#1019). Раздел
# «живая ведомость» судит ПРИСУТСТВИЕ строки ствола в живой ведомости; её число
# заменяется числом фикстуры в копии — иначе он судил бы набор workflow ствола.
# Близнецы (обязаны молчать — код 0): прежний прогон имени failure стоит в ответе
# ПЕРВЫМ либо ПОСЛЕДНИМ, последний по started_at — success (вытеснен; порядок
# ответа не судит); защиты ветки нет вовсе; commit status success вне check-runs.
# Сверяется код И строка причины — что напечатано, а не только «покраснел».
#
# ИСПОЛНЕНИЕ (ws#1019): случаи готовятся ОДИН раз — каталог на случай (ответы
# двойника, ведомость, ожидаемое), — затем матрица «сценарий × случай» (контроль и
# каждый мутант) гонится параллельно, CI_READ_INJECT_JOBS процессов (по умолчанию
# nproc). Двойник gh — один на все, без сети; ci-read.sh берёт свой mktemp, каталоги
# случаев только читаются. Прежде каждый мутант заново строил все случаи jq и гнал
# их подряд: шаг конвейера вырос до 100+ с и оборвал задание по пределу (прогон
# 38182137070).
#
# МУТАНТЫ (вторая половина доказательства): копия ci-read.sh с ровно одним
# дефектом, превращающим красное в зелёное, прогоняется тем же набором случаев;
# мутант обязан дать хотя бы одно расхождение (KILLED). Мутант, правка которого
# не легла в текст (образец не нашёлся), — VOID, а не «убит». Перечень:
#   paginate-dropped    — apip() без --paginate: читается первая страница;
#   status-failure-ok   — commit status failure/error отображён в success;
#   failset-<значение>  — значение убрано из FAILSET, по одному на каждое из шести;
#   draft-ignored       — черновик читается как готовый запрос;
#   guard-any-failure   — стражем считается любой failure черновика, без аннотации;
#   guard-title-any     — стражем считается ЛЮБАЯ аннотация (`.title != null`; N1
#                         check-verifier): на живой форме у упавшей проверки она есть;
#   supersede-dropped   — check-run вытесненного прогона судится наравне (ws#1019);
#   supersede-earliest  — последним считается САМЫЙ РАННИЙ прогон workflow;
#   supersede-event-dropped — событие выпало из ключа: push вытесняется pull_request;
#   runs-pending-all    — RUNS-PENDING судит и вытесненные прогоны;
#   supersede-key-name  — ключ workflow — имя, а не workflow_id (V1 приёмки);
#   supersede-run-number — последний по run_number, а не по created_at (V2);
#   supersede-id-only   — последний только по id (V5);
#   runs-pending-in-progress-only — RUNS-PENDING только при in_progress (V5);
#   narrow-latest-kept  — на не-черновике целевой прогон остаётся последним (д);
#   narrow-on-draft     — исключение целевого прогона применено и к черновику;
#   narrow-guard-dropped — на не-черновике целевым считается check_suite ЛЮБОЙ
#                         проверки failure, без аннотации стража (D2 check-verifier);
#   manual-skip-kept    — (е1) снято: skipped ручного прогона судится наравне;
#   manual-skip-no-pr   — проверка не-pull_request отброшена и без проверки того же имени
#                         из pull_request;
#   manual-drop-skipped-only — по (е1) отброшен только skipped, neutral — нет;
#   manual-skip-pr-event-too — отброшен и skipped самого прогона pull_request;
#   third-party-dropped — из (е1) выпало .ev != null: сторонний skipped отброшен;
#   drop-any-conclusion — форма круга 2 (⛔ check-verifier): отброшено ВСЁ не-pull_request,
#                         включая failure стороннего check-run без прогона;
#   drop-failure-too    — failure прогона не-pull_request отброшен при проверке из PR;
#   red-not-first       — (е2) снято: судится последняя по started_at, ранний красный
#                         другого check_suite закрыт поздним success;
#   null-suite-ignored  — check-run с check_suite null выпал из суда;
#   displaced-dropped   — (ж) снято: cancelled без проверок не судится, счёт суммой (ws#1216);
#   displaced-any-cancelled — RUN-DISPLACED и при проверках прогона (близнец краснеет);
#   required-out-dropped — набор обязательных вызывающему не пишется (ws#1215);
#   required-out-empty  — вызывающему пишется пустой набор при непустом;
#   rules-read-tolerated — отказ чтения наборов правил терпим: набор пуст, а не
#                         «не получен» (M2 check-verifier, ws#1215);
#   protection-read-tolerated — то же для отказа чтения защиты не вида «not protected»;
#   no-rule-e           — (е) снято целиком (прежняя форма «последний по имени»);
#   expect-compare-dropped — сверка числа снята: CHECKS-INCOMPLETE не выносится (ws#1097);
#   ledger-stale-dropped — строка LEDGER-STALE не печатается: занижение снова молчит (ws#1244);
#   rate-limit-dropped  — проверка лимита до чтения снята (урок 2026-10-16, ws#1110);
#   both-forms-checkrun-wins — у имени с обеими формами судится первая запись, красное
#                         и незавершённое не побеждают (прежняя форма слияния, ws#1113);
#   etag-fallback-dropped — отказ заглушки без `-i` не переводит чтение в безусловное;
#   etag-hit-blind      — любой ответ при условном чтении принят за 304: тело из кэша;
#   etag-hit-blind-any  — кэш отдаётся без запроса, едва ETag есть (ws#1113);
#   red-wins-while-running — красное при идущих снова 1: ожидание прервано на первом
#                         красном (ws#1110);
#   trunk-row-dropped-<ствол> — из ЖИВОЙ ведомости снята строка <ствол>/main
#                         (по одному на каждый из четырёх; урок corelib#111);
#   row-dropped-<репозиторий>-<база> — из ЖИВОЙ ведомости снята строка не-ствола
#                         (по одному на каждую; ws#1097: пары нет — код 2).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIVE="$HERE/ci-read-expected.tsv"   # живая ведомость; мутанты строк подменяют её копией
FX_N=68                             # различных проверок в фикстуре kacho-3140
FX="$HERE/ci-read-fixtures/kacho-3140"
JOBS="${CI_READ_INJECT_JOBS:-$(nproc 2>/dev/null || echo 4)}"
command -v jq >/dev/null 2>&1 || { echo "VOID: нет jq" >&2; exit 2; }
[ -r "$HERE/ci-read.sh" ] && [ -d "$FX" ] || { echo "VOID: нет $HERE/ci-read.sh или $FX" >&2; exit 2; }
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || { echo "VOID: CI_READ_INJECT_JOBS «$JOBS» не число" >&2; exit 2; }
# Предпосылка: фикстура несёт поля живой формы, которые читает ci-read.sh. Проверка без
# id выпадает из поиска стража молча — случаи на такой фикстуре судят не площадку.
jq -e '(.check_runs | length > 0) and all(.check_runs[]; (.id | type) == "number")' "$FX/check-runs.json" >/dev/null \
    || { echo "VOID: в $FX/check-runs.json есть проверка без id — фикстура не живой формы" >&2; exit 2; }
jq -e '(.workflow_runs | length > 0) and all(.workflow_runs[]; (.workflow_id | type) == "number" and (.created_at | type) == "string")' "$FX/runs.json" >/dev/null \
    || { echo "VOID: в $FX/runs.json есть прогон без workflow_id или created_at — фикстура не живой формы" >&2; exit 2; }
jq -e '.draft == false' "$FX/pull.json" >/dev/null || { echo "VOID: в $FX/pull.json нет draft: false" >&2; exit 2; }

T="$(mktemp -d "${TMPDIR:-/tmp}/ci-read-inject.XXXXXX")" || exit 2
# shellcheck disable=SC2154
trap '_rc=$?; rm -rf "$T" 2>/dev/null || rm -rf "$T" || echo "ПРЕДУПРЕЖДЕНИЕ: временный каталог $T не снят; код проверки $_rc сохранён" >&2; exit $_rc' EXIT

# Двойник gh — общий с пробой демона состояния: scripts/ci-read-fixtures/gh-twin.sh
# (там же форма ответа, страницы, живая форма аннотаций и условное чтение -i/If-None-Match).
if ! cp "$HERE/ci-read-fixtures/gh-twin.sh" "$T/gh" || ! chmod +x "$T/gh"; then echo "VOID: нет двойника gh-twin.sh" >&2; exit 2; fi
# Предпосылка двойника: без файла случая он отдаёт ЖИВУЮ форму — упавшей проверке
# аннотацию failure с пустым title и message выхода, отменённой — «canceled»,
# пропущенной — [], неизвестной — 404. Иначе случаи снова судят форму, которой у
# площадки нет.
mkdir -p "$T/pre"
echo '{"check_runs":[{"id":1,"status":"completed","conclusion":"failure"},{"id":2,"status":"completed","conclusion":"cancelled"},{"id":3,"status":"completed","conclusion":"skipped"}]}' > "$T/pre/check-runs.json"
pre() { CI_READ_FX="$T/pre" "$T/gh" api "repos/o/r/check-runs/$1/annotations" 2>/dev/null | jq -e "$2" >/dev/null 2>&1; }
{ pre 1 'any(.[]; .annotation_level == "failure" and .title == "" and .message == "Process completed with exit code 1.")' \
    && pre 2 'any(.[]; .annotation_level == "failure" and .title == "" and .message == "The operation was canceled.")' \
    && pre 3 '. == []' \
    && ! CI_READ_FX="$T/pre" "$T/gh" api repos/o/r/check-runs/9/annotations >/dev/null 2>&1; } \
    || { echo "VOID: двойник gh не отдаёт живую форму аннотаций" >&2; exit 2; }
# Предпосылка условного чтения (ws#1113): форма живого gh 2.100 — `-i` даёт строку
# статуса, заголовок Etag и пустую строку перед телом; совпавший If-None-Match — 304,
# код 1 и «gh: HTTP 304». Иначе случаи условного чтения судят форму, которой нет.
echo '{"x":1}' > "$T/pre/pull.json"
# ответ — в файл, затем разбор: grep -q в трубе под pipefail дал бы 141 писателю
CI_READ_FX="$T/pre" "$T/gh" api -i repos/o/r/pulls/1 > "$T/pre/200" 2>/dev/null
pre_e="$(tr -d '\r' < "$T/pre/200" | sed -n 's/^Etag: //p')"
{ [ "$(head -n 1 "$T/pre/200" | tr -d '\r')" = 'HTTP/2.0 200 OK' ] && [ -n "$pre_e" ] \
    && ! CI_READ_FX="$T/pre" "$T/gh" api -i -H "If-None-Match: $pre_e" repos/o/r/pulls/1 > "$T/pre/304" 2> "$T/pre/304.err" \
    && [ "$(head -n 1 "$T/pre/304" | tr -d '\r')" = 'HTTP/2.0 304 Not Modified' ] && [ "$(cat "$T/pre/304.err")" = 'gh: HTTP 304' ]; } \
    || { echo "VOID: двойник gh не отдаёт форму условного чтения (-i, If-None-Match → 304)" >&2; exit 2; }

# Исполнитель одной клетки матрицы: <сценарий ci-read> <живая ведомость> <каталог
# случая> <файл исхода>. Исход — строка «OK|FAIL TAB код»; при FAIL следом хвост вывода.
# Ведомость случая: файл ledger.tsv в каталоге случая, либо row (репозиторий TAB
# база) — копия ЖИВОЙ ведомости сценария с числом этой строки, заменённым на fxn.
cat > "$T/cell.sh" <<'CELL'
#!/usr/bin/env bash
S="$1"; LV="$2"; C="$3"; O="$4"
L="$C/ledger.tsv"
if [ -f "$C/row" ]; then
    L="$O.ledger"
    IFS=$'\t' read -r rr rb < "$C/row"
    awk -F'\t' -v OFS='\t' -v r="$rr" -v b="$rb" -v n="$(cat "$C/fxn")" \
        '!/^#/ && $1==r && $2==b {$3=n} {print}' "$LV" > "$L"
fi
# кэш условного чтения — свой у клетки: клетки идут параллельно и судят разные ответы;
# noinc — двойник в форме заглушки без `-i`
if [ -f "$C/noinc" ]; then export GH_TWIN_NO_INCLUDE=1; fi
# reqout — случай судит набор обязательных, отданный вызывающему (ws#1215): строка
# REQOUT с именами через «|» либо REQOUT-ABSENT, если файла нет
if [ -f "$C/reqout" ]; then rm -f "$O.req"; export CI_READ_REQUIRED_OUT="$O.req"; fi
out="$(CI_STATE_DIR="$O.state" CI_READ_GH_CONDITIONAL=1 CI_READ_GH="$GHX" CI_READ_FX="$C" CI_READ_EXPECTED="$L" bash "$S" "$(cat "$C/repo")" 3140 $(cat "$C/args" 2>/dev/null) 2>&1)"; code=$?
if [ -d "$C/2" ]; then  # второе чтение тем же кэшем условного чтения по ответам $C/2: судится оно
    out="$(CI_STATE_DIR="$O.state" CI_READ_GH_CONDITIONAL=1 CI_READ_GH="$GHX" CI_READ_FX="$C/2" CI_READ_EXPECTED="$L" bash "$S" "$(cat "$C/repo")" 3140 2>&1)"; code=$?
fi
rm -rf "$O.state"
if [ -f "$C/reqout" ]; then
    if [ -f "$O.req" ]; then out="$out"$'\n'"REQOUT"$'\t'"$(paste -sd'|' "$O.req")"; else out="$out"$'\n'"REQOUT-ABSENT"; fi
    rm -f "$O.req"
fi
pat="$(cat "$C/pat")"
# nopat — строка, которой в выводе быть НЕ должно (близнец сигнала, ws#1244 L4)
if [ "$code" -eq "$(cat "$C/code")" ] && { [ -z "$pat" ] || grep -qP "$pat" <<<"$out"; } && grep -qP "^VERDICT\t" <<<"$out" \
    && { [ ! -f "$C/nopat" ] || ! grep -qP "$(cat "$C/nopat")" <<<"$out"; }; then
    printf 'OK\t%s\n' "$code" > "$O"
else
    { printf 'FAIL\t%s\n' "$code"; tail -8 <<<"$out"; } > "$O"
fi
CELL
chmod +x "$T/cell.sh"
export GHX="$T/gh"

FXL="$T/ledger.fixture.tsv"           # ведомость случаев: строка — число фикстуры
printf 'PRO-Robotech/kacho\t1266\t%s\tфикстура kacho-3140\n' "$FX_N" > "$FXL"

# --- построение случаев: mk открывает каталог случая, edit правит его ответ, run
# записывает ожидаемое. Строятся ОДИН раз; исполняет их матрица ниже.
CASES="$T/cases"; mkdir -p "$CASES"; NC=0; SECTION=""; C=""
mk() { NC=$((NC + 1)); C="$CASES/$(printf '%03d' "$NC")"; mkdir -p "$C"; cp "$FX"/*.json "$C/"; }
edit() { jq "$2" "$C/$1" > "$C/$1.n" && mv "$C/$1.n" "$C/$1"; }
run() {  # run <имя> <ожидаемый код> <образец строки REASON|VOID либо пусто> [ведомость|row:<база>[:<число>]] [репозиторий]
    printf '%s' "$1" > "$C/name"; printf '%s' "$2" > "$C/code"; printf '%s' "$3" > "$C/pat"
    printf '%s' "${5:-PRO-Robotech/kacho}" > "$C/repo"; printf '%s' "$SECTION" > "$C/section"
    case "${4:-}" in
        row:*) r="${4#row:}"; printf '%s\t%s\n' "${5:-PRO-Robotech/kacho}" "${r%%:*}" > "$C/row"
               [ "${r#*:}" != "$r" ] && printf '%s' "${r#*:}" > "$C/fxn" || printf '%s' "$FX_N" > "$C/fxn" ;;
        "") cp "$FXL" "$C/ledger.tsv" ;;
        *) cp "$4" "$C/ledger.tsv" ;;
    esac
}
say() { SECTION="$*"; }
# одна проверка (первая по имени, имя в ответе единственное) завершена значением $1
one_concl() {
    mk; edit check-runs.json "(.check_runs | sort_by(.name) | .[0].name) as \$n | .check_runs |= map(.conclusion = (if .name == \$n then \"$1\" else .conclusion end))"
}

say "== контроль"
mk; run "полный зелёный, база свежая" 0 '^VERDICT\tgreen\t.*проверок 68 из 68'

say "== ведомость занижена — сигнал LEDGER-STALE, вердикт тот же (ws#1244 L4)"
# 2026-10-18: kaname/main записано 19 при 27 на голове, kacho/main — 68 при 74. Занижение молчало:
# голова с 20 из 27 читалась полной. Различных проверок на голове БОЛЬШЕ записанного — строка
# ведомости устарела; вердикт о голове не меняется (полна), сигнал — отдельной строкой.
printf 'PRO-Robotech/kacho\t1266\t%s\tзанижено\n' "$((FX_N - 1))" > "$T/ledger.low.tsv"
mk; run "68 при записанных 67: LEDGER-STALE с числом и строкой, зелёный" 0 "^LEDGER-STALE\tPRO-Robotech/kacho\t1266\tпроверок $FX_N при записанных $((FX_N - 1))" "$T/ledger.low.tsv"
mk; run "близнец: 68 при записанных 68 — сигнала нет" 0 '^VERDICT\tgreen\t.*проверок 68 из 68'; printf '%s' '^LEDGER-STALE' > "$C/nopat"
mk; edit pull.json '.draft = true'; run "близнец: черновик при занижении — полнота не судится, сигнала нет" 3 '' "$T/ledger.low.tsv"; printf '%s' '^LEDGER-STALE' > "$C/nopat"

say "== неполно и идёт — 3"
mk; edit check-runs.json '.check_runs |= (group_by(.name) | map(.[0]) | .[0:30])'
run "урок #3142: 30 из 68, всё видимое зелёное" 3 '^REASON\tCHECKS-INCOMPLETE\tпроверок 30 из 68'
mk; edit check-runs.json '.check_runs |= (sort_by(.name) | (.[0:3] | map(.status="in_progress" | .conclusion=null | .started_at="2099-01-01T00:00:00Z")) + .[3:])'
run "урок #3142: 68 из 68, три ещё идут" 3 '^REASON\tCI-PENDING\tне завершена: '
mk; edit runs.json '.workflow_runs[0] |= (.status="in_progress" | .conclusion=null)'
run "workflow run не завершён при завершённых check-runs" 3 '^REASON\tRUNS-PENDING\t'
mk; edit runs.json '.workflow_runs[0] |= (.status="queued" | .conclusion=null)'
run "workflow run queued (не in_progress) — тоже не завершён" 3 '^REASON\tRUNS-PENDING\t.*\(queued, run '

say "== база устарела — 4"
mk; edit branch.json '.commit.sha="1111111111111111111111111111111111111111"'
run "всё зелёное, база ушла вперёд" 4 '^REASON\tBASE-STALE\tmerge-base '

say "== красное — 1"
mk; edit check-runs.json '.check_runs |= (sort_by(.name) | (.[0:1] | map(.conclusion="failure")) + .[1:])'
run "одна проверка failure" 1 '^REASON\tCI-FAILED\tfailure: '
for c in cancelled timed_out action_required startup_failure stale; do
    one_concl "$c"; run "одна проверка $c" 1 "^REASON\\tCI-FAILED\\t$c: "
done
say "== красное при идущих — 3, ожидание не прерывается (ws#1110, владелец 2026-10-16)"
mk; edit check-runs.json '.check_runs |= (sort_by(.name) | (.[0:1] | map(.conclusion="failure")) + (.[1:2] | map(.status="in_progress" | .conclusion=null | .started_at="2099-01-01T00:00:00Z")) + .[2:])'
run "одна failure, другая ещё идёт — идёт, число красных названо" 3 '^VERDICT\trunning\t.*красных уже 1, задания идут'
mk; edit check-runs.json '.check_runs |= (sort_by(.name) | (.[0:1] | map(.conclusion="failure")) + .[1:])'
edit runs.json '.workflow_runs[0] |= (.status="in_progress" | .conclusion=null)'
run "одна failure, workflow run ещё идёт — идёт" 3 '^VERDICT\trunning\t.*красных уже 1'
mk; edit status.json '.statuses=[{context:"внешний контекст",state:"failure"}]'
run "commit status failure вне check-runs" 1 '^REASON\tCI-FAILED\tfailure: внешний контекст'
# 109 прогонов: исходные 70, 38 ранних повторов имён (success) и поздний failure
# имени — последним; страница 1 — первые 100 (все 68 имён, всё зелёное),
# страница 2 — 9, среди них failure. Без --paginate вердикт был бы green.
# $s и $i ниже — переменные jq, не оболочки.
mk
# shellcheck disable=SC2016
edit check-runs.json '(.check_runs | sort_by(.name)) as $s
    | .check_runs = .check_runs
        + [range(0; 38) as $i | $s[$i % ($s|length)] | .started_at = "2000-01-01T00:00:00Z"]
        + [$s[0] | .conclusion = "failure" | .started_at = "2099-01-01T00:00:00Z"]
    | .total_count = (.check_runs | length)'
jq '.check_runs = .check_runs[100:]' "$C/check-runs.json" > "$C/check-runs.json.p2"
edit check-runs.json '.check_runs = .check_runs[0:100]'
run "две страницы 100+9, поздний failure на второй" 1 '^REASON\tCI-FAILED\tfailure: '
mk; edit check-runs.json '.check_runs |= map(select(.name != "сводный вердикт (все проверки завершились и зелены)"))'
edit check-runs.json '.check_runs += [.check_runs[0] | .name="замена" ]'
run "обязательный контекст исчез, остальное завершено" 1 '^REASON\tREQUIRED-MISSING\t.*сводный вердикт'
mk; edit check-runs.json '.check_runs |= map(.conclusion = (if .name == "сводный вердикт (все проверки завершились и зелены)" then "skipped" else .conclusion end))'
run "обязательный контекст skipped" 1 '^REASON\tREQUIRED-NOT-SUCCESS\tобязательный контекст skipped'

mk; edit check-runs.json '.check_runs = .check_runs + [(.check_runs | sort_by(.name) | .[0]) | .conclusion="failure" | .started_at="2099-01-01T00:00:00Z"]'
run "повтор имени позже прежнего success — failure" 1 '^REASON\tCI-FAILED\tfailure: '

say "== вытесненный прогон того же workflow (ws#1019; урок kaname#709)"
# Workflow «сводный вердикт» фикстуры (run 38086061943, suite 103192606632) делается
# ПРЕЖНИМ прогоном (created_at раньше), рядом — новый прогон того же workflow и того
# же события, suite 999. Урок kaname#709: черновик перевели в ready, сводный вердикт
# целевого прогона черновика failure, полный прогон ещё идёт — его сводная проверка
# стартует последней и на голове её ещё нет.
OLDRUN=38086061943; OLDSUITE=103192606632
AGG_REQ="сводный вердикт (все проверки завершились и зелены)"   # обязательный контекст базы 1266
# shellcheck disable=SC2016
supersede() {  # supersede <заключение прежнего> <статус нового> <заключение нового|null> [событие прежнего] [id нового] [workflow_id нового]
    mk
    edit runs.json "(.workflow_runs |= map(if .id == $OLDRUN then .workflow_id = 5 | .event = \"${4:-pull_request}\" | .created_at = \"2026-10-10T21:00:00Z\" | .run_attempt = 1 | .run_number = 20 | .status = \"completed\" | .conclusion = \"$1\" end))
        | .workflow_runs += [{id: ${5:-38199999999}, name: \"сводный вердикт\", workflow_id: ${6:-5}, event: \"pull_request\", status: \"$2\", conclusion: $3, created_at: \"2026-10-10T22:00:00Z\", run_attempt: 1, run_number: 21, head_sha: .workflow_runs[0].head_sha, check_suite_id: 999}]"
    edit check-runs.json "(.check_runs |= map(if .check_suite.id == $OLDSUITE then .conclusion = \"$1\" end))"
}
new_agg() {  # проверка сводного вердикта в новом прогоне: <статус> <заключение|null> <started_at>
    # id новый, как у площадки: новый прогон — новая проверка (id + 1 000 000)
    edit check-runs.json ".check_runs += [(.check_runs[] | select(.check_suite.id == $OLDSUITE)) | .id += 1000000 | .check_suite.id = 999 | .status = \"$1\" | .conclusion = $2 | .started_at = \"$3\"]"
}
supersede failure in_progress null
run "прежний красный сводный черновика, полный того же workflow идёт" 3 '^VERDICT\trunning\t'
supersede failure in_progress null
run "вытеснение напечатано переписью" 3 '^CENSUS\tworkflow runs на голове: 11; последних по workflow и событию 8, вытеснено 3'
supersede success completed '"failure"'; new_agg completed '"failure"' 2026-10-10T22:30:00Z
run "близнец: последний полный красный" 1 '^REASON\tCI-FAILED\tfailure: сводный вердикт'
# Остаток ws#1019 (D2): на не-черновике полный красный прогон без аннотации стража
# — НЕ целевой. Проверка failure несёт id (как на площадке), аннотаций у неё нет;
# прежний прогон того же workflow зелёный. Сочти ci-read.sh целевым любой check_suite
# с failure — последним стал бы прежний зелёный, и голова читалась бы green.
supersede success completed '"failure"'; new_agg completed '"failure"' 2026-10-10T22:30:00Z
jq -e '[.check_runs[] | select(.check_suite.id == 999 and .conclusion == "failure") | .id | type] == ["number"]' "$C/check-runs.json" >/dev/null \
    || { echo "VOID: у проверки failure нового прогона нет id — случай D2 не судит живую форму" >&2; exit 2; }
ls "$C"/annotations*.json >/dev/null 2>&1 && { echo "VOID: в случае D2 лежат аннотации" >&2; exit 2; }
run "не черновик: полный красный прогон, у проверки есть id, аннотации стража нет" 1 '^REASON\tCI-FAILED\tfailure: сводный вердикт'
supersede failure completed '"success"'; new_agg completed '"success"' 2026-10-10T22:30:00Z
run "близнец: последний полный зелёный, прежний черновой красный" 0 '^VERDICT\tgreen\t'
supersede failure completed '"success"'; new_agg completed '"success"' 2026-10-10T22:30:00Z
edit check-runs.json ".check_runs |= map(if .check_suite.id == $OLDSUITE then .started_at = \"2099-01-01T00:00:00Z\" end)"
run "вытесненный прогон судится по прогону, а не по started_at проверки" 0 '^VERDICT\tgreen\t'
supersede failure completed '"success"'; new_agg completed '"success"' 2026-10-10T22:30:00Z
edit runs.json ".workflow_runs |= map(if .id == $OLDRUN then .status = \"in_progress\" | .conclusion = null end)"
run "вытесненный прогон ещё идёт, последний завершён зелёным" 0 '^VERDICT\tgreen\t'
supersede failure completed '"success"' push; new_agg completed '"success"' 2026-10-10T22:30:00Z
edit runs.json ".workflow_runs |= map(if .id == $OLDRUN then .status = \"in_progress\" | .conclusion = null end)"
run "прогон push того же workflow pull_request-прогоном не вытесняется (его failure красный по (е2), но прогон идёт — 3)" 3 '^REASON\tRUNS-PENDING\t.*run 38086061943'
# V1: одноимённый workflow другого файла (workflow_id 6) позже — не вытесняет
supersede failure completed '"success"' pull_request 38199999999 6
run "одноимённый workflow другого файла не вытесняет: красное прежнего судится" 1 '^REASON\tCI-FAILED\tfailure: сводный вердикт'
# V2: новый позже по created_at, но с меньшим run_number
supersede failure completed '"success"'; new_agg completed '"success"' 2026-10-10T22:30:00Z
edit runs.json '.workflow_runs |= map(if .check_suite_id == 999 then .run_number = 3 end)'
run "последний — по created_at, а не по run_number" 0 '^VERDICT\tgreen\t'
# V5: новый позже по created_at, но с меньшим id
supersede failure completed '"success"' pull_request 38000000000; new_agg completed '"success"' 2026-10-10T22:30:00Z
run "последний — по created_at, а не по id" 0 '^VERDICT\tgreen\t'

say "== ручной прогон workflow_dispatch на голове запроса (ws#1049; урок kaname#765)"
# Живая форма (kaname#765, голова d4cb8ca, 2026-10-12): прогон workflow_dispatch того
# же workflow (тот же workflow_id, своё событие и check_suite) рядом с прогоном
# pull_request; сводный вердикт запроса в нём skipped по условию на событие и стартует
# позже — «последний по имени». Здесь: workflow «сводный вердикт» фикстуры получает
# ручной прогон (suite 997), его проверки — копии прогона pull_request.
# shellcheck disable=SC2016
manual() {  # manual <заключение проверок ручного прогона> [started_at] [событие] — прогон pull_request не трогается
    mk
    edit runs.json ".workflow_runs += [{id: 38199999997, name: \"сводный вердикт\", workflow_id: 336467769, event: \"${3:-workflow_dispatch}\", status: \"completed\", conclusion: \"success\", created_at: \"2026-10-10T22:00:00Z\", run_attempt: 1, run_number: 22, head_sha: .workflow_runs[0].head_sha, check_suite_id: 997}]"
    edit check-runs.json ".check_runs += [(.check_runs[] | select(.check_suite.id == $OLDSUITE)) | .id += 3000000 | .check_suite.id = 997 | .status = \"completed\" | .conclusion = \"$1\" | .started_at = \"${2:-2026-10-10T22:01:00Z}\"]"
}
# сторонний check-run сводного вердикта: тот же name, workflow run у его check_suite нет
foreign() {  # foreign <заключение> <started_at> <check_suite: число | null>
    mk
    edit check-runs.json ".check_runs += [(.check_runs[] | select(.check_suite.id == $OLDSUITE)) | .id += 4000000 | .check_suite = ($3 | if . == null then null else {id: .} end) | .app = {slug: \"external-ci\"} | .status = \"completed\" | .conclusion = \"$1\" | .started_at = \"$2\"]"
}
manual skipped
run "ручной прогон: skipped агрегата при success того же из pull_request" 0 '^VERDICT\tgreen\t.*проверок 68 из 68'
manual skipped
run "ручной прогон: отброшенный skipped напечатан переписью" 0 '^CENSUS\tskipped/neutral/success прогона не-pull_request при проверке того же имени из pull_request не судится: сводный вердикт \(все проверки завершились и зелены\) \(workflow_dispatch, skipped'
manual neutral
run "ручной прогон: neutral позже success из pull_request отброшен" 0 '^VERDICT\tgreen\t.*проверок 68 из 68'
manual success
run "ручной прогон: success позже success из pull_request" 0 '^VERDICT\tgreen\t.*проверок 68 из 68'
manual failure
run "ручной failure позже success из pull_request — красное" 1 "^REASON\tCI-FAILED\tfailure: \Q$AGG_REQ\E"
manual failure 2000-01-01T00:00:00Z push
run "push failure раньше success из pull_request — красное" 1 "^REASON\tCI-FAILED\tfailure: \Q$AGG_REQ\E"
manual failure 2026-10-10T22:01:00Z pull_request_target
run "pull_request_target failure позже success из pull_request — красное" 1 "^REASON\tCI-FAILED\tfailure: \Q$AGG_REQ\E"
manual success
edit check-runs.json ".check_runs |= map(if .check_suite.id == $OLDSUITE then .conclusion = \"failure\" end)"
run "pr-fail-disp-success-later (3): поздний success ручного не закрывает failure из pull_request" 1 "^REASON\tCI-FAILED\tfailure: \Q$AGG_REQ\E"
foreign failure 2000-01-01T00:00:00Z 996
run "сторонний check-run failure того же имени (suite без workflow run) — красное" 1 "^REASON\tCI-FAILED\tfailure: \Q$AGG_REQ\E"
foreign failure 2000-01-01T00:00:00Z null
run "сторонний check-run failure того же имени, check_suite null — красное" 1 "^REASON\tCI-FAILED\tfailure: \Q$AGG_REQ\E"
foreign skipped 2026-10-10T22:01:00Z 996
run "сторонний check-run skipped позже success из pull_request не отбрасывается" 1 "^REASON\tREQUIRED-NOT-SUCCESS\tобязательный контекст skipped: \Q$AGG_REQ\E"
manual skipped
edit runs.json ".workflow_runs |= map(if .id == $OLDRUN then .status = \"in_progress\" | .conclusion = null end)"
edit check-runs.json ".check_runs |= map(if .check_suite.id == $OLDSUITE then .status = \"in_progress\" | .conclusion = null end)"
run "ручной skipped при идущем агрегате pull_request — ждать" 3 "^REASON\tCI-PENDING\tне завершена: \Q$AGG_REQ\E"
mk
edit runs.json ".workflow_runs |= map(if .id == $OLDRUN then .event = \"workflow_dispatch\" end)"
edit check-runs.json ".check_runs |= map(if .check_suite.id == $OLDSUITE then .conclusion = \"skipped\" end)"
run "близнец: skipped ручного прогона без прогона pull_request — красное" 1 "^REASON\tREQUIRED-NOT-SUCCESS\tобязательный контекст skipped: \Q$AGG_REQ\E"
mk
edit runs.json ".workflow_runs |= map(if .id == $OLDRUN then .event = \"workflow_dispatch\" end)"
edit check-runs.json ".check_runs |= map(if .check_suite.id == $OLDSUITE then .conclusion = \"failure\" end)"
run "близнец: failure ручного прогона без прогона pull_request — красное" 1 "^REASON\tCI-FAILED\tfailure: \Q$AGG_REQ\E"

# Аннотации проверки в живой форме (снимок kaname check-run 114579859902, 2026-10-12):
# у стража три — failure «Process completed with exit code 1.» с ПУСТЫМ title, сам
# страж и notice раннера; страж — не первый в списке. <аргументы> — тройки level title message.
ann_live() {
    jq -cn --args '[$ARGS.positional as $a | range(0; $a | length; 3) as $i
        | {path: ".github", blob_href: "", start_line: (72 + $i), start_column: null, end_line: (72 + $i), end_column: null,
           annotation_level: $a[$i], title: $a[$i + 1], message: $a[$i + 2], raw_details: ""}]' "$@"
}
EXIT1="Process completed with exit code 1."
guard_ann() {  # guard_ann <message стража> — живая тройка аннотаций стража
    ann_live failure "" "$EXIT1" failure "черновик не вливается" "$1" notice "" "runner image notice"
}

say "== целевой прогон на не-черновике (ws#1019, (д) ci-read.sh)"
# Workflow «ci» фикстуры (run 38086061971, suite 103192606701) — прежний ПОЛНЫЙ
# прогон с build failure; поздний ЦЕЛЕВОЙ прогон того же workflow (suite 998): его
# проверки — копии полного со skipped, плюс страж «сводный вердикт ci» failure с
# аннотацией. На не-черновике целевой не вытесняет полный: красное build судится.
CIRUN=38086061971; CISUITE=103192606701; BUILD="build · vet · gofmt"
narrow() {
    mk
    edit runs.json "(.workflow_runs |= map(if .id == $CIRUN then .workflow_id = 7 | .created_at = \"2026-10-10T21:00:00Z\" | .conclusion = \"failure\" end))
        | .workflow_runs += [{id: 38199999998, name: \"ci\", workflow_id: 7, event: \"pull_request\", status: \"completed\", conclusion: \"failure\", created_at: \"2026-10-10T23:00:00Z\", run_attempt: 1, head_sha: .workflow_runs[0].head_sha, check_suite_id: 998}]"
    jq --arg b "$BUILD" ".check_runs |= map(if .check_suite.id == $CISUITE and .name == \$b then .conclusion = \"failure\" end)
        | .check_runs += [(.check_runs[] | select(.check_suite.id == $CISUITE)) | .id += 2000000 | .check_suite.id = 998 | .conclusion = \"skipped\" | .started_at = \"2026-10-10T23:01:00Z\"]
        | .check_runs += [{id: 778, name: \"сводный вердикт ci\", status: \"completed\", conclusion: \"failure\", started_at: \"2026-10-10T23:02:00Z\", completed_at: \"2026-10-10T23:03:00Z\", check_suite: {id: 998}}]" \
        "$C/check-runs.json" > "$C/cr.n" && mv "$C/cr.n" "$C/check-runs.json"
    guard_ann "целевой прогон" > "$C/annotations.778.json"
}
narrow; jq --arg b "$BUILD" -e '[.check_runs[] | select(.name == $b)] | length == 2' "$C/check-runs.json" >/dev/null \
    || { echo "VOID: в фикстуре нет проверки «$BUILD» в workflow ci" >&2; exit 2; }
run "не черновик: поздний целевой не вытесняет красное полного" 1 "^REASON\tCI-FAILED\tfailure: \Q$BUILD\E"
narrow; edit pull.json '.draft = true'
run "близнец — черновик: судится поздний целевой" 5 '^VERDICT\ttargeted-green\t'

say "== черновик — целевой прогон (ws#1013)"
AGG="сводный вердикт (все проверки завершились и зелены)"
# черновик: 20 проверок skipped (не выбраны), страж — failure с аннотацией
draft() {
    mk; edit pull.json '.draft = true'
    jq --arg a "$AGG" '.check_runs |= (sort_by(.name) | map(
          .id = (if .name == $a then 777 else .id end)
        | .conclusion = (if .name == $a then "failure"
            elif (.name | test("^(юниты|integration|e2e|unit|build) ")) then "skipped"
            else .conclusion end)))' "$C/check-runs.json" > "$C/cr.n" && mv "$C/cr.n" "$C/check-runs.json"
    guard_ann "целевой прогон: 9 заданий из 27" > "$C/annotations.777.json"
}
draft; run "черновик: исполненное зелёное, страж вынес вердикт" 5 '^VERDICT\ttargeted-green\t.*ЦЕЛЕВОЙ, не полный'
draft; rm "$C/annotations.777.json"   # аннотации — живая форма двойника по заключению
run "черновик: failure без аннотации стража — настоящий отказ" 1 "^REASON\tCI-FAILED\tfailure: \Q$AGG\E"
# N1 (check-verifier): у КАЖДОЙ упавшей проверки площадка отдаёт аннотацию failure с
# пустым title — стражем она не делает. Сочти ci-read.sh стражем любую аннотацию,
# этот случай стал бы 5 targeted-green, а на не-черновике красное полного — green.
draft; ann_live failure "" "$EXIT1" notice "" "runner image notice" > "$C/annotations.777.json"
jq -e 'length > 0 and any(.[]; .annotation_level == "failure" and .title == "") and all(.[]; .title != "черновик не вливается")' "$C/annotations.777.json" >/dev/null \
    || { echo "VOID: случай N1 не несёт аннотации failure с пустым title" >&2; exit 2; }
run "черновик: failure, аннотация «$EXIT1» с пустым title, стража нет (N1)" 1 "^REASON\tCI-FAILED\tfailure: \Q$AGG\E"
draft; edit check-runs.json '.check_runs |= map(.conclusion = (if .name == "build · vet · gofmt" then "failure" else .conclusion end))'
run "черновик: страж есть, выбранное задание failure" 1 '^REASON\tCI-FAILED\tfailure: build · vet · gofmt'
draft; jq --arg a "$AGG" '.check_runs |= map(.status = (if .name == $a then "in_progress" else .status end) | .conclusion = (if .name == $a then null else .conclusion end))' "$C/check-runs.json" > "$C/cr.n" && mv "$C/cr.n" "$C/check-runs.json"
run "черновик: страж ещё идёт" 3 '^REASON\tDRAFT-GUARD-PENDING\t'
draft; edit pull.json '.draft = false'
run "не черновик: аннотация стражем не делает" 1 "^REASON\tCI-FAILED\tfailure: \Q$AGG\E"

say "== не прочитано — 2"
mk; echo 'gh: HTTP 502 Bad Gateway' > "$C/check-runs.json.err"
run "площадка не отдала check-runs" 2 '^VOID\tcheck-runs на '
mk; jq -n '{resources: {core: {limit: 5000, remaining: 5, reset: 1760620800}, graphql: {limit: 5000, remaining: 4000, reset: 1760620800}}}' > "$C/rate_limit.json"
run "лимит REST исчерпан (урок 2026-10-16) — не выполнилось со временем сброса" 2 '^REASON\tRATE-LIMIT\tлимит REST: остаток 5 из 5000 < порога 100, сброс в [0-9]{2}:[0-9]{2}'
mk; jq -n '{resources: {core: {limit: 5000, remaining: 100, reset: 1760620800}, graphql: {limit: 5000, remaining: 4000, reset: 1760620800}}}' > "$C/rate_limit.json"
run "близнец: остаток ровно на пороге — чтение идёт, полный зелёный" 0 '^VERDICT\tgreen\t.*проверок 68 из 68'
mk; grep -v '^PRO-Robotech/kacho	1266	' "$FXL" > "$T/ledger.nopair.tsv"
run "пары kacho/1266 нет в ведомости" 2 '^VOID\tпары PRO-Robotech/kacho / 1266 нет' "$T/ledger.nopair.tsv"

say "== живая ведомость: у ствола каждого нашего репозитория строка есть"
# Стволы — kacho · kaname · corelib (00-kacho-core ban20-scope-is-our-trunks) и сам
# воркспейс. Фикстура та же (68 различных проверок), меняются репозиторий и база
# запроса — main; строки берутся из ЖИВОЙ ведомости сценария, число строки ствола в
# копии заменяется числом фикстуры (судится присутствие, а не набор workflow ствола).
# Строки нет — замене нечего менять, ci-read.sh отвечает 2, и случай краснеет
# (урок corelib#111: код 2 «пары нет в ведомости»).
TRUNKS="kacho kaname corelib kacho-workspace"
for tr in $TRUNKS; do
    mk; edit pull.json '.base.ref = "main"'
    run "строка PRO-Robotech/$tr / main в ведомости" 0 "^VERDICT\tgreen\t.*проверок $FX_N из $FX_N" "row:main" "PRO-Robotech/$tr"
done

say "== живая ведомость: каждая строка — пара есть и число сверяется (ws#1097)"
# Перечень строк — обходом живой ведомости, а не выпиской: строка эпика заводится и
# снимается вместе с эпиком, и случаи с мутантами идут за ней сами. Ноль строк —
# отказ, а не зелёное. На каждую строку два случая: число строки = числу фикстуры —
# зелёное (пара найдена ровно по репозиторию И базе); на 1 больше — CHECKS-INCOMPLETE
# «проверок 68 из 69» (сверка числа, а не одно присутствие). Мутант строки — та же
# строка снята из копии ведомости: случай «пара есть» обязан дать код 2 и покраснеть.
ROWS="$T/rows.tsv"
awk -F'\t' '!/^#/ && NF >= 3 && $3 ~ /^[1-9][0-9]*$/ {print $1 "\t" $2}' "$LIVE" | sort -u > "$ROWS"
[ -s "$ROWS" ] || { echo "VOID: в живой ведомости $LIVE строк ноль — судить нечего" >&2; exit 2; }
echo "  строк живой ведомости: $(wc -l < "$ROWS") ($(grep -vc $'\tmain$' "$ROWS") не-ствол)"
while IFS=$'\t' read -r rr rb; do
    mk; edit pull.json ".base.ref = \"$rb\""
    run "строка $rr / $rb: пара есть" 0 "^VERDICT\tgreen\t.*проверок $FX_N из $FX_N" "row:$rb" "$rr"
    mk; edit pull.json ".base.ref = \"$rb\""
    run "строка $rr / $rb: число сверяется" 3 "^REASON\tCHECKS-INCOMPLETE\tпроверок $FX_N из $((FX_N + 1))" "row:$rb:$((FX_N + 1))" "$rr"
done < "$ROWS"

say "== сводный вердикт commit status вместо check-run (ws#1113): обе формы"
# Форма status выводится из той же фикстуры, а не копией: проверка «$AGG_REQ» и прогон
# её workflow «сводный вердикт» сняты, тот же контекст — commit status (как его пишет
# площадка: context, state, created_at, updated_at). Различных имён по-прежнему 68.
# Имя в образце — \Q…\E: скобки в нём — не группа регулярного выражения.
status_form() {  # status_form <state commit status> — в каталоге случая $C
    edit check-runs.json ".check_runs |= map(select(.name != \"$AGG_REQ\"))"
    edit runs.json '.workflow_runs |= map(select(.name != "сводный вердикт"))'
    edit status.json ".state = \"$1\" | .statuses = [{context: \"$AGG_REQ\", state: \"$1\", created_at: \"2026-10-10T21:48:47Z\", updated_at: \"2026-10-10T21:48:47Z\"}]"
}
mk; status_form success
jq -e --arg n "$AGG_REQ" '[.check_runs[] | select(.name == $n)] | length == 0' "$C/check-runs.json" >/dev/null \
    || { echo "VOID: форма status — проверка «$AGG_REQ» осталась check-run" >&2; exit 2; }
run "форма status: сводный вердикт success" 0 '^VERDICT\tgreen\t.*проверок 68 из 68'
mk; status_form pending
run "форма status: сводный вердикт pending — идёт" 3 "^REASON\tCI-PENDING\tне завершена: \Q$AGG_REQ\E"
mk; status_form failure
run "форма status: сводный вердикт failure" 1 "^REASON\tREQUIRED-NOT-SUCCESS\tобязательный контекст failure: \Q$AGG_REQ\E"
mk; status_form error
run "форма status: сводный вердикт error — красное" 1 "^REASON\tCI-FAILED\tfailure: \Q$AGG_REQ\E"
mk; status_form success; edit status.json '.state = "pending" | .statuses = []'
run "форма status: статус ещё не выставлен — идёт, не REQUIRED-MISSING" 3 "^REASON\tCI-PENDING\tобязательный контекст ещё не появился: \Q$AGG_REQ\E"
# обе формы разом (переход): check-run прежней формы и commit status новой — одно имя
both() {  # both <заключение check-run> <state commit status>
    mk; edit check-runs.json ".check_runs |= map(if .name == \"$AGG_REQ\" then .conclusion = \"$1\" end)"
    edit status.json ".statuses = [{context: \"$AGG_REQ\", state: \"$2\", created_at: \"2026-10-10T21:50:00Z\", updated_at: \"2026-10-10T21:50:00Z\"}]"
}
both success failure
run "обе формы: check-run success, status failure — красное не закрыто" 1 "^REASON\tCI-FAILED\tfailure: \Q$AGG_REQ\E"
both success pending
run "обе формы: check-run success, status pending — идёт" 3 "^REASON\tCI-PENDING\tне завершена: \Q$AGG_REQ\E"
both failure success
run "обе формы: check-run failure, status success — красное" 1 "^REASON\tCI-FAILED\tfailure: \Q$AGG_REQ\E"
both success success
run "обе формы: обе success — имя одно, 68 из 68" 0 '^VERDICT\tgreen\t.*проверок 68 из 68'

say "== условное чтение If-None-Match (ws#1113): 304 не расходует лимит и не прячет смену"
# Второе чтение тем же кэшем — по ответам $C/2: неизменное приходит 304 и берётся из
# кэша; изменившееся — 200 с новым телом. Кэш, отдающий прежнее тело при сменившемся
# ответе, прочёл бы голову по устаревшему.
again() { mkdir -p "$C/2"; cp "$C"/*.json "$C/2/"; }
mk; again
run "повтор без смены: тот же зелёный, условных 6, из кэша 6" 0 '^ci-read: условных чтений 6, не изменилось 6$'
mk; again; jq '.commit.sha="1111111111111111111111111111111111111111"' "$C/branch.json" > "$C/2/branch.json"
run "между чтениями база ушла вперёд — 4, кэш не прячет" 4 '^REASON\tBASE-STALE\tmerge-base '
mk; again; jq --arg n "$AGG_REQ" '.statuses = [{context: $n, state: "failure"}]' "$C/status.json" > "$C/2/status.json"
run "между чтениями commit status стал failure — 1" 1 "^REASON\tCI-FAILED\tfailure: \Q$AGG_REQ\E"
mk; again; jq '.draft = true' "$C/pull.json" > "$C/2/pull.json"
run "между чтениями запрос стал черновиком — читается черновиком" 3 '^REASON\tDRAFT-GUARD-PENDING\t'
mk; : > "$C/noinc"
run "заглушка без -i (форма check-09): отказ на -i — чтение без условия, зелёное" 0 '^VERDICT\tgreen\t.*проверок 68 из 68'

say "== вытеснение в группе concurrency (ws#1216; захват kacho#3296 @5a586e18)"
FX6="$HERE/ci-read-fixtures/kacho-3296"
L6="$T/ledger.3296.tsv"; printf 'PRO-Robotech/kacho\tmain\t68\tстрока ствола на 2026-10-19\n' > "$L6"
PP_SUITE=106089981440; PP_RUN=39149502546
mk6() { NC=$((NC + 1)); C="$CASES/$(printf '%03d' "$NC")"; mkdir -p "$C"; cp "$FX6"/*.json "$C/"; cp -r "$FX6/wf" "$C/wf"; }
# одна строка сводного вердикта success — нехватка видна только причиной (ж)
agg_green() { edit check-runs.json '.check_runs |= map(if .name == "сводный вердикт (все проверки завершились и зелены)" then .conclusion = "success" end)'; edit runs.json '.workflow_runs |= map(if .name == "сводный вердикт" then .conclusion = "success" end)'; }
# три проверки прогона production-posture с исходом <c> (имена — из файла workflow)
pp_checks() {
    edit runs.json ".workflow_runs |= map(if .id == $PP_RUN then .conclusion = \"$1\" end)"
    edit check-runs.json "(.check_runs | max_by(.id).id) as \$m | .check_runs += [range(3) as \$i | {id: (\$m + 1 + \$i), name: ([\"выбор затронутого (posture)\", \"stack dev-prod boots (kind, production posture)\", \"stack own boots (kind, production posture)\"][\$i]), status: \"completed\", conclusion: (if \$i == 2 then \"$1\" else \"success\" end), started_at: \"2026-10-18T17:30:00Z\", completed_at: \"2026-10-18T17:40:00Z\", check_suite: {id: $PP_SUITE}}] | .total_count = (.check_runs | length)"
}
mk6
run "как есть: production-posture вытеснен, три имени не появились" 1 '^REASON\tRUN-DISPLACED\tproduction-posture \(\.github/workflows/production-posture\.yml, pull_request, run 39149502546, check_suite 106089981440\): cancelled без единой проверки.*не появились 3 из 3: выбор затронутого \(posture\); stack dev-prod boots \(kind, production posture\); stack own boots \(kind, production posture\)' "$L6"
mk6; agg_green
run "один факт: сводный вердикт success — 71 из 68 не зелёное, причина (ж)" 1 '^VERDICT\tred\tкод 1; причин 1; проверок 71 из 68' "$L6"
mk6; agg_green; rm -r "$C/wf"
run "файла workflow на голове нет — причина та же, имена не выведены" 1 '^REASON\tRUN-DISPLACED\tproduction-posture .*не выведены: файл \.github/workflows/production-posture\.yml на голове не прочитан' "$L6"
mk6; agg_green; pp_checks success
run "близнец: прогон с исходом, его проверки есть — зелёное" 0 '^VERDICT\tgreen\t.*проверок 74 из 68' "$L6"
mk6; agg_green; pp_checks cancelled
run "близнец: cancelled С проверками — судятся они, не (ж)" 1 '^CENSUS\tworkflow runs на голове: 8; .*cancelled без проверок 0$' "$L6"

say "== набор обязательных — вызывающему (ws#1215: merge-readiness, путь базы без контекстов)"
mk; : > "$C/reqout"
run "набор отдан: обязательный контекст защиты базы" 0 "^REQOUT\t\Q$AGG_REQ\E$"
mk; : > "$C/reqout"; rm "$C/protection.json"; echo 'gh: Branch not protected (HTTP 404)' > "$C/protection.json.err"
run "защиты нет, наборов правил нет: набор отдан пустым — установленный ноль" 0 '^REQOUT\t$'
mk; : > "$C/reqout"; rm "$C/protection.json"; echo 'gh: Branch not protected (HTTP 404)' > "$C/protection.json.err"
jq -n --arg n "$AGG_REQ" '[{type: "required_status_checks", parameters: {required_status_checks: [{context: $n}]}}]' > "$C/rules.json"
run "защиты нет, контекст из набора правил: отдан" 0 "^REQOUT\t\Q$AGG_REQ\E$"
# не прочитано — не ноль: отказ чтения защиты (не «not protected») либо наборов
# правил — VOID, и файла набора нет (пустой файл читался бы установленным нулём)
mk; : > "$C/reqout"; echo 'gh: HTTP 502 Bad Gateway' > "$C/rules.json.err"
run "наборы правил не прочитаны (HTTP 502) — VOID" 2 '^VOID\tнаборы правил ветки 1266 не прочитаны: '
mk; : > "$C/reqout"; echo 'gh: HTTP 502 Bad Gateway' > "$C/rules.json.err"
run "наборы правил не прочитаны — файла набора нет" 2 '^REQOUT-ABSENT$'
mk; : > "$C/reqout"; rm "$C/protection.json"; echo 'gh: HTTP 502 Bad Gateway' > "$C/protection.json.err"
run "защита не прочитана (HTTP 502, не «not protected») — VOID" 2 '^VOID\tзащита ветки 1266 не прочитана: '
mk; : > "$C/reqout"; rm "$C/protection.json"; echo 'gh: HTTP 502 Bad Gateway' > "$C/protection.json.err"
run "защита не прочитана — файла набора нет" 2 '^REQOUT-ABSENT$'

say "== близнецы — молчат"
mk; edit check-runs.json '.check_runs = [(.check_runs | sort_by(.name) | .[0]) | .conclusion="failure" | .started_at="2000-01-01T00:00:00Z"] + .check_runs'
run "прежний failure первым в ответе, последний success" 0 '^VERDICT\tgreen\t'
mk; edit check-runs.json '.check_runs += [(.check_runs | sort_by(.name) | .[0]) | .conclusion="failure" | .started_at="2000-01-01T00:00:00Z"]'
run "прежний failure последним в ответе, последний по времени success" 0 '^VERDICT\tgreen\t'
mk; rm "$C/protection.json"; echo 'gh: Branch not protected (HTTP 404)' > "$C/protection.json.err"
run "защиты ветки нет вовсе" 0 '^CENSUS\tзащиты ветки 1266 нет'
mk; edit status.json '.statuses=[{context:"внешний контекст",state:"success"}]'
run "commit status success вне check-runs" 0 '^VERDICT\tgreen\t.*проверок 69 из 68'

# --- сценарии: контроль и мутанты. Мутант ci-read.sh: <имя> TAB <sed-выражение>;
# мутант ведомости: строка ствола снята из копии живой ведомости. Правка, не
# легшая в текст, — VOID, а не «убит».
SC="$T/scen"; mkdir -p "$SC"; void=0
ln -s "$HERE/lib" "$SC/lib"   # мутант лежит в $SC и берёт lib/gh-rate.sh рядом с собой
printf 'control\t%s\t%s\n' "$HERE/ci-read.sh" "$LIVE" > "$SC/list"
while IFS=$'\t' read -r name expr; do
    M="$SC/ci-read.$name.sh"
    sed -e "$expr" "$HERE/ci-read.sh" > "$M"
    if cmp -s "$M" "$HERE/ci-read.sh"; then
        void=$((void + 1)); echo "  MUTANT $name → RESULT VOID (правка не легла: образец не найден)"; continue
    fi
    printf '%s\t%s\t%s\n' "$name" "$M" "$LIVE" >> "$SC/list"
done <<'MUT'
paginate-dropped	/^apip()/s/ --paginate//
status-failure-ok	/state=="pending" then ""/s/else "failure" end/else "success" end/
failset-failure	/^FAILSET=/s/"failure",//
failset-cancelled	/^FAILSET=/s/,"cancelled"//
failset-timed_out	/^FAILSET=/s/,"timed_out"//
failset-action_required	/^FAILSET=/s/,"action_required"//
failset-startup_failure	/^FAILSET=/s/,"startup_failure"//
failset-stale	/^FAILSET=/s/,"stale"//
draft-ignored	/DRAFT="$(jq -r/s/.draft == true/.draft == "never"/
guard-any-failure	/any(.\[\]; .title==$t)/s/any(.\[\]; .title==$t)/true/
guard-title-any	/any(.\[\]; .title==$t)/s/.title==$t/.title != null/
supersede-dropped	/select((.check_suite.id \/\/ null) as $i/s/$s | index($i) | not/true/
supersede-earliest	/if ($full | length) > 0 then ($full | last) else last end/s/($full | last) else last end/($full | first) else first end/
supersede-event-dropped	/group_by(\[(.workflow_id/s/, .event\])/])/
runs-pending-all	/reason RUNS-PENDING/s/'\.latest\[\]|select/'.superseded[], .latest[]|select/
supersede-key-name	/group_by(\[(.workflow_id/s/(.workflow_id \/\/ .path \/\/ .name)/.name/
supersede-run-number	/map(sort_by(\[(.created_at/s/(.created_at \/\/ "")/(.run_number \/\/ 0)/
supersede-id-only	/map(sort_by(\[(.created_at/s/sort_by(\[(.created_at \/\/ ""), .id\])/sort_by([.id])/
runs-pending-in-progress-only	/reason RUNS-PENDING/s/select(.status!="completed")/select(.status=="in_progress")/
narrow-latest-kept	/$nar | index($c) | not/s/$nar | index($c) | not/true/
narrow-on-draft	/^if \[ "$DRAFT" != true \]; then$/s/"$DRAFT" != true/true/
narrow-guard-dropped	/"$gsuite" != null ] || continue/,/if guarded/s/if guarded "$gid" "$gname"/if true/
manual-skip-kept	/\.drop = (\$pr and/s/\.drop = (\$pr and/.drop = (false and/
manual-skip-no-pr	/\.drop = (\$pr and/s/\.drop = (\$pr and/.drop = (true and/
manual-drop-skipped-only	/\.drop = (\$pr and/s/IN("skipped", "neutral", "success")/IN("skipped")/
manual-skip-pr-event-too	/\.drop = (\$pr and/s/ and \.ev != "pull_request"/ and true/
third-party-dropped	/\.drop = (\$pr and/s/ and \.ev != null//
drop-any-conclusion	/\.drop = (\$pr and/s/ and \.ev != null and \.ev != "pull_request" and .*$/ and .ev != "pull_request")))/
drop-failure-too	/\.drop = (\$pr and/s/IN("skipped", "neutral", "success")/IN("skipped", "neutral", "success", "failure")/
red-not-first	/if (\$red | length) > 0/s/if (\$red | length) > 0/if false/
null-suite-ignored	/map(\.ev = \$ev\[/s/map(\.ev = /map(select(.check_suite != null) | .ev = /
ledger-stale-dropped	/^    printf 'LEDGER-STALE/s/^    printf /    : printf /
expect-compare-dropped	/then reason CHECKS-INCOMPLETE/s/\[ "$NAMES" -lt "$EXPECT" \]/false/
red-wins-while-running	/^if \[ "$REDN" -gt 0 \] \&\& ! has/s/ \&\& ! has "$PEND"//
rate-limit-dropped	/^if ! RL="$(gh_rate_short/s/if ! RL=/if false \&\& ! RL=/
both-forms-checkrun-wins	/| if (\$bad | length) > 0 then \$bad\[0\] elif/s/if (\$bad | length) > 0 then \$bad\[0\] elif (\$open | length) > 0/if false then $bad[0] elif false/
etag-fallback-dropped	/if \[ "\$rc" -ne 0 \]; then EC=""; api "\$p"; return; fi/s/then EC=""; api "\$p"; return; fi/then return "$rc"; fi/
etag-hit-blind	/HTTP\/\*\x27 304\x27\*)/s/HTTP\/\*\x27 304\x27\*)/HTTP\/*)/
etag-hit-blind-any	/^    if \[ -f "\$f" \] \&\& IFS= read -r e/s/then hdr=(-H "If-None-Match: \$e"); fi/then CONDHIT=$((CONDHIT + 1)); sed 1d "$f"; return 0; fi/
displaced-dropped	/and .conclusion == "cancelled"$/s/and .conclusion == "cancelled"/and false/
displaced-any-cancelled	/and (.check_suite_id as $s | $have | index($s) | not))\]/s/and (.check_suite_id as $s | $have | index($s) | not))\]/)]/
required-out-dropped	/cp "$W\/req.txt" "$CI_READ_REQUIRED_OUT"/s/cp "$W\/req.txt"/: "$W\/req.txt"/
required-out-empty	/cp "$W\/req.txt" "$CI_READ_REQUIRED_OUT"/s/cp "$W\/req.txt"/cp \/dev\/null/
rules-read-tolerated	/void "наборы правил ветки \$BASE не прочитаны/s/void "/: "/
protection-read-tolerated	/void "защита ветки \$BASE не прочитана/s/void "/: "/
no-rule-e	/\.drop = (\$pr and/s/\.drop = (\$pr and/.drop = (false and/;/if (\$red | length) > 0/s/if (\$red | length) > 0/if false/
MUT
for tr in $TRUNKS; do
    name="trunk-row-dropped-$tr"
    grep -v "^PRO-Robotech/$tr	main	" "$LIVE" > "$SC/ledger.$name.tsv"
    if cmp -s "$SC/ledger.$name.tsv" "$LIVE"; then
        void=$((void + 1)); echo "  MUTANT $name → RESULT VOID (правка не легла: строки нет)"; continue
    fi
    printf '%s\t%s\t%s\n' "$name" "$HERE/ci-read.sh" "$SC/ledger.$name.tsv" >> "$SC/list"
done
while IFS=$'\t' read -r rr rb; do
    [ "$rb" != main ] || continue
    name="row-dropped-${rr#*/}-$rb"
    awk -F'\t' -v r="$rr" -v b="$rb" '/^#/ || !($1==r && $2==b)' "$LIVE" > "$SC/ledger.$name.tsv"
    if cmp -s "$SC/ledger.$name.tsv" "$LIVE"; then
        void=$((void + 1)); echo "  MUTANT $name → RESULT VOID (правка не легла: строки нет)"; continue
    fi
    printf '%s\t%s\t%s\n' "$name" "$HERE/ci-read.sh" "$SC/ledger.$name.tsv" >> "$SC/list"
done < "$ROWS"

# --- матрица: каждая клетка — отдельный процесс, JOBS одновременно
R="$T/res"
while IFS=$'\t' read -r name scr lv; do
    mkdir -p "$R/$name"
    for c in "$CASES"/*; do printf '%s\0%s\0%s\0%s\0' "$scr" "$lv" "$c" "$R/$name/$(basename "$c")"; done
done < "$SC/list" | xargs -0 -n 4 -P "$JOBS" "$T/cell.sh"
xs=$?
[ "$xs" -eq 0 ] || { echo "VOID: исполнитель матрицы вернул $xs" >&2; exit 2; }

# --- свод: контроль — построчно, мутанты — строкой на мутант
tally() {  # tally <сценарий> → pass fail failed-перечень в переменные
    pass=0; fail=0; failed=""
    for c in "$CASES"/*; do
        o="$R/$1/$(basename "$c")"
        if [ -s "$o" ] && [ "$(head -c 2 "$o")" = OK ]; then pass=$((pass + 1))
        else fail=$((fail + 1)); failed="$failed; $(cat "$c/name") (код $(head -1 "$o" 2>/dev/null | cut -f2))"; fi
    done
}
sec=""
for c in "$CASES"/*; do
    s="$(cat "$c/section")"; [ "$s" = "$sec" ] || { echo "$s"; sec="$s"; }
    o="$R/control/$(basename "$c")"
    if [ -s "$o" ] && [ "$(head -c 2 "$o")" = OK ]; then
        echo "  [OK]   $(cat "$c/name") — код $(head -1 "$o" | cut -f2)"
    else
        echo "  [FAIL] $(cat "$c/name") — код $(head -1 "$o" 2>/dev/null | cut -f2) (ждали $(cat "$c/code"), строка «$(cat "$c/pat")»)"
        tail -n +2 "$o" 2>/dev/null | while IFS= read -r l; do echo "         $l"; done
    fi
done
tally control
echo
echo "ci-read-inject: случаев $((pass + fail)), сошлось $pass, разошлось $fail"
cases_ok=0; [ "$fail" -eq 0 ] && [ "$pass" -gt 0 ] && cases_ok=1

echo
echo "== мутанты — каждый обязан покраснеть"
killed=0; survived=0
while IFS=$'\t' read -r name _ _; do
    [ "$name" != control ] || continue
    tally "$name"
    if [ "$fail" -gt 0 ]; then
        killed=$((killed + 1)); echo "  MUTANT $name → RESULT KILLED (разошлось $fail из $((pass + fail)): ${failed#; })"
    else
        survived=$((survived + 1)); echo "  MUTANT $name → RESULT SURVIVED (все $pass случаев сошлись)"
    fi
done < "$SC/list"

echo
echo "ci-read-inject: мутантов $((killed + survived + void)), убито $killed, выжило $survived, не легло $void; клеток $(( $(wc -l < "$SC/list") * NC )), процессов $JOBS"
[ "$cases_ok" = 1 ] && [ "$survived" -eq 0 ] && [ "$void" -eq 0 ] && [ "$killed" -gt 0 ]
