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
#     правило «Не жди» и правильную форму (setsid nohup … > журнал, pid-файл);
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
    fix="нет"; grep -qF 'setsid nohup <команда> > <журнал> 2>&1 & echo $! > <pid-файл>' "$WORK/out" && fix="да"
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

echo "== законные близнецы той же формы — пропуск без слова"
passes 'sleep 299'
passes 'sleep 30 && gh pr checks 7'
passes 'timeout 599 go test ./...'
passes 'timeout 120 tail -f /tmp/run.log'
passes 'tail -n 50 /tmp/run.log; kill -0 4242 && echo идёт'
passes 'gh pr checks 7'
passes 'gh run view 123456 --json status,conclusion'
passes 'flock -n /tmp/l true'
passes 'flock -w 60 /tmp/l true'
passes 'setsid nohup timeout 3600 go test ./... > /tmp/run.log 2>&1 & echo $! > /tmp/run.pid'
passes 'nohup bash -c "until test -f d; do sleep 5; done" > l 2>&1 &'
passes '( while true; do sleep 5; done ) > l 2>&1 &'
passes 'setsid -f sleep 900'
passes 'while read -r l; do echo "$l"; done < f'
passes 'for i in 1 2 3; do gh pr checks 7; done'
passes 'for i in 1 2 3; do gh pr checks 7; sleep 5; done'
passes 'for i in 1 2 3 4 5 6 7 8 9; do sleep 33; done'
passes 'for i in $(seq 60); do echo "$i"; done'
passes 'for i in $(seq 60); do sleep 10; done > l 2>&1 &'
passes 'for i in 1 2 3; do sleep 200 & done'
passes 'timeout 60 bash -c "for i in \$(seq 9); do sleep 5; done"'
passes 'setsid nohup make test > l 2>&1 & echo $! > p'
passes 'bash -c "make a & make b & wait" > l 2>&1 &'
passes 'git commit -m "until x; do sleep 900; done; gh run watch"'
passes 'echo "sleep 600"; grep -n "tail --pid" f'
passes $'cat > f.sh <<EOF\nwhile :; do sleep 1; done\nEOF'
passes $'cat <<EOF | grep sleep\nwhile :; do sleep 1; done\nEOF'
passes '/ws/scripts/heavy-slot.sh go-race -- go test -race ./...'
passes '/ws/scripts/heavy-slot.sh --wait 300 go-race -- go test -race ./...'

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

echo "== граница (BOUNDARY шапки guard.py) — известно, не ловится"
boundary "ожидание внутри скрипта"     'bash ./wait-for-ci.sh'
boundary "wait без фонового запуска"   'wait 4242'

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
mutant "flock без -w пропущен"      'if not nb and (w is None or w >= FLOCK_MAX):' 'if not nb and (w is not None and w >= FLOCK_MAX):' 'flock /tmp/l go test ./...'
mutant "tail --pid не судится"      'pid = any(a == "--pid" or a.startswith("--pid=") for a in args)' 'pid = False' 'tail --pid=1 -n0 log'
mutant "gh run watch пропущен"      'if sub[:2] == ["run", "watch"] or' 'if False or' 'gh run watch 1'
mutant "bash -c не разбирается"     '                self.text(cmd, dict(ctx, bg=bg, tmo=bound))' '                pass' 'bash -c "until x; do sleep 1; done"'
mutant "heredoc в конвейер не судится" 'for seg in line.split("|"):' 'for seg in line.split("|")[:1]:' $'cat <<EOF | bash\nwhile :; do sleep 1; done\nEOF'
mutant "подстановка не судится"     '            self.text(s, dict(ctx, bg=ctx["bg"]))' '            pass' 'x=$(sleep 900)'
mutant "метка без timeout"          'left = [f for f in j.found if f.bound is None or f.bound > limit]' 'left = []' 'gh run watch 1 # no-wait-exempt ci-watcher 9m'
mutant "метка любого агента"        '    if agent_type and agent_type != "ci-watcher":' '    if False:' 'timeout 500 gh run watch 1 # no-wait-exempt ci-watcher 9m' go-implementer
mutant "метка сверх 9 мин"          'if mins > EXEMPT_MAX_MIN or mins < 1:' 'if mins < 1:' 'timeout 500 gh run watch 1 # no-wait-exempt ci-watcher 10m'
mutant "nohup отсоединяет"          '        if base in ("nohup", "nice",' '        if base == "nohup":
            detached = True
        if base in ("nohup", "nice",' 'nohup timeout 3600 go test ./... > l 2>&1'

echo "[CENSUS] no-wait-guard: утверждений $((pass + fail)), сошлось $pass, разошлось $fail; отказов проверено $denied, пропусков $passed, мутантов $muts; граница (не ловится, заявлено в шапке) $bound"
[ "$fail" -eq 0 ]
