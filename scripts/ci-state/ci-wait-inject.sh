#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# ci-wait-inject.sh — доказательство `scripts/ci-state/ci-wait.sh` ИСПОЛНЕНИЕМ (ws#1114).
#
# Чтение подменено (`CI_WAIT_READ`): подставной ci-read.sh отдаёт коды и голову из
# очереди сцены и пишет, с какими доводами его позвали. Каталог состояния (`CI_STATE_DIR`)
# и шаг пробуждения (`CI_WAIT_TICK`) — песочницы. Сигнал демона — строка в FIFO ожидающего,
# как его пишет демон состояния (шапка ci-wait.sh, «КОНТРАКТ С ДЕМОНОМ»).
#
# СЦЕНЫ (каждая меняет один факт против соседней):
#   код 4 первого чтения — выход 4 сразу, ожидания нет («база устарела» до ожидания);
#   код 0 первого чтения — выход 0, чтение одно;
#   3, затем сигнал в FIFO — второе чтение РАНЬШЕ шага пробуждения: будит демон, а не часы;
#   3, сигнала нет (демона нет) — второе чтение по шагу пробуждения (законный близнец);
#   3 всё время — выход 3 по сроку, REASON WAIT-EXPIRED, срок не превышен;
#   голова сменилась — выход без ожидания, REASON HEAD-MOVED;
#   --max 541 — отказ кодом 2 до первого чтения; голова не sha40 — код 2;
#   --from-state — передаётся, только если чтение его знает;
#   FIFO запроса — путь контракта ci-stated.py, 0600, иных следов ожидающий не оставил;
#   --head <голова> — передаётся, только если чтение его знает.
# Коды: 0 — все утверждения сошлись; 1 — нет; 2 — предмета нет (скрипта нет).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CW="$HERE/ci-wait.sh"
[ -r "$CW" ] || { echo "[VOID] ci-wait-inject: скрипта $CW нет — предмета нет" >&2; exit 2; }
W="$(mktemp -d)"
trap '[ -z "${sig:-}" ] || kill "$sig" 2> /dev/null; rm -rf "$W"' EXIT
pass=0 fail=0
H=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
O=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
assert() {
    if [ "$1" = "$2" ]; then echo "  [OK]   $3"; pass=$((pass + 1))
    else echo "  [FAIL] $3 — ожидалось «$1», получено «$2»" >&2; sed 's/^/         /' "$W/out" >&2; fail=$((fail + 1)); fi
}

# Подставное чтение: строка очереди «<код> <голова>», последняя повторяется.
mkreader() { # mkreader <файл> <знает --from-state: 0|1>
    {
        echo '#!/usr/bin/env bash'
        [ "$2" = 1 ] && echo '# доводы: --from-state) — читать из снимка; --head) — ключ снимка'
        cat <<'R'
n=$(( $(cat "$SEQ.n" 2> /dev/null || echo 0) + 1 )); echo "$n" > "$SEQ.n"
line="$(sed -n "${n}p" "$SEQ")"; [ -n "$line" ] || line="$(tail -1 "$SEQ")"
read -r code head <<< "$line"
echo "ARGS $*" >> "$SEQ.args"
[ "$code" != 4 ] || printf 'REASON\tBASE-STALE\tбаза ушла\n'
printf 'VERDICT\tx\tкод %s; причин 0; проверок 1 из 1; голова %s\n' "$code" "$head"
exit "$code"
R
    } > "$1"
}
mkreader "$W/read.sh" 1
mkreader "$W/read-old.sh" 0
export CI_STATE_DIR="$W/state" SEQ="$W/seq"
FIFO="$CI_STATE_DIR/wait/o__r__7.fifo"   # путь контракта ci-stated.py: <владелец>__<репо>__<PR>
scene() { # scene <очередь> — новая очередь чтений
    printf '%s\n' "$@" > "$SEQ"; rm -f "$SEQ.n" "$SEQ.args"
}
reads() { cat "$SEQ.n" 2> /dev/null || echo 0; }
# run <tick> <доводы…> — код в RC, секунды в el; вывод в $W/out (без подоболочки)
RC="" el=0
run() {
    local t="$1" s0; shift
    s0="$(date +%s)"
    CI_WAIT_READ="${READER:-$W/read.sh}" CI_WAIT_TICK="$t" bash "$CW" "$@" > "$W/out" 2>&1; RC=$?
    el=$(( $(date +%s) - s0 ))
}
has() { grep -q -- "$1" "$W/out" && echo да || echo нет; }

echo "== код 4 и иной код — сразу, без ожидания"
scene "4 $H"
run 60 o/r 7 "$H" --max 30
rc="$RC"
assert "4 1 да" "$rc $(reads) $(has 'BASE-STALE')" "код 4 первого чтения — выход 4, чтение одно, причина напечатана"
assert "да" "$([ "$el" -lt 5 ] && echo да || echo нет)" "код 4 — без ожидания (прошло ${el} с)"
scene "0 $H"
run 60 o/r 7 "$H" --max 30
assert "0 1" "$RC $(reads)" "код 0 первого чтения — выход 0, чтение одно"
scene "1 $H"
run 60 o/r 7 "$H" --max 30
assert "1 1" "$RC $(reads)" "код 1 — выход 1 без ожидания"

echo "== сигнал демона будит раньше шага пробуждения"
scene "3 $H" "0 $H"
# Демон пишет строку, когда ожидающий уже прочёл раз (первое чтение — код 3): как
# ci-stated.py — открытием без блокировки; читающего нет — строка не пишется.
(   for _ in $(seq 100); do
        if [ -s "$SEQ.n" ] && [ -p "$FIFO" ]; then
            python3 -c 'import os,sys; fd=os.open(sys.argv[1], os.O_WRONLY|os.O_NONBLOCK); os.write(fd, b"o/r 7 h code 0\n"); os.close(fd)' "$FIFO" 2> /dev/null && exit 0
        fi
        sleep 0.1
    done ) &
sig=$!
run 60 o/r 7 "$H" --max 30
rc="$RC"
wait "$sig" 2> /dev/null; sig=""
assert "0 2 да" "$rc $(reads) $(has 'пробуждений сигналом 1')" "3, затем сигнал в FIFO — второе чтение, выход 0"
assert "да" "$([ "$el" -lt 15 ] && echo да || echo нет)" "разбудил сигнал, а не шаг 60 с (прошло ${el} с)"
assert "да 600 1" "$([ -p "$FIFO" ] && echo да || echo нет) $(stat -c %a "$FIFO" 2> /dev/null) $(find "$CI_STATE_DIR" -mindepth 1 -not -type d | grep -c .)" "FIFO запроса — один, 0600, иных файлов ожидающий не оставил (FIFO снимает демон)"

echo "== демона нет — законный близнец: чтение по шагу пробуждения"
scene "3 $H" "0 $H"
run 1 o/r 7 "$H" --max 20
rc="$RC"
assert "0 2 да" "$rc $(reads) $(has 'пробуждений сигналом 0')" "3, сигнала нет — второе чтение по шагу, выход 0"

echo "== срок"
scene "3 $H"
run 1 o/r 7 "$H" --max 3
rc="$RC"
assert "3 да" "$rc $(has 'REASON	WAIT-EXPIRED')" "3 всё время — выход 3 по сроку, WAIT-EXPIRED"
assert "да" "$([ "$el" -ge 3 ] && [ "$el" -le 8 ] && echo да || echo нет)" "срок 3 с выдержан и не превышен (прошло ${el} с)"
assert "да" "$([ "$(reads)" -ge 2 ] && echo да || echo нет)" "за срок — больше одного чтения (чтений $(reads))"

echo "== голова сменилась — ждать нечего"
scene "3 $O"
run 60 o/r 7 "$H" --max 30
rc="$RC"
assert "3 1 да" "$rc $(reads) $(has 'REASON	HEAD-MOVED')" "голова PR не та — выход без ожидания, HEAD-MOVED"
assert "да" "$([ "$el" -lt 5 ] && echo да || echo нет)" "HEAD-MOVED — без ожидания (прошло ${el} с)"

echo "== доводы"
scene "0 $H"
run 60 o/r 7 "$H" --max 541
assert "2 0" "$RC $(reads)" "--max 541 — отказ кодом 2 до первого чтения"
run 60 o/r 7 "$H" --max=900
assert "2 0" "$RC $(reads)" "--max=900 — отказ кодом 2"
run 60 o/r 7 deadbeef --max 30
assert "2 0" "$RC $(reads)" "голова не sha40 — код 2"
run 60 o/r 7
assert "2 0" "$RC $(reads)" "неполный вызов — код 2"
run 60 o/r 7 "$H" --max=540
assert "0 1" "$RC $(reads)" "близнец: --max=540 — предел, принято"
assert "да" "$(grep -q -- '--from-state' "$SEQ.args" && echo да || echo нет)" "чтение знает --from-state — довод передан"
assert "да" "$(grep -q -- "--head $H" "$SEQ.args" && echo да || echo нет)" "чтение знает --head — голова передана ключом снимка"
scene "0 $H"
READER="$W/read-old.sh"
run 60 o/r 7 "$H"
assert "0" "$RC" "чтение без --from-state — выход 0"
READER=""
assert "нет нет" "$(grep -q -- '--from-state' "$SEQ.args" && echo да || echo нет) $(grep -q -- '--head' "$SEQ.args" && echo да || echo нет)" "близнец: чтение не знает --from-state и --head — доводы не переданы"

echo
echo "ci-wait-inject: утверждений $((pass + fail)); сошлось $pass, разошлось $fail"
[ "$fail" -eq 0 ]
