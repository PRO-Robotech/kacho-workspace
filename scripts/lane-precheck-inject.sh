#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# lane-precheck-inject.sh — доказательство того, что `scripts/lane-precheck.sh`
# СПОСОБЕН отказать по каждому своему пункту и назвать причину кодом, а законный
# близнец каждого пункта проходит.
#
# Песочница настоящая: голый репозиторий `kacho-workspace.git` как origin (имя
# даёт словарь строки зелёного итога хука), дом копий `<ws>/tmp/`, копия полосы
# под ним и копия вне его. Трекер — обёртка `LANE_PRECHECK_GH` над файлами
# комментариев: без сети, тем же выражением jq, что зовёт предпроверка. Журнал
# отправки — форма из шапки предпроверки, итог хука — дословные строки хуков:
# формат печати КОПИРУЕТСЯ из исходника хука (ревизия названа у случая), а не пишется
# руками — придуманная форма дважды разошлась с настоящей (ws#1110).
# Каждая порча меняет ОДИН факт против контроля. Вывод дома копий без
# переопределения — предпроверкой, скопированной в клон под `tmp/` песочницы.
# Коды: 0 — все утверждения сошлись; 1 — хотя бы одно нет; 2 — jq нет, часть
# про трекер не построена.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/lane-precheck.sh"
W="$(mktemp -d)"
W="$(cd "$W" && pwd -P)"
# shellcheck disable=SC2154
trap '_rc=$?; rm -rf "$W" 2>/dev/null || rm -rf "$W" || echo "ПРЕДУПРЕЖДЕНИЕ: временный каталог $W не снят; код проверки $_rc сохранён" >&2; exit $_rc' EXIT
pass=0 fail=0
command -v jq > /dev/null || { echo "  [VOID] jq нет — обёртку трекера не построить" >&2; exit 2; }

assert() {
    if [ "$1" = "$2" ]; then echo "  [OK]   $3"; pass=$((pass + 1))
    else echo "  [FAIL] $3 — ожидалось «$1», получено «$2»" >&2; sed 's/^/         /' "$W/out" >&2; fail=$((fail + 1)); fi
}

# ── песочница ────────────────────────────────────────────────────────────
# Подпись посева — корневая учётная запись через HOME песочницы (правило подписи,
# check-16); нет её — у пробы нет предмета.
# shellcheck source=lib/sandbox-git-home.sh
. "$HERE/lib/sandbox-git-home.sh"
sandbox_git_home "$W/home" || exit 2
git() { sandbox_git "$@"; }
mkdir -p "$W/srv" "$W/ws/tmp" "$W/c"
git init -q --bare -b main "$W/srv/kacho-workspace.git"
L="$W/ws/tmp/lane"
git clone -q "$W/srv/kacho-workspace.git" "$L" 2> /dev/null
echo a > "$L/README.md"; git -C "$L" add . && git -C "$L" commit -qm base && git -C "$L" push -q origin main 2> /dev/null
git -C "$L" checkout -qb 1-lane
echo b > "$L/b.md"; git -C "$L" add . && git -C "$L" commit -qm one
MID="$(git -C "$L" rev-parse HEAD)"
echo c > "$L/c.md"; git -C "$L" add . && git -C "$L" commit -qm two
HEAD_SHA="$(git -C "$L" rev-parse HEAD)"
BASE_SHA="$(git -C "$L" rev-parse main)"
git -C "$L" push -q origin 1-lane 2> /dev/null

cat > "$W/gh" <<'GH'
#!/usr/bin/env bash
# api [--paginate] repos/<путь> [--jq <выражение>] — без --jq отдаёт ответ как есть
[ "$1" = api ] || exit 1
path="" expr=""
while [ $# -gt 0 ]; do
    case "$1" in --jq) expr="$2"; shift 2 ;; repos/*) path="$1"; shift ;; *) shift ;; esac
done
f="$GH_FIXTURES/$(printf '%s' "$path" | tr '/' '_').json"
[ -f "$f" ] || { echo "HTTP 404" >&2; exit 1; }
if [ -n "$expr" ]; then jq -r "$expr" "$f"; else cat "$f"; fi
GH
chmod +x "$W/gh"
export LANE_PRECHECK_GH="$W/gh" LANE_PRECHECK_WS="$W/ws" GH_FIXTURES="$W/c"
cfile() { echo "$W/c/repos_o_r_issues_$1_comments.json"; }
comments() { local n="$1"; shift; printf '%s\n' "$@" | jq -R . | jq -s '[.[] | {body: .}]' > "$(cfile "$n")"; }
# comment1 <n> <тело> — ОДИН многострочный комментарий (`comments` режет вход по строкам).
comment1() { printf '%s' "$2" | jq -Rs '[{body: .}]' > "$(cfile "$1")"; }
comments 7 "DoD-proof @${HEAD_SHA:0:12}
команда: bash scripts/x/run-all.sh; код 0"

GREEN='pre-push: локальные проверки воркспейса зелёные'
log() { { echo "lane-push head=$1"; echo "$2"; echo "lane-push rc=$3"; } > "$W/push.log"; }
log "$HEAD_SHA" "$GREEN" 0

run() { bash "$P" "$@" > "$W/out" 2>&1; echo $?; }
has() { grep -q -- "$1" "$W/out" && echo да || echo нет; }
ok_args=("$L" 1-lane main --issue o/r#7 --hook-log "$W/push.log")

echo "== контроль"
assert "0 да" "$(run "${ok_args[@]}") $(has 'причин 0, не судимо 0')" "законная полоса: код 0, причин 0, перепись напечатана"

echo "== голова и база"
git -C "$L" checkout -q -b 2-unpushed
assert "1 да" "$(run "$L" 2-unpushed main --issue o/r#7 --hook-log "$W/push.log") $(has 'REASON HEAD-NOT-ON-ORIGIN')" "ветки нет на origin → HEAD-NOT-ON-ORIGIN"
git -C "$L" checkout -q 1-lane
echo d > "$L/d.md"; git -C "$L" add . && git -C "$L" commit -qm three
assert "1 да" "$(run "${ok_args[@]}") $(has 'REASON HEAD-DIVERGED')" "коммит после отправки → HEAD-DIVERGED"
git -C "$L" checkout -q -B 1-lane "$HEAD_SHA"
assert "0" "$(run "${ok_args[@]}")" "близнец: копия снова равна origin → 0"
git -C "$L" checkout -q --orphan other && git -C "$L" commit -qm orphan --allow-empty
assert "1 да" "$(run "$L" 1-lane other --issue o/r#7 --hook-log "$W/push.log") $(has 'REASON BASE-NOT-ANCESTOR')" "база не предок головы → BASE-NOT-ANCESTOR"
git -C "$L" checkout -q -f 1-lane

echo "== дом копии"
M="$W/ws/main-copy"
git clone -q "$W/srv/kacho-workspace.git" "$M" 2> /dev/null && git -C "$M" checkout -q 1-lane 2> /dev/null
assert "1 да" "$(run "$M" 1-lane origin/main --issue o/r#7 --hook-log "$W/push.log") $(has 'REASON MAIN-COPY')" "копия вне <ws>/tmp/ → MAIN-COPY"
L2="$W/ws/tmp/lane2"
git clone -q "$W/srv/kacho-workspace.git" "$L2" 2> /dev/null && git -C "$L2" checkout -q 1-lane 2> /dev/null
assert "0" "$(run "$L2" 1-lane origin/main --issue o/r#7 --hook-log "$W/push.log")" "близнец: та же ветка из копии под tmp/ → 0"

echo "== чужой go.mod над копией (ws#1010)"
# Копия шаблона волны под <ws>/tmp/ переключена на дерево с go.mod; копия полосы
# легла в ЕЁ tmp/ — тесты полосы берут чужой go.mod за корень модуля.
NEST="$W/ws/tmp/wave7/ws-main"
mkdir -p "$NEST/tmp" && echo 'module example.com/foreign' > "$NEST/go.mod"
L3="$NEST/tmp/lane"
git clone -q "$W/srv/kacho-workspace.git" "$L3" 2> /dev/null && git -C "$L3" checkout -q 1-lane 2> /dev/null
assert "1 да" "$(run "$L3" 1-lane origin/main --issue o/r#7 --hook-log "$W/push.log") $(has "REASON GOMOD-ABOVE над копией $L3 чужой go.mod: $NEST/go.mod")" "копия полосы под каталогом с чужим go.mod → GOMOD-ABOVE с путём"
mv "$NEST/go.mod" "$NEST/go.mod.off"
assert "0" "$(run "$L3" 1-lane origin/main --issue o/r#7 --hook-log "$W/push.log")" "близнец: тот же путь без чужого go.mod → 0"
mv "$NEST/go.mod.off" "$NEST/go.mod"
echo 'module example.com/own' > "$L2/go.mod" && echo go.mod >> "$L2/.git/info/exclude"
assert "0 да" "$(run "$L2" 1-lane origin/main --issue o/r#7 --hook-log "$W/push.log") $(has 'предков осмотрено на go.mod')" "близнец: свой go.mod в корне копии — не предмет → 0, подъём в переписи"
rm -f "$L2/go.mod"

echo "== незакоммиченное в копии"
echo e >> "$L/b.md"
assert "1 да" "$(run "${ok_args[@]}") $(has 'REASON UNCOMMITTED')" "правленный отслеживаемый файл → UNCOMMITTED"
git -C "$L" checkout -q -- b.md
echo 'package x' > "$L/untracked.go"
assert "1 да" "$(run "${ok_args[@]}") $(has 'REASON UNCOMMITTED')" "новый файл вне git add → UNCOMMITTED"
rm -f "$L/untracked.go"
mkdir -p "$L/.git/info" && echo 'build.out' >> "$L/.git/info/exclude" && echo x > "$L/build.out"
assert "0" "$(run "${ok_args[@]}")" "близнец: игнорируемый файл — не незакоммиченное → 0"
rm -f "$L/build.out"

echo "== дом копий без переопределения: worktree и клон под tmp/ — один корень"
# Предпроверка лежит в КЛОНЕ под <ws2>/tmp/ (у клона свой .git): корень обязан
# выйти <ws2>, а не корень клона (check-verifier ws#933, п. 6).
WS2="$W/ws2"
git init -q -b main "$WS2" && mkdir -p "$WS2/tmp"
C="$WS2/tmp/tools-clone"
git init -q -b main "$C" && mkdir -p "$C/scripts/lib"
cp "$P" "$C/scripts/" && cp "$HERE/lib/ws-home.sh" "$HERE/lib/dod_proof.jq" "$C/scripts/lib/"
git clone -q "$W/srv/kacho-workspace.git" "$WS2/tmp/lane" 2> /dev/null && git -C "$WS2/tmp/lane" checkout -q 1-lane 2> /dev/null
git -C "$WS2/tmp/lane" remote set-url origin "$(git -C "$L" remote get-url origin)"
git -C "$WS2/tmp/lane" fetch -q origin 2> /dev/null; git -C "$WS2/tmp/lane" checkout -q -B 1-lane origin/1-lane
runc() { env -u LANE_PRECHECK_WS bash "$C/scripts/lane-precheck.sh" "$@" > "$W/out" 2>&1; echo $?; }
assert "0" "$(runc "$WS2/tmp/lane" 1-lane origin/main --issue o/r#7 --hook-log "$W/push.log")" "предпроверка из клона под tmp/, копия под <ws>/tmp/ → 0, не MAIN-COPY"
git clone -q "$W/srv/kacho-workspace.git" "$WS2/outside" 2> /dev/null
git -C "$WS2/outside" remote set-url origin "$(git -C "$L" remote get-url origin)"
git -C "$WS2/outside" fetch -q origin 2> /dev/null; git -C "$WS2/outside" checkout -q -B 1-lane origin/1-lane
assert "1 да" "$(runc "$WS2/outside" 1-lane origin/main --issue o/r#7 --hook-log "$W/push.log") $(has "REASON MAIN-COPY копия $WS2/outside вне $WS2/tmp/")" "близнец: копия вне <ws>/tmp/ из того же клона → MAIN-COPY с корнем <ws>"

echo "== доказательство DoD"
assert "1 да" "$(run "$L" 1-lane main --hook-log "$W/push.log") $(has 'REASON ISSUES-NONE')" "задач ноль → ISSUES-NONE"
comments 8 "готово, всё зелёное"
assert "1 да" "$(run "$L" 1-lane main --issue o/r#8 --hook-log "$W/push.log") $(has 'REASON DOD-PROOF-MISSING o/r#8: комментария')" "комментария DoD-proof нет → DOD-PROOF-MISSING"
comments 9 "DoD-proof @${BASE_SHA:0:12}"
assert "1 да" "$(run "$L" 1-lane main --issue o/r#9 --hook-log "$W/push.log") $(has 'ни один sha не голова')" "доказательство на базе (прежняя ревизия) → DOD-PROOF-MISSING"
comments 10 "текст" "DoD-proof @${MID:0:9}"
assert "0" "$(run "$L" 1-lane main --issue o/r#10 --hook-log "$W/push.log")" "близнец: доказательство на коммите из база..голова, вторым комментарием → 0"
comments 11 "см. DoD-proof @${HEAD_SHA:0:12} в соседней задаче"
assert "1" "$(run "$L" 1-lane main --issue o/r#11 --hook-log "$W/push.log")" "DoD-proof не в начале строки — не доказательство"
# Распознаватель — общий `lib/dod_proof.jq` (ws#1140): заголовок markdown перед
# маркером — начало строки; цитата и блок кода — нет.
comment1 12 "## DoD-proof @${HEAD_SHA:0:12} — ответ на возврат
команда: bash scripts/x/run-all.sh; код 0"
assert "0" "$(run "$L" 1-lane main --issue o/r#12 --hook-log "$W/push.log")" "близнец: DoD-proof под заголовком markdown → 0"
comment1 13 "> DoD-proof @${HEAD_SHA:0:12}"
assert "1 да" "$(run "$L" 1-lane main --issue o/r#13 --hook-log "$W/push.log") $(has 'REASON DOD-PROOF-MISSING o/r#13: комментария')" "DoD-proof в цитате — не доказательство"
comment1 14 "журнал:
\`\`\`
DoD-proof @${HEAD_SHA:0:12}
\`\`\`"
assert "1 да" "$(run "$L" 1-lane main --issue o/r#14 --hook-log "$W/push.log") $(has 'REASON DOD-PROOF-MISSING o/r#14: комментария')" "DoD-proof внутри блока кода — не доказательство"
assert "2 да" "$(run "$L" 1-lane main --issue o/r#99 --hook-log "$W/push.log") $(has 'VOID GH-UNREADABLE')" "трекер не ответил → код 2, не зелёное и не красное"
assert "2" "$(run "$L" 1-lane main --issue o-r-7 --hook-log "$W/push.log")" "задача не в форме владелец/репо#N → код 2"

echo "== хук отправки"
assert "1 да" "$(run "$L" 1-lane main --issue o/r#7) $(has 'REASON HOOK-LOG-MISSING')" "журнала нет → HOOK-LOG-MISSING"
log "$MID" "$GREEN" 0
assert "1 да" "$(run "${ok_args[@]}") $(has 'REASON HOOK-HEAD-MISMATCH')" "журнал прежней головы → HOOK-HEAD-MISMATCH"
log "$HEAD_SHA" "$GREEN" 1
assert "1 да" "$(run "${ok_args[@]}") $(has 'REASON HOOK-RC')" "отправка кодом 1 → HOOK-RC"
log "$HEAD_SHA" "pre-push: пропущен по KACHO_SKIP_PREPUSH=1 — наборы НЕ выполнялись (страж атрибуции исполнен выше)" 0
assert "1 да" "$(run "${ok_args[@]}") $(has 'REASON HOOK-BYPASSED')" "обход KACHO_SKIP_PREPUSH → HOOK-BYPASSED"
log "$HEAD_SHA" "Вершина уезжает НЕПРОВЕРЕННОЙ этими наборами: заведите клон и повторите отправку." 0
assert "1 да" "$(run "${ok_args[@]}") $(has 'REASON HOOK-NOT-GREEN')" "хук «без предмета» (код 0) — не зелёный → HOOK-NOT-GREEN"
log "$HEAD_SHA" "$GREEN" 0
assert "0" "$(run "${ok_args[@]}")" "близнец: тот же журнал с зелёным итогом → 0"

echo "== статика: весь список отказов хука разом (ws#1110)"
nstatic() { grep -c "^REASON STATIC-$1 " "$W/out"; }
WSRED=$'pre-push: судились вершины x; исполнено наборов 9, провалено 3\n\nОТКАЗ: отправка остановлена. Красные наборы:\n  rules-gate\n  tooling-gate\n  docs-gate\n\nОбойти можно, но осознанно'
log "$HEAD_SHA" "$WSRED" 1
assert "1 3 да" "$(run "${ok_args[@]}") $(nstatic RED) $(has 'REASON STATIC-RED kacho-workspace: docs-gate')" "три красных набора → три STATIC-RED, последний назван"
log "$HEAD_SHA" $'pre-push: ОТКАЗ — имя ветки не по форме «<N>-<суффикс>»\npre-push: ОТКАЗ — правило атрибуции нарушено' 1
assert "1 2 0" "$(run "${ok_args[@]}") $(nstatic REFUSAL) $(nstatic RED)" "красных единиц нет — каждая строка ОТКАЗ хука → STATIC-REFUSAL"
log "$HEAD_SHA" "error: failed to push some refs" 1
assert "1 1" "$(run "${ok_args[@]}") $(nstatic UNPARSED)" "отказ без формы итога → STATIC-UNPARSED, не «отказов 0»"
log "$HEAD_SHA" "$GREEN" 0
assert "0 0" "$(run "${ok_args[@]}") $(grep -c '^REASON STATIC-' "$W/out")" "близнец: зелёный хук — статических строк 0"
# Мутант: берётся лишь первая единица — случай трёх наборов обязан покраснеть.
# shellcheck disable=SC2016 # образец sed — литерал, не подстановка
sed 's/ | awk .!seen\[\$0\]++.)$/ | head -1)/' "$P" > "$W/mut-first.sh"
if cmp -s "$W/mut-first.sh" "$P"; then echo "  [FAIL] мутант «лишь первый отказ» не лёг в текст" >&2; fail=$((fail + 1))
else log "$HEAD_SHA" "$WSRED" 1; bash "$W/mut-first.sh" "${ok_args[@]}" > "$W/out" 2>&1
    assert "1" "$(nstatic RED)" "мутант «лишь первый отказ»: STATIC-RED один — случай трёх наборов его отличает"; [ "$(nstatic RED)" != 3 ] || fail=$((fail + 1)); fi
log "$HEAD_SHA" "$GREEN" 0

echo "== словарь итогов хука по репозиторию"
for kind in corelib kaname kacho other; do git init -q --bare -b main "$W/srv/$kind.git"; done
git -C "$L" remote set-url origin "$W/srv/corelib.git"; git -C "$L" push -q origin main 1-lane 2> /dev/null
log "$HEAD_SHA" "pre-push (corelib): исполнено 4 из 5, красных 0 — отправляю" 0
assert "1 да" "$(run "${ok_args[@]}") $(has 'REASON HOOK-NOT-GREEN')" "corelib: исполнено 4 из 5 — не зелёный"
log "$HEAD_SHA" "pre-push (corelib): исполнено 5 из 5, красных 0 — отправляю" 0
assert "0" "$(run "${ok_args[@]}")" "близнец corelib: 5 из 5 → 0"
log "$HEAD_SHA" $'-- gofmt --\nКРАСНОЕ: gofmt (код 1)\n-- vet --\nКРАСНОЕ: vet (код 2)\npre-push (corelib): исполнено 5 из 5, красных 2' 1
assert "1 2" "$(run "${ok_args[@]}") $(nstatic RED)" "corelib: две строки КРАСНОЕ → два STATIC-RED"
git -C "$L" remote set-url origin "$W/srv/kaname.git"; git -C "$L" push -q origin main 1-lane 2> /dev/null
log "$HEAD_SHA" "pre-push: зелёное — исполнено 6 из 6 групп, отказов 0." 0
assert "0" "$(run "${ok_args[@]}")" "kaname: строка зелёного итога → 0"
log "$HEAD_SHA" "pre-push: НЕ ВЫПОЛНИЛОСЬ — групп без условия 1 из 6: x." 0
assert "1" "$(run "${ok_args[@]}")" "kaname: недобор групп — не зелёный"
# Строки kaname — дословные формы печати scripts/hooks/pre-push kaname (@bbbe33524):
# `echo "── $gname: $gdesc"`, `echo "   → КРАСНОЕ (код $rc)"`, перепись `групп ИСПОЛНЕНО`.
KNRED=$'── сборка: go build ./...\n   → КРАСНОЕ (код 1)\n── vet: make vet\n   → КРАСНОЕ (код 2)\n── gofmt: gofmt по индексу git\n\n=== pre-push: перепись прогона ===\nгрупп ИСПОЛНЕНО     : 6  (зелёных 4 · красных 2)\nкрасные             : сборка vet\npre-push: ОТКАЗ — красных групп 2. Отправка остановлена.'
log "$HEAD_SHA" "$KNRED" 1
assert "1 2 да 0" "$(run "${ok_args[@]}") $(nstatic RED) $(has 'REASON STATIC-RED kaname: vet') $(nstatic REFUSAL)" "kaname: «красные : сборка vet» при красных 2 → два STATIC-RED, ОТКАЗ не дублирует"
log "$HEAD_SHA" "${KNRED/красных 2)/красных 3)}" 1
assert "1 0 1" "$(run "${ok_args[@]}") $(nstatic RED) $(nstatic UNPARSED)" "kaname: итог говорит красных 3, имён в строке 2 → STATIC-UNPARSED, не два и не три"
git -C "$L" remote set-url origin "$W/srv/kacho.git"; git -C "$L" push -q origin main 1-lane 2> /dev/null
log "$HEAD_SHA" "== pre-push: локальные проверки зелёные (не выполненных нет) — отправляю" 0
assert "0" "$(run "${ok_args[@]}")" "kacho: строка зелёного итога → 0"
# Строка «   красное: ${fails[*]}» kacho склеивает имена ПРОБЕЛОМ, а имя шага пробелы
# содержит. Словарь — заголовки журнала и литералы scripts/ci-local.sh ГОЛОВЫ: полоса
# несёт его коммитом. Настоящий производитель (KACHO_CILOCAL либо project/kacho
# воркспейса, origin/main) — целиком; нет его — строки, скопированные из него
# дословно (@a95248464), и их дословность сверяется, когда он есть.
KFIX=$'    local name="go.mod: объявление сходится с графом импортов"\n                    fails+=("gosec (level=error)")\n        fails+=("generate-diff")'
KREAL="${KACHO_CILOCAL:-}"
kc="$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2> /dev/null)/../project/kacho"
if [ -z "$KREAL" ] && git -C "$kc" show origin/main:scripts/ci-local.sh > "$W/ci-local.real" 2> /dev/null; then KREAL="$W/ci-local.real"; fi
mkdir -p "$L/scripts"
if [ -n "$KREAL" ] && [ -s "$KREAL" ]; then
    cp "$KREAL" "$L/scripts/ci-local.sh"
    nfix=0; while IFS= read -r fl; do grep -Fxq -- "$fl" "$KREAL" && nfix=$((nfix + 1)); done <<< "$KFIX"
    assert "3" "$nfix" "строки фикстуры kacho дословны в настоящем ci-local.sh"
else
    printf '%s\n' "$KFIX" > "$L/scripts/ci-local.sh"
    echo "  [NOTE] настоящий ci-local.sh kacho не найден — случаи ниже на дословной фикстуре, её дословность НЕ сверена"
fi
git -C "$L" add scripts/ci-local.sh && git -C "$L" commit -qm ci-local && git -C "$L" push -q origin 1-lane 2> /dev/null
HEAD_SHA="$(git -C "$L" rev-parse HEAD)"
KHOOK=$'\npre-push ОТКАЗ: локальные проверки красные — отправка остановлена.'
klog() { log "$HEAD_SHA" "$1"$'\n\n== итог: проверок исполнено 31, отказов '"$2"$', НЕ выполнено 0\n   красное: '"$3$KHOOK" 1; }
klog $'\n== go.mod: объявление сходится с графом импортов\n   ОТКАЗ (код 1)\n   | целиком: /tmp/x/log-07-go-mod-tidy.txt' 1 "go.mod: объявление сходится с графом импортов"
assert "1 1 да 0" "$(run "${ok_args[@]}") $(nstatic RED) $(has 'REASON STATIC-RED kacho: go.mod: объявление сходится с графом импортов$') $(nstatic REFUSAL)" "kacho: одно имя шага с пробелами → ровно один STATIC-RED, имя целиком"
klog $'\n== gosec (v2.22.4, как в конвейере)\n   осмотрено результатов 3; из них level=error: 1\n\n== generate-diff (стабы в синхроне с .proto)' 2 "gosec (level=error) generate-diff"
assert "1 2 да да" "$(run "${ok_args[@]}") $(nstatic RED) $(has 'REASON STATIC-RED kacho: gosec (level=error)$') $(has 'REASON STATIC-RED kacho: generate-diff$')" "kacho: «gosec (level=error) generate-diff» → два STATIC-RED по литералам ci-local.sh головы"
klog $'\n== go build\n   ОТКАЗ (код 1)\n\n== go vet\n   ОТКАЗ (код 1)' 2 "go build go vet"
assert "1 2 да" "$(run "${ok_args[@]}") $(nstatic RED) $(has 'REASON STATIC-RED kacho: go vet$')" "kacho: шаги run из заголовков журнала «== go build», «== go vet» → два STATIC-RED"
klog $'\n== go build\n   ОТКАЗ (код 1)' 3 "go build go vet"
assert "1 0 1" "$(run "${ok_args[@]}") $(nstatic RED) $(nstatic UNPARSED)" "kacho: отказов в итоге 3, имён 2 → STATIC-UNPARSED, а не четыре слова"
klog $'\n== go build\n   ОТКАЗ (код 1)' 1 "go build lint"
assert "1 0 1" "$(run "${ok_args[@]}") $(nstatic RED) $(nstatic UNPARSED)" "kacho: имени «lint» нет ни в журнале, ни в ci-local.sh → STATIC-UNPARSED"
klog $'\n== x y\n   ОТКАЗ (код 1)\n\n== z\n\n== x\n\n== y z\n   ОТКАЗ (код 1)' 2 "x y z"
assert "1 0 1" "$(run "${ok_args[@]}") $(nstatic RED) $(nstatic UNPARSED)" "kacho: разрезов два («x y|z» и «x|y z») → STATIC-UNPARSED, не выбор наугад"
# Мутант: неоднозначный разрез принят — случай двух разрезов обязан его отличить.
sed 's/ways\[0\]\[k\] != 1:/ways[0][k] < 1:/' "$P" > "$W/mut-amb.sh"
if cmp -s "$W/mut-amb.sh" "$P"; then echo "  [FAIL] мутант «неоднозначный разрез принят» не лёг в текст" >&2; fail=$((fail + 1))
else bash "$W/mut-amb.sh" "${ok_args[@]}" > "$W/out" 2>&1
    if [ "$(nstatic UNPARSED)" = 0 ]; then echo "  [OK]   мутант «неоднозначный разрез принят» убит: STATIC-UNPARSED пропал"; pass=$((pass + 1))
    else echo "  [FAIL] мутант «неоднозначный разрез принят» выжил" >&2; fail=$((fail + 1)); fi; fi
if [ -n "$KREAL" ] && [ -s "$KREAL" ]; then
    # Весь словарь литералов настоящего производителя разом: каждое имя — одной единицей.
    # shellcheck disable=SC2016 # образец grep — литерал, не подстановка
    mapfile -t kall < <(grep -oE 'fails\+=\("[^"$`\\]+"\)|local name="[^"$`\\]+"' "$KREAL" | sed -E 's/^fails\+=\("//; s/"\)$//; s/^local name="//; s/"$//' | awk '!seen[$0]++')
    klog "" "${#kall[@]}" "${kall[*]}"
    assert "1 ${#kall[@]} 0" "$(run "${ok_args[@]}") $(nstatic RED) $(nstatic UNPARSED)" "kacho: все ${#kall[@]} литералов отказа настоящего ci-local.sh одной строкой → столько же STATIC-RED"
fi
log "$HEAD_SHA" "== pre-push: локальные проверки зелёные (не выполненных нет) — отправляю" 0
git -C "$L" remote set-url origin "$W/srv/other.git"; git -C "$L" push -q origin main 1-lane 2> /dev/null
assert "2 да" "$(run "${ok_args[@]}") $(has 'VOID HOOK-KIND-UNKNOWN')" "репозиторий вне словаря → код 2"

echo "== предусловия задания до раздачи (ws#1071)"
# Трекер — та же обёртка; каждая порча меняет ОДИН факт против контроля.
printf '%s' '{"state":"closed","merged":true}' > "$W/c/repos_o_r_pulls_5.json"
printf '%s' '{"state":"open","merged":false}' > "$W/c/repos_o_r_pulls_6.json"
printf '%s' '{"name":"1-lane"}' > "$W/c/repos_o_r_branches_1-lane.json"
printf 'verdict:\n  value: %s\n  blocking: НЕТ\n' "'✅ принято'" > "$W/rev-ok.yaml"
printf 'verdict:\n  value: %s\n  blocking: ДА\n' "'⛔ возврат → x'" > "$W/rev-ret.yaml"
prem() { printf '%s\n' "$@" > "$W/premise.txt"; }
runp() { bash "$P" --premise "$W/premise.txt" > "$W/out" 2>&1; echo $?; }
prem '# предусловия' 'pr o/r#5 MERGED' 'pr o/r#6 OPEN' 'branch o/r 1-lane' 'proof o/r#7' "verdict $W/rev-ok.yaml accept"
assert "0 да" "$(runp) $(has 'предусловий 5; ложных 0, не судимо 0')" "контроль: пять верных предусловий → 0, перепись"
prem 'pr o/r#6 MERGED'
assert "1 да" "$(runp) $(has 'REASON PREMISE-FALSE pr o/r#6 MERGED: состояние OPEN')" "PR открыт, задание считает влитым → PREMISE-FALSE"
prem 'pr o/r#9 OPEN'
assert "1 да" "$(runp) $(has 'PREMISE-FALSE pr o/r#9 OPEN: PR нет')" "PR нет (404) → PREMISE-FALSE"
prem 'branch o/r 2-gone'
assert "1 да" "$(runp) $(has 'ветки на origin нет')" "ветки на origin нет → PREMISE-FALSE"
# Голова ветки на origin (ws#1191): полоса стенда и образов — на sha, которая уже на origin.
HA=1111111111111111111111111111111111111111 HB=2222222222222222222222222222222222222222
printf '%s' "{\"name\":\"3-stand\",\"commit\":{\"sha\":\"$HA\"}}" > "$W/c/repos_o_r_branches_3-stand.json"
printf '%s' '{"name":' > "$W/c/repos_o_r_branches_4-flaky.json"
prem "head o/r 3-stand $HA"
assert "0 да" "$(runp) $(has 'предусловий 1; ложных 0, не судимо 0')" "близнец: голова 3-stand на origin равна sha → 0"
prem "head o/r 3-stand $HB"
assert "1 да да" "$(runp) $(has "голова 3-stand на origin $HA, ожидалась $HB") $(has 'REASON PREMISE-FALSE head')" "голова на origin иная → PREMISE-FALSE, обе sha названы"
# Близнец, совпадающий с головой во всех знаках, кроме последнего: сравнение — целиком,
# не по префиксу и не по первому знаку (приёмка r1).
HN=111111111111111111111111111111111111111f
prem "head o/r 3-stand $HN"
assert "1 да" "$(runp) $(has "голова 3-stand на origin $HA, ожидалась $HN")" "голова отличается лишь последним знаком → PREMISE-FALSE"
prem "head o/r 3-st#and $HA" "branch o/r 1-la#ne"
assert "2 да да" "$(runp) $(has 'VOID PREMISE-FORM head o/r 3-st#and') $(has 'VOID PREMISE-FORM branch o/r 1-la#ne')" "«#» в имени ветки обрезал бы путь GET → строка вне формы, код 2"
prem "head o/r 2-gone $HA"
assert "1 да" "$(runp) $(has "ветки 2-gone на origin нет — ожидалась голова $HA")" "ветки на origin нет → PREMISE-FALSE с веткой и sha"
prem "head o/r 4-flaky $HA"
assert "2 да" "$(runp) $(has 'VOID GH-UNREADABLE head o/r 4-flaky')" "origin не ответил → не судимо (VOID), не зелёное"
prem "head o/r 3-stand ${HA:0:12}"
assert "2 да" "$(runp) $(has 'VOID PREMISE-FORM head')" "sha не 40 знаков → строка вне формы, код 2"
prem 'proof o/r#8'
comments 8 "без доказательства"
assert "1 да" "$(runp) $(has 'комментария «DoD-proof @<sha>» нет')" "DoD-proof нет → PREMISE-FALSE"
prem 'proof o/r#12'
assert "0" "$(runp)" "близнец: DoD-proof под заголовком markdown — предусловие верно"
prem 'proof o/r#13'
assert "1 да" "$(runp) $(has 'PREMISE-FALSE proof o/r#13: комментария')" "DoD-proof в цитате → PREMISE-FALSE"
prem "verdict $W/rev-ret.yaml accept"
assert "1 да" "$(runp) $(has 'вердикт return')" "роль вернула, задание считает принятым → PREMISE-FALSE"
prem "verdict $W/rev-ret.yaml return"
assert "0" "$(runp)" "близнец: тот же возврат, задание о возврате → 0"
prem 'proof o/r#3'
assert "2 да" "$(runp) $(has 'VOID GH-UNREADABLE')" "комментарии задачи не прочитаны → код 2, не «ложно»"
prem 'pr o/r#5 merged'
assert "2 да" "$(runp) $(has 'VOID PREMISE-FORM')" "строка вне словаря → код 2"
# Номер задачи (урок 2026-10-16): в шаблон подставился текст отказа — полоса не раздаётся.
printf '%s' '{"number":7,"state":"open"}' > "$W/c/repos_o_r_issues_7.json"
printf '%s' '{"number":5,"state":"closed","pull_request":{"url":"x"}}' > "$W/c/repos_o_r_issues_5.json"
prem 'task o/r#7'
assert "0 да" "$(runp) $(has 'предусловий 1; ложных 0, не судимо 0')" "близнец: task o/r#7 — номер числом, задача есть → 0"
prem 'task o/r#ОТКАЗ: gh issue view не ответил'
assert "1 да" "$(runp) $(has 'PREMISE-FALSE task o/r#ОТКАЗ: gh issue view не ответил: номер задачи «ОТКАЗ: gh issue view не ответил» не ')" "в номер подставлен текст отказа → PREMISE-FALSE, полоса не раздаётся"
prem 'task o/r#'
assert "1 да" "$(runp) $(has 'номер задачи «» не')" "пустой номер → PREMISE-FALSE"
prem 'task o/r#7 '
assert "1 да" "$(runp) $(has 'номер задачи «7 » не')" "номер с хвостом → PREMISE-FALSE"
prem 'task o/r#9'
assert "1 да" "$(runp) $(has 'PREMISE-FALSE task o/r#9: задачи нет')" "задачи нет (404) → PREMISE-FALSE"
prem 'task o/r#5'
assert "1 да" "$(runp) $(has 'это PR, а не задача')" "номер PR вместо задачи → PREMISE-FALSE"
prem 'task o/r'
assert "2 да" "$(runp) $(has 'VOID PREMISE-FORM task o/r')" "без #<N> — строка вне формы → код 2"
prem '# только комментарий'
assert "2" "$(runp)" "ноль предусловий — не «все верны» → код 2"

# ── ws#1227: задача открыта и о предмете; голова — текущая (ls-remote); предмет жив ──
printf '%s' '{"number":20,"state":"open","title":"lane-precheck: состояние задачи, предмет жив"}' > "$W/c/repos_o_r_issues_20.json"
printf '%s' '{"number":21,"state":"closed","title":"старая задача о квотах"}' > "$W/c/repos_o_r_issues_21.json"
printf '%s' '{"number":22,' > "$W/c/repos_o_r_issues_22.json"
prem 'task o/r#20 open title~состояние задачи'
assert "0 да" "$(runp) $(has 'предусловий 1; ложных 0, не судимо 0')" "близнец: задача открыта, заголовок несёт подстроку → 0"
prem 'task o/r#20 title~СОСТОЯНИЕ'
assert "0" "$(runp)" "подстрока заголовка — без учёта регистра, состояние по умолчанию open → 0"
prem 'task o/r#20 title~квоты'
assert "1 да" "$(runp) $(has 'задача не о предмете — заголовок «lane-precheck: состояние задачи, предмет жив» без «квоты»')" "заголовок без подстроки — PREMISE-FALSE «не о предмете» (урок ae22eb25)"
prem 'task o/r#21'
assert "1 да" "$(runp) $(has 'PREMISE-FALSE task o/r#21: задача closed, задание ждёт open')" "закрытая задача — PREMISE-FALSE (урок fa7858a6: #832 закрыта)"
prem 'task o/r#21 closed title~квот'
assert "0" "$(runp)" "близнец: задание само о закрытой задаче → 0"
prem 'task o/r#22'
assert "2 да" "$(runp) $(has 'VOID GH-UNREADABLE task o/r#22')" "ответ трекера не разобран → VOID, не зелёное"
mkdir -p "$W/gb/o"; ln -s "$W/srv/kacho-workspace.git" "$W/gb/o/r.git"
runl() { LANE_PRECHECK_GIT_BASE="$W/gb" bash "$P" --premise "$W/premise.txt" > "$W/out" 2>&1; echo $?; }
prem 'head o/r 1-lane ls-remote'
assert "0 да" "$(runl) $(has "HEAD o/r 1-lane $(git -C "$W/srv/kacho-workspace.git" rev-parse 1-lane)")" "head … ls-remote — текущая голова напечатана для задания, код 0 (урок 9d4363aa)"
prem 'head o/r 2-gone ls-remote'
assert "1 да" "$(runl) $(has 'PREMISE-FALSE head o/r 2-gone ls-remote: ветки 2-gone на origin нет')" "ls-remote: ветки нет → PREMISE-FALSE"
prem 'head o/x 1-lane ls-remote'
assert "2 да" "$(runl) $(has 'VOID GIT-UNREADABLE head o/x 1-lane ls-remote')" "ls-remote: origin не ответил → VOID"
# ws#1242: шаг, зависящий от отправки, — только при голове на origin = ожидаемой (ls-remote).
OH="$(git -C "$W/srv/kacho-workspace.git" rev-parse 1-lane)"
prem "pushed o/r 1-lane $OH"
assert "0 да" "$(runl) $(has 'предусловий 1; ложных 0, не судимо 0')" "близнец: опубликованная голова = ожидаемая → 0, зависимый шаг выдаётся"
prem "pushed o/r 1-lane $BASE_SHA"
assert "1 да" "$(runl) $(has "PREMISE-FALSE pushed o/r 1-lane $BASE_SHA: голова 1-lane на origin $OH, отправка $BASE_SHA не доехала")" "непредъявленная голова (на origin другая) → PREMISE-FALSE, код 1 (ws#1242: шаг выдан до .rc отправки)"
prem "pushed o/r 2-gone $HEAD_SHA"
assert "1 да" "$(runl) $(has 'PREMISE-FALSE pushed o/r 2-gone .*: ветки 2-gone на origin нет')" "ветки на origin нет → PREMISE-FALSE"
prem "pushed o/x 1-lane $HEAD_SHA"
assert "2 да" "$(runl) $(has 'VOID GIT-UNREADABLE pushed o/x')" "origin не ответил → VOID, не зелёное"
prem "pushed o/r 1-lane ${HEAD_SHA:0:12}"
assert "2 да" "$(runl) $(has 'VOID PREMISE-FORM pushed')" "sha не целиком → VOID PREMISE-FORM: неполная голова не сверяется"
prem "alive $L main a"
assert "0" "$(runp)" "близнец: фраза есть в дереве базы → предмет жив, 0"
prem "alive $L main фраза-которой-нет"
assert "1 да" "$(runp) $(has 'предмет снят до раздачи')" "фразы нет в базе → PREMISE-FALSE «снят до раздачи» (урок f487bb7c)"
prem "alive $W/nope main x"
assert "2 да" "$(runp) $(has 'VOID PREMISE-FORM alive')" "клона нет → VOID"

# ── ws#1242 п.1: вишни пачки собираются пробами — go vet -tags=integration на голове ──
# Песочница — урок b3d4f0781: вишня с integration-пробой, чья зависимость (функция B) осталась
# в ветке-источнике. `go build ./...` такой ветки зелёный (проба вне сборки) — дефект видит лишь vet
# с тегом. Близнец — та же проба стеком от предшественницы (B в ветке).
if command -v go > /dev/null 2>&1; then
    git init -q --bare -b main "$W/srv/gv.git"; GV="$W/gv"
    git clone -q "$W/srv/gv.git" "$GV" 2> /dev/null
    mkdir -p "$GV/p"; printf 'module example.com/gv\n\ngo 1.21\n' > "$GV/go.mod"
    printf 'package p\n\nfunc A() int { return 1 }\n' > "$GV/p/p.go"
    echo r > "$GV/README.md"
    git -C "$GV" add . && git -C "$GV" commit -qm base && git -C "$GV" push -q origin main 2> /dev/null
    git -C "$GV" checkout -qb src
    printf 'package p\n\nfunc B() int { return 2 }\n' > "$GV/p/b.go"; git -C "$GV" add . && git -C "$GV" commit -qm dep
    printf '//go:build integration\n\npackage p\n\nimport "testing"\n\nfunc TestB(t *testing.T) { _ = A() + B() }\n' > "$GV/p/p_integration_test.go"
    git -C "$GV" add . && git -C "$GV" commit -qm probe; PROBE_SHA="$(git -C "$GV" rev-parse HEAD)"
    git -C "$GV" checkout -qb 771 main && git -C "$GV" cherry-pick "$PROBE_SHA" > /dev/null
    git -C "$GV" checkout -qb 772 main && git -C "$GV" merge -q --ff-only src
    git -C "$GV" checkout -qb 773 main && echo s > "$GV/README.md" && git -C "$GV" commit -qam docs
    # check-verifier ws#1242: tools.go (//go:build tools) и testdata — не предмет vet.
    git -C "$GV" checkout -qb 774 main; mkdir -p "$GV/tools" "$GV/p/testdata"
    printf '//go:build tools\n\npackage tools\n\nimport _ "example.com/nope"\n' > "$GV/tools/tools.go"
    printf 'package broken\n\nfunc X( {\n' > "$GV/p/testdata/bad.go"
    git -C "$GV" add . && git -C "$GV" commit -qm tools
    git -C "$GV" checkout -qb 775 771 && git -C "$GV" merge -q --no-edit 774 > /dev/null
    git -C "$GV" checkout -q 771
    assert "0" "$( (cd "$GV" && go build ./... > /dev/null 2>&1); echo $?)" "предпосылка: go build ./... на вишне без зависимости зелёный (урок b3d4f0781)"
    prem "cherry-vet $GV 771"
    assert "1 да" "$(runp) $(has 'PREMISE-FALSE cherry-vet .* 771: go vet -tags=integration на голове .*(пакетов 1).*undefined: B')" "вишня, чья зависимость не перенесена, — PREMISE-FALSE, код 1, причина vet названа"
    prem "cherry-vet $GV 772"
    assert "0 да" "$(runp) $(has 'CHERRY-VET 772 @.*: пакетов 1, vet -tags=integration 0')" "близнец: та же проба стеком (зависимость в ветке) — 0, перепись пакетов названа"
    prem "cherry-vet $GV 774"
    assert "2 да" "$(runp) $(has 'VOID CHERRY-EMPTY .*отсечено тегами 1, файлов testdata 1')" "близнец: только tools.go (//go:build tools) и testdata — не ложь, VOID с переписью отсечённого"
    prem "cherry-vet $GV 775"
    assert "1 да" "$(runp) $(has 'PREMISE-FALSE cherry-vet .* 775: .*(пакетов 1).*undefined: B')" "tools.go и testdata рядом с вишней без зависимости — ложь вишни судится, отсечённое её не прячет"
    prem "cherry-vet $GV 773"
    assert "2 да" "$(runp) $(has 'VOID CHERRY-EMPTY')" "Go-пакетов в диффе нет — VOID, не зелёное"
    assert "0" "$(git -C "$GV" worktree list | grep -vc "^$GV ")" "копии голов сняты тем же шагом (worktree list — только клон)"
    prem "cherry-vet $W/nope 771"
    assert "2 да" "$(runp) $(has 'VOID PREMISE-FORM cherry-vet')" "клона нет — VOID"
    if ! PATH=/usr/bin:/bin command -v go > /dev/null 2>&1; then
        prem "cherry-vet $GV 771"
        assert "2 да" "$(PATH=/usr/bin:/bin bash "$P" --premise "$W/premise.txt" > "$W/out" 2>&1; echo $?) $(has 'VOID GO-ABSENT')" "go нет — VOID GO-ABSENT, не зелёное"
    fi
    CHERRY_GV="$GV"
else
    echo "  [VOID] go нет — cherry-vet не судим" >&2; CHERRY_VOID=1
fi

# ── ws#1226: имя ветки и первая строка — правилом репозитория; форма отправки ──
# Клоны с origin продукта (сети нет: адрес лишь читается). Предикат kaname — форма
# branch_rule_is_number из scripts/hooks/branch-rule.sh kaname (@bbbe33524), дословно.
mkcl() { git init -q -b "${3:-main}" "$1"; git -C "$1" remote add origin "https://github.com/PRO-Robotech/$2.git"; }
mkcl "$W/kn" kaname 3180; mkdir -p "$W/kn/scripts/hooks"
printf '%s\n' 'branch_rule_is_number() { [[ "$1" =~ ^[0-9]+$ ]]; }' > "$W/kn/scripts/hooks/branch-rule.sh"
mkcl "$W/wsc" kacho-workspace 1228-x; mkcl "$W/oth" other
printf '%s' '[{"number":1201,"merged_at":"2026-10-18T00:00:00Z"}]' > "$W/c/repos_PRO-Robotech_kacho-workspace_pulls?head=PRO-Robotech:1200-old&state=closed&per_page=100.json"
printf '%s' '[{"number":5,"merged_at":null}]' > "$W/c/repos_PRO-Robotech_kacho-workspace_pulls?head=PRO-Robotech:1199-closed&state=closed&per_page=100.json"
prem "branchname $W/kn 893-acc"
assert "1 да" "$(runp) $(has 'имя не номер задачи kaname')" "kaname 893-acc → PREMISE-FALSE по предикату клона (урок a261e3e4)"
prem "branchname $W/kn w10-kn-x"
assert "1" "$(runp)" "kaname w10-kn-x → PREMISE-FALSE (урок 6ea1bffe)"
prem "branchname $W/kn 893"
assert "0 да" "$(runp) $(has 'предусловий 1; ложных 0, не судимо 0')" "близнец: kaname 893 → 0"
prem "branchname $W/wsc 1226-lane-precheck" "branchname $W/wsc 1199-closed"
assert "0" "$(runp)" "близнец: воркспейс <N>-<суть>; закрытый НЕвлитый PR ветки — не помеха → 0"
prem "branchname $W/wsc w10-x"
assert "1 да" "$(runp) $(has 'не по форме «<N>-<суффикс>»: не начинается с номера задачи')" "воркспейс w10-x → PREMISE-FALSE с причиной хука (общий предикат branch-name-rule.sh)"
prem "branchname $W/wsc 1200-old"
assert "1 да" "$(runp) $(has 'ветка 1200-old уже влита (#1201)')" "ветка с этим именем уже влита → PREMISE-FALSE (урок ed1f2016)"
prem "branchname $W/oth 1-x"
assert "2 да" "$(runp) $(has 'VOID RULE-UNKNOWN')" "правила для репозитория нет → VOID, не зелёное"
mv "$W/kn/scripts/hooks/branch-rule.sh" "$W/kn/br.away"; prem "branchname $W/kn 893"
assert "2 да" "$(runp) $(has 'предиката')" "предиката в клоне нет → VOID"
mv "$W/kn/br.away" "$W/kn/scripts/hooks/branch-rule.sh"
prem "commit-subject $W/kn 3180 #3274 правка пробы"
assert "1 да" "$(runp) $(has 'несёт номер ВЕТКИ: «#3180 …»')" "kaname: первая строка #3274 на ветке 3180 → PREMISE-FALSE (уроки 3da5d886, 5ed6b2bb)"
prem "commit-subject $W/kn 3180 #3180 правка пробы"
assert "0 да" "$(runp) $(has 'предусловий 1; ложных 0, не судимо 0')" "близнец: #3180 на ветке 3180 → 0, счёт предусловий не сбит номером строки"
prem "commit-subject $W/wsc 1228-x #1225 механизм ожидания"
assert "0" "$(runp)" "воркспейс: номер задачи на ветке другой задачи пачки — законно → 0"
prem "commit-subject $W/wsc 1228-x механизм без номера"
assert "1 да" "$(runp) $(has 'первая строка не «#<N> …»')" "первая строка без «#<N> » → PREMISE-FALSE"
git -C "$W/kn" commit -q --allow-empty -m x 2>/dev/null || sandbox_git -C "$W/kn" commit -q --allow-empty -m x
cp -r "$W/kn" "$W/knd"; git -C "$W/knd" checkout -q --detach
prem "push-form $W/kn bash -c 'git push origin HEAD:refs/heads/3180'"
assert "1 да" "$(runp) $(has 'обёртка «bash -c»')" "bash -c вокруг git push → PREMISE-FALSE «слот отдаст 77» (урок b9c180f6)"
prem "push-form $W/kn cd /x && git push origin HEAD:refs/heads/3180; echo \$?"
assert "1 да да" "$(runp) $(has '«cd … &&»') $(has '«; echo $?»')" "cd … && и ; echo \$? → обе причины одной строкой"
prem "push-form $W/knd /ws/scripts/heavy-slot.sh ci-local -- git push origin HEAD:refs/heads/3180"
assert "1 да" "$(runp) $(has 'голова копии отсоединена')" "отсоединённая голова без KACHO_TASK → PREMISE-FALSE (урок 36369ea7)"
prem "push-form $W/knd env KACHO_TASK=3180 /ws/scripts/heavy-slot.sh ci-local -- git push origin HEAD:refs/heads/3180"
assert "0" "$(runp)" "близнец: та же отправка с KACHO_TASK=<N> → 0"
prem "push-form $W/kn env KACHO_HOME_KACHO=/k /ws/scripts/heavy-slot.sh ci-local -- git push origin HEAD:refs/heads/3180"
assert "1 да" "$(runp) $(has '--local')" "kaname с KACHO_HOME_KACHO без --local → PREMISE-FALSE"
prem "push-form $W/kn env KACHO_HOME_KACHO=/k /ws/scripts/heavy-slot.sh --local \"проба приёмок\" ci-local -- git push origin HEAD:refs/heads/3180"
assert "0" "$(runp)" "близнец: та же с --local → 0"

echo "== текст задания (ws#1225)"
tt() { printf '%s\n' "$@" > "$W/task.txt"; bash "$P" --task-text "$W/task.txt" > "$W/out" 2>&1; echo $?; }
assert "1 да" "$(tt 'Ожидание хука: 270 с на паузу между чтениями журнала.') $(has 'REASON TASK-WAIT строка 1')" "«270 с на паузу» → TASK-WAIT со строкой (урок c375d889)"
assert "1 да" "$(tt 'Проверь .rc, затем sleep 50 и снова.') $(has 'TASK-WAIT')" "sleep 50 в задании → TASK-WAIT (урок 04a0cb11)"
assert "1 да" "$(tt 'Отправь и не жди дольше трёх пауз.') $(has 'TASK-WAIT')" "«не жди дольше трёх пауз» → TASK-WAIT"
assert "1 да" "$(tt 'Каждый Bash ≤ 60 с.' 'Хук: вызов до 270 с.') $(has 'TASK-LIMITS пределы одного вызова разные: 60 270 с')" "два предела вызова (60 и 270 с) → TASK-LIMITS"
assert "1 да" "$(tt 'Отправка полным хуком: heavy-slot.sh ci-local -- git push origin HEAD:refs/heads/1-x.') $(has 'TASK-RETURN строка 1')" "долгий шаг без возврата «идёт» → TASK-RETURN (урок 525a21f5)"
assert "0 да" "$(tt 'Каждый Bash ≤ 60 с; Не жди.' 'Отправка полным хуком: heavy-slot.sh ci-local -- git push origin HEAD:refs/heads/1-x.' 'Долгое — scripts/detach.sh start <каталог> -- …; верни «идёт: pid, журнал, срок», исход — detach.sh status.') $(has 'строк 3; причин 0')" "близнец: один предел, «Не жди» как норма, возврат «идёт» назван → 0"
: > "$W/task.txt"
assert "2" "$(bash "$P" --task-text "$W/task.txt" > "$W/out" 2>&1; echo $?)" "пустой текст — ноль строк, не «причин нет» → 2"
# Класс «заказ ожидания или паузы числом внутри вызова» (возврат check-verifier по #1225):
# формы урока 525a21f5, на которых перечень форм молчал (rc 0 @7e9fb34e7), — каждая строкой.
for f in 'ожидание `.rc` в пределах 10 мин под no-wait-guard' 'дождись .rc в пределах 10 минут' 'жди .rc до 10 мин' \
    'ждать 270 с между чтениями .rc' 'пауза в 270 с, затем повтор' 'повторяй чтение каждые 270 с' 'жди не дольше 10 мин'; do
    assert "1 да" "$(tt "$f") $(has 'REASON TASK-WAIT строка 1')" "класс ожидания числом: «$f» → TASK-WAIT"
done
# Близнецы: число не о заказе (предел вызова, порог-запрет, прогноз срока) и норма без числа.
for f in 'Не жди' 'Каждый Bash ≤ 60 с' 'Ни один вызов не держит ожидание дольше 10 минут' 'Каждый Bash ≤ 60 с; Не жди.' \
    'ожидаемое окончание через 20 мин'; do
    assert "0 да" "$(tt "$f") $(has 'строк 1; причин 0')" "близнец: «$f» → 0"
done
assert "0 да" "$(bash "$P" --task-text "$HERE/../CLAUDE.md" > "$W/out" 2>&1; echo $?) $(has '; причин 0')" "близнец: CLAUDE.md целиком (норма «Не жди», «дольше 300 с — --enqueue; повтор») → 0"

echo "== дом документа предусловием path (ws#1271)"
prem "path $L 1-lane b.md" "path $L 1-lane docs/"
assert "1 да" "$(runp) $(has "REASON PREMISE-FALSE path $L 1-lane docs/: дома нет")" "каталога нет в ревизии → PREMISE-FALSE «дома нет»"
prem "path $L 1-lane scripts/"
assert "0" "$(runp)" "близнец: каталог есть в ревизии (слэш на конце) → 0"
prem "path $L 1-lane b.md"
assert "0 да" "$(runp) $(has 'предусловий 1; ложных 0, не судимо 0')" "близнец: файл есть в ревизии → 0"
prem "path $L нет-ревизии b.md"
assert "2 да" "$(runp) $(has 'VOID PREMISE-FORM path')" "ревизии нет → не судимо, код 2"

echo "== задание автору приёмки — перепись координат до раздачи (ws#1271)"
tta() { printf '%s\n' "$@" > "$W/task.txt"; bash "$P" --task-text "$W/task.txt" --agent acceptance-author > "$W/out" 2>&1; echo $?; }
ACC='Приёмка: смена контракта ListUsers, дом — b.md, задача o/r#20, ветка 1-lane.'
CEN=("- \`path $L 1-lane b.md\`" '- `task o/r#20 open`' '- `branch o/r 1-lane`')
assert "1 да да да" "$(tta "$ACC") $(has 'REASON TASK-COORD-CENSUS') $(has 'дом (path') $(has 'задача (task')" "задание автору приёмки без переписи (урок «дом приёмки по задаче продукта») → TASK-COORD-CENSUS, недостающие виды названы"
assert "0 да" "$(tta "$ACC" "${CEN[@]}") $(has 'причин 0; агент acceptance-author; строк переписи 3')" "близнец: та же с переписью дом · задача · ветка, сверка сошлась → 0"
assert "1 да" "$(tta "$ACC" "- \`path $L 1-lane docs/x-acceptance.md\`" '- `task o/r#20 open`' '- `branch o/r 1-lane`') $(has 'REASON TASK-COORD-FALSE перепись не сошлась: PREMISE-FALSE path')" "дом по памяти: файла в ревизии нет → TASK-COORD-FALSE с причиной предусловия"
assert "1 да" "$(tta "$ACC" "${CEN[@]}" 'Сосед — o/r#21, его ветку не трогать.') $(has 'REASON TASK-COORD-UNCENSUSED строка 5: «o/r#21»')" "номер задачи вне переписи → TASK-COORD-UNCENSUSED со строкой"
assert "1 да" "$(tta "$ACC" "${CEN[@]}" 'Образец — docs/specs/sub-phase-F6b-x-acceptance.md.') $(has 'TASK-COORD-UNCENSUSED строка 5: «docs/specs/sub-phase-F6b-x-acceptance.md»')" "путь приёмки вне переписи → TASK-COORD-UNCENSUSED"
printf '%s' '{"number":20,"state":"open","title":"x"}' > "$W/c/repos_o_kacho-workspace_issues_20.json"
assert "0" "$(tta "$ACC" "${CEN[@]}" 'Сосед — ws#20.' "- \`task o/kacho-workspace#20\`")" "близнец: короткая форма ws#N сверяется с task <владелец>/kacho-workspace#N"
assert "2 да" "$(tta 'Приёмка: дом — b.md, задача o/r#22.' "- \`path $L 1-lane b.md\`" '- `task o/r#22`' '- `branch o/r 1-lane`') $(has 'VOID перепись не судима (код 2)')" "трекер не ответил на строку переписи → код 2, не зелёное"
assert "0 да" "$(tt "$ACC") $(has 'агент не назван')" "близнец: то же задание без --agent — перепись не требуется, агент назван в переписи"
assert "0" "$(printf '%s\n' "$ACC" > "$W/task.txt"; bash "$P" --task-text "$W/task.txt" --agent go-implementer > "$W/out" 2>&1; echo $?)" "близнец: задание другому агенту — перепись не требуется"
assert "0 да" "$(tt "$ACC" '- `path /ws/tmp/heavy-slots/c 1-lane b.md`' '- `alive /ws/.cache/heavy-slots/x main --enqueue`') $(has 'причин 0')" "близнец: строка переписи с «heavy-slot» и «--enqueue» в пути — данные, а не долгий шаг (корень 5 провалов под TMPDIR слота)"

echo "== строка слияния в задании — форма «#<N> merge #<M>» (ws#1278)"
assert "1 да" "$(tt 'Слей ветку коммитом «#808 merge 746: сборка».') $(has 'REASON TASK-MERGE-FORM строка 1: «#808 merge 746:»')" "«#808 merge 746: …» (урок: хук ветки отверг) → TASK-MERGE-FORM со строкой"
assert "1 да" "$(tt 'Сводка.' 'git commit -m "#808 merge 1272-wave-premise: цепочка"') $(has 'TASK-MERGE-FORM строка 2: «#808 merge 1272-wave-premise:»')" "вливаемая — именем ветки → TASK-MERGE-FORM"
assert "1 да нет" "$(tt 'Сначала «#808 merge #746: a», затем «#808 merge 747: b».') $(has 'TASK-MERGE-FORM строка 1: «#808 merge 747:»') $(has '«#808 merge #746')" "две строки слияния в строке задания — судится каждая, законная молчит"
assert "0 да" "$(tt 'Слей ветку коммитом «#808 merge #746: сборка».') $(has 'строк 1; причин 0')" "близнец: «#808 merge #746: …» → 0"
assert "0 да" "$(tt 'Догон базы — «#808 merge main: догон базы».' 'git commit -m "#808 merge #746"') $(has 'строк 2; причин 0')" "близнец: «merge main» и «merge #746» без хвоста → 0"
assert "0 да" "$(tt 'Форма — «#<N> merge #<M>: …»; номер задачи kacho#808 merge-ветки не трогает.') $(has 'причин 0')" "близнец: шаблон формы без чисел и ссылка репо#N — не строка слияния → 0"

echo "== мутанты lane-precheck (по одной правке; проба выше обязана покраснеть)"
mut() {  # <имя> <было> <стало> <файл предусловий|--task-text строки…> — печатает код мутанта
    local m="$W/mut-lp.sh"
    python3 - "$P" "$m" "$2" "$3" <<'PYM' || { echo "VOID"; return; }
import sys
s, d, a, b = sys.argv[1:5]
t = open(s, encoding="utf-8").read()
if t.count(a) != 1:
    sys.exit(1)
open(d, "w", encoding="utf-8").write(t.replace(a, b))
PYM
    # Мутант — в своём каталоге рядом со ссылками на lib/ и hooks/: HERE мутанта находит их, дерево не тронуто.
    mkdir -p "$W/ms"; ln -sfn "$(dirname "$P")/lib" "$W/ms/lib"; ln -sfn "$(dirname "$P")/hooks" "$W/ms/hooks"
    mv "$m" "$W/ms/lane-precheck.sh"; m="$W/ms/lane-precheck.sh"
    if [ "$4" = --task-text ]; then shift 4; printf '%s\n' "$@" > "$W/task.txt"; bash "$m" --task-text "$W/task.txt" > "$W/out" 2>&1; echo $?
    else shift 3; printf '%s\n' "$@" > "$W/premise.txt"; bash "$m" --premise "$W/premise.txt" > "$W/out" 2>&1; echo $?; fi
}
assert "0" "$(mut state 'elif [ "$gstate" != "$want_state" ]; then' 'elif false; then' 'task o/r#21')" "мутант «состояние не судится»: закрытая задача проходит — проба выше его ловит"
assert "0" "$(mut title '[[ "${gtitle,,}" != *"${want_title,,}"* ]]' 'false' 'task o/r#20 title~квоты')" "мутант «заголовок не судится»: задача не о предмете проходит"
assert "0" "$(mut merged 'elif [ -n "$got" ]; then reasons+=("PREMISE-FALSE $line: ветка $b уже влита' 'elif false; then reasons+=("PREMISE-FALSE $line: ветка $b уже влита' "branchname $W/wsc 1200-old")" "мутант «влитая ветка не судится»: прежнее имя проходит"
assert "0" "$(mut detached '! git -C "$top" symbolic-ref -q HEAD > /dev/null 2>&1 &&' 'false &&' "push-form $W/knd /ws/scripts/heavy-slot.sh ci-local -- git push origin HEAD:refs/heads/3180")" "мутант «отсоединённая голова не судится»: отправка без KACHO_TASK проходит"
assert "0" "$(mut wait '|| { [[ "$w" =~ (^|[^[:alpha:]])(ожида|жд|дожд|подожд|выжд|обожд|пауз|повтор) ]] \' '|| { false \' --task-text 'повторяй чтение каждые 270 с')" "мутант «основа ожидания не судится»: «каждые 270 с» проходит"
assert "1" "$(mut limit 'while [[ "$w" =~ (bash|вызов[[:alpha:]]*)' 'while false && [[ "$w" =~ (bash|вызов[[:alpha:]]*)' --task-text 'Каждый Bash ≤ 60 с; Не жди.')" "мутант «предел вызова не снят»: близнец «Bash ≤ 60 с; Не жди» краснеет — проба выше его ловит"
assert "1" "$(mut thresh 'while [[ "$w" =~ (^|[^[:alpha:]_])${cmp}' 'while false && [[ "$w" =~ (^|[^[:alpha:]_])${cmp}' --task-text 'Ни один вызов не держит ожидание дольше 10 минут')" "мутант «порог-запрет не снят»: норма CLAUDE.md краснеет"
assert "0" "$(mut ne 'while [[ "$w" =~ (^|[^[:alpha:]])не[[:space:]]+$cmp ]]' 'while false' --task-text 'жди не дольше 10 мин')" "мутант «не дольше» прочитан порогом: разрешённый срок проходит"
assert "1" "$(mut forecast 'w="${l//ожидаем/_}"' 'w="$l"' --task-text 'ожидаемое окончание через 20 мин')" "мутант «прогноз не снят»: «ожидаемое окончание» краснеет"
mut_a() {  # <имя> <было> <стало> <строки задания…> — код мутанта на задании автору приёмки
    local nm="$1" a="$2" b="$3"; shift 3
    mut "$nm" "$a" "$b" --task-text "$@" > /dev/null
    printf '%s\n' "$@" > "$W/task.txt"; bash "$W/ms/lane-precheck.sh" --task-text "$W/task.txt" --agent acceptance-author > "$W/out" 2>&1; echo $?
}
assert "0" "$(mut_a census '[ -z "$miss" ] || reasons+=("TASK-COORD-CENSUS' 'true || reasons+=("TASK-COORD-CENSUS' 'Приёмка: смена контракта ListUsers.')" "мутант «перепись не требуется»: задание без переписи проходит — проба выше его ловит"
assert "0" "$(mut_a verify 'if [ "${#cen[@]}" -gt 0 ]; then' 'if false; then' "$ACC" "- \`path $L 1-lane docs/x-acceptance.md\`" '- `task o/r#20 open`' '- `branch o/r 1-lane`')" "мутант «перепись не сверяется»: дом по памяти проходит"
assert "1" "$(mut census-data '${BASH_REMATCH[1]}"; continue' '${BASH_REMATCH[1]}"' --task-text '- `path /ws/tmp/heavy-slots/c 1-lane b.md`')" "мутант «строка переписи судится на ожидание»: путь под heavy-slots даёт TASK-RETURN — проба выше его ловит"
assert "0" "$(mut_a mention 'reasons+=("TASK-COORD-UNCENSUSED' ': || reasons+=("TASK-COORD-UNCENSUSED' "$ACC" "${CEN[@]}" 'Сосед — o/r#21.')" "мутант «упоминание вне переписи не судится»: o/r#21 проходит"
assert "0" "$(mut merge-form '|| reasons+=("TASK-MERGE-FORM' '|| : || reasons+=("TASK-MERGE-FORM' --task-text 'Слей ветку коммитом «#808 merge 746: сборка».')" "мутант «форма слияния не судится»: «#808 merge 746» проходит — проба выше его ловит"
assert "1" "$(mut merge-lawful '(#[0-9]+|main)([^0-9A-Za-z_]|$)' '(#[0-9]+)([^0-9A-Za-z_]|$)' --task-text 'Догон базы — «#808 merge main: догон базы».')" "мутант «merge main не узнан»: законная форма краснеет — проба выше его ловит"

assert "0" "$(LANE_PRECHECK_GIT_BASE="$W/gb" mut pushed '[ "$kind" = pushed ] && [ "$got" != "$want" ]' 'false' "pushed o/r 1-lane $BASE_SHA")" "мутант «голова отправки не сверяется»: непредъявленная голова проходит — проба выше его ловит"

[ -z "${CHERRY_GV:-}" ] || assert "1" "$(mut tags-cut 'if [ "${nf:-0}" -gt 0 ]; then keep=' 'if true; then keep=' "cherry-vet $CHERRY_GV 774")" "мутант «теги не отсекаются»: tools.go даёт ложь vet — проба выше его ловит"
[ -z "${CHERRY_GV:-}" ] || assert "1" "$(mut testdata '*/testdata/*) ctd=$((ctd + 1)); continue ;;' '*/testdata-never/*) ;;' "cherry-vet $CHERRY_GV 774")" "мутант «testdata судится»: битый файл testdata даёт ложь — проба выше его ловит"
[ -z "${CHERRY_GV:-}" ] || assert "0" "$(mut cherry 'elif [ -n "$cerr" ]; then reasons+=' 'elif false; then reasons+=' "cherry-vet $CHERRY_GV 771")" "мутант «отказ vet не судится»: вишня без зависимости проходит — проба выше его ловит"

echo "== вход"
assert "2" "$(run "$W/srv" 1-lane main --issue o/r#7)" "не рабочая копия → код 2"
assert "2" "$(run "$L" 1-lane)" "неполный вызов → код 2"

echo
echo "lane-precheck-inject: утверждений $((pass + fail)); сошлось $pass, разошлось $fail${CHERRY_VOID:+; cherry-vet не судим (нет go)}"
[ "$fail" -eq 0 ] || exit 1
[ -z "${CHERRY_VOID:-}" ] || exit 2
