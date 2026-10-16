#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
# Строки команд — предмет пробы, а не код этой оболочки: `$(…)` и `$l` в них не
# раскрываются намеренно.
# shellcheck disable=SC2016
#
# prove.sh — доказательство no-wait-guard ИНЪЕКЦИЕЙ (ws#1004): хук исполняется
# настоящим входом PreToolUse (JSON на stdin, как его подаёт харнесс), и проба
# сверяет код и текст.
#
#   · каждая запрещённая форма — отказ кодом 2, класс формы назван, текст несёт
#     правило «Не жди» и правильную форму (setsid env --default-signal=PIPE … > журнал, .rc, pid-файл);
#   · законный близнец той же формы — пропуск: код 0 и ни слова (короткий sleep,
#     timeout < 600, отсоединённый запуск, одно чтение CI, слова в данных);
#   · метка исключения — только ci-watcher, ≤ 9 мин и под timeout ≤ N·60;
#   · граница (BOUNDARY шапки guard.py) — [BOUND]: известно, не ловится; пойманный
#     пример — [FAIL]: шапка устарела;
#   · мутанты guard.py (по одной правке) обязаны покраснеть: проба, не способная
#     отличить сломанный страж, ничего не доказывает;
#   · поломка стража — пропуск со словом «СЛОМАН», а не отказ всему.
# Коды: 0 — все утверждения сошлись; 1 — нет; 2 — нет python3 (вердикта нет).
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$HOOK_DIR/no-wait-guard.sh"
GUARD="$HOOK_DIR/no-wait-guard/guard.py"
command -v python3 > /dev/null 2>&1 || { echo "[VOID] no-wait-guard: нет python3" >&2; exit 2; }
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0; denied=0; passed=0; bound=0; muts=0
AGENT=""
assert() {
    if [ "$1" = "$2" ]; then echo "  [OK]   $3"; pass=$((pass + 1))
    else echo "  [FAIL] $3 — ожидалось «$1», получено «$2»" >&2; fail=$((fail + 1)); fi
}
# run <команда> [хук] — код хука на настоящем входе; вывод в $WORK/out.
run() {
    python3 -c 'import json,sys; d={"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":"/tmp"}
if sys.argv[2]: d["agent_type"]=sys.argv[2]
print(json.dumps(d))' "$1" "$AGENT" > "$WORK/in.json"
    CLAUDE_PROJECT_DIR=/ws bash "${2:-$HOOK}" < "$WORK/in.json" > "$WORK/out" 2>&1
    echo $?
}
# denies <класс-текст> <команда> — отказ 2; форма названа; правило и правильная форма в тексте.
denies() {
    local rc named rule fix
    rc="$(run "$2")"
    named="нет"; grep -qF -- "$1" "$WORK/out" && named="да"
    rule="нет"; grep -qF 'Правило «Не жди»' "$WORK/out" && rule="да"
    fix="нет"; grep -qF "setsid env --default-signal=PIPE sh -c '<команда>; echo \$? > <журнал>.rc' > <журнал> 2>&1 & echo \$! > <pid-файл>" "$WORK/out" && ! grep -qF 'setsid nohup <команда>' "$WORK/out" && fix="да"
    assert "2 да да да" "$rc $named $rule $fix" "отказ ($1): $(printf '%s' "$2" | tr '\n' ' ')"
    denied=$((denied + 1))
}
passes() {
    local rc
    rc="$(run "$1")"
    assert "0 0" "$rc $(wc -c < "$WORK/out" | tr -d ' ')" "пропуск: $(printf '%s' "$1" | tr '\n' ' ')"
    passed=$((passed + 1))
}
boundary() {
    local rc
    rc="$(run "$2")"
    if [ "$rc $(wc -c < "$WORK/out" | tr -d ' ')" = "0 0" ]; then
        echo "  [BOUND] не ловится (граница: $1): $(printf '%s' "$2" | tr '\n' ' ')"; bound=$((bound + 1))
    else
        echo "  [FAIL] граница «$1» — страж поймал пример (код $rc): шапка guard.py устарела" >&2; fail=$((fail + 1))
    fi
}

LOOP='цикл until/while со sleep'
TAIL='tail --pid / tail -f'
CI='ожидание CI'
SLEEP='sleep ≥ 300 с'
TMO='timeout ≥ 600 с без отсоединения'
FLOCK='flock ждёт замка'
FOR='цикл for со sleep'
BGW='wait после фонового запуска'
BUSY='read из /dev/zero, /dev/urandom или после yes |'

echo "== запрещённые формы — отказ с правилом и правильной формой"
denies "$LOOP"  'until test -f /tmp/x.done; do sleep 30; done'
denies "$LOOP"  'while kill -0 123 2>/dev/null; do sleep 10; done; tail -n 20 log'
denies "$LOOP"  'while true; do gh pr checks 7; sleep 60; done'
denies "$LOOP"  'bash -c "until curl -sf http://x; do sleep 3; done"'
denies "$LOOP"  'timeout 300 bash -lc "while ! test -f d; do sleep 1; done"'
denies "$LOOP"  $'bash <<EOF\nwhile :; do sleep 1; done\nEOF'
denies "$LOOP"  $'cat <<EOF | bash\nwhile :; do sleep 1; done\nEOF'
denies "$FOR"   $'cat <<\'EOF\' | bash -s\nfor i in $(seq 100); do sleep 10; done\nEOF'
denies "$TAIL"  'tail --pid=4242 -f /tmp/run.log'
denies "$TAIL"  'tail --pid 4242 -n0 -f log'
denies "$TAIL"  'tail -F /tmp/run.log'
denies "$CI"    'gh run watch 123456'
denies "$CI"    'gh pr checks 7 --watch --interval 30'
denies "$CI"    'cd x && gh run watch --exit-status 1'
denies "watch"  'watch -n 5 kubectl get pods'
denies "$SLEEP" 'sleep 300'
denies "$SLEEP" 'sleep 5m && gh pr checks 7'
denies "$SLEEP" 'x=$(sleep 900; echo y)'
denies "$BGW"   'sleep 600 & wait'
denies "$TMO"   'timeout 600 go test ./...'
denies "$TMO"   'timeout 1h make ci'
denies "$TMO"   'nohup timeout 3600 go test ./... > l 2>&1'
denies "$TMO"   'setsid timeout 900 go test ./...'
denies "$SLEEP" 'sudo sleep 900'
denies "$SLEEP" 'sudo -u root -- sleep 900'
denies "$TMO"   'sudo -E timeout 3600 make ci'
denies "$FLOCK" 'flock -w 300 ~/.cache/heavy-slots/slot1.lock go test ./...'
denies "$FLOCK" 'flock -w 2400 /tmp/l true'
denies "$FLOCK" 'flock ~/.cache/heavy-slots/slot1.lock go test ./...'
denies "$FOR"   'for i in $(seq 60); do sleep 10; done'
denies "$FOR"   'for i in {1..30}; do gh pr checks 7; sleep 10; done'
denies "$FOR"   'for i in a b c d e f g h i j; do sleep 30; done'
denies "$FOR"   'for i in a b c; do for j in 1 2 3 4 5 6 7 8 9 10; do sleep 10; done; done'
denies "$FOR"   'for ((i=0; i<100; i++)); do sleep 5; done'
denies "$FOR"   'for f in *.log; do sleep 1; done'
denies "$FOR"   'for i in 1 2; do sleep "$d"; done'
denies "$FOR"   'bash -c "for i in \$(seq 60); do sleep 10; done"'
denies "$BGW"   'make test > l 2>&1 & wait'
denies "$BGW"   'go test ./... > l 2>&1 & pid=$!; wait $pid'
denies "$BGW"   'a & b & wait $!'
denies "$BGW"   '{ make a & make b; }; wait'
denies "$BUSY"  'read -t 290 < /dev/zero'
denies "$BUSY"  'read -t5 </dev/urandom'
denies "$BUSY"  'read -t 9 0</dev/random x'
denies "$BUSY"  'read -r x <> /dev/zero'
denies "$BUSY"  'yes | read -t 5 x'
denies "$BUSY"  'cat /dev/zero | read -t 3'
denies "$BUSY"  'yes | while read -t 1 l; do :; done'
denies "$BUSY"  'while read -t 1 l; do :; done < /dev/zero'
denies "$BUSY"  'timeout 5 bash -c "read -t 4 < /dev/zero"'
denies "$BUSY"  'read -t 60 < /dev/zero > /dev/null 2>&1 &'
rc="$(run 'read -t 290 < /dev/zero')"
assert "2 да" "$rc $(grep -qF 'подсказка: жди через heavy-slot --enqueue или короткий шаг' "$WORK/out" && echo да || echo нет)" "busy-read — подсказка «жди через heavy-slot --enqueue или короткий шаг»"
rc="$(run 'timeout 500 read -t 5 < /dev/zero # no-wait-exempt ci-watcher 9m')"
assert 2 "$rc" "busy-read — метка ci-watcher его не снимает"
denied=$((denied + 2))

echo "== законные близнецы той же формы — пропуск без слова"
passes 'sleep 299'
passes 'sleep 30 && gh pr checks 7'
passes 'timeout 599 go test ./...'
passes 'timeout 120 tail -f /tmp/run.log'
passes 'tail -n 50 /tmp/run.log; kill -0 4242 && echo идёт'
passes 'gh pr checks 7'
passes 'gh run view 123456 --json status,conclusion'
passes 'flock -n /tmp/l true'
passes 'sudo true'
passes 'sudo -u root sleep 5'
passes 'flock -w 60 /tmp/l true'
passes 'setsid nohup timeout 3600 go test ./... > /tmp/run.log 2>&1 & echo $! > /tmp/run.pid'
passes 'nohup bash -c "until test -f d; do sleep 5; done" > l 2>&1 &'
passes '( while true; do sleep 5; done ) > l 2>&1 &'
passes 'setsid -f sleep 900'
passes 'while read -r l; do echo "$l"; done < f'
passes 'read -t 5 -r l < /tmp/run.log'
passes 'read -r l <<< "$x"'
passes 'while read -r x < f; do :; done < /dev/zero'
passes 'head -c 32 /dev/urandom > key'
passes 'yes | head -n 3'
passes 'yes | apt-get install x'
passes 'grep -c /dev/zero f; echo "read -t 5 < /dev/zero"'
passes 'for i in 1 2 3; do gh pr checks 7; done'
passes 'for i in 1 2 3; do gh pr checks 7; sleep 5; done'
passes 'for i in 1 2 3 4 5 6 7 8 9; do sleep 33; done'
passes 'for i in $(seq 60); do echo "$i"; done'
passes 'for i in $(seq 60); do sleep 10; done > l 2>&1 &'
passes 'for i in 1 2 3; do sleep 200 & done'
passes 'timeout 60 bash -c "for i in \$(seq 9); do sleep 5; done"'
passes 'setsid nohup make test > l 2>&1 & echo $! > p'
passes "setsid env --default-signal=PIPE sh -c 'go test ./...; echo \$? > l.rc' > l 2>&1 & echo \$! > p"
passes 'bash -c "make a & make b & wait" > l 2>&1 &'
passes 'git commit -m "until x; do sleep 900; done; gh run watch"'
passes 'echo "sleep 600"; grep -n "tail --pid" f'
passes $'cat > f.sh <<EOF\nwhile :; do sleep 1; done\nEOF'
passes $'cat <<EOF | grep sleep\nwhile :; do sleep 1; done\nEOF'
passes '/ws/scripts/heavy-slot.sh go-race -- go test -race ./...'
passes '/ws/scripts/heavy-slot.sh --wait 300 go-race -- go test -race ./...'

echo "== ожидание CI — ci-wait.sh (ws#1114): одна команда, срок за вызов ≤ 540 с"
# Блокирующее чтение FIFO демона состояния — ОДНА команда. Отказ: срок ожидания CI за
# вызов > 540 (--max выше или не вычислим; сумма запусков — цепочка, подстановка) и запуск
# в цикле при любом сроке. Возврат check-verifier @bcc01837a: while, for и `&&` с ci-wait.sh
# без sleep пропускались кодом 0. Запуск судится по узлу: путь в данных — не запуск.
CIW='ci-wait.sh: срок ожидания CI за вызов'
H40=ffffffffffffffffffffffffffffffffffffffff
CWS="bash /ws/scripts/ci-state/ci-wait.sh PRO-Robotech/kacho 7 $H40"
RCP='( set -o pipefail; WS=/ws; git -C "$WS" fetch -q origin main && R=$(git -C "$WS" show origin/main:scripts/landing-precheck.sh | sed -n p) && [ -n "$R" ] || exit 2; WS="$WS" S=ci-state/ci-wait.sh TMPDIR=/ws/tmp/wave-9 bash -c "$R" _ PRO-Robotech/kacho 7 '"$H40"
# reason <подстрока> — причину, а не симптом, называет вывод последнего отказа.
reason() {
    local got=нет
    grep -qF -- "$1" "$WORK/out" && got=да
    assert да "$got" "  причина названа: «$1»"
}
passes "$CWS --max 540"
passes "$CWS"
passes "/ws/scripts/ci-state/ci-wait.sh PRO-Robotech/kacho 7 $H40 --max=300"
passes "$RCP --max 540 ) > /ws/tmp/wave-9/ci-0.md 2>&1"
denies "$CIW" "$CWS --max 541"
reason 'за вызов 541 с, запусков 1'
denies "$CIW" "$CWS --max 700"
denies "$CIW" "$CWS --max=900"
denies "$CIW" "$CWS --max \"\$M\""
reason 'не вычислим по тексту'
denies "$CIW" "$CWS --max 100 --max 900"
denies "$CIW" "$RCP --max 700 ) > /ws/tmp/wave-9/ci-0.md 2>&1"
denies "$CIW" "sh /ws/scripts/ci-state/./ci-wait.sh PRO-Robotech/kacho 7 $H40 --max 900"
echo "   композиция без sleep: цикл и цепочка"
denies "$CIW" "while true; do $CWS --max 540; done"
reason 'в цикле while'
denies "$CIW" "until $CWS --max 540; do :; done"
reason 'в цикле until'
denies "$CIW" "for i in 1 2 3; do $CWS --max 540; done"
reason 'в цикле for'
denies "$CIW" "timeout 300 bash -c 'while :; do $CWS --max 100; done'"
denies "$CIW" "while :; do $RCP --max 540 ) > /ws/tmp/wave-9/ci-0.md 2>&1; done"
denies "$CIW" "CW=/ws/scripts/ci-state/ci-wait.sh; while :; do bash \"\$CW\" PRO-Robotech/kacho 7 $H40 --max 540; done"
denies "$CIW" "for i in 1 2; do . /ws/scripts/ci-state/ci-wait.sh PRO-Robotech/kacho 7 $H40 --max 60; done"
denies "$CIW" "$CWS --max 540 && $CWS --max 540"
reason 'за вызов 1080 с, запусков 2'
denies "$CIW" "$CWS --max 300; $CWS --max 241"
denies "$CIW" "v=\$($CWS --max 540); w=\$($CWS --max 540)"
denies "$LOOP" "while bash /ws/scripts/ci-read.sh PRO-Robotech/kacho 7; [ \$? = 3 ]; do sleep 60; done"
denies "$LOOP" "while :; do $CWS --max 540; sleep 1; done"
echo "   подстановка в теле и условии цикла — запуск в цикле (возврат check-verifier @99637b3c7)"
denies "$CIW" "while :; do out=\$($CWS --max 540); done"
reason 'в цикле while'
denies "$CIW" "while :; do out=\`$CWS --max 540\`; done"
denies "$CIW" "until false; do echo \"\$($CWS --max 540)\"; done"
reason 'в цикле until'
denies "$CIW" "for i in 1 2; do x=\$($CWS --max 60); done"
reason 'в цикле for'
denies "$CIW" "for i in 1 2; do x=\`$CWS --max 60\`; done"
denies "$CIW" "while [ \"\$($CWS --max 540)\" != ok ]; do :; done"
denies "$CIW" "until [ \"\$($CWS --max 540)\" = ok ]; do :; done"
denies "$CIW" "while out=\$($CWS --max 540); [ \"\$out\" != ok ]; do :; done"
denies "$CIW" "until [ \"\`$CWS --max 540\`\" = ok ]; do :; done"
denies "$CIW" "select o in a b; do x=\$($CWS --max 60); done"
reason 'в цикле select'
echo "   срок в ветках if и в хвосте перенаправлений — в сумме за вызов"
denies "$CIW" "if true; then x=\$($CWS --max 900); fi"
reason 'за вызов 900 с'
denies "$CIW" "if false; then :; else x=\$($CWS --max 900); fi"
denies "$CIW" "if false; then :; elif x=\$($CWS --max 900); then :; fi"
denies "$CIW" "if true; then x=\$($CWS --max 300); fi; y=\$($CWS --max 300)"
reason 'за вызов 600 с, запусков 2'
denies "$CIW" "while read -r l; do :; done < <($CWS --max 900)"
echo "   законные близнецы той же формы: один запуск, сумма ≤ 540, путь в данных, фон"
passes "$CWS --max 540 || echo \"код \$?\""
passes "$CWS --max 270 && $CWS --max 270"
passes "$CWS --max 900 --max 100"
passes "timeout 300 bash -c '$CWS --max 540; $CWS --max 540'"
passes "for x in \$($CWS --max 540); do echo \"\$x\"; done"
passes "for f in /ws/scripts/ci-state/ci-wait.sh /ws/scripts/ci-read.sh; do shellcheck \"\$f\"; done"
passes "for i in 1 2; do grep -c -- --max /ws/scripts/ci-state/ci-wait.sh; done"
passes "grep -n -- --max /ws/scripts/ci-state/ci-wait.sh"
passes "bash -n /ws/scripts/ci-state/ci-wait.sh && $CWS --max 540"
passes "shellcheck /ws/scripts/ci-state/ci-wait.sh && $CWS --max 540"
passes "while :; do $CWS --max 540; done > l 2>&1 &"
passes "$CWS --max 540 > l 2>&1 & $CWS --max 540"
echo "   законные близнецы подстановки: раз до цикла, сумма ≤ 540, путь в данных, фон"
passes "for x in \`$CWS --max 540\`; do echo \"\$x\"; done"
passes "if x=\$($CWS --max 540); then echo \"\$x\"; fi"
passes "if true; then x=\$($CWS --max 270); fi; y=\$($CWS --max 270)"
passes "while read -r l; do echo \"\$l\"; done < <($CWS --max 540)"
passes "while :; do n=\$(grep -c -- --max /ws/scripts/ci-state/ci-wait.sh); break; done"
passes "until x=\$(bash -n /ws/scripts/ci-state/ci-wait.sh); do :; done"
passes "echo \"\$($CWS --max 540)\" > l 2>&1 & $CWS --max 540"
passes "while :; do x=\$($CWS --max 540); done > l 2>&1 &"

echo "== метка исключения — только ci-watcher, ≤ 9 мин, под timeout ≤ N·60"
passes 'timeout 540 gh run watch 1 # no-wait-exempt ci-watcher 9m'
passes 'timeout 120 gh pr checks 7 --watch # no-wait-exempt ci-watcher 2m'
AGENT=ci-watcher
passes 'timeout 500 gh run watch 1 # no-wait-exempt ci-watcher 9m'
AGENT=go-implementer
rc="$(run 'timeout 500 gh run watch 1 # no-wait-exempt ci-watcher 9m')"
assert "2 да" "$rc $(grep -qF 'исключение только у ci-watcher' "$WORK/out" && echo да || echo нет)" "метку ci-watcher несёт другой агент — отказ, причина названа"
AGENT=""
rc="$(run 'timeout 500 gh run watch 1 # no-wait-exempt ci-watcher 10m')"
assert "2 да" "$rc $(grep -qF 'предел 9 мин' "$WORK/out" && echo да || echo нет)" "метка на 10 мин — отказ, предел назван"
rc="$(run 'gh run watch 1 # no-wait-exempt ci-watcher 9m')"
assert "2 да" "$rc $(grep -qF 'без timeout ≤ 540 с' "$WORK/out" && echo да || echo нет)" "метка без timeout — отказ: ожидание без предела"
rc="$(run 'timeout 541 gh run watch 1 # no-wait-exempt ci-watcher 9m')"
assert 2 "$rc" "метка 9 мин, timeout 541 с — отказ"
rc="$(run 'timeout 500 gh run watch 1 # no-wait-exempt go-implementer 9m')"
assert "2 да" "$rc $(grep -qF 'только у ci-watcher' "$WORK/out" && echo да || echo нет)" "метка другого агента — отказ"
denied=$((denied + 5))
rc="$(run "timeout 500 bash -c 'while :; do $CWS --max 100; done' # no-wait-exempt ci-watcher 9m")"
assert 2 "$rc" "ci-wait.sh в цикле — метка ci-watcher его не снимает и под timeout"
denied=$((denied + 1))

echo "== граница (BOUNDARY шапки guard.py) — известно, не ловится"
boundary "путь ci-wait.sh — переменная цикла for" "for f in /ws/scripts/ci-state/ci-wait.sh; do bash \"\$f\" PRO-Robotech/kacho 7 $H40 --max 540; done"
boundary "цикл без sleep вокруг иного блокирующего чтения" 'while :; do timeout 500 head -n1 /tmp/fifo; done'
boundary "цикл без sleep вокруг чтения CI" 'while :; do gh pr checks 7; done'
boundary "ожидание внутри скрипта"     'bash ./wait-for-ci.sh'
boundary "wait без фонового запуска"   'wait 4242'
boundary "eval: строка не разбирается" 'eval "sleep 900"'
boundary "xargs: argv из входа"       'echo 900 | xargs sleep'
boundary "иной интерпретатор"         'python3 -c "import time; time.sleep(900)"'
boundary "источник — дескриптор"      'exec 3< /dev/zero; read -t 9 -u 3'
boundary "свой редирект на дескриптор"  'read -t 9 -u 3 3< /dev/zero'
boundary "поток через фильтр"         'yes | grep y | read x'

echo "== поломка стража — пропуск со словом «СЛОМАН», а не отказ"
mkdir -p "$WORK/broken/no-wait-guard"
cp "$HOOK" "$WORK/broken/no-wait-guard.sh"
printf 'raise RuntimeError("проба")\n' > "$WORK/broken/no-wait-guard/guard.py"
rc="$(run 'sleep 900' "$WORK/broken/no-wait-guard.sh")"
assert "0 да" "$rc $(grep -qF 'СЛОМАН' "$WORK/out" && echo да || echo нет)" "guard.py бросает — код 0 и «СЛОМАН» (не отказ всему)"
rm -rf "$WORK/broken/no-wait-guard"
rc="$(run 'sleep 900' "$WORK/broken/no-wait-guard.sh")"
assert "0 да" "$rc $(grep -qF 'СЛОМАН' "$WORK/out" && echo да || echo нет)" "guard.py нет — код 0 и «СЛОМАН»"

echo "== мутанты guard.py — обязаны покраснеть"
# mutant <имя> <было> <стало> <команда> <ожидаемый код исходного>: мутант меняет
# исход на настоящем входе — иначе проба его не различает.
mutant() {
    local d="$WORK/m$muts"
    mkdir -p "$d/no-wait-guard" "$d/heavy-guard"
    cp "$HOOK" "$d/no-wait-guard.sh"
    cp "$HOOK_DIR/heavy-guard/guard.py" "$d/heavy-guard/guard.py"
    if ! python3 - "$GUARD" "$d/no-wait-guard/guard.py" "$2" "$3" <<'PY'
import sys
src, dst, a, b = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
if s.count(a) != 1:
    sys.exit(1)
open(dst, "w", encoding="utf-8").write(s.replace(a, b, 1))
PY
    then echo "  [FAIL] мутант «$1»: образец не найден в guard.py" >&2; fail=$((fail + 1)); muts=$((muts + 1)); return; fi
    local want got
    AGENT="${5:-}"
    want="$(run "$4")"; got="$(run "$4" "$d/no-wait-guard.sh")"
    AGENT=""
    if [ "$want" != "$got" ] && ! grep -qF 'СЛОМАН' "$WORK/out"; then
        echo "  [OK]   мутант «$1» красный: «$4» — $want → $got"; pass=$((pass + 1))
    else
        echo "  [FAIL] мутант «$1» выжил: «$4» — $want → $got" >&2; fail=$((fail + 1))
    fi
    muts=$((muts + 1))
}
mutant "ci-wait: срок за вызов не судится" 'if total > CI_WAIT_MAX:' 'if False:' "$CWS --max 700"
mutant "ci-wait: порог 900"          'CI_WAIT_MAX = 540 ' 'CI_WAIT_MAX = 900 ' "$CWS --max 700"
mutant "ci-wait: цикл не судится"    'if n.loop and len(self.ciw) > mark:' 'if False:' "while true; do $CWS --max 540; done"
mutant "ci-wait: цепочка не суммируется" 'self.frames[-1] += got' 'self.frames[-1] = max(self.frames[-1], got)' "$CWS --max 540 && $CWS --max 540"
mutant "ci-wait: timeout не ограничивает" 'got = min(got, tmo)' 'got = got' "timeout 300 bash -c '$CWS --max 540; $CWS --max 540'"
mutant "ci-wait: фон судится"        'own = None if ctx["bg"] or det else ci_wait_call(' 'own = ci_wait_call(' "$CWS --max 540 > l 2>&1 & $CWS --max 540"
mutant "ci-wait: путь в данных — запуск" 'if names_ci_wait(argv[0], civars):' 'if any(names_ci_wait(w, civars) for w in argv):' "for i in 1 2; do grep -c -- --max /ws/scripts/ci-state/ci-wait.sh; done"
mutant "ci-wait: bash -n — запуск"   'if base not in SHELLS or noexec(argv[1:]):' 'if base not in SHELLS:' "bash -n /ws/scripts/ci-state/ci-wait.sh && $CWS --max 540"
mutant "ci-wait: рецепт не узнан"     'if cmd is not None and VAR_REF.match(plain(cmd)) and any(' 'if False and any(' "$RCP --max 700 ) > /ws/tmp/wave-9/ci-0.md 2>&1"
mutant "ci-wait: переменная не узнана" 'return bool(m and m.group(1) in civars)' 'return False' "CW=/ws/scripts/ci-state/ci-wait.sh; while :; do bash \"\$CW\" PRO-Robotech/kacho 7 $H40 --max 540; done"
mutant "ci-wait: source не узнан"     'if base in (".", "source"):' 'if False:' "for i in 1 2; do . /ws/scripts/ci-state/ci-wait.sh PRO-Robotech/kacho 7 $H40 --max 60; done"
mutant "ci-wait: первый --max"        'v = vals[-1]' 'v = vals[0]' "$CWS --max 100 --max 900"
mutant "ci-wait: цикл под меткой снят"  '% (self.ciw[mark], n.loop), None)' '% (self.ciw[mark], n.loop), ctx["tmo"])' "timeout 500 bash -c 'while :; do $CWS --max 100; done' # no-wait-exempt ci-watcher 9m"
mutant "ci-wait: не вычислимое — ноль" 'else float("inf")' 'else 0.0' "$CWS --max \"\$M\""
mutant "ci-wait: условие цикла — вне цикла" 'm = re.match(r"^\s*(\S+)\s+", seg)' 'm = None' "while [ \"\$($CWS --max 540)\" != ok ]; do :; done"
mutant "ci-wait: ветка then теряет подстановку" 'm = re.match(r"^\s*(\S+)\s+", seg)' 'm = None' "if true; then x=\$($CWS --max 900); fi"
mutant "ci-wait: заголовок for — в цикле" 'if n.loop in ("for", "select") and kids:' 'if False and kids:' "for x in \$($CWS --max 540); do echo \"\$x\"; done"
mutant "ci-wait: хвост < <(…) теряется" 'node.substs += [t[1] for t in self.t[at:self.i]]' 'pass' "while read -r l; do :; done < <($CWS --max 900)"
mutant "ci-wait: подстановка фона судится" 'self.text(s, dict(ctx, bg=bg))' 'self.text(s, dict(ctx, bg=ctx["bg"]))' "echo \"\$($CWS --max 540)\" > l 2>&1 & $CWS --max 540"
mutant "цикл не судится"            'loop=ctx["loop"] or (n.loop in ("while", "until"))' 'loop=ctx["loop"]' 'until test -f x; do sleep 5; done'
mutant "& не отсоединяет"           'bg = ctx["bg"] or n.bg' 'bg = ctx["bg"]' 'setsid nohup timeout 3600 go test ./... > l 2>&1 &'
mutant "for не судится"             'if n.loop in ("for", "select") and not bg' 'if False and not bg' 'for i in $(seq 60); do sleep 10; done'
mutant "for: невычислимое — ноль"   'return None if per is None or cnt is None else cnt * per' 'return 0.0 if per is None or cnt is None else cnt * per' 'for i in $(seq 60); do sleep 10; done'
mutant "for: порог 600"             'FOR_MAX = 300 ' 'FOR_MAX = 600 ' 'for i in a b c d e f g h i j; do sleep 30; done'
mutant "for: итерации не множатся"  'else cnt * per' 'else per' 'for i in a b c d e f g h i j; do sleep 30; done'
mutant "for: \$ в заголовке считан"  '|__SUBST__", hdr):' '|__SUBST__", ""):' 'for i in $X; do sleep 1; done'
mutant "for: вложенный не множится" 'd = self.for_total(k)' 'd = 0.0' 'for i in a b c; do for j in 1 2 3 4 5 6 7 8 9 10; do sleep 10; done; done'
mutant "for: timeout не ограничивает" 'bounded = ctx["tmo"] is not None and ctx["tmo"] < FOR_MAX' 'bounded = False' 'timeout 60 bash -c "for i in \$(seq 9); do sleep 5; done"'
mutant "тело bash -c с меткой \$"   'text = text.replace(hg.SQ, "$").replace(hg.DQ, "$")' 'pass' 'bash -c "for i in \$(seq 60); do sleep 10; done"'
mutant "wait после & пропущен"      'if base == "wait" and not bg and ctx.get("launched"):' 'if False:' 'make test > l 2>&1 & wait'
mutant "wait без & — отказ"         'and not bg and ctx.get("launched"):' 'and not bg:' 'wait 4242'
mutant "& в группе не виден"        'return n.bg or any(self.has_bg(k) for k in n.kids)' 'return n.bg' '{ make a & make b; }; wait'
mutant "порог sleep 600"            'SLEEP_MAX = 300 ' 'SLEEP_MAX = 600 ' 'sleep 300'
mutant "порог timeout 3600"         'TIMEOUT_MAX = 600 ' 'TIMEOUT_MAX = 3600 ' 'timeout 600 go test ./...'
mutant "flock без -w пропущен"      'if not nb and (w is None or w >= FLOCK_MAX):' 'if not nb and (w is not None and w >= FLOCK_MAX):' 'flock /tmp/l go test ./...'
mutant "tail --pid не судится"      'pid = any(a == "--pid" or a.startswith("--pid=") for a in args)' 'pid = False' 'tail --pid=1 -n0 log'
mutant "gh run watch пропущен"      'if sub[:2] == ["run", "watch"] or' 'if False or' 'gh run watch 1'
mutant "bash -c не разбирается"     '                self.text(cmd, dict(ctx, bg=bg, tmo=bound))' '                pass' 'bash -c "until x; do sleep 1; done"'
mutant "heredoc в конвейер не судится" 'for seg in line.split("|"):' 'for seg in line.split("|")[:1]:' $'cat <<EOF | bash\nwhile :; do sleep 1; done\nEOF'
mutant "подстановка не судится"     '            self.text(s, dict(ctx, bg=bg))' '            pass' 'x=$(sleep 900)'
mutant "метка без timeout"          'left = [f for f in j.found if f.bound is None or f.bound > limit]' 'left = []' 'gh run watch 1 # no-wait-exempt ci-watcher 9m'
mutant "метка любого агента"        '    if agent_type and agent_type != "ci-watcher":' '    if False:' 'timeout 500 gh run watch 1 # no-wait-exempt ci-watcher 9m' go-implementer
mutant "метка сверх 9 мин"          'if mins > EXEMPT_MAX_MIN or mins < 1:' 'if mins < 1:' 'timeout 500 gh run watch 1 # no-wait-exempt ci-watcher 10m'
mutant "sudo не снимается"          '        if base == "sudo":' '        if False:' 'sudo sleep 900'
mutant "флаг sudo без значения"    'i += 2 if argv[i] in SUDO_ARG else 1' 'i += 1' 'sudo -u root sleep 900'
mutant "чтение /dev/zero не судится" '            if (own in BUSY_DEV) if own is not None else ctx.get("busy"):' '            if False:' 'read -t 5 < /dev/zero'
mutant "yes | не судится"           '    return base == "yes" or' '    return False and' 'yes | read -t 5 x'
mutant "редирект цикла не виден"    '        src = stdin_source(n.redir) if n.redir else None' '        src = None' 'while read -t 1 l; do :; done < /dev/zero'
mutant "свой < не перекрывает"      '            if (own in BUSY_DEV) if own is not None else ctx.get("busy"):' '            if own in BUSY_DEV or ctx.get("busy"):' 'while read -r x < f; do :; done < /dev/zero'
mutant "busy-read под timeout снят" '                self.add("busy-read", shown, None)' '                self.add("busy-read", shown, bound)' 'timeout 500 read -t 5 < /dev/zero # no-wait-exempt ci-watcher 9m'
mutant "nohup отсоединяет"          '        if base in ("nohup", "nice",' '        if base == "nohup":
            detached = True
        if base in ("nohup", "nice",' 'nohup timeout 3600 go test ./... > l 2>&1'

echo "[CENSUS] no-wait-guard: утверждений $((pass + fail)), сошлось $pass, разошлось $fail; отказов проверено $denied, пропусков $passed, мутантов $muts; граница (не ловится, заявлено в шапке) $bound"
[ "$fail" -eq 0 ]
