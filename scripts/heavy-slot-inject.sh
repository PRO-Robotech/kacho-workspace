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
# Исключение одно — близнец раздела ручек: законный вызов над настоящей памятью
# входит в общий каталог машины классом newman с командой touch.
#
# Части, чьей предпосылки в среде нет (systemd --user с контроллером memory,
# docker с образом HEAVY_SLOT_PROBE_IMAGE), не «пройдены», а «не выполнились».
# Граница слота (шапка heavy-slot.sh) исполняется тоже, но строкой [BOUND]: это
# известное «не ловится», а не зелёное; форма границы, которую слот вдруг поймал, —
# [FAIL]: шапка называет границей то, чего уже нет.
# Коды: 0 — все утверждения сошлись; 1 — хотя бы одно нет; 2 — сошлось всё
# исполненное, но часть не построена.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SLOT="$HERE/heavy-slot.sh"
IMAGE="${HEAVY_SLOT_PROBE_IMAGE:-python:3.13-slim}"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

pass=0; fail=0; void=0; bound=0
assert() {
    if [ "$1" = "$2" ]; then echo "  [OK]   $3"; pass=$((pass + 1))
    else echo "  [FAIL] $3 — ожидалось «$1», получено «$2»" >&2; fail=$((fail + 1)); fi
}
# boundary <ожидание> <факт> <форма> — граница слота: форма обязана уйти мимо него.
boundary() {
    if [ "$1" = "$2" ]; then echo "  [BOUND] не ловится (граница): $3"; bound=$((bound + 1))
    else echo "  [FAIL] граница «$3» — ожидалось «$1», получено «$2»: слот её держит, шапка устарела" >&2; fail=$((fail + 1)); fi
}
skip() { echo "  [VOID] $1" >&2; void=$((void + 1)); }
has() { grep -qF -- "$2" "$1" && echo да || echo нет; }
# entries — сколько файлов записей слотов осталось (состояние слота, не дерево).
entries() { local n=0 f; for f in "$HEAVY_SLOT_DIR"/active/*; do [ -e "$f" ] && n=$((n + 1)); done; echo "$n"; }

# mem <занято МиБ> — синтетическая память машины (MemTotal 96 ГиБ).
mem() { printf 'MemTotal: %d kB\nMemAvailable: %d kB\n' $((98304 * 1024)) $(( (98304 - $1) * 1024 )) > "$W/meminfo"; }

export HEAVY_SLOT_DIR="$W/slots" HEAVY_SLOT_MEMINFO="$W/meminfo" HEAVY_SLOT_LIMIT_MIB=100000 \
       HEAVY_SLOT_POLL_S=1 HEAVY_SLOT_WAIT_S=2 HEAVY_SLOT_GUARD_S=1 HEAVY_SLOT_GUARD_GRACE_S=10 \
       HEAVY_SLOT_BUDGET_MIB=64
mem 1000

# slot [ENV=…] <класс> -- … — код слота; stderr в $W/err.
slot() { env "$@" 2> "$W/err" > "$W/out"; echo $?; }
ALLOC='import sys, time; a = bytearray(int(sys.argv[1]) << 20); a[::4096] = b"x" * len(a[::4096]); time.sleep(float(sys.argv[2]))'

echo "── вызов"
assert 64 "$(slot bash "$SLOT" no-such -- true)" "неизвестный класс — 64"
assert 64 "$(slot bash "$SLOT" docker true)" "без «--» — 64"
assert 64 "$(slot HEAVY_SLOT_BUDGET_MIB=200000 bash "$SLOT" docker -- true)" "бюджет больше потолка — 64, а не вечное ожидание"
assert 3 "$(slot bash "$SLOT" docker -- bash -c 'exit 3')" "исполнившаяся команда — её собственный код"

echo "── ci-local держит ssh отправки живым: GIT_SSH_COMMAND с keepalive, заданное — сильнее (урок 2026-10-16)"
# git push открывает ssh до хука отправки; минуты хука простаивающее соединение
# площадка снимает, и push умирал PIPE (141) после зелёного хука.
# shellcheck disable=SC2016  # строка дочерней оболочки, переменную раскрывает она
assert "0 да" "$(slot -u GIT_SSH_COMMAND bash "$SLOT" ci-local -- sh -c 'printf %s "$GIT_SSH_COMMAND" > "$0"' "$W/ssh1") $(grep -q 'ServerAliveInterval=30' "$W/ssh1" && echo да || echo нет)" "ci-local без заданного ssh — GIT_SSH_COMMAND с ServerAliveInterval"
# shellcheck disable=SC2016
assert "0 да" "$(slot GIT_SSH_COMMAND='ssh -o Своё=1' bash "$SLOT" ci-local -- sh -c 'printf %s "$GIT_SSH_COMMAND" > "$0"' "$W/ssh2") $([ "$(cat "$W/ssh2")" = 'ssh -o Своё=1' ] && echo да || echo нет)" "близнец: заданный вызывающим GIT_SSH_COMMAND не переписан"
# shellcheck disable=SC2016
assert "0 да" "$(slot -u GIT_SSH_COMMAND bash "$SLOT" docker -- sh -c 'printf %s "${GIT_SSH_COMMAND:-}" > "$0"' "$W/ssh3") $([ -s "$W/ssh3" ] && echo нет || echo да)" "близнец: класс не ci-local — GIT_SSH_COMMAND не ставится"

echo "── перенос в другой unit уводит из cgroup слота: systemd-run и --scope в argv — 64"
# B2 круга 3: `heavy-slot.sh docker -- systemd-run --user --scope …` уходил из слота.
assert "64 да нет" "$(slot bash "$SLOT" docker -- systemd-run --user --scope touch "$W/e1") $(has "$W/err" '«systemd-run»') $([ -e "$W/e1" ] && echo да || echo нет)" "systemd-run первым словом — 64, причина названа, команда не запускалась"
assert "64 нет" "$(slot bash "$SLOT" docker -- bash -c "/usr/bin/systemd-run --user --scope touch $W/e2") $([ -e "$W/e2" ] && echo да || echo нет)" "systemd-run в строке bash -c — 64"
assert "64 да" "$(slot bash "$SLOT" docker -- sudo --scope true) $(has "$W/err" '«--scope»')" "--scope словом argv — 64"
# shellcheck disable=SC2016  # строка дочерней оболочки, $0 раскрывает она
assert "0 да" "$(slot bash "$SLOT" docker -- sh -c 'touch "$0"' "$W/e3" systemd-runner --scoped) $([ -e "$W/e3" ] && echo да || echo нет)" "близнец: systemd-runner и --scoped — не те слова, команда исполнилась"

echo "── над настоящей памятью ручек нет: потолок 70 ГиБ, ожидание только --wait ≤ 300 с, класс как есть"
# Без синтетического meminfo слот судит настоящую память машины — и тогда любая
# ручка получает 64 ДО первой записи (опыт ws#832, круги 2–3).
REAL=(-u HEAVY_SLOT_DIR -u HEAVY_SLOT_MEMINFO -u HEAVY_SLOT_LIMIT_MIB -u HEAVY_SLOT_GUARD_S -u HEAVY_SLOT_GUARD_GRACE_S -u HEAVY_SLOT_BUDGET_MIB -u HEAVY_SLOT_POLL_S -u HEAVY_SLOT_WAIT_S)
SHARED="$(getent passwd "$(id -u)" | cut -d: -f6)/.cache/heavy-slots"
seen() { stat -c %s:%Y "$SHARED/journal.log" 2>/dev/null || echo нет; }
before="$(seen)"
assert "64 да" "$(slot "${REAL[@]}" HEAVY_SLOT_LIMIT_GIB=46 bash "$SLOT" docker -- touch "$W/k1") $(has "$W/err" 'HEAVY_SLOT_LIMIT_GIB=46')" "потолок 46 ГиБ — 64, ручка названа"
assert "64 да нет" "$(slot "${REAL[@]}" HEAVY_SLOT_DIR="$W/own" bash "$SLOT" docker -- touch "$W/k2") $(has "$W/err" 'отдельная очередь') $([ -e "$W/own" ] && echo да || echo нет)" "свой каталог — 64, каталог не заведён"
assert "64 да" "$(slot "${REAL[@]}" HEAVY_SLOT_BUDGET_MIB=64 bash "$SLOT" docker -- touch "$W/k3") $(has "$W/err" 'HEAVY_SLOT_BUDGET_MIB')" "бюджет вызова — 64"
assert "64 да" "$(slot "${REAL[@]}" HEAVY_SLOT_LIMITER=watch bash "$SLOT" docker -- touch "$W/k4") $(has "$W/err" 'HEAVY_SLOT_LIMITER')" "мягкий предел вместо ядра — 64"
# B3 круга 3: потолок 1 ГиБ и ожидание 99999 с стояли головой строгой очереди.
assert "64 да" "$(slot "${REAL[@]}" HEAVY_SLOT_LIMIT_GIB=1 HEAVY_SLOT_WAIT_S=99999 bash "$SLOT" docker -- touch "$W/k6") $(has "$W/err" 'HEAVY_SLOT_')" "потолок 1 ГиБ и ожидание 99999 с — 64"
assert "64 да" "$(slot "${REAL[@]}" HEAVY_SLOT_LIMIT_GIB=70 bash "$SLOT" docker -- touch "$W/k7") $(has "$W/err" 'HEAVY_SLOT_LIMIT_GIB')" "даже потолок 70 ГиБ ручкой — 64: величина не переопределяется"
assert "64 да" "$(slot "${REAL[@]}" HEAVY_SLOT_SLOTS_SUM_MIB=99999 bash "$SLOT" docker -- touch "$W/k9") $(has "$W/err" 'HEAVY_SLOT_SLOTS_SUM_MIB')" "Σ бюджетов слотов ручкой — 64"
assert "64 да" "$(slot "${REAL[@]}" HEAVY_SLOT_ENQ_S=99999 bash "$SLOT" --enqueue "$W" docker -- touch "$W/k10") $(has "$W/err" 'HEAVY_SLOT_ENQ_S')" "срок --enqueue ручкой — 64"
# Чтение и поиск разведены: `grep -q` в конце трубы под pipefail рвёт писателя (ws#395).
cl="$(env "${REAL[@]}" bash "$SLOT" --classes 2>/dev/null)"; cl="${cl%%$'\n'*}"
assert "да да" "$(grep -qE 'потолок машины: 70[.,]0 ГиБ' <<<"$cl" && echo да || echo нет) $(grep -qE 'свободных до старта ≥ 15[.,]0 ГиБ; слотов ≤ 3, Σ бюджетов ≤ 30[.,]0 ГиБ' <<<"$cl" && echo да || echo нет)" "--classes над настоящей памятью: потолок 70 ГиБ, свободных ≥ 15, слотов ≤ 3, Σ ≤ 30 (решение 2026-10-02)"
assert "64 да" "$(slot "${REAL[@]}" HEAVY_SLOT_POLL_S=0 bash "$SLOT" docker -- touch "$W/k8") $(has "$W/err" 'HEAVY_SLOT_POLL_S')" "опрос 0 с (замок без паузы) — 64"
assert "нет $before" "$(ls "$W"/k* >/dev/null 2>&1 && echo да || echo нет) $(seen)" "ни одна команда не запускалась, журнал общего каталога не тронут"
# Близнец идёт в общую очередь без ожидания (ws#1004); занятая машина — 74, «не выполнилось».
rc="$(slot "${REAL[@]}" timeout 90 bash "$SLOT" newman -- touch "$W/k5")"
if [ "$rc" = 74 ] || [ "$rc" = 75 ] || [ "$rc" = 124 ]; then
    skip "машина занята — близнец общего каталога не построен ($rc)"
else
    assert "0 да" "$rc $([ -e "$W/k5" ] && echo да || echo нет)" "близнец: общий каталог без ручек — слот выдан, команда исполнилась"
fi

echo "── синтетический meminfo — режим проб: тяжёлым прогоном он быть не способен"
# Опыт ws#832, круг 3: скрипт с синтетическим meminfo, своим каталогом и потолком
# 200 ГиБ страж пропускает (ручки он видит лишь в строке команды) — держит слот.
printf '#!/usr/bin/env bash\nHEAVY_SLOT_MEMINFO=%q HEAVY_SLOT_DIR=%q HEAVY_SLOT_LIMIT_GIB=200 bash %q go-race -- touch %q\n' \
    "$W/meminfo" "$W/own2" "$SLOT" "$W/p1" > "$W/knobs.sh"
assert "64 да нет" "$(slot -u HEAVY_SLOT_BUDGET_MIB -u HEAVY_SLOT_LIMIT_MIB bash "$W/knobs.sh") $(has "$W/err" 'режим проб') $([ -e "$W/p1" ] && echo да || echo нет)" "скрипт с ручками, бюджет класса go-race — 64, причина названа, команда не запускалась"
assert "64 нет" "$(slot HEAVY_SLOT_BUDGET_MIB=513 bash "$SLOT" docker -- touch "$W/p2") $([ -e "$W/p2" ] && echo да || echo нет)" "бюджет 513 МиБ — 64"
assert "0 да" "$(slot HEAVY_SLOT_BUDGET_MIB=512 bash "$SLOT" docker -- touch "$W/p3") $([ -e "$W/p3" ] && echo да || echo нет)" "близнец: бюджет 512 МиБ — слот выдан"
assert "64 да" "$(slot HEAVY_SLOT_GUARD_S=60 bash "$SLOT" docker -- true) $(has "$W/err" 'сторож раз в 1–2 с')" "сторож раз в 60 с — 64, причина названа"
assert "64 да нет" "$(slot -u HEAVY_SLOT_DIR bash "$SLOT" docker -- touch "$W/p4") $(has "$W/err" 'только в своём каталоге') $([ -e "$W/p4" ] && echo да || echo нет)" "режим проб в общем каталоге — 64: билет пробы не встаёт в настоящую очередь"
assert "64 да" "$(slot HEAVY_SLOT_WAIT_S=x bash "$SLOT" docker -- true) $(has "$W/err" 'не число')" "нечисловая ручка — 64"

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

echo "── голову очереди держит лишь билет, влезающий под свой потолок при пустых слотах"
# B3 круга 3: билет с потолком ниже занятого ждал до конца своего ожидания, и
# строгая очередь стояла за ним вся.
HEAVY_SLOT_BUDGET_MIB=200 bash "$SLOT" docker -- sleep 4 2>/dev/null & A=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do ls "$HEAVY_SLOT_DIR"/active/*.slot >/dev/null 2>&1 && break; sleep 0.2; done
HEAVY_SLOT_LIMIT_MIB=1100 HEAVY_SLOT_WAIT_S=6 HEAVY_SLOT_BUDGET_MIB=250 bash "$SLOT" docker -- touch "$W/q1" 2>"$W/errQ" & B=$!
sleep 0.5
assert "0 да" "$(slot HEAVY_SLOT_BUDGET_MIB=50 bash "$SLOT" docker -- touch "$W/q2") $([ -e "$W/q2" ] && echo да || echo нет)" "впереди билет с потолком 1100 < 1000 + 250: голову не держит — малый (1000 + ~200 + 50 ≤ 1300) входит сразу (близнец — строгая очередь выше: потолок 1300, малый ждёт)"
wait "$A"; wait "$B"; rc_b=$?
assert "75 нет" "$rc_b $([ -e "$W/q1" ] && echo да || echo нет)" "сам билет с низким потолком — 75 по своему ожиданию, команда не запускалась"

echo "── lint по одному на машину, ci-local рядом с ним входит; ждущий линтер очередь не держит"
HEAVY_SLOT_BUDGET_MIB=50 bash "$SLOT" lint -- sleep 4 2>/dev/null & A=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do ls "$HEAVY_SLOT_DIR"/active/*.slot >/dev/null 2>&1 && break; sleep 0.2; done
HEAVY_SLOT_WAIT_S=2 HEAVY_SLOT_BUDGET_MIB=50 bash "$SLOT" lint -- true 2>"$W/errB" & B=$!
sleep 0.5
assert 0 "$(slot HEAVY_SLOT_BUDGET_MIB=50 bash "$SLOT" newman -- true)" "newman за ждущим lint входит сразу"
assert 0 "$(slot -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_BUDGET_MIB=50 bash "$SLOT" ci-local -- true)" "ci-local при идущем lint входит сразу: замок линтера у него в своём TMPDIR (ws#1087)"
wait "$B"; rc_b=$?; wait "$A"
assert "75 да" "$rc_b $(has "$W/errB" 'golangci-lint по одному на машину')" "lint при идущем lint ждёт, причина названа"
assert 0 "$(slot HEAVY_SLOT_BUDGET_MIB=50 bash "$SLOT" lint -- true)" "близнец: линтер вышел — lint входит"

echo "── ci-local: у каждой копии свой постоянный TMPDIR — замок golangci-lint не общий, логи переживают слот (ws#1087)"
# E4. Замок golangci-lint — $TMPDIR/golangci-lint.lock: держит его первая копия (flock,
# как сам линтер) до отметки второй, вторая гонит настоящий golangci-lint по модулю из
# одного файла. Копии — два разных рабочих каталога: ключ TMPDIR — корень копии.
if command -v golangci-lint >/dev/null && command -v go >/dev/null && command -v flock >/dev/null; then
    mkdir -p "$W/ga" "$W/gm" "$W/shtmp"; printf 'module x\n\ngo 1.26\n' > "$W/gm/go.mod"; printf 'package x\n\nfunc F() int { return 1 }\n' > "$W/gm/x.go"
    # shellcheck disable=SC2016  # строки дочерней оболочки
    HOLD='printf "%s\n" "$TMPDIR" > "$0"; exec flock "$TMPDIR/golangci-lint.lock" timeout 60 bash -c "until [ -e \"\$0\" ]; do sleep 0.2; done" "$1"'
    # shellcheck disable=SC2016
    LINT='printf "%s\n" "$TMPDIR" > "$0"; golangci-lint run ./...; rc=$?; : > "$1"; exit "$rc"'
    held() { for _ in $(seq 1 50); do [ -s "$1" ] && break; sleep 0.2; done; }
    export HEAVY_SLOT_LIMIT_MIB=100000  # линтер берёт 512 МиБ: потолок раздела выше (1300) его не вместил бы
    rm -f "$W/tA" "$W/tB" "$W/doneB"
    (cd "$W/ga" && env -u TMPDIR HEAVY_SLOT_BUDGET_MIB=64 bash "$SLOT" ci-local -- bash -c "$HOLD" "$W/tA" "$W/doneB" 2>/dev/null) & A=$!; held "$W/tA"
    rc="$(cd "$W/gm" && slot -u TMPDIR -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_BUDGET_MIB=512 GOLANGCI_LINT_CACHE="$W/glc" bash "$SLOT" ci-local -- bash -c "$LINT" "$W/tB" "$W/doneB")"
    wait "$A"; rc_a=$?
    tA="$(cat "$W/tA" 2>/dev/null)"; tB="$(cat "$W/tB" 2>/dev/null)"
    assert "0/0 да да" "$rc_a/$rc $([[ "$tA" == "$HEAVY_SLOT_DIR"/tmp/* ]] && [[ "$tB" == "$HEAVY_SLOT_DIR"/tmp/* ]] && echo да || echo нет) $([ -n "$tA" ] && [ "$tA" != "$tB" ] && echo да || echo нет)" "E4: две ci-local разных копий без TMPDIR вызывающего — TMPDIR у каждой свой, линтер второй при занятом замке первой — 0/0"
    assert "да да" "$([ -d "$tA" ] && echo да || echo нет) $([ -d "$tB" ] && echo да || echo нет)" "TMPDIR копии постоянный: выход слота его не снимает"
    rm -f "$W/tA" "$W/tB" "$W/doneB"
    (cd "$W/ga" && TMPDIR="$W/shtmp" HEAVY_SLOT_BUDGET_MIB=64 bash "$SLOT" ci-local -- bash -c "$HOLD" "$W/tA" "$W/doneB" 2>/dev/null) & A=$!; held "$W/tA"
    rc="$(cd "$W/gm" && slot -u HEAVY_SLOT_WAIT_S TMPDIR="$W/shtmp" HEAVY_SLOT_BUDGET_MIB=512 GOLANGCI_LINT_CACHE="$W/glc" bash "$SLOT" ci-local -- bash -c "$LINT" "$W/tB" "$W/doneB")"
    wait "$A"
    assert "3 да $W/shtmp" "$rc $(has "$W/err" 'parallel golangci-lint is running') $(cat "$W/tB" 2>/dev/null)" "E4 близнец: TMPDIR задан вызывающим и общий — слот его не трогает, второй линтер — код 3 «parallel golangci-lint is running»"
    export HEAVY_SLOT_LIMIT_MIB=1300
else
    skip "нет golangci-lint, go либо flock — замок линтера под своим TMPDIR не доказан в этой среде"
fi

# E7. Настоящий потребитель: kacho scripts/ci-local.sh выводит из TMPDIR каталог кэша и
# логов (ci-local.sh:214, 221) и печатает его строкой «ci-local: логи …». Неизвестная
# группа — код 2 сразу после того, как каталог прогона заведён: прогон дешёвый, путь — его.
CILOCAL="${HEAVY_SLOT_PROBE_CI_LOCAL:-$HERE/../project/kacho/scripts/ci-local.sh}"
if [ -f "$CILOCAL" ]; then
    rc="$(cd "$W/gm" && slot -u TMPDIR -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_BUDGET_MIB=256 bash "$SLOT" ci-local -- bash "$CILOCAL" нет-такой-группы)"
    logs="$(sed -n 's/^ci-local: логи *//p' "$W/out" | head -n 1)"
    assert "2 да да" "$rc $([[ "$logs" == "$HEAVY_SLOT_DIR"/tmp/* ]] && echo да || echo нет) $([ -n "$logs" ] && [ -d "$logs" ] && echo да || echo нет)" "E7: логи kacho ci-local.sh под TMPDIR слота ($logs) переживают выход слота"
    key="$(dirname "$(dirname "$logs")")"
    rc="$(cd "$W/gm" && slot -u TMPDIR -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_BUDGET_MIB=256 bash "$SLOT" ci-local -- bash "$CILOCAL" нет-такой-группы)"
    logs2="$(sed -n 's/^ci-local: логи *//p' "$W/out" | head -n 1)"
    assert "да да" "$([ "$(dirname "$(dirname "$logs2")")" = "$key" ] && echo да || echo нет) $([ -d "$logs" ] && echo да || echo нет)" "E7: второй прогон той же копии — тот же TMPDIR, логи первого на месте"
else
    skip "нет kacho scripts/ci-local.sh ($CILOCAL) — E7 настоящим потребителем не построен"
fi

# Уборка — отдельным шагом по возрасту, а не выходом слота: не тронутый > 7 суток
# снимается, моложе — остаётся, занятый слотом — остаётся при любом возрасте.
mkdir -p "$HEAVY_SLOT_DIR/tmp/old" "$HEAVY_SLOT_DIR/tmp/young" "$HEAVY_SLOT_DIR/tmp/busy" "$HEAVY_SLOT_DIR/active"
touch -d '8 days ago' "$HEAVY_SLOT_DIR/tmp/old" "$HEAVY_SLOT_DIR/tmp/busy"; touch -d '6 days ago' "$HEAVY_SLOT_DIR/tmp/young"
printf 'class=ci-local\nbudget=1\npid=%s\npid_start=%s\ntmp=%s\n' "$$" "$(awk '{ print $22 }' /proc/$$/stat)" "$HEAVY_SLOT_DIR/tmp/busy" > "$HEAVY_SLOT_DIR/active/probe-busy.slot"
rc="$(slot bash "$SLOT" --prune-tmp)"
assert "0 нет да да" "$rc $([ -d "$HEAVY_SLOT_DIR/tmp/old" ] && echo да || echo нет) $([ -d "$HEAVY_SLOT_DIR/tmp/young" ] && echo да || echo нет) $([ -d "$HEAVY_SLOT_DIR/tmp/busy" ] && echo да || echo нет)" "--prune-tmp: 8 суток — снят, 6 — оставлен, занятый слотом — оставлен"
rm -rf "$HEAVY_SLOT_DIR/active/probe-busy.slot" "$HEAVY_SLOT_DIR/tmp/young" "$HEAVY_SLOT_DIR/tmp/busy"

echo "── слот занят — код 74 СРАЗУ, ожидание только явным --wait ≤ 300 с (ws#1004)"
# Решение владельца 2026-10-11 «максимальная оперативность и минимум простоя»: ожидание
# слота в переднем плане — 116,4 агент-ч замера ws#1001. Без --wait занятый слот
# отвечает кодом 74 за доли секунды; ручка ожидания проб снята (-u HEAVY_SLOT_WAIT_S) —
# вызов тот же, что у агента.
HEAVY_SLOT_BUDGET_MIB=250 bash "$SLOT" docker -- sleep 5 2>/dev/null & A=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do ls "$HEAVY_SLOT_DIR"/active/*.slot >/dev/null 2>&1 && break; sleep 0.2; done
t0="$(date +%s%N)"
rc="$(slot -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_BUDGET_MIB=200 bash "$SLOT" docker -- touch "$W/b1")"
ms=$(( ($(date +%s%N) - t0) / 1000000 ))
assert "74 да да нет" "$rc $(has "$W/err" 'СЛОТ ЗАНЯТ, очередь 0') $([ "$ms" -lt 2000 ] && echo да || echo "нет(${ms}мс)") $([ -e "$W/b1" ] && echo да || echo нет)" "все слоты заняты — код 74 за < 2 с, «слот занят, очередь K» названо, команда не запускалась"
assert "busy" "$(grep -o ' busy ' "$HEAVY_SLOT_DIR/journal.log" | tr -d ' ' | head -n 1)" "занятость записана в журнал"
assert "0 да" "$(slot -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_BUDGET_MIB=20 bash "$SLOT" docker -- touch "$W/b2") $([ -e "$W/b2" ] && echo да || echo нет)" "близнец: малый слот влезает рядом — выдан сразу, без ожидания"
# Счёт ожидания — в целых секундах: «~1 с» бывает и долей секунды на границе.
rc="$(slot -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_BUDGET_MIB=200 bash "$SLOT" --wait 1 docker -- touch "$W/b3")"
assert "75 да нет" "$rc $(has "$W/err" 'не выдан за') $([ -e "$W/b3" ] && echo да || echo нет)" "--wait 1 при занятом — ожидание истекло: 75 (не 74), команда не запускалась"
wait "$A"
assert "0 да" "$(slot -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_BUDGET_MIB=200 bash "$SLOT" --wait 2 docker -- touch "$W/b4") $([ -e "$W/b4" ] && echo да || echo нет)" "близнец: --wait 2 при свободном — выдан сразу"
assert "64 да" "$(slot bash "$SLOT" --wait 301 docker -- true) $(has "$W/err" 'целое от 0 до 300')" "--wait 301 — 64: дольше 300 с вызов не ждёт"
assert "64 да" "$(slot bash "$SLOT" --wait 2400 docker -- true) $(has "$W/err" 'целое от 0 до 300')" "--wait 2400 (прежние 1800+) — 64"
assert 64 "$(slot bash "$SLOT" --wait x docker -- true)" "--wait без числа — 64"
assert "0 да" "$(slot bash "$SLOT" --wait 300 docker -- touch "$W/b5") $([ -e "$W/b5" ] && echo да || echo нет)" "близнец: --wait 300 — законная граница"
assert "64 да" "$(slot HEAVY_SLOT_WAIT_S=301 bash "$SLOT" docker -- true) $(has "$W/err" 'больше 300 с')" "ручка проб HEAVY_SLOT_WAIT_S=301 — 64: и проба дольше не ждёт"

echo "── --enqueue: долгое ожидание — ОДНИМ билетом отсоединённо, а не перезапуском (урок 2026-10-16, ws#1110)"
# Пять попыток newman за час слота не получили: перезапуск на 74/75 ставил билет в
# конец очереди. Поставленное задание держит место всё ожидание: вошедший позже
# видит его впереди; код команды — в .rc под уникальным именем.
rcof() { sed -n 's/^ENQUEUED\tlog=[^\t]*\trc=\([^\t]*\)\t.*/\1/p' "$W/out"; }
await_rc() { local _; for _ in $(seq 1 80); do [ -s "$1" ] && break; sleep 0.25; done; cat "$1" 2>/dev/null || echo нет; }
HEAVY_SLOT_BUDGET_MIB=250 bash "$SLOT" docker -- sleep 4 2>/dev/null & A=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do ls "$HEAVY_SLOT_DIR"/active/*.slot >/dev/null 2>&1 && break; sleep 0.2; done
mkdir -p "$W/enq"
t0="$(date +%s%N)"
rc="$(slot -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_ENQ_S=40 HEAVY_SLOT_BUDGET_MIB=200 bash "$SLOT" --enqueue "$W/enq" docker -- touch "$W/q1")"
ms=$(( ($(date +%s%N) - t0) / 1000000 )); RC1="$(rcof)"
assert "0 да да нет" "$rc $([ "$ms" -lt 3000 ] && echo да || echo "нет(${ms}мс)") $(case "$RC1" in "$W/enq/hs-docker-"*.rc) echo да ;; *) echo "нет($RC1)" ;; esac) $([ -e "$RC1" ] && echo да || echo нет)" "занятый слот: --enqueue возвращает 0 «поставлено» за < 3 с, .rc под уникальным именем ещё не записан"
for _ in $(seq 1 20); do ls "$HEAVY_SLOT_DIR"/queue/* >/dev/null 2>&1 && break; sleep 0.2; done
assert "74 да" "$(slot -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_BUDGET_MIB=200 bash "$SLOT" docker -- true) $(has "$W/err" 'СЛОТ ЗАНЯТ, очередь 1')" "вошедший позже видит поставленное задание ВПЕРЕДИ (очередь 1): билет держится всё ожидание"
assert "да" "$(has "$W/err" 'ОДИН раз --enqueue')" "отказ 74 называет --enqueue и запрет перезапуска"
wait "$A"
assert "0 да" "$(await_rc "$RC1") $([ -e "$W/q1" ] && echo да || echo нет)" "слот освободился — поставленное задание исполнилось тем же билетом, код 0 в .rc"
rc="$(slot -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_ENQ_S=40 HEAVY_SLOT_BUDGET_MIB=200 bash "$SLOT" --enqueue "$W/enq" docker -- bash -c 'exit 7')"; RC2="$(rcof)"
assert "0 7 да" "$rc $(await_rc "$RC2") $([ "$RC2" != "$RC1" ] && echo да || echo нет)" "близнец: код команды доходит до .rc (7), имя второго задания другое"
assert "64 да" "$(slot bash "$SLOT" --queued "$W/enq/x" docker -- true) $(has "$W/err" 'внутренняя форма')" "--queued в переднем плане — 64: долгое ожидание только у отсоединённого ребёнка"
assert "64 да" "$(slot bash "$SLOT" --enqueue "$W/нет-такого" docker -- true) $(has "$W/err" 'каталог журналов')" "--enqueue в несуществующий каталог — 64"
assert "64 да" "$(slot bash "$SLOT" --enqueue "$W/enq" --wait 5 docker -- true) $(has "$W/err" 'не ставятся')" "--enqueue вместе с --wait — 64"

echo "── запись слота, чей держатель умер, снимается при следующем входе"
printf 'class=go-race\nbudget=999\npid=999999\npid_start=1\nunit=\nstart=1\nseq=0\n' > "$HEAVY_SLOT_DIR/active/1-999999.slot"
assert 0 "$(slot HEAVY_SLOT_BUDGET_MIB=300 bash "$SLOT" docker -- true)" "мёртвая запись не держит 999 МиБ: вход выдан"
assert "0 да" "$(entries) $(has "$HEAVY_SLOT_DIR/journal.log" ' reap id=1-999999')" "запись снята и снятие записано"
export HEAVY_SLOT_LIMIT_MIB=100000

# nslots — сколько слотов занято (записей *.slot).
nslots() { local n=0 f; for f in "$HEAVY_SLOT_DIR"/active/*.slot; do [ -e "$f" ] && n=$((n + 1)); done; echo "$n"; }

echo "── тяжёлых не больше трёх: третий входит, четвёртый — 74 (решение владельца 2026-10-02)"
for i in 1 2 3; do HEAVY_SLOT_BUDGET_MIB=20 bash "$SLOT" docker -- sleep 4 2>/dev/null & eval "N$i=\$!"; done
for _ in $(seq 1 25); do [ "$(nslots)" -ge 3 ] && break; sleep 0.2; done
assert 3 "$(nslots)" "три слота по 20 МиБ заняты разом — третий вошёл"
assert "74 да нет" "$(slot -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_BUDGET_MIB=20 bash "$SLOT" docker -- touch "$W/n4") $(has "$W/err" 'занято слотов 3 из 3') $([ -e "$W/n4" ] && echo да || echo нет)" "четвёртый — 74, причина названа, команда не запускалась (память при этом свободна)"
wait "$N1" "$N2" "$N3"
assert "0 да" "$(slot -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_BUDGET_MIB=20 bash "$SLOT" docker -- touch "$W/n4") $([ -e "$W/n4" ] && echo да || echo нет)" "близнец: слоты вышли — тот же четвёртый входит"

echo "── Σ бюджетов занятых + бюджет ≤ 3 × 10 ГиБ (здесь ручкой проб — 100 МиБ)"
HEAVY_SLOT_BUDGET_MIB=60 bash "$SLOT" docker -- sleep 4 2>/dev/null & A=$!
for _ in $(seq 1 25); do [ "$(nslots)" -ge 1 ] && break; sleep 0.2; done
assert "74 да" "$(slot -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_SLOTS_SUM_MIB=100 HEAVY_SLOT_BUDGET_MIB=50 bash "$SLOT" docker -- true) $(has "$W/err" 'бюджеты занятых')" "60 + 50 > 100 — 74, причина названа"
assert 0 "$(slot -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_SLOTS_SUM_MIB=100 HEAVY_SLOT_BUDGET_MIB=40 bash "$SLOT" docker -- true)" "близнец: 60 + 40 ≤ 100 — входит"
wait "$A"

echo "── вход только при свободных ≥ 15 ГиБ (решение владельца 2026-10-02)"
mem $(( 98304 - 15359 ))
assert "74 да" "$(slot -u HEAVY_SLOT_WAIT_S bash "$SLOT" docker -- true) $(has "$W/err" 'до старта')" "свободно 15359 МиБ < 15 ГиБ — 74 при потолке с запасом, причина названа"
mem $(( 98304 - 15360 ))
assert 0 "$(slot -u HEAVY_SLOT_WAIT_S bash "$SLOT" docker -- true)" "близнец: свободно ровно 15 ГиБ — входит"
mem 1000

echo "── потолок без ручки — 70 ГиБ: (MemTotal − MemAvailable) + бюджет ≤ 71680 МиБ"
mem $(( 71680 - 300 ))
assert 0 "$(slot -u HEAVY_SLOT_LIMIT_MIB -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_BUDGET_MIB=300 bash "$SLOT" docker -- true)" "71380 + 300 = 71680 — входит"
mem $(( 71680 - 299 ))
assert "74 да" "$(slot -u HEAVY_SLOT_LIMIT_MIB -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_BUDGET_MIB=300 bash "$SLOT" docker -- true) $(grep -qE 'потолка 70[.,]0 ГиБ' "$W/err" && echo да || echo нет)" "71381 + 300 > 71680 — 74, потолок 70 ГиБ назван"
mem 1000

echo "── предел ядра: systemd-run --user --scope, MemoryMax"
if systemd-run --user --scope --quiet --collect -p MemoryMax=32M -- true 2>/dev/null &&
   grep -qw memory "/sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/cgroup.controllers" 2>/dev/null; then
    assert 0 "$(slot HEAVY_SLOT_BUDGET_MIB=64 bash "$SLOT" docker -- python3 -c "$ALLOC" 16 0)" "16 МиБ под бюджетом 64 — код 0"
    assert "76 да" "$(slot HEAVY_SLOT_BUDGET_MIB=64 bash "$SLOT" docker -- python3 -c "$ALLOC" 256 0) $(has "$W/err" 'OOM в cgroup слота')" "256 МиБ под бюджетом 64 — 76, причина названа"
    assert "да" "$(grep -q 'limiter=systemd.*cut=OOM' <<<"$(grep ' leave ' "$HEAVY_SLOT_DIR/journal.log" | tail -n 1)" && echo да || echo нет)" "выход с пиком и причиной обрыва — в журнале"

    # Объявленный, но НЕ действующий предел: подставной systemd-run запускает
    # команду без cgroup. Слот обязан это увидеть по memory.max и уйти в запасной путь.
    mkdir -p "$W/shim"
    # shellcheck disable=SC2016  # текст подставного скрипта, а не раскрытие
    printf '#!/usr/bin/env bash\nwhile [ "$1" != -- ]; do shift; done; shift; exec "$@"\n' > "$W/shim/systemd-run"
    chmod +x "$W/shim/systemd-run"
    rc="$(slot PATH="$W/shim:$PATH" HEAVY_SLOT_BUDGET_MIB=64 bash "$SLOT" docker -- python3 -c "$ALLOC" 256 3)"
    assert "76 да да" "$rc $(has "$W/err" 'предел ядра НЕ в силе') $(has "$W/err" 'мягкий предел')" "предел объявлен, но не в силе — замечено по memory.max, команда всё равно оборвана"

    # Граница: systemd-run внутри скрипта в argv не виден — команда уходит в свой
    # scope, мимо предела слота. Держит её потолок сессии либо ничто.
    printf 'systemd-run --user --scope --quiet --collect cat /proc/self/cgroup\n' > "$W/escape.sh"
    rc="$(slot HEAVY_SLOT_BUDGET_MIB=64 bash "$SLOT" docker -- bash "$W/escape.sh")"
    boundary "0 нет" "$rc $(grep -q 'heavy-slot-' "$W/out" && echo да || echo нет)" "скрипт с systemd-run внутри — команда в чужом scope ($(sed 's#.*/##' "$W/out"))"

    echo "── scope, куда команда ушла сама, — память слота, без двойного резерва (хук kaname, pre-push:194)"
    # Команда слота уводит себя `systemd-run --scope` изнутри скрипта, как хук kaname.
    # Слот A (бюджет 300) держит в ушедшей scope 200 МиБ; второй (300) при потолке 1500
    # входит лишь тогда, когда эти 200 засчитаны слоту A: 1000 + ~90 + 300 ≤ 1500, а без
    # счёта 1000 + 300 + 300 > 1500.
    ESC='import os, sys, time; a = bytearray(int(sys.argv[1]) << 20); a[::4096] = b"x" * len(a[::4096]); open(sys.argv[3], "w").write(str(os.getpid())); time.sleep(float(sys.argv[2]))'
    # shellcheck disable=SC2016  # текст скрипта: $1…$3 раскрывает он
    printf 'exec systemd-run --user --scope --quiet --collect -- python3 -c %q "$1" "$2" "$3"\n' "$ESC" > "$W/esc.sh"
    esc() {  # esc <МиБ> <с> <метка> — слот A фоном, ждёт метку ушедшей scope
        rm -f "$3"; HEAVY_SLOT_LIMIT_MIB="${ESC_LIMIT:-1500}" HEAVY_SLOT_BUDGET_MIB=300 bash "$SLOT" docker -- bash "$W/esc.sh" "$1" "$2" "$3" 2>"$W/errE" & E=$!
        for _ in $(seq 1 50); do [ -s "$3" ] && break; sleep 0.2; done
    }
    esc 200 3 "$W/m1"
    assert "0 да" "$(slot -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_LIMIT_MIB=1500 HEAVY_SLOT_BUDGET_MIB=300 bash "$SLOT" docker -- true) $([ "$(sed -n 's/^0:://p' "/proc/$(cat "$W/m1")/cgroup" 2>/dev/null | grep -c 'heavy-slot-')" = 0 ] && echo да || echo нет)" "200 МиБ в ушедшей scope засчитаны слоту — второй входит; scope и вправду не cgroup слота"
    wait "$E"
    lv="$(grep ' leave ' "$HEAVY_SLOT_DIR/journal.log" | tail -n 2)"
    assert "да" "$(grep -qE 'escaped_peak=(19[0-9]|2[0-9][0-9])MiB' <<<"$lv" && echo да || echo нет)" "пик ушедшей scope — в журнале выхода слота (escaped_peak)"
    esc 0 3 "$W/m2"
    assert "74 да" "$(slot -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_LIMIT_MIB=1500 HEAVY_SLOT_BUDGET_MIB=300 bash "$SLOT" docker -- true) $(has "$W/err" 'СЛОТ ЗАНЯТ')" "близнец: ушедшая scope пуста — недобранное слота A полное, второй — 74"
    wait "$E"
    # Сторож машины снимает и ушедшую scope: её процессы не в unit слота.
    rm -f "$HEAVY_SLOT_DIR/guard-at"; ESC_LIMIT=1300 esc 0 30 "$W/m3"; mem 1400
    wait "$E"; rc=$?; mem 1000
    sleep 0.5
    assert "76 нет" "$rc $(kill -0 "$(cat "$W/m3" 2>/dev/null || echo 999999)" 2>/dev/null && echo да || echo нет)" "сторож машины: слот 76, процесс ушедшей scope снят"
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

    # docker не первым словом: подставляет `docker` из PATH команды (опыт ws#832).
    assert "0 100663296" "$(slot HEAVY_SLOT_BUDGET_MIB=96 bash "$SLOT" docker -- timeout 60 docker run --rm "$IMAGE" cat /sys/fs/cgroup/memory.max) $(tr -d '\n' < "$W/out")" "docker за timeout — тот же предел"
    assert "0 100663296" "$(slot HEAVY_SLOT_BUDGET_MIB=96 bash "$SLOT" docker -- bash -c "docker run --rm $IMAGE cat /sys/fs/cgroup/memory.max") $(tr -d '\n' < "$W/out")" "docker в bash -c — тот же предел"
    n="hs-probe-c-$$"
    assert "0 100663296 100663296" "$(slot HEAVY_SLOT_BUDGET_MIB=96 bash "$SLOT" docker -- docker create --name "$n" "$IMAGE" true) $(docker inspect -f '{{.HostConfig.Memory}} {{.HostConfig.MemorySwap}}' "$n" 2>/dev/null)" "docker create — предел в HostConfig"
    docker rm -f "$n" >/dev/null 2>&1
    assert "64 да" "$(slot HEAVY_SLOT_BUDGET_MIB=96 bash "$SLOT" docker -- bash -c "docker run --rm -m 1g $IMAGE true") $(has "$W/err" 'несёт «-m»')" "свой -m у вложенного docker run — 64 от подмены"

    # Сторож машины снимает и контейнер: он потомок dockerd, смерть клиента его не
    # останавливает. «Оборвана» — только если остановлен и он: близнец с docker,
    # чей kill ничего не делает, обязан сказать, что контейнер РАБОТАЕТ.
    guarded() {  # guarded <имя контейнера> <stderr> [PATH=…] — код слота под перебором потолка
        rm -f "$HEAVY_SLOT_DIR/guard-at"; export HEAVY_SLOT_LIMIT_MIB=1300; mem 1000
        env ${3:+"$3"} HEAVY_SLOT_BUDGET_MIB=96 bash "$SLOT" docker -- bash -c "docker run --rm --name $1 $IMAGE sleep 30" 2>"$2" & local g=$!
        for _ in $(seq 1 50); do [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = true ] && break; sleep 0.2; done
        mem 1400; wait "$g"; local r=$?; mem 1000; export HEAVY_SLOT_LIMIT_MIB=100000
        echo "$r"
    }
    running() { grep -qx true <<<"$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" && echo да || echo нет; }
    n="hs-probe-g-$$"
    rc="$(guarded "$n" "$W/errG")"
    assert "76 да нет" "$rc $(has "$W/errG" 'контейнеры слота остановлены') $(running "$n")" "сторож машины: 76, контейнер из bash -c снят, сказано"
    docker rm -f "$n" >/dev/null 2>&1
    mkdir -p "$W/nokill"
    # shellcheck disable=SC2016  # текст подставного скрипта, а не раскрытие
    printf '#!/usr/bin/env bash\n[ "$1" = kill ] && exit 0\nexec %q "$@"\n' "$(command -v docker)" > "$W/nokill/docker"
    chmod +x "$W/nokill/docker"
    n="hs-probe-k-$$"
    rc="$(guarded "$n" "$W/errK" PATH="$W/nokill:$PATH")"
    assert "76 да нет да" "$rc $(has "$W/errK" 'РАБОТАЮТ') $(has "$W/errK" 'контейнеры слота остановлены') $(running "$n")" "близнец: kill не остановил — «работают», а не «остановлены»"
    docker rm -f "$n" >/dev/null 2>&1
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

echo "── внешний кластер: тяжёлый класс уходит в run.sh, локально — только с причиной (ws#984)"
# Двойник run.sh пишет свой argv и отвечает на --available кодом FAKE_AVAIL; клон —
# настоящий git с origin вида PRO-Robotech/kaname и веткой 984-x.
cat > "$W/fake-run.sh" <<'FAKE'
#!/usr/bin/env bash
if [ "${1:-}" = --available ]; then
    printf '%s\n' "$@" > "$FAKE_ARGV.avail"
    [ "${FAKE_AVAIL:-0}" = 0 ] && exit 0
    [ "${FAKE_AVAIL:-0}" = 2 ] && { echo "remote-heavy: открытого для планирования узла нет (узлов 2: закрыты для планирования 2)" >&2; exit 69; }
    [ "${FAKE_AVAIL:-0}" = 3 ] && { echo "remote-heavy: идущих тяжёлых прогонов 2 из 2" >&2; exit 75; }
    [ "${FAKE_AVAIL:-0}" = 4 ] && { sleep 30; exit 0; }
    if [ "${FAKE_AVAIL:-0}" = 5 ]; then
        [ -e "$FAKE_ARGV.busy" ] && exit 0
        touch "$FAKE_ARGV.busy"; echo "remote-heavy: кластер занят: идущих тяжёлых прогонов 2 при пределе 2" >&2; exit 75
    fi
    echo "remote-heavy: кластер не отвечает" >&2; exit 69
fi
printf '%s\n' "$@" > "$FAKE_ARGV"; exit 17
FAKE
R="$W/rclone"
# shellcheck source=lib/sandbox-git-home.sh
. "$HERE/lib/sandbox-git-home.sh"
sandbox_git_home "$W/ghome" || { echo "  [VOID] корневой подписи нет — клон маршрута не построен" >&2; exit 2; }
git init -q -b 984-x "$R"
git -C "$R" remote add origin https://github.com/PRO-Robotech/kaname.git
echo a > "$R/f"; git -C "$R" add f; sandbox_git -C "$R" commit -q -m p
mkdir -p "$R/sub"; echo b > "$R/sub/g"; git -C "$R" add sub; sandbox_git -C "$R" commit -q -m p2
rslot() { (cd "${RDIR:-$R}" && env HEAVY_SLOT_REMOTE_RUN="$W/fake-run.sh" FAKE_ARGV="$W/argv" "$@" 2> "$W/err" > "$W/out"); echo $?; }
rm -f "$W/argv"
assert "17 да" "$(RDIR="$R/sub" rslot bash "$SLOT" lint -- go version) $(has "$W/argv" '--profile')" "lint с go в чистом клоне → run.sh, его код (17)"
assert "--available --profile lint" "$(tr '\n' ' ' < "$W/argv.avail" | sed 's/ $//')" "проверка кластера несёт профиль класса — размещение судится под его запрос (ws#991)"
assert "984 kaname sub $(git -C "$R" rev-parse HEAD)" "$(sed -n '/^--task$/{n;p}' "$W/argv") $(sed -n '/^--repo$/{n;p}' "$W/argv") $(sed -n '/^--workdir$/{n;p}' "$W/argv") $(sed -n '/^--ref$/{n;p}' "$W/argv")" "задача из ветки, repo из origin, каталог и коммит — в argv"
assert "go version" "$(sed -n '/^--$/,$p' "$W/argv" | sed 1d | tr '\n' ' ' | sed 's/ $//')" "команда передана после «--» без искажения"
rm -f "$W/argv"
assert "0 да нет" "$(FAKE_AVAIL=1 rslot bash "$SLOT" lint -- go version) $(has "$W/err" 'локально — кластер недоступен') $([ -e "$W/argv" ] && echo да || echo нет)" "кластер не отвечает → локально, причина названа"
rm -f "$W/argv"
assert "0 да нет" "$(FAKE_AVAIL=2 rslot bash "$SLOT" go-race -- go version) $(has "$W/err" 'локально — кластер недоступен: открытого для планирования узла нет') $([ -e "$W/argv" ] && echo да || echo нет)" "открытого узла нет → локально сразу, причина названа (ws#991)"
rm -f "$W/argv"
assert "0 да нет" "$(rslot bash "$SLOT" ci-local -- git status) $(has "$W/err" 'внешнего пути не имеет') $([ -e "$W/argv" ] && echo да || echo нет)" "git первым словом (pre-push) → локально, причина названа"
echo c >> "$R/f"
printf 'all:\n\t@touch "%s"\n' "$W/dirty-ran" > "$W/dirty.mk"
assert "77 да нет нет" "$(rslot bash "$SLOT" go-race -- make -s -f "$W/dirty.mk") $(has "$W/err" 'во внешний кластер: закоммить правки') $([ -e "$W/argv" ] && echo да || echo нет) $([ -e "$W/dirty-ran" ] && echo да || echo нет)" "правка в отслеживаемом файле при доступном кластере → 77 «во внешний кластер: …», команда не запускалась (ws#1105)"
rm -f "$W/argv"
assert "0 да" "$(FAKE_AVAIL=1 rslot bash "$SLOT" go-race -- make -v) $(has "$W/err" 'локально — кластер недоступен')" "близнец: та же правка при недоступном кластере → локально, причина названа"
git -C "$R" checkout -q -- f
assert "17 да" "$(rslot bash "$SLOT" go-race -- timeout 60 make -v) $(has "$W/argv" 'go-race')" "близнец: тот же клон без правки, timeout перед make → run.sh"
rm -f "$W/argv"
assert "0 нет нет" "$(rslot bash "$SLOT" docker -- true) $(has "$W/err" 'локально') $([ -e "$W/argv" ] && echo да || echo нет)" "класс docker маршрут не судит: ни run.sh, ни строки"
assert "64 да" "$(cd "$R" && env "${REAL[@]}" HEAVY_SLOT_REMOTE_RUN="$W/fake-run.sh" bash "$SLOT" lint -- go version 2>"$W/err" >/dev/null; echo $?) $(has "$W/err" 'HEAVY_SLOT_REMOTE_RUN')" "над настоящей памятью двойник run.sh — ручка, 64"

echo "── тяжёлое только во внешнем кластере, локально — по доказательству недоступности (ws#1105)"
# Решение владельца 2026-10-16: «тяжелые тесты только на внешнем кластере, если он
# недоступен тогда локально». Доказательство — вывод проверки кластера в журнале слота.
JL="$HEAVY_SLOT_DIR/journal.log"
# shellcheck disable=SC2016  # тело `bash -c` раскрывает дочерняя оболочка
jn() { grep -cF -- "$1" "$JL" 2>/dev/null || true; }
b="$(jn ' local class=lint proof=rc=69 remote-heavy: кластер не отвечает')"
assert "0 $((b + 1))" "$(FAKE_AVAIL=1 rslot bash "$SLOT" lint -- go version) $(jn ' local class=lint proof=rc=69 remote-heavy: кластер не отвечает')" "недоступен → локально, вывод проверки (код и причина) записан в журнал строкой local … proof="
# Занятость — не недоступность (решение диспетчера 2026-10-16): ожидание места в
# пределах --wait, затем 74/75; локально команда НЕ идёт ни в каком исходе.
printf 'all:\n\t@touch "%s"\n' "$W/busy-ran" > "$W/busy.mk"
b="$(jn ' local class=lint ')"; bb="$(jn ' busy-external class=lint waited=')"
rm -f "$W/argv"
assert "75 нет нет да $b $((bb + 1))" "$(FAKE_AVAIL=3 rslot bash "$SLOT" lint -- make -s -f "$W/busy.mk") $([ -e "$W/busy-ran" ] && echo да || echo нет) $([ -e "$W/argv" ] && echo да || echo нет) $(has "$W/err" 'кластер занят') $(jn ' local class=lint ') $(jn ' busy-external class=lint waited=')" "занят (75) при --wait (проба: 2 с) → 75 после ожидания, локально НЕ запускалось, строки local нет, busy-external в журнале"
assert "74 нет" "$(FAKE_AVAIL=3 rslot env HEAVY_SLOT_WAIT_S=0 bash "$SLOT" lint -- make -s -f "$W/busy.mk") $([ -e "$W/busy-ran" ] && echo да || echo нет)" "занят без ожидания → 74 сразу, локально НЕ запускалось"
rm -f "$W/argv" "$W/argv.busy"
assert "17 да" "$(FAKE_AVAIL=5 rslot bash "$SLOT" lint -- go version) $(has "$W/argv" '--profile')" "близнец: занят на первом опросе, свободен на втором в пределах --wait → run.sh (17)"
t0="$(date +%s)"
r="$(FAKE_AVAIL=4 rslot bash "$SLOT" lint -- go version)"
assert "0 да да" "$r $(has "$W/err" 'не ответила за 10 с') $([ $(( $(date +%s) - t0 )) -lt 20 ] && echo да || echo нет)" "проверка кластера висит → прервана за 10 с, локально, причина названа"
b="$(jn ' local class=ci-local proof=')"; bw="$(jn ' local class=ci-local why=команда «git»')"
assert "0 $b $((bw + 1))" "$(rslot bash "$SLOT" ci-local -- git status) $(jn ' local class=ci-local proof=') $(jn ' local class=ci-local why=команда «git»')" "близнец: хук отправки (git push) внешнего пути не имеет — локально без опроса кластера, без proof, причина в журнале"
rm -f "$W/argv" "$W/argv.avail"
assert "77 да нет нет" "$(rslot bash "$SLOT" stand -- bash -c 'touch "$1"' x "$W/st1" dev-up) $(has "$W/err" 'во внешний кластер: в deploy/ продукта make stand-ns-up NS=t984-') $([ -e "$W/st1" ] && echo да || echo нет) $([ -e "$W/argv" ] && echo да || echo нет)" "стенд: dev-up при доступном кластере → 77 с формой своего ns, команда не запускалась"
assert "--available" "$(tr '\n' ' ' < "$W/argv.avail" | sed 's/ $//')" "стенд судит кластер без профиля: стенд ставит stand-ns.sh, не Job профиля"
# Двойник kind: настоящий kind проба не зовёт и при регрессии маршрута — узел не поднимется.
mkdir -p "$W/bin"; printf '#!/usr/bin/env bash\ntouch "%s"\n' "$W/kind-ran" > "$W/bin/kind"; chmod +x "$W/bin/kind"
assert "77 да нет" "$(rslot bash "$SLOT" stand -- "$W/bin/kind" -q create cluster) $(has "$W/err" 'во внешний кластер') $([ -e "$W/kind-ran" ] && echo да || echo нет)" "стенд: kind -q create при доступном кластере → 77 (флаг между kind и create не уводит), kind не запускался"
b="$(jn ' local class=stand proof=rc=69')"
assert "0 да $((b + 1))" "$(FAKE_AVAIL=1 rslot bash "$SLOT" stand -- bash -c 'touch "$1"' x "$W/st2" own-up) $([ -e "$W/st2" ] && echo да || echo нет) $(jn ' local class=stand proof=rc=69')" "стенд: own-up при недоступном кластере → локально, вывод проверки в журнале"
rm -f "$W/argv.avail"
assert "0 да нет" "$(rslot bash "$SLOT" stand -- bash -c 'touch "$1"' x "$W/st3" stand-ns-up) $([ -e "$W/st3" ] && echo да || echo нет) $([ -e "$W/argv.avail" ] && echo да || echo нет)" "близнец: stand-ns-up (внешний путь) маршрут не судит — идёт, кластер не спрашивается"
echo "── --local на ПЕРЕНОСИМОЙ команде в чистом клоне при доступном кластере (мутант G — ws#1105)"
rm -f "$W/argv" "$W/argv.avail"
assert "17" "$(rslot bash "$SLOT" lint -- go version)" "контроль: go version без флага в чистом клоне → run.sh (17)"
b="$(jn ' bypass-local class=lint why=проба G: переносимая команда локально')"
rm -f "$W/argv" "$W/argv.avail"
assert "0 нет нет $((b + 1))" "$(rslot bash "$SLOT" --local 'проба G: переносимая команда локально' lint -- go version) $([ -e "$W/argv" ] && echo да || echo нет) $([ -e "$W/argv.avail" ] && echo да || echo нет) $(jn ' bypass-local class=lint why=проба G: переносимая команда локально')" "та же команда с --local → локально (0), кластер не спрашивался, bypass-local в журнале"
(cd "$R" && bash "$SLOT" --status > "$W/status" 2>/dev/null)
assert "да" "$(has "$W/status" 'why=проба G: переносимая команда локально')" "обход G виден в --status"
assert 64 "$(rslot bash "$SLOT" lint --local 'проба: флаг после класса' -- go version)" "--local после класса — 64 (форма вызова), не тихий локальный запуск"
b="$(jn 'why=проба переноса строки вторая строка')"
assert "0 $((b + 1)) 0" "$(rslot bash "$SLOT" --local $'проба переноса строки\nвторая строка' --wait 0 newman -- true) $(jn 'why=проба переноса строки вторая строка') $(grep -c '^вторая строка' "$JL")" "причина с переводом строки — одна строка журнала, вторая строкой журнала не стала"

echo "── обёртки: нагрузка судится за ними, неопознанная при доступном кластере — 77 (ws#1105)"
for wr in "env GOFLAGS=-count=1" "nice -n 5" "ionice -c 3" "timeout -s KILL 60" "nohup" "stdbuf -oL" "setsid" "env -u GOFLAGS nice"; do
    rm -f "$W/argv"
    # shellcheck disable=SC2086  # обёртка — слова
    assert "17 да" "$(rslot bash "$SLOT" lint -- $wr go version) $(has "$W/argv" '--profile')" "«$wr go version» → run.sh: обёртка не уводит переносимое локально"
done
rm -f "$W/argv" "$W/wr-ran"
# shellcheck disable=SC2016  # тело `bash -c` раскрывает дочерняя оболочка
for wr in "bash -c" "nice -n 5 bash -c" "env FOO=1 sh -c" "bash -ec"; do
    # shellcheck disable=SC2086
    assert "77 нет да нет" "$(rslot bash "$SLOT" go-race -- $wr 'touch "$0"' "$W/wr-ran") $([ -e "$W/wr-ran" ] && echo да || echo нет) $(has "$W/err" 'не опознана') $([ -e "$W/argv" ] && echo да || echo нет)" "«$wr '…'» при доступном кластере → 77 с подсказкой, локально НЕ запускалось"
done
assert "77 нет" "$(rslot bash "$SLOT" go-race -- env -C "$R" touch "$W/wr-ran") $([ -e "$W/wr-ran" ] && echo да || echo нет)" "ключ обёртки вне разбора (env -C) при доступном кластере → 77, не локально"
printf '#!/usr/bin/env bash\ntouch "%s"\n' "$W/wr-ran" > "$W/custom.sh"; chmod +x "$W/custom.sh"
assert "77 нет" "$(rslot bash "$SLOT" integration -- "$W/custom.sh") $([ -e "$W/wr-ran" ] && echo да || echo нет)" "иная команда (скрипт) тяжёлого класса при доступном кластере → 77, не локально"
b="$(jn ' local class=go-race proof=rc=69')"
assert "0 да $((b + 1))" "$(FAKE_AVAIL=1 rslot bash "$SLOT" go-race -- bash -c 'touch "$0"' "$W/wr-ran") $([ -e "$W/wr-ran" ] && echo да || echo нет) $(jn ' local class=go-race proof=rc=69')" "близнец: та же строка bash -c при недоступном кластере → локально, proof в журнале"
rm -f "$W/wr-ran"
assert "75 нет" "$(FAKE_AVAIL=3 rslot bash "$SLOT" go-race -- bash -c 'touch "$0"' "$W/wr-ran") $([ -e "$W/wr-ran" ] && echo да || echo нет)" "строка bash -c при занятом кластере → 75, не локально"

echo "── стенд: относительный путь, цель через переменную"
mkdir -p "$W/kd"; printf '#!/usr/bin/env bash\ntouch "%s"\n' "$W/cc-ran" > "$W/kd/create-cluster.sh"; chmod +x "$W/kd/create-cluster.sh"
assert "77 нет" "$(RDIR="$W/kd" rslot bash "$SLOT" stand -- ./create-cluster.sh) $([ -e "$W/cc-ran" ] && echo да || echo нет)" "./create-cluster.sh (относительный путь) при доступном кластере → 77, не запускался"
assert "77 нет" "$(RDIR="$W/kd" rslot bash "$SLOT" stand -- bash create-cluster.sh) $([ -e "$W/cc-ran" ] && echo да || echo нет)" "bash create-cluster.sh при доступном кластере → 77"
printf 'dev-up:\n\t@touch "%s"\ndev-down:\n\t@touch "%s"\n' "$W/mv-ran" "$W/dd-ran" > "$W/kd/mk"
# shellcheck disable=SC2016
assert "77 нет" "$(RDIR="$W/kd" rslot env G=dev-up bash "$SLOT" stand -- bash -c 'make -s -f mk "$G"') $([ -e "$W/mv-ran" ] && echo да || echo нет)" "цель make через переменную в строке оболочки при доступном кластере → 77, не запускалась"
# shellcheck disable=SC2016
assert "0 да" "$(RDIR="$W/kd" FAKE_AVAIL=1 rslot env G=dev-up bash "$SLOT" stand -- bash -c 'make -s -f mk "$G"') $([ -e "$W/mv-ran" ] && echo да || echo нет)" "близнец: та же строка при недоступном кластере → локально"
assert "0 да нет" "$(RDIR="$W/kd" rslot bash "$SLOT" stand -- make -s -f mk dev-down) $([ -e "$W/dd-ran" ] && echo да || echo нет) $(has "$W/err" 'во внешний кластер')" "близнец: снятие локального стенда (dev-down) маршрут не судит — идёт"

git init -q -b nodigits "$W/rclone2"; git -C "$W/rclone2" remote add origin https://github.com/PRO-Robotech/kacho.git
echo a > "$W/rclone2/f"; git -C "$W/rclone2" add f; sandbox_git -C "$W/rclone2" commit -q -m p
assert "77 да" "$(RDIR="$W/rclone2" rslot bash "$SLOT" integration -- go version) $(has "$W/err" 'KACHO_TASK=<N>')" "номер задачи не выводится при доступном кластере → 77 с формой KACHO_TASK"
assert "17" "$(RDIR="$W/rclone2" rslot env KACHO_TASK=1105 bash "$SLOT" integration -- go version)" "близнец: тот же клон с KACHO_TASK → run.sh"
echo c >> "$R/f"
assert 64 "$(rslot bash "$SLOT" --local коротко go-race -- true)" "--local без причины (< 12 символов) — 64"
b="$(jn ' bypass-local class=go-race why=проба обхода: стенд снят владельцем')"
rm -f "$W/argv" "$W/argv.avail"
assert "0 нет нет $((b + 1))" "$(rslot bash "$SLOT" --local 'проба обхода: стенд снят владельцем' go-race -- true) $([ -e "$W/argv" ] && echo да || echo нет) $([ -e "$W/argv.avail" ] && echo да || echo нет) $(jn ' bypass-local class=go-race why=проба обхода: стенд снят владельцем')" "--local с причиной при доступном кластере и правке → локально, кластер не спрашивается, причина в журнале"
# Чтение и поиск разведены: `grep -q` в конце трубы под pipefail рвёт писателя (ws#395).
(cd "$R" && bash "$SLOT" --status > "$W/status" 2>/dev/null)
assert "да" "$(has "$W/status" 'локально по флагу --local')" "обход флагом виден в --status"
rslot bash "$SLOT" --local 'проба обхода: запись слота' --wait 0 newman -- bash -c 'sleep 3' >/dev/null &
LP=$!
for _ in $(seq 1 25); do ls "$HEAVY_SLOT_DIR"/active/*.slot >/dev/null 2>&1 && break; sleep 0.2; done
(cd "$R" && bash "$SLOT" --status > "$W/status" 2>/dev/null)
assert "да" "$(has "$W/status" 'локально по флагу: проба обхода: запись слота')" "занятый слот с --local показывает причину в --status"
wait "$LP"
git -C "$R" checkout -q -- f

echo "[CENSUS] heavy-slot: утверждений $((pass + fail)), сошлось $pass, разошлось $fail; граница (не ловится, заявлено в шапке) $bound; не построено частей $void"
[ "$fail" -eq 0 ] || exit 1
[ "$void" -eq 0 ] || exit 2
exit 0
