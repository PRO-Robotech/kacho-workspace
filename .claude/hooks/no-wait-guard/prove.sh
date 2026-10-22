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
#   · поломка стража — пропуск со словом «СЛОМАН», а не отказ всему;
#   · (ws#1159) снятие процессов по шаблону — отказ кодом 2 с подсказкой «снимай по
#     pid — по записанному pid-файлу», без текста «Не жди» (предмет другой); снятие по
#     pid, группе и pid-файлу — пропуск; метка ci-watcher снятие не снимает.
# Коды: 0 — все утверждения сошлись; 1 — нет; 2 — нет python3 (вердикта нет).
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$HOOK_DIR/no-wait-guard.sh"
GUARD="$HOOK_DIR/no-wait-guard/guard.py"
command -v python3 > /dev/null 2>&1 || { echo "[VOID] no-wait-guard: нет python3" >&2; exit 2; }
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0; denied=0; passed=0; bound=0; muts=0; kdenied=0
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
    fix="нет"; grep -qF "setsid env --default-signal=PIPE sh -c '<команда>; echo \$? > <журнал>.rc' > <журнал> 2>&1 & echo \$! > <pid-файл>" "$WORK/out" && ! grep -qF 'setsid nohup <команда>' "$WORK/out" \
        && grep -qF '/scripts/detach.sh start <каталог> -- <команда>' "$WORK/out" && fix="да"
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
# ws#1344: агент правок kio#3 ждал CI `flock -w 290` на своём замке — 6 вызовов за 20 мин; предел 60 с
denies "$FLOCK" 'D=/s/ciwait; flock -w 290 $D/head.lock true; echo lock=$?'
denies "$FLOCK" 'flock -w 61 /tmp/l true'
denies "$FLOCK" 'flock -w61 /tmp/l true'
denies "$FLOCK" 'flock --wait 90 /tmp/l true'
denies "$FLOCK" 'flock --timeout 120 /tmp/l true'
denies "$FLOCK" 'flock --timeout=240 /tmp/l true'
denies "$FLOCK" 'flock -w 60.5 /tmp/l true'
denies "$FLOCK" 'timeout 120 flock -w 290 /tmp/l true'
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
passes 'flock -w 30 /tmp/l true'
passes 'flock --timeout=60 /tmp/l true'
passes 'flock -n -w 290 /tmp/l true'
passes 'flock --wait 60 /tmp/l true'
passes 'flock --timeout 30 /tmp/l true'
passes 'flock -w60 /tmp/l true'
# общий предел внешнего timeout ≤ 60 с ограничивает и ожидание замка (приёмка ws#1344)
passes 'timeout 50 flock -w 290 /tmp/l true'
passes 'timeout 60 flock /tmp/l true'
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
# ws#1279: тело heredoc с кавыченным ограничителем к не-оболочке — данные
passes $'cat <<\'EOF\' > a.md\nwhile true; do sleep 5; done\nEOF'
passes $'python3 - <<\'PY\'\nprint("""until x; do sleep 5; done""")\nPY'
passes $'python3 - <<\'OUT\'\ns = """\ncat <<\'PY\'\nPY\nwhile :; do sleep 5; done\n"""\nOUT'
passes '/ws/scripts/heavy-slot.sh go-race -- go test -race ./...'
passes '/ws/scripts/heavy-slot.sh --wait 300 go-race -- go test -race ./...'
passes 'bash /ws/scripts/detach.sh start /ws/tmp/1225 -- bash /ws/scripts/heavy-slot.sh ci-local -- git push origin HEAD:refs/heads/1225-x'
passes 'bash /ws/scripts/detach.sh status /ws/tmp/1225/a.rc'

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

echo "== снятие по шаблону (ws#1159) — отказ с подсказкой «снимай по pid»"
# kills <команда> — отказ 2; класс назван; подсказка «снимай по pid — по записанному
# pid-файлу»; текста ожидания нет: предмет отказа — снятие, а не ожидание.
kills() {
    local rc named hint other
    rc="$(run "$1")"
    named="нет"; grep -qF 'отказ — снятие процессов по шаблону' "$WORK/out" && grep -qF 'снятие процессов не по pid' "$WORK/out" && named="да"
    hint="нет"; grep -qF 'подсказка: снимай по pid — по записанному pid-файлу: `kill $(cat <pid-файл>)`' "$WORK/out" && hint="да"
    other="нет"; grep -qF 'Правило «Не жди»' "$WORK/out" && other="да"
    assert "2 да да нет" "$rc $named $hint $other" "отказ (снятие): $(printf '%s' "$1" | tr '\n' ' ')"
    kdenied=$((kdenied + 1))
}
kills 'pkill -f x'
kills 'pkill newman'
kills 'killall node'
kills 'pkill -9 -f "heavy-slot"'
kills 'pkill -u dk'
kills 'pkill -P 1'
kills 'pkill -P 4242 -f x'
kills 'killall5 -9'
kills 'sudo killall -9 node'
kills 'fuser -k 8080/tcp'
kills 'kill -9 -1'
kills 'kill -- -1'
kills 'kill node'
kills 'kill $(pgrep -f newman)'
kills 'kill -TERM `pidof node`'
kills 'kill $(lsof -t -i :8080)'
kills 'pgrep -f x | xargs kill'
kills 'pgrep -f x | xargs -r -n1 kill -9'
kills "ps aux | grep newman | awk '{print \$2}' | xargs kill"
kills 'pgrep x | while read p; do kill "$p"; done'
kills 'for p in $(pidof node); do kill -9 $p; done'
kills 'bash -c "pkill -f heavy"'
kills 'setsid -f pkill x'
kills 'pkill -f x > /dev/null 2>&1 &'
kills 'timeout 5 pkill -f x'
kills 'cd /tmp && pkill -f x || true'
# приёмка ws#1159, круг 1: класс «вход xargs/read/цикла — выборщик», число по значению,
# подстановка в id-значении, флаги обёрток без значения
kills 'xargs kill < <(pgrep x)'
kills 'while read p; do kill $p; done < <(pgrep x)'
kills 'xargs kill <<< "$(pgrep x)"'
kills 'xargs kill <<< $(pgrep x)'
kills 'kill -9 -01'
kills 'kill -s KILL -01'
kills 'pkill -P 01'
kills 'pkill -P $(pgrep x)'
kills 'pkill -g $(pgrep -f x)'
kills 'time -p pkill -f x'
kills 'command -p pkill -f x'
rc="$(run 'timeout 500 pkill -f x # no-wait-exempt ci-watcher 9m')"
assert "2 да" "$rc $(grep -qF 'отказ — снятие процессов по шаблону' "$WORK/out" && echo да || echo нет)" "снятие — метка ci-watcher его не снимает"
AGENT=ci-watcher
rc="$(run 'timeout 500 killall node # no-wait-exempt ci-watcher 9m')"
assert 2 "$rc" "снятие — и у самого ci-watcher метка его не снимает"
AGENT=""
rc="$(run 'pkill -f x; sleep 900')"
assert "2 да да" "$rc $(grep -qF 'снятие процессов по шаблону' "$WORK/out" && echo да || echo нет) $(grep -qF 'Правило «Не жди»' "$WORK/out" && echo да || echo нет)" "снятие и ожидание в одной строке — оба предмета названы"
kdenied=$((kdenied + 3))

echo "== снятие по pid, группе, pid-файлу — законные близнецы, пропуск без слова"
passes 'kill 4242'
passes 'kill -- -4242'
passes 'kill -TERM -- -4242'
passes 'kill -9 4242 4243'
passes 'kill -s TERM 4242'
passes 'kill -1 4242'
passes 'kill $(cat /tmp/run.pid)'
passes 'kill -TERM -- -"$(cat /tmp/run.pgid)"'
passes 'kill "$pid"'
passes 'kill -- -"$pg"'
passes 'kill %1'
passes 'kill -0 $(pgrep -f x)'
passes 'kill -TERM -- -$(ps -o pgid= -p "$pid" | tr -d " ")'
passes 'cat /tmp/run.pid | xargs kill'
passes 'pkill -F /tmp/run.pid'
passes 'pkill -TERM -P $$'
passes 'pkill -USR1 -P 4242'
passes 'pkill -g 0'
passes 'pkill -0 newman'
passes 'pgrep -fa newman'
passes 'pidof node'
passes 'ps -o pid,args -p 4242'
passes 'fuser 8080/tcp'
passes 'echo "pkill -f x"; grep -n killall f'
passes 'git commit -m "pkill -f x и killall node — запрещены"'
# законные близнецы форм приёмки — та же запись, источник или значение по id
passes 'kill 12345'
passes 'kill -0 $pid'
passes 'pkill -F run.pid'
passes 'pgrep -F f | xargs kill'
passes 'xargs kill < run.pid'
passes 'while read p; do kill $p; done < run.pid'
passes 'xargs kill <<< "$(cat run.pid)"'
passes 'xargs kill <<< $(cat run.pid)'
passes 'kill -9 -0101'
passes 'kill -s KILL -0101'
passes 'pkill -P 0101'
passes 'pkill -P $(cat run.pid)'
passes 'pkill -g $(cat run.pgid)'
passes 'time -p kill 12345'
passes 'command -p kill 12345'

echo "== граница (BOUNDARY шапки guard.py) — известно, не ловится"
boundary "ожидание внутри скрипта"     'bash ./wait-for-ci.sh'
boundary "wait без фонового запуска"   'wait 4242'
boundary "eval: строка не разбирается" 'eval "sleep 900"'
boundary "xargs: argv из входа"       'echo 900 | xargs sleep'
boundary "иной интерпретатор"         'python3 -c "import time; time.sleep(900)"'
boundary "источник — дескриптор"      'exec 3< /dev/zero; read -t 9 -u 3'
boundary "свой редирект на дескриптор"  'read -t 9 -u 3 3< /dev/zero'
boundary "поток через фильтр"         'yes | grep y | read x'
boundary "снятие: адресат через переменную другой команды" 'p=$(pgrep x); kill $p'
boundary "снятие: адресат через файл"  'pgrep x > f; kill $(cat f)'
boundary "снятие: иной интерпретатор"  'python3 -c "import os; os.kill(1, 9)"'
boundary "снятие: eval"                'eval "pkill -f x"'
boundary "снятие: переменная-команда"  'K=pkill; $K -f x'
boundary "снятие: su -c"               "su -c 'pkill -f x' dk"
boundary "снятие: doas"                'doas pkill -f x'
boundary "снятие: runuser"             'runuser -u dk -- pkill -f x'
boundary "снятие: nsenter"             'nsenter -t 1 -m pkill -f x'
boundary "снятие: unshare"             'unshare -r pkill -f x'
boundary "снятие: systemd-run"         'systemd-run --user pkill -f x'
boundary "снятие: script -qc"          "script -qc 'pkill -f x' /dev/null"
boundary "снятие: strace"              'strace -f pkill -f x'
boundary "снятие: find -exec"          'find /proc -maxdepth 1 -name 1 -exec kill {} \;'
boundary "снятие: env -S"              "env -S 'pkill -f x'"

echo "== heredoc, закрытый вложенным ограничителем, — отказ называет причину (ws#1279)"
# Вход урока 2026-10-19: тело `python3 - <<'PY'` несло текст с вложенным `<<'PY'`; оболочка
# закрыла внешний heredoc первой строкой «PY», и цикл после неё — исполняемая часть.
EARLY=$'python3 - <<\'PY\'\ns = """\ncat <<\'PY\'\nPY\nwhile :; do sleep 5; done\n"""\nPY'
early() {  # <страж> — «код названо-причины номера-строк»
    local rc named lines
    rc="$(run "$EARLY" "$1")"
    named="нет"; grep -qF 'heredoc закрыт раньше задуманного: тело «PY» (строка 1)' "$WORK/out" && named="да"
    lines="нет"; grep -qF '(строка 3); оболочка закрывает внешний первой строкой «PY» (строка 4)' "$WORK/out" && lines="да"
    echo "$rc $named $lines"
}
assert "2 да да" "$(early "$HOOK")" "вложенный ограничитель того же имени: отказ, причина и строки названы"
rc="$(run $'bash <<EOF\nwhile :; do sleep 1; done\nEOF')"
assert "2 нет" "$rc $(grep -qF 'heredoc закрыт раньше' "$WORK/out" && echo да || echo нет)" "близнец: цикл в теле, поданном оболочке, — отказ без строки о закрытии"
d="$WORK/early"; mkdir -p "$d/no-wait-guard" "$d/heavy-guard"
cp "$HOOK" "$d/no-wait-guard.sh"; cp "$HOOK_DIR/heavy-guard/guard.py" "$d/heavy-guard/guard.py"
if python3 - "$GUARD" "$d/no-wait-guard/guard.py" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
a = "    e = heredoc_early_close(cmd or \"\")\n"
if s.count(a) != 1:
    sys.exit(1)
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(a, "    e = None\n", 1))
PY
then assert "2 нет нет" "$(early "$d/no-wait-guard.sh")" "мутант «причина не названа»: проба выше его ловит"; muts=$((muts + 1))
else echo "  [FAIL] мутант «причина не названа»: образец не найден в guard.py" >&2; fail=$((fail + 1)); fi

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
mutant "flock без -w пропущен"      'if not nb and (eff is None or eff > FLOCK_MAX):' 'if not nb and (eff is not None and eff > FLOCK_MAX):' 'flock /tmp/l go test ./...'
mutant "flock: предел не проверяется" 'if not nb and (eff is None or eff > FLOCK_MAX):' 'if not nb and eff is None:' 'flock -w 290 /tmp/l true'
mutant "flock: порог 300 (до ws#1344)" 'FLOCK_MAX = 60 ' 'FLOCK_MAX = 300 ' 'flock -w 290 /tmp/l true'
mutant "flock: 60 — уже ожидание"    'eff > FLOCK_MAX):' 'eff >= FLOCK_MAX):' 'flock -w 60 /tmp/l true'
mutant "flock: --wait N раздельно не разбирается" 'if a in ("-w", "--wait", "--timeout"):' 'if a == "-w":' 'flock --wait 60 /tmp/l true'
mutant "flock: --timeout N раздельно не разбирается" 'if a in ("-w", "--wait", "--timeout"):' 'if a in ("-w", "--wait"):' 'flock --timeout 30 /tmp/l true'
mutant "flock: -wN слитно не разбирается" 'elif re.match(r"^-w\d", a):' 'elif False:' 'flock -w60 /tmp/l true'
mutant "flock: внешний timeout не ограничивает" 'eff = w if bound is None else' 'eff = w if True else' 'timeout 50 flock -w 290 /tmp/l true'
mutant "tail --pid не судится"      'pid = any(a == "--pid" or a.startswith("--pid=") for a in args)' 'pid = False' 'tail --pid=1 -n0 log'
mutant "gh run watch пропущен"      'if sub[:2] == ["run", "watch"] or' 'if False or' 'gh run watch 1'
mutant "bash -c не разбирается"     '                self.text(cmd, dict(ctx, bg=bg, tmo=bound))' '                pass' 'bash -c "until x; do sleep 1; done"'
mutant "heredoc в конвейер не судится" 'for seg in line.split("|"):' 'for seg in line.split("|")[:1]:' $'cat <<EOF | bash\nwhile :; do sleep 1; done\nEOF'
mutant "подстановка не судится"     '            self.text(s, dict(ctx, bg=ctx["bg"]))' '            pass' 'x=$(sleep 900)'
mutant "метка без timeout"          'left = [f for f in waits if f.bound is None or f.bound > limit]' 'left = []' 'gh run watch 1 # no-wait-exempt ci-watcher 9m'
mutant "метка любого агента"        '    if agent_type and agent_type != "ci-watcher":' '    if False:' 'timeout 500 gh run watch 1 # no-wait-exempt ci-watcher 9m' go-implementer
mutant "метка сверх 9 мин"          'if mins > EXEMPT_MAX_MIN or mins < 1:' 'if mins < 1:' 'timeout 500 gh run watch 1 # no-wait-exempt ci-watcher 10m'
mutant "sudo не снимается"          '        if base == "sudo":' '        if False:' 'sudo sleep 900'
mutant "флаг sudo без значения"    'i += 2 if argv[i] in SUDO_ARG else 1' 'i += 1' 'sudo -u root sleep 900'
mutant "чтение /dev/zero не судится" '            if (own in BUSY_DEV) if own is not None else ctx.get("busy"):' '            if False:' 'read -t 5 < /dev/zero'
mutant "yes | не судится"           '    return base == "yes" or' '    return False and' 'yes | read -t 5 x'
mutant "редирект цикла не виден"    '        src = stdin_source(n.redir) if n.redir else None' '        src = None' 'while read -t 1 l; do :; done < /dev/zero'
mutant "свой < не перекрывает"      '            if (own in BUSY_DEV) if own is not None else ctx.get("busy"):' '            if own in BUSY_DEV or ctx.get("busy"):' 'while read -r x < f; do :; done < /dev/zero'
mutant "busy-read под timeout снят" '                self.add("busy-read", shown, None)' '                self.add("busy-read", shown, bound)' 'timeout 500 read -t 5 < /dev/zero # no-wait-exempt ci-watcher 9m'
mutant "страж пропускает killall"   '        if base in KILL_BY_MATCH:' '        if False:' 'killall node'
mutant "pkill -f снят из отказа"     '        if base == "pkill":' '        if False:' 'pkill -f x'
mutant "образец при id-выборе пропущен" '    return (pattern or attr or parent_all or not ids), zero' '    return (attr or parent_all or not ids), zero' 'pkill -P 4242 -f x'
mutant "pkill: id-выбор — тоже отказ" '    return (pattern or attr or parent_all or not ids), zero' '    return True, zero' 'pkill -F /tmp/run.pid'
mutant "pkill -P 1 законен"          '    parent_all = any(n in ("-P", "--parent") and any(num_is(x, 1) for x in v.split(",")) for n, v in ids)' '    parent_all = False' 'pkill -P 1'
mutant "kill \$(pgrep) не судится"   '                       or ("__SUBST__" in t and from_sel)                 # kill $(pgrep …)' '' 'kill $(pgrep -f newman)'
mutant "kill -1 законен"             '                bad = (num_is(t, -1)                                     # все процессы uid (-01 = -1)' '                bad = (False' 'kill -9 -1'
mutant "xargs не передаёт адресаты"  '            if not targets and ctx.get("xargs") and ctx.get("sel"):   # pgrep … | xargs kill' '            if False:' 'pgrep -f x | xargs kill'
mutant "конвейер не несёт выборщик"  '        if feed_selects(n) or own_in or head_in' '        if own_in or head_in' 'pgrep x | while read p; do kill "$p"; done'
mutant "ps без id — не выборщик"     '    if base == "ps":
        return ps_by_pattern(args)' '    if base == "ps":
        return False' "ps aux | grep newman | awk '{print \$2}' | xargs kill"
mutant "ps с -p — выборщик"          '            if got[0] in PS_ID_OPTS:
                return False' '            if False:
                return False' 'kill -TERM -- -$(ps -o pgid= -p "$pid" | tr -d " ")'
mutant "сигнал 0 доставляет"         '            if zero:
                return True
            from_sel' '            from_sel' 'kill -0 $(pgrep -f x)'
mutant "fuser -k пропущен"           '        if base == "fuser":' '        if False:' 'fuser -k 8080/tcp'
mutant "метка снимает снятие"        '    kills = [f for f in j.found if f.cls in KILL_CLASSES]' '    kills = []' 'timeout 500 pkill -f x # no-wait-exempt ci-watcher 9m'
mutant "фон снимает снятие"          '        if self.kill_form(base, args, substs, ctx, shown):' '        if not bg and self.kill_form(base, args, substs, ctx, shown):' 'pkill -f x > /dev/null 2>&1 &'
mutant "вход < <(…) не судится"     '        own_in = stdin_selects(n.redir, n.redir_substs) if n.kind == "group" else stdin_selects(n.text, n.substs)' '        own_in = False' 'xargs kill < <(pgrep x)'
mutant "хвост цикла < <(…) потерян"   '            while self.peek()[0] == "subst" and self.past_substs() == ("kw", closer):' '            while False:' 'while read p; do kill $p; done < <(pgrep x)'
mutant "here-string не источник"     '0?(<<<|<>|<)(?!<)' '0?(<>|<)(?!<)' 'xargs kill <<< "$(pgrep x)"'
mutant "here-string без кавычек не источник" $'\']?([^' $'\']([^' 'xargs kill <<< $(pgrep x)'
mutant "kill: -01 по написанию"     '                bad = (num_is(t, -1)' '                bad = (t == "-1"' 'kill -9 -01'
mutant "kill -s: -01 по написанию"  '                bad = (num_is(t, -1)' '                bad = (t == "-1"' 'kill -s KILL -01'
mutant "pkill -P 01 по написанию"   'and any(num_is(x, 1) for x in v.split(","))' 'and "1" in v.split(",")' 'pkill -P 01'
mutant "-P \$(pgrep) — id"           '                if ("__SUBST__" in val and sub_sel) or' '                if False or' 'pkill -P $(pgrep x)'
mutant "-g \$(pgrep) — id"           '                if ("__SUBST__" in val and sub_sel) or' '                if False or' 'pkill -g $(pgrep -f x)'
mutant "time -p съедает команду"    '"time": ("-o", "--output", "-f", "--format")' '"time": ("-o", "--output", "-f", "--format", "-p")' 'time -p pkill -f x'
mutant "command -p съедает команду" '"command": ()' '"command": ("-p",)' 'command -p pkill -f x'
mutant "nohup отсоединяет"          '        if base in ("nohup", "nice",' '        if base == "nohup":
            detached = True
        if base in ("nohup", "nice",' 'nohup timeout 3600 go test ./... > l 2>&1'

echo "[CENSUS] no-wait-guard: утверждений $((pass + fail)), сошлось $pass, разошлось $fail; отказов проверено $denied, пропусков $passed, мутантов $muts; граница (не ловится, заявлено в шапке) $bound; снятий по шаблону проверено $kdenied"
[ "$fail" -eq 0 ]
