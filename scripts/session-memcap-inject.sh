#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# session-memcap-inject.sh — доказательство того, что потолок сессии СТАВИТСЯ ядру,
# ДЕРЖИТ и ОТКАЗЫВАЕТ, а не только объявлен в шапке session-memcap.sh.
#
# Каждая проба идёт на ОДНОРАЗОВОМ scope (`systemd-run --user --scope`, имя
# session-memcap-probe-*) с малыми числами: потолок машины 1024 МиБ, граница 64,
# запас 16, docker 128, память машины — синтетический meminfo. Живую сессию проба не
# трогает: скрипт внутри себя отказывает режиму проб на чужом scope, и это тоже проба.
# Рядом с каждым отказом — законный близнец той же формы.
#
# Граница потолка (перенос в свой scope уходит из-под него) исполняется строкой
# [BOUND] — «известно, не держится», не зелёное. Взаимодействие с systemd-oomd —
# на одноразовом срезе под его слежением (kill, 1 %, 2 с).
#
# Нет systemd --user с контроллером memory либо systemd-oomd — части «не выполнились».
# Коды: 0 — все утверждения сошлись; 1 — хотя бы одно нет; 2 — сошлось всё
# исполненное, но часть не построена.
# Тексты оболочек и cat-файлов ниже раскрывает исполняющая их оболочка, а не эта.
# shellcheck disable=SC2016
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEMCAP="$HERE/session-memcap.sh"
ROOT="$(cd "$HERE/.." && pwd)"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
export LC_ALL=C.UTF-8

pass=0; fail=0; void=0; bound=0; n=0
assert() {
    if [ "$1" = "$2" ]; then echo "  [OK]   $3"; pass=$((pass + 1))
    else echo "  [FAIL] $3 — ожидалось «$1», получено «$2»" >&2; fail=$((fail + 1)); fi
}
skip() { echo "  [VOID] $1" >&2; void=$((void + 1)); }
boundary() {
    if [ "$1" = "$2" ]; then echo "  [BOUND] не держится (граница): $3"; bound=$((bound + 1))
    else echo "  [FAIL] граница «$3» — ожидалось «$1», получено «$2»: шапка устарела" >&2; fail=$((fail + 1)); fi
}
has() { grep -qF -- "$2" "$1" && echo да || echo нет; }

# mem <занято МиБ> — синтетическая память машины (MemTotal 60 ГиБ).
mem() { printf 'MemTotal: %d kB\nMemAvailable: %d kB\n' $((61440 * 1024)) $(( (61440 - $1) * 1024 )) > "$W/meminfo"; }
PROBE=(SESSION_MEMCAP_MEMINFO="$W/meminfo" SESSION_MEMCAP_CAP_MIB=1024 SESSION_MEMCAP_FLOOR_MIB=64
       SESSION_MEMCAP_MARGIN_MIB=16 SESSION_MEMCAP_DOCKER_MIB=128)

# inner.sh <режим|-> <аллокация МиБ|0> [env…] — внутри одноразового scope: вызов
# session-memcap.sh, затем состояние cgroup и, если просили, аллокация сверх потолка.
cat > "$W/alloc.py" <<'PY'
import sys
a = bytearray(int(sys.argv[1]) << 20)
a[::4096] = b"x" * len(a[::4096])
PY
cat > "$W/inner.sh" <<'EOF'
o="$1"; mode="$2"; alloc="$3"; shift 3
cg="/sys/fs/cgroup$(sed -n 's/^0:://p' /proc/self/cgroup)"
if [ "$mode" = - ]; then env "$@" bash "$MEMCAP" > "$o.out" 2> "$o.err"; else env "$@" bash "$MEMCAP" "$mode" > "$o.out" 2> "$o.err"; fi
echo "$?" > "$o.rc"
printf '%s %s %s\n' "$(cat "$cg/memory.max")" "$(cat "$cg/memory.swap.max")" "$(cat "$cg/memory.high")" > "$o.cg"
python3 -c 'import os,sys
try: print(os.getxattr(sys.argv[1], "user.oomd_avoid").decode())
except OSError: print("нет")' "$cg" > "$o.avoid"
if [ "$alloc" != 0 ]; then
    python3 "$ALLOCPY" "$alloc"; echo "$?" > "$o.alloc"
    awk '$1 == "oom_kill" { print $2 }' "$cg/memory.events" > "$o.oom"
fi
exit 0
EOF

# probe <имя unit> <режим|-> <аллокация> [-p свойство …] [-- env …] — scope-проба; префикс
# результатов — в $R. Возвращает код systemd-run (0 — scope дожил до конца).
probe() {
    local unit="$1" mode="$2" alloc="$3" props=() envs=()
    shift 3
    while [ "$#" -gt 0 ] && [ "$1" != -- ]; do props+=("$1"); shift; done
    [ "${1:-}" = -- ] && shift
    envs=("$@")
    n=$((n + 1)); R="$W/r$n"
    MEMCAP="$MEMCAP" ALLOCPY="$W/alloc.py" timeout 60 systemd-run --user --scope --quiet --collect \
        --unit="$unit-$n-$$.scope" "${props[@]}" -- bash "$W/inner.sh" "$R" "$mode" "$alloc" "${envs[@]}" 2>/dev/null
}
rd() { cat "$R.$1" 2>/dev/null || echo нет; }
mibs() { awk '{ printf "%d\n", $1 / 1048576 }' <<< "$1"; }
anon_of() { sed -n 's/.*anon scope \([0-9][0-9]*\) МиБ.*/\1/p' "$R.out" | head -n 1; }

if ! systemd-run --user --scope --quiet --collect -p MemoryMax=32M -- true 2>/dev/null ||
   ! grep -qw memory "/sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/cgroup.controllers" 2>/dev/null; then
    skip "systemd --user с контроллером memory недоступен — потолок сессии не доказан в этой среде"
    echo "[CENSUS] session-memcap: утверждений 0; не построено частей $void"
    exit 2
fi

CONT=(-p OOMPolicy=continue)
echo "── формула: потолок = max(граница, потолок машины − вне − docker), сверка по cgroup"
mem 700
probe session-memcap-probe - 0 "${CONT[@]}" -- "${PROBE[@]}"
a="$(anon_of)"
assert "0 $((1024 - 700 - 128 + ${a:-0})) 0 max 1" "$(rd rc) $(mibs "$(rd cg | cut -d' ' -f1)") $(rd cg | cut -d' ' -f2,3) $(rd avoid)" \
    "1024 − (700 − anon ${a:-?}) − 128: memory.max по формуле, swap.max 0, high max, user.oomd_avoid=1"
assert "да" "$(has "$R.out" 'в силе')" "в силе — сказано по сверке cgroup"

echo "── ядро держит: сверх потолка снят процесс, scope жив (OOMPolicy=continue)"
probe session-memcap-probe - 400 "${CONT[@]}" -- "${PROBE[@]}"
assert "0 137 1" "$(rd rc) $(rd alloc) $(rd oom)" "400 МиБ под потолком ~200 — аллокатор убит ядром (137, oom_kill 1), оболочка scope дожила"

echo "── нижняя граница и отказ по запасу"
mem 1000
probe session-memcap-probe - 0 "${CONT[@]}" -- "${PROBE[@]}"
assert "0 64 да" "$(rd rc) $(mibs "$(rd cg | cut -d' ' -f1)") $(has "$R.out" 'нижняя граница')" "1024 − ~1000 − 128 < 64 — потолок = граница 64, это сказано"
probe session-memcap-probe - 0 "${CONT[@]}" -- "${PROBE[@]}" SESSION_MEMCAP_MARGIN_MIB=64
assert "1 max да нет" "$(rd rc) $(rd cg | cut -d' ' -f1) $(has "$R.err" 'запас') $(rd avoid)" "anon + 64 ≥ потолка 64 — отказ 1, потолок и avoid не поставлены, причина названа"

echo "── OOMPolicy=stop: первое OOM-убийство сняло бы весь scope — отказ"
mem 700
probe session-memcap-probe - 0 -- "${PROBE[@]}"
assert "1 max да нет" "$(rd rc) $(rd cg | cut -d' ' -f1) $(has "$R.err" 'OOMPolicy=stop') $(rd avoid)" "scope со stop (как терминал) — отказ 1, ничего не поставлено, названы причина и --launch"
# Причина отказа — замер: под stop OOM-убийство под потолком останавливает scope целиком.
MEMCAP=/bin/true ALLOCPY="$W/alloc.py" timeout 60 systemd-run --user --scope --quiet --collect \
    --unit="session-memcap-probe-stop-$$.scope" -p MemoryMax=64M -p MemorySwapMax=0 \
    -- bash -c 'sleep 30 & echo $! > "$0.sleep"; python3 "$1" 256; sleep 2; echo жив > "$0.alive"' "$W/stop" "$W/alloc.py" 2>/dev/null
assert "нет нет" "$(cat "$W/stop.alive" 2>/dev/null || echo нет) $(kill -0 "$(cat "$W/stop.sleep" 2>/dev/null || echo 999999)" 2>/dev/null && echo да || echo нет)" \
    "предпосылка отказа: под OOMPolicy=stop OOM-убийство одного процесса остановило весь scope (оболочка и сосед sleep сняты)"

echo "── ручки и режим проб: живую сессию проба не трогает"
probe session-memcap-probe - 0 "${CONT[@]}" -- SESSION_MEMCAP_CAP_MIB=1
assert "64 max да" "$(rd rc) $(rd cg | cut -d' ' -f1) $(has "$R.err" 'SESSION_MEMCAP_CAP_MIB')" "ручка над настоящей памятью — 64, потолок не поставлен"
probe hsx-memcap-other - 0 "${CONT[@]}" -- "${PROBE[@]}"
assert "64 max да" "$(rd rc) $(rd cg | cut -d' ' -f1) $(has "$R.err" 'одноразовом scope')" "режим проб не на session-memcap-probe-* — 64: чужой scope не тронут"
probe session-memcap-probe --show 0 "${CONT[@]}" -- "${PROBE[@]}"
assert "0 max да" "$(rd rc) $(rd cg | cut -d' ' -f1) $(has "$R.out" 'поставил бы')" "--show считает, ничего не меняя"

echo "── --hook: отказ — строкой диспетчеру, код 0; успех — молча"
probe session-memcap-probe --hook 0 -- "${PROBE[@]}"
hook_ok="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["hookSpecificOutput"]; print(d["hookEventName"], "SESSION-MEMCAP" in d["additionalContext"], "--launch" in d["additionalContext"])' "$R.out" 2>/dev/null || echo нет)"
assert "0 SessionStart True True" "$(rd rc) $hook_ok" "отказ (stop) — код 0 и additionalContext SESSION-MEMCAP с перезапуском --launch"
probe session-memcap-probe --hook 0 "${CONT[@]}" -- "${PROBE[@]}"
assert "0 0 1" "$(rd rc) $(wc -c < "$R.out" | tr -d ' ') $(rd avoid)" "близнец: потолок поставлен — код 0 и ни слова"
wired="$(python3 -c '
import json, sys
hs = json.load(open(sys.argv[1])).get("hooks", {}).get("SessionStart", [])
print(any("session-memcap.sh" in h.get("command", "") and "--hook" in h.get("command", "")
          for e in hs for h in e.get("hooks", [])))' "$ROOT/.claude/settings.json" 2>/dev/null)"
assert "True" "$wired" "settings.json: SessionStart зовёт session-memcap.sh --hook"

echo "── --launch: новый scope сразу под потолком, OOMPolicy=continue, avoid"
cat > "$W/launched.sh" <<'EOF'
cg="/sys/fs/cgroup$(sed -n 's/^0:://p' /proc/self/cgroup)"
printf '%s %s %s %s %s\n' "$(cat "$cg/memory.max")" "$(cat "$cg/memory.swap.max")" "$(cat "$cg/memory.high")" \
    "$(systemctl --user show -p OOMPolicy --value "${cg##*/}")" \
    "$(python3 -c 'import os,sys; print(os.getxattr(sys.argv[1], "user.oomd_avoid").decode())' "$cg" 2>/dev/null || echo нет)" > "$1"
EOF
env "${PROBE[@]}" timeout 60 bash "$MEMCAP" --launch -- bash "$W/launched.sh" "$W/launch.res" 2>/dev/null
assert "$(( (1024 - 700 - 128) * 1048576 )) 0 max continue 1" "$(cat "$W/launch.res" 2>/dev/null || echo нет)" "потолок 1024 − 700 − 128 = 196 МиБ, swap 0, high max, continue, avoid"

echo "── граница: перенос в свой scope уходит из-под потолка"
cat > "$W/escape.sh" <<'EOF'
systemd-run --user --scope --quiet --collect bash -c 'cat "/sys/fs/cgroup$(sed -n "s/^0:://p" /proc/self/cgroup)/memory.max"' > "$1"
EOF
env "${PROBE[@]}" timeout 60 bash "$MEMCAP" --launch -- bash "$W/escape.sh" "$W/escape.res" 2>/dev/null
boundary "max" "$(cat "$W/escape.res" 2>/dev/null || echo нет)" "systemd-run --user --scope из сессии под потолком — у нового scope memory.max = max"

echo "── systemd-oomd: avoid соблюдён для листа под срезом пользователя"
if systemctl is-active --quiet systemd-oomd && command -v oomctl >/dev/null; then
    printf 'import sys, time\na = bytearray(512 << 20)\nend = time.time() + float(sys.argv[1])\nwhile time.time() < end:\n    a[::4096] = b"x" * len(a[::4096])\n' > "$W/thrash.py"
    # oomd_round <на ком avoid: thrasher|neighbor> <с давления> — «rc давящего rc соседа».
    # Давящий с avoid давит 8 с: сняв соседа, oomd ждёт ~15 с до следующего действия
    # (журнал oomd 2026-09-24: 16:48:40 → 16:48:56), и к ним avoid-лист уже не давит.
    oomd_round() {
        local S="memcapprobe$$$1.slice" N rt rn an=() at=()  # без дефиса: срез с дефисом вложился бы в чужой (session.slice)
        if [ "$1" = neighbor ]; then an=(-p ManagedOOMPreference=avoid); else at=(-p ManagedOOMPreference=avoid); fi
        systemd-run --user --scope --quiet --collect --slice="$S" --unit="session-memcap-probe-n-$1-$$.scope" \
            "${an[@]}" -- sleep 25 2>/dev/null & N=$!
        sleep 0.5
        systemctl --user set-property --runtime "$S" ManagedOOMMemoryPressure=kill ManagedOOMMemoryPressureLimit=1% \
            ManagedOOMMemoryPressureDurationSec=2s 2>/dev/null
        timeout 40 systemd-run --user --scope --quiet --collect --slice="$S" --unit="session-memcap-probe-t-$1-$$.scope" \
            -p MemoryMax=64M -p OOMPolicy=continue "${at[@]}" \
            -- python3 "$W/thrash.py" "$2" 2>/dev/null; rt=$?
        wait "$N" 2>/dev/null; rn=$?
        systemctl --user set-property --runtime "$S" ManagedOOMMemoryPressure=auto 2>/dev/null
        systemctl --user stop "$S" 2>/dev/null  # пустой срез пробы не остаётся в менеджере
        echo "$rt $rn"
    }
    assert "0 137" "$(oomd_round thrasher 8 2>/dev/null)" "срез kill 1 %/2 с: давящий scope (64 МиБ со swap) с avoid дожил, сосед без avoid снят oomd"
    sleep 17  # пауза oomd после действия — иначе близнец судил бы паузу, а не avoid
    assert "137" "$(oomd_round neighbor 25 2>/dev/null | cut -d' ' -f1)" "близнец: avoid на соседе — снят сам давящий"
else
    skip "systemd-oomd не активен — соблюдение avoid не доказано в этой среде"
fi

echo "[CENSUS] session-memcap: утверждений $((pass + fail)), сошлось $pass, разошлось $fail; граница (не держится, заявлено в шапке) $bound; не построено частей $void"
[ "$fail" -eq 0 ] || exit 1
[ "$void" -eq 0 ] || exit 2
exit 0
