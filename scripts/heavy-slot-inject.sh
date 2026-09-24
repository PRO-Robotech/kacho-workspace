#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# heavy-slot-inject.sh — доказательство того, что слот памяти СПОСОБЕН отказать,
# оборвать и выпустить, а не только объявляет это в шапке.
#
# ЗАЧЕМ. Слот, который ни разу не отказал, неотличим от слота, который отказывать
# не умеет; предел, который ни разу не сработал, неотличим от предела, которого
# нет. Поэтому каждое свойство подаётся настоящим входом с МАЛЫМ бюджетом (десятки
# МиБ), и рядом — законный близнец той же формы, который обязан пройти.
#
# Память машины подаётся синтетическим meminfo (HEAVY_SLOT_MEMINFO): вход и
# сторож машины судят по нему, поэтому исход не зависит от соседних полос. Предел
# ядра, мягкий предел и docker — настоящие: 256 МиБ против бюджета 64 МиБ.
# Каталог слотов — свой временный: занятые слоты машины проба не видит и не трогает.
#
# Части, чьей предпосылки в среде нет (systemd --user с контроллером memory,
# docker с образом HEAVY_SLOT_PROBE_IMAGE), не «пройдены», а «не выполнились».
# Коды: 0 — все утверждения сошлись; 1 — хотя бы одно нет; 2 — сошлось всё
# исполненное, но часть не построена.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SLOT="$HERE/heavy-slot.sh"
IMAGE="${HEAVY_SLOT_PROBE_IMAGE:-python:3.13-slim}"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

pass=0; fail=0; void=0
assert() {
    if [ "$1" = "$2" ]; then echo "  [OK]   $3"; pass=$((pass + 1))
    else echo "  [FAIL] $3 — ожидалось «$1», получено «$2»" >&2; fail=$((fail + 1)); fi
}
skip() { echo "  [VOID] $1" >&2; void=$((void + 1)); }
has() { grep -qF -- "$2" "$1" && echo да || echo нет; }
# entries — сколько файлов записей слотов осталось (состояние слота, не дерево).
entries() { local n=0 f; for f in "$HEAVY_SLOT_DIR"/active/*; do [ -e "$f" ] && n=$((n + 1)); done; echo "$n"; }

# mem <занято МиБ> — синтетическая память машины (MemTotal 60 ГиБ).
mem() { printf 'MemTotal: %d kB\nMemAvailable: %d kB\n' $((61440 * 1024)) $(( (61440 - $1) * 1024 )) > "$W/meminfo"; }

export HEAVY_SLOT_DIR="$W/slots" HEAVY_SLOT_MEMINFO="$W/meminfo" HEAVY_SLOT_LIMIT_MIB=100000 \
       HEAVY_SLOT_POLL_S=1 HEAVY_SLOT_WAIT_S=2 HEAVY_SLOT_GUARD_S=1 HEAVY_SLOT_GUARD_GRACE_S=10
mem 1000

# slot [ENV=…] <класс> -- … — код слота; stderr в $W/err.
slot() { env "$@" 2> "$W/err" > "$W/out"; echo $?; }
ALLOC='import sys, time; a = bytearray(int(sys.argv[1]) << 20); a[::4096] = b"x" * len(a[::4096]); time.sleep(float(sys.argv[2]))'

echo "── вызов"
assert 64 "$(slot bash "$SLOT" no-such -- true)" "неизвестный класс — 64"
assert 64 "$(slot bash "$SLOT" docker true)" "без «--» — 64"
assert 64 "$(slot HEAVY_SLOT_BUDGET_MIB=200000 bash "$SLOT" docker -- true)" "бюджет больше потолка — 64, а не вечное ожидание"
assert 3 "$(slot bash "$SLOT" docker -- bash -c 'exit 3')" "исполнившаяся команда — её собственный код"

echo "── вход по порогу: (MemTotal − MemAvailable) + недобранное + бюджет ≤ потолок"
export HEAVY_SLOT_LIMIT_MIB=1300
assert 0 "$(slot HEAVY_SLOT_BUDGET_MIB=300 bash "$SLOT" docker -- touch "$W/ran1")" "1000 + 0 + 300 ≤ 1300 — слот выдан"
assert 75 "$(slot HEAVY_SLOT_BUDGET_MIB=301 bash "$SLOT" docker -- touch "$W/ran2")" "1000 + 0 + 301 > 1300 — 75 по истечении ожидания"
assert "нет да" "$([ -e "$W/ran2" ] && echo да || echo нет) $(has "$W/err" 'команда НЕ запускалась')" "при 75 команда не запускалась, и это сказано"
assert "timeout" "$(grep -o ' timeout ' "$HEAVY_SLOT_DIR/journal.log" | tr -d ' ' | head -n 1)" "невыдача записана в журнал"

echo "── недобранное занятым слотом входит в счёт (исходный отказ — сосед ещё не набрал память)"
HEAVY_SLOT_BUDGET_MIB=200 bash "$SLOT" docker -- sleep 4 2>/dev/null & A=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do ls "$HEAVY_SLOT_DIR"/active/*.slot >/dev/null 2>&1 && break; sleep 0.2; done
assert 75 "$(slot HEAVY_SLOT_BUDGET_MIB=200 bash "$SLOT" docker -- true)" "1000 + ~200 недобранных + 200 > 1300 — второй ждёт и не входит"
wait "$A"
assert 0 "$(slot HEAVY_SLOT_BUDGET_MIB=200 bash "$SLOT" docker -- true)" "близнец: первый вышел — второй входит"

echo "── очередь строгая: малый не обгоняет ждущий большой"
HEAVY_SLOT_BUDGET_MIB=200 bash "$SLOT" docker -- sleep 4 2>/dev/null & A=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do ls "$HEAVY_SLOT_DIR"/active/*.slot >/dev/null 2>&1 && break; sleep 0.2; done
HEAVY_SLOT_WAIT_S=10 HEAVY_SLOT_BUDGET_MIB=250 bash "$SLOT" docker -- true 2>/dev/null & B=$!
sleep 0.5
assert "75 да" "$(slot HEAVY_SLOT_BUDGET_MIB=50 bash "$SLOT" docker -- true) $(has "$W/err" 'в очереди впереди 1')" "малый (50) влез бы по памяти, но большой (250) впереди — ждёт, и причина названа"
wait "$B"; rc_b=$?; wait "$A"
assert 0 "$rc_b" "большой дождался выхода первого и вошёл"
assert 0 "$(slot HEAVY_SLOT_BUDGET_MIB=50 bash "$SLOT" docker -- true)" "близнец: очередь пуста — малый входит"

echo "── golangci-lint по одному на машину; ждущий линтер очередь не держит"
HEAVY_SLOT_BUDGET_MIB=50 bash "$SLOT" lint -- sleep 4 2>/dev/null & A=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do ls "$HEAVY_SLOT_DIR"/active/*.slot >/dev/null 2>&1 && break; sleep 0.2; done
HEAVY_SLOT_WAIT_S=2 HEAVY_SLOT_BUDGET_MIB=50 bash "$SLOT" ci-local -- true 2>"$W/errB" & B=$!
sleep 0.5
assert 0 "$(slot HEAVY_SLOT_BUDGET_MIB=50 bash "$SLOT" newman -- true)" "newman за ждущим ci-local входит сразу"
wait "$B"; rc_b=$?; wait "$A"
assert "75 да" "$rc_b $(has "$W/errB" 'golangci-lint по одному на машину')" "ci-local при идущем lint ждёт, причина названа"
assert 0 "$(slot HEAVY_SLOT_BUDGET_MIB=50 bash "$SLOT" ci-local -- true)" "близнец: линтер вышел — ci-local входит"

echo "── запись слота, чей держатель умер, снимается при следующем входе"
printf 'class=go-race\nbudget=999\npid=999999\npid_start=1\nunit=\nstart=1\nseq=0\n' > "$HEAVY_SLOT_DIR/active/1-999999.slot"
assert 0 "$(slot HEAVY_SLOT_BUDGET_MIB=300 bash "$SLOT" docker -- true)" "мёртвая запись не держит 999 МиБ: вход выдан"
assert "0 да" "$(entries) $(has "$HEAVY_SLOT_DIR/journal.log" ' reap id=1-999999')" "запись снята и снятие записано"
export HEAVY_SLOT_LIMIT_MIB=100000

echo "── предел ядра: systemd-run --user --scope, MemoryMax"
if systemd-run --user --scope --quiet --collect -p MemoryMax=32M -- true 2>/dev/null &&
   grep -qw memory "/sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/cgroup.controllers" 2>/dev/null; then
    assert 0 "$(slot HEAVY_SLOT_BUDGET_MIB=64 bash "$SLOT" docker -- python3 -c "$ALLOC" 16 0)" "16 МиБ под бюджетом 64 — код 0"
    assert "76 да" "$(slot HEAVY_SLOT_BUDGET_MIB=64 bash "$SLOT" docker -- python3 -c "$ALLOC" 256 0) $(has "$W/err" 'OOM в cgroup слота')" "256 МиБ под бюджетом 64 — 76, причина названа"
    assert "да" "$(grep ' leave ' "$HEAVY_SLOT_DIR/journal.log" | tail -n 1 | grep -q 'limiter=systemd.*cut=OOM' && echo да || echo нет)" "выход с пиком и причиной обрыва — в журнале"

    # Объявленный, но НЕ действующий предел: подставной systemd-run запускает
    # команду без cgroup. Слот обязан это увидеть по memory.max и уйти в запасной путь.
    mkdir -p "$W/shim"
    # shellcheck disable=SC2016  # текст подставного скрипта, а не раскрытие
    printf '#!/usr/bin/env bash\nwhile [ "$1" != -- ]; do shift; done; shift; exec "$@"\n' > "$W/shim/systemd-run"
    chmod +x "$W/shim/systemd-run"
    rc="$(slot PATH="$W/shim:$PATH" HEAVY_SLOT_BUDGET_MIB=64 bash "$SLOT" docker -- python3 -c "$ALLOC" 256 3)"
    assert "76 да да" "$rc $(has "$W/err" 'предел ядра НЕ в силе') $(has "$W/err" 'мягкий предел')" "предел объявлен, но не в силе — замечено по memory.max, команда всё равно оборвана"
else
    skip "systemd --user с контроллером memory недоступен — предел ядра не доказан в этой среде"
fi

echo "── запасной путь: мягкий предел по RSS дерева"
assert 0 "$(slot HEAVY_SLOT_LIMITER=watch HEAVY_SLOT_BUDGET_MIB=64 bash "$SLOT" docker -- python3 -c "$ALLOC" 16 2)" "16 МиБ под бюджетом 64 — код 0"
assert "76 да" "$(slot HEAVY_SLOT_LIMITER=watch HEAVY_SLOT_BUDGET_MIB=64 bash "$SLOT" docker -- python3 -c "$ALLOC" 256 4) $(has "$W/err" 'мягкий предел')" "256 МиБ под бюджетом 64 — 76, причина названа"

echo "── docker run: предел — контейнеру, флаги памяти вызова — отказ"
if docker image inspect "$IMAGE" >/dev/null 2>&1; then
    assert "0 100663296" "$(slot HEAVY_SLOT_BUDGET_MIB=96 bash "$SLOT" docker -- docker run --rm "$IMAGE" cat /sys/fs/cgroup/memory.max) $(tr -d '\n' < "$W/out")" "контейнер получил memory.max = бюджет"
    assert "76 да" "$(slot HEAVY_SLOT_BUDGET_MIB=96 bash "$SLOT" docker -- docker run --rm "$IMAGE" python3 -c "$ALLOC" 300 0) $(has "$W/err" 'OOM контейнера')" "300 МиБ в контейнере под бюджетом 96 — 76, причина названа"
    assert 64 "$(slot HEAVY_SLOT_BUDGET_MIB=96 bash "$SLOT" docker -- docker run --rm -m 1g "$IMAGE" true)" "свой -m у вызова — 64"
    assert 0 "$(slot HEAVY_SLOT_BUDGET_MIB=96 bash "$SLOT" docker -- docker run --rm -e X=1 "$IMAGE" sh -c 'exit 0' -m)" "близнец: -m после образа — аргумент контейнера, не флаг docker"
else
    skip "нет docker либо образа $IMAGE — предел контейнера не доказан в этой среде"
fi

echo "── сторож машины: перебор потолка обрывает МЛАДШИЙ слот, старший живёт"
export HEAVY_SLOT_LIMIT_MIB=1300
HEAVY_SLOT_BUDGET_MIB=50 bash "$SLOT" docker -- sleep 6 2>"$W/errA" & A=$!
sleep 1.2
HEAVY_SLOT_BUDGET_MIB=50 bash "$SLOT" docker -- sleep 6 2>"$W/errC" & C=$!
sleep 1.2
mem 1400
wait "$C"; rc_c=$?
mem 1000
wait "$A"; rc_a=$?
assert "76 да 0" "$rc_c $(has "$W/errC" 'сторож машины') $rc_a" "младший оборван (76, причина названа), старший дошёл (0)"
export HEAVY_SLOT_LIMIT_MIB=100000

echo "── сигнал слоту снимает команду и запись"
bash "$SLOT" docker -- bash -c "echo \$\$ > $W/cmdpid; exec sleep 30" 2>/dev/null & S=$!
for _ in $(seq 1 25); do [ -s "$W/cmdpid" ] && break; sleep 0.2; done
t0="$(date +%s)"; kill -TERM "$S"; wait "$S"; rc=$?; t1="$(date +%s)"
alive="нет"; kill -0 "$(cat "$W/cmdpid" 2>/dev/null || echo 999999)" 2>/dev/null && alive="да"
assert "143 0 нет да" "$rc $(entries) $alive $([ $(( t1 - t0 )) -lt 10 ] && echo да || echo нет)" "TERM слоту → 143 сразу, записи нет, команда снята"

echo "[CENSUS] heavy-slot: утверждений $((pass + fail)), сошлось $pass, разошлось $fail; не построено частей $void"
[ "$fail" -eq 0 ] || exit 1
[ "$void" -eq 0 ] || exit 2
exit 0
