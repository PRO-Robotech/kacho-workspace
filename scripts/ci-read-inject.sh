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
#   trunk-row-dropped-<ствол> — из ЖИВОЙ ведомости снята строка <ствол>/main
#                         (по одному на каждый из четырёх; урок corelib#111).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/ci-read.sh"
LIVE="$HERE/ci-read-expected.tsv"   # живая ведомость; мутанты строк подменяют её копией
FX_N=68                             # различных проверок в фикстуре kacho-3140
FX="$HERE/ci-read-fixtures/kacho-3140"
command -v jq >/dev/null 2>&1 || { echo "VOID: нет jq" >&2; exit 2; }
[ -r "$S" ] && [ -d "$FX" ] || { echo "VOID: нет $S или $FX" >&2; exit 2; }

T="$(mktemp -d "${TMPDIR:-/tmp}/ci-read-inject.XXXXXX")" || exit 2
trap 'rm -rf "$T"' EXIT

# Двойник gh: путь (последний довод) → файл в каталоге $CI_READ_FX; файла нет — 404.
# Страницы — как у площадки: <файл>.p2 рядом — вторая страница; без --paginate
# отдаётся только первая, с ним — обе подряд (поток JSON, как печатает gh).
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
  repos/*/check-runs/*/annotations) f=annotations.json ;;
  *) f=none ;;
esac
if [ -f "$CI_READ_FX/$f.err" ]; then cat "$CI_READ_FX/$f.err" >&2; exit 1; fi
if [ "$f" = rules.json ] && [ ! -f "$CI_READ_FX/$f" ]; then echo '[]'; exit 0; fi
[ -f "$CI_READ_FX/$f" ] || { echo "gh: Not Found (HTTP 404) $p" >&2; exit 1; }
cat "$CI_READ_FX/$f"
if [ "$pg" = 1 ] && [ -f "$CI_READ_FX/$f.p2" ]; then cat "$CI_READ_FX/$f.p2"; fi
GH
chmod +x "$T/gh"

FXL="$T/ledger.fixture.tsv"           # ведомость случаев: строка — число фикстуры
printf 'PRO-Robotech/kacho\t1266\t%s\tфикстура kacho-3140\n' "$FX_N" > "$FXL"

pass=0; fail=0; quiet=0; failed=""
mk() { rm -rf "$T/c"; mkdir -p "$T/c"; cp "$FX"/*.json "$T/c/"; }
edit() { jq "$2" "$T/c/$1" > "$T/c/$1.n" && mv "$T/c/$1.n" "$T/c/$1"; }
run() {  # run <имя> <ожидаемый код> <образец строки REASON|VOID либо пусто> [ведомость] [репозиторий]
    local out code
    out="$(CI_READ_GH="$T/gh" CI_READ_FX="$T/c" CI_READ_EXPECTED="${4:-$FXL}" bash "$S" "${5:-PRO-Robotech/kacho}" 3140 2>&1)"; code=$?
    if [ "$code" -eq "$2" ] && { [ -z "$3" ] || grep -qP "$3" <<<"$out"; } && grep -qP "^VERDICT\t" <<<"$out"; then
        pass=$((pass + 1)); [ "$quiet" = 1 ] || echo "  [OK]   $1 — код $code"
    else
        fail=$((fail + 1)); failed="$failed; $1 (код $code)"
        [ "$quiet" = 1 ] || { echo "  [FAIL] $1 — код $code (ждали $2, строка «$3»)"; tail -8 <<<"$out" | while IFS= read -r l; do echo "         $l"; done; }
    fi
}
# одна проверка (первая по имени, имя в ответе единственное) завершена значением $1
one_concl() {
    mk; edit check-runs.json "(.check_runs | sort_by(.name) | .[0].name) as \$n | .check_runs |= map(.conclusion = (if .name == \$n then \"$1\" else .conclusion end))"
}

say() { [ "$quiet" = 1 ] || echo "$@"; }
cases() {

say "== контроль"
mk; run "полный зелёный, база свежая" 0 '^VERDICT\tgreen\t.*проверок 68 из 68'

say "== неполно и идёт — 3"
mk; edit check-runs.json '.check_runs |= (group_by(.name) | map(.[0]) | .[0:30])'
run "урок #3142: 30 из 68, всё видимое зелёное" 3 '^REASON\tCHECKS-INCOMPLETE\tпроверок 30 из 68'
mk; edit check-runs.json '.check_runs |= (sort_by(.name) | (.[0:3] | map(.status="in_progress" | .conclusion=null | .started_at="2099-01-01T00:00:00Z")) + .[3:])'
run "урок #3142: 68 из 68, три ещё идут" 3 '^REASON\tCI-PENDING\tне завершена: '
mk; edit runs.json '.workflow_runs[0] |= (.status="in_progress" | .conclusion=null)'
run "workflow run не завершён при завершённых check-runs" 3 '^REASON\tRUNS-PENDING\t'

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
jq '.check_runs = .check_runs[100:]' "$T/c/check-runs.json" > "$T/c/check-runs.json.p2"
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
supersede() {  # supersede <заключение прежнего> <статус нового> <заключение нового|null> [событие прежнего]
    mk
    edit runs.json "(.workflow_runs |= map(if .id == $OLDRUN then .workflow_id = 5 | .event = \"${4:-pull_request}\" | .created_at = \"2026-10-10T21:00:00Z\" | .run_attempt = 1 | .status = \"completed\" | .conclusion = \"$1\" end))
        | .workflow_runs += [{id: 38199999999, name: \"сводный вердикт\", workflow_id: 5, event: \"pull_request\", status: \"$2\", conclusion: $3, created_at: \"2026-10-10T22:00:00Z\", run_attempt: 1, head_sha: .workflow_runs[0].head_sha, check_suite_id: 999}]"
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

say "== черновик — целевой прогон (ws#1013)"
AGG="сводный вердикт (все проверки завершились и зелены)"
# черновик: 20 проверок skipped (не выбраны), страж — failure с аннотацией
draft() {
    mk; edit pull.json '.draft = true'
    jq --arg a "$AGG" '.check_runs |= (sort_by(.name) | map(
          .id = (if .name == $a then 777 else .id end)
        | .conclusion = (if .name == $a then "failure"
            elif (.name | test("^(юниты|integration|e2e|unit|build) ")) then "skipped"
            else .conclusion end)))' "$T/c/check-runs.json" > "$T/c/cr.n" && mv "$T/c/cr.n" "$T/c/check-runs.json"
    echo '[{"title":"черновик не вливается","message":"целевой прогон: 9 заданий из 27"}]' > "$T/c/annotations.json"
}
draft; run "черновик: исполненное зелёное, страж вынес вердикт" 5 '^VERDICT\ttargeted-green\t.*ЦЕЛЕВОЙ, не полный'
draft; echo '[]' > "$T/c/annotations.json"
run "черновик: failure без аннотации стража — настоящий отказ" 1 "^REASON\tCI-FAILED\tfailure: \Q$AGG\E"
draft; edit check-runs.json '.check_runs |= map(.conclusion = (if .name == "build · vet · gofmt" then "failure" else .conclusion end))'
run "черновик: страж есть, выбранное задание failure" 1 '^REASON\tCI-FAILED\tfailure: build · vet · gofmt'
draft; jq --arg a "$AGG" '.check_runs |= map(.status = (if .name == $a then "in_progress" else .status end) | .conclusion = (if .name == $a then null else .conclusion end))' "$T/c/check-runs.json" > "$T/c/cr.n" && mv "$T/c/cr.n" "$T/c/check-runs.json"
edit runs.json '.'
run "черновик: страж ещё идёт" 3 '^REASON\tDRAFT-GUARD-PENDING\t'
draft; edit pull.json '.draft = false'
run "не черновик: аннотация стражем не делает" 1 "^REASON\tCI-FAILED\tfailure: \Q$AGG\E"

say "== не прочитано — 2"
mk; echo 'gh: HTTP 502 Bad Gateway' > "$T/c/check-runs.json.err"
run "площадка не отдала check-runs" 2 '^VOID\tcheck-runs на '
mk; grep -v '^PRO-Robotech/kacho	1266	' "$FXL" > "$T/ledger.tsv"
run "пары kacho/1266 нет в ведомости" 2 '^VOID\tпары PRO-Robotech/kacho / 1266 нет' "$T/ledger.tsv"

say "== живая ведомость: у ствола каждого нашего репозитория строка есть"
# Стволы — kacho · kaname · corelib (00-kacho-core ban20-scope-is-our-trunks) и сам
# воркспейс. Фикстура та же (68 различных проверок), меняются репозиторий и база
# запроса — main; строки берутся из ЖИВОЙ ведомости, число строки ствола в копии
# заменяется числом фикстуры (судится присутствие, а не набор workflow ствола).
# Строки нет — замене нечего менять, ci-read.sh отвечает 2, и случай краснеет
# (урок corelib#111: код 2 «пары нет в ведомости»).
for tr in kacho kaname corelib kacho-workspace; do
    mk; edit pull.json '.base.ref = "main"'
    awk -F'\t' -v OFS='\t' -v r="PRO-Robotech/$tr" -v n="$FX_N" \
        '!/^#/ && $1==r && $2=="main" {$3=n} {print}' "$LIVE" > "$T/ledger.trunk.tsv"
    run "строка PRO-Robotech/$tr / main в ведомости" 0 "^VERDICT\tgreen\t.*проверок $FX_N из $FX_N" "$T/ledger.trunk.tsv" "PRO-Robotech/$tr"
done

say "== близнецы — молчат"
mk; edit check-runs.json '.check_runs = [(.check_runs | sort_by(.name) | .[0]) | .conclusion="failure" | .started_at="2000-01-01T00:00:00Z"] + .check_runs'
run "прежний failure первым в ответе, последний success" 0 '^VERDICT\tgreen\t'
mk; edit check-runs.json '.check_runs += [(.check_runs | sort_by(.name) | .[0]) | .conclusion="failure" | .started_at="2000-01-01T00:00:00Z"]'
run "прежний failure последним в ответе, последний по времени success" 0 '^VERDICT\tgreen\t'
mk; rm "$T/c/protection.json"; echo 'gh: Branch not protected (HTTP 404)' > "$T/c/protection.json.err"
run "защиты ветки нет вовсе" 0 '^CENSUS\tзащиты ветки 1266 нет'
mk; edit status.json '.statuses=[{context:"внешний контекст",state:"success"}]'
run "commit status success вне check-runs" 0 '^VERDICT\tgreen\t.*проверок 69 из 68'
}

S="$HERE/ci-read.sh"
cases
echo
echo "ci-read-inject: случаев $((pass + fail)), сошлось $pass, разошлось $fail"
cases_ok=0; [ "$fail" -eq 0 ] && [ "$pass" -gt 0 ] && cases_ok=1

# --- мутанты: <имя> TAB <sed-выражение>; каждый обязан дать расхождение
echo
echo "== мутанты — каждый обязан покраснеть"
killed=0; survived=0; void=0
while IFS=$'\t' read -r name expr; do
    M="$T/ci-read.$name.sh"
    sed -e "$expr" "$HERE/ci-read.sh" > "$M"
    if cmp -s "$M" "$HERE/ci-read.sh"; then
        void=$((void + 1)); echo "  MUTANT $name → RESULT VOID (правка не легла: образец не найден)"; continue
    fi
    S="$M"; pass=0; fail=0; quiet=1; failed=""
    cases
    if [ "$fail" -gt 0 ]; then
        killed=$((killed + 1)); echo "  MUTANT $name → RESULT KILLED (разошлось $fail из $((pass + fail)): ${failed#; })"
    else
        survived=$((survived + 1)); echo "  MUTANT $name → RESULT SURVIVED (все $pass случаев сошлись)"
    fi
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
supersede-earliest	/superseded: (map(/s/latest: map(last), superseded: (map(.\[0:-1\])/latest: map(first), superseded: (map(.[1:])/
supersede-event-dropped	/group_by(\[(.workflow_id/s/, .event\])/])/
runs-pending-all	/reason RUNS-PENDING/s/'\.latest\[\]|select/'.superseded[], .latest[]|select/
MUT
# --- мутанты ведомости: строка ствола снята; живой ci-read.sh, копия ведомости
S="$HERE/ci-read.sh"
for tr in kacho kaname corelib kacho-workspace; do
    name="trunk-row-dropped-$tr"
    grep -v "^PRO-Robotech/$tr	main	" "$HERE/ci-read-expected.tsv" > "$T/ledger.$name.tsv"
    if cmp -s "$T/ledger.$name.tsv" "$HERE/ci-read-expected.tsv"; then
        void=$((void + 1)); echo "  MUTANT $name → RESULT VOID (правка не легла: строки нет)"; continue
    fi
    LIVE="$T/ledger.$name.tsv"; pass=0; fail=0; quiet=1; failed=""
    cases
    if [ "$fail" -gt 0 ]; then
        killed=$((killed + 1)); echo "  MUTANT $name → RESULT KILLED (разошлось $fail из $((pass + fail)): ${failed#; })"
    else
        survived=$((survived + 1)); echo "  MUTANT $name → RESULT SURVIVED (все $pass случаев сошлись)"
    fi
done
LIVE="$HERE/ci-read-expected.tsv"

echo
echo "ci-read-inject: мутантов $((killed + survived + void)), убито $killed, выжило $survived, не легло $void"
[ "$cases_ok" = 1 ] && [ "$survived" -eq 0 ] && [ "$void" -eq 0 ] && [ "$killed" -gt 0 ]
