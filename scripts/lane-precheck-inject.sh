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
# отправки — форма из шапки предпроверки, итог хука — дословные строки хуков.
# Каждая порча меняет ОДИН факт против контроля.
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
# api --paginate repos/<o>/<r>/issues/<n>/comments --jq <выражение>
[ "$1" = api ] || exit 1
path="" expr=""
while [ $# -gt 0 ]; do
    case "$1" in --jq) expr="$2"; shift 2 ;; repos/*) path="$1"; shift ;; *) shift ;; esac
done
f="$GH_FIXTURES/$(printf '%s' "$path" | tr '/' '_').json"
[ -f "$f" ] || { echo "HTTP 404" >&2; exit 1; }
jq -r "$expr" "$f"
GH
chmod +x "$W/gh"
export LANE_PRECHECK_GH="$W/gh" LANE_PRECHECK_WS="$W/ws" GH_FIXTURES="$W/c"
cfile() { echo "$W/c/repos_o_r_issues_$1_comments.json"; }
comments() { local n="$1"; shift; printf '%s\n' "$@" | jq -R . | jq -s '[.[] | {body: .}]' > "$(cfile "$n")"; }
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

echo "== словарь итогов хука по репозиторию"
for kind in corelib kaname kacho other; do git init -q --bare -b main "$W/srv/$kind.git"; done
git -C "$L" remote set-url origin "$W/srv/corelib.git"; git -C "$L" push -q origin main 1-lane 2> /dev/null
log "$HEAD_SHA" "pre-push (corelib): исполнено 4 из 5, красных 0 — отправляю" 0
assert "1 да" "$(run "${ok_args[@]}") $(has 'REASON HOOK-NOT-GREEN')" "corelib: исполнено 4 из 5 — не зелёный"
log "$HEAD_SHA" "pre-push (corelib): исполнено 5 из 5, красных 0 — отправляю" 0
assert "0" "$(run "${ok_args[@]}")" "близнец corelib: 5 из 5 → 0"
git -C "$L" remote set-url origin "$W/srv/kaname.git"; git -C "$L" push -q origin main 1-lane 2> /dev/null
log "$HEAD_SHA" "pre-push: зелёное — исполнено 6 из 6 групп, отказов 0." 0
assert "0" "$(run "${ok_args[@]}")" "kaname: строка зелёного итога → 0"
log "$HEAD_SHA" "pre-push: НЕ ВЫПОЛНИЛОСЬ — групп без условия 1 из 6: x." 0
assert "1" "$(run "${ok_args[@]}")" "kaname: недобор групп — не зелёный"
git -C "$L" remote set-url origin "$W/srv/kacho.git"; git -C "$L" push -q origin main 1-lane 2> /dev/null
log "$HEAD_SHA" "== pre-push: локальные проверки зелёные (не выполненных нет) — отправляю" 0
assert "0" "$(run "${ok_args[@]}")" "kacho: строка зелёного итога → 0"
git -C "$L" remote set-url origin "$W/srv/other.git"; git -C "$L" push -q origin main 1-lane 2> /dev/null
assert "2 да" "$(run "${ok_args[@]}") $(has 'VOID HOOK-KIND-UNKNOWN')" "репозиторий вне словаря → код 2"

echo "== вход"
assert "2" "$(run "$W/srv" 1-lane main --issue o/r#7)" "не рабочая копия → код 2"
assert "2" "$(run "$L" 1-lane)" "неполный вызов → код 2"

echo
echo "lane-precheck-inject: утверждений $((pass + fail)); сошлось $pass, разошлось $fail"
[ "$fail" -eq 0 ]
