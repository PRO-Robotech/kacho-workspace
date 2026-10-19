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
    if [ -e "$base.pid" ]' '        exit 3
    fi
    exit 3
    if [ -e "$base.pid" ]'
mutant name-not-unique '-$$-$(printf' '-$(printf'
mutant tree-unchecked '= true ] && [ "$ign" = 0 ]; then' '= true ] && false; then'
mutant boot-unread '[ "$mt" -lt "$bt" ]; then' '[ "$mt" -lt 0 ]; then' detach-launch.sh boot_cases
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
