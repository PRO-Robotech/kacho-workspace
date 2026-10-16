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
# ключами заданий, подменный `.github/scripts/affected.py` печатает свой выбор).
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

cat > "$W/gh" <<'GH'
#!/usr/bin/env bash
[ "$1" = api ] || { echo "fake gh: только api" >&2; exit 64; }
[ ! -f "$CASE/gh-fail" ] || { echo "fake gh: площадка недоступна" >&2; exit 1; }
case "$2" in
    repos/PRO-Robotech/kacho-workspace/issues/1110) printf '{"number":1110,"state":"%s"}\n' "$(cat "$CASE/state" 2>/dev/null || echo open)" ;;
    *) echo "fake gh: путь $2 не известен" >&2; exit 64 ;;
esac
GH
chmod +x "$W/gh"

control() {
    jq -n --arg h "$H" '{head: $h, mode: "full", context: "probe-client", ns: "t3259-w1", residue: 0, planned: 5,
      suites: [
        {name: "go-race", job: "ci.yaml:unit-shard", outcome: "green", executed: 41, total: 41},
        {name: "integration", job: "ci.yaml:integration", outcome: "green", executed: 12, total: 12},
        {name: "newman shard-1", job: "e2e-newman.yml:shard", outcome: "green", executed: 230, total: 230},
        {name: "newman shard-2", job: "e2e-newman.yml:shard", outcome: "green", executed: 198, total: 198},
        {name: "console-e2e", job: "console-e2e.yml:probes", outcome: "green", executed: 64, total: 64}]}'
}
expected() {  # expected [jq-правка] — ожидаемое контроля формы `stand-report.sh expect`
    jq -n --arg h "$H" '{head: $h, repo: "PRO-Robotech/kacho", source: "affected", base: "origin/1266",
      jobs: ["ci.yaml:unit-shard", "ci.yaml:integration", "e2e-newman.yml:shard", "console-e2e.yml:probes"]}' | jq "${1:-.}"
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
    printf 'import sys\nsel = open(".github/scripts/sel").read()\nprint(sel)\nsys.exit(int(open(".github/scripts/rc").read()))\n' > "$C/co/.github/scripts/affected.py"
    printf '%s' "${3:--}" > "$C/co/.github/scripts/sel"; echo 0 > "$C/co/.github/scripts/rc"
    sandbox_run git -C "$C/co" init -q && git -C "$C/co" remote add origin "git@github.com:$2.git"
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
kase "набор выпал: 4 из planned 5" 'del(.suites[4])'; want 1 STAND-REPORT-TRUNCATED
kase "зелёный набор исполнен 200 из 230" '.suites[2].executed = 200'; want 1 STAND-REPORT-TRUNCATED
kase "зелёный набор total 0" '.suites[0].executed = 0 | .suites[0].total = 0'; want 1 STAND-REPORT-TRUNCATED
kase "красный набор с цитатой" '.suites[2] |= (.outcome = "red" | .quote = "expected 404, got 403" | .root = "проба")'; want 1 STAND-REPORT-RED
kase "красный без цитаты" '.suites[2] |= (.outcome = "red")'; want 1 STAND-REPORT-NO-QUOTE
kase "контекст локальный, proof нет" '.context = "kind-kacho"'; want 1 STAND-REPORT-LOCAL
kase "близнец: контекст локальный при proof слота" '.context = "kind-kacho" | .proof = "local class=newman proof=rc=77"'; want 0 -
kase "остаток после прогона 1" '.residue = 1'; want 1 STAND-REPORT-RESIDUE
kase "residue не число" 'del(.residue)'; want 1 STAND-REPORT-RESIDUE
kase "not-run без причины ведомости" '.suites[4] |= (.outcome = "not-run" | .reason = "занято")'; want 1 STAND-REPORT-NOT-RUN
kase "близнец: not-run NO-PR-IMAGES при открытой ws#1110" '.suites[4] |= (.outcome = "not-run" | .reason = "NO-PR-IMAGES")'; want 0 -
kase "not-run NO-PR-IMAGES при закрытой ws#1110 — истекло" '.suites[4] |= (.outcome = "not-run" | .reason = "NO-PR-IMAGES")'; echo closed > "$C/state"; want 1 STAND-RELAX-EXPIRED
kase "площадка о послаблении не ответила — VOID" '.suites[4] |= (.outcome = "not-run" | .reason = "NO-PR-IMAGES")'; : > "$C/gh-fail"; want 2 -
kase "все not-run — исполнено 0" '.suites |= map(.outcome = "not-run" | .reason = "NO-PR-IMAGES")'; want 1 STAND-REPORT-NOTHING-RUN
kase "исход вне словаря" '.suites[1].outcome = "skipped"'; want 1 STAND-REPORT-MISSING
kase "отчёт не объект" -; echo '[]' > "$C/r.json"; want 1 STAND-REPORT-MISSING
kase "файла отчёта нет" -; rm "$C/r.json"; want 1 STAND-REPORT-MISSING
kase "only-red: красный прежде набор пропал" '.mode = "only-red" | .planned = 1 | .suites = [.suites[0]]' '.suites[2] |= (.outcome = "red" | .quote = "q")'; want 1 STAND-REPORT-RED-DROPPED
kase "близнец only-red: прежний красный перепрогнан зелёным" '.mode = "only-red" | .planned = 1 | .suites = [.suites[2]]' '.suites[2] |= (.outcome = "red" | .quote = "q")'; want 0 -
kase "only-red под --of — не mode only-red" '.planned = 5' '.suites[2] |= (.outcome = "red" | .quote = "q")'; want 1 STAND-REPORT-TRUNCATED

kase "ожидаемое newman, набора с этим job нет (D1)" 'del(.suites[2,3]) | .planned = 3'; want 1 STAND-REPORT-UNCOVERED
kase "planned 0 и наборов 0 при непустом ожидаемом" '.planned = 0 | .suites = []'; want 1 STAND-REPORT-UNCOVERED
kase "ожидаемое о другой голове" -; expected ".head = \"$H2\"" > "$C/exp.json"; want 1 STAND-EXPECT-STALE
kase "близнец: выведенный ноль — пустой отчёт при пустом ожидаемом (D2)" '.planned = 0 | .suites = []'; expected '.jobs = [] | .source = "none"' > "$C/exp.json"; want 0 -
kase "близнец: выведенный ноль, наборы сверх ожидаемого зелёные" -; expected '.jobs = []' > "$C/exp.json"; want 0 -
kase "полный прогон без --expect — VOID" -; : > "$C/args"; want 2 -
kase "ожидаемое не формы expect — VOID" -; echo '{"jobs": "все"}' > "$C/exp.json"; want 2 -
kase "зелёный исполнено больше, чем всего (D5)" '.suites[2].executed = 231'; want 1 STAND-REPORT-TRUNCATED
kase "proof не формы журнала слота (D4)" '.context = "kind-kacho" | .proof = "rc=77"'; want 1 STAND-REPORT-LOCAL
ecase "expect kacho: выбор ∩ задания стенда" PRO-Robotech/kacho '{"jobs": ["ci.yaml:lint", "e2e-newman.yml:shard", "console-e2e.yml:probes"]}'; ecommit
printf -- '--base\norigin/main\n' > "$C/args"; want 0 '["e2e-newman.yml:shard","console-e2e.yml:probes"]'
ecase "expect kacho: выбор без заданий стенда — выведенный ноль" PRO-Robotech/kacho '{"jobs": ["ci.yaml:lint"]}'; ecommit
printf -- '--base\norigin/main\n' > "$C/args"; want 0 '[]'
ecase "expect kacho: выбор не выполнился — VOID" PRO-Robotech/kacho '{"jobs": ["e2e-newman.yml:shard"]}'; echo 2 > "$C/co/.github/scripts/rc"; ecommit; printf -- '--base\norigin/main\n' > "$C/args"; want 2 -
ecase "expect kacho без --base — VOID" PRO-Robotech/kacho '{"jobs": []}'; ecommit; want 2 -
ecase "expect kacho: задания ведомости нет в workflow головы — VOID" PRO-Robotech/kacho '{"jobs": []}'
printf 'jobs:\n  shard-renamed: {}\n' > "$C/co/.github/workflows/e2e-newman.yml"; ecommit; printf -- '--base\norigin/main\n' > "$C/args"; want 2 -
ecase "expect kaname: CI без выбора — все задания стенда" PRO-Robotech/kaname; printf 'jobs:\n  stand: {}\n' > "$C/co/.github/workflows/e2e-newman.yml"; ecommit
want 0 '["ci.yml:unit","ci.yml:integration","e2e-newman.yml:stand"]'
ecase "expect kacho-workspace: заданий на кластере нет — выведенный ноль" PRO-Robotech/kacho-workspace; ecommit; want 0 '[]'
ecase "expect: репозиторий вне ведомости — VOID" PRO-Robotech/elsewhere; ecommit; want 2 -
ecase "expect: копия не на голове — VOID" PRO-Robotech/kacho-workspace; ecommit; echo "$H" > "$C/head"; want 2 -

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
affected-rc-ignored	s/    if p.returncode != 0:/    if False:/
checkout-head-ignored	s/\[ "\$got" = "\$HEAD" \] || void/true || void/
unknown-repo-zero	s/^if repo not in STAND:/if False:/
red-ignored	s/elif out == 'red':/elif out == 'never':/
quote-not-required	s/if not q:/if False:/
local-ok	s/if not ctx.endswith('-client') and not re.match/if False and not re.match/
residue-ignored	s/if num(d.get('residue')) != 0:/if False:/
notrun-any-reason	s/if why not in RELAX:/if False and why not in RELAX:/
relax-never-expires	s/alive\[why\] = json.loads(p.stdout).get('state') == 'open'/alive[why] = True/
nothing-run-ok	s/if (suites or expected) and green == 0:/if False:/
red-dropped-ok	s/if s.get('outcome') == 'red' and str(s.get('name')) not in mine:/if False:/
exit-zero	s/sys.exit(1 if reasons else 0)/sys.exit(0)/
MUT
echo "stand-report-inject: мутантов $((killed + survived + void)), убито $killed, выжило $survived, не легло $void"
[ "$fail" -eq 0 ] && [ "$pass" -gt 0 ] && [ "$survived" -eq 0 ] && [ "$void" -eq 0 ] && [ "$killed" -gt 0 ]
