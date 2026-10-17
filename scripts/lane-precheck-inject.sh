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
trap 'rm -rf "$W"' EXIT
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

echo "== вход"
assert "2" "$(run "$W/srv" 1-lane main --issue o/r#7)" "не рабочая копия → код 2"
assert "2" "$(run "$L" 1-lane)" "неполный вызов → код 2"

echo
echo "lane-precheck-inject: утверждений $((pass + fail)); сошлось $pass, разошлось $fail"
[ "$fail" -eq 0 ]
