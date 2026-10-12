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
# и compare.json — синтетика той же формы (база = base.sha запроса). Каждый случай
# меняет РОВНО один факт контроля:
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
#             прежний — событие push и идёт: не вытеснен             → 3 RUNS-PENDING
#             одноимённый workflow ДРУГОГО файла (workflow_id) позже:
#             не вытесняет, красное прежнего судится                → 1 CI-FAILED
#             новый позже по created_at, но с меньшим run_number      → 0 green
#             новый позже по created_at, но с меньшим id              → 0 green
#             последний прогон queued (не in_progress)               → 3 RUNS-PENDING
#   целевой прогон на НЕ-черновике (ws#1019, (д) ci-read.sh): прежний
#             ПОЛНЫЙ — build failure, поздний ЦЕЛЕВОЙ того же workflow
#             (проверки skipped, страж с аннотацией) не вытесняет его → 1 CI-FAILED build
#             близнец — тот же набор на черновике: судится целевой  → 5 targeted-green
#   черновик (ws#1013): исполненное зелёное, прочее skipped, страж
#             с аннотацией «черновик не вливается»                 → 5 targeted-green
#   черновик: failure БЕЗ аннотации стража — настоящий отказ       → 1 CI-FAILED
#   черновик: страж есть, выбранное задание failure                → 1 CI-FAILED
#   черновик: страж ещё идёт                                       → 3 DRAFT-GUARD-PENDING
#   не черновик: та же аннотация стражем не делает                 → 1 CI-FAILED
#   площадка не отдала check-runs                                  → 2 VOID
#   пары репозиторий/база нет в ведомости                          → 2 VOID
#   живая ведомость: запрос в main каждого ствола (kacho, kaname,
#             corelib, kacho-workspace) — строка есть             → 0 green
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
#   trunk-row-dropped-<ствол> — из ЖИВОЙ ведомости снята строка <ствол>/main
#                         (по одному на каждый из четырёх; урок corelib#111).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIVE="$HERE/ci-read-expected.tsv"   # живая ведомость; мутанты строк подменяют её копией
FX_N=68                             # различных проверок в фикстуре kacho-3140
FX="$HERE/ci-read-fixtures/kacho-3140"
JOBS="${CI_READ_INJECT_JOBS:-$(nproc 2>/dev/null || echo 4)}"
command -v jq >/dev/null 2>&1 || { echo "VOID: нет jq" >&2; exit 2; }
[ -r "$HERE/ci-read.sh" ] && [ -d "$FX" ] || { echo "VOID: нет $HERE/ci-read.sh или $FX" >&2; exit 2; }
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || { echo "VOID: CI_READ_INJECT_JOBS «$JOBS» не число" >&2; exit 2; }

T="$(mktemp -d "${TMPDIR:-/tmp}/ci-read-inject.XXXXXX")" || exit 2
trap 'rm -rf "$T"' EXIT

# Двойник gh: путь (последний довод) → файл в каталоге $CI_READ_FX; файла нет — 404.
# Страницы — как у площадки: <файл>.p2 рядом — вторая страница; без --paginate
# отдаётся только первая, с ним — обе подряд (поток JSON, как печатает gh).
# Аннотации: annotations.<id>.json — для проверки <id>, иначе annotations.json,
# иначе пустой список (у проверки аннотаций нет).
cat > "$T/gh" <<'GH'
#!/usr/bin/env bash
p="${!#}"
pg=0; for a in "$@"; do [ "$a" != --paginate ] || pg=1; done
case "$p" in
  repos/*/pulls/*) f=pull.json ;;
  repos/*/commits/*/check-runs*) f=check-runs.json ;;
  repos/*/commits/*/status) f=status.json ;;
  repos/*/actions/runs*) f=runs.json ;;
  repos/*/branches/*/protection/required_status_checks) f=protection.json ;;
  repos/*/rules/branches/*) f=rules.json ;;
  repos/*/branches/*) f=branch.json ;;
  repos/*/compare/*) f=compare.json ;;
  repos/*/check-runs/*/annotations)
    id="${p#repos/*/check-runs/}"; id="${id%/annotations}"
    if [ -f "$CI_READ_FX/annotations.$id.json" ]; then f="annotations.$id.json"
    elif [ -f "$CI_READ_FX/annotations.json" ]; then f=annotations.json
    else echo '[]'; exit 0; fi ;;
  *) f=none ;;
esac
if [ -f "$CI_READ_FX/$f.err" ]; then cat "$CI_READ_FX/$f.err" >&2; exit 1; fi
if [ "$f" = rules.json ] && [ ! -f "$CI_READ_FX/$f" ]; then echo '[]'; exit 0; fi
[ -f "$CI_READ_FX/$f" ] || { echo "gh: Not Found (HTTP 404) $p" >&2; exit 1; }
cat "$CI_READ_FX/$f"
if [ "$pg" = 1 ] && [ -f "$CI_READ_FX/$f.p2" ]; then cat "$CI_READ_FX/$f.p2"; fi
GH
chmod +x "$T/gh"

# Исполнитель одной клетки матрицы: <сценарий ci-read> <живая ведомость> <каталог
# случая> <файл исхода>. Исход — строка «OK|FAIL TAB код»; при FAIL следом хвост вывода.
# Ведомость случая: файл ledger.tsv в каталоге случая, либо trunk=<ствол> — копия
# ЖИВОЙ ведомости сценария с числом строки ствола, заменённым числом фикстуры.
cat > "$T/cell.sh" <<'CELL'
#!/usr/bin/env bash
S="$1"; LV="$2"; C="$3"; O="$4"
L="$C/ledger.tsv"
if [ -f "$C/trunk" ]; then
    L="$O.ledger"
    awk -F'\t' -v OFS='\t' -v r="PRO-Robotech/$(cat "$C/trunk")" -v n="$(cat "$C/fxn")" \
        '!/^#/ && $1==r && $2=="main" {$3=n} {print}' "$LV" > "$L"
fi
out="$(CI_READ_GH="$GHX" CI_READ_FX="$C" CI_READ_EXPECTED="$L" bash "$S" "$(cat "$C/repo")" 3140 2>&1)"; code=$?
pat="$(cat "$C/pat")"
if [ "$code" -eq "$(cat "$C/code")" ] && { [ -z "$pat" ] || grep -qP "$pat" <<<"$out"; } && grep -qP "^VERDICT\t" <<<"$out"; then
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
run() {  # run <имя> <ожидаемый код> <образец строки REASON|VOID либо пусто> [ведомость|trunk:<ствол>] [репозиторий]
    printf '%s' "$1" > "$C/name"; printf '%s' "$2" > "$C/code"; printf '%s' "$3" > "$C/pat"
    printf '%s' "${5:-PRO-Robotech/kacho}" > "$C/repo"; printf '%s' "$SECTION" > "$C/section"
    case "${4:-}" in
        trunk:*) printf '%s' "${4#trunk:}" > "$C/trunk"; printf '%s' "$FX_N" > "$C/fxn" ;;
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
# shellcheck disable=SC2016
supersede() {  # supersede <заключение прежнего> <статус нового> <заключение нового|null> [событие прежнего] [id нового] [workflow_id нового]
    mk
    edit runs.json "(.workflow_runs |= map(if .id == $OLDRUN then .workflow_id = 5 | .event = \"${4:-pull_request}\" | .created_at = \"2026-10-10T21:00:00Z\" | .run_attempt = 1 | .run_number = 20 | .status = \"completed\" | .conclusion = \"$1\" end))
        | .workflow_runs += [{id: ${5:-38199999999}, name: \"сводный вердикт\", workflow_id: ${6:-5}, event: \"pull_request\", status: \"$2\", conclusion: $3, created_at: \"2026-10-10T22:00:00Z\", run_attempt: 1, run_number: 21, head_sha: .workflow_runs[0].head_sha, check_suite_id: 999}]"
    edit check-runs.json "(.check_runs |= map(if .check_suite.id == $OLDSUITE then .conclusion = \"$1\" end))"
}
new_agg() {  # проверка сводного вердикта в новом прогоне: <статус> <заключение|null> <started_at>
    edit check-runs.json ".check_runs += [(.check_runs[] | select(.check_suite.id == $OLDSUITE)) | .check_suite.id = 999 | .status = \"$1\" | .conclusion = $2 | .started_at = \"$3\"]"
}
supersede failure in_progress null
run "прежний красный сводный черновика, полный того же workflow идёт" 3 '^VERDICT\trunning\t'
supersede failure in_progress null
run "вытеснение напечатано переписью" 3 '^CENSUS\tworkflow runs на голове: 11; последних по workflow и событию 8, вытеснено 3'
supersede success completed '"failure"'; new_agg completed '"failure"' 2026-10-10T22:30:00Z
run "близнец: последний полный красный" 1 '^REASON\tCI-FAILED\tfailure: сводный вердикт'
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
run "прогон push того же workflow pull_request-прогоном не вытесняется" 3 '^REASON\tRUNS-PENDING\t.*run 38086061943'
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
        | .check_runs += [(.check_runs[] | select(.check_suite.id == $CISUITE)) | .check_suite.id = 998 | .conclusion = \"skipped\" | .started_at = \"2026-10-10T23:01:00Z\"]
        | .check_runs += [{id: 778, name: \"сводный вердикт ci\", status: \"completed\", conclusion: \"failure\", started_at: \"2026-10-10T23:02:00Z\", completed_at: \"2026-10-10T23:03:00Z\", check_suite: {id: 998}}]" \
        "$C/check-runs.json" > "$C/cr.n" && mv "$C/cr.n" "$C/check-runs.json"
    echo '[{"title":"черновик не вливается","message":"целевой прогон"}]' > "$C/annotations.778.json"
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
    echo '[{"title":"черновик не вливается","message":"целевой прогон: 9 заданий из 27"}]' > "$C/annotations.json"
}
draft; run "черновик: исполненное зелёное, страж вынес вердикт" 5 '^VERDICT\ttargeted-green\t.*ЦЕЛЕВОЙ, не полный'
draft; echo '[]' > "$C/annotations.json"
run "черновик: failure без аннотации стража — настоящий отказ" 1 "^REASON\tCI-FAILED\tfailure: \Q$AGG\E"
draft; edit check-runs.json '.check_runs |= map(.conclusion = (if .name == "build · vet · gofmt" then "failure" else .conclusion end))'
run "черновик: страж есть, выбранное задание failure" 1 '^REASON\tCI-FAILED\tfailure: build · vet · gofmt'
draft; jq --arg a "$AGG" '.check_runs |= map(.status = (if .name == $a then "in_progress" else .status end) | .conclusion = (if .name == $a then null else .conclusion end))' "$C/check-runs.json" > "$C/cr.n" && mv "$C/cr.n" "$C/check-runs.json"
run "черновик: страж ещё идёт" 3 '^REASON\tDRAFT-GUARD-PENDING\t'
draft; edit pull.json '.draft = false'
run "не черновик: аннотация стражем не делает" 1 "^REASON\tCI-FAILED\tfailure: \Q$AGG\E"

say "== не прочитано — 2"
mk; echo 'gh: HTTP 502 Bad Gateway' > "$C/check-runs.json.err"
run "площадка не отдала check-runs" 2 '^VOID\tcheck-runs на '
mk; grep -v '^PRO-Robotech/kacho	1266	' "$FXL" > "$T/ledger.nopair.tsv"
run "пары kacho/1266 нет в ведомости" 2 '^VOID\tпары PRO-Robotech/kacho / 1266 нет' "$T/ledger.nopair.tsv"

say "== живая ведомость: у ствола каждого нашего репозитория строка есть"
# Стволы — kacho · kaname · corelib (00-kacho-core ban20-scope-is-our-trunks) и сам
# воркспейс. Фикстура та же (68 различных проверок), меняются репозиторий и база
# запроса — main; строки берутся из ЖИВОЙ ведомости сценария, число строки ствола в
# копии заменяется числом фикстуры (судится присутствие, а не набор workflow ствола).
# Строки нет — замене нечего менять, ci-read.sh отвечает 2, и случай краснеет
# (урок corelib#111: код 2 «пары нет в ведомости»).
for tr in kacho kaname corelib kacho-workspace; do
    mk; edit pull.json '.base.ref = "main"'
    run "строка PRO-Robotech/$tr / main в ведомости" 0 "^VERDICT\tgreen\t.*проверок $FX_N из $FX_N" "trunk:$tr" "PRO-Robotech/$tr"
done

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
MUT
for tr in kacho kaname corelib kacho-workspace; do
    name="trunk-row-dropped-$tr"
    grep -v "^PRO-Robotech/$tr	main	" "$LIVE" > "$SC/ledger.$name.tsv"
    if cmp -s "$SC/ledger.$name.tsv" "$LIVE"; then
        void=$((void + 1)); echo "  MUTANT $name → RESULT VOID (правка не легла: строки нет)"; continue
    fi
    printf '%s\t%s\t%s\n' "$name" "$HERE/ci-read.sh" "$SC/ledger.$name.tsv" >> "$SC/list"
done

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
