#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# detach-inject.sh — доказательство scripts/detach.sh ИСПОЛНЕНИЕМ (ws#1225): каждый исход
# status подаётся настоящим шагом, рядом — законный близнец; мутанты detach.sh (по одной
# правке) обязаны уронить свою пробу. Страж no-wait-guard судится настоящим входом
# PreToolUse: start и status он пропускает, цикл дочитки — отказ.
# Каталог шагов — свой временный; процессы шагов снимаются по группе на выходе (и на падении).
# Коды: 0 — всё сошлось, мутанты убиты; 1 — нет; 2 — нет setsid или python3 (вердикта нет).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
D_REAL="$HERE/detach.sh"; D="$D_REAL"
GUARD="$(cd "$HERE/.." && pwd)/.claude/hooks/no-wait-guard/guard.py"
for t in setsid python3 git; do command -v "$t" > /dev/null 2>&1 || { echo "[VOID] нет $t" >&2; exit 2; }; done
W="$(mktemp -d)"; W="$(cd "$W" && pwd -P)"
PGS=()
# shellcheck disable=SC2154
trap '_rc=$?; rm -rf "$W" 2>/dev/null || rm -rf "$W" || echo "ПРЕДУПРЕЖДЕНИЕ: временный каталог $W не снят; код проверки $_rc сохранён" >&2; exit $_rc' EXIT
# Шаги пробы снимаются группой (setsid — своя группа) в конце; долгий шаг (sleep 30) снят в своём случае.
reap_steps() { local p; for p in "${PGS[@]}"; do kill -- "-$p" 2>/dev/null; done; }

pass=0; fail=0
assert() {
    if [ "$1" = "$2" ]; then echo "  [OK]   $3"; pass=$((pass + 1))
    else echo "  [FAIL] $3 — ожидалось «$1», получено «$2»" >&2; fail=$((fail + 1)); fi
}
# st <каталог> <команда…> — start; код start — в SRC, вывод — в OUT, путь .rc — в RCF;
# pid шага — в PGS (снимается группой на выходе). Без $(…): глобальные остаются в оболочке пробы.
OUT=""; RCF=""; SRC=""
st() {
    local dir="$1" pid; shift
    bash "$D" start "$dir" -- "$@" > "$W/start.out" 2>&1; SRC=$?
    OUT="$(cat "$W/start.out")"
    RCF="$(sed -n 's/^идёт: pid [0-9]*; журнал [^;]*; rc \([^;]*\);.*/\1/p' "$W/start.out")"
    pid="$(sed -n 's/^идёт: pid \([0-9]*\);.*/\1/p' "$W/start.out")"; [ -n "$pid" ] && PGS+=("$pid")
    return 0
}
# done_rc <.rc> — дочитка исхода пробой (не агентом): до 10 с.
settle() { local _; for _ in $(seq 1 40); do [ -s "$1" ] && return 0; sleep 0.25; done; return 1; }
status() { bash "$D" status "$1" > "$W/st.out" 2>&1; echo $?; }

run_cases() {
    local rc R; R="$W/run.$RANDOM"; mkdir -p "$R"   # каждый прогон (контроль, мутант) — своё дерево
    echo "== исходы"
    st "$R/s" sh -c 'echo ok-line; exit 0'; rc=$SRC
    assert "0 да" "$rc $(grep -qE '^идёт: pid [0-9]+; журнал .*; rc .*\.rc; срок 20' <<< "$OUT" && echo да || echo нет)" "start — код 0 сразу, строка «идёт: pid; журнал; rc; срок»"
    settle "$RCF"
    assert "0 да" "$(status "$RCF") $(grep -qF 'ok-line' "$W/st.out" && echo да || echo нет)" "команда вышла 0 — status 0, хвост журнала напечатан"
    st "$R/s" sh -c 'exit 7'; settle "$RCF"
    assert "1 да" "$(status "$RCF") $(grep -qF 'исход: код 7' "$W/st.out" && echo да || echo нет)" "команда вышла 7 — status 1, код назван (не зелёное)"
    st "$R/s" sleep 30; local pid; pid="$(cat "${RCF%.rc}.pid")"
    assert "3" "$(status "$RCF")" "идёт — status 3"
    assert "3" "$(status "${RCF%.rc}.log")" "status принимает и путь журнала"
    kill -- "-$pid" 2>/dev/null; for _ in $(seq 1 20); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
    assert "2 да" "$(status "$RCF") $(grep -qF 'шаг оборван' "$W/st.out" && echo да || echo нет)" "процесс снят без .rc — status 2 «не выполнилось», не зелёное и не «идёт»"
    printf '%s\n' "$$" > "$R/s/foreign.pid"
    assert "2" "$(status "$R/s/foreign.rc")" "pid в .pid — живой ЧУЖОЙ процесс без метки шага — не «идёт» (2)"
    assert "2" "$(status "$R/s/none.rc")" "файлов шага нет — status 2"
    # ws#1242: имя «<журнал>.log.rc» (код рядом с журналом) — исход по этому имени.
    echo chain-line > "$R/s/ch.log"; echo 0 > "$R/s/ch.log.rc"
    assert "0 да" "$(status "$R/s/ch.log.rc") $(grep -qF 'chain-line' "$W/st.out" && echo да || echo нет)" "status <журнал>.log.rc с кодом 0 — 0, хвост журнала"
    assert "0" "$(status "$R/s/ch.log")" "status <журнал>.log при <журнал>.log.rc — тот же исход"
    echo 4 > "$R/s/cf.log.rc"; : > "$R/s/cf.log"
    assert "1 да" "$(status "$R/s/cf.log.rc") $(grep -qF 'исход: код 4' "$W/st.out" && echo да || echo нет)" "status <журнал>.log.rc с кодом 4 — 1, код назван"
    assert "2" "$(status "$R/s/gone.log.rc")" "близнец: <журнал>.log.rc нет и процесса нет — 2 «не выполнилось»"
    # Внешняя цепочка (без .pid и метки): живость — по журналу (check-verifier ws#1242).
    : > "$R/s/ext.log"
    # Один процесс (exec sleep), лидер своей сессии: pid — из файла, группа снимается целиком.
    setsid bash -c 'echo $$ > "$1"; exec >> "$0"; echo ext-line; exec sleep 30' "$R/s/ext.log" "$R/s/ext.holder" < /dev/null &
    for _ in $(seq 1 20); do grep -q ext-line "$R/s/ext.log" 2>/dev/null && break; sleep 0.1; done
    local ext; ext="$(cat "$R/s/ext.holder" 2>/dev/null)"; [ -n "$ext" ] && PGS+=("$ext")
    assert "3 да" "$(status "$R/s/ext.log.rc") $(grep -qF 'журнал держит pid' "$W/st.out" && echo да || echo нет)" "живая внешняя цепочка держит журнал — 3 «идёт», не «оборван»"
    kill -- "-$ext" 2>/dev/null; for _ in $(seq 1 20); do kill -0 "$ext" 2>/dev/null || break; sleep 0.1; done
    assert "4 нет" "$(status "$R/s/ext.log.rc") $(grep -qF 'оборван' "$W/st.out" && echo да || echo нет)" "внешний журнал никто не держит, .rc нет — 4 «не судим как идущий», слова «оборван» нет"
    echo "== код последней команды строки оболочки"
    st "$R/s" sh -c 'false; echo "rc=$?"'
    assert "64 да" "$SRC $(grep -qF 'в .rc лёг бы код echo' <<< "$OUT" && echo да || echo нет)" "«…; echo rc=\$?» — 64: код echo в .rc не пишется (урок ws#1242)"
    st "$R/s" bash -c 'false; printf "x\n"  ;  '; assert "64" "$SRC" "строка, кончающаяся printf и «;» с пробелами, — 64"
    st "$R/s" sh -c 'false; a=$?; echo "rc=$a"; exit $a'; settle "$RCF"
    assert "0 1" "$SRC $(status "$RCF")" "близнец: код сохранён и возвращён exit — запуск 0, status 1 (код 1 прогона)"
    printf 'shift; "$@"\n' > "$R/s/chain.sh"
    st "$R/s" bash "$R/s/chain.sh" -- sh -c 'printf "%s" x > /dev/null'; settle "$RCF"
    assert "0 0" "$SRC $(status "$RCF")" "близнец: «-c» — довод шага цепочки, не сама команда — запускается (код — цепочки)"
    st "$R/s" echo hi; settle "$RCF"
    assert "0 0" "$SRC $(status "$RCF")" "близнец: сама команда echo (не строка оболочки) — запускается"
    echo "== уникальность и каталог"
    # Два запуска той же команды РАЗОМ (в одну секунду): имена различает pid вызова.
    bash "$D" start "$R/u" -- sh -c 'exit 0' > "$R/u1" 2>&1 & local j1=$!
    bash "$D" start "$R/u" -- sh -c 'exit 0' > "$R/u2" 2>&1 & local j2=$!
    wait "$j1"; wait "$j2"
    local a b; a="$(sed -n 's/^идёт: .*; rc \([^;]*\);.*/\1/p' "$R/u1")"; b="$(sed -n 's/^идёт: .*; rc \([^;]*\);.*/\1/p' "$R/u2")"
    settle "$a"; settle "$b"
    assert "да 2" "$([ -n "$a" ] && [ -n "$b" ] && [ "$a" != "$b" ] && echo да || echo нет) $(ls "$R/u"/*.rc 2>/dev/null | wc -l)" "два запуска той же команды разом — разные журнал и .rc, оба исхода записаны"
    git init -q "$R/repo"
    st "$R/repo/steps" true; assert "64" "$SRC" "каталог внутри рабочего дерева git без игнора — 64 (файлы шага сделали бы копию грязной)"
    printf 'steps/\n' > "$R/repo/.gitignore"
    st "$R/repo/steps" true; assert "0" "$SRC" "близнец: тот же каталог, игнорируемый git, — 0"
    st "$R/s"; assert "64" "$SRC" "без «-- <команда>» — 64"
}

grc() {
    python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"agent_type":"go-implementer"}))' "$1" \
        | python3 "$GUARD" > "$W/g.out" 2>&1
    echo $?
}
run_cases
echo "== страж no-wait-guard"
assert "0" "$(grc "bash \$WS/scripts/detach.sh start \$WS/tmp/1225 -- bash \$WS/scripts/heavy-slot.sh ci-local -- env KACHO_TASK=1225 git push origin HEAD:refs/heads/1225-x")" "страж пропускает start"
assert "0" "$(grc "bash \$WS/scripts/detach.sh status \$WS/tmp/1225/x.rc")" "страж пропускает status"
assert "2" "$(grc "until bash \$WS/scripts/detach.sh status \$WS/tmp/1225/x.rc; do sleep 30; done")" "страж отказывает циклу дочитки агентом"
assert "да" "$(grc 'gh run watch 1' > /dev/null; grep -qF 'scripts/detach.sh start' "$W/g.out" && echo да || echo нет)" "текст отказа стража называет detach.sh как правильную форму"

echo "== мутанты"
muts=0; survived=0
mutant() {  # <имя> <было> <стало>
    local m="$W/mut/detach.sh"; mkdir -p "$W/mut"
    python3 - "$D_REAL" "$m" "$2" "$3" <<'PY' || { echo "  [VOID] мутант $1: правка не легла"; survived=$((survived + 1)); return; }
import sys
s, d, a, b = sys.argv[1:5]
t = open(s, encoding="utf-8").read()
if t.count(a) != 1:
    sys.exit(1)
open(d, "w", encoding="utf-8").write(t.replace(a, b))
PY
    muts=$((muts + 1))
    local before=$fail
    D="$m"; run_cases > "$W/mut.out" 2>&1; D="$D_REAL"
    if [ "$fail" -gt "$before" ]; then echo "  [убит] $1 — $(grep -m1 -F '[FAIL]' "$W/mut.out" | sed 's/^ *\[FAIL\] //' | cut -c1-160)"
    else echo "  [ВЫЖИЛ] $1"; survived=$((survived + 1)); fi
    fail=$before
}
mutant tag-ignored '[ "$e" = "DETACH_TAG=$2" ] && return 0' '[ -n "$e" ] && return 0'
mutant nonzero-as-green '[ "$code" -eq 0 ] && exit 0
        exit 1' 'exit 0'
mutant dead-as-running '        echo "идёт: pid $pid; журнал $logf"
        exit 3
    fi' '        echo "идёт: pid $pid; журнал $logf"
        exit 3
    fi
    exit 3'
mutant log-rc-name '        *.log.rc) rcf="$2"; logf="${2%.rc}" ;;
' ''
mutant ext-dead-as-broken '        echo "не судим как идущий: внешний шаг без .pid и метки, журнал $logf не держит ни один процесс — .rc нет; исход — status позже либо по журналу"
        exit 4' '        echo "оборван"; exit 2'
mutant ext-holder-ignored '        if [ -n "$holder" ]; then echo' '        if false; then echo'
mutant inner-c-judged '        [ "$prev" != -c ] && [ "$prev" != "" ] && [ "${prev:0:1}" != - ] && [ "$prev" != "$1" ] && break
' ''
mutant trailing-echo-allowed '            if [[ "$last" =~ ^(echo|printf)([[:space:]]|$) ]]; then' '            if false; then'
mutant name-not-unique '-$$-$(printf' '-$(printf'
mutant tree-unchecked '= true ] && [ "$ign" = 0 ]; then' '= true ] && false; then'

reap_steps
echo "[CENSUS] detach: утверждений $((pass + fail)), сошлось $pass, разошлось $fail; мутантов $muts, выжило $survived"
[ "$fail" -eq 0 ] && [ "$survived" -eq 0 ]
