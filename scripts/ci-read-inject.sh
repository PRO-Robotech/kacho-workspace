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
#   площадка не отдала check-runs                                  → 2 VOID
#   пары репозиторий/база нет в ведомости                          → 2 VOID
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
#   failset-<значение>  — значение убрано из FAILSET, по одному на каждое из шести.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/ci-read.sh"
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
  *) f=none ;;
esac
if [ -f "$CI_READ_FX/$f.err" ]; then cat "$CI_READ_FX/$f.err" >&2; exit 1; fi
if [ "$f" = rules.json ] && [ ! -f "$CI_READ_FX/$f" ]; then echo '[]'; exit 0; fi
[ -f "$CI_READ_FX/$f" ] || { echo "gh: Not Found (HTTP 404) $p" >&2; exit 1; }
cat "$CI_READ_FX/$f"
if [ "$pg" = 1 ] && [ -f "$CI_READ_FX/$f.p2" ]; then cat "$CI_READ_FX/$f.p2"; fi
GH
chmod +x "$T/gh"

pass=0; fail=0; quiet=0; failed=""
mk() { rm -rf "$T/c"; mkdir -p "$T/c"; cp "$FX"/*.json "$T/c/"; }
edit() { jq "$2" "$T/c/$1" > "$T/c/$1.n" && mv "$T/c/$1.n" "$T/c/$1"; }
run() {  # run <имя> <ожидаемый код> <образец строки REASON|VOID либо пусто> [ведомость]
    local out code
    out="$(CI_READ_GH="$T/gh" CI_READ_FX="$T/c" CI_READ_EXPECTED="${4:-$HERE/ci-read-expected.tsv}" bash "$S" PRO-Robotech/kacho 3140 2>&1)"; code=$?
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

say "== не прочитано — 2"
mk; echo 'gh: HTTP 502 Bad Gateway' > "$T/c/check-runs.json.err"
run "площадка не отдала check-runs" 2 '^VOID\tcheck-runs на '
mk; grep -v '^PRO-Robotech/kacho	1266	' "$HERE/ci-read-expected.tsv" > "$T/ledger.tsv"
run "пары kacho/1266 нет в ведомости" 2 '^VOID\tпары PRO-Robotech/kacho / 1266 нет' "$T/ledger.tsv"

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
MUT
echo
echo "ci-read-inject: мутантов $((killed + survived + void)), убито $killed, выжило $survived, не легло $void"
[ "$cases_ok" = 1 ] && [ "$survived" -eq 0 ] && [ "$void" -eq 0 ] && [ "$killed" -gt 0 ]
