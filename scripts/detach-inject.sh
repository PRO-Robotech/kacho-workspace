#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# detach-inject.sh — доказательство scripts/detach.sh ИСПОЛНЕНИЕМ (ws#1225): каждый исход
# status подаётся настоящим шагом, рядом — законный близнец; мутанты detach.sh (по одной
# правке) обязаны уронить свою пробу. Страж no-wait-guard судится настоящим входом
# PreToolUse: start и status он пропускает, цикл дочитки — отказ.
# Переживание перезапуска сессии (scripts/detach-launch.sh): шаг запускается ИЗНУТРИ
# одноразового scope (`systemd-run --user --scope`), scope снимается `systemctl --user stop`
# — служба шага жива и дописывает исход; близнец KACHO_DETACH_NO_SYSTEMD=1 (setsid-путь)
# в том же опыте убит, status — «шаг оборван». Метки окружения доходят до службы (их
# читает перепись застоя). Машина перезагружена — .pid старше btime — причина названа.
# Причина обрыва службы — дословной строкой status: kill -9 процесса шага и
# `systemctl --user stop` — РАЗНЫЕ фразы (запись .exit службы), сторонний kill -TERM — своя
# (журнал о нём молчит — держит чтение записи); запись снята — та же фраза из журнала юнита.
# Без systemd --user (ранер CI) случаи службы не исполняются и печатаются счётом
# «служба: не исполнено N» — не зелёным; setsid-путь и остальное исполняются везде.
# Каталог шагов — свой временный; процессы шагов снимаются по группе на выходе (и на падении),
# службы и scope пробы — `systemctl --user stop` по имени (в конце, как и шаги: ловушка — лишь
# шаблон уборки каталога, tooling-gate check-26; на обрыве шаги самоистекают — sleep 2 и 60 с).
# Коды: 0 — всё сошлось, мутанты убиты; 1 — нет; 2 — нет setsid или python3 (вердикта нет).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
D_REAL="$HERE/detach.sh"; D="$D_REAL"
GUARD="$(cd "$HERE/.." && pwd)/.claude/hooks/no-wait-guard/guard.py"
for t in setsid python3 git; do command -v "$t" > /dev/null 2>&1 || { echo "[VOID] нет $t" >&2; exit 2; }; done
W="$(mktemp -d)"; W="$(cd "$W" && pwd -P)"
PGS=(); UNITS=()
SYSD=0; systemctl --user show-environment > /dev/null 2>&1 && command -v systemd-run > /dev/null 2>&1 && SYSD=1
unexec=0
# Шаги пробы снимаются группой (setsid — своя группа) в конце; долгий шаг (sleep 30) снят в своём случае.
reap_steps() {
    local p
    for p in "${PGS[@]}"; do kill -- "-$p" 2>/dev/null; done
    for p in "${UNITS[@]}"; do systemctl --user stop "$p" 2>/dev/null; done
    for p in "$W"/run.*/*/*.unit; do [ -f "$p" ] && systemctl --user stop "$(cat "$p")" 2>/dev/null; done
    return 0
}
# shellcheck disable=SC2154
trap '_rc=$?; rm -rf "$W" 2>/dev/null || rm -rf "$W" || echo "ПРЕДУПРЕЖДЕНИЕ: временный каталог $W не снят; код проверки $_rc сохранён" >&2; exit $_rc' EXIT

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
    # Разделитель перед хвостовым echo (check-verifier ws#1242, круг 3): маскирует ; \n || | &, не &&.
    st "$R/s" sh -c 'false
echo x'; assert "64" "$SRC" "echo после перевода строки — 64"
    st "$R/s" sh -c 'false || echo x'; assert "64" "$SRC" "echo после «||» — 64 (при отказе код echo 0)"
    st "$R/s" sh -c 'false | echo x'; assert "64" "$SRC" "echo после «|» — 64 (код конвейера — echo)"
    st "$R/s" sh -c 'false & echo x'; assert "64" "$SRC" "echo после «&» — 64"
    st "$R/s" bash -c 'true && echo ok'; settle "$RCF"
    assert "0 0" "$SRC $(status "$RCF")" "близнец: «true && echo ok» — запуск 0, status 0"
    st "$R/s" bash -c 'false && echo ok'; settle "$RCF"
    assert "0 1" "$SRC $(status "$RCF")" "близнец: «false && echo ok» — запуск 0, status 1 (код false, не echo)"
    st "$R/s" sh -c 'echo only'; settle "$RCF"
    assert "0 0" "$SRC $(status "$RCF")" "близнец: строка из одного echo — его код честен, запуск 0"
    st "$R/s" sh -c 'false; a=$?; echo "rc=$a"; exit $a'; settle "$RCF"
    assert "0 1" "$SRC $(status "$RCF")" "близнец: код сохранён и возвращён exit — запуск 0, status 1 (код 1 прогона)"
    printf 'shift; "$@"\n' > "$R/s/chain.sh"
    st "$R/s" bash "$R/s/chain.sh" -- sh -c 'true; printf "%s" x > /dev/null'; settle "$RCF"
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

# boot_cases — машина перезагружена: файлы шага старше загрузки, процесса нет — причина названа.
boot_cases() {
    local R="$W/run.$RANDOM" bt; mkdir -p "$R/s"
    bt="$(awk '$1 == "btime" { print $2 }' /proc/stat)"
    printf '%s\n' 999999999 > "$R/s/boot.pid"; : > "$R/s/boot.log"; touch -d "@$((bt - 60))" "$R/s/boot.pid"
    assert "2 да" "$(status "$R/s/boot.rc") $(grep -qF 'машина перезагружена после старта' "$W/st.out" && echo да || echo нет)" "шаг старше загрузки машины без .rc — 2, причина «машина перезагружена»"
    printf '%s\n' 999999999 > "$R/s/fresh.pid"; : > "$R/s/fresh.log"
    assert "2 нет" "$(status "$R/s/fresh.rc") $(grep -qF 'машина перезагружена' "$W/st.out" && echo да || echo нет)" "близнец: шаг этой загрузки без процесса — 2, перезагрузкой не назван"
}

# survive_cases — шаг из одноразового scope; scope снят; служба жива, setsid — нет.
survive_cases() {
    local R="$W/run.$RANDOM" sc rc pid r2 p2; mkdir -p "$R"
    st "$R/v" sh -c 'exit 0'
    if [ "$SYSD" = 0 ]; then
        unexec=$((unexec + 6))
        assert "да" "$(grep -qF 'вид setsid (не переживёт перезапуск сессии)' <<< "$OUT" && echo да || echo нет)" "без systemd --user — строка «вид setsid (не переживёт…)»"
        return 0
    fi
    assert "да" "$(grep -qE '; вид служба kacho-detach-' <<< "$OUT" && [ -s "${RCF%.rc}.unit" ] && echo да || echo нет)" "systemd --user есть — шаг службой, строка «вид служба», файл .unit"
    sc="detach-inject-$$-$RANDOM"; UNITS+=("$sc.scope")
    export DETACH_PROBE_MARK="m-$sc"
    systemd-run --user --quiet --scope --unit="$sc" -- bash -c '
        bash "$1" start "$2/a" -- bash -c "sleep 2; exit 4" > "$2/a.out" 2>&1
        KACHO_DETACH_NO_SYSTEMD=1 bash "$1" start "$2/b" -- bash -c "sleep 2; exit 4" > "$2/b.out" 2>&1
        exec sleep 60' _ "$D" "$R" > /dev/null 2>&1 &
    for _ in $(seq 1 40); do [ -s "$R/b.out" ] && grep -q '^идёт' "$R/b.out" && break; sleep 0.25; done
    rc="$(sed -n 's/^идёт: .*; rc \([^;]*\);.*/\1/p' "$R/a.out")"; pid="$(cat "${rc%.rc}.pid" 2>/dev/null)"
    r2="$(sed -n 's/^идёт: .*; rc \([^;]*\);.*/\1/p' "$R/b.out")"; p2="$(cat "${r2%.rc}.pid" 2>/dev/null)"
    [ -n "$p2" ] && PGS+=("$p2")
    assert "да" "$(grep -qzxF "DETACH_PROBE_MARK=m-$sc" "/proc/$pid/environ" 2>/dev/null && echo да || echo нет)" "окружение вызова дошло до службы (метки переписи застоя)"
    assert "да" "$(grep -q "/$sc.scope\$" "/proc/$p2/cgroup" 2>/dev/null && ! grep -q "/$sc.scope\$" "/proc/$pid/cgroup" && echo да || echo нет)" "служба — вне scope вызова, setsid-шаг — в нём"
    systemctl --user stop "$sc.scope" 2>/dev/null
    for _ in $(seq 1 20); do kill -0 "$p2" 2>/dev/null || break; sleep 0.1; done
    assert "3" "$(status "$rc")" "инъекция: scope вызова снят — служба шага жива, status 3"
    assert "2 да" "$(status "$r2") $(grep -qF 'шаг оборван' "$W/st.out" && echo да || echo нет)" "близнец: тот же scope снят — setsid-шаг убит, status 2 «шаг оборван»"
    settle "$rc"
    assert "1 да" "$(status "$rc") $(grep -qF 'исход: код 4' "$W/st.out" && echo да || echo нет)" "служба дописала исход после снятия scope — код 4 назван"
    st "$R/v" bash -c 'printf "%s|%s\n" "$$" "${HOME:-}"; exit 0'; settle "$RCF"
    assert "да" "$(grep -qE "^[0-9]+\|$HOME\$" "${RCF%.rc}.log" && grep -qE '^[0-9]+$' "${RCF%.rc}.pid" && echo да || echo нет)" "доводы службы — дословно: \$\$ и \$HOME команды не раскрыты systemd"
    unset DETACH_PROBE_MARK
}

# cause_cases — причина обрыва службы: каждая своей инъекцией, строка status — дословно.
# want <фраза причины> <что> — status шага (RCF, UNIT) — 2 и строка ровно такая.
want() {
    local b="${RCF%.rc}"
    assert "2|не выполнилось: процесса $PID нет, а .rc нет — шаг оборван: $1; журнал $b.log" \
        "$(status "$RCF")|$(head -n 1 "$W/st.out")" "$2"
}
# jsettle <юнит> <образец> — журнал юнита дописан (journald асинхронен): до 5 с.
jsettle() {
    local _ j
    for _ in $(seq 1 20); do
        j="$(journalctl --user -u "$1.service" -o cat --no-pager -n 40 2>/dev/null)"
        grep -qF "$2" <<< "$j" && return 0
        sleep 0.25
    done
    return 1
}
PID=""; UNIT=""
cause_cases() {
    local R="$W/run.$RANDOM" kill9 stop; mkdir -p "$R"
    if [ "$SYSD" = 0 ]; then unexec=$((unexec + 6)); return 0; fi
    step_up() { st "$R/c" sleep 30; PID="$(cat "${RCF%.rc}.pid")"; UNIT="$(cat "${RCF%.rc}.unit")"; }
    step_up; kill -9 "$PID"; settle "${RCF%.rc}.exit"
    kill9="служба $UNIT: процесс шага убит сигналом KILL (kill -9 либо OOM-убийство)"
    want "$kill9" "инъекция kill -9 процесса шага — «убит сигналом KILL (kill -9 либо OOM-убийство)»"
    rm -f "${RCF%.rc}.exit"; jsettle "$UNIT" "Failed with result"
    want "$kill9" "  …записи .exit нет — та же фраза из журнала юнита"
    step_up; systemctl --user stop "$UNIT"; settle "${RCF%.rc}.exit"
    stop="служба $UNIT остановлена менеджером служб (systemctl stop либо остановка systemd --user)"
    want "$stop" "инъекция systemctl --user stop — «остановлена менеджером служб», не «убит»"
    rm -f "${RCF%.rc}.exit"; jsettle "$UNIT" "Stopped $UNIT"
    want "$stop" "  …записи .exit нет — та же фраза из журнала юнита"
    step_up; kill -TERM "$PID"; settle "${RCF%.rc}.exit"
    want "служба $UNIT: процесс шага убит сигналом TERM" "инъекция стороннего kill -TERM — «убит сигналом TERM», не остановка (журнал молчит — фраза из записи)"
    step_up; settle "${RCF%.rc}.exit"
    assert "3" "$(status "$RCF")" "близнец: служба жива — status 3, причины нет"
    systemctl --user stop "$UNIT" 2>/dev/null
}

grc() {
    python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"agent_type":"go-implementer"}))' "$1" \
        | python3 "$GUARD" > "$W/g.out" 2>&1
    echo $?
}
run_cases
echo "== перезагрузка машины"
boot_cases
echo "== перезапуск сессии: scope вызова снят"
survive_cases
echo "== причина обрыва службы"
cause_cases
echo "== страж no-wait-guard"
assert "0" "$(grc "bash \$WS/scripts/detach.sh start \$WS/tmp/1225 -- bash \$WS/scripts/heavy-slot.sh ci-local -- env KACHO_TASK=1225 git push origin HEAD:refs/heads/1225-x")" "страж пропускает start"
assert "0" "$(grc "bash \$WS/scripts/detach.sh status \$WS/tmp/1225/x.rc")" "страж пропускает status"
assert "2" "$(grc "until bash \$WS/scripts/detach.sh status \$WS/tmp/1225/x.rc; do sleep 30; done")" "страж отказывает циклу дочитки агентом"
assert "да" "$(grc 'gh run watch 1' > /dev/null; grep -qF 'scripts/detach.sh start' "$W/g.out" && echo да || echo нет)" "текст отказа стража называет detach.sh как правильную форму"

# Диспозиция сигналов шага (ws#1274): вызывающий с SIG_IGN на SIGPIPE и SIGHUP (nohup, python) —
# шаг их не наследует ни службой, ни путём setsid (служба стартует от systemd с умолчанием, setsid —
# от вызывающего: держит его только env --default-signal). Вывод шага — «<код yes | head> <биты>».
sig_cases() {
    local R; R="$W/run.$RANDOM"; mkdir -p "$R"
    echo "== диспозиция сигналов шага"
    # shellcheck disable=SC2016  # строка дочерней оболочки
    printf '%s\n' 'set -o pipefail; yes | head -n 1 > /dev/null; p=$?; i=$(sed -n "s/^SigIgn:[[:space:]]*//p" /proc/$$/status); printf "%s %s" "$p" $(( 16#$i & 0x1001 )) > "$1"' > "$R/sig.sh"
    KACHO_DETACH_NO_SYSTEMD=1 python3 -c 'import os, signal, sys; signal.signal(signal.SIGPIPE, signal.SIG_IGN); signal.signal(signal.SIGHUP, signal.SIG_IGN); os.execvp(sys.argv[1], sys.argv[1:])' \
        bash "$D" start "$R/g" -- bash "$R/sig.sh" "$R/g.out" > "$W/start.out" 2>&1
    RCF="$(sed -n 's/^идёт: pid [0-9]*; журнал [^;]*; rc \([^;]*\);.*/\1/p' "$W/start.out")"; settle "$RCF"
    assert "141 0" "$(cat "$R/g.out" 2>/dev/null || echo нет)" "setsid-путь: вызывающий с SIG_IGN на PIPE и HUP — шаг их не наследует (141, ничего не заглушено)"
}
sig_cases

echo "== мутанты"
muts=0; survived=0
mutant() {  # <имя> <было> <стало>
    local m="$W/mut/detach.sh" f="${4:-detach.sh}"; mkdir -p "$W/mut"; cp "$HERE/detach.sh" "$HERE/detach-launch.sh" "$W/mut/"
    python3 - "$HERE/$f" "$W/mut/$f" "$2" "$3" <<'PY' || { echo "  [VOID] мутант $1: правка не легла"; survived=$((survived + 1)); return; }
import sys
s, d, a, b = sys.argv[1:5]
t = open(s, encoding="utf-8").read()
if t.count(a) != 1:
    sys.exit(1)
open(d, "w", encoding="utf-8").write(t.replace(a, b))
PY
    muts=$((muts + 1))
    local before=$fail
    D="$m"; "${5:-run_cases}" > "$W/mut.out" 2>&1; D="$D_REAL"
    if [ "$fail" -gt "$before" ]; then echo "  [убит] $1 — $(grep -m1 -F '[FAIL]' "$W/mut.out" | sed 's/^ *\[FAIL\] //' | cut -c1-160)"
    else echo "  [ВЫЖИЛ] $1"; survived=$((survived + 1)); fi
    fail=$before
}
mutant tag-ignored '[ "$e" = "DETACH_TAG=$2" ] && return 0' '[ -n "$e" ] && return 0'
mutant nonzero-as-green '[ "$code" -eq 0 ] && exit 0
        exit 1' 'exit 0'
mutant dead-as-running '        exit 3
    fi
    # Внешний шаг' '        exit 3
    fi
    exit 3
    # Внешний шаг'
mutant log-rc-name '        *.log.rc) rcf="$2"; logf="${2%.rc}" ;;
' ''
mutant ext-dead-as-broken '        echo "не судим как идущий: внешний шаг без .pid и метки, журнал $logf не держит ни один процесс — .rc нет; исход — status позже либо по журналу"
        exit 4' '        echo "оборван"; exit 2'
mutant ext-holder-ignored '        if [ -n "$holder" ]; then echo' '        if false; then echo'
mutant inner-c-judged '        [ "$prev" != -c ] && [ "$prev" != "" ] && [ "${prev:0:1}" != - ] && [ "$prev" != "$1" ] && break
' ''
mutant and-as-semicolon '[ "${pre: -2}" != "&&" ] &&' 'true &&'
mutant trailing-echo-allowed '&& [[ "$last" =~ ^(echo|printf)([[:space:]]|$) ]]; then' '&& false; then'
mutant name-not-unique '-$$-$(printf' '-$(printf'
mutant tree-unchecked '= true ] && [ "$ign" = 0 ]; then' '= true ] && false; then'
mutant boot-unread '[ "$mt" -lt "$bt" ]; then' '[ "$mt" -lt 0 ]; then' detach-launch.sh boot_cases
mutant hup-inherited 'env --default-signal=PIPE,HUP DETACH_TAG' 'env --default-signal=PIPE DETACH_TAG' detach.sh sig_cases
if [ "$SYSD" = 1 ]; then
    mutant no-unit '[ "${KACHO_DETACH_NO_SYSTEMD:-}" = 1 ]; then' 'true; then' detach-launch.sh survive_cases
    mutant env-expanded ' --expand-environment=no \' ' \' detach-launch.sh survive_cases
    mutant env-not-carried '&& [ "$n" != DETACH_EXIT_FILE ] && envs+=("--setenv=$n")' '&& true' detach-launch.sh survive_cases
    mutant one-phrase-stop-as-kill "printf 'служба %s остановлена менеджером служб (systemctl stop либо остановка systemd --user)' \"\$1\"" \
        "printf 'служба %s: процесс шага убит сигналом KILL (kill -9 либо OOM-убийство)' \"\$1\"" detach-launch.sh cause_cases
    mutant one-phrase-both-gone '[ -n "$rec" ] && { detach_cause_text "$u" $rec; return; }' ':' detach-launch.sh cause_cases
    mutant stop-mark-inverted '[ -z "$MAINPID" ] || : >' '[ -n "$MAINPID" ] || : >' detach-launch.sh cause_cases
    mutant record-unread 'rec="$(head -n 1 "${2%.unit}.exit" 2> /dev/null)"' 'rec=""' detach-launch.sh cause_cases
    mutant journal-unread '[ -n "$rec" ] || rec="$(detach_unit_journal "$u")"' ':' detach-launch.sh cause_cases
fi

reap_steps
echo "[CENSUS] detach: утверждений $((pass + fail)), сошлось $pass, разошлось $fail; мутантов $muts, выжило $survived; служба: systemd --user $([ "$SYSD" = 1 ] && echo есть || echo НЕТ), не исполнено утверждений $unexec"
[ "$fail" -eq 0 ] && [ "$survived" -eq 0 ]
