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
        {name: "go-race", outcome: "green", executed: 41, total: 41},
        {name: "integration", outcome: "green", executed: 12, total: 12},
        {name: "newman shard-1", outcome: "green", executed: 230, total: 230},
        {name: "newman shard-2", outcome: "green", executed: 198, total: 198},
        {name: "console-e2e", outcome: "green", executed: 64, total: 64}]}'
}
NC=0; pass=0; fail=0
# kase <имя> <jq-правка контроля | -> [довод --of: jq-правка прежнего] — отчёт случая
kase() {
    NC=$((NC + 1)); C="$W/c$NC"; mkdir -p "$C"; printf '%s' "$1" > "$C/name"
    if [ "$2" = - ]; then control > "$C/r.json"; else control | jq "$2" > "$C/r.json"; fi
    : > "$C/args"
    if [ -n "${3:-}" ]; then control | jq "$3" > "$C/prev.json"; printf -- '--of\n%s\n' "$C/prev.json" > "$C/args"; fi
}
# want <код> <код причины | -> — ожидание случая; «-» — ни одной строки REASON
want() { printf '%s' "$1" > "$C/code"; printf '%s' "$2" > "$C/want"; }
judge() {  # judge <скрипт> <каталог случая> → 0 сошлось
    local c="$2" out code; mapfile -t extra < "$c/args"
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
kase "planned 0 и наборов 0" '.planned = 0 | .suites = []'; want 1 STAND-REPORT-TRUNCATED
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

echo "== случаи"
for c in "$W"/c*; do
    if judge "$TOOL" "$c"; then pass=$((pass + 1)); echo "  [OK]   $(cat "$c/name")"
    else fail=$((fail + 1)); echo "  [FAIL] $(cat "$c/name") — ждали код $(cat "$c/code") и «$(cat "$c/want")»:" >&2; sed 's/^/         /' "$c/out.stand-report.sh" >&2; fi
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
planned-not-compared	s/if planned < 1 or planned != len(suites):/if planned < 1:/
green-partial-ok	s/if tot < 1 or ex < tot:/if tot < 1:/
red-ignored	s/elif out == 'red':/elif out == 'never':/
quote-not-required	s/if not q:/if False:/
local-ok	s/if not ctx.endswith('-client') and not proof:/if False:/
residue-ignored	s/if num(d.get('residue')) != 0:/if False:/
notrun-any-reason	s/if why not in RELAX:/if False and why not in RELAX:/
relax-never-expires	s/alive\[why\] = json.loads(p.stdout).get('state') == 'open'/alive[why] = True/
nothing-run-ok	s/if suites and green == 0:/if False:/
red-dropped-ok	s/if s.get('outcome') == 'red' and str(s.get('name')) not in mine:/if False:/
exit-zero	s/sys.exit(1 if reasons else 0)/sys.exit(0)/
MUT
echo "stand-report-inject: мутантов $((killed + survived + void)), убито $killed, выжило $survived, не легло $void"
[ "$fail" -eq 0 ] && [ "$pass" -gt 0 ] && [ "$survived" -eq 0 ] && [ "$void" -eq 0 ] && [ "$killed" -gt 0 ]
