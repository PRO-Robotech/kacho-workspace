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
#   обязательный контекст исчез при завершённом остальном          → 1 REQUIRED-MISSING
#   обязательный контекст skipped                                  → 1 REQUIRED-NOT-SUCCESS
#   последний по started_at прогон имени failure, прежний success  → 1 CI-FAILED
#   площадка не отдала check-runs                                  → 2 VOID
#   пары репозиторий/база нет в ведомости                          → 2 VOID
# Близнецы (обязаны молчать — код 0): прежний прогон имени failure стоит в ответе
# ПЕРВЫМ либо ПОСЛЕДНИМ, последний по started_at — success (вытеснен; порядок
# ответа не судит); защиты ветки нет вовсе; commit status success вне check-runs.
# Сверяется код И строка причины — что напечатано, а не только «покраснел».
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/ci-read.sh"
FX="$HERE/ci-read-fixtures/kacho-3140"
command -v jq >/dev/null 2>&1 || { echo "VOID: нет jq" >&2; exit 2; }
[ -r "$S" ] && [ -d "$FX" ] || { echo "VOID: нет $S или $FX" >&2; exit 2; }

T="$(mktemp -d "${TMPDIR:-/tmp}/ci-read-inject.XXXXXX")" || exit 2
trap 'rm -rf "$T"' EXIT

# Двойник gh: путь (последний довод) → файл в каталоге $CI_READ_FX; файла нет — 404.
cat > "$T/gh" <<'GH'
#!/usr/bin/env bash
p="${!#}"
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
GH
chmod +x "$T/gh"

pass=0; fail=0
mk() { rm -rf "$T/c"; mkdir -p "$T/c"; cp "$FX"/*.json "$T/c/"; }
edit() { jq "$2" "$T/c/$1" > "$T/c/$1.n" && mv "$T/c/$1.n" "$T/c/$1"; }
run() {  # run <имя> <ожидаемый код> <образец строки REASON|VOID либо пусто> [ведомость]
    local out code
    out="$(CI_READ_GH="$T/gh" CI_READ_FX="$T/c" CI_READ_EXPECTED="${4:-$HERE/ci-read-expected.tsv}" bash "$S" PRO-Robotech/kacho 3140 2>&1)"; code=$?
    if [ "$code" -eq "$2" ] && { [ -z "$3" ] || grep -qP "$3" <<<"$out"; } && grep -qP "^VERDICT\t" <<<"$out"; then
        pass=$((pass + 1)); echo "  [OK]   $1 — код $code"
    else
        fail=$((fail + 1)); echo "  [FAIL] $1 — код $code (ждали $2, строка «$3»)"; tail -8 <<<"$out" | while IFS= read -r l; do echo "         $l"; done
    fi
}

echo "== контроль"
mk; run "полный зелёный, база свежая" 0 '^VERDICT\tgreen\t.*проверок 68 из 68'

echo "== неполно и идёт — 3"
mk; edit check-runs.json '.check_runs |= (group_by(.name) | map(.[0]) | .[0:30])'
run "урок #3142: 30 из 68, всё видимое зелёное" 3 '^REASON\tCHECKS-INCOMPLETE\tпроверок 30 из 68'
mk; edit check-runs.json '.check_runs |= (sort_by(.name) | (.[0:3] | map(.status="in_progress" | .conclusion=null | .started_at="2099-01-01T00:00:00Z")) + .[3:])'
run "урок #3142: 68 из 68, три ещё идут" 3 '^REASON\tCI-PENDING\tне завершена: '
mk; edit runs.json '.workflow_runs[0] |= (.status="in_progress" | .conclusion=null)'
run "workflow run не завершён при завершённых check-runs" 3 '^REASON\tRUNS-PENDING\t'

echo "== база устарела — 4"
mk; edit branch.json '.commit.sha="1111111111111111111111111111111111111111"'
run "всё зелёное, база ушла вперёд" 4 '^REASON\tBASE-STALE\tmerge-base '

echo "== красное — 1"
mk; edit check-runs.json '.check_runs |= (sort_by(.name) | (.[0:1] | map(.conclusion="failure")) + .[1:])'
run "одна проверка failure" 1 '^REASON\tCI-FAILED\tfailure: '
mk; edit check-runs.json '.check_runs |= map(select(.name != "сводный вердикт (все проверки завершились и зелены)"))'
edit check-runs.json '.check_runs += [.check_runs[0] | .name="замена" ]'
run "обязательный контекст исчез, остальное завершено" 1 '^REASON\tREQUIRED-MISSING\t.*сводный вердикт'
mk; edit check-runs.json '.check_runs |= map(if .name == "сводный вердикт (все проверки завершились и зелены)" then .conclusion="skipped" else . end)'
run "обязательный контекст skipped" 1 '^REASON\tREQUIRED-NOT-SUCCESS\tобязательный контекст skipped'

mk; edit check-runs.json '.check_runs = .check_runs + [(.check_runs | sort_by(.name) | .[0]) | .conclusion="failure" | .started_at="2099-01-01T00:00:00Z"]'
run "повтор имени позже прежнего success — failure" 1 '^REASON\tCI-FAILED\tfailure: '

echo "== не прочитано — 2"
mk; echo 'gh: HTTP 502 Bad Gateway' > "$T/c/check-runs.json.err"
run "площадка не отдала check-runs" 2 '^VOID\tcheck-runs на '
mk; grep -v '^PRO-Robotech/kacho	1266	' "$HERE/ci-read-expected.tsv" > "$T/ledger.tsv"
run "пары kacho/1266 нет в ведомости" 2 '^VOID\tпары PRO-Robotech/kacho / 1266 нет' "$T/ledger.tsv"

echo "== близнецы — молчат"
mk; edit check-runs.json '.check_runs = [(.check_runs | sort_by(.name) | .[0]) | .conclusion="failure" | .started_at="2000-01-01T00:00:00Z"] + .check_runs'
run "прежний failure первым в ответе, последний success" 0 '^VERDICT\tgreen\t'
mk; edit check-runs.json '.check_runs += [(.check_runs | sort_by(.name) | .[0]) | .conclusion="failure" | .started_at="2000-01-01T00:00:00Z"]'
run "прежний failure последним в ответе, последний по времени success" 0 '^VERDICT\tgreen\t'
mk; rm "$T/c/protection.json"; echo 'gh: Branch not protected (HTTP 404)' > "$T/c/protection.json.err"
run "защиты ветки нет вовсе" 0 '^CENSUS\tзащиты ветки 1266 нет'
mk; edit status.json '.statuses=[{context:"внешний контекст",state:"success"}]'
run "commit status success вне check-runs" 0 '^VERDICT\tgreen\t.*проверок 69 из 68'

echo
echo "ci-read-inject: случаев $((pass + fail)), сошлось $pass, разошлось $fail"
[ "$fail" -eq 0 ] && [ "$pass" -gt 0 ]
