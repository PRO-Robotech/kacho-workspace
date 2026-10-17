#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# stand-report-inject.sh — доказательство scripts/stand-report.sh ИСПОЛНЕНИЕМ (ws#1110).
#
# ВХОД. Контроль — отчёт формы, которую пишет ci-watcher шагом mech:stand шаблона волны:
# голова, mode full, контекст -client, ns t<N>-w<k>, residue 0, planned = числу наборов;
# состав наборов — затронутое kacho#3259 (go-race, integration, newman двух шардов,
# console-e2e). Живого отчёта до ws#1110 в дереве нет: первый прогон шага mech:stand
# заменит синтетику своим отчётом (предикат снятия — файл scripts/stand-report-fixtures/
# живого прогона; до него вход — эта форма). Каждый случай меняет РОВНО один факт
# контроля и ждёт свой код причины; близнец той же формы — молчание.
# Площадка подменена: STAND_REPORT_GH отдаёт state задачи послабления из файла случая.
# ОЖИДАЕМОЕ — файл формы `stand-report.sh expect`, задания контроля; подкоманду `expect`
# судят случаи на песочных git-копиях (origin — url репозитория ведомости, workflow с
# ключами заданий). Для kacho выбор в копии — НАСТОЯЩИЙ `.github/scripts/affected.py` и
# `.github/ci-paths.json` ствола kacho (`STAND_REPORT_KACHO`, иначе `project/kacho`
# воркспейса; конвейер кладёт их туда шагом checkout), и каждое ожидаемое сверяется с
# ДЕТЕКТОРОМ CI того же файла: `affected.py --github-output <workflow>` при EVENT,
# DRAFT, BASE события запроса (пути запроса — подменный `gh` из `git diff` копии),
# задание = `full == 'true' || contains(jobs, <ключ>)` — условие `if:` заданий kacho.
# Паритет — для ready в ветку эпика, черновика в `main` и целевого черновика в эпик
# (ws#1110, возврат check-verifier: «DRAFT=false — полный набор 3 из 3, expect — 1 из 5»).
#
# МУТАНТЫ — по правке stand-report.sh на свойство; каждый обязан покраснеть хотя бы
# одним случаем, правка, не легшая в текст, — VOID, а не «убит».
# Коды: 0 — все случаи сошлись и все мутанты убиты; 1 — нет; 2 — нет jq/python3.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/stand-report.sh"
for t in jq python3; do command -v "$t" > /dev/null 2>&1 || { echo "stand-report-inject: VOID — нет $t" >&2; exit 2; }; done
W="$(mktemp -d "${TMPDIR:-/tmp}/stand-report-inject.XXXXXX")" || exit 2
trap 'rm -rf "$W"' EXIT
# shellcheck source=lib/sandbox-git-home.sh
. "$HERE/lib/sandbox-git-home.sh"
sandbox_git_home "$W/home" || { echo "stand-report-inject: VOID — подписи песочницы нет" >&2; exit 2; }
H="$(printf 'a%.0s' $(seq 40))"; H2="$(printf 'b%.0s' $(seq 40))"
K="${STAND_REPORT_KACHO:-$HERE/../project/kacho}"
for f in .github/scripts/affected.py .github/ci-paths.json; do
    [ -r "$K/$f" ] || { echo "stand-report-inject: VOID — нет $K/$f: выбор kacho судить не с чем (STAND_REPORT_KACHO либо project/kacho)" >&2; exit 2; }
done
echo "== выбор kacho — настоящий: $K @$(git -C "$K" rev-parse --short=12 HEAD 2>/dev/null || echo 'не git')"
# Пути запроса для детектора CI: `gh api … pulls/<N>/files … --jq` → дифф копии случая.
mkdir -p "$W/ghpr"
cat > "$W/ghpr/gh" <<'GH'
#!/usr/bin/env bash
case "$*" in *"/pulls/"*"/files"*) git -C "$CO" diff --name-only --no-renames "$BASEREF...HEAD" ;; *) echo "fake gh: $*" >&2; exit 64 ;; esac
GH
chmod +x "$W/ghpr/gh"
# detected <копия> <draft> <база-ветка> <ledger JSON> — задания ведомости, которые
# исполнит CI по детекторам `--github-output` (условие `if:` заданий kacho).
detected() {
    local co="$1" d="$2" b="$3" wf out
    for wf in $(jq -r '.[] | split(":")[0]' <<< "$4" | sort -u); do
        out="$co.go.$wf"; : > "$out"
        (cd "$co" && CO="$co" BASEREF="origin/$b" PATH="$W/ghpr:$PATH" EVENT=pull_request DRAFT="$d" BASE="$b" REPO=PRO-Robotech/kacho PR=1 \
            GITHUB_OUTPUT="$out" python3 .github/scripts/affected.py --github-output "$wf" > /dev/null 2>&1) || { echo "DETECTOR-VOID $wf"; return; }
    done
    python3 - "$co" "$4" <<'PY'
import json, sys
co, ledger = sys.argv[1], json.loads(sys.argv[2])
out = []
for j in ledger:
    wf, key = j.split(':', 1)
    kv = dict(l.split('=', 1) for l in open('%s.go.%s' % (co, wf), encoding='utf-8').read().splitlines() if '=' in l)
    if kv.get('full') == 'true' or key in json.loads(kv.get('jobs', '[]')):
        out.append(j)
print(json.dumps(out, separators=(',', ':')))
PY
}

cat > "$W/gh" <<'GH'
#!/usr/bin/env bash
[ "$1" = api ] || { echo "fake gh: только api" >&2; exit 64; }
[ ! -f "$CASE/gh-fail" ] || { echo "fake gh: площадка недоступна" >&2; exit 1; }
case "$2" in
    # Послабление NO-PR-IMAGES — до kacho#3260; ws#1110, прежняя его задача, закрыта — как на площадке.
    repos/PRO-Robotech/kacho/issues/3260) printf '{"number":3260,"state":"%s"}\n' "$(cat "$CASE/state" 2>/dev/null || echo open)" ;;
    repos/PRO-Robotech/kacho-workspace/issues/1110) printf '{"number":1110,"state":"closed"}\n' ;;
    repos/*/compare/*) [ ! -f "$CASE/cmp-fail" ] || { echo "fake gh: compare недоступен" >&2; exit 1; }; cat "$CASE/compare.json" ;;
    *) echo "fake gh: путь $2 не известен" >&2; exit 64 ;;
esac
GH
chmod +x "$W/gh"

control() {
    jq -n --arg h "$H" '{head: $h, mode: "full", context: "probe-client", ns: "t3259-w1", residue: 0, planned: 6,
      suites: [
        {name: "go-race", job: "ci.yaml:unit-shard", outcome: "green", executed: 41, total: 41},
        {name: "integration", job: "ci.yaml:integration", outcome: "green", executed: 12, total: 12},
        {name: "newman shard-1", job: "e2e-newman.yml:shard", outcome: "green", executed: 230, total: 230},
        {name: "newman shard-2", job: "e2e-newman.yml:shard", outcome: "green", executed: 198, total: 198},
        {name: "console-e2e", job: "console-e2e.yml:probes", outcome: "green", executed: 64, total: 64},
        {name: "posture", job: "production-posture.yml:stand", outcome: "green", executed: 7, total: 7}]}'
}
LEDGER='["ci.yaml:unit-shard","ci.yaml:integration","e2e-newman.yml:shard","console-e2e.yml:probes","production-posture.yml:stand"]'
expected() {  # expected [jq-правка] — ожидаемое контроля: дословная форма вывода `stand-report.sh expect` при ready
    jq -n --arg h "$H" --argjson l "$LEDGER" '{head: $h, repo: "PRO-Robotech/kacho", source: "affected", base: "origin/1266",
      draft: "false", full: true, reason: "ready", ledger: $l, jobs: $l}' | jq "${1:-.}"
}
NC=0; pass=0; fail=0
# kase <имя> <jq-правка контроля | -> [довод --of: jq-правка прежнего] — отчёт случая
kase() {
    NC=$((NC + 1)); C="$W/c$NC"; mkdir -p "$C"; printf '%s' "$1" > "$C/name"
    if [ "$2" = - ]; then control > "$C/r.json"; else control | jq "$2" > "$C/r.json"; fi
    expected > "$C/exp.json"; printf -- '--expect\n%s\n' "$C/exp.json" > "$C/args"
    if [ -n "${3:-}" ]; then control | jq "$3" > "$C/prev.json"; printf -- '--of\n%s\n' "$C/prev.json" > "$C/args"; fi
}
# ecase <имя> <репозиторий origin> <выбор affected.py | -> — песочная копия для `expect`
ecase() {
    NC=$((NC + 1)); C="$W/c$NC"; mkdir -p "$C/co/.github/workflows" "$C/co/.github/scripts"; printf '%s' "$1" > "$C/name"; : > "$C/expect"
    printf 'jobs:\n  unit-shard: {}\n  integration: {}\n' > "$C/co/.github/workflows/ci.yaml"
    printf 'jobs:\n  shard: {}\n' > "$C/co/.github/workflows/e2e-newman.yml"
    printf 'jobs:\n  probes: {}\n' > "$C/co/.github/workflows/console-e2e.yml"
    printf 'jobs:\n  stand: {}\n' > "$C/co/.github/workflows/production-posture.yml"
    printf 'jobs:\n  unit: {}\n  integration: {}\n' > "$C/co/.github/workflows/ci.yml"
    [ "$2" != PRO-Robotech/kacho ] || cp "$K/.github/scripts/affected.py" "$C/co/.github/scripts/" && { [ "$2" != PRO-Robotech/kacho ] || cp "$K/.github/ci-paths.json" "$C/co/.github/"; }
    sandbox_run git -C "$C/co" init -q && git -C "$C/co" remote add origin "git@github.com:$2.git"
}
# kecase <имя> <draft> <база-ветка> <путь правки> <ожидаемое JSON> — копия kacho: база —
# origin/main и origin/1266, голова правит путь; ожидаемое сверено с детектором CI.
kecase() {
    ecase "$1" PRO-Robotech/kacho; sandbox_run git -C "$C/co" add -A && sandbox_run git -C "$C/co" commit -qm base
    git -C "$C/co" update-ref refs/remotes/origin/main HEAD; git -C "$C/co" update-ref refs/remotes/origin/1266 HEAD
    mkdir -p "$C/co/$(dirname "$4")"; echo x > "$C/co/$4"; ecommit
    printf -- '--base\norigin/%s\n--draft\n%s\n' "$3" "$2" > "$C/args"
    local det; det="$(detected "$C/co" "$2" "$3" "$(jq -c '[.[]]' <<< "$LEDGER")")"
    if [ "$det" = "$5" ]; then pass=$((pass + 1)); echo "  [OK]   паритет с --github-output: $1 — CI исполнит $det"
    else fail=$((fail + 1)); echo "  [FAIL] паритет с --github-output: $1 — детектор CI даёт «$det», а случай ждёт «$5»" >&2; fi
    want 0 "$det"
}
ecommit() { sandbox_run git -C "$C/co" add -A && sandbox_run git -C "$C/co" commit -qm c && git -C "$C/co" rev-parse HEAD > "$C/head"; }
# want <код> <код причины | -> — ожидание случая; «-» — ни одной строки REASON
want() { printf '%s' "$1" > "$C/code"; printf '%s' "$2" > "$C/want"; }
judge() {  # judge <скрипт> <каталог случая> → 0 сошлось
    local c="$2" out code
    if [ -f "$c/expect" ]; then  # случай подкоманды expect: код и задания либо строка VOID
        local eargs=(); [ ! -f "$c/args" ] || mapfile -t eargs < "$c/args"
        out="$(bash "$1" expect --checkout "$c/co" --head "$(cat "$c/head")" "${eargs[@]}" 2>/dev/null)"; code=$?
        printf '%s\n' "$out" > "$c/out.$(basename "$1")"
        [ "$code" = "$(cat "$c/code")" ] || return 1
        if [ "$code" = 0 ]; then [ "$(jq -c .jobs <<< "$out" 2>/dev/null)" = "$(cat "$c/want")" ]
        else grep -q "^VOID" <<< "$out"; fi
        return
    fi
    local extra; mapfile -t extra < "$c/args"
    out="$(CASE="$c" STAND_REPORT_GH="$W/gh" bash "$1" check "$c/r.json" --head "$(cat "$c/head" 2>/dev/null || echo "$H")" "${extra[@]}" 2>&1)"; code=$?
    printf '%s\n' "$out" > "$c/out.$(basename "$1")"
    [ "$code" = "$(cat "$c/code")" ] || return 1
    if [ "$(cat "$c/want")" = - ]; then ! grep -q '^REASON' <<< "$out"
    else grep -qP "^REASON\t$(cat "$c/want")\t" <<< "$out"; fi
}

kase "контроль: полный, внешний, всё зелёное" -; want 0 -
kase "голова другая" -; echo "$H2" > "$C/head"; want 1 STAND-REPORT-STALE
kase "only-red без --of" '.mode = "only-red"'; want 1 STAND-REPORT-NOT-FULL
kase "набор выпал: 5 из planned 6" 'del(.suites[4]) | .suites += [.suites[0]] | .planned = 7'; want 1 STAND-REPORT-TRUNCATED
kase "зелёный набор исполнен 200 из 230" '.suites[2].executed = 200'; want 1 STAND-REPORT-TRUNCATED
kase "зелёный набор total 0" '.suites[0].executed = 0 | .suites[0].total = 0'; want 1 STAND-REPORT-TRUNCATED
kase "красный набор с цитатой" '.suites[2] |= (.outcome = "red" | .quote = "expected 404, got 403" | .root = "проба")'; want 1 STAND-REPORT-RED
kase "красный без цитаты" '.suites[2] |= (.outcome = "red")'; want 1 STAND-REPORT-NO-QUOTE
kase "контекст локальный, proof нет" '.context = "kind-kacho"'; want 1 STAND-REPORT-LOCAL
kase "близнец: контекст локальный при proof слота" '.context = "kind-kacho" | .proof = "local class=newman proof=rc=77"'; want 0 -
kase "остаток после прогона 1" '.residue = 1'; want 1 STAND-REPORT-RESIDUE
kase "residue не число" 'del(.residue)'; want 1 STAND-REPORT-RESIDUE
kase "not-run без причины ведомости" '.suites[4] |= (.outcome = "not-run" | .reason = "занято")'; want 1 STAND-REPORT-NOT-RUN
kase "близнец: not-run NO-PR-IMAGES при открытой kacho#3260" '.suites[4] |= (.outcome = "not-run" | .reason = "NO-PR-IMAGES")'; want 0 -
kase "not-run NO-PR-IMAGES при закрытой kacho#3260 — истекло" '.suites[4] |= (.outcome = "not-run" | .reason = "NO-PR-IMAGES")'; echo closed > "$C/state"; want 1 STAND-RELAX-EXPIRED
kase "послабление NO-PR-IMAGES спрашивает kacho#3260: закрытая ws#1110 его не гасит" '.suites[2] |= (.outcome = "not-run" | .reason = "NO-PR-IMAGES")'; want 0 -
kase "площадка о послаблении не ответила — VOID" '.suites[4] |= (.outcome = "not-run" | .reason = "NO-PR-IMAGES")'; : > "$C/gh-fail"; want 2 -
kase "все not-run — исполнено 0" '.suites |= map(.outcome = "not-run" | .reason = "NO-PR-IMAGES")'; want 1 STAND-REPORT-NOTHING-RUN
kase "исход вне словаря" '.suites[1].outcome = "skipped"'; want 1 STAND-REPORT-MISSING
kase "отчёт не объект" -; echo '[]' > "$C/r.json"; want 1 STAND-REPORT-MISSING
kase "файла отчёта нет" -; rm "$C/r.json"; want 1 STAND-REPORT-MISSING
kase "only-red: красный прежде набор пропал" '.mode = "only-red" | .planned = 1 | .suites = [.suites[0]]' '.suites[2] |= (.outcome = "red" | .quote = "q")'; want 1 STAND-REPORT-RED-DROPPED
kase "близнец only-red: прежний красный перепрогнан зелёным" '.mode = "only-red" | .planned = 1 | .suites = [.suites[2]]' '.suites[2] |= (.outcome = "red" | .quote = "q")'; want 0 -
kase "only-red под --of — не mode only-red" '.planned = 6' '.suites[2] |= (.outcome = "red" | .quote = "q")'; want 1 STAND-REPORT-TRUNCATED

kase "ожидаемое newman, набора с этим job нет (D1)" 'del(.suites[2,3]) | .planned = 4'; want 1 STAND-REPORT-UNCOVERED
kase "planned 0 и наборов 0 при непустом ожидаемом" '.planned = 0 | .suites = []'; want 1 STAND-REPORT-UNCOVERED
kase "ожидаемое о другой голове" -; expected ".head = \"$H2\"" > "$C/exp.json"; want 1 STAND-EXPECT-STALE
WSZERO='.repo = "PRO-Robotech/kacho-workspace" | .source = "none" | .ledger = [] | .jobs = [] | .draft = null'
kase "близнец: выведенный ноль — пустой отчёт при пустом ожидаемом (D2)" '.planned = 0 | .suites = []'; expected "$WSZERO" > "$C/exp.json"; want 0 -
kase "близнец: выведенный ноль, наборы сверх ожидаемого зелёные" -; expected "$WSZERO" > "$C/exp.json"; want 0 -
kase "ожидаемое ready kacho «full: true, jobs: []» — полный обязан нести все задания" -; expected '.jobs = []' > "$C/exp.json"; want 1 STAND-EXPECT-LEDGER
kase "ожидаемое ready kacho: заданий 4 из ведомости 5" -; expected '.jobs |= .[:4]' > "$C/exp.json"; want 1 STAND-EXPECT-LEDGER
kase "ожидаемое: ledger подменён двумя заданиями" -; expected '.ledger |= .[:2] | .jobs = .ledger' > "$C/exp.json"; want 1 STAND-EXPECT-LEDGER
kase "ожидаемое: задание вне ведомости" -; expected '.jobs += ["ci.yaml:lint"]' > "$C/exp.json"; want 1 STAND-EXPECT-LEDGER
kase "ожидаемое: репозиторий вне ведомости" -; expected '.repo = "PRO-Robotech/elsewhere"' > "$C/exp.json"; want 1 STAND-EXPECT-LEDGER
kase "ожидаемое: источник не ведомости (none у kacho)" -; expected '.source = "none"' > "$C/exp.json"; want 1 STAND-EXPECT-LEDGER
kase "близнец only-red: целевой черновик, часть заданий — полнотой не судится" '.mode = "only-red" | .planned = 2 | .suites = [.suites[0], .suites[2]]' '.suites[2] |= (.outcome = "red" | .quote = "q")'; expected '.draft = "true" | .full = false | .jobs = ["ci.yaml:unit-shard","e2e-newman.yml:shard"]' > "$C/exp.json"; printf -- '--of\n%s\n--expect\n%s\n' "$C/prev.json" "$C/exp.json" > "$C/args"; want 0 -
kase "ожидаемое о другом репозитории, чем запрос" -; printf -- '--expect\n%s\n--pr-repo\nPRO-Robotech/kaname\n' "$C/exp.json" > "$C/args"; want 1 STAND-EXPECT-REPO
kase "близнец: репозиторий ожидаемого — репозиторий запроса" -; printf -- '--expect\n%s\n--pr-repo\nPRO-Robotech/kacho\n' "$C/exp.json" > "$C/args"; want 0 -
kase "ожидаемое выбора черновика — основанием ready не служит" -; expected '.draft = "true"' > "$C/exp.json"; want 1 STAND-EXPECT-DRAFT
kase "ожидаемое без поля draft — не выбор ready" -; expected 'del(.draft)' > "$C/exp.json"; want 1 STAND-EXPECT-DRAFT
kase "близнец only-red: ожидаемое черновика не судится" '.mode = "only-red" | .planned = 1 | .suites = [.suites[2]]' '.suites[2] |= (.outcome = "red" | .quote = "q")'; want 0 -
kase "ожидаемое от другой базы, чем у запроса" -; printf -- '--expect\n%s\n--pr-base\nmain\n' "$C/exp.json" > "$C/args"; want 1 STAND-EXPECT-BASE
kase "близнец: база ожидаемого — база запроса" -; printf -- '--expect\n%s\n--pr-base\n1266\n' "$C/exp.json" > "$C/args"; want 0 -
kase "полный прогон без --expect — VOID" -; : > "$C/args"; want 2 -
kase "ожидаемое не формы expect — VOID" -; echo '{"jobs": "все"}' > "$C/exp.json"; want 2 -
kase "зелёный исполнено больше, чем всего (D5)" '.suites[2].executed = 231'; want 1 STAND-REPORT-TRUNCATED
kase "proof не формы журнала слота (D4)" '.context = "kind-kacho" | .proof = "rc=77"'; want 1 STAND-REPORT-LOCAL
kecase "expect kacho: ready в ветку эпика — полный прогон, все задания стенда" false 1266 tests/newman/x.json "$LEDGER"
kecase "expect kacho: черновик в main — полный прогон" true main tests/newman/x.json "$LEDGER"
kecase "expect kacho: черновик в эпик — целевой выбор ∩ задания стенда" true 1266 tests/newman/x.json '["ci.yaml:unit-shard","e2e-newman.yml:shard"]'
kecase "expect kacho: черновик в эпик, правка Go — интеграция и стенд" true 1266 services/x/a.go '["ci.yaml:unit-shard","ci.yaml:integration","e2e-newman.yml:shard","console-e2e.yml:probes","production-posture.yml:stand"]'
ecase "expect kacho: карта путей не разбирается — VOID" PRO-Robotech/kacho; echo '{' > "$C/co/.github/ci-paths.json"; ecommit; printf -- '--base\norigin/main\n--draft\nfalse\n' > "$C/args"; want 2 -
ecase "expect kacho без --base — VOID" PRO-Robotech/kacho; ecommit; printf -- '--draft\nfalse\n' > "$C/args"; want 2 -
ecase "expect kacho без --draft — VOID" PRO-Robotech/kacho; ecommit; printf -- '--base\norigin/main\n' > "$C/args"; want 2 -
kecase "expect kacho: черновик в эпик, дифф пуст — VOID" true 1266 tests/newman/x.json '["ci.yaml:unit-shard","e2e-newman.yml:shard"]'
git -C "$C/co" update-ref refs/remotes/origin/1266 HEAD; want 2 -
kecase "expect kacho: правка вне коммита в копии — VOID" false 1266 tests/newman/x.json "$LEDGER"; echo y > "$C/co/untracked.txt"; want 2 -
ecase "expect kacho: задания ведомости нет в workflow головы — VOID" PRO-Robotech/kacho
printf 'jobs:\n  shard-renamed: {}\n' > "$C/co/.github/workflows/e2e-newman.yml"; ecommit; printf -- '--base\norigin/main\n--draft\nfalse\n' > "$C/args"; want 2 -
ecase "expect kaname: CI без выбора — все задания стенда" PRO-Robotech/kaname; printf 'jobs:\n  stand: {}\n' > "$C/co/.github/workflows/e2e-newman.yml"; ecommit
want 0 '["ci.yml:unit","ci.yml:integration","e2e-newman.yml:stand"]'
ecase "expect kacho-workspace: заданий на кластере нет — выведенный ноль" PRO-Robotech/kacho-workspace; ecommit; want 0 '[]'
ecase "expect: репозиторий вне ведомости — VOID" PRO-Robotech/elsewhere; ecommit; want 2 -
ecase "expect: копия не на голове — VOID" PRO-Robotech/kacho-workspace; ecommit; echo "$H" > "$C/head"; want 2 -

# ПЕРЕНОС (ws#1148). Вход — живой случай kacho#3265: полный отчёт @825364b5 (A), голова
# 4283bcfb (B) правит лишь пробу ban6; вывод inputs — ДОСЛОВНО из прогона
# tmp/w9/m3258-full-4283bcfb/inputs-825364b5-vs-4283bcfb.txt. Контроль: ban6 и unit
# прогнаны на B, остальное перенесено с A, образы стенда — A. Случай меняет один факт.
HA="$(printf 'c%.0s' $(seq 40))"; BAN6=deploy/scripts/assert-ban6-external-isolation.py
INP0="  не вход $BAN6 — не доезжает ни до одного образа
stand-ns inputs: Dockerfile 23, контекстов 9, образов go 7; изменённых путей 1, из них входов сборки 0"
csuites() {  # наборы стенда живой формы; $1 — head отчёта
    jq -n --arg h "$1" '{head: $h, mode: "full", context: "a8f60d-client", ns: "t3258-w9", residue: 0, planned: 7, suites: [
        {name: "unit:all-shards", job: "ci.yaml:unit-shard", outcome: "green", executed: 295, total: 295},
        {name: "integration:vpc", job: "ci.yaml:integration", outcome: "green", executed: 10, total: 10},
        {name: "newman:vpc", job: "e2e-newman.yml:shard", outcome: "green", executed: 3851, total: 3851},
        {name: "newman:ban6-external-isolation", job: "e2e-newman.yml:shard", outcome: "green", executed: 1, total: 1},
        {name: "playwright:probes", job: "console-e2e.yml:probes", outcome: "green", executed: 319, total: 319},
        {name: "posture:dev-prod", job: "production-posture.yml:stand", outcome: "green", executed: 4, total: 4},
        {name: "posture:own", job: "production-posture.yml:stand", outcome: "green", executed: 2, total: 2}]}'
}
# ckase <имя> <jq-правка отчёта B | -> [jq-правка отчёта A] — compare.json: A предок B, путь ban6
ckase() {
    NC=$((NC + 1)); C="$W/c$NC"; mkdir -p "$C"; printf '%s' "$1" > "$C/name"
    local rb="${2:--}" ra="${3:--}"; [ "$rb" != - ] || rb=.; [ "$ra" != - ] || ra=.
    csuites "$H" | jq --arg a "$HA" --arg inp "$INP0" --arg p "$BAN6" '.images_rev = $a
        | .suites |= map(if (.name | test("^(unit|newman:ban6)")) then . else . + {carried_from: $a} end)
        | .carry_basis = {($a): {changed: [$p], inputs: $inp, inputs_rc: 0, report: "src.json"}}' | jq --arg a "$HA" --arg h "$H" "$rb" > "$C/r.json"
    csuites "$HA" | jq "$ra" > "$C/src.json"
    jq -n --arg p "$BAN6" '{status: "ahead", ahead_by: 1, behind_by: 0, files: [{filename: $p}]}' > "$C/compare.json"
    expected > "$C/exp.json"; printf -- '--expect\n%s\n--pr-repo\nPRO-Robotech/kacho\n' "$C/exp.json" > "$C/args"
}
ckase "перенос: входов 0, область не задета — check 0" -; want 0 -
ckase "перенос: ban6 перенесён, хотя его файл изменился" '.suites[3].carried_from = $a'; want 1 STAND-CARRY-AREA
ckase "перенос: ban6 не прогнан после правки — not-run" '.suites[3] |= (.outcome = "not-run" | .reason = "CARRY-AREA" | .executed = 0)'; want 1 STAND-REPORT-NOT-RUN
ckase "перенос: unit перенесён — читает всё дерево" '.suites[0].carried_from = $a'; want 1 STAND-CARRY-AREA
X=services/vpc/internal/app/x.go
ckase "перенос: вход сборки изменён — запрещён" ".carry_basis[\$a] |= (.changed += [\"$X\"] | .inputs_rc = 1 | .inputs = \"  ВХОД    $X — образ vpc\n  не вход $BAN6 — нет\nstand-ns inputs: Dockerfile 23, контекстов 9, образов go 7; изменённых путей 2, из них входов сборки 1\")"
jq --arg x "$X" '.files += [{filename: $x}]' "$C/compare.json" > "$C/c" && mv "$C/c" "$C/compare.json"; want 1 STAND-CARRY-INPUTS
D=docs/x.md
ckase "перенос: путь вне ведомости областей — закрыто" ".carry_basis[\$a] |= (.changed += [\"$D\"] | .inputs = \"  не вход $D — нет\n  не вход $BAN6 — нет\nstand-ns inputs: Dockerfile 23, контекстов 9, образов go 7; изменённых путей 2, из них входов сборки 0\")"
jq --arg x "$D" '.files += [{filename: $x}]' "$C/compare.json" > "$C/c" && mv "$C/c" "$C/compare.json"; want 1 STAND-CARRY-AREA
ckase "перенос: перечень путей отчёта короче площадки" -; jq --arg x "$D" '.files += [{filename: $x}]' "$C/compare.json" > "$C/c" && mv "$C/c" "$C/compare.json"; want 1 STAND-CARRY-BASIS
ckase "перенос: вывод inputs не называет путь разности" ".carry_basis[\$a].inputs = \"stand-ns inputs: Dockerfile 23, контекстов 9, образов go 7; изменённых путей 1, из них входов сборки 0\""; want 1 STAND-CARRY-BASIS
ckase "перенос: обоснования для ревизии нет" '.carry_basis = {}'; want 1 STAND-CARRY-BASIS
ckase "перенос: A не предок головы" -; jq '.status = "diverged" | .behind_by = 2' "$C/compare.json" > "$C/c" && mv "$C/c" "$C/compare.json"; want 1 STAND-CARRY-BASIS
ckase "перенос: перечень площадки обрезан на 300" -; jq '.files = [range(300) | {filename: "f\(.)"}]' "$C/compare.json" > "$C/c" && mv "$C/c" "$C/compare.json"; want 1 STAND-CARRY-BASIS
ckase "перенос: в источнике набор красный" - '.suites[2] |= (.outcome = "red" | .quote = "q")'; want 1 STAND-CARRY-SOURCE
ckase "перенос: число исполненного разошлось с источником" - '.suites[2].executed = 3850 | .suites[2].total = 3850'; want 1 STAND-CARRY-SOURCE
ckase "перенос: источник о другой ревизии" - ".head = \"$H2\""; want 1 STAND-CARRY-SOURCE
ckase "перенос: источник не на внешнем стенде" - '.context = "kind-kacho"'; want 1 STAND-CARRY-SOURCE
ckase "перенос: образы источника — третья ревизия без обоснования" - ".images_rev = \"$H2\""; want 1 STAND-CARRY-BASIS
ckase "образы стенда ≠ голова без обоснования, переноса нет" 'del(.suites[] | .carried_from) | .carry_basis = {}'; want 1 STAND-CARRY-BASIS
ckase "близнец: образы стенда = голова, переноса нет" 'del(.suites[] | .carried_from) | del(.carry_basis) | .images_rev = $h'; want 0 -
ckase "перенос: репозиторий без ведомости областей — закрыто" -; printf -- '--expect\n%s\n--pr-repo\nPRO-Robotech/kaname\n' "$C/exp.json" > "$C/args"; want 1 STAND-CARRY-AREA
ckase "перенос: площадка о разности не ответила — VOID" -; : > "$C/cmp-fail"; want 2 -

echo "== случаи"
for c in "$W"/c*; do
    if judge "$TOOL" "$c"; then pass=$((pass + 1)); echo "  [OK]   $(cat "$c/name")"
    else fail=$((fail + 1)); echo "  [FAIL] $(cat "$c/name") — ждали код $(cat "$c/code") и «$(cat "$c/want")»:" >&2; sed 's/^/         /' "$c/out.stand-report.sh" >&2 2>/dev/null; fi
done
echo "stand-report-inject: случаев $NC, сошлось $pass, разошлось $fail"

echo "== мутанты — каждый обязан покраснеть"
killed=0; survived=0; void=0
while IFS=$'\t' read -r name expr; do
    [ -n "$name" ] || continue
    M="$W/m-$name.sh"; sed -e "$expr" "$TOOL" > "$M"
    if cmp -s "$M" "$TOOL"; then void=$((void + 1)); echo "  MUTANT $name → RESULT VOID (правка не легла)"; continue; fi
    red=0; for c in "$W"/c*; do judge "$M" "$c" || red=$((red + 1)); done
    if [ "$red" -gt 0 ]; then killed=$((killed + 1)); echo "  MUTANT $name → RESULT KILLED (разошлось $red из $NC)"
    else survived=$((survived + 1)); echo "  MUTANT $name → RESULT SURVIVED"; fi
done <<'MUT'
stale-dropped	s/if d\['head'\] != head:/if False:/
full-not-required	s/if d\['mode'\] != want:/if False:/
planned-not-compared	s/if planned < 0 or planned != len(suites):/if planned < 0:/
green-partial-ok	s/if tot < 1 or ex != tot:/if tot < 1 or ex > tot:/
green-over-total-ok	s/if tot < 1 or ex != tot:/if tot < 1 or ex < tot:/
uncovered-ignored	s/            if j not in have:/            if False:/
expect-stale-ignored	s/    if e\['head'\] != head:/    if False:/
expect-optional	s/\[ -n "\$OF" \] || \[ -n "\$EXP" \] || void/true || void/
proof-any-form	s/not re.match(r'local\\b.*\\bproof=\\S', proof)/not proof/
ledger-drift-ignored	s/    if not (isinstance(doc, dict) and isinstance(doc.get('jobs'), dict) and key in doc\['jobs'\]):/    if False:/
affected-not-intersected	s/    want = \[j for j in jobs if j in picked\]/    want = list(jobs)/
draft-ignored	s/        full, why = af.event_mode(m, 'pull_request', draft,/        full, why = False, ''; af.event_mode(m, 'pull_request', draft,/
draft-always-full	s/        if not full:/        if False:/
own-selection	s/            sel = af.select(m, af.git_changed(base))/            sel = af.select(m, ['tests\/x.json'])/
empty-diff-ok	s/            if not sel.files:/            if False:/
draft-optional	s/    if not base or not draft:/    if not base:/
expect-draft-ignored	s/    if not of and e.get('source') == 'affected' and e.get('draft') != 'false':/    if False:/
expect-base-ignored	s/    if prb and e.get('source') == 'affected'/    if False and prb/
dirty-copy-ok	s/    \[ -z "\$dirty" \] || void/    true || void/
pycache-written	s/        sys.dont_write_bytecode = True/        pass/
checkout-head-ignored	s/\[ "\$got" = "\$HEAD" \] || void/true || void/
unknown-repo-zero	s/^if repo not in STAND:/if False:/
red-ignored	s/elif out == 'red':/elif out == 'never':/
quote-not-required	s/if not q:/if False:/
local-ok	s/if not ctx.endswith('-client') and not re.match/if False and not re.match/
residue-ignored	s/if num(d.get('residue')) != 0:/if False:/
notrun-any-reason	s/if why not in RELAX:/if False and why not in RELAX:/
relax-bound-to-closed-1110	s/    'NO-PR-IMAGES': ('PRO-Robotech\/kacho', '3260',/    'NO-PR-IMAGES': ('PRO-Robotech\/kacho-workspace', '1110',/
relax-never-expires	s/alive\[why\] = json.loads(p.stdout).get('state') == 'open'/alive[why] = True/
nothing-run-ok	s/if (suites or expected) and green == 0:/if False:/
red-dropped-ok	s/if s.get('outcome') == 'red' and str(s.get('name')) not in mine:/if False:/
exit-zero	s/sys.exit(1 if reasons else 0)/sys.exit(0)/
ledger-full-ignored	s/                and sorted(set(expected)) != sorted(ledger)):/                and False):/
ledger-out-ignored	s/        if out:/        if False:/
ledger-source-ignored	s/        if e.get('source') != src or e.get('ledger') != ledger:/        if False:/
ledger-repo-ignored	s/    if erepo not in STAND:/    if erepo not in STAND and False:/
expect-repo-ignored	s/    if prr and erepo != prr:/    if False:/
carry-area-read-ok	s/        if hit:/        if False:/
carry-unknown-path-ok	s/        if unknown:/        if False:/
carry-whole-tree-ok	s/        if any(fnmatch.fnmatchcase(name, w) for w in area\['whole_tree'\]):/        if False:/
carry-no-area-ok	s/        if not area:/        if False:/
carry-inputs-trusted	s/        if b.get('inputs_rc') != 0 or not tot or tot.group(2) != '0' or 'ВХОД' in rows.values():/        if not tot:/
carry-paths-trusted	s/        if rec != plat:/        if False:/
carry-inputs-partial-ok	s/        if set(rows) != plat or int(tot.group(1)) != len(plat):/        if False:/
carry-ancestor-ignored	s/        if behind != 0 or st not in ('ahead', 'identical'):/        if False:/
carry-truncated-ok	s/        if len(c\['files'\]) >= 300:/        if False:/
carry-basis-missing-ok	s/        if not (isinstance(b, dict) and isinstance(b.get('changed'), list) and isinstance(b.get('inputs'), str)):/        if False:/
carry-source-unchecked	s/            reason('STAND-CARRY-SOURCE'/            continue; reason('STAND-CARRY-SOURCE'/
carry-source-head-ignored	s/        if (src is None or src\['head'\] != r or/        if (src is None or/
carry-source-local-ok	s/                or not (str(src.get('context') or '').endswith('-client')/                or False and not (str(src.get('context') or '').endswith('-client')/
carry-src-images-ignored	s/        if xi != head and base(xi,/        if False and base(xi,/
images-rev-unjudged	s/    if img not in (None, head):/    if False:/
MUT
echo "stand-report-inject: мутантов $((killed + survived + void)), убито $killed, выжило $survived, не легло $void"
[ "$fail" -eq 0 ] && [ "$pass" -gt 0 ] && [ "$survived" -eq 0 ] && [ "$void" -eq 0 ] && [ "$killed" -gt 0 ]
