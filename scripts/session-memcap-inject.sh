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
# Граница потолка и метки omit (перенос в свой scope уходит из-под обоих) исполняется
# строкой [BOUND] — «известно, не держится», не зелёное. Взаимодействие с systemd-oomd —
# на одноразовом срезе под его слежением (kill, 1 %, 2 с); убийцу каждого листа называет
# журнал systemd-oomd по имени unit и memory.events среза, а не код 137.
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
try: print(os.getxattr(sys.argv[1], "user.oomd_omit").decode())
except OSError: print("нет")' "$cg" > "$o.omit"
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
assert "0 $((1024 - 700 - 128 + ${a:-0})) 0 max 1" "$(rd rc) $(mibs "$(rd cg | cut -d' ' -f1)") $(rd cg | cut -d' ' -f2,3) $(rd omit)" \
    "1024 − (700 − anon ${a:-?}) − 128: memory.max по формуле, swap.max 0, high max, user.oomd_omit=1"
assert "да" "$(has "$R.out" 'в силе')" "в силе — сказано по сверке cgroup"

echo "── ядро держит: сверх потолка снят процесс, scope жив (OOMPolicy=continue)"
probe session-memcap-probe - 400 "${CONT[@]}" -- "${PROBE[@]}"
assert "0 137 1" "$(rd rc) $(rd alloc) $(rd oom)" "400 МиБ под потолком ~200 — аллокатор убит ядром (137, oom_kill 1), оболочка scope дожила"

echo "── нижняя граница и отказ по запасу"
mem 1000
probe session-memcap-probe - 0 "${CONT[@]}" -- "${PROBE[@]}"
assert "0 64 да" "$(rd rc) $(mibs "$(rd cg | cut -d' ' -f1)") $(has "$R.out" 'нижняя граница')" "1024 − ~1000 − 128 < 64 — потолок = граница 64, это сказано"
probe session-memcap-probe - 0 "${CONT[@]}" -- "${PROBE[@]}" SESSION_MEMCAP_MARGIN_MIB=64
assert "1 max да 1" "$(rd rc) $(rd cg | cut -d' ' -f1) $(has "$R.err" 'запас') $(rd omit)" "anon + 64 ≥ потолка 64 — отказ 1, потолок не поставлен, причина названа; omit в силе и при отказе"

echo "── OOMPolicy=stop: первое OOM-убийство сняло бы весь scope — отказ"
mem 700
probe session-memcap-probe - 0 -- "${PROBE[@]}"
assert "1 max да да 1" "$(rd rc) $(rd cg | cut -d' ' -f1) $(has "$R.err" 'OOMPolicy=stop') $(has "$R.err" 'omit=1 в силе') $(rd omit)" "scope со stop (как терминал) — отказ 1, потолка нет, названы причина и --launch; omit поставлен и сверен"
# Причина отказа — замер: под stop OOM-убийство под потолком останавливает scope целиком.
MEMCAP=/bin/true ALLOCPY="$W/alloc.py" timeout 60 systemd-run --user --scope --quiet --collect \
    --unit="session-memcap-probe-stop-$$.scope" -p MemoryMax=64M -p MemorySwapMax=0 \
    -- bash -c 'sleep 30 & echo $! > "$0.sleep"; python3 "$1" 256; sleep 2; echo жив > "$0.alive"' "$W/stop" "$W/alloc.py" 2>/dev/null
assert "нет нет" "$(cat "$W/stop.alive" 2>/dev/null || echo нет) $(kill -0 "$(cat "$W/stop.sleep" 2>/dev/null || echo 999999)" 2>/dev/null && echo да || echo нет)" \
    "предпосылка отказа: под OOMPolicy=stop OOM-убийство одного процесса остановило весь scope (оболочка и сосед sleep сняты)"

echo "── ручки и режим проб: живую сессию проба не трогает"
probe session-memcap-probe - 0 "${CONT[@]}" -- SESSION_MEMCAP_CAP_MIB=1
assert "64 max да нет" "$(rd rc) $(rd cg | cut -d' ' -f1) $(has "$R.err" 'SESSION_MEMCAP_CAP_MIB') $(rd omit)" "ручка над настоящей памятью — 64, ни потолка, ни omit"
probe hsx-memcap-other - 0 "${CONT[@]}" -- "${PROBE[@]}"
assert "64 max да нет" "$(rd rc) $(rd cg | cut -d' ' -f1) $(has "$R.err" 'одноразовом scope') $(rd omit)" "режим проб не на session-memcap-probe-* — 64: чужой scope не тронут, omit нет"
probe session-memcap-probe --show 0 "${CONT[@]}" -- "${PROBE[@]}"
assert "0 max да нет" "$(rd rc) $(rd cg | cut -d' ' -f1) $(has "$R.out" 'поставил бы') $(rd omit)" "--show считает, ничего не меняя: ни потолка, ни omit"

echo "── --hook: отказ — строкой диспетчеру, код 0; успех — молча"
probe session-memcap-probe --hook 0 -- "${PROBE[@]}"
hook_ok="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["hookSpecificOutput"]; print(d["hookEventName"], "SESSION-MEMCAP" in d["additionalContext"], "--launch" in d["additionalContext"])' "$R.out" 2>/dev/null || echo нет)"
assert "0 SessionStart True True" "$(rd rc) $hook_ok" "отказ (stop) — код 0 и additionalContext SESSION-MEMCAP с перезапуском --launch"
probe session-memcap-probe --hook 0 "${CONT[@]}" -- "${PROBE[@]}"
assert "0 0 1" "$(rd rc) $(wc -c < "$R.out" | tr -d ' ') $(rd omit)" "близнец: потолок поставлен — код 0 и ни слова, omit в силе"
wired="$(python3 -c '
import json, sys
hs = json.load(open(sys.argv[1])).get("hooks", {}).get("SessionStart", [])
print(any("session-memcap.sh" in h.get("command", "") and "--hook" in h.get("command", "")
          for e in hs for h in e.get("hooks", [])))' "$ROOT/.claude/settings.json" 2>/dev/null)"
assert "True" "$wired" "settings.json: SessionStart зовёт session-memcap.sh --hook"

echo "── --launch: новый scope сразу под потолком, OOMPolicy=continue, omit"
cat > "$W/launched.sh" <<'EOF'
cg="/sys/fs/cgroup$(sed -n 's/^0:://p' /proc/self/cgroup)"
printf '%s %s %s %s %s\n' "$(cat "$cg/memory.max")" "$(cat "$cg/memory.swap.max")" "$(cat "$cg/memory.high")" \
    "$(systemctl --user show -p OOMPolicy --value "${cg##*/}")" \
    "$(python3 -c 'import os,sys; print(os.getxattr(sys.argv[1], "user.oomd_omit").decode())' "$cg" 2>/dev/null || echo нет)" > "$1"
EOF
env "${PROBE[@]}" timeout 60 bash "$MEMCAP" --launch -- bash "$W/launched.sh" "$W/launch.res" 2>/dev/null
assert "$(( (1024 - 700 - 128) * 1048576 )) 0 max continue 1" "$(cat "$W/launch.res" 2>/dev/null || echo нет)" "потолок 1024 − 700 − 128 = 196 МиБ, swap 0, high max, continue, omit"

echo "── граница: перенос в свой scope уходит из-под потолка и из-под omit"
cat > "$W/escape.sh" <<'EOF'
systemd-run --user --scope --quiet --collect bash -c 'cg="/sys/fs/cgroup$(sed -n "s/^0:://p" /proc/self/cgroup)"
printf "%s %s\n" "$(cat "$cg/memory.max")" "$(python3 -c "import os,sys; print(os.getxattr(sys.argv[1], \"user.oomd_omit\").decode())" "$cg" 2>/dev/null || echo нет)"' > "$1"
EOF
env "${PROBE[@]}" timeout 60 bash "$MEMCAP" --launch -- bash "$W/escape.sh" "$W/escape.res" 2>/dev/null
boundary "max нет" "$(cat "$W/escape.res" 2>/dev/null || echo нет)" "systemd-run --user --scope из сессии под потолком и omit — у нового scope memory.max = max, метки omit нет"

echo "── systemd-oomd: omit, поставленный session-memcap.sh, соблюдён; убийцу называет журнал"
# Давящий — OV МиБ под MemoryMax OM со swap: давление даёт подкачка, и ей нужно OV − OM
# свободной; иначе давящего снимает ядро (OOM среза), а не oomd — так судились раунды
# 512/64 на подкачке 7949 из 8191 МиБ (journalctl -k 2026-09-24 18:50–18:53). Объём
# малый: 96/16 давали full avg10 до 2,5 % при пределе 1 % (замер 2026-09-24). Убийца
# листа — строка «Killed <путь unit>» журнала systemd-oomd; ядро — oom_kill в
# memory.events среза. Код 137 убийцу не различает: раунд, где процесс сняло ядро, не
# засчитан ни утверждению, ни близнецу. omit ставит сам session-memcap.sh — отказом
# потолка на scope со stop, как у терминала.
OV=96; OM=16; OD=10
UPATH="/user.slice/user-$(id -u).slice/user@$(id -u).service"
pre=""
systemctl is-active --quiet systemd-oomd || pre="systemd-oomd не активен"
command -v oomctl >/dev/null || pre="${pre:+$pre; }нет oomctl"
[ "$(journalctl --system -q -n 1 -o cat --no-pager 2>/dev/null | wc -l)" -ge 1 ] ||
    pre="${pre:+$pre; }системный журнал не читается (группы adm либо systemd-journal нет) — убийцу не назвать"
if [ -z "$pre" ]; then
    sup="$(oomctl 2>/dev/null | awk -v p="$UPATH" '/^Memory Pressure Monitored CGroups:/ { m = 1; next } /^[^\t]/ { m = 0 }
                                                  m && $1 == "Path:" && $2 == p { n++ } END { print n + 0 }')"
    echo "  [NOTE] надзор oomd по давлению за user@$(id -u).service сейчас: $([ "$sup" -gt 0 ] && echo есть || echo нет) — omit защищает сессию от него; соблюдение omit ниже судит срез пробы со своим надзором"
    printf 'import sys, time\na = bytearray(int(sys.argv[1]) << 20)\nend = time.time() + float(sys.argv[2])\nwhile time.time() < end:\n    a[::4096] = b"x" * len(a[::4096])\n' > "$W/thrash.py"
    # omitted.sh <префикс> <команда…> — session-memcap.sh в режиме проб (отказ по stop,
    # omit), его код и метка — в файлы, затем команда листа.
    cat > "$W/omitted.sh" <<'EOF'
o="$1"; shift
cg="/sys/fs/cgroup$(sed -n 's/^0:://p' /proc/self/cgroup)"
bash "$MEMCAP" > "$o.out" 2> "$o.err"; echo "$?" > "$o.rc"
python3 -c 'import os,sys
try: print(os.getxattr(sys.argv[1], "user.oomd_omit").decode())
except OSError: print("нет")' "$cg" > "$o.omit"
exec "$@"
EOF
    # killer <unit> <код> <снятые oomd> — oomd (журнал) · жив (код 0) · код=<N> (не объяснён).
    killer() { if grep -qxF -- "$1" <<< "$3"; then echo oomd; elif [ "$2" -eq 0 ]; then echo жив; else echo "код=$2"; fi; }
    # oomd_round <на ком omit: thrasher|neighbor> — «код-memcap метка убийца-давящего
    # убийца-соседа» либо «VOID <причина>».
    oomd_round() {
        local who="$1" S="memcapprobe$$$1.slice" SD T0 N P rt rn free need kk killed others run tu nu ou
        SD="/sys/fs/cgroup$UPATH/$S"; tu="session-memcap-probe-t-$who-$$.scope"; nu="session-memcap-probe-n-$who-$$.scope"
        free="$(awk '/^SwapFree:/ { printf "%d\n", $2 / 1024 }' /proc/meminfo)"; need=$((OV - OM))
        if [ "${free:-0}" -lt "$need" ]; then
            echo "VOID свободной подкачки ${free:-?} МиБ < объёма давления $OV − MemoryMax $OM = $need МиБ: давящего сняло бы ядро, а не oomd"; return
        fi
        T0=$(( $(date +%s) - 1 )); ou="$W/o-$who"
        if [ "$who" = neighbor ]; then
            env "${PROBE[@]}" MEMCAP="$MEMCAP" systemd-run --user --scope --quiet --collect --slice="$S" --unit="$nu" \
                -- bash "$W/omitted.sh" "$ou" sleep $((OD + 4)) 2>/dev/null & N=$!
            for _ in $(seq 1 40); do [ -e "$ou.omit" ] && break; sleep 0.25; done  # метка — до давления
        else
            systemd-run --user --scope --quiet --collect --slice="$S" --unit="$nu" -- sleep $((OD + 4)) 2>/dev/null & N=$!
        fi
        sleep 0.5
        systemctl --user set-property --runtime "$S" ManagedOOMMemoryPressure=kill ManagedOOMMemoryPressureLimit=1% \
            ManagedOOMMemoryPressureDurationSec=2s 2>/dev/null
        sleep 0.5
        if ! oomctl 2>/dev/null | grep -qF "Path: $UPATH/$S"; then
            kill "$N" 2>/dev/null; wait "$N" 2>/dev/null; systemctl --user stop "$S" 2>/dev/null
            echo "VOID oomd не следит за срезом пробы $S (нет в oomctl) — соблюдение omit не судимо"; return
        fi
        ( end=$(( $(date +%s) + OD + 2 )); while [ "$(date +%s)" -lt "$end" ]; do
              awk '$1 == "full" { split($2, a, "="); print a[2] }' "$SD/memory.pressure" 2>/dev/null; sleep 0.5; done ) > "$W/p-$who" & P=$!
        if [ "$who" = thrasher ]; then
            env "${PROBE[@]}" MEMCAP="$MEMCAP" timeout 40 systemd-run --user --scope --quiet --collect --slice="$S" --unit="$tu" \
                -p MemoryMax="${OM}M" -- bash "$W/omitted.sh" "$ou" python3 "$W/thrash.py" "$OV" "$OD" 2>/dev/null; rt=$?
        else
            timeout 40 systemd-run --user --scope --quiet --collect --slice="$S" --unit="$tu" \
                -p MemoryMax="${OM}M" -p OOMPolicy=continue -- python3 "$W/thrash.py" "$OV" "$OD" 2>/dev/null; rt=$?
        fi
        wait "$N" 2>/dev/null; rn=$?
        wait "$P" 2>/dev/null
        kk="$(awk '$1 == "oom_kill" { print $2 }' "$SD/memory.events" 2>/dev/null)"
        systemctl --user set-property --runtime "$S" ManagedOOMMemoryPressure=auto 2>/dev/null
        systemctl --user stop "$S" 2>/dev/null  # пустой срез пробы не остаётся в менеджере
        if [ "${kk:-0}" -gt 0 ]; then
            echo "VOID ядро сняло процесс в срезе пробы (memory.events oom_kill $kk): раунд решило ядро, а не oomd — не засчитан"; return
        fi
        killed="$(journalctl -u systemd-oomd --since "@$T0" -q -o cat --no-pager 2>/dev/null |
            awk -v p="Killed $UPATH/$S/" 'index($0, p) == 1 { u = substr($0, length(p) + 1); sub(/ .*/, "", u); print u }')"
        if [ -z "$killed" ]; then
            others="$(journalctl -u systemd-oomd --since "@$((T0 - 16))" -q -o cat --no-pager 2>/dev/null | grep -c '^Killed ')"
            run="$(awk -v l=1 '$1 + 0 >= l { c++; if (c > m) m = c; next } { c = 0 } END { print m + 0 }' "$W/p-$who")"
            if [ "${others:-0}" -gt 0 ]; then
                echo "VOID oomd в паузе после своего действия вне среза ($others за 16 с до раунда) — раунд не судим"; return
            fi
            if [ "$run" -lt 5 ]; then
                echo "VOID давление среза не держалось выше 1 % дольше 2 с (подряд замеров full avg10 ≥ 1: $run по 0,5 с) — oomd не с чего действовать"; return
            fi
        fi
        echo "$(cat "$ou.rc" 2>/dev/null || echo нет) $(cat "$ou.omit" 2>/dev/null || echo нет) $(killer "$tu" "$rt" "$killed") $(killer "$nu" "$rn" "$killed")"
    }
    res="$(oomd_round thrasher)"
    case "$res" in
        VOID*) skip "omit на давящем: ${res#VOID }" ;;
        *) assert "1 1 жив oomd" "$res" "срез kill 1 %/2 с: omit поставил session-memcap.sh (отказ по stop, код 1), scope с omit дожил, соседа снял oomd — журнал: Killed …/session-memcap-probe-n-thrasher-$$.scope, ядро 0" ;;
    esac
    sleep 17  # пауза oomd после действия — иначе близнец судил бы паузу, а не omit
    res="$(oomd_round neighbor)"
    case "$res" in
        VOID*) skip "близнец, omit на соседе: ${res#VOID }" ;;
        *) assert "1 1 oomd жив" "$res" "близнец: omit на соседе — давящего снял oomd (журнал: Killed …/session-memcap-probe-t-neighbor-$$.scope), сосед с omit дожил, ядро 0" ;;
    esac
else
    skip "соблюдение omit oomd не судимо в этой среде: $pre"
fi

echo "[CENSUS] session-memcap: утверждений $((pass + fail)), сошлось $pass, разошлось $fail; граница (не держится, заявлено в шапке) $bound; не построено частей $void"
[ "$fail" -eq 0 ] || exit 1
[ "$void" -eq 0 ] || exit 2
exit 0
