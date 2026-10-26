#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# push-then-inject.sh — доказательство scripts/push-then.sh ИСПОЛНЕНИЕМ (ws#1242): зависимый
# шаг НЕ выдаётся, пока отправка идёт, вышла не 0 или её голова не доехала до origin; законный
# близнец (отправка 0, голова на origin = отправленной) — шаг выдан с PUSHED_SHA.
# Песочница настоящая: голый origin `$W/gb/o/r.git`, копия с адресом github.com/o/r (подмена
# адреса — `url.insteadOf` копии), lane-precheck — с LANE_PRECHECK_GIT_BASE. Слот — заглушка
# heavy-slot.sh в каталоге-двойнике scripts/ (настоящие push-then, detach, lane-precheck — его
# ссылками): полный хук здесь не предмет, предмет — порядок «отправка → факт → шаг».
# Шаг пробы пишет метку — «выдан» судится по метке, а не по тексту.
# Коды: 0 — всё сошлось, мутанты убиты; 1 — нет; 2 — нет setsid, python3 или git, либо
# утверждений ноль (вердикта нет).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for t in setsid python3 git; do command -v "$t" > /dev/null 2>&1 || { echo "[VOID] нет $t" >&2; exit 2; }; done
W="$(mktemp -d)"; W="$(cd "$W" && pwd -P)"
PGS=()
# shellcheck disable=SC2154
trap '_rc=$?; rm -rf "$W" 2>/dev/null || rm -rf "$W" || echo "ПРЕДУПРЕЖДЕНИЕ: временный каталог $W не снят; код проверки $_rc сохранён" >&2; exit $_rc' EXIT
# Шаги пробы (setsid — своя группа) снимаются группой в конце; долгий шаг снят в своём случае.
reap_steps() { local p; for p in "${PGS[@]+"${PGS[@]}"}"; do kill -- "-$p" 2>/dev/null; done; }
# shellcheck source=lib/sandbox-git-home.sh
. "$HERE/lib/sandbox-git-home.sh"
sandbox_git_home "$W/home" || exit 2

pass=0; fail=0
assert() {
    if [ "$1" = "$2" ]; then echo "  [OK]   $3"; pass=$((pass + 1))
    else echo "  [FAIL] $3 — ожидалось «$1», получено «$2»" >&2; sed 's/^/         /' "$W/out" >&2 2>/dev/null; fail=$((fail + 1)); fi
}

# ── песочница ────────────────────────────────────────────────────────────
mkdir -p "$W/gb/o" "$W/steps"
sandbox_git init -q --bare -b main "$W/gb/o/r.git"
C="$W/copy"
sandbox_git init -q -b 7-lane "$C"
sandbox_git -C "$C" remote add origin https://github.com/o/r.git
sandbox_git -C "$C" config url."$W/gb/".insteadOf https://github.com/
echo a > "$C/a.md"; sandbox_git -C "$C" add . && sandbox_git -C "$C" commit -qm one
sandbox_git -C "$C" push -q origin HEAD:refs/heads/7-lane 2> /dev/null
OLD="$(sandbox_git -C "$C" rev-parse HEAD)"
echo b > "$C/b.md"; sandbox_git -C "$C" add . && sandbox_git -C "$C" commit -qm two
NEW="$(sandbox_git -C "$C" rev-parse HEAD)"   # на origin ещё нет — «непредъявленная голова»
export LANE_PRECHECK_GIT_BASE="$W/gb"
# Копия kaname (ws#1413): ветка 8 правит приёмку, ветка 9 — нет; на origin — лишь база.
sandbox_git init -q --bare -b main "$W/gb/o/kaname.git"
K="$W/kn"
sandbox_git init -q -b main "$K"
sandbox_git -C "$K" remote add origin https://github.com/o/kaname.git
sandbox_git -C "$K" config url."$W/gb/".insteadOf https://github.com/
echo a > "$K/README.md"; sandbox_git -C "$K" add . && sandbox_git -C "$K" commit -qm base
sandbox_git -C "$K" push -q origin HEAD:refs/heads/main 2> /dev/null; sandbox_git -C "$K" fetch -q origin
KBASE="$(sandbox_git -C "$K" rev-parse HEAD)"
sandbox_git -C "$K" checkout -q -b 9; echo b >> "$K/README.md"; sandbox_git -C "$K" commit -qam other; K9="$(sandbox_git -C "$K" rev-parse HEAD)"
sandbox_git -C "$K" checkout -q -b 8 "$KBASE"; mkdir -p "$K/docs/engineering/acceptance"; echo x > "$K/docs/engineering/acceptance/x.md"
sandbox_git -C "$K" add . && sandbox_git -C "$K" commit -qm acc; K8="$(sandbox_git -C "$K" rev-parse HEAD)"
sandbox_git -C "$K" checkout -q -b 8c; echo c >> "$K/README.md"; sandbox_git -C "$K" commit -qam on-acc; K8C="$(sandbox_git -C "$K" rev-parse HEAD)"   # приёмка ниже, на origin/8c
PASS3='--- PASS: TestAcceptancePathCoordinateResolves (0.1s)\n--- PASS: TestAcceptanceEditedAfterItsVerdictSaysSo (0.1s)\n--- PASS: TestAcceptanceProbeCoordinateResolves (0.1s)\nok  x 0.3s\n'
PASS2='--- PASS: TestAcceptancePathCoordinateResolves (0.1s)\n--- PASS: TestAcceptanceEditedAfterItsVerdictSaysSo (0.1s)\nok  x 0.2s\n'
# Чужой репозиторий с тем же путём приёмки (⛔ check-verifier ws#1413, CV-repo-any): статика — лишь kaname.
sandbox_git init -q --bare -b main "$W/gb/o/other.git"
OT="$W/ot"
sandbox_git init -q -b main "$OT"
sandbox_git -C "$OT" remote add origin https://github.com/o/other.git
sandbox_git -C "$OT" config url."$W/gb/".insteadOf https://github.com/
echo a > "$OT/README.md"; sandbox_git -C "$OT" add . && sandbox_git -C "$OT" commit -qm base
sandbox_git -C "$OT" push -q origin HEAD:refs/heads/main 2> /dev/null; sandbox_git -C "$OT" fetch -q origin
sandbox_git -C "$OT" checkout -q -b 5; mkdir -p "$OT/docs/engineering/acceptance"; echo x > "$OT/docs/engineering/acceptance/x.md"
sandbox_git -C "$OT" add . && sandbox_git -C "$OT" commit -qm acc; OT5="$(sandbox_git -C "$OT" rev-parse HEAD)"

# Двойник scripts/: заглушка слота; прочее — ссылки на настоящее.
mkscripts() {  # <каталог> <push-then.sh>
    mkdir -p "$1"
    ln -sfn "$2" "$1/push-then.sh"
    for f in detach.sh lane-precheck.sh lib hooks; do ln -sfn "$HERE/$f" "$1/$f"; done
    cat > "$1/heavy-slot.sh" <<'SLOT'
#!/usr/bin/env bash
# Заглушка слота: «--wait N <класс> -- <команда…>» → команда; STUB_SLOT=74 — слот не выдан.
printf '%s\n' "$*" >> "${STUB_ARGV:-/dev/null}"
[ -n "${STUB_SLOT:-}" ] && exit "$STUB_SLOT"
[ "$1" = --wait ] && shift 2
shift; [ "$1" = -- ] && shift
# Статика приёмок (ws#1413): «go …» — вывод STUB_GO_OUT, код STUB_GO_RC.
if [ "$1" = go ]; then printf "%b" "${STUB_GO_OUT:-}"; exit "${STUB_GO_RC:-0}"; fi
[ -n "${STUB_PUSH_RC:-}" ] && exit "$STUB_PUSH_RC"
exec "$@"
SLOT
}
S="$W/s"; mkscripts "$S" "$HERE/push-then.sh"; PT="$S/push-then.sh"

M="$W/mark"
step=(sh -c 'printf "%s\n" "$PUSHED_SHA" > "$0"' "$M")
# fake_rc <код|-> — файлы шага отправки, как их пишет detach.sh; «-» — без .rc и без процесса.
# «-» — шаг detach.sh (есть .pid мёртвого процесса), «ext» — внешний шаг без .pid.
fake_rc() {
    local b="$W/steps/push-$RANDOM"; echo "lane-push" > "$b.log"
    case "$1" in -) sh -c 'echo $$' > "$b.pid" ;; ext) ;; *) echo "$1" > "$b.rc" ;; esac
    echo "$b.rc"
}
after() { rm -f "$M"; bash "$PT" after "$@" > "$W/out" 2>&1; echo "$? $([ -s "$M" ] && echo выдан || echo нет)"; }
settle() { local _; for _ in $(seq 1 120); do [ -s "$1" ] && return 0; sleep 0.25; done; return 1; }

run_cases() {
    # Каждый прогон (контроль, мутант) — с того же состояния: origin на OLD, копия на NEW.
    sandbox_git -C "$C" checkout -q -B 7-lane "$NEW"; sandbox_git -C "$W/gb/o/r.git" update-ref refs/heads/7-lane "$OLD"
    echo "== after: шаг — только по факту отправки"
    assert "0 выдан" "$(after "$(fake_rc 0)" o/r 7-lane "$OLD" -- "${step[@]}")" "близнец: отправка 0, голова на origin = отправленной — шаг выдан, код 0"
    assert "$OLD" "$(cat "$M" 2>/dev/null)" "шаг получил PUSHED_SHA = отправленную голову"
    assert "12 нет" "$(after "$(fake_rc 0)" o/r 7-lane "$NEW" -- "${step[@]}")" "отправка 0, но на origin другая голова (непредъявленная) — шаг НЕ выдан, 12"
    assert "12 нет" "$(after "$(fake_rc 0)" o/r 9-gone "$OLD" -- "${step[@]}")" "ветки на origin нет — шаг НЕ выдан, 12"
    assert "13 нет" "$(after "$(fake_rc 0)" o/x 7-lane "$OLD" -- "${step[@]}")" "origin не ответил — VOID, шаг НЕ выдан, 13 (не зелёное)"
    assert "10 нет" "$(after "$(fake_rc 1)" o/r 7-lane "$OLD" -- "${step[@]}")" "отправка вышла 1 — шаг НЕ выдан, 10"
    assert "11 нет" "$(after "$(fake_rc -)" o/r 7-lane "$OLD" -- "${step[@]}")" "отправка оборвана (.rc нет, процесса нет) — шаг НЕ выдан, 11"
    assert "14 нет" "$(after "$(fake_rc ext)" o/r 7-lane "$OLD" -- "${step[@]}")" "внешняя отправка без .pid и .rc, журнал никто не держит — не судима, шаг НЕ выдан, 14"
    bash "$HERE/detach.sh" start "$W/steps" -- sleep 30 > "$W/st.out" 2>&1
    local rcf pid; rcf="$(sed -n 's/^идёт: .*; rc \([^;]*\);.*/\1/p' "$W/st.out")"; pid="$(sed -n 's/^идёт: pid \([0-9]*\);.*/\1/p' "$W/st.out")"
    [ -n "$pid" ] && PGS+=("$pid")
    assert "3 нет" "$(after "$rcf" o/r 7-lane "$OLD" -- "${step[@]}")" "отправка идёт (status 3) — шаг НЕ выдан, 3"
    [ -n "$pid" ] && kill -- "-$pid" 2>/dev/null
    assert "5 выдан" "$(after "$(fake_rc 0)" o/r 7-lane "$OLD" -- sh -c 'echo x > "$0"; exit 5' "$M")" "шаг выдан и вышел 5 — код шага как есть"
    assert "64" "$(bash "$PT" after "$(fake_rc 0)" o/r 7-lane "${OLD:0:12}" -- true > "$W/out" 2>&1; echo $?)" "sha не целиком — 64"

    echo "== start: отправка отсоединённо, затем факт, затем шаг"
    local out rc
    rm -f "$M"; out="$(STUB_ARGV="$W/argv" bash "$PT" start "$W/steps" "$C" 7-lane -- "${step[@]}" 2>&1)"; rc=$?; printf '%s\n' "$out" > "$W/out"; printf "%s\n" "$out" > "$W/out"
    rcf="$(sed -n 's/^идёт: .*; rc \([^;]*\);.*/\1/p' <<< "$out")"
    assert "0 да" "$rc $([ -n "$rcf" ] && echo да || echo нет)" "start — код 0 сразу, строка «идёт … rc …» (ожидания в вызове нет)"
    settle "$rcf"
    assert "0 $NEW $NEW" "$(cat "$rcf" 2>/dev/null) $(cat "$M" 2>/dev/null) $(sandbox_git -C "$W/gb/o/r.git" rev-parse 7-lane)" "цепочка: отправка доехала, шаг выдан с отправленной головой, .rc 0"
    assert "да" "$(grep -qF -- '--wait 300 ci-local -- git push origin HEAD:refs/heads/7-lane' "$W/argv" 2>/dev/null && echo да || echo нет)" "отправка — слотом ci-local полным хуком (argv слота назван)"
    echo c > "$C/c.md"; sandbox_git -C "$C" add . && sandbox_git -C "$C" commit -qm three
    rm -f "$M"; out="$(STUB_PUSH_RC=1 bash "$PT" start "$W/steps" "$C" 7-lane -- "${step[@]}" 2>&1)"; printf '%s\n' "$out" > "$W/out"
    rcf="$(sed -n 's/^идёт: .*; rc \([^;]*\);.*/\1/p' <<< "$out")"; settle "$rcf"
    assert "10 нет" "$(cat "$rcf" 2>/dev/null) $([ -s "$M" ] && echo выдан || echo нет)" "цепочка: отправка вышла 1 — .rc 10, шаг НЕ выдан"
    rm -f "$M"; out="$(STUB_SLOT=74 bash "$PT" start "$W/steps" "$C" 7-lane -- "${step[@]}" 2>&1)"; printf '%s\n' "$out" > "$W/out"
    rcf="$(sed -n 's/^идёт: .*; rc \([^;]*\);.*/\1/p' <<< "$out")"; settle "$rcf"
    assert "74 нет" "$(cat "$rcf" 2>/dev/null) $([ -s "$M" ] && echo выдан || echo нет)" "цепочка: слот не выдан — .rc 74, шаг НЕ выдан"
    echo d > "$C/dirty.md"
    assert "64" "$(bash "$PT" start "$W/steps" "$C" 7-lane -- true > "$W/out" 2>&1; echo $?)" "копия грязная — 64, не запущено"
    rm -f "$C/dirty.md"
    assert "64" "$(bash "$PT" start "$W/steps" "$C" 7-lane > "$W/out" 2>&1; echo $?)" "без «-- <шаг>» — 64"
    # Голова копии сдвинулась между start и отправкой — не отправлять и шаг не выдавать.
    rm -f "$M" "$W/argv"; local o7; o7="$(sandbox_git -C "$W/gb/o/r.git" rev-parse 7-lane)"
    assert "64 нет нет $o7" "$(STUB_ARGV="$W/argv" bash "$PT" _run "$C" o/r 7-lane "$OLD" -- "${step[@]}" > "$W/out" 2>&1; echo $?) $([ -s "$M" ] && echo выдан || echo нет) $([ -s "$W/argv" ] && echo отправлено || echo нет) $(sandbox_git -C "$W/gb/o/r.git" rev-parse 7-lane)" "голова копии не та, что при start, — 64: отправки нет, шаг НЕ выдан, origin прежний"

    echo "== голова уже на origin — отправка не повторяется (ws#1413)"
    sandbox_git -C "$C" checkout -q --detach "$o7"; rm -f "$M" "$W/argv"
    assert "0 выдан нет" "$(STUB_ARGV="$W/argv" bash "$PT" _run "$C" o/r 7-lane "$o7" -- "${step[@]}" > "$W/out" 2>&1; echo $?) $([ -s "$M" ] && echo выдан || echo нет) $(grep -q 'git push' "$W/argv" 2>/dev/null && echo отправлено || echo нет)" "голова на origin = копии — шаг выдан по факту, второй отправки нет (уроки 90ba32bc, 09c2da35)"

    echo "== статика приёмок kaname до полного хука (ws#1413)"
    kn() {  # <ветка> <sha> [<копия> <репо>] — код _run, «выдан|нет», «go|-», «push|-»
        local cp="${3:-$K}" rp="${4:-o/kaname}"
        sandbox_git -C "$cp" checkout -q "$1"; rm -f "$M" "$W/argv"
        sandbox_git -C "$W/gb/$rp.git" update-ref -d "refs/heads/$1" 2> /dev/null
        sandbox_git -C "$cp" update-ref -d "refs/remotes/origin/$1" 2> /dev/null
        [ -z "${KN_ORIGIN_AT:-}" ] || { sandbox_git -C "$W/gb/$rp.git" update-ref "refs/heads/$1" "$KN_ORIGIN_AT"; sandbox_git -C "$cp" update-ref "refs/remotes/origin/$1" "$KN_ORIGIN_AT"; }
        STUB_ARGV="$W/argv" bash "$PT" _run "$cp" "$rp" "$1" "$2" -- "${step[@]}" > "$W/out" 2>&1; local rc=$?
        echo "$rc $([ -s "$M" ] && echo выдан || echo нет) $(grep -q 'go test ./internal/check' "$W/argv" 2>/dev/null && echo go || echo -) $(grep -q 'git push' "$W/argv" 2>/dev/null && echo push || echo -)"
    }
    assert "15 нет go -" "$(STUB_GO_RC=1 STUB_GO_OUT='--- FAIL: TestAcceptancePathCoordinateResolves (0.1s)\nFAIL\n' kn 8 "$K8")" "правка приёмки, проба красная — 15: отправки нет, шаг НЕ выдан (уроки ea998b24, 67c9bf72)"
    assert "16 нет go -" "$(STUB_GO_OUT='ok  x 0.1s [no tests to run]\n' kn 8 "$K8")" "проб исполнено не три («no tests to run») — 16, не зелёное: отправки нет"
    assert "0 выдан go push" "$(STUB_GO_OUT="$PASS3" kn 8 "$K8")" "близнец: три пробы прошли — отправка и шаг"
    assert "0 выдан - push" "$(kn 9 "$K9")" "близнец: приёмка не тронута — статики нет, отправка и шаг"
    # ⛔ check-verifier ws#1413: CV-np-any, CV-ob-mergebase-only, CV-ob-empty-open, CV-repo-any.
    assert "16 нет go -" "$(STUB_GO_OUT="$PASS2" kn 8 "$K8")" "прошло 2 из 3 при коде 0 — 16, не зелёное: отправки нет"
    assert "0 выдан - push" "$(KN_ORIGIN_AT="$K8" kn 8c "$K8C")" "близнец: приёмка уже на origin/8c, новая голова её не трогает — статики нет (база — origin/<ветка>, не merge-base)"
    sandbox_git -C "$K" update-ref -d refs/remotes/origin/main
    assert "0 выдан go push" "$(STUB_GO_OUT="$PASS3" kn 8 "$K8")" "базы нет (ни origin/<ветка>, ни merge-base) — статика гонится, а не пропускается"
    sandbox_git -C "$K" update-ref refs/remotes/origin/main "$KBASE"
    assert "0 выдан - push" "$(kn 5 "$OT5" "$OT" o/other)" "близнец: тот же путь приёмки не в kaname — статики нет"
}

run_cases

echo "== мутанты (по одной правке; проба выше обязана покраснеть)"
muts=0; survived=0
mutant() {  # <имя> <было> <стало>
    local d="$W/mut-$1"; mkdir -p "$d"
    python3 - "$HERE/push-then.sh" "$d/push-then.real" "$2" "$3" <<'PY' || { echo "  [VOID] мутант $1: правка не легла"; survived=$((survived + 1)); return; }
import sys
s, d, a, b = sys.argv[1:5]
t = open(s, encoding="utf-8").read()
if t.count(a) != 1:
    sys.exit(1)
open(d, "w", encoding="utf-8").write(t.replace(a, b))
PY
    muts=$((muts + 1))
    mkscripts "$d" "$d/push-then.real"
    local before=$fail
    PT="$d/push-then.sh"; run_cases > "$W/mut.out" 2>&1; PT="$S/push-then.sh"
    if [ "$fail" -gt "$before" ]; then echo "  [убит] $1 — $(grep -m1 -F '[FAIL]' "$W/mut.out" | sed 's/^ *\[FAIL\] //' | cut -c1-160)"
    else echo "  [ВЫЖИЛ] $1"; survived=$((survived + 1)); fi
    fail=$before
}
mutant running-issues '        0) ;;
        3) say' '        0 | 3) ;;
        3333) say'
mutant head-unchecked '        1) say "голова $br на origin не $sha — шаг НЕ выдан"; return 12 ;;' '        1) ;;'
mutant head-moved-ignored '    [ "$(git rev-parse HEAD)" = "$sha" ] || { say' '    true || { say'
mutant push-rc-ignored '0) st=0 ;; *) st=1 ;; esac' '*) st=0 ;; esac'
mutant already-pushed-ignored 'if [ "$(git ls-remote origin "refs/heads/$br" 2>/dev/null | cut -f1)" = "$sha" ]; then' 'if false; then'
mutant acc-static-skipped 'if [ "${repo##*/}" = kaname ]; then' 'if false; then'
mutant acc-diff-unchecked '[ -z "$ob" ] || [ -n "$(git diff --name-only "$ob" HEAD -- docs/engineering/acceptance/ 2>/dev/null)" ]' 'true'
mutant acc-red-ignored '[ "$arc" = 0 ] || [ "$nf" = 0 ] || {' 'true || {'
mutant acc-count-unchecked '[ "$arc" = 0 ] && [ "$np" = 3 ] ||' 'true ||'
mutant cv-np-any '[ "$arc" = 0 ] && [ "$np" = 3 ] ||' '[ "$arc" = 0 ] && [ "$np" != 0 ] ||'
mutant cv-ob-mergebase-only 'ob="$(git rev-parse -q --verify "refs/remotes/origin/$br" || git merge-base' 'ob="$(git merge-base'
mutant cv-ob-empty-open '[ -z "$ob" ] || [ -n "$(git diff' '[ -n "$(git diff'
mutant cv-repo-any 'if [ "${repo##*/}" = kaname ]; then' 'if true; then'

reap_steps
total=$((pass + fail))
echo "[CENSUS] push-then: утверждений $total, сошлось $pass, разошлось $fail; мутантов $muts, выжило $survived"
[ "$total" -gt 0 ] || { echo "[VOID] утверждений ноль — вердикта нет" >&2; exit 2; }
[ "$fail" -eq 0 ] && [ "$survived" -eq 0 ]
