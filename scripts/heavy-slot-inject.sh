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
#
# КОНВЕЙЕР ЭТУ ПРОБУ НЕ ЗОВЁТ — граница (ws#1115): три её части судят машину, а не
# дерево. Близнец общего каталога входит над НАСТОЯЩЕЙ памятью (свободных ≥ 15 ГиБ —
# FREE_MIN_MIB heavy-slot.sh — и свободный слот), предел ядра — systemd --user с
# контроллером memory, docker — образ HEAVY_SLOT_PROBE_IMAGE. Ранер ubuntu-latest
# публичного репозитория — 16 ГБ памяти всего (документация площадки): близнец там 74,
# часть «не построена», код 2, и шаг задания краснел бы на каждом прогоне. Время не
# мешало бы: 189 с здесь (2026-10-16, копия полосы, load average 12–26; код 2 —
# близнец 74 при трёх занятых слотах соседей, E7 без project/kacho рядом с копией;
# утверждений 190 из 190); без systemd --user и образа — 171 с, код 2, не построено 3,
# утверждений 173 из 173 (`env -u XDG_RUNTIME_DIR -u DBUS_SESSION_BUS_ADDRESS
# HEAVY_SLOT_PROBE_IMAGE=<нет такого> bash scripts/heavy-slot-inject.sh`).
# Держится ВНИМАНИЕМ автора правки heavy-slot* и приёмки check-verifier. Предикат
# снятия — ранер со свободными ≥ 15 ГиБ при старте задания: тогда — шаг задания
# `bats-and-shellcheck`, создающий образ и сеанс systemd --user, без послабления кода 2.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SLOT="$HERE/heavy-slot.sh"
IMAGE="${HEAVY_SLOT_PROBE_IMAGE:-python:3.13-slim}"
W="$(mktemp -d)"
# shellcheck disable=SC2154
trap '_rc=$?; rm -rf "$W" 2>/dev/null || rm -rf "$W" || echo "ПРЕДУПРЕЖДЕНИЕ: временный каталог $W не снят; код проверки $_rc сохранён" >&2; exit $_rc' EXIT

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
# qlen — сколько ЖИВЫХ билетов в очереди: отложенные 74/75 (resume_until=) тоже лежат в
# queue/, но не ждут. Пробы ждут постановки билета этим счётом, а не сном: сон под
# нагрузкой машины не успевал (урок 2026-10-16).
qlen() { local n=0 f; for f in "$HEAVY_SLOT_DIR"/queue/*; do [ -e "$f" ] && ! grep -q '^resume_until=' "$f" && n=$((n + 1)); done; echo "$n"; }
# nslots — сколько слотов занято (записей *.slot).
nslots() { local n=0 f; for f in "$HEAVY_SLOT_DIR"/active/*.slot; do [ -e "$f" ] && n=$((n + 1)); done; echo "$n"; }

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
# Заданный вызывающим ssh без keepalive (цепочки tmp/autoland, уроки 6fb9cbf3 и 789e4f3d: 141
# после зелёного хука) — keepalive ДОПИСЫВАЕТСЯ за его опциями: у ssh побеждает первое значение
# опции, поэтому своё вызывающего сильнее; свой keepalive и не-ssh команда — не трогаются.
assert "0 да" "$(slot GIT_SSH_COMMAND='ssh -o Своё=1' bash "$SLOT" ci-local -- sh -c 'printf %s "$GIT_SSH_COMMAND" > "$0"' "$W/ssh2") $([ "$(cat "$W/ssh2")" = 'ssh -o Своё=1 -o ServerAliveInterval=30 -o ServerAliveCountMax=40' ] && echo да || echo нет)" "заданный вызывающим ssh без keepalive — его опции первыми, keepalive дописан"
assert "0 да" "$(slot GIT_SSH_COMMAND='/usr/bin/ssh -i k' bash "$SLOT" ci-local -- sh -c 'printf %s "$GIT_SSH_COMMAND" > "$0"' "$W/ssh2b") $(grep -q '^/usr/bin/ssh -i k -o ServerAliveInterval=30' "$W/ssh2b" && echo да || echo нет)" "ssh полным путём без keepalive — дописан"
assert "0 да" "$(slot GIT_SSH_COMMAND='ssh -o serveraliveinterval=5' bash "$SLOT" ci-local -- sh -c 'printf %s "$GIT_SSH_COMMAND" > "$0"' "$W/ssh2c") $([ "$(cat "$W/ssh2c")" = 'ssh -o serveraliveinterval=5' ] && echo да || echo нет)" "близнец: свой keepalive вызывающего (регистр любой) — не переписан"
assert "0 да" "$(slot GIT_SSH_COMMAND='my-ssh-wrapper -x' bash "$SLOT" ci-local -- sh -c 'printf %s "$GIT_SSH_COMMAND" > "$0"' "$W/ssh2d") $([ "$(cat "$W/ssh2d")" = 'my-ssh-wrapper -x' ] && echo да || echo нет)" "близнец: не-ssh команда вызывающего — не переписана (опций ssh может не понять)"
# shellcheck disable=SC2016
assert "0 да" "$(slot -u GIT_SSH_COMMAND bash "$SLOT" docker -- sh -c 'printf %s "${GIT_SSH_COMMAND:-}" > "$0"' "$W/ssh3") $([ -s "$W/ssh3" ] && echo нет || echo да)" "близнец: класс не ci-local — GIT_SSH_COMMAND не ставится"
# Заданное вызывающим иначе, чем GIT_SSH_COMMAND, тоже сильнее: core.sshCommand копии
# (и из её подкаталога), глобального слоя, обёртка GIT_SSH — git предпочёл бы им
# поставленный слотом GIT_SSH_COMMAND. Вывод ребёнка пуст — слот не перекрыл.
git init -q "$W/gitc" && git -C "$W/gitc" config core.sshCommand 'ssh -o Своё=2' && mkdir -p "$W/gitc/sub" "$W/nogit"
printf '[core]\n\tsshCommand = ssh -o Своё=3\n' > "$W/gitglobal"
# kssh <файл> <каталог> [ENV=…] — ci-local из каталога, ребёнок пишет свой GIT_SSH_COMMAND.
# shellcheck disable=SC2016
kssh() { local f="$1" d="$2"; shift 2; (cd "$d" && slot -u GIT_SSH_COMMAND -u GIT_SSH "$@" bash "$SLOT" ci-local -- sh -c 'printf %s "${GIT_SSH_COMMAND:-}" > "$0"' "$f"); }
assert "0 да" "$(kssh "$W/ssh4" "$W/gitc") $([ -s "$W/ssh4" ] && echo нет || echo да)" "близнец: core.sshCommand копии — GIT_SSH_COMMAND не ставится"
assert "0 да" "$(kssh "$W/ssh5" "$W/gitc/sub") $([ -s "$W/ssh5" ] && echo нет || echo да)" "близнец: core.sshCommand копии из подкаталога — не ставится"
assert "0 да" "$(kssh "$W/ssh6" "$W/nogit" GIT_CONFIG_GLOBAL="$W/gitglobal") $([ -s "$W/ssh6" ] && echo нет || echo да)" "близнец: глобальный core.sshCommand — не ставится"
assert "0 да" "$(kssh "$W/ssh7" "$W/nogit" GIT_SSH=/bin/true) $([ -s "$W/ssh7" ] && echo нет || echo да)" "близнец: обёртка GIT_SSH вызывающего — GIT_SSH_COMMAND не ставится"
assert "0 да" "$(kssh "$W/ssh8" "$W/nogit" GIT_CONFIG_GLOBAL=/dev/null) $(grep -q 'ServerAliveInterval=30' "$W/ssh8" && echo да || echo нет)" "контроль тех же вызовов: вне копии, без своих настроек — keepalive ставится"

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
# Общий журнал пишут и соседние полосы машины: сравнение размера и времени (stat) краснело от чужой
# строки (2026-10-18, нагрузка 100+). Судится наше: строки журнала с путём этой пробы ($W/).
seen() { local n; n="$(grep -cF -- "$W/" "$SHARED/journal.log" 2>/dev/null)"; echo "${n:-0}"; }
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
printf 'dev-down:\n\t@touch "%s"\n' "$W/k5" > "$W/k5.mk"  # снятие стенда маршрут не судит (ws#1301)
rc="$(slot "${REAL[@]}" timeout 90 bash "$SLOT" stand -- make -s -f "$W/k5.mk" dev-down)"
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

echo "── очередь по билету: малый ОБГОНЯЕТ ждущего большего, которому места нет (ws#1161 д)"
# Прежняя редакция («малый не обгоняет ждущий большой») держала малые отправки позади go-race в
# 16 ГиБ при свободном месте. Обгон ограничен: BYPASS_MAX раз на ждущего, и не у того, кому места
# уже хватает. Держатель ждёт по событию (файл), а не по сну: под нагрузкой машины сон не успевал.
export HEAVY_SLOT_LIMIT_MIB=1300
# bphold <файл> — держатель слота (бюджет 200), живёт до появления файла.
# shellcheck disable=SC2016  # строка дочерней оболочки
bphold() { HEAVY_SLOT_BUDGET_MIB=200 bash "$SLOT" docker -- sh -c 'for _ in $(seq 1 900); do [ -e "$0" ] && break; sleep 0.1; done' "$1" 2>/dev/null & BPH=$!
           for _ in $(seq 1 50); do [ "$(nslots)" -ge 1 ] && break; sleep 0.2; done; }
rm -f "$W/hold-q" "$W/ov1"
bphold "$W/hold-q"
HEAVY_SLOT_WAIT_S=20 HEAVY_SLOT_BUDGET_MIB=250 bash "$SLOT" docker -- true 2>/dev/null & B=$!
for _ in $(seq 1 50); do [ "$(qlen)" -ge 1 ] && break; sleep 0.2; done
assert "0 да" "$(slot HEAVY_SLOT_BUDGET_MIB=50 bash "$SLOT" docker -- touch "$W/ov1") $([ -e "$W/ov1" ] && echo да || echo нет)" "малый (50) влезает по памяти, большой (250) впереди ждёт и сам не влезает → малый проходит"
gb250="$(grep -l '^budget=250$' "$HEAVY_SLOT_DIR"/queue/* | head -n 1)"; bp0="$(sed -n 's/^bypassed=//p' "$gb250")"
assert "75 да да" "$(slot HEAVY_SLOT_BUDGET_MIB=150 bash "$SLOT" docker -- true) $(has "$W/err" 'потолка') $([ "$(sed -n 's/^bypassed=//p' "$gb250")" = "$bp0" ] && echo да || echo нет)" "близнец: малый (150), которому в оставшееся место не уместиться, не проходит (ждёт памяти, причина названа) и обгоном не засчитан"
touch "$W/hold-q"; wait "$B"; rc_b=$?; wait "$BPH"
assert 0 "$rc_b" "большой дождался выхода держателя и вошёл"
assert 0 "$(slot HEAVY_SLOT_BUDGET_MIB=50 bash "$SLOT" docker -- true)" "близнец: очередь пуста — малый входит"
export HEAVY_SLOT_LIMIT_MIB=100000

echo "── голову очереди держит лишь билет, влезающий под свой потолок при пустых слотах"
# B3 круга 3: билет с потолком ниже занятого ждал до конца своего ожидания, и
# строгая очередь стояла за ним вся.
HEAVY_SLOT_BUDGET_MIB=200 bash "$SLOT" docker -- sleep 4 2>/dev/null & A=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do ls "$HEAVY_SLOT_DIR"/active/*.slot >/dev/null 2>&1 && break; sleep 0.2; done
HEAVY_SLOT_LIMIT_MIB=1100 HEAVY_SLOT_WAIT_S=6 HEAVY_SLOT_BUDGET_MIB=250 bash "$SLOT" docker -- touch "$W/q1" 2>"$W/errQ" & B=$!
for _ in $(seq 1 25); do [ "$(qlen)" -ge 1 ] && break; sleep 0.2; done
assert "0 да" "$(slot HEAVY_SLOT_BUDGET_MIB=50 bash "$SLOT" docker -- touch "$W/q2") $([ -e "$W/q2" ] && echo да || echo нет)" "впереди билет с потолком 1100 < 1000 + 250: голову не держит — малый (1000 + ~200 + 50 ≤ 1300) входит сразу (близнец — строгая очередь выше: потолок 1300, малый ждёт)"
wait "$A"; wait "$B"; rc_b=$?
assert "75 нет" "$rc_b $([ -e "$W/q1" ] && echo да || echo нет)" "сам билет с низким потолком — 75 по своему ожиданию, команда не запускалась"

echo "── lint по одному на машину, ci-local рядом с ним входит; ждущий линтер очередь не держит"
HEAVY_SLOT_BUDGET_MIB=50 bash "$SLOT" lint -- sleep 4 2>/dev/null & A=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do ls "$HEAVY_SLOT_DIR"/active/*.slot >/dev/null 2>&1 && break; sleep 0.2; done
HEAVY_SLOT_WAIT_S=2 HEAVY_SLOT_BUDGET_MIB=50 bash "$SLOT" lint -- true 2>"$W/errB" & B=$!
for _ in $(seq 1 25); do [ "$(qlen)" -ge 1 ] && break; sleep 0.2; done
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
assert "да" "$(has "$W/err" 'занято слотов 1 из 3 при постановке')" "постановка печатает занятость слотов сразу (1 из 3), а не по 74 следующего шага (ws#1225)"
# Ждать ЖИВОГО билета: отложенные 74/75 выше (resume_until) в очереди тоже лежат.
for _ in $(seq 1 20); do [ -n "$(grep -L '^resume_until=' "$HEAVY_SLOT_DIR"/queue/* 2>/dev/null)" ] && break; sleep 0.2; done
assert "74 да" "$(slot -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_BUDGET_MIB=200 bash "$SLOT" docker -- true) $(has "$W/err" 'СЛОТ ЗАНЯТ, очередь 1')" "вошедший позже видит поставленное задание ВПЕРЕДИ (очередь 1): билет держится всё ожидание"
assert "да" "$(has "$W/err" 'ОДИН раз --enqueue')" "отказ 74 называет --enqueue и запрет перезапуска"
wait "$A"
assert "0 да" "$(await_rc "$RC1") $([ -e "$W/q1" ] && echo да || echo нет)" "слот освободился — поставленное задание исполнилось тем же билетом, код 0 в .rc"
rc="$(slot -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_ENQ_S=40 HEAVY_SLOT_BUDGET_MIB=200 bash "$SLOT" --enqueue "$W/enq" docker -- bash -c 'exit 7')"; RC2="$(rcof)"
assert "0 7 да" "$rc $(await_rc "$RC2") $([ "$RC2" != "$RC1" ] && echo да || echo нет)" "близнец: код команды доходит до .rc (7), имя второго задания другое"
# Место держится ВСЁ ожидание, а не в миг постановки: снимок сразу после постановки
# слеп к ребёнку, который на каждом опросе перевзял бы билет и ушёл в конец (ровно урок
# 74/75). Два поставленных и ждущий в переднем плане (--wait, билет он не перевзимает)
# опрашивают несколько раз, пока держатель занят: ждущий на каждом опросе видит обоих
# впереди, а входят все по билету — E1, E2, затем он.
HEAVY_SLOT_BUDGET_MIB=250 bash "$SLOT" docker -- sleep 10 2>/dev/null & A=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do ls "$HEAVY_SLOT_DIR"/active/*.slot >/dev/null 2>&1 && break; sleep 0.2; done
# shellcheck disable=SC2016  # строка дочерней оболочки, $0 раскрывает она
rc1="$(slot -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_ENQ_S=60 HEAVY_SLOT_BUDGET_MIB=200 bash "$SLOT" --enqueue "$W/enq" docker -- sh -c 'date +%s%N > "$0"; sleep 1' "$W/o1")"; RO1="$(rcof)"
for _ in $(seq 1 20); do [ "$(qlen)" -ge 1 ] && break; sleep 0.2; done
# shellcheck disable=SC2016
rc2="$(slot -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_ENQ_S=60 HEAVY_SLOT_BUDGET_MIB=200 bash "$SLOT" --enqueue "$W/enq" docker -- sh -c 'date +%s%N > "$0"; sleep 1' "$W/o2")"; RO2="$(rcof)"
for _ in $(seq 1 20); do [ "$(qlen)" -ge 2 ] && break; sleep 0.2; done
# shellcheck disable=SC2016
env -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_BUDGET_MIB=200 bash "$SLOT" --wait 30 docker -- sh -c 'date +%s%N > "$0"' "$W/o3" 2> "$W/lerr" > /dev/null & L=$!
wait "$A"
wait "$L"; rcl=$?
ro1="$(await_rc "$RO1")"; ro2="$(await_rc "$RO2")"
# Опросы ждущего, пока держатель занят: строки до первого входа поставленного.
polls="$(grep -c 'ждёт слота' "$W/lerr")"
early="$(grep 'ждёт слота' "$W/lerr" | head -n 3)"
order() { [ -s "$W/o1" ] && [ -s "$W/o2" ] && [ -s "$W/o3" ] && [ "$(cat "$W/o1")" -lt "$(cat "$W/o2")" ] && [ "$(cat "$W/o2")" -lt "$(cat "$W/o3")" ] && echo да || echo "нет($(cat "$W/o1" "$W/o2" "$W/o3" 2>/dev/null | tr '\n' ' '))"; }
assert "0 0 0 0 0" "$rc1 $rc2 $ro1 $ro2 $rcl" "два поставленных и ждущий --wait: все трое исполнились, коды 0"
assert "да да" "$([ "$polls" -ge 3 ] && echo да || echo "нет($polls)") $([ "$(grep -c 'в очереди впереди 2' <<<"$early")" -eq 3 ] && echo да || echo "нет($(tr '\n' '|' <<<"$early"))")" "ждущий опрашивал ≥ 3 раз, и на каждом из первых трёх — «впереди 2»: поставленные билета не перевзяли"
assert "да" "$(order)" "вход по билету: E1, затем E2, затем ждущий, поставленный последним"
assert "64 да" "$(slot bash "$SLOT" --queued "$W/enq/x" docker -- true) $(has "$W/err" 'внутренняя форма')" "--queued в переднем плане — 64: долгое ожидание только у отсоединённого ребёнка"
assert "64 да" "$(slot bash "$SLOT" --enqueue "$W/нет-такого" docker -- true) $(has "$W/err" 'каталог журналов')" "--enqueue в несуществующий каталог — 64"
assert "64 да" "$(slot bash "$SLOT" --enqueue "$W/enq" --wait 5 docker -- true) $(has "$W/err" 'не ставятся')" "--enqueue вместе с --wait — 64"

echo "── повтор с --resume <билет> держит место в очереди до 120 с; без билета и просроченный — в конец (ws#1115)"
# order <файл> <метка> — команда слота: дописать метку (порядок входа).
tkof() { sed -n 's/.*--resume \([0-9][0-9]*\).*/\1/p' "$W/err" | head -n 1; }
# race <режим> — A держит слот; X получает 74 с билетом; N ждёт; X повторяет по режиму.
# shellcheck disable=SC2016  # строки `sh -c` раскрывает дочерняя оболочка
race() {
    rm -f "$W/order"
    # A держит 6 с: повтор X обязан встать в очередь, пока слот занят, — иначе
    # отложенный билет голову не держит и сосед входит в освободившийся слот.
    HEAVY_SLOT_BUDGET_MIB=250 bash "$SLOT" docker -- sleep 6 2>/dev/null & local a=$!
    for _ in $(seq 1 25); do ls "$HEAVY_SLOT_DIR"/active/*.slot >/dev/null 2>&1 && break; sleep 0.2; done
    local rx tk; rx="$(slot -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_BUDGET_MIB=200 bash "$SLOT" docker -- sh -c 'echo X >> "$0"' "$W/order")"; tk="$(tkof)"
    echo "$rx ${tk:-нет}" > "$W/rx"; TK="$tk"
    TF="$HEAVY_SLOT_DIR/queue/$(printf '%012d' "${TK:-0}")"
    [ "$1" = expired ] && [ -e "$TF" ] && sed -i "s/^resume_until=.*/resume_until=$(( $(date +%s) - 1 ))/" "$TF"
    HEAVY_SLOT_BUDGET_MIB=200 bash "$SLOT" --wait 15 docker -- sh -c 'echo N >> "$0"' "$W/order" 2>/dev/null & local n=$!
    sleep 0.6
    local rarg=(); [ "$1" != none ] && rarg=(--resume "${TK:-0}")
    HEAVY_SLOT_BUDGET_MIB=200 bash "$SLOT" "${rarg[@]}" --wait 15 docker -- sh -c 'echo X >> "$0"' "$W/order" 2>"$W/errR" & local x=$!
    wait "$a" "$n" "$x"
    tr '\n' ' ' < "$W/order" | sed 's/ $//'
}
o="$(race resume)"
read -r RX TK < "$W/rx"
assert "74 да X N" "$RX $([ "$TK" != нет ] && echo да || echo нет) $o" "74 называет билет; повтор --resume <билет> входит РАНЬШЕ соседа, вставшего после отказа"
o="$(race none)"
assert "N X" "$o" "близнец: повтор без билета — в конец очереди, сосед входит первым"
o="$(race expired)"
assert "N X да" "$o $(has "$W/errR" 'просрочен')" "просроченный билет (> 120 с) → в конец очереди, и это сказано"
HEAVY_SLOT_BUDGET_MIB=250 bash "$SLOT" docker -- sleep 3 2>/dev/null & A=$!
for _ in $(seq 1 25); do ls "$HEAVY_SLOT_DIR"/active/*.slot >/dev/null 2>&1 && break; sleep 0.2; done
rc="$(slot -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_BUDGET_MIB=200 bash "$SLOT" docker -- true)"; TK="$(tkof)"; TF="$HEAVY_SLOT_DIR/queue/$(printf '%012d' "${TK:-0}")"
ru="$(sed -n 's/^resume_until=//p' "$TF" 2>/dev/null)"; d=$(( ${ru:-0} - $(date +%s) ))
assert "74 да" "$rc $([ "$d" -ge 115 ] && [ "$d" -le 120 ] && echo да || echo "нет(${d}с)")" "билет 74 отложен на 120 с (resume_until в записи очереди)"
wait "$A"
assert "0 да" "$(slot -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_BUDGET_MIB=200 bash "$SLOT" docker -- touch "$W/rs1") $([ -e "$W/rs1" ] && echo да || echo нет)" "отложенный билет без владельца голову не держит: слот свободен — новый входит сразу"
assert "64 да" "$(slot bash "$SLOT" --resume x docker -- true) $(has "$W/err" '--resume')" "--resume не числом — 64"
nw="$(grep -c ' wait ' "$HEAVY_SLOT_DIR/journal.log")"
assert "да 0" "$([ "$nw" -gt 0 ] && echo да || echo нет) $(grep ' wait ' "$HEAVY_SLOT_DIR/journal.log" | grep -vc ' slots=.* free=\| free=.* slots=' || true)" "событие wait несёт slots и free (событий wait $nw, без полей — 0)"

echo "── запись слота, чей держатель умер, снимается при следующем входе"
printf 'class=go-race\nbudget=999\npid=999999\npid_start=1\nunit=\nstart=1\nseq=0\n' > "$HEAVY_SLOT_DIR/active/1-999999.slot"
assert 0 "$(slot HEAVY_SLOT_BUDGET_MIB=300 bash "$SLOT" docker -- true)" "мёртвая запись не держит 999 МиБ: вход выдан"
assert "0 да" "$(entries) $(has "$HEAVY_SLOT_DIR/journal.log" ' reap id=1-999999')" "запись снята и снятие записано"
export HEAVY_SLOT_LIMIT_MIB=100000

echo "── тяжёлых не больше трёх: третий входит, четвёртый — 74 (решение владельца 2026-10-02)"
# Трое стартуют разом и попадают друг другу в очередь: вход — по опросу (POLL_S=1), и под
# нагрузкой машины WAIT_S=2 не хватало третьему (74, «получено 1»). Держателям — ожидание 10 с
# и сон 6 с: утверждение то же — три слота заняты РАЗОМ, четвёртый при них — 74.
for i in 1 2 3; do HEAVY_SLOT_WAIT_S=10 HEAVY_SLOT_BUDGET_MIB=20 bash "$SLOT" docker -- sleep 6 2>/dev/null & eval "N$i=\$!"; done
for _ in $(seq 1 40); do [ "$(nslots)" -ge 3 ] && break; sleep 0.2; done
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

echo "── docker run: предел — контейнеру, флаги памяти вызова сверх бюджета — отказ"
if docker image inspect "$IMAGE" >/dev/null 2>&1; then
    assert "0 100663296" "$(slot HEAVY_SLOT_BUDGET_MIB=96 bash "$SLOT" docker -- docker run --rm "$IMAGE" cat /sys/fs/cgroup/memory.max) $(tr -d '\n' < "$W/out")" "контейнер получил memory.max = бюджет"
    assert "76 да" "$(slot HEAVY_SLOT_BUDGET_MIB=96 bash "$SLOT" docker -- docker run --rm "$IMAGE" python3 -c "$ALLOC" 300 0) $(has "$W/err" 'OOM контейнера')" "300 МиБ в контейнере под бюджетом 96 — 76, причина названа"
    assert 64 "$(slot HEAVY_SLOT_BUDGET_MIB=96 bash "$SLOT" docker -- docker run --rm -m 1g "$IMAGE" true)" "свой -m у вызова — 64"
    assert 0 "$(slot HEAVY_SLOT_BUDGET_MIB=96 bash "$SLOT" docker -- docker run --rm -e X=1 "$IMAGE" sh -c 'exit 0' -m)" "близнец: -m после образа — аргумент контейнера, не флаг docker"
    assert "0 67108864" "$(slot HEAVY_SLOT_BUDGET_MIB=96 bash "$SLOT" docker -- docker run --rm -m 64m "$IMAGE" cat /sys/fs/cgroup/memory.max) $(tr -d '\n' < "$W/out")" "близнец: свой -m 64m в бюджете 96 — контейнер получил предел вызова (ws#1110)"

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

echo "── подмена docker: свой предел вызова — законен в бюджете, не дублируется (ws#1110)"
# Настоящий вход — форма стенда kaname (`.github/scripts/stand-own.sh`: службе
# `--memory 1280m --memory-swap 1280m`, законная в конвейере); docker — двойник,
# печатающий argv: судится то, что подмена ОТДАЁТ настоящему docker.
DS="$W/dshim"; mkdir -p "$DS"; ln -sf "$SLOT" "$DS/docker"
printf '#!/bin/sh\nprintf "%%s\\n" "$@"\n' > "$DS/real"; chmod +x "$DS/real"
# shim <бюджет MiB> <аргументы docker…> — код подмены; argv настоящего — в $W/out.
shim() { local b="$1"; shift; HEAVY_SLOT_P="$DS/p" HEAVY_SLOT_B="$b" HEAVY_SLOT_REAL_DOCKER="$DS/real" "$DS/docker" "$@" > "$W/out" 2> "$W/err"; echo $?; }
cnt() { grep -cE -- "$1" "$W/out"; }
rc="$(shim 8192 run --rm --name svc --network host --memory 1280m --memory-swap 1280m --user 1:1 img /bin/kaname)"
assert "0 1 1 0 1" "$rc $(cnt '^--memory$') $(cnt '^--memory-swap$') $(cnt '^--memory(-swap)?=') $(cnt '^--cidfile=')" "форма стенда kaname под бюджетом 8 ГиБ: исполнено, предел вызова один, своего слот не дописал, --cidfile есть"
rc="$(shim 8192 run --rm --memory 1280m img true)"
assert "0 1 1" "$rc $(cnt '^--memory-swap=1280m$') $(cnt '^--memory(=|$)')" "только --memory вызова: swap дописан равным памяти (сверх неё swap нет), память не продублирована"
rc="$(shim 8192 run --rm -dm512m img true)"
assert "0 1 0" "$rc $(cnt '^--memory-swap=512m$') $(cnt '^--memory=')" "склейка коротких -dm512m — та же форма: swap дописан, память не продублирована"
rc="$(shim 8192 run --rm img sh -c true -m 99g)"
assert "0 1 1" "$rc $(cnt '^--memory=8192m$') $(cnt '^--memory-swap=8192m$')" "близнец: без предела вызова (-m после образа — аргумент контейнера) — слот ставит бюджет"
for c in "--memory 9g" "-m 9g" "--memory=9g" "--memory-swap 9g" "--memory 0" "--memory-swap -1" "--memory 12x"; do
    # shellcheck disable=SC2086  # флаг и значение — два слова
    rc="$(shim 8192 run --rm $c img true)"
    assert "64 0" "$rc $(wc -l < "$W/out" | tr -d ' ')" "«$c» под бюджетом 8 ГиБ — 64, настоящий docker не звался"
done
assert "да" "$(has "$W/err" 'не разбирается как величина памяти')" "неразобранная величина названа причиной"
rc="$(shim 8192 run --rm --memory 9g img true)"; assert "да" "$(has "$W/err" 'больше бюджета класса 8,0 ГиБ')" "сверх бюджета — причина и бюджет названы"
rc="$(shim 8192 run --rm --cidfile x img true)"; assert "64 да" "$rc $(has "$W/err" 'слот ставит --cidfile сам')" "свой --cidfile — 64: по нему слот снимает контейнер"
rc="$(shim 8192 run --rm --memory 8192m img true)"; assert 0 "$rc" "граница: предел ровно в бюджет — законен"

echo "── сторож машины: перебор потолка обрывает МЛАДШИЙ слот, старший живёт"
export HEAVY_SLOT_LIMIT_MIB=1300
HEAVY_SLOT_BUDGET_MIB=50 bash "$SLOT" docker -- sleep 6 2>"$W/errA" & A=$!
for _ in $(seq 1 25); do [ "$(nslots)" -ge 1 ] && break; sleep 0.2; done
HEAVY_SLOT_BUDGET_MIB=50 bash "$SLOT" docker -- sleep 6 2>"$W/errC" & C=$!
for _ in $(seq 1 25); do [ "$(nslots)" -ge 2 ] && break; sleep 0.2; done
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

echo "── порождения процессов — признак машины, как память: вход по порогу, пик и счёт в журнале (ws#1291)"
# Счётчик подаётся синтетическим /proc/stat (HEAVY_SLOT_PROCSTAT): вход судит темп за окно 1 с,
# сторож — темп за свой шаг. Рост счётчика в окне делает писатель пробы, а не машина: исход не
# зависит от соседних полос. Каждый случай меняет ОДИН факт против близнеца.
PS="$W/procstat"; echo "processes 1000" > "$PS"
# spawn_storm <с> — писатель поднимает счётчик на 1000 каждые 0,1 с: темп ~10000/с.
spawn_storm() { local i=0; while [ "$i" -lt $(( $1 * 10 )) ]; do i=$((i + 1)); echo "processes $(( 1000 + i * 1000 ))" > "$PS.tmp" && mv -f "$PS.tmp" "$PS"; sleep 0.1; done; }
JS="$HEAVY_SLOT_DIR/journal.log"
assert "0 1" "$(slot HEAVY_SLOT_PROCSTAT="$PS" HEAVY_SLOT_SPAWN_MAX=100 bash "$SLOT" docker -- true) $(grep -c ' enter id=.* spawn=0/s ' "$JS")" "близнец: счётчик стоит — темп 0/с ≤ 100, слот выдан, темп в строке enter"
spawn_storm 4 & SPW=$!
assert "74 да нет" "$(slot -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_PROCSTAT="$PS" HEAVY_SLOT_SPAWN_MAX=100 bash "$SLOT" --wait 0 docker -- touch "$W/sp1") $(has "$W/err" 'порождений процессов') $([ -e "$W/sp1" ] && echo да || echo нет)" "темп выше порога — место не выдано (74), причина «порождений процессов … > порога», команда не запускалась"
wait "$SPW"; echo "processes 1000" > "$PS"
assert "1" "$(grep -c ' busy class=docker .* spawn=[0-9][0-9]*/s ' "$JS")" "невыдача по темпу записана строкой busy с темпом"
spawn_storm 4 & SPW=$!
assert "0" "$(slot -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_PROCSTAT="$PS" HEAVY_SLOT_SPAWN_MAX=1000000 bash "$SLOT" --wait 0 docker -- true)" "близнец: тот же темп при пороге выше него — слот выдан"
wait "$SPW"; echo "processes 1000" > "$PS"
# Сторож: команда сама поднимает счётчик посреди прогона — первое превышение строкой spawn-over.
# shellcheck disable=SC2016  # тело `bash -c` раскрывает дочерняя оболочка
JUMP='sleep 2.5; echo "processes 900000" > "$0"; sleep 2.5'
b0="$(grep -c ' spawn-over id=' "$JS")"
assert "0 $((b0 + 1)) да" "$(slot HEAVY_SLOT_PROCSTAT="$PS" HEAVY_SLOT_SPAWN_MAX=100 bash "$SLOT" docker -- bash -c "$JUMP" "$PS") $(grep -c ' spawn-over id=' "$JS") $(grep -qE ' leave .* spawns=899000 spawn_peak=[0-9]+/s ' <<<"$(tail -n 1 "$JS")" && echo да || echo нет)" "темп посреди прогона выше порога — строка spawn-over, выход — spawns= и spawn_peak= в leave"
echo "processes 1000" > "$PS"
assert "0 $((b0 + 1))" "$(slot HEAVY_SLOT_PROCSTAT="$PS" HEAVY_SLOT_SPAWN_MAX=100000000 bash "$SLOT" docker -- bash -c "$JUMP" "$PS") $(grep -c ' spawn-over id=' "$JS")" "близнец: тот же скачок под порогом — spawn-over нет"
assert "0 да" "$(slot bash "$SLOT" docker -- true) $(grep -qF ' spawns=— spawn_peak=—/s ' <<<"$(tail -n 1 "$JS")" && echo да || echo нет)" "режим проб без HEAVY_SLOT_PROCSTAT — темп не судится и назван «—», а не нулём"
assert "64 да" "$(slot "${REAL[@]}" HEAVY_SLOT_PROCSTAT="$PS" bash "$SLOT" docker -- touch "$W/sp2") $(has "$W/err" 'HEAVY_SLOT_PROCSTAT')" "над настоящей памятью синтетический счётчик — ручка, 64"
assert "64 да" "$(slot "${REAL[@]}" HEAVY_SLOT_SPAWN_MAX=999999 bash "$SLOT" docker -- touch "$W/sp3") $(has "$W/err" 'HEAVY_SLOT_SPAWN_MAX')" "над настоящей памятью порог порождений — ручка, 64"
# shellcheck disable=SC2016  # образец sed и тело `sh -c` раскрывает не эта оболочка
sed 's|^    \[ -n "\$srate" \] && \[ "\$srate" -gt "\$SPAWN_MAX" \] && full=|    false \&\& full=|' "$SLOT" > "$W/slot-mut-sp.sh"
spawn_storm 4 & SPW=$!
assert "1 0" "$(diff "$SLOT" "$W/slot-mut-sp.sh" | grep -c '^<') $(slot -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_PROCSTAT="$PS" HEAVY_SLOT_SPAWN_MAX=100 bash "$W/slot-mut-sp.sh" --wait 0 docker -- true)" "мутант «темп входа не судится»: шторм входит (0) — проба «74 по темпу» выше его ловит"
wait "$SPW"; echo "processes 1000" > "$PS"

echo "── класс suite — наборы и пробы оснастки; нагрузка продукта под ним — 64 (ws#1291)"
assert "1" "$(bash "$SLOT" --classes 2>/dev/null | grep -c '^suite ')" "класс suite в --classes"
assert "1536" "$(bash "$SLOT" --budget suite)" "бюджет suite — 1536 МиБ (основание — в --classes)"
# shellcheck disable=SC2016  # образец sed и тело `sh -c` раскрывает не эта оболочка
assert "0 да" "$(slot bash "$SLOT" suite -- sh -c 'touch "$0"' "$W/su1") $([ -e "$W/su1" ] && echo да || echo нет)" "набор под suite исполняется слотом"
for pl in "go version" "make -v" "golangci-lint version" "env FOO=1 go vet ./..." "nice -n 5 bash scripts/ci-local.sh"; do
    # shellcheck disable=SC2086  # нагрузка — слова
    assert "64 да" "$(slot bash "$SLOT" suite -- $pl) $(has "$W/err" 'нагрузка продукта')" "suite -- $pl → 64: нагрузке продукта положен свой класс"
done
assert "0" "$(slot bash "$SLOT" suite -- git --version)" "близнец: git без отправки под suite — исполняется"
git init -q "$W/sugit"
assert "64 да" "$(cd "$W/sugit" && slot bash "$SLOT" suite -- git push -q origin HEAD) $(has "$W/err" 'нагрузка продукта')" "suite -- git push → 64: отправке положен ci-local"
assert "64 да" "$(cd "$W/sugit" && env HEAVY_SLOT_REMOTE_RUN="$W/nope" bash "$SLOT" --route suite -- go version 2>"$W/err" >/dev/null; echo $?) $(has "$W/err" 'нагрузка продукта')" "--route судит тем же: suite -- go → 64"

echo "── --waits: ожидание входа класса по журналу — медиана для решения о пуле suite (ws#1291)"
# Журнал синтетический: вошедшие suite 100/300/500 с, не дождавшийся 200 с, отказ 74, чужой класс,
# строка старше окна. Каждая порча — один факт: окно, класс, вид строки.
WJ="$W/wslots"; mkdir -p "$WJ"; wnow="$(date -Is)"; wold="$(date -Is -d '-30 hours')"
{
    echo "$wnow enter id=1 class=suite budget=1536MiB waited=100s head=x who=w cmd=c"
    echo "$wnow enter id=2 class=suite budget=1536MiB waited=500s head=x who=w cmd=c"
    echo "$wnow timeout class=suite budget=1536MiB ahead=1 waited=200s ticket=t who=w cmd=c"
    echo "$wnow enter id=3 class=suite budget=1536MiB waited=300s head=x who=w cmd=c"
    echo "$wnow busy class=suite budget=1536MiB ahead=2 ticket=t who=w cmd=c"
    echo "$wnow enter id=4 class=lint budget=512MiB waited=9000s head=x who=w cmd=c"
    echo "$wold enter id=5 class=suite budget=1536MiB waited=7000s head=x who=w cmd=c"
} > "$WJ/journal.log"
assert "0 WAITS class=suite hours=24 n=4 median=250s p90=500s max=500s timeout75=1 busy74=1" "$(slot HEAVY_SLOT_DIR="$WJ" bash "$SLOT" --waits suite) $(cat "$W/out")" "suite за 24 ч: медиана чётного числа, p90, наибольшее; 74 — счётом, чужой класс и строка вне окна не входят"
assert "0 n=5 max=7000s" "$(slot HEAVY_SLOT_DIR="$WJ" bash "$SLOT" --waits suite 48) $(grep -o ' n=[0-9]*' "$W/out" | tr -d ' ') $(grep -o 'max=[0-9]*s' "$W/out")" "близнец: окно 48 ч — старая строка входит"
assert "2 да" "$(slot HEAVY_SLOT_DIR="$WJ" bash "$SLOT" --waits go-race) $(has "$W/out" 'медиана не установлена')" "записей класса нет — код 2, «не установлена», а не ноль ожидания"
assert "64 64" "$(slot HEAVY_SLOT_DIR="$WJ" bash "$SLOT" --waits no-such) $(slot HEAVY_SLOT_DIR="$WJ" bash "$SLOT" --waits suite 0)" "неизвестный класс и окно 0 ч — 64"
echo "── внешний кластер: тяжёлый класс уходит в run.sh, локально — только с причиной (ws#984)"
# Двойник run.sh пишет свой argv и отвечает на --available кодом FAKE_AVAIL; клон —
# настоящий git с origin вида PRO-Robotech/kaname и веткой 984-x.
cat > "$W/fake-run.sh" <<'FAKE'
#!/usr/bin/env bash
# --request — запрос pod билета внешнего входа (ws#1302): argv прогона он не пишет.
[ "${1:-}" = --request ] && { echo "1000 1000"; exit 0; }
if [ "${1:-}" = --available ]; then
    printf '%s\n' "$@" > "$FAKE_ARGV.avail"
    [ "${FAKE_AVAIL:-0}" = 0 ] && exit 0
    [ "${FAKE_AVAIL:-0}" = 2 ] && { echo "remote-heavy: открытого для планирования узла нет (узлов 2: закрыты для планирования 2)" >&2; exit 69; }
    [ "${FAKE_AVAIL:-0}" = 3 ] && { echo "remote-heavy: идущих тяжёлых прогонов 2 из 2" >&2; exit 75; }
    [ "${FAKE_AVAIL:-0}" = 4 ] && { sleep 30; exit 0; }
    # 8 — дефект обёртки run.sh (70); 9 — сама обёртка не исполнилась так, как в журнале
    # ws#1210 (bash: «jq: Argument list too long», 126): ни то, ни другое не недоступность.
    [ "${FAKE_AVAIL:-0}" = 8 ] && { echo "remote-heavy: дефект обёртки run.sh: перепись идущих тяжёлых ns прочитана, а разбор её отказал" >&2; exit 70; }
    [ "${FAKE_AVAIL:-0}" = 9 ] && { echo "run.sh: line 611: /usr/bin/jq: Argument list too long" >&2; exit 126; }
    # 6 — медленный, но живой ответ: 12 с (замер ws#1141 — кластер отвечал за 3,3–12,6 с).
    [ "${FAKE_AVAIL:-0}" = 6 ] && { sleep 12; exit 0; }
    # 7 — первый опрос висит, второй отвечает сразу: повтор после 124 (ws#1141).
    if [ "${FAKE_AVAIL:-0}" = 7 ]; then
        [ -e "$FAKE_ARGV.slow" ] && exit 0
        touch "$FAKE_ARGV.slow"; sleep 30; exit 0
    fi
    if [ "${FAKE_AVAIL:-0}" = 5 ]; then
        [ -e "$FAKE_ARGV.busy" ] && exit 0
        touch "$FAKE_ARGV.busy"; echo "remote-heavy: кластер занят: идущих тяжёлых прогонов 2 при пределе 2" >&2; exit 75
    fi
    echo "remote-heavy: кластер не отвечает" >&2; exit 69
fi
printf '%s\n' "$@" > "$FAKE_ARGV"
# FAKE_EXEC=1 — исполнить команду в --src/--workdir, как Job (FAKE_IN_JOB=1 видит она).
if [ "${FAKE_EXEC:-0}" = 1 ]; then
    src=""; wd=.; ref=""
    while [ "$#" -gt 0 ] && [ "$1" != -- ]; do case "$1" in --src) src="$2"; shift 2 ;; --workdir) wd="$2"; shift 2 ;; --ref) ref="$2"; shift 2 ;; *) shift ;; esac; done
    shift
    [ -n "${FAKE_EXEC_RC:-}" ] && exit "$FAKE_EXEC_RC"
    # FAKE_EXEC_CLONE=1 — как pod: свой клон со СВОЕЙ .git на --ref; снимается после команды (ws#1288).
    if [ "${FAKE_EXEC_CLONE:-0}" = 1 ]; then
        c="$(mktemp -d "$FAKE_ARGV.pod.XXXXXX")"
        env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_CONFIG_PARAMETERS git clone -q --no-local "$src" "$c/t" 2> /dev/null &&
            env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_CONFIG_PARAMETERS git -C "$c/t" checkout -q --detach "$ref" || { rm -rf "$c"; exit 69; }
        (cd "$c/t/$wd" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_CONFIG_PARAMETERS FAKE_IN_JOB=1 "$@" < /dev/null); rc=$?
        rm -rf "$c"; exit "$rc"
    fi
    (cd "$src/$wd" && FAKE_IN_JOB=1 "$@" < /dev/null); exit $?
fi
exit 17
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
assert "--available --profile lint --repo kaname" "$(tr '\n' ' ' < "$W/argv.avail" | sed 's/ $//')" "проверка кластера несёт профиль класса и репозиторий — размещение судится под запрос по замеру его прогонов (ws#991, ws#1195)"
assert "984 kaname sub $(git -C "$R" rev-parse HEAD)" "$(sed -n '/^--task$/{n;p}' "$W/argv") $(sed -n '/^--repo$/{n;p}' "$W/argv") $(sed -n '/^--workdir$/{n;p}' "$W/argv") $(sed -n '/^--ref$/{n;p}' "$W/argv")" "задача из ветки, repo из origin, каталог и коммит — в argv"
assert "go version" "$(sed -n '/^--$/,$p' "$W/argv" | sed 1d | tr '\n' ' ' | sed 's/ $//')" "команда передана после «--» без искажения"
rm -f "$W/argv" "$W/argv.avail"
assert "17 go-race --available --profile go-race --repo kaname" "$(RDIR="$R/sub" rslot bash "$SLOT" go-unit -- go test ./...) $(sed -n '/^--profile$/{n;p}' "$W/argv") $(tr '\n' ' ' < "$W/argv.avail" | sed 's/ $//')" "go-unit (go test без -race) → Job профилем go-race: проверка и run.sh — тем же профилем (ws#1301)"
rm -f "$W/argv"
assert "0 да нет" "$(FAKE_AVAIL=1 rslot bash "$SLOT" lint -- go version) $(has "$W/err" 'локально — кластер недоступен') $([ -e "$W/argv" ] && echo да || echo нет)" "кластер не отвечает → локально, причина названа"
rm -f "$W/argv"
assert "0 да нет" "$(FAKE_AVAIL=2 rslot bash "$SLOT" go-race -- go version) $(has "$W/err" 'локально — кластер недоступен: открытого для планирования узла нет') $([ -e "$W/argv" ] && echo да || echo нет)" "открытого узла нет → локально сразу, причина названа (ws#991)"
rm -f "$W/argv"
# ws#1210: отказ проверки не сетевым признаком — не «недоступен»: 70, ни Job, ни локально
assert "69 да нет нет" "$(FAKE_AVAIL=8 rslot bash "$SLOT" go-race -- go version) $(has "$W/err" 'отказала не сетевым признаком (код 70)') $([ -e "$W/argv" ] && echo да || echo нет) $(has "$W/out" 'go version go')" "дефект обёртки run.sh (70) → 69, команда не запускалась ни там, ни локально (ws#1210)"
assert "69 да нет нет" "$(FAKE_AVAIL=9 rslot bash "$SLOT" lint -- go version) $(has "$W/err" 'не сетевым признаком (код 126)') $([ -e "$W/argv" ] && echo да || echo нет) $(has "$W/out" 'go version go')" "обёртка не исполнилась («Argument list too long», 126) → 69, не локально (ws#1210)"
rm -f "$W/argv"
assert "77 да нет" "$(rslot bash "$SLOT" ci-local -- git status) $(has "$W/err" 'внешнего маршрута нет') $([ -e "$W/argv" ] && echo да || echo нет)" "git без push при доступном кластере → 77: внешнего маршрута нет, машина — лишь при недоступном (ws#1301)"
echo c >> "$R/f"
printf 'all:\n\t@touch "%s"\n' "$W/dirty-ran" > "$W/dirty.mk"
assert "77 да нет нет" "$(rslot bash "$SLOT" go-race -- make -s -f "$W/dirty.mk") $(has "$W/err" 'во внешний кластер: закоммить правки') $([ -e "$W/argv" ] && echo да || echo нет) $([ -e "$W/dirty-ran" ] && echo да || echo нет)" "правка в отслеживаемом файле при доступном кластере → 77 «во внешний кластер: …», команда не запускалась (ws#1105)"
rm -f "$W/argv"
assert "0 да" "$(FAKE_AVAIL=1 rslot bash "$SLOT" go-race -- make -v) $(has "$W/err" 'локально — кластер недоступен')" "близнец: та же правка при недоступном кластере → локально, причина названа"
git -C "$R" checkout -q -- f
assert "17 да" "$(rslot bash "$SLOT" go-race -- timeout 60 make -v) $(has "$W/argv" 'go-race')" "близнец: тот же клон без правки, timeout перед make → run.sh"
rm -f "$W/argv"
rm -f "$W/argv.avail"
assert "77 да нет да" "$(rslot bash "$SLOT" docker -- true) $(has "$W/err" "внешнего маршрута нет (класс «docker» внешнего пути не имеет) — до него команда не выполняется нигде: маршрут — задача ws#1303") $([ -e "$W/argv" ] && echo да || echo нет) $([ -e "$W/argv.avail" ] && echo да || echo нет)" "класс docker при доступном кластере → 77 с задачей маршрута, run.sh не звался, кластер спрошен (ws#1301)"
b="$(grep -cF -- ' local class=docker proof=rc=69' "$HEAVY_SLOT_DIR/journal.log" 2>/dev/null || true)"
assert "0 $((b + 1))" "$(FAKE_AVAIL=1 rslot bash "$SLOT" docker -- true) $(grep -cF -- ' local class=docker proof=rc=69' "$HEAVY_SLOT_DIR/journal.log" 2>/dev/null || true)" "близнец: тот же docker при недоступном кластере → локально, proof в журнале"
sed 's#^    \[ -n "\$PROOF\$NR_MOOT" \] || no_route_judge$#    :#' "$SLOT" > "$W/slot-mut-nr.sh"
assert "1 0" "$(diff "$SLOT" "$W/slot-mut-nr.sh" | grep -c '^<') $(rslot bash "$W/slot-mut-nr.sh" docker -- true)" "мутант «класс без маршрута не судится»: docker при доступном кластере локально (0) — проба «77» выше его ловит"
assert "64 да" "$(cd "$R" && env "${REAL[@]}" HEAVY_SLOT_REMOTE_RUN="$W/fake-run.sh" bash "$SLOT" lint -- go version 2>"$W/err" >/dev/null; echo $?) $(has "$W/err" 'HEAVY_SLOT_REMOTE_RUN')" "над настоящей памятью двойник run.sh — ручка, 64"

echo "── переносимый скрипт клона: контейнерные пробы kaname уходят Job-ом сами (ws#1192 б)"
# Вход — форма шага integrationshard ci.yml kaname: `.github/scripts/run-integration.sh` с
# INTEGRATION_SHARD; до правки слот отвечал 77 «нагрузка не опознана». Скрипт — ОТСЛЕЖИВАЕМЫЙ
# файл клона kaname (Job исполняет коммит), путь — относительный (путь машины в pod не существует).
mkdir -p "$R/.github/scripts"
printf '#!/usr/bin/env bash\necho integration\n' > "$R/.github/scripts/run-integration.sh"
printf '#!/usr/bin/env bash\necho other\n' > "$R/.github/scripts/other.sh"
chmod +x "$R/.github/scripts/"*.sh; git -C "$R" add .github; sandbox_git -C "$R" commit -q -m scripts
rm -f "$W/argv"
assert "17 да" "$(rslot bash "$SLOT" integration -- .github/scripts/run-integration.sh) $(has "$W/argv" '.github/scripts/run-integration.sh')" "скрипт контейнерных проб kaname формой шага CI → run.sh профилем integration"
rm -f "$W/argv"
assert "17 да" "$(rslot bash "$SLOT" integration -- env INTEGRATION_SHARD=0/3 bash .github/scripts/run-integration.sh) $(has "$W/argv" 'INTEGRATION_SHARD=0/3')" "тот же скрипт за env и bash, шард в argv → run.sh"
rm -f "$W/argv"
assert "77 да да нет" "$(rslot bash "$SLOT" integration -- "$R/.github/scripts/run-integration.sh") $(has "$W/err" 'не опознана как переносимая') $(has "$W/err" 'относительным путём') $([ -e "$W/argv" ] && echo да || echo нет)" "близнец: тот же скрипт абсолютным путём машины → 77, Job не создан"
assert "77 да" "$(rslot bash "$SLOT" integration -- .github/scripts/other.sh) $(has "$W/err" 'не опознана как переносимая')" "близнец: другой отслеживаемый скрипт клона → 77"
assert "77 да" "$(rslot bash "$SLOT" lint -- .github/scripts/run-integration.sh) $(has "$W/err" 'не опознана как переносимая')" "близнец: тот же скрипт классом lint (ведомость — integration) → 77"
R3="$W/rclone-kc"; git init -q -b 984-y "$R3"; git -C "$R3" remote add origin https://github.com/PRO-Robotech/kacho.git
mkdir -p "$R3/.github/scripts"; cp "$R/.github/scripts/run-integration.sh" "$R3/.github/scripts/"; git -C "$R3" add .github; sandbox_git -C "$R3" commit -q -m s
assert "77 да" "$(RDIR="$R3" rslot bash "$SLOT" integration -- .github/scripts/run-integration.sh) $(has "$W/err" 'не опознана как переносимая')" "близнец: скрипт того же имени в клоне kacho → 77"
R4="$W/rclone-un"; git init -q -b 984-z "$R4"; git -C "$R4" remote add origin https://github.com/PRO-Robotech/kaname.git
echo a > "$R4/f"; git -C "$R4" add f; sandbox_git -C "$R4" commit -q -m p; mkdir -p "$R4/.github/scripts"; cp "$R/.github/scripts/run-integration.sh" "$R4/.github/scripts/"
assert "77 да" "$(RDIR="$R4" rslot bash "$SLOT" integration -- .github/scripts/run-integration.sh) $(has "$W/err" 'не опознана как переносимая')" "близнец: скрипт не отслеживается (Job его не увидит) → 77"
sed 's|^        \[\[ "\$real" == "\$RS_TOP/"\$p \]\] \|\| continue$|        :|' "$SLOT" > "$W/slot-mut-port.sh"
assert "1 17" "$(diff "$SLOT" "$W/slot-mut-port.sh" | grep -c '^<') $(rslot bash "$W/slot-mut-port.sh" integration -- .github/scripts/other.sh)" "мутант «путь скрипта не сверяется»: другой скрипт уходит Job-ом — близнец выше его ловит"

echo "── маршрут без исполнения: --route — чистое суждение того же механизма (ws#1192 в)"
# stand-report.sh expect спрашивает здесь маршрут каждого задания ведомости ДО прогона. Суждение
# статическое: кластер не спрашивается, run.sh не зовётся, команда не исполняется, журнала нет.
route() { (cd "$1" && shift && env HEAVY_SLOT_REMOTE_RUN="$W/fake-run.sh" FAKE_ARGV="$W/argv" bash "${RSLOT:-$SLOT}" --route "$@" 2> "$W/err" > "$W/out"); echo "$? $(cut -f2 "$W/out" | head -n 1)"; }
rm -f "$W/argv" "$W/argv.avail" "$W/route-ran"; jl0="$(wc -l < "$HEAVY_SLOT_DIR/journal.log" 2>/dev/null || echo 0)"
assert "0 external да" "$(route "$R" go-race -- go test ./...) $(has "$W/out" 'Job внешнего кластера')" "go test классом go-race в клоне kaname → external (Job)"
assert "нет нет $jl0" "$([ -e "$W/argv.avail" ] && echo да || echo нет) $([ -e "$W/argv" ] && echo да || echo нет) $(wc -l < "$HEAVY_SLOT_DIR/journal.log" 2>/dev/null || echo 0)" "--route не спрашивает кластер, не зовёт run.sh и не пишет журнал"
printf 'all:\n\t@touch "%s"\n' "$W/route-ran" > "$W/route.mk"
assert "0 external нет" "$(route "$R" go-race -- make -s -f "$W/route.mk") $([ -e "$W/route-ran" ] && echo да || echo нет)" "--route команду не исполняет: make с рецептом-меткой → external, метки нет"
assert "0 external" "$(route "$R" integration -- env INTEGRATION_SHARD=0/3 .github/scripts/run-integration.sh)" "скрипт контейнерных проб kaname → external"
assert "0 none да" "$(route "$R" integration -- bash .github/scripts/other.sh) $(has "$W/out" 'не опознана как переносимая')" "неопознанная нагрузка → none (при доступном кластере было бы 77)"
assert "0 none да" "$(route "$R" docker -- true) $(has "$W/out" 'внешнего пути не имеет')" "класс без внешнего пути → none: при доступном кластере 77 (ws#1301)"
assert "0 none да" "$(route "$W" lint -- go version) $(has "$W/out" 'не клон git')" "каталог не клон → none (ws#1301)"
RO="$W/rclone-other"; git init -q -b 984-o "$RO"; git -C "$RO" remote add origin https://github.com/PRO-Robotech/elsewhere.git
assert "0 none да" "$(route "$RO" lint -- go version) $(has "$W/out" 'клон не kacho, kaname, corelib или kacho-workspace')" "близнец: клон чужого репозитория → none (ws#1301)"
RK="$W/rclone-sn"; git init -q -b 984-s "$RK"; git -C "$RK" remote add origin https://github.com/PRO-Robotech/kacho.git
mkdir -p "$RK/deploy/scripts"; printf 'stand-ns-run:\n\t@true\n' > "$RK/deploy/Makefile"; printf '#!/usr/bin/env bash\ntrue\n' > "$RK/deploy/scripts/stand-ns.sh"
git -C "$RK" add deploy; sandbox_git -C "$RK" commit -q -m sn
assert "0 none да" "$(route "$RK" stand -- make -C deploy stand-ns-run 'NS=t<задача>-w1' 'CMD=<шаги>') $(has "$W/out" 'CMD stand-ns-run идёт на машине')" "stand-ns-run: CMD идёт на машине → none (ws#1301)"
assert "0 external да" "$(route "$RK" stand -- make -C deploy stand-ns-up 'NS=t<задача>-w1') $(has "$W/out" 'stand-ns')" "близнец: stand-ns-up в клоне kacho с механизмом stand-ns → external (стенд — ns внешнего кластера)"
assert "0 none да" "$(route "$RK" stand -- make -C deploy dev-up) $(has "$W/out" 'подъём локального стенда')" "подъём локального стенда → none (при доступном кластере было бы 77)"
assert "0 none да" "$(route "$RK" stand -- python3 -c pass) $(has "$W/out" 'у команды стенда внешнего маршрута нет')" "команда стенда без признака → none: внешнего маршрута нет (ws#1301)"
assert "0 local да" "$(route "$RK" stand -- make -C deploy dev-down) $(has "$W/out" 'снятие локального стенда')" "близнец: снятие локального стенда → local, машину освобождает"
# shellcheck disable=SC2016  # строка дочерней оболочки — предмет суждения, раскрывать её нечему
assert "0 none да" "$(route "$RK" stand -- bash -c 'make "$G"') $(has "$W/out" 'строку оболочки')" "строка оболочки без формы stand-ns-* → none (цель может прийти переменной)"
RK2="$W/rclone-sn2"; git init -q -b 984-t "$RK2"; git -C "$RK2" remote add origin https://github.com/PRO-Robotech/kacho.git
mkdir -p "$RK2/deploy"; cp "$RK/deploy/Makefile" "$RK2/deploy/"; git -C "$RK2" add deploy; sandbox_git -C "$RK2" commit -q -m sn
assert "0 local да" "$(route "$RK2" stand -- make -C deploy stand-ns-up 'NS=t<задача>-w1') $(has "$W/out" 'stand-ns')" "близнец: stand-ns-up, в клоне нет deploy/scripts/stand-ns.sh → local"
assert "64" "$(cd "$R" && bash "$SLOT" --route --enqueue "$W" go-race -- go version 2>/dev/null >/dev/null; echo $?)" "--route с --enqueue → 64"
assert "64" "$(cd "$R" && bash "$SLOT" --route 2>/dev/null >/dev/null; echo $?)" "--route без класса → 64"
sed 's|^        if \[ -n "\$RS_KNOWN" \]; then kind=external|        if true; then kind=external|' "$SLOT" > "$W/slot-mut-rt.sh"
assert "1 0 external" "$(diff "$SLOT" "$W/slot-mut-rt.sh" | grep -c '^<') $(RSLOT="$W/slot-mut-rt.sh" route "$R" integration -- bash .github/scripts/other.sh)" "мутант «нагрузка не судится»: неопознанная → external — утверждение выше его ловит"

echo "── оснастка внешнего маршрута сверяется со стволом до проверки кластера (ws#1228)"
# Дерево оснастки — песочница: голый origin и выписка main со scripts/heavy-slot.sh и
# scripts/remote-heavy/run.sh. Каждая порча меняет ОДИН факт: коммит origin/main по пути
# оснастки (отставание) против коммита вне её (близнец), недоступный origin при нуле.
# Мутанты — копии слота в $W/tmut рядом с настоящим main-clone-lag.sh: «сверять нечем»
# не подменяет причину красного.
TT="$W/ttree"; mkdir -p "$TT"
git init -q --bare -b main "$TT/origin.git"
git clone -q "$TT/origin.git" "$TT/ws" 2>/dev/null; git -C "$TT/ws" symbolic-ref HEAD refs/heads/main
mkdir -p "$TT/ws/scripts/remote-heavy" "$TT/ws/docs"
echo a > "$TT/ws/scripts/heavy-slot.sh"; echo a > "$TT/ws/scripts/remote-heavy/run.sh"; echo a > "$TT/ws/docs/x.md"
git -C "$TT/ws" add -A; sandbox_git -C "$TT/ws" commit -qm base; git -C "$TT/ws" push -q origin main 2>/dev/null
git clone -q "$TT/origin.git" "$TT/up" 2>/dev/null
ttpush() { echo "$RANDOM" >> "$TT/up/$1"; git -C "$TT/up" add -A; sandbox_git -C "$TT/up" commit -qm "$1"; git -C "$TT/up" push -q origin HEAD:main 2>/dev/null; }
ttslot() { rm -f "$W/argv"; rslot env HEAVY_SLOT_TOOLING_TREE="$TT/ws" bash "${1:-$SLOT}" lint -- go version; }
argv_seen() { [ -e "$W/argv" ] || [ -e "$W/argv.avail" ] && echo да || echo нет; }
rm -f "$W/argv.avail"
assert "17 да" "$(ttslot) $(has "$W/argv" '--profile')" "контроль: дерево оснастки на origin/main — сверка молчит, маршрут во внешний кластер (17)"
ttpush docs/x.md
rm -f "$W/argv.avail"
assert "17 нет" "$(ttslot) $(has "$W/err" 'TOOLING-LAG')" "близнец: origin/main впереди лишь вне оснастки (docs/) — слоту не мешает (17)"
ttpush scripts/remote-heavy/run.sh
rm -f "$W/argv.avail"
assert "69 да да нет нет" "$(ttslot) $(has "$W/err" 'отстаёт от origin/main на 1 коммит(ов) по путям scripts/remote-heavy/ scripts/heavy-slot.sh') $(has "$W/err" "merge --ff-only origin/main") $(argv_seen) $(has "$W/out" 'go version go')" "дерево оснастки отстаёт по run.sh на 1 — 69 с числом, путями и командой догона; ни проверки кластера, ни Job, ни локального запуска"
assert "1" "$(grep -c ' stale-tooling class=lint rc=1 ' "$HEAVY_SLOT_DIR/journal.log" 2>/dev/null)" "отказ записан в журнал слота строкой stale-tooling"
assert "0 да" "$(FAKE_AVAIL=1 rslot env HEAVY_SLOT_TOOLING_TREE="$TT/ws" bash "$SLOT" --local "сверка ws#1228" lint -- true) $(has "$W/err" 'локально по флагу --local')" "обход — только --local с причиной: маршрут и сверка не судятся"
git -C "$TT/ws" merge -q --ff-only origin/main
rm -f "$W/argv.avail"
assert "17" "$(ttslot)" "после догона дерева — снова во внешний кластер (17)"
git -C "$TT/ws" remote set-url origin "$TT/absent.git"
rm -f "$W/argv.avail"
assert "69 да нет" "$(ttslot) $(has "$W/err" 'отставание не установлено') $(argv_seen)" "fetch не прошёл при нуле — «не установлено», 69, не зелёное и не локально"
git -C "$TT/ws" remote set-url origin "$TT/origin.git"
assert "64 да" "$(cd "$R" && env "${REAL[@]}" HEAVY_SLOT_TOOLING_TREE="$TT/ws" bash "$SLOT" lint -- go version 2>"$W/err" >/dev/null; echo $?) $(has "$W/err" 'HEAVY_SLOT_TOOLING_TREE')" "над настоящей памятью дерево оснастки — ручка, 64"
mkdir -p "$W/tmut"; cp "$HERE/main-clone-lag.sh" "$W/tmut/main-clone-lag.sh"
tmut() { python3 - "$SLOT" "$W/tmut/heavy-slot.sh" "$1" "$2" <<'PYM'
import sys
s, d, a, b = sys.argv[1:5]
t = open(s, encoding="utf-8").read()
if t.count(a) != 1:
    sys.exit(1)
open(d, "w", encoding="utf-8").write(t.replace(a, b))
PYM
echo $?; }
ttpush scripts/heavy-slot.sh
assert "0 17" "$(tmut '    tooling_gate
    ext_enter' '    ext_enter') $(ttslot "$W/tmut/heavy-slot.sh")" "мутант «сверки нет»: отставший слот уходит во внешний кластер — проба отставания выше его ловит"
git -C "$TT/ws" merge -q --ff-only origin/main; ttpush docs/x.md
assert "0 69" "$(tmut ' -- "${TOOLING_PATHS[@]}" 2>&1)' ' 2>&1)') $(ttslot "$W/tmut/heavy-slot.sh")" "мутант «пути не судятся»: отставание вне оснастки отказывает — проба близнеца выше его ловит"
git -C "$TT/ws" merge -q --ff-only origin/main; git -C "$TT/ws" remote set-url origin "$TT/absent.git"
assert "0 17" "$(tmut '    [ "$rc" -eq 0 ] && return 0
    out=' '    [ "$rc" -ne 1 ] && return 0
    out=') $(ttslot "$W/tmut/heavy-slot.sh")" "мутант «не установлено молчит»: fetch не прошёл — маршрут как зелёный; проба «не установлено» выше его ловит"
git -C "$TT/ws" remote set-url origin "$TT/origin.git"

echo "── тяжёлое только во внешнем кластере, локально — по доказательству недоступности (ws#1105)"
# Решение владельца 2026-10-16: «тяжелые тесты только на внешнем кластере, если он
# недоступен тогда локально». Доказательство — вывод проверки кластера в журнале слота.
JL="$HEAVY_SLOT_DIR/journal.log"
# shellcheck disable=SC2016  # тело `bash -c` раскрывает дочерняя оболочка
jn() { grep -cF -- "$1" "$JL" 2>/dev/null || true; }
echo "── первая строка вывода слота — ревизия рабочего каталога, класс и время (ws#1244 L3)"
# Журналы -race и integration 2026-10-18 не несли ни sha, ни класса: какую голову судил прогон, по
# журналу не установить. Первая строка stderr слота — «HEAD <sha> class=… at=… dir=…»; в журнале
# слотов строка enter — с head=.
hr="$(git -C "$R" rev-parse HEAD)"; b="$(jn "head=${hr:0:12}")"
rc="$(FAKE_AVAIL=1 rslot bash "$SLOT" docker -- true)"; l1="$(head -n 1 "$W/err")"
assert "0 HEAD $hr class=docker да $((b + 1))" "$rc $(cut -d' ' -f1-3 <<< "$l1") $(grep -qE ' at=20[0-9-]+T[0-9:]+' <<< "$l1" && echo да || echo нет) $(jn "head=${hr:0:12}")" "git-каталог: первая строка — HEAD с полной ревизией, класс, время; enter в журнале несёт head="
rc="$(RDIR="$W/nogit" FAKE_AVAIL=1 rslot bash "$SLOT" docker -- true)"
assert "0 HEAD — class=docker" "$rc $(head -n 1 "$W/err" | cut -d' ' -f1-3)" "близнец: каталог не git — первая строка та же, ревизии нет («—»), без отказа"
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
# Срок проверки — по замеру (ws#1141, шапка heavy-slot.sh): медленный живой ответ
# недоступностью не считается; висящая проверка — недоступность после всех попыток.
# Срок опроса в пробе укорочен ручкой HEAVY_SLOT_CHECK_S там, где судится висение;
# медленный ответ судится сроком без ручки — тем, что стоит в слоте.
b="$(jn ' local class=lint ')"; rm -f "$W/argv"
t0="$(date +%s)"
r="$(FAKE_AVAIL=6 rslot bash "$SLOT" lint -- go version)"
assert "17 да нет $b" "$r $(has "$W/argv" '--profile') $(has "$W/err" 'не ответила') $(jn ' local class=lint ')" "медленный ответ (12 с) — не «недоступен»: срок без ручки, уход в run.sh (17), строки local нет (ws#1141)"
assert "да" "$([ $(( $(date +%s) - t0 )) -ge 12 ] && echo да || echo нет)" "контроль: двойник действительно отвечал ≥ 12 с — случай не пуст"
rm -f "$W/argv" "$W/argv.slow"
r="$(FAKE_AVAIL=7 rslot env HEAVY_SLOT_CHECK_S=2 bash "$SLOT" lint -- go version)"
assert "17 да да" "$r $(has "$W/argv" '--profile') $([ -e "$W/argv.slow" ] && echo да || echo нет)" "первый опрос висит, повтор отвечает → run.sh (17): одно висение недоступностью не считается (ws#1141)"
b="$(jn ' local class=lint proof=rc=124 ')"
t0="$(date +%s)"
r="$(FAKE_AVAIL=4 rslot env HEAVY_SLOT_CHECK_S=2 bash "$SLOT" lint -- go version)"
dt=$(( $(date +%s) - t0 ))
assert "0 да $((b + 1)) да" "$r $(has "$W/err" 'не ответила за 2 с, попыток 2') $(jn ' local class=lint proof=rc=124 ') $([ "$dt" -lt 15 ] && echo да || echo "нет(${dt}с)")" "проверка висит на каждой попытке → недоступен: локально, proof=rc=124 в журнале, попытки названы"
assert "64 да" "$(cd "$R" && env "${REAL[@]}" HEAVY_SLOT_CHECK_S=2 bash "$SLOT" lint -- go version 2>"$W/err" >/dev/null; echo $?) $(has "$W/err" 'HEAVY_SLOT_CHECK_S')" "над настоящей памятью срок проверки кластера ручкой — 64"
# Мутант на месте срока: копия слота с прежним сроком 10 с на том же медленном ответе
# обязана уйти локально — иначе проба медленного ответа слепа к сроку (ws#1141).
n_at="$(grep -c '^CHECK_S=30 ' "$SLOT")"
sed 's/^CHECK_S=30 /CHECK_S=10 /' "$SLOT" > "$W/slot-mut-check.sh"
rm -f "$W/argv"
r="$(FAKE_AVAIL=6 rslot bash "$W/slot-mut-check.sh" lint -- go version)"
assert "1 0 да нет" "$n_at $r $(has "$W/err" 'не ответила за 10 с') $([ -e "$W/argv" ] && echo да || echo нет)" "мутант «срок 10 с»: место срока одно, тот же ответ за 12 с — «недоступен», локально (проба выше его ловит)"
b="$(jn ' local class=ci-local proof=')"; bw="$(jn ' local class=ci-local why=команда «git» без push')"
assert "77 $b $bw" "$(rslot bash "$SLOT" ci-local -- git status) $(jn ' local class=ci-local proof=') $(jn ' local class=ci-local why=команда «git» без push')" "близнец: git без push при доступном кластере → 77, локального запуска в журнале нет (ws#1301)"

echo "── клон воркспейса: хук отправки, наборы и пробы — Job профиля ws, причина в журнале (ws#1304)"
# Клон с origin PRO-Robotech/kacho-workspace: скрипт ведомости PORTABLE (отслеживаемый, относительным
# путём) классов suite и ci-local и хук отправки уходят Job-ом профиля ws, строка remote журнала
# несёт profile= и why=; прочая нагрузка клона и прочие классы — без внешнего пути. Законный
# близнец — клон kacho тем же механизмом уходит профилем своего класса.
RW="$W/rclone-ws"; git init -q -b 1304-w "$RW"; git -C "$RW" remote add origin https://github.com/PRO-Robotech/kacho-workspace.git
mkdir -p "$RW/scripts/tg" "$RW/scripts/hooks" "$RW/.claude/hooks/hg"
for f in scripts/tg/run-all.sh scripts/tg/inject.sh scripts/tg-inject.sh scripts/other.sh .claude/hooks/hg/prove.sh; do printf '#!/usr/bin/env bash\necho %s\n' "$f" > "$RW/$f"; done
printf 'print(1)\n' > "$RW/scripts/tg/mutants.py"
# shellcheck disable=SC2016  # текст хука раскрывает он сам
printf '#!/usr/bin/env bash\n{ printf "job=%%s args=%%s\\n" "${FAKE_IN_JOB:-нет}" "$*"; cat; } >> "$HOOK_LOG"\nexit 0\n' > "$RW/scripts/hooks/pre-push"
chmod +x "$RW/scripts/hooks/pre-push"; git -C "$RW" add -A; sandbox_git -C "$RW" commit -q -m ws
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\nexec "$(git rev-parse --show-toplevel)/scripts/hooks/pre-push" "$@"\n' > "$RW/.git/hooks/pre-push"; chmod +x "$RW/.git/hooks/pre-push"
printf '#!/usr/bin/env bash\necho untracked\n' > "$RW/scripts/tg/check-99-untracked.sh"
argv_of() { sed -n "/^--$1\$/{n;p}" "$W/argv"; }
rm -f "$W/argv" "$W/argv.avail"; bw="$(jn ' remote class=suite route=job profile=ws ')"
assert "17 ws kacho-workspace 1304 . $((bw + 1)) 1" "$(RDIR="$RW" rslot bash "$SLOT" suite -- bash scripts/tg/run-all.sh) $(argv_of profile) $(argv_of repo) $(argv_of task) $(argv_of workdir) $(jn ' remote class=suite route=job profile=ws ') $(grep -F ' remote class=suite route=job profile=ws ' "$JL" | tail -n 1 | grep -c 'why=клон воркспейса, скрипт ведомости PORTABLE scripts/tg/run-all.sh — Job профиля ws who=')" "suite: run-all.sh набора в клоне воркспейса → Job профиля ws, задача из ветки; строка remote журнала — профиль и причина маршрута"
assert "--available --profile ws --repo kacho-workspace" "$(tr '\n' ' ' < "$W/argv.avail" | sed 's/ $//')" "проверка кластера — под профиль ws и репозиторий воркспейса"
rm -f "$W/argv"; bl="$(jn ' local class=suite proof=rc=69')"
assert "0 да нет $((bl + 1))" "$(FAKE_AVAIL=1 RDIR="$RW" rslot bash "$SLOT" suite -- bash scripts/tg/run-all.sh) $(has "$W/err" 'локально — кластер недоступен') $([ -e "$W/argv" ] && echo да || echo нет) $(jn ' local class=suite proof=rc=69')" "близнец: кластер недоступен → набор воркспейса локально слотом, доказательство (proof=) в журнале"
for pl in "python3 scripts/tg/mutants.py -j 2" "bash scripts/tg-inject.sh" "env X=1 bash scripts/tg/inject.sh" "bash .claude/hooks/hg/prove.sh"; do
    rm -f "$W/argv"
    # shellcheck disable=SC2086  # нагрузка — слова
    assert "17 ws" "$(RDIR="$RW" rslot bash "$SLOT" ci-local -- $pl) $(argv_of profile)" "ci-local: $pl в клоне воркспейса → Job профиля ws"
done
for pl in "bash scripts/other.sh" "bash scripts/tg/check-99-untracked.sh" "bash $RW/scripts/tg/run-all.sh" "python3 -c pass"; do
    rm -f "$W/argv"
    # shellcheck disable=SC2086  # нагрузка — слова
    assert "77 да нет" "$(RDIR="$RW" rslot bash "$SLOT" suite -- $pl) $(has "$W/err" 'клон воркспейса: нагрузка') $([ -e "$W/argv" ] && echo да || echo нет)" "близнец: $pl (вне ведомости, не отслеживается, путь машины, строка) → внешнего пути нет, при доступном кластере 77 с причиной (ws#1301)"
done
rm -f "$W/argv"
assert "77 да нет" "$(RDIR="$RW" rslot bash "$SLOT" go-race -- true) $(has "$W/err" 'Job профиля ws несёт лишь ci-local и suite') $([ -e "$W/argv" ] && echo да || echo нет)" "близнец: класс go-race в клоне воркспейса — внешнего пути нет (образ ws без go), при доступном кластере 77"
rm -f "$W/argv"; bk="$(jn 'why=клон kacho — Job профиля go-race who=')"
assert "17 go-race kacho $((bk + 1))" "$(RDIR="$R3" rslot bash "$SLOT" go-race -- go version) $(argv_of profile) $(argv_of repo) $(jn 'why=клон kacho — Job профиля go-race who=')" "законный близнец: клон kacho уходит своим маршрутом — профиль класса, причина в журнале"
assert "77 да" "$(RDIR="$R3" rslot bash "$SLOT" suite -- bash .github/scripts/run-integration.sh) $(has "$W/err" 'у клона kacho внешнего пути нет')" "близнец: класс suite в клоне kacho — внешнего пути нет, при доступном кластере 77"
# Перепись в обе стороны с деревом: каждый отслеживаемый файл дерева воркспейса, которого страж
# heavy-guard зовёт набором или пробой (suite_member: SUITE_NAME под scripts/ и .claude/hooks/ —
# импортом guard.py, а не копией образца), классом suite уходит Job-ом профиля ws; ноль файлов — отказ.
WS_TOP="$(cd "$HERE/.." && pwd -P)"
mapfile -t SUF < <(cd "$WS_TOP" && git ls-files -- scripts .claude/hooks | python3 -c 'import importlib.util, os, sys
s = importlib.util.spec_from_file_location("guard", sys.argv[1]); g = importlib.util.module_from_spec(s); s.loader.exec_module(g)
for l in sys.stdin:
    p = l.strip()
    if p.startswith(("scripts/", ".claude/hooks/")) and g.SUITE_NAME.match(os.path.basename(p)):
        print(p)' "$WS_TOP/.claude/hooks/heavy-guard/guard.py" 2>/dev/null)
RSC="$W/rclone-wsc"; git init -q -b 1304-c "$RSC"; git -C "$RSC" remote add origin https://github.com/PRO-Robotech/kacho-workspace.git
for f in "${SUF[@]}"; do mkdir -p "$RSC/$(dirname "$f")"; : > "$RSC/$f"; done
git -C "$RSC" add -A 2>/dev/null; sandbox_git -C "$RSC" commit -q --allow-empty -m census
# Пробы, судящие машину (MACHINE heavy-slot.sh), — без внешнего пути: каждая запись — живой файл
# дерева (иначе запись устарела) и маршрут none (при доступном кластере 77) с причиной; прочие — external.
mapfile -t MACH < <(sed -n "/^MACHINE='/,/'\$/p" "$SLOT" | sed -e "s/^MACHINE='//" -e "s/'\$//" | sed '/^$/d')
in_mach() { local m; for m in "${MACH[@]}"; do [ "$m" = "$1" ] && return 0; done; return 1; }
n_ext=0; n_mach=0; miss=""
for f in "${SUF[@]}"; do
    r="$(route "$RSC" suite -- bash "$f")"
    if in_mach "$f"; then
        if [ "$r" = "0 local" ] && grep -q 'предмет — машина' "$W/out"; then n_mach=$((n_mach + 1)); else miss="$miss $f(MACHINE→$r)"; fi
    elif [ "$r" = "0 external" ]; then n_ext=$((n_ext + 1)); else miss="$miss $f"; fi
done
assert "да ${#SUF[@]}" "$([ "${#SUF[@]}" -gt 0 ] && echo да || echo нет) $((n_ext + n_mach))" "перепись: наборов и проб дерева воркспейса (SUITE_NAME стража) ${#SUF[@]}: Job-ом профиля ws $n_ext, судящих машину (none) $n_mach${miss:+ — мимо ведомости:$miss}"
# MACHINE — законный локальный маршрут (решение диспетчера 2026-10-22 по правилу владельца «только
# если доступа к кластеру нету»: у предмета-машины доступа из кластера нет по построению): запись
# перечня при ДОСТУПНОМ кластере идёт в слоте машины с доказательством, а не 77; посторонняя
# проба воркспейса без внешнего пути — по-прежнему 77.
jl0="$(jn ' local class=suite proof=машина: ')"
assert "0 да $((jl0 + 1))" "$(RDIR="$RSC" rslot bash "$SLOT" suite -- bash "${MACH[0]}") $(has "$W/err" 'предмет — машина') $(jn ' local class=suite proof=машина: ')" "MACHINE: ${MACH[0]} при доступном кластере — локально в слоте (код команды 0), доказательство «предмет — машина» в журнале слотов"
mkdir -p "$RSC/scripts/zz"; : > "$RSC/scripts/zz/not-a-suite.sh"
assert "77 да нет" "$(RDIR="$RSC" rslot bash "$SLOT" suite -- bash scripts/zz/not-a-suite.sh) $(has "$W/err" 'внешнего маршрута нет') $(has "$W/err" 'предмет — машина')" "близнец: посторонняя команда воркспейса без внешнего пути — 77, локального маршрута MACHINE не получает"
m_live=0; for f in "${MACH[@]}"; do (cd "$WS_TOP" && git ls-files --error-unmatch -- "$f" >/dev/null 2>&1) && m_live=$((m_live + 1)); done
assert "да ${#MACH[@]}" "$([ "${#MACH[@]}" -gt 0 ] && echo да || echo нет) $m_live" "записи MACHINE — живые файлы дерева: ${#MACH[@]} записей, отслеживается $m_live (устаревшая запись — находка)"
git init -q --bare "$W/bare-ws.git"; HLW="$W/hook-ws.log"; rm -f "$HLW" "$W/argv"; bp="$(jn ' remote class=ci-local route=push profile=ws ')"
assert "0 1 ws kacho-workspace $((bp + 1)) 1" "$(RDIR="$RW" rslot env FAKE_EXEC=1 HOOK_LOG="$HLW" bash "$SLOT" ci-local -- git push -q "$W/bare-ws.git" HEAD:refs/heads/1304-w) $(grep -c '^job=1 ' "$HLW" 2>/dev/null) $(argv_of profile) $(argv_of repo) $(jn ' remote class=ci-local route=push profile=ws ') $(grep -F ' remote class=ci-local route=push profile=ws ' "$JL" | tail -n 1 | grep -c 'why=клон воркспейса, хук отправки — Job профиля ws who=')" "хук отправки воркспейса: Job профиля ws, хук исполнен там, строка remote с причиной"
assert "0 external да" "$(route "$RW" ci-local -- git push origin HEAD) $(has "$W/out" 'профиль ws, репозиторий kacho-workspace')" "--route: отправка из клона воркспейса → external, профиль ws"
assert "0 external да" "$(route "$RW" suite -- bash scripts/tg/run-all.sh) $(has "$W/out" 'профиль ws')" "--route: набор воркспейса классом suite → external, профиль ws"
sed 's#^        \*PRO-Robotech/kacho-workspace|\*PRO-Robotech/kacho-workspace\.git)$#        *PRO-Robotech/kacho-workspace-OFF)#' "$SLOT" > "$W/slot-mut-ws.sh"
assert "1 0 none" "$(diff "$SLOT" "$W/slot-mut-ws.sh" | grep -c '^<') $(RSLOT="$W/slot-mut-ws.sh" route "$RW" suite -- bash scripts/tg/run-all.sh)" "мутант «маршрут воркспейса снят»: набор → none — утверждения выше (external, Job профиля ws) его ловят"
# shellcheck disable=SC2016  # образец sed, раскрывать нечего
sed 's#^            RS_PROFILE=ws$#            RS_PROFILE="$CLASS"#' "$SLOT" > "$W/slot-mut-wsp.sh"; rm -f "$W/argv"
assert "1 17 suite" "$(diff "$SLOT" "$W/slot-mut-wsp.sh" | grep -c '^<') $(RDIR="$RW" rslot bash "$W/slot-mut-wsp.sh" suite -- bash scripts/tg/run-all.sh) $(argv_of profile)" "мутант «профиль — класс»: Job воркспейса идёт профилем suite — утверждение «ws» выше его ловит"
sed 's#^        \[\[ "\$real" == "\$RS_TOP/"\$p \]\] || continue$#        [ "$real" = "$RS_TOP/$p" ] || continue#' "$SLOT" > "$W/slot-mut-glob.sh"
assert "1 0 none" "$(diff "$SLOT" "$W/slot-mut-glob.sh" | grep -c '^<') $(RSLOT="$W/slot-mut-glob.sh" route "$RW" suite -- bash scripts/tg/run-all.sh)" "мутант «путь записи — не образец»: строки воркспейса ничего не узнают — утверждения выше его ловят"

echo "── хук отправки при доступном кластере → run.sh: хук — Job-ом на той же голове, локально лишь отправка, замок слотов не берётся (ws#1106, ws#1115)"
# Настоящий git push в голый репозиторий; хук продукта — отслеживаемый
# scripts/hooks/pre-push клона за переходником .git/hooks/pre-push (форма install-hooks).
mkdir -p "$R/scripts/hooks"
# shellcheck disable=SC2016  # текст хука раскрывает он сам
printf '#!/usr/bin/env bash\n{ printf "job=%%s args=%%s\\n" "${FAKE_IN_JOB:-нет}" "$*"; cat; } >> "$HOOK_LOG"\nexit "${HOOK_RC:-0}"\n' > "$R/scripts/hooks/pre-push"
chmod +x "$R/scripts/hooks/pre-push"; git -C "$R" add scripts; sandbox_git -C "$R" commit -q -m hook
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\nexec "$(git rev-parse --show-toplevel)/scripts/hooks/pre-push" "$@"\n' > "$R/.git/hooks/pre-push"; chmod +x "$R/.git/hooks/pre-push"
git init -q --bare "$W/bare.git"
HL="$W/hook.log"; touch "$HEAVY_SLOT_DIR/lock"
has_ref() { git -C "$W/bare.git" rev-parse --verify --quiet "refs/heads/$1" >/dev/null && echo да || echo нет; }
be="$(jn ' enter ')"; br="$(jn ' remote class=ci-local route=push ')"; rm -f "$HL" "$W/argv"
flock "$HEAVY_SLOT_DIR/lock" sleep 20 & LKH=$!; sleep 0.3
t0="$(date +%s)"
rc="$(rslot env FAKE_EXEC=1 HOOK_LOG="$HL" bash "$SLOT" ci-local -- git push -q "$W/bare.git" HEAD:refs/heads/1115-x)"
dt=$(( $(date +%s) - t0 )); kill "$LKH" 2>/dev/null; wait "$LKH" 2>/dev/null
assert "0 1 1 да $be $((br + 1)) да" "$rc $(grep -c '^job=1 ' "$HL" 2>/dev/null) $(grep -c '^job=' "$HL" 2>/dev/null) $(has_ref 1115-x) $(jn ' enter ') $(jn ' remote class=ci-local route=push ') $([ "$dt" -lt 10 ] && echo да || echo "нет(${dt}с)")" "git push при доступном кластере: хук исполнен Job-ом и только там, отправка дошла, слот не занят, строка remote в журнале, замок слотов (занят соседом) не брался"
assert "да $(git -C "$R" rev-parse HEAD) ci-local" "$(grep -q 'refs/heads/1115-x' "$HL" && echo да || echo нет) $(sed -n '/^--ref$/{n;p}' "$W/argv") $(sed -n '/^--profile$/{n;p}' "$W/argv")" "Job получил вход git (строки отправки) и судит отправляемую голову профилем ci-local"
pin_arg="$(sed -n '/^--push-input$/{n;p}' "$W/argv")"
assert "да" "$([[ "$pin_arg" =~ ^[^\ ]+\ $(git -C "$R" rev-parse HEAD)\ refs/heads/1115-x\ [0-9a-f]{40}$ ]] && echo да || echo нет)" "run.sh получил тот же вход git флагом --push-input — по нему Job ставит зависимости консоли до хука (ws#1115)"
rm -f "$HL"
assert "1 1 нет" "$(rslot env FAKE_EXEC=1 HOOK_LOG="$HL" HOOK_RC=1 bash "$SLOT" ci-local -- git push -q "$W/bare.git" HEAD:refs/heads/1115-y) $(grep -c '^job=1 ' "$HL" 2>/dev/null) $(has_ref 1115-y)" "близнец: хук в Job красный → отправка остановлена, ссылки нет"
assert "69 нет да" "$(rslot env FAKE_EXEC=1 FAKE_EXEC_RC=69 HOOK_LOG="$HL" bash "$SLOT" ci-local -- git push -q "$W/bare.git" HEAD:refs/heads/1115-z) $(has_ref 1115-z) $(has "$W/err" 'не выполнилось')" "Job не состоялся (69) → 69 «не выполнилось», не красное, ссылки нет"
be="$(jn ' enter id=')"; rm -f "$HL"
assert "0 1 да $((be + 1))" "$(rslot env FAKE_AVAIL=1 FAKE_EXEC=1 HOOK_LOG="$HL" bash "$SLOT" ci-local -- git push -q "$W/bare.git" HEAD:refs/heads/1115-w) $(grep -c '^job=нет ' "$HL" 2>/dev/null) $(has_ref 1115-w) $(jn ' enter id=')" "близнец: кластер недоступен → хук локально слотом (enter в журнале)"
be="$(jn ' enter id=')"; b78="$(jn 'route=push rc=1 hook_rc=78 ')"; rm -f "$HL"
assert "77   нет $be $((b78 + 1))" "$(rslot env FAKE_EXEC=1 HOOK_LOG="$HL" bash "$SLOT" ci-local -- git push -q "$W/bare.git" HEAD~1:refs/heads/1115-v) $(grep -c '^job=1 ' "$HL" 2>/dev/null) $(grep -c '^job=нет ' "$HL" 2>/dev/null) $(has_ref 1115-v) $(jn ' enter id=') $(jn 'route=push rc=1 hook_rc=78 ')" "отправка не головы копии: переходник — 78, Job не звался, та же отправка локально слотом с хуком"
# Замок отправки (класс «параллельные-отправки-ветки», 5 случаев: вторая отправка той же ветки
# теряла ref ПОСЛЕ полного хука): идёт отправка (репозиторий, ветка) — вторая отказывает 64 ДО хука.
PLF="$HEAVY_SLOT_DIR/push-locks/bare--1314-l.lock"; mkdir -p "${PLF%/*}"; rm -f "$W/held"
( exec 9>> "$PLF"; flock -n 9 && : > "$W/held"; sleep 30 ) & PLH=$!
for _ in $(seq 1 50); do [ -e "$W/held" ] && break; sleep 0.1; done
assert "64 да нет" "$(rslot env FAKE_EXEC=1 HOOK_LOG="$HL" bash "$SLOT" ci-local -- git push -q "$W/bare.git" HEAD:refs/heads/1314-l) $(has "$W/err" 'уже идёт') $(has_ref 1314-l)" "замок отправки: та же ветка того же репозитория при идущей отправке — 64 до хука, ref не тронут"
assert "0 да" "$(rslot env FAKE_EXEC=1 HOOK_LOG="$HL" bash "$SLOT" ci-local -- git push -q "$W/bare.git" HEAD:refs/heads/1314-m) $(has_ref 1314-m)" "близнец: другая ветка того же репозитория при идущей отправке — идёт"
kill "$PLH" 2>/dev/null; wait "$PLH" 2>/dev/null
assert "0 да" "$(rslot env FAKE_EXEC=1 HOOK_LOG="$HL" bash "$SLOT" ci-local -- git push -q "$W/bare.git" HEAD:refs/heads/1314-l) $(has_ref 1314-l)" "близнец: первая отправка вышла — та же ветка идёт (замок держит лишь живая)"

echo "── маршрут Job: запись проверенного — на машине, повтор проверенной вершины Job не ставит (ws#1288, kacho#3336)"
# Приёмка ws#1288: Job судит в своём клоне со своей .git, запись хука оставалась в поде, и
# ускорение в маршруте Job не срабатывало ни разу. Здесь «pod» — клон со СВОЕЙ .git
# (FAKE_EXEC_CLONE двойника); предикат — настоящий prepush-new-commits.sh воркспейса (побайтово
# равен копии kacho — check-28); хук клона повторяет форму хука kacho: предикат 0 — «наборы не
# нужны», KACHO_PREPUSH_SKIP_ONLY=1 — 79 вместо наборов, наборы — строкой в журнал, зелёный —
# запись вершины (HOOK_NOREC — диапазон не покрыл, не пишет; FAKE_DIVERGE — предикату не верит).
RJ="$W/rjob"; git init -q -b 1288-x "$RJ"; git -C "$RJ" remote add origin https://github.com/PRO-Robotech/kacho.git
mkdir -p "$RJ/scripts/hooks"; cp "$HERE/hooks/prepush-new-commits.sh" "$RJ/scripts/hooks/"
cat > "$RJ/scripts/hooks/pre-push" << 'JHOOK'
#!/usr/bin/env bash
in="$(cat)"; tip="$(printf '%s\n' "$in" | awk 'NF >= 4 { print $2; exit }')"
pred="$(git rev-parse --show-toplevel)/scripts/hooks/prepush-new-commits.sh"
if [ -z "${FAKE_DIVERGE:-}" ] && printf '%s\n' "$in" | bash "$pred" > /dev/null 2>&1; then
    echo "skip job=${FAKE_IN_JOB:-нет}" >> "$HOOK_LOG"; echo "pre-push: наборы не нужны" >&2; exit 0
fi
[ "${KACHO_PREPUSH_SKIP_ONLY:-0}" != 1 ] || exit 79
echo "suites job=${FAKE_IN_JOB:-нет} $tip" >> "$HOOK_LOG"
[ "${HOOK_RC:-0}" = 0 ] || exit "$HOOK_RC"
[ -n "${HOOK_NOREC:-}" ] || bash "$pred" --record "$tip" >&2
exit 0
JHOOK
chmod +x "$RJ/scripts/hooks/pre-push"; echo a > "$RJ/f"; git -C "$RJ" add -A; sandbox_git -C "$RJ" commit -q -m base
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\nexec "$(git rev-parse --show-toplevel)/scripts/hooks/pre-push" "$@"\n' > "$RJ/.git/hooks/pre-push"; chmod +x "$RJ/.git/hooks/pre-push"
git init -q --bare "$W/bare-j.git"
jref() { git -C "$W/bare-j.git" rev-parse --verify --quiet "refs/heads/$1" > /dev/null && echo да || echo нет; }
jrec() { (cd "$RJ" && bash scripts/hooks/prepush-new-commits.sh --recorded "$1") && echo да || echo нет; }
# Счёт строк журнала хука; журнала нет — 0, а не пусто (ws#1334: мутант «79 — итог» краснел на main).
jlog() { [ -e "$HL" ] || { echo 0; return; }; grep -c "^$1" "$HL" || true; }
jnew() { echo "$1" > "$RJ/n-$1"; git -C "$RJ" add -A; sandbox_git -C "$RJ" commit -q -m "$1"; git -C "$RJ" rev-parse HEAD; }
jpush() { local s="$1" ref="$2"; shift 2; rm -f "$W/argv"; RDIR="$RJ" rslot env FAKE_EXEC=1 FAKE_EXEC_CLONE=1 HOOK_LOG="$HL" "$@" bash "$s" ci-local -- git push -q "$W/bare-j.git" HEAD:refs/heads/"$ref"; }
jargv() { [ -e "$W/argv" ] && echo Job || echo без-Job; }
rm -f "$HL"; JH="$(jnew j1)"
br="$(jn 'route=push rc=0 hook_rc=0 verified=record ')"
assert "0 Job 1 да да 1 $((br + 1))" "$(jpush "$SLOT" 1288-a) $(jargv) $(jlog 'suites job=1 ') $(jref 1288-a) $(jrec "$JH") $(wc -l < "$RJ/.git/kacho-prepush-verified") $(jn 'route=push rc=0 hook_rc=0 verified=record ')" "J1: новая вершина — хук Job-ом в клоне со своей .git, зелёный; вершина внесена в запись МАШИНЫ (строка heavy-slot-push-verified), verified=record в журнале"
bs="$(jn 'route=push rc=0 hook_rc=0 verified=skip ')"; rm -f "$HL"
assert "0 без-Job 0 1 да да $((bs + 1))" "$(jpush "$SLOT" 1288-b) $(jargv) $(jlog 'suites ') $(jlog 'skip job=нет') $(jref 1288-b) $(has "$W/err" 'Job не ставится') $(jn 'route=push rc=0 hook_rc=0 verified=skip ')" "J2: та же вершина новым именем — Job не ставится, хук идёт на машине до «наборы не нужны», ссылка ушла, verified=skip"
rm -f "$HL"
assert "0 Job 1 да" "$(jpush "$SLOT" 1288-c FAKE_DIVERGE=1) $(jargv) $(jlog 'suites job=1 ') $(jref 1288-c)" "близнец J2: предикат сказал 0, хук на машине погнал бы наборы (79) — хук уходит Job-ом, а не теряется и не гонит наборы на машине"
rm -f "$HL"; JN="$(jnew j2)"
assert "0 Job 1 нет" "$(jpush "$SLOT" 1288-d HOOK_NOREC=1) $(jargv) $(jlog 'suites job=1 ') $(jrec "$JN")" "близнец J1: хук в Job зелёный, но вершину не записал (диапазон не покрыл) — на машине записи нет"
rm -f "$HL"
assert "0 Job 1" "$(jpush "$SLOT" 1288-e) $(jargv) $(jlog 'suites job=1 ')" "близнец J2: незаписанная вершина новым именем — Job снова ставится"
rm -f "$HL"; JR="$(jnew j3)"
assert "1 Job нет нет" "$(jpush "$SLOT" 1288-f HOOK_RC=1) $(jargv) $(jref 1288-f) $(jrec "$JR")" "близнец J1: хук в Job красный — отправки нет, вершина не записана"
# Мутанты на месте правки: каждый ложится одной строкой и роняет свою пробу выше.
# shellcheck disable=SC2016  # выражения в кавычках — текст переходника, раскрывать нельзя
sed 's/^if \[ -f "\$pred" \] && (cd "\$HS_TOP" && printf/if false \&\& (cd "$HS_TOP" \&\& printf/' "$SLOT" > "$W/slot-mut-1288pre.sh"
# shellcheck disable=SC2016
sed 's/^if \[ "\$rc" = 0 \] && \[ -f "\$pred" \] && grep -qxF/if false \&\& grep -qxF/' "$SLOT" > "$W/slot-mut-1288rec.sh"
# shellcheck disable=SC2016
sed 's/^    if \[ "\$rc" -ne 79 \]; then echo skip/    if true; then echo skip/' "$SLOT" > "$W/slot-mut-1288div.sh"
for m in pre rec div; do assert 1 "$(diff "$SLOT" "$W/slot-mut-1288$m.sh" | grep -c '^<')" "мутант ws#1288 «$m» лёг ровно одной строкой"; done
rm -f "$HL"; JM="$(jnew j4)"
assert "0 Job" "$(jpush "$SLOT" 1288-g) $(jargv)" "посев мутанта «pre»: вершина j4 записана на машине"
rm -f "$HL"
assert "0 Job 1" "$(jpush "$W/slot-mut-1288pre.sh" 1288-h) $(jargv) $(jlog 'suites job=1 ')" "мутант «запись машины до Job не спрошена»: записанная вершина снова гонит Job — проба J2 его ловит"
rm -f "$HL"; JM="$(jnew j5)"
assert "0 Job нет" "$(jpush "$W/slot-mut-1288rec.sh" 1288-i) $(jargv) $(jrec "$JM")" "мутант «запись пода не возвращается»: зелёный Job — на машине записи нет (прежний дефект приёмки) — проба J1 его ловит"
# Посев мутанта «div»: голова j5 (мутант «rec» её не записал) вносится в запись машины, иначе
# предикат скажет «не проверена», отправка уйдёт в Job мимо строки мутанта и проба промолчит.
(cd "$RJ" && bash scripts/hooks/prepush-new-commits.sh --record "$JM") > /dev/null 2>&1
assert "да" "$(jrec "$JM")" "посев мутанта «div»: вершина j5 записана на машине — переходник дойдёт до ветви 79"
rm -f "$HL"
assert "1 без-Job 0" "$(jpush "$W/slot-mut-1288div.sh" 1288-j FAKE_DIVERGE=1) $(jargv) $(jlog 'suites ')" "мутант «79 — итог»: расхождение хука с предикатом роняет отправку без Job — близнец J2 (79 → Job) его ловит"
rm -f "$W/argv" "$W/argv.avail"
assert "77 да нет нет" "$(rslot bash "$SLOT" stand -- bash -c 'touch "$1"' x "$W/st1" dev-up) $(has "$W/err" 'во внешний кластер: в deploy/ продукта make stand-ns-up NS=t984-') $([ -e "$W/st1" ] && echo да || echo нет) $([ -e "$W/argv" ] && echo да || echo нет)" "стенд: dev-up при доступном кластере → 77 с формой своего ns, команда не запускалась"
assert "--available" "$(tr '\n' ' ' < "$W/argv.avail" | sed 's/ $//')" "стенд судит кластер без профиля: стенд ставит stand-ns.sh, не Job профиля"
# Двойник kind: настоящий kind проба не зовёт и при регрессии маршрута — узел не поднимется.
mkdir -p "$W/bin"; printf '#!/usr/bin/env bash\ntouch "%s"\n' "$W/kind-ran" > "$W/bin/kind"; chmod +x "$W/bin/kind"
assert "77 да нет" "$(rslot bash "$SLOT" stand -- "$W/bin/kind" -q create cluster) $(has "$W/err" 'во внешний кластер') $([ -e "$W/kind-ran" ] && echo да || echo нет)" "стенд: kind -q create при доступном кластере → 77 (флаг между kind и create не уводит), kind не запускался"
b="$(jn ' local class=stand proof=rc=69')"
assert "0 да $((b + 1))" "$(FAKE_AVAIL=1 rslot bash "$SLOT" stand -- bash -c 'touch "$1"' x "$W/st2" own-up) $([ -e "$W/st2" ] && echo да || echo нет) $(jn ' local class=stand proof=rc=69')" "стенд: own-up при недоступном кластере → локально, вывод проверки в журнале"
rm -f "$W/argv.avail"
assert "77 нет да" "$(rslot bash "$SLOT" stand -- bash -c 'touch "$1"' x "$W/st3" stand-ns-up) $([ -e "$W/st3" ] && echo да || echo нет) $([ -e "$W/argv.avail" ] && echo да || echo нет)" "строка оболочки со словом stand-ns-up — слов строки слот не судит: при доступном кластере 77 (ws#1301)"
echo "── --local судится: при принимающем кластере — 77, локально лишь при отказавшем механизме (ws#1291; прежде мутант G — ws#1105)"
rm -f "$W/argv" "$W/argv.avail"
assert "17" "$(rslot bash "$SLOT" lint -- go version)" "контроль: go version без флага в чистом клоне → run.sh (17)"
b="$(jn ' bypass-local class=lint why=проба G: переносимая команда локально')"; be="$(jn ' external class=lint how=--local «проба G')"
rm -f "$W/argv" "$W/argv.avail"
assert "77 нет да нет $b $((be + 1)) да" "$(rslot bash "$SLOT" --local 'проба G: переносимая команда локально' lint -- go version) $([ -e "$W/argv" ] && echo да || echo нет) $([ -e "$W/argv.avail" ] && echo да || echo нет) $(has "$W/out" 'go version go') $(jn ' bypass-local class=lint why=проба G: переносимая команда локально') $(jn ' external class=lint how=--local «проба G') $(has "$W/err" 'отклонён: кластер принимает')" "та же команда с --local при принимающем кластере → 77: кластер спрошен, Job не звался, локально не шла, bypass-local нет, external в журнале, причина названа"
rm -f "$W/argv.avail"
assert "77 да" "$(FAKE_AVAIL=3 rslot bash "$SLOT" --local 'проба G: кластер занят местом' lint -- go version) $(has "$W/err" 'занят: место ждётся --wait N')" "--local при занятом кластере (75) → 77: занятость — не недоступность"
b="$(jn ' bypass-local class=lint why=проба G: кластер не отвечает proof=rc=69')"
assert "0 да $((b + 1))" "$(FAKE_AVAIL=1 rslot bash "$SLOT" --local 'проба G: кластер не отвечает' lint -- go version) $(has "$W/out" 'go version go') $(jn ' bypass-local class=lint why=проба G: кластер не отвечает proof=rc=69')" "близнец: --local при недоступном кластере → локально, вывод проверки — proof= строки bypass-local"
b="$(jn ' bypass-local class=lint why=проба G: дефект обёртки proof=rc=70')"
assert "69 $b" "$(FAKE_AVAIL=8 rslot bash "$SLOT" --local 'проба G: дефект обёртки' lint -- go version) $(jn ' bypass-local class=lint why=проба G: дефект обёртки proof=rc=70')" "--local при дефекте обёртки (70) → 69: дефект — не недоступность, локально не идёт (ws#1301)"
b="$(jn 'why=проба G: внешнего пути нет moot=')"; rm -f "$W/argv.avail"
assert "77 да $b да" "$(rslot bash "$SLOT" --local 'проба G: внешнего пути нет' --wait 0 newman -- true) $([ -e "$W/argv.avail" ] && echo да || echo нет) $(jn 'why=проба G: внешнего пути нет moot=') $(has "$W/err" 'задача ws#1303, до неё не выполнилось')" "--local у класса без внешнего пути при доступном кластере → 77, кластер спрошен, задача маршрута названа (ws#1301)"
b="$(jn 'bypass-local class=lint why=проба G: нет yq в образе Job')"
assert "77 нет $b да" "$(rslot bash "$SLOT" --local 'проба G: нет yq в образе Job' lint -- go version) $(has "$W/out" 'go version go') $(jn 'bypass-local class=lint why=проба G: нет yq в образе Job') $(has "$W/err" 'причина флага не основание')" "--local «нет yq в образе Job» при доступном кластере → 77: недостающий инструмент чинится в образе (ws#1301)"
# shellcheck disable=SC2016  # образец sed и тело `sh -c` раскрывает не эта оболочка
sed 's|^    \[ "\$REMOTE_ON" = 1 \] \&\& local_judge$|    :|' "$SLOT" > "$W/slot-mut-lj.sh"
rm -f "$W/argv.avail"
assert "1 0" "$(diff "$SLOT" "$W/slot-mut-lj.sh" | grep -c '^<') $(rslot bash "$W/slot-mut-lj.sh" --local 'проба G: мутант без суждения' lint -- go version)" "мутант «--local не судится»: при принимающем кластере локально (0) — проба «77» выше его ловит"
(cd "$R" && bash "$SLOT" --status > "$W/status" 2>/dev/null)
assert "да" "$(has "$W/status" 'why=проба G: кластер не отвечает')" "обход G при недоступном кластере виден в --status"
assert 64 "$(rslot bash "$SLOT" lint --local 'проба: флаг после класса' -- go version)" "--local после класса — 64 (форма вызова), не тихий локальный запуск"
b="$(jn 'why=проба переноса строки вторая строка')"
assert "0 $((b + 1)) 0" "$(FAKE_AVAIL=1 rslot bash "$SLOT" --local $'проба переноса строки\nвторая строка' --wait 0 newman -- true) $(jn 'why=проба переноса строки вторая строка') $(grep -c '^вторая строка' "$JL")" "причина с переводом строки — одна строка журнала, вторая строкой журнала не стала"

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

echo "── стенд: обёртка поднимает стенд — признак в СОДЕРЖИМОМ скрипта, на глубину одного вызова (ws#1244 L2)"
# 2026-10-18 скрипт, внутри которого `kind create` либо up.sh, уходил «локально — команда стенда не
# поднимает локальный стенд»: судились лишь слова argv. kind здесь — двойник ($W/bin/kind).
printf '#!/usr/bin/env bash\n%s/bin/kind create cluster --name t1244\ntouch "%s"\n' "$W" "$W/wk-ran" > "$W/kd/wrap-kind.sh"
printf '#!/usr/bin/env bash\nbash ./stand-up.sh\n' > "$W/kd/wrap-up.sh"; printf '#!/usr/bin/env bash\ntouch "%s"\n' "$W/wk-ran" > "$W/kd/stand-up.sh"
# shellcheck disable=SC2016  # строка скрипта-обёртки, раскрывает он сам
printf '#!/usr/bin/env bash\n"$(dirname "$0")/helper.sh" "$@"\n' > "$W/kd/wrap-outer.sh"; printf '#!/usr/bin/env bash\nctlptl apply -f cluster.yaml\n' > "$W/kd/helper.sh"
printf '#!/usr/bin/env bash\n# kind create cluster — здесь не зовётся: стенд внешний\nKUBECONFIG=/dev/null kubectl version --client >/dev/null 2>&1 || true\ntouch "%s"\n' "$W/wk-ran" > "$W/kd/wrap-kubectl.sh"
printf '#!/usr/bin/env bash\n./mid.sh\n' > "$W/kd/wrap-deep.sh"; printf '#!/usr/bin/env bash\n./deep.sh\n' > "$W/kd/mid.sh"; printf '#!/usr/bin/env bash\nctlptl version >/dev/null 2>&1 || true\n' > "$W/kd/deep.sh"
chmod +x "$W/kd"/*.sh; rm -f "$W/wk-ran" "$W/kind-ran"
assert "77 да нет нет" "$(RDIR="$W/kd" rslot bash "$SLOT" stand -- ./wrap-kind.sh) $(has "$W/err" 'по признаку содержимого') $([ -e "$W/wk-ran" ] && echo да || echo нет) $([ -e "$W/kind-ran" ] && echo да || echo нет)" "обёртка с kind create при доступном кластере → 77, признак содержимого назван, обёртка не запускалась"
assert "77 да" "$(RDIR="$W/kd" rslot bash "$SLOT" stand -- bash wrap-up.sh) $(has "$W/err" 'stand-up.sh')" "bash <обёртка>, зовущая up-скрипт → 77, признак (stand-up.sh) назван"
assert "77 да" "$(RDIR="$W/kd" rslot bash "$SLOT" stand -- ./wrap-outer.sh) $(has "$W/err" 'helper.sh')" "обёртка → помощник с ctlptl (глубина одного вызова) → 77, файл признака назван"
b="$(jn 'локально по признаку содержимого')"
assert "0 да $((b + 1))" "$(RDIR="$W/kd" FAKE_AVAIL=1 rslot bash "$SLOT" stand -- ./wrap-kind.sh) $([ -e "$W/wk-ran" ] && echo да || echo нет) $(jn 'локально по признаку содержимого')" "та же обёртка при недоступном кластере → локально, в журнале «локально по признаку содержимого»"
rm -f "$W/wk-ran"
assert "77 нет да" "$(RDIR="$W/kd" rslot bash "$SLOT" stand -- ./wrap-kubectl.sh) $([ -e "$W/wk-ran" ] && echo да || echo нет) $(has "$W/err" 'у команды стенда внешнего маршрута нет')" "близнец: обёртка лишь с kubectl — подъёма нет, но и внешнего маршрута нет: при доступном кластере 77 (ws#1301)"
rm -f "$W/wk-ran"
assert "0 да" "$(RDIR="$W/kd" FAKE_AVAIL=1 rslot bash "$SLOT" stand -- ./wrap-kubectl.sh) $([ -e "$W/wk-ran" ] && echo да || echo нет)" "близнец: та же обёртка при недоступном кластере → локально"
assert "77" "$(RDIR="$W/kd" rslot bash "$SLOT" stand -- ./wrap-deep.sh)" "обёртка → посредник → помощник с ctlptl (глубина два): прежняя граница закрыта — при доступном кластере 77 (ws#1301)"

echo "── стенд: флаг СО ЗНАЧЕНИЕМ между kind и create — подъём (ws#1250 K2, C1)"
# K2: признак допускал между kind и create лишь слова на «-», и значение флага («3») рвало совпадение;
# разбор argv брал значение флага за подкоманду.
rm -f "$W/kind-ran"
assert "77 да нет" "$(rslot bash "$SLOT" stand -- "$W/bin/kind" --verbosity 3 create cluster) $(has "$W/err" 'во внешний кластер') $([ -e "$W/kind-ran" ] && echo да || echo нет)" "argv: kind --verbosity 3 create при доступном кластере → 77, kind не запускался"
assert "77 нет" "$(rslot bash "$SLOT" stand -- "$W/bin/kind" -v 3 create cluster) $([ -e "$W/kind-ran" ] && echo да || echo нет)" "argv: kind -v 3 create → 77"
assert "0 да" "$(rslot bash "$SLOT" stand -- "$W/bin/kind" -v 3 delete cluster) $([ -e "$W/kind-ran" ] && echo да || echo нет)" "близнец argv: kind -v 3 delete (не подъём) → идёт локально"
rm -f "$W/kind-ran"
printf '#!/usr/bin/env bash\n%s/bin/kind -v 3 create cluster\n' "$W" > "$W/kd/wrap-kv.sh"; chmod +x "$W/kd/wrap-kv.sh"
assert "77 да" "$(RDIR="$W/kd" rslot bash "$SLOT" stand -- ./wrap-kv.sh) $(has "$W/err" 'по признаку содержимого')" "содержимое: kind -v 3 create → 77 по признаку содержимого"

echo "── стенд: текст скрипта судится весь, кроме строки-комментария; вывод echo и хвостовой комментарий не отбрасываются (ws#1250 C2)"
# Отбрасывание сегментов echo/printf четыре круга подряд давало ложный зелёный одного рода (kind
# исполнялся локально при доступном кластере): <(…), ${ cmd; }, затем многострочная двойная кавычка —
# построчный разбор оболочки текстом неполон. Снято (решение диспетчера, fa-b6): лишние 77 безопасны.
mkw() { printf '#!/usr/bin/env bash\n%s\ntouch "%s"\n' "$2" "$W/wk-ran" > "$W/kd/$1.sh"; chmod +x "$W/kd/$1.sh"; }
mkw wrap-funsub "echo \${ $W/bin/kind create cluster; }"
mkw wrap-valsub "echo \${| $W/bin/kind create cluster; }"
mkw wrap-dsub "echo \$($W/bin/kind create cluster)"
mkw wrap-dsubq "echo \"\$($W/bin/kind create cluster)\""
mkw wrap-bq "printf '%s' \`$W/bin/kind create cluster\`"
mkw wrap-psub "echo <($W/bin/kind create cluster)"
mkw wrap-psub-out "printf x >($W/bin/kind create cluster)"
mkw wrap-bashc "echo \"подъём\"; bash -c \"$W/bin/kind create cluster\""
mkw wrap-subst "echo \"\$($W/bin/kind create cluster)\" # вывод"
mkw wrap-pipe-sh "echo $W/bin/kind create cluster | sh"
# Многострочная двойная кавычка: вторая строка — echo '…' целиком в одинарных, но $(…) раскрывает
# внешняя "…", открытая строкой выше.
mkw wrap-ml "echo \"начало
echo '\$($W/bin/kind create cluster)'
конец\""
for ps in wrap-funsub wrap-valsub wrap-dsub wrap-dsubq wrap-bq wrap-psub wrap-psub-out wrap-bashc wrap-subst wrap-pipe-sh wrap-ml; do
    rm -f "$W/kind-ran" "$W/wk-ran"
    assert "77 да нет нет" "$(RDIR="$W/kd" rslot bash "$SLOT" stand -- "./$ps.sh") $(has "$W/err" 'по признаку содержимого') $([ -e "$W/wk-ran" ] && echo да || echo нет) $([ -e "$W/kind-ran" ] && echo да || echo нет)" "$ps: kind create в строке echo/printf — признак → 77, ни обёртка, ни kind не запускались"
done
# shellcheck disable=SC2016  # строки скрипта: раскрывает он сам
mkw wrap-funsub-walk 'echo ${ ./helper.sh; }'
mkw wrap-psub-walk 'echo <(./helper.sh)'
for ps in wrap-funsub-walk wrap-psub-walk; do
    assert "77 да" "$(RDIR="$W/kd" rslot bash "$SLOT" stand -- "./$ps.sh") $(has "$W/err" 'helper.sh: ctlptl')" "$ps: обход на глубину один читает помощник с ctlptl, названный в строке echo → 77, признак «helper.sh: ctlptl» назван"
done
# Законный близнец: строка-комментарий целиком — не вызов.
mkw wrap-cmt-line '# kind create cluster'
rm -f "$W/wk-ran"
assert "77 нет да нет" "$(RDIR="$W/kd" rslot bash "$SLOT" stand -- ./wrap-cmt-line.sh) $([ -e "$W/wk-ran" ] && echo да || echo нет) $(has "$W/err" 'у команды стенда внешнего маршрута нет') $(has "$W/err" 'по признаку содержимого')" "законный близнец: «# kind create cluster» — комментарий, признака нет; внешнего маршрута нет — 77 (ws#1301)"
# [BOUND] fail-closed (шапка stand_sign): echo/printf и хвостовой комментарий с признаком — признак,
# 77; лишний красный безопасен — команда уходит на кластер, а не тайно поднимает стенд локально.
bound_fc() {
    if [ "$1" = "$2" ]; then echo "  [BOUND] fail-closed (лишний красный, граница): $3"; bound=$((bound + 1))
    else echo "  [FAIL] граница fail-closed «$3» — ожидалось «$1», получено «$2»: шапка устарела" >&2; fail=$((fail + 1)); fi
}
mkw wrap-bd-echo 'echo "kind create"'
mkw wrap-bd-tail 'true # kind create cluster — не здесь'
# shellcheck disable=SC2016  # строки скрипта: раскрывает он сам
mkw wrap-bd-sq "echo 'kind create cluster \$HOME'"
mkw wrap-bd-printf 'printf "%s\n" "run kind create cluster yourself"'
# shellcheck disable=SC2016  # строки скрипта: раскрывает он сам
mkw wrap-bd-var 'echo "kind create ${var}"'
mkw wrap-bd-psubq 'echo "<(kind create cluster)"'
for bd in wrap-bd-echo wrap-bd-tail wrap-bd-sq wrap-bd-printf wrap-bd-var wrap-bd-psubq; do
    rm -f "$W/wk-ran"
    bound_fc "77 нет" "$(RDIR="$W/kd" rslot bash "$SLOT" stand -- "./$bd.sh") $([ -e "$W/wk-ran" ] && echo да || echo нет)" "$bd: литерал kind create в выводе echo/printf либо в хвостовом комментарии → 77"
done
# Мутант «сегмент echo снова отбрасывается»: подъём из строки echo уходит локально — пробы
# wrap-dsub и wrap-ml выше его ловят.
for ps in wrap-dsub wrap-ml; do
    rm -f "$W/kind-ran"
    # shellcheck disable=SC2016  # тексты мутанта — строки исходника слота
    assert "0 77 нет нет" "$(tmut "grep -vE '^[[:space:]]*#' \"\$f\"" "grep -vE '^[[:space:]]*(#|echo[[:space:]])' \"\$f\"") $(RDIR="$W/kd" rslot bash "$W/tmut/heavy-slot.sh" stand -- "./$ps.sh") $([ -e "$W/kind-ran" ] && echo да || echo нет) $(has "$W/err" 'по признаку содержимого')" "мутант «сегмент echo отбрасывается»: $ps — признак не назван (77 без маршрута) — проба $ps выше, ждущая «по признаку содержимого», его ловит"
done

echo "── стенд во внешнем ns — без слота машины: на машине лишь kubectl и helm (ws#1143)"
# Журнал слотов до правки: stand-ns-up/down/census/forward — 139 запусков, пик
# памяти ≤ 118 МиБ, ожидание слота до 1343 с (17.10 — дважды больше 10 мин).
# Фикстура — настоящий клон с origin PRO-Robotech/kacho: отслеживаемые deploy/Makefile
# (цели зовут scripts/stand-ns.sh, как в продукте) и deploy/scripts/stand-ns.sh,
# который пишет метку sn-<подкоманда> и зовёт kubectl (форма границы PATH ниже).
KC="$W/kc"; SN="$KC/deploy"
git init -q -b 1143-x "$KC"; git -C "$KC" remote add origin https://github.com/PRO-Robotech/kacho.git
mkdir -p "$SN/scripts"
# shellcheck disable=SC2016  # тексты фикстуры раскрывают make и bash
printf 'stand-ns-up:\n\t@bash scripts/stand-ns.sh up "$(NS)"\nstand-ns-down:\n\t@bash scripts/stand-ns.sh down "$(NS)"\nstand-ns-census:\n\t@bash scripts/stand-ns.sh census\nstand-ns-run:\n\t@bash scripts/stand-ns.sh run "$(NS)"\ndev-up:\n\t@touch "%s/sn-devup"\n' "$W" > "$SN/Makefile"
# shellcheck disable=SC2016
# kubectl --client: настоящий клиент к серверу не идёт (кластер проба не трогает).
printf '#!/usr/bin/env bash\nKUBECONFIG=/dev/null kubectl version --client >/dev/null 2>&1 || true\ntouch "%s/sn-$1"\n' "$W" > "$SN/scripts/stand-ns.sh"; chmod +x "$SN/scripts/stand-ns.sh"
git -C "$KC" add deploy; sandbox_git -C "$KC" commit -q -m stand
# Чужое: каталог с тем же именем цели и тем же именем скрипта — исполняют тяжёлое.
EV="$W/evil"; mkdir -p "$EV/scripts"
printf 'stand-ns-up:\n\t@touch "%s/ev-ran"\n' "$W" > "$EV/Makefile"
printf '#!/usr/bin/env bash\ntouch "%s/ev-ran"\n' "$W" > "$EV/stand-ns.sh"; chmod +x "$EV/stand-ns.sh"
printf 'stand-ns-up:\n\t@touch "%s/ev-ran"\n' "$W" > "$EV/inj.mk"
# Держатели живут до явного отпускания (файл sn-release, предел 60 с): со сном фиксированной
# длины под нагрузкой машины они выходили раньше близнецов, и 74 близнеца не судилось.
rm -f "$W/sn-release"
# shellcheck disable=SC2016  # строка дочерней оболочки, $0 раскрывает она
for i in 1 2 3; do HEAVY_SLOT_WAIT_S=10 HEAVY_SLOT_BUDGET_MIB=20 bash "$SLOT" docker -- bash -c 'for _ in $(seq 1 300); do [ -e "$0" ] && exit 0; sleep 0.2; done' "$W/sn-release" 2>/dev/null & eval "SH$i=\$!"; done
for _ in $(seq 1 50); do [ "$(nslots)" -ge 3 ] && break; sleep 0.2; done
assert 3 "$(nslots)" "контроль: три слота заняты разом"
snx() { [ -e "$W/$1" ] && echo да || echo нет; }
# Вход в слот классом stand: держатели идут классом docker, и их поздняя строка enter
# (файл слота появляется раньше строки журнала) счёт не сдвигает.
ens() { grep -cE ' enter id=[^ ]+ class=stand ' "$JL" 2>/dev/null || true; }
# snclr — снять метки исполнения: каждое утверждение судит лишь свой вызов.
snclr() { rm -f "$W/ev-ran" "$W/sn-up" "$W/sn-down" "$W/sn-census" "$W/sn-run" "$W/sn-devup" "$W/sn-forward" "$W/sn-unforward"; }
# sn <каталог> <команда…> — класс stand без ожидания слота: код; метки сняты до вызова.
sn() { local d="$1"; shift; snclr; RDIR="$d" rslot env HEAVY_SLOT_WAIT_S=0 bash "$SLOT" stand -- "$@"; }
# snenv <каталог> <ПЕРЕМЕННАЯ=…> <команда…> — то же с переменной в окружении вызова слота.
snenv() { local d="$1" e="$2"; shift 2; snclr; RDIR="$d" rslot env HEAVY_SLOT_WAIT_S=0 "$e" bash "$SLOT" stand -- "$@"; }
be="$(ens)"; bx="$(jn ' external-ns class=stand slot=нет busy_slots=3 waited=0s ')"
t0="$(date +%s%N)"
r="$(sn "$SN" make -s stand-ns-up NS=t1143-x)"
ms=$(( ($(date +%s%N) - t0) / 1000000 ))
assert "0 да $be $((bx + 1))" "$r $(snx sn-up) $(ens) $(jn ' external-ns class=stand slot=нет busy_slots=3 waited=0s ')" "make stand-ns-up в deploy/ клона при трёх занятых слотах → исполнился сразу, слота не брал, журнал: занято 3, ожидание 0 с"
echo "  [MEASURE] stand-ns-up при занятых слотах $(nslots) из 3: код $r; журнал — «$(grep -o 'external-ns class=stand slot=[^ ]* busy_slots=[0-9]* waited=[0-9]*s' "$JL" | tail -n 1)»; вызов целиком ${ms} мс"
assert "да" "$(has "$W/err" 'слот машины не занимается')" "причина без слота названа в stderr"
assert "0 да" "$(sn "$KC" make -s -C deploy --no-print-directory stand-ns-down NS=t1143-x STACK=dev-prod REF=HEAD) $(snx sn-down)" "make -C deploy stand-ns-down NS STACK REF из корня клона → без слота"
assert "0 да" "$(sn "$KC" make --quiet -C deploy stand-ns-census EXPIRED=1) $(snx sn-census)" "make -C deploy stand-ns-census EXPIRED=1 → без слота"
for sub in census forward unforward down up; do
    rm -f "$W/sn-$sub"
    assert "0 да" "$(sn "$KC" bash deploy/scripts/stand-ns.sh "$sub" t1143-x) $(snx "sn-$sub")" "bash deploy/scripts/stand-ns.sh $sub клона → без слота"
done
rm -f "$W/sn-census"
assert "0 да" "$(sn "$W" "$SN/scripts/stand-ns.sh" census) $(snx sn-census)" "stand-ns.sh клона по абсолютному пути из чужого каталога → без слота"
assert "$be" "$(ens)" "ни одна из форм выше слота не занимала (enter класса stand)"
# Обход слота (приёмка ws#1143, check-verifier): каждая форма — под слотом, 74, тяжёлое
# не исполнилось. ev-ran — метка чужого рецепта и скрипта.
assert "74 нет" "$(sn "$EV" make -s stand-ns-up NS=t1143-x) $(snx ev-ran)" "обход: подменённый рецепт (Makefile чужого каталога с целью stand-ns-up) → под слотом, 74"
assert "74 нет" "$(sn "$KC" make -s -C "$EV" stand-ns-up) $(snx ev-ran)" "обход: make -C <чужой каталог> stand-ns-up → под слотом, 74"
assert "74 нет" "$(sn "$KC" make -s -C deploy -C .. stand-ns-up) $(snx ev-ran)" "обход: -C уводит из deploy/ (deploy, затем ..) → под слотом, 74"
assert "77 нет" "$(sn "$KC" bash "$EV/stand-ns.sh" up t1143-x) $(snx ev-ran)" "обход: bash <чужой путь>/stand-ns.sh up → 77: внешнего маршрута нет, на машине не исполнялся (ws#1301)"
assert "77 нет" "$(sn "$KC" "$EV/stand-ns.sh" up t1143-x) $(snx ev-ran)" "обход: <чужой путь>/stand-ns.sh up без bash → 77: внешнего маршрута нет, на машине не исполнялся (ws#1301)"
# shellcheck disable=SC2016  # присваивание make — буквально
assert "74 нет нет" "$(sn "$SN" make -s stand-ns-up 'NS=$(shell touch '"$W"'/ev-ran)') $(snx ev-ran) $(snx sn-up)" "обход: присваивание NS='\$(shell …)' → под слотом, 74"
# shellcheck disable=SC2016
assert "74 нет" "$(sn "$SN" make -s stand-ns-up 'NS=`touch x`') $(snx sn-up)" "обход: присваивание с обратной кавычкой → под слотом, 74"
assert "74 нет нет" "$(sn "$SN" make -s stand-ns-up MAKEFILES="$EV/inj.mk") $(snx ev-ran) $(snx sn-up)" "обход: присваивание MAKEFILES=<файл> → под слотом, 74"
assert "74 нет" "$(sn "$SN" make -s stand-ns-up MAKEFILE="$EV/inj.mk") $(snx sn-up)" "обход: присваивание MAKEFILE=<файл> → под слотом, 74"
assert "74 нет" "$(sn "$SN" make -s stand-ns-up FOO=1) $(snx sn-up)" "обход: присваивание вне NS, STACK, REF, EXPIRED → под слотом, 74"
assert "74 нет нет" "$(sn "$SN" env MAKEFILES="$EV/inj.mk" make -s stand-ns-up) $(snx ev-ran) $(snx sn-up)" "обход: обёртка env с MAKEFILES → под слотом, 74"
assert "74 нет нет" "$(snenv "$SN" MAKEFILES="$EV/inj.mk" make -s stand-ns-up) $(snx ev-ran) $(snx sn-up)" "обход: MAKEFILES в окружении вызова → под слотом, 74"
r="$(snenv "$KC" BASH_ENV="$EV/stand-ns.sh" bash deploy/scripts/stand-ns.sh census)"
assert "77 нет" "$r $(snx sn-census)" "обход: BASH_ENV в окружении вызова → 77: внешнего маршрута нет, на машине не исполнялся (ws#1301), stand-ns.sh без слота не исполнялся"
boundary "да" "$(snx ev-ran)" "BASH_ENV вызова исполняет сама оболочка heavy-slot.sh при старте — до суждения слота"
assert "77 нет" "$(sn "$KC" bash -x deploy/scripts/stand-ns.sh up t1143-x) $(snx sn-up)" "обход: ключ bash перед скриптом → 77: внешнего маршрута нет, на машине не исполнялся (ws#1301)"
assert "74 нет" "$(sn "$SN" make -s -f Makefile stand-ns-up NS=t1143-x) $(snx sn-up)" "обход: make -f → под слотом, 74"
printf '\n# правка\n' >> "$SN/Makefile"
assert "74 нет" "$(sn "$SN" make -s stand-ns-up NS=t1143-x) $(snx sn-up)" "обход: deploy/Makefile с неотправленной правкой → под слотом, 74"
git -C "$KC" checkout -q -- deploy/Makefile
printf 'stand-ns-up:\n\t@touch "%s/ev-ran"\n' "$W" > "$SN/GNUmakefile"
assert "74 нет нет" "$(sn "$SN" make -s stand-ns-up NS=t1143-x) $(snx ev-ran) $(snx sn-up)" "обход: GNUmakefile рядом (make взял бы его) → под слотом, 74"
rm -f "$SN/GNUmakefile"
# Близнецы прежних форм: на машине исполняется не только kubectl и helm — слот (74).
assert "77 нет" "$(sn "$SN" make -s stand-ns-run NS=t1143-x) $(snx sn-run)" "близнец: stand-ns-run (CMD идёт на машине) → 77: внешнего маршрута нет, на машине не исполнялся (ws#1301)"
assert "77 нет" "$(sn "$KC" bash deploy/scripts/stand-ns.sh run t1143-x -- true) $(snx sn-run)" "близнец: stand-ns.sh run → 77: внешнего маршрута нет, на машине не исполнялся (ws#1301)"
assert "77 нет" "$(sn "$SN" bash -c 'make -s stand-ns-up NS=t1143-x') $(snx sn-up)" "близнец: строка оболочки со stand-ns-up → 77: внешнего маршрута нет, на машине не исполнялся (ws#1301)"
assert "77 нет" "$(sn "$SN" make -s stand-ns-up stand-ns-run NS=t1143-x) $(snx sn-up)" "близнец: stand-ns-up вместе с иной целью → 77: внешнего маршрута нет, на машине не исполнялся (ws#1301)"
assert "74 нет" "$(FAKE_AVAIL=1 sn "$SN" make -s dev-up) $(snx sn-devup)" "близнец: локальный kind-стенд (dev-up, кластер недоступен) → под слотом, 74"
# ГРАНИЦА (шапка heavy-slot.sh): закоммиченный в клон рецепт и подмена PATH — без слота.
printf 'stand-ns-census:\n\t@touch "%s/ev-ran"\n' "$W" > "$SN/Makefile"; sandbox_git -C "$KC" commit -q -am heavy
boundary "0 да" "$(sn "$SN" make -s stand-ns-census) $(snx ev-ran)" "рецепт, закоммиченный в deploy/Makefile клона, исполняет тяжёлое без слота"
sandbox_git -C "$KC" revert --no-edit HEAD >/dev/null 2>&1
assert "0" "$(git -C "$KC" diff --quiet HEAD~2 HEAD -- deploy; echo $?)" "контроль: откат закоммиченного рецепта вернул deploy/ клона"
mkdir -p "$W/evbin"
printf '#!/usr/bin/env bash\ntouch "%s/ev-ran"\n' "$W" > "$W/evbin/kubectl"; chmod +x "$W/evbin/kubectl"
boundary "0 да" "$(snenv "$KC" PATH="$W/evbin:$PATH" bash deploy/scripts/stand-ns.sh census) $(snx ev-ran)" "PATH подменяет kubectl рецепта — тяжёлое без слота"
assert "3" "$(nslots)" "контроль: держатели всё ещё держат три слота — 74 выше судит слот, а не их уход"
assert "8192" "$(env "${REAL[@]}" bash "$SLOT" --budget stand 2>/dev/null)" "бюджет локального стенда — 8192 МиБ, как был"
touch "$W/sn-release"; wait "$SH1" "$SH2" "$SH3"
be="$(ens)"
assert "0 да $((be + 1))" "$(FAKE_AVAIL=1 sn "$SN" make -s dev-up) $(snx sn-devup) $(ens)" "близнец: слоты вышли — тот же dev-up входит в слот (enter в журнале)"

git init -q -b nodigits "$W/rclone2"; git -C "$W/rclone2" remote add origin https://github.com/PRO-Robotech/kacho.git
echo a > "$W/rclone2/f"; git -C "$W/rclone2" add f; sandbox_git -C "$W/rclone2" commit -q -m p
assert "77 да" "$(RDIR="$W/rclone2" rslot bash "$SLOT" integration -- go version) $(has "$W/err" 'KACHO_TASK=<N>')" "номер задачи не выводится при доступном кластере → 77 с формой KACHO_TASK"
assert "17" "$(RDIR="$W/rclone2" rslot env KACHO_TASK=1105 bash "$SLOT" integration -- go version)" "близнец: тот же клон с KACHO_TASK → run.sh"
echo c >> "$R/f"
assert 64 "$(rslot bash "$SLOT" --local коротко go-race -- true)" "--local без причины (< 12 символов) — 64"
b="$(jn ' bypass-local class=go-race why=проба обхода: стенд снят владельцем')"
rm -f "$W/argv" "$W/argv.avail"
assert "77 нет да $b да" "$(rslot bash "$SLOT" --local 'проба обхода: стенд снят владельцем' go-race -- true) $([ -e "$W/argv" ] && echo да || echo нет) $([ -e "$W/argv.avail" ] && echo да || echo нет) $(jn ' bypass-local class=go-race why=проба обхода: стенд снят владельцем') $(has "$W/err" 'Повтори без --local')" "--local с причиной при доступном кластере и правке → 77 (ws#1291): кластер спрошен, локально не шла, bypass-local нет, подсказка названа"
b="$(jn ' bypass-local class=go-race why=проба обхода: кластер снят владельцем')"
assert "0 $((b + 1))" "$(FAKE_AVAIL=2 rslot bash "$SLOT" --local 'проба обхода: кластер снят владельцем' go-race -- true) $(jn ' bypass-local class=go-race why=проба обхода: кластер снят владельцем')" "близнец: та же правка, узла нет (69) → --local локально, причина в журнале"
# Чтение и поиск разведены: `grep -q` в конце трубы под pipefail рвёт писателя (ws#395).
(cd "$R" && bash "$SLOT" --status > "$W/status" 2>/dev/null)
assert "да" "$(has "$W/status" 'локально по флагу --local')" "обход флагом виден в --status"
FAKE_AVAIL=1 rslot bash "$SLOT" --local 'проба обхода: запись слота' --wait 0 newman -- bash -c 'sleep 3' >/dev/null &
LP=$!
for _ in $(seq 1 25); do ls "$HEAVY_SLOT_DIR"/active/*.slot >/dev/null 2>&1 && break; sleep 0.2; done
(cd "$R" && bash "$SLOT" --status > "$W/status" 2>/dev/null)
assert "да" "$(has "$W/status" 'локально по флагу: проба обхода: запись слота')" "занятый слот с --local показывает причину в --status"
wait "$LP"
git -C "$R" checkout -q -- f

echo "── --enqueue: каталог журналов внутри рабочего дерева git — 64 до постановки, файлы слота копию грязной не делают (ws#1181, kacho#3251)"
# 2026-10-18 на kacho#3251 файлы hs-*.{log,pid,rc} лежали в копии git, хук отправки судил
# «грязную» временную копию без node_modules, и проверки консоли ушли в «НЕ выполнено».
# Законен каталог вне git и каталог в дереве, где git игнорирует ВСЕ четыре файла слота.
git init -q "$W/er" && mkdir -p "$W/er/logs" "$W/er/ign" "$W/er/part" "$W/outside"
printf 'ign/\n' > "$W/er/.gitignore"; printf '*.log\n' > "$W/er/part/.gitignore"
rm -f "$W/e1" "$W/e2" "$W/e3" "$W/e4" "$W/e5"
rc="$(slot bash "$SLOT" --enqueue "$W/er/logs" docker -- touch "$W/e1")"
assert "64 да да 0 0 нет" "$rc $(has "$W/err" 'в рабочем дереве git') $(has "$W/err" "$HEAVY_SLOT_DIR/enq") $(ls -A "$W/er/logs" | wc -l) $(qlen) $([ -e "$W/e1" ] && echo да || echo нет)" "каталог в дереве git, файлы слота не игнорируются → 64 до постановки: причина и каталог вне копии названы, в каталоге пусто, билета нет, команда не запускалась"
rc="$(slot bash "$SLOT" --enqueue "$W/er/ign" docker -- touch "$W/e2")"; RE2="$(rcof)"
assert "0 0 да" "$rc $(await_rc "$RE2") $([ -e "$W/e2" ] && echo да || echo нет)" "близнец: каталог в дереве, но git игнорирует все файлы слота → поставлен и исполнен"
assert "" "$(git -C "$W/er" status --porcelain --untracked-files=all -- ign)" "...и копия чиста: в git status файлов слота нет"
rc="$(slot bash "$SLOT" --enqueue "$W/outside" docker -- touch "$W/e3")"; RE3="$(rcof)"
assert "0 0 да" "$rc $(await_rc "$RE3") $([ -e "$W/e3" ] && echo да || echo нет)" "близнец: каталог вне любого git → поставлен и исполнен"
rc="$(slot bash "$SLOT" --enqueue "$W/er/part" docker -- touch "$W/e4")"
assert "64 да нет" "$rc $(has "$W/err" 'в рабочем дереве git') $([ -e "$W/e4" ] && echo да || echo нет)" "игнорируется лишь *.log, .pid и .rc — нет → 64: судится КАЖДЫЙ из четырёх файлов слота, не один"
n_at="$(grep -c 'if enq_dir_in_tree ' "$SLOT")"
sed 's/if enq_dir_in_tree /if false \&\& enq_dir_in_tree /' "$SLOT" > "$W/slot-mut-1181.sh"
rc="$(slot bash "$W/slot-mut-1181.sh" --enqueue "$W/er/logs" docker -- touch "$W/e5")"; RE5="$(rcof)"; await_rc "$RE5" >/dev/null
assert "1 0 да" "$n_at $rc $([ -n "$(git -C "$W/er" status --porcelain --untracked-files=all -- logs)" ] && echo да || echo нет)" "мутант «проверки каталога нет»: тот же вызов ставится, и копия становится грязной — проба выше его ловит"

echo "── git push: слот печатает, откуда и куда идёт отправка; из первичной копии воркспейса в иную ветку — 64 (ws#1182)"
# Дважды за сутки (2026-10-17…18) `git push origin HEAD:refs/heads/<ветка>` через --enqueue ушёл из
# корня воркспейса, а не из копии задачи, и в чужом репозитории легла ветка с номером чужой
# задачи. Узнаватель — класс «первичная копия того репозитория, где отслеживается сам слот,
# и ветка назначения иная, чем текущая»; перечня каталогов и номеров нет.
git init -q -b main "$W/wsr" && mkdir -p "$W/wsr/scripts" && cp "$SLOT" "$W/wsr/scripts/heavy-slot.sh"
git -C "$W/wsr" add scripts && sandbox_git -C "$W/wsr" commit -q -m ws
git init -q --bare "$W/wsr.git" && git -C "$W/wsr" remote add origin "$W/wsr.git"
git -C "$W/wsr" worktree add -q -b 1182-lane "$W/wsr-lane"
git init -q -b main "$W/kcl" && echo k > "$W/kcl/f" && git -C "$W/kcl" add f && sandbox_git -C "$W/kcl" commit -q -m k
git -C "$W/kcl" remote add origin "https://tok:secret@github.com/PRO-Robotech/kacho.git" && git -C "$W/kcl" remote add bare "$W/wsr.git"
bref() { git -C "$W/wsr.git" rev-parse --verify --quiet "refs/heads/$1" >/dev/null && echo да || echo нет; }
wslot() { local d="$1"; shift; (cd "$d" && slot bash "$SLOT" docker -- "$@"); }
wh="$(git -C "$W/wsr" rev-parse --short=8 HEAD)"; b0="$(grep -c ' push-where ' "$HEAVY_SLOT_DIR/journal.log")"
rc="$(wslot "$W/wsr" git push -q origin HEAD:refs/heads/3251-x)"
assert "64 да да да нет" "$rc $(has "$W/err" 'первичной копии воркспейса') $(has "$W/err" "git push: каталог $W/wsr ") $(has "$W/err" "голова $wh") $(bref 3251-x)" "корень воркспейса, ветка назначения иная, чем текущая → 64: причина и печать каталога и головы, отправки не было"
assert "$((b0 + 1))" "$(grep -c ' push-where ' "$HEAVY_SLOT_DIR/journal.log")" "и в отказе строка push-where записана в журнал"
rc="$(wslot "$W/wsr-lane" git push -q origin HEAD:refs/heads/1182-lane)"
assert "0 да да" "$rc $(bref 1182-lane) $(has "$W/err" 'ветка 1182-lane')" "близнец: та же команда из связанной копии git worktree → печать и отправка идёт"
rc="$(wslot "$W/wsr-lane" git push -q origin HEAD:refs/heads/другая-ветка)"
assert "0 да" "$rc $(bref другая-ветка)" "близнец: из связанной копии назначение иное, чем текущая ветка → отправка идёт (копии так и работают)"
rc="$(wslot "$W/wsr" git -C "$W/wsr-lane" push -q origin HEAD:refs/heads/через-C)"
assert "0 да да" "$rc $(bref через-C) $(has "$W/err" "корень git $W/wsr-lane")" "близнец: из корня, но git -C <копия> → судится копия, не cwd"
rc="$(wslot "$W/wsr" timeout 60 git push -q origin HEAD:refs/heads/3251-w)"
assert "64 нет" "$rc $(bref 3251-w)" "обёртка перед git (timeout) не уводит от суждения"
rc="$(wslot "$W/wsr" git push -q origin main)"
assert "0 да" "$rc $(bref main)" "близнец: из корня, назначение — текущая ветка (main) → слот не судит, печать есть"
rc="$(wslot "$W/kcl" git push -q bare HEAD:refs/heads/3251-y)"
assert "0 да да нет" "$rc $(bref 3251-y) $(has "$W/err" 'git push: каталог') $(has "$W/err" 'secret')" "близнец: корень чужого репозитория (в нём слот не отслеживается) → отправка идёт; учётные данные в origin в печати не показаны"
sed 's/&& push_to_foreign_branch /\&\& false \&\& push_to_foreign_branch /' "$SLOT" > "$W/slot-mut-1182a.sh"
sed 's/^\( *\)git -C "$top" ls-files --error-unmatch scripts\/heavy-slot.sh >\/dev\/null 2>&1 || return 1/\1true/' "$SLOT" > "$W/slot-mut-1182b.sh"
sed 's/^\( *\)\[ -n "$gdir" \] \&\& \[ "$gdir" = "$cdir" \] || return 1/\1true/' "$SLOT" > "$W/slot-mut-1182c.sh"
dl() { diff "$SLOT" "$W/slot-mut-1182$1.sh" | grep -c '^<'; }
mrc() { local m="$1" d="$2" rem="$3" ref="$4"; (cd "$d" && slot bash "$W/slot-mut-1182$m.sh" docker -- git push -q "$rem" HEAD:refs/heads/"$ref"); }
assert "1 0 да" "$(dl a) $(mrc a "$W/wsr" origin мутант-a) $(bref мутант-a)" "мутант «не судит»: отправка из корня идёт — проба выше его ловит"
assert "1 64 нет" "$(dl b) $(mrc b "$W/kcl" bare мутант-b) $(bref мутант-b)" "мутант «судит любую первичную копию»: корень чужого репозитория отказан — близнец выше его ловит"
assert "1 64 нет" "$(dl c) $(mrc c "$W/wsr-lane" origin мутант-c) $(bref мутант-c)" "мутант «связанная копия — тоже корень»: копия задачи отказана — близнец выше его ловит"

# Опции после имени удалённого репозитория — не refspec; отправка по имени и удаление — не «голова корня в иную ветку».
# Первая редакция читала `--force-with-lease` как ветку назначения и отказывала законным отправкам из корня.
git -C "$W/wsr.git" config receive.advertisePushOptions true
wslot "$W/wsr-lane" git push -q origin HEAD:refs/heads/del-x >/dev/null
rc="$(wslot "$W/wsr" git push -q origin main --force-with-lease)"
assert "0 да" "$rc $(bref main)" "из корня на main: «origin main --force-with-lease» — законна (опция после refspec не ветка)"
rc="$(wslot "$W/wsr" git push -q origin HEAD:refs/heads/main -o ci.skip)"
assert "0 да" "$rc $(has "$W/err" 'HEAD→main')" "из корня на main: «HEAD:refs/heads/main -o ci.skip» — законна, в печати ветка назначения main, а не опция"
rc="$(wslot "$W/wsr" git push -q origin --delete del-x)"
assert "0 нет да" "$rc $(bref del-x) $(has "$W/err" 'удалить:del-x')" "из корня: «--delete del-x» — законно, удаление названо в печати своим текстом"
rc="$(wslot "$W/wsr" git push -q origin 1182-lane)"
assert "0 да да" "$rc $(bref 1182-lane) $(has "$W/err" 'по имени:1182-lane')" "из корня: «origin 1182-lane» — отправка ветки по имени, голову корня никуда не кладёт, в печати «по имени»"
rc="$(wslot "$W/wsr" git push -q origin HEAD:refs/heads/main)"
assert "0" "$rc" "близнец: «HEAD:refs/heads/<текущая>» из корня — законна (refs/heads/ срезается)"
rc="$(wslot "$W/wsr" git push -q origin HEAD)"
assert "0" "$rc" "близнец: «origin HEAD» из корня — в одноимённую ветку, законна"
rc="$(wslot "$W/wsr" git push -q origin HEAD:refs/heads/3251-z -o ci.skip)"
assert "64 да нет нет" "$rc $(has "$W/err" '«3251-z»') $(has "$W/err" '«-o') $(bref 3251-z)" "из корня «HEAD:refs/heads/3251-z -o ci.skip» — 64, названа ветка 3251-z (не опция), отправки не было"
rc="$(wslot "$W/wsr" git push -q origin main:refs/heads/3251-q)"
assert "64 нет" "$rc $(bref 3251-q)" "из корня имя текущей ветки в роли источника («main:3251-q») — тоже голова корня: 64"
sed 's|^\( *\)dsta="${dsta#refs/heads/}"$|\1:|' "$SLOT" > "$W/slot-mut-1182r.sh"
assert "1 0 да" "$(dl r) $(cd "$W/wsr" && slot bash "$W/slot-mut-1182r.sh" docker -- git push -q origin HEAD:refs/heads/3251-m) $(bref 3251-m)" "мутант «refs/heads/ не срезается»: «refs/heads/…» читается как не-ветка и отказ теряется (0 вместо 64) — отказ выше его ловит; близнец «HEAD:refs/heads/<текущая> → 0» держит обратную ошибку"

# >>> prelude-1176
# Двойник run.sh для проб внешнего входа (ws#1176, ws#1302) — модель ЁМКОСТИ: кластер держит
# GATE_CAP_MIB (по умолчанию — без предела на пробу), запрос прогона — GATE_REQ МиБ (1000).
# --available судит место: созданные ns ($GATE_DIR/ns) + вошедшие (--pending) + свой запрос;
# GATE_BARRIER=N — первые N опросов решают ДО того, как дождутся друг друга (гонка: оба прошли
# проверку, не видя друг друга). Прогон — как run.sh ws#1293: стадия запуска ($GATE_DIR/st/<метка>,
# держится GATE_START_HOLD), создание ns, строка «ns … создано:», вторая перепись по времени
# создания — не ложится со старшими: своё ns снято, 75. Ожидания — по событию, а не по сну.
cat > "$W/fake-run-gate.sh" <<'GATE'
#!/usr/bin/env bash
cap="${GATE_CAP_MIB:-100000000}"; req="${GATE_REQ:-1000}"
sum() { awk '{ s += $NF } END { print s + 0 }' "$@" 2>/dev/null || echo 0; }
[ "${1:-}" = --request ] && { echo "1000 $req"; exit 0; }
if [ "${1:-}" = --available ]; then
    pf=""; while [ "$#" -gt 0 ]; do [ "$1" = --pending ] && pf="$2"; shift; done
    [ -n "${GATE_BUSY:-}" ] && [ -e "$GATE_BUSY" ] && { echo "remote-heavy: кластер занят: идущих тяжёлых прогонов 4 при пределе 4" >&2; exit 75; }
    [ -n "${GATE_DOWN:-}" ] && [ -e "$GATE_DOWN" ] && { echo "remote-heavy: кластер не отвечает" >&2; exit 69; }
    used=$(( $(sum "$GATE_DIR/ns") + $( [ -n "$pf" ] && sum "$pf" || echo 0 ) ))
    rc=0; [ $(( used + req )) -le "$cap" ] || rc=75
    echo "$rc $( [ -n "$pf" ] && grep -c . "$pf" || echo 0 )" >> "$GATE_DIR/avail"
    if [ -n "${GATE_BARRIER:-}" ] && [ ! -e "$GATE_DIR/barrier.done" ]; then
        echo x >> "$GATE_DIR/barrier"
        for _ in $(seq 1 150); do [ "$(grep -c . "$GATE_DIR/barrier")" -ge "$GATE_BARRIER" ] && break; sleep 0.1; done
        touch "$GATE_DIR/barrier.done"
    fi
    [ "$rc" = 0 ] || echo "remote-heavy: места под запрос (память $req МиБ) нет: занято $used из $cap" >&2
    exit "$rc"
fi
label="${*: -1}"
mkdir -p "$GATE_DIR/st"; mkdir "$GATE_DIR/st/$label"
n="$(ls "$GATE_DIR/st" | wc -l)"; [ "$n" -le "$(cat "$GATE_DIR/maxst" 2>/dev/null || echo 0)" ] || echo "$n" > "$GATE_DIR/maxst"
if [ -n "${GATE_START_HOLD:-}" ]; then
    for _ in $(seq 1 600); do [ -e "$GATE_START_HOLD" ] && break; sleep 0.1; done
else sleep "${GATE_START_S:-0.3}"; fi
( flock 9; echo "$label $req" >> "$GATE_DIR/ns"; c="$(grep -c . "$GATE_DIR/ns")"
  [ "$c" -le "$(cat "$GATE_DIR/maxns" 2>/dev/null || echo 0)" ] || echo "$c" > "$GATE_DIR/maxns" ) 9>>"$GATE_DIR/lk"
unns() { ( flock 9; grep -v "^$label " "$GATE_DIR/ns" > "$GATE_DIR/ns.t"; mv -f "$GATE_DIR/ns.t" "$GATE_DIR/ns" ) 9>>"$GATE_DIR/lk"; }
[ -n "${GATE_NOMARK:-}" ] || echo "remote-heavy: ns t1176-$label создано: задача 1176" >&2
if [ "$(awk -v l="$label" '{ s += $2 } $1 == l { print s; exit }' "$GATE_DIR/ns")" -gt "$cap" ]; then
    rmdir "$GATE_DIR/st/$label"; unns
    echo "remote-heavy: кластер занят: прогон по времени создания со старшими идущими не ложится — снимаю своё ns (не выполнилось)" >&2; exit 75
fi
rmdir "$GATE_DIR/st/$label"
echo "$label" >> "$GATE_DIR/order"
[ -z "${GATE_TRAP:-}" ] || trap 'unns; touch "$GATE_DIR/term"; exit 143' TERM
if [ -n "${GATE_HOLD:-}" ]; then
    for _ in $(seq 1 600); do [ -e "$GATE_HOLD" ] && break; sleep 0.1; done
else sleep "${GATE_RUN_S:-0.3}" & wait $!; fi
unns
echo "$label" >> "$GATE_DIR/end"
exit 0
GATE
mkdir -p "$W/gate" "$W/enq2" "$R/sub"
# genq <каталог> <метка> [ENV=…] — поставить lint с go version <метка> из каталога; код вызова.
genq() {
    local d="$1" label="$2"; shift 2
    (cd "$d" && env -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_REMOTE_RUN="$W/fake-run-gate.sh" GATE_DIR="$W/gate" HEAVY_SLOT_ENQ_S=60 "$@" bash "${GSLOT:-$SLOT}" --enqueue "$W/enq2" lint -- go version "$label" 2> "$W/err" > "$W/out"); echo $?
}
gorder() { cat "$W/gate/order" 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }
gnew() { rm -rf "$W/gate"; mkdir -p "$W/gate"; rm -f "$HEAVY_SLOT_DIR"/ext/* 2>/dev/null; JMARK="$(wc -l < "$JL")"; }
# wait_order <ожидаемый порядок> <предел, с> — дождаться порядка стартов; 0, если дождались.
wait_order() { local _; for _ in $(seq 1 $(( $2 * 5 ))); do [ "$(gorder)" = "$1" ] && return 0; sleep 0.2; done; return 1; }
# wait_st <число> <предел, с> — дождаться стольких прогонов в стадии запуска разом; печатает достигнутое.
wait_st() { local _ n=0; for _ in $(seq 1 $(( $2 * 5 ))); do n="$(ls "$W/gate/st" 2>/dev/null | wc -l)"; [ "$n" -ge "$1" ] && break; sleep 0.2; done; echo "$n"; }
JMARK=0
# jsince <событие> — строки журнала слотов с событием после отметки JMARK.
jsince() { tail -n +$((JMARK + 1)) "$JL" | grep " $1 "; }
# <<< prelude-1176
echo "── внешний путь: свои билеты входят РАЗОМ в пределах места, гонка своих — порядком билетов (ws#1302; было по одному — ws#1176)"
# Свободный кластер: три своих --enqueue подряд — все трое в стадии запуска ОДНОВРЕМЕННО, а не по
# одному (замер 2026-10-22: ожидание входа p90 148 с при занятости кластера 14 % времени).
# entry_n <слот> — сцена N одновременных заявок; печатает «в стадии запуска разом · коды · ожидание ≤ 10 с».
entry_n() {
    gnew; rm -f "$W/sh"; GSLOT="${1:-}"
    genq "$R" A GATE_START_HOLD="$W/sh" >/dev/null; RA="$(rcof)"; genq "$R" B GATE_START_HOLD="$W/sh" >/dev/null; RBB="$(rcof)"; genq "$R" C GATE_START_HOLD="$W/sh" >/dev/null; RCC="$(rcof)"
    local st; st="$(wait_st 3 "${2:-20}")"
    touch "$W/sh"
    local ca cb cc; ca="$(await_rc "$RA")"; cb="$(await_rc "$RBB")"; cc="$(await_rc "$RCC")"
    local wmax; wmax="$(jsince ext-go | sed -n 's/.* waited=\([0-9]*\)s.*/\1/p' | sort -n | tail -n 1)"
    echo "$st $ca/$cb/$cc $( [ -n "$wmax" ] && [ "$wmax" -le 10 ] && echo "≤10" || echo "нет(${wmax:-—})")"; GSLOT=""
}
assert "3 0/0/0 ≤10" "$(entry_n)" "три --enqueue на свободный кластер: все трое в стадии запуска разом, коды 0, ожидание входа (ext-go waited) ≤ 10 с у каждого"
# Нехватка места — ожидание: кластер на один прогон, первый исполняется — второй не стартует, пока
# тот не кончит; затем входит сам (код 0). Срок заявки короче — 75 с причиной.
gnew; rm -f "$W/hold6"
genq "$R" A GATE_CAP_MIB=1000 GATE_HOLD="$W/hold6" >/dev/null; RA="$(rcof)"; wait_order "A" 40
genq "$R" B GATE_CAP_MIB=1000 >/dev/null; RBB="$(rcof)"; sleep 3; got="$(gorder)"
touch "$W/hold6"; ca="$(await_rc "$RA")"; cb="$(await_rc "$RBB")"
assert "A 0/0 A B" "$got $ca/$cb $(gorder)" "близнец: места на один — второй ждёт, пока первый исполняется (старт лишь A), затем входит сам: коды 0, порядок A B"
gnew; rm -f "$W/hold7"
genq "$R" A GATE_CAP_MIB=1000 GATE_HOLD="$W/hold7" >/dev/null; RA="$(rcof)"; wait_order "A" 40
genq "$R" B GATE_CAP_MIB=1000 HEAVY_SLOT_ENQ_S=3 >/dev/null; RBB="$(rcof)"; cb="$(await_rc "$RBB")"
assert "75 A да" "$cb $(gorder) $(has "${RBB%.rc}.log" 'места под запрос')" "...срок заявки истёк при нехватке места — 75, причина кластера названа, команда не запускалась"
touch "$W/hold7"; await_rc "$RA" >/dev/null
# Гонка: два билета опрашивают кластер РАЗОМ (GATE_BARRIER — решают, не дождавшись друг друга),
# места — на один. Младший учёл старшего (его запрос — во --pending) и ждёт, старший входит:
# коды 0/0, ns разом не больше одного — второй переписи run.sh уступать некому.
race2() {
    gnew; GSLOT="${1:-}"
    genq "$R" A GATE_CAP_MIB=1000 GATE_BARRIER=2 >/dev/null; RA="$(rcof)"; genq "$R" B GATE_CAP_MIB=1000 GATE_BARRIER=2 >/dev/null; RBB="$(rcof)"
    local ca cb; ca="$(await_rc "$RA")"; cb="$(await_rc "$RBB")"
    echo "$ca/$cb $(cat "$W/gate/maxns" 2>/dev/null || echo 0) $(gorder)"; GSLOT=""
}
assert "0/0 1 A B" "$(race2)" "гонка двух на место одного: опрос разом — младший учёл старшего и ждёт; коды 0/0, ns разом не больше одного, порядок A B"
# Старший ждущий не обгоняется: места 2000, A исполняется (1000), B ждёт весь кластер (2000), C (1000)
# пришёл позже — вместе с B ему места нет, и он ждёт B, хотя с одним A лёг бы.
fair3() {
    gnew; rm -f "$W/hold8"; GSLOT="${1:-}"
    genq "$R" A GATE_CAP_MIB=2000 GATE_HOLD="$W/hold8" >/dev/null; RA="$(rcof)"; wait_order "A" 40
    genq "$R" B GATE_CAP_MIB=2000 GATE_REQ=2000 >/dev/null; RBB="$(rcof)"
    for _ in $(seq 1 50); do [ "$(ls "$HEAVY_SLOT_DIR"/ext/ 2>/dev/null | wc -l)" -ge 1 ] && break; sleep 0.2; done
    sleep 1; genq "$R" C GATE_CAP_MIB=2000 >/dev/null; RCC="$(rcof)"; sleep 3
    local got; got="$(gorder)"; touch "$W/hold8"
    echo "$got / $(await_rc "$RA")/$(await_rc "$RBB")/$(await_rc "$RCC") $(gorder)"; GSLOT=""
}
assert "A / 0/0/0 A B C" "$(fair3)" "старший ждущий (B, весь кластер) не обгоняется младшим (C), которому с ним места нет: пока A исполняется, стартов лишь A; порядок A B C"
# Мутанты: «вход по одному» (вошедший занимает весь кластер), «старший не учтён» (младший судит
# лишь вошедших), «учёта вошедших нет» (EXT_GATE=0).
sed 's/^\( *\)printf '"'"'hs-%s %s\\n'"'"' "\$n" "\$req"$/\1printf '"'"'hs-%s 1000 99999999\\n'"'"' "$n"/' "$SLOT" > "$W/slot-mut-1302a.sh"
sed 's/^\( *\)\[ -n "\$(field "\$f" go)" \] || { \[ -n "\$me" \] \&\& \[ "\$n" -lt "\$me" \]; } || continue$/\1[ -n "$(field "$f" go)" ] || continue/' "$SLOT" > "$W/slot-mut-1302f.sh"
sed 's/^EXT_GATE=1$/EXT_GATE=0/' "$SLOT" > "$W/slot-mut-1176a.sh"
assert "1 1" "$(diff "$SLOT" "$W/slot-mut-1302a.sh" | grep -c '^<') $(entry_n "$W/slot-mut-1302a.sh" 6 | cut -d' ' -f1)" "мутант «вход по одному»: сцена трёх одновременных — в стадии запуска лишь один (проба выше его ловит)"
assert "1 да" "$(diff "$SLOT" "$W/slot-mut-1302f.sh" | grep -c '^<') $(r="$(race2 "$W/slot-mut-1302f.sh")"; case "$r" in "0/0 1 A B") echo "нет($r)" ;; *) echo да ;; esac)" "мутант «старший не учтён»: сцена гонки — оба вошли, младший по ns снят второй переписью run.sh (75) либо ns разом два (проба выше его ловит)"
assert "1 да" "$(diff "$SLOT" "$W/slot-mut-1302f.sh" | grep -c '^<') $(r="$(fair3 "$W/slot-mut-1302f.sh")"; case "$r" in "A / 0/0/0 A B C") echo "нет($r)" ;; *) echo да ;; esac)" "...тот же мутант: C стартует при A, пока B ждёт (проба старшинства выше его ловит)"
assert "1 да" "$(diff "$SLOT" "$W/slot-mut-1176a.sh" | grep -c '^<') $(r="$(race2 "$W/slot-mut-1176a.sh")"; case "$r" in "0/0 1 A B") echo "нет($r)" ;; *) echo да ;; esac)" "мутант «учёта вошедших нет» (EXT_GATE=0): сцена гонки — 75 второй переписи run.sh либо ns разом два (проба выше его ловит)"
# Связка с настоящим run.sh: --request отвечает запросом «mCPU МиБ» без кластера (тем же sizing).
assert "да" "$(o="$(bash "$HERE/remote-heavy/run.sh" --request --profile lint --repo kaname 2>/dev/null)"; grep -qE '^[1-9][0-9]* [1-9][0-9]*$' <<<"$o" && echo да || echo нет)" "связка с run.sh: --request --profile lint --repo kaname — «mCPU МиБ» (heavy-slot берёт запрос билета у него)"
# Внешний вход очередь памяти не держит: локальная команда входит, пока внешний билет в стадии запуска.
gnew; rm -f "$W/shold" "$W/gl1"
r1="$(genq "$R" A GATE_START_HOLD="$W/shold")"; RA="$(rcof)"
for _ in $(seq 1 150); do [ -d "$W/gate/st/A" ] && break; sleep 0.2; done
# shellcheck disable=SC2016  # строка дочерней оболочки
rl="$(slot -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_BUDGET_MIB=64 bash "$SLOT" docker -- sh -c 'test -d "$0" && touch "$1"' "$W/gate/st/A" "$W/gl1")"
assert "0 да" "$rl $([ -e "$W/gl1" ] && echo да || echo нет)" "близнец: локальный слот памяти исполнился, пока внешний билет в стадии запуска, — внешний вход очередь памяти не держит"
touch "$W/shold"; await_rc "$RA" >/dev/null
# Повтор --enqueue при ещё ждущем своём билете не плодит второго и называет первый.
gnew; touch "$W/gate-busy"
r1="$(genq "$R" A GATE_BUSY="$W/gate-busy")"; RA="$(rcof)"
for _ in $(seq 1 150); do ls "$HEAVY_SLOT_DIR"/ext/* >/dev/null 2>&1 && break; sleep 0.2; done
r2="$(genq "$R" A GATE_BUSY="$W/gate-busy")"; RA2="$(rcof)"
assert "0 0 да да" "$r1 $r2 $([ -n "$RA" ] && [ "$RA" = "$RA2" ] && echo да || echo "нет($RA2)") $(has "$W/err" 'уже стоит')" "повторный --enqueue той же команды при ждущем своём билете: код 0, назван ПЕРВЫЙ (тот же .rc), «уже стоит» сказано"
assert "1" "$(ls "$HEAVY_SLOT_DIR"/ext/* 2>/dev/null | wc -l)" "...и второго билета нет"
r3="$(genq "$R" B GATE_BUSY="$W/gate-busy")"; RBB="$(rcof)"
assert "0 да" "$r3 $([ -n "$RBB" ] && [ "$RBB" != "$RA" ] && echo да || echo нет)" "близнец: другая команда — свой билет"
rm -f "$W/gate-busy"; await_rc "$RA" >/dev/null; await_rc "$RBB" >/dev/null
gnew; rm -f "$W/hold5"
r1="$(genq "$R" A GATE_HOLD="$W/hold5")"; RA="$(rcof)"; wait_order "A" 40
r2="$(genq "$R" A GATE_HOLD="$W/hold5")"; RA2="$(rcof)"
assert "0 0 да" "$r1 $r2 $([ -n "$RA2" ] && [ "$RA" != "$RA2" ] && echo да || echo нет)" "близнец: первый уже ИСПОЛНЯЕТСЯ (не ждёт) — та же команда ставится вновь, это не повтор"
touch "$W/hold5"; await_rc "$RA" >/dev/null; await_rc "$RA2" >/dev/null
# Учёт вошедшего снимает строка «ns … создано» (ns уже в переписи), а не выход run.sh: места на два,
# A исполняется — B входит при нём (иначе A считался бы дважды: вошедшим и своим ns).
assert "1" "$(grep -c 'say "ns $NSNAME создано:' "$HERE/remote-heavy/run.sh")" "связка с run.sh: строка «ns … создано:», по которой снимается учёт вошедшего, в run.sh на месте и одна"
sed 's/\*"ns "\*" создано:"\*) \[ -z "$EXT_T" \]/*"ns "*" НЕТ-ТАКОЙ:"*) [ -z "$EXT_T" ]/' "$SLOT" > "$W/slot-mut-1176c.sh"
mark2() {
    gnew; rm -f "$W/hold1"; GSLOT="${1:-}"
    genq "$R" A GATE_CAP_MIB=2000 GATE_HOLD="$W/hold1" >/dev/null; RA="$(rcof)"; wait_order "A" 40
    genq "$R" B GATE_CAP_MIB=2000 GATE_HOLD="$W/hold1" >/dev/null; RBB="$(rcof)"
    wait_order "A B" 8; echo "$(gorder) $(cat "$W/gate/end" 2>/dev/null | wc -l)"
    touch "$W/hold1"; await_rc "$RA" >/dev/null; await_rc "$RBB" >/dev/null; GSLOT=""
}
assert "A B 0" "$(mark2)" "учёт снят строкой «ns … создано»: места на два — второй стартовал (A B), пока первый ещё исполняется (завершений 0)"
assert "1 A 0" "$(diff "$SLOT" "$W/slot-mut-1176c.sh" | grep -c '^<') $(mark2 "$W/slot-mut-1176c.sh")" "мутант «фильтр не снимает учёт»: A считается дважды — второй ждёт (стартов лишь A; проба выше его ловит)"
# Страховка: run.sh без строки «ns … создано» учёт держит не дольше EXT_HOLD_S (ручка проб).
gnew; rm -f "$W/hold3"
r1="$(genq "$R" A GATE_CAP_MIB=2000 GATE_HOLD="$W/hold3" GATE_NOMARK=1 HEAVY_SLOT_EXT_HOLD_S=2)"; RA="$(rcof)"; wait_order "A" 40
r2="$(genq "$R" B GATE_CAP_MIB=2000 GATE_HOLD="$W/hold3" GATE_NOMARK=1 HEAVY_SLOT_EXT_HOLD_S=2)"; RBB="$(rcof)"
wait_order "A B" 40; got="$(gorder)"; ended="$(cat "$W/gate/end" 2>/dev/null | wc -l)"
assert "A B 0 да" "$got $ended $(grep -c 'ext-reap .*стадия запуска дольше 2s' "$JL" | sed 's/^[1-9][0-9]*$/да/;s/^0$/нет/')" "без строки «ns … создано» учёт снят по сроку EXT_HOLD_S: второй стартовал (A B), пока первый исполняется, причина в журнале"
touch "$W/hold3"; await_rc "$RA" >/dev/null; await_rc "$RBB" >/dev/null
gnew; rm -f "$W/hold4"
r1="$(genq "$R" A GATE_CAP_MIB=2000 GATE_HOLD="$W/hold4" GATE_NOMARK=1)"; RA="$(rcof)"; wait_order "A" 40
r2="$(genq "$R" B GATE_CAP_MIB=2000 GATE_HOLD="$W/hold4" GATE_NOMARK=1)"; RBB="$(rcof)"
sleep 3
assert "A" "$(gorder)" "близнец: срок по умолчанию (120 с) — второй ждёт выхода первого, раньше не стартует"
touch "$W/hold4"; await_rc "$RA" >/dev/null; await_rc "$RBB" >/dev/null
# Сигнал слоту доходит до run.sh: ребёнок, а не exec — TERM пересылается, ns снимает сам run.sh.
gnew; rm -f "$W/never"
r1="$(genq "$R" A GATE_HOLD="$W/never" GATE_TRAP=1)"; RA="$(rcof)"; wait_order "A" 40
wp="$(cat "${RA%.rc}.pid" 2>/dev/null)"; sp="$(pgrep -P "${wp:-0}" -f heavy-slot 2>/dev/null | head -n 1)"
[ -z "$sp" ] || kill -TERM "$sp"
ca="$(await_rc "$RA")"
for _ in $(seq 1 25); do [ -e "$W/gate/term" ] && break; sleep 0.2; done
assert "143 да да" "$ca $([ -e "$W/gate/term" ] && echo да || echo нет) $([ -n "$sp" ] && echo да || echo нет)" "TERM слоту во внешнем запуске: run.sh получил сигнал (снимает своё ns), слот вышел 143"
assert "0" "$(ls "$HEAVY_SLOT_DIR"/ext-*.fifo 2>/dev/null | wc -l)" "...и канал фильтра не остался"

# Ключ повтора включает ВЛАДЕЛЬЦА: та же команда из другого каталога либо другой ветки — свой билет и свой .rc.
gnew; touch "$W/gate-busy"
r1="$(genq "$R" A GATE_BUSY="$W/gate-busy")"; RA="$(rcof)"
for _ in $(seq 1 150); do ls "$HEAVY_SLOT_DIR"/ext/* >/dev/null 2>&1 && break; sleep 0.2; done
r2="$(genq "$R/sub" A GATE_BUSY="$W/gate-busy")"; RA2="$(rcof)"; e2="$(has "$W/err" 'уже стоит')"
git -C "$R" switch -q -c 985-k
r3="$(genq "$R" A GATE_BUSY="$W/gate-busy")"; RA3="$(rcof)"; e3="$(has "$W/err" 'уже стоит')"
git -C "$R" switch -q 984-x
assert "0 0 0 да нет нет" "$r1 $r2 $r3 $([ -n "$RA" ] && [ "$RA" != "$RA2" ] && [ "$RA" != "$RA3" ] && [ "$RA2" != "$RA3" ] && echo да || echo нет) $e2 $e3" "та же команда --enqueue из другого каталога и из другой ветки — свой билет и свой .rc, а не «уже стоит» с чужим"
for _ in $(seq 1 150); do [ "$(ls "$HEAVY_SLOT_DIR"/ext/* 2>/dev/null | wc -l)" -ge 3 ] && break; sleep 0.2; done
assert "3" "$(ls "$HEAVY_SLOT_DIR"/ext/* 2>/dev/null | wc -l)" "...три билета внешнего входа"
rm -f "$W/gate-busy"; await_rc "$RA" >/dev/null; await_rc "$RA2" >/dev/null; await_rc "$RA3" >/dev/null
sed 's|"\$(git -C "\$PWD" branch --show-current 2>/dev/null)@\$PWD" "\$LOCAL_WHY"|"$LOCAL_WHY"|' "$SLOT" > "$W/slot-mut-1176k.sh"
sed 's|"\$(git -C "\$PWD" branch --show-current 2>/dev/null)@\$PWD" "\$LOCAL_WHY"|"@$PWD" "$LOCAL_WHY"|' "$SLOT" > "$W/slot-mut-1176k2.sh"
gnew; touch "$W/gate-busy"; GSLOT="$W/slot-mut-1176k.sh"
r1="$(genq "$R" A GATE_BUSY="$W/gate-busy")"; RA="$(rcof)"
for _ in $(seq 1 150); do ls "$HEAVY_SLOT_DIR"/ext/* >/dev/null 2>&1 && break; sleep 0.2; done
r2="$(genq "$R/sub" A GATE_BUSY="$W/gate-busy")"; RA2="$(rcof)"
assert "1 да" "$(diff "$SLOT" "$W/slot-mut-1176k.sh" | grep -c '^<') $([ "$RA" = "$RA2" ] && echo да || echo нет)" "мутант «ключ повтора без владельца»: из другого каталога возвращён чужой .rc — проба выше его ловит"
rm -f "$W/gate-busy"; await_rc "$RA" >/dev/null; GSLOT=""
gnew; touch "$W/gate-busy"; GSLOT="$W/slot-mut-1176k2.sh"
r1="$(genq "$R" A GATE_BUSY="$W/gate-busy")"; RA="$(rcof)"
for _ in $(seq 1 150); do ls "$HEAVY_SLOT_DIR"/ext/* >/dev/null 2>&1 && break; sleep 0.2; done
git -C "$R" switch -q -c 985-k
r3="$(genq "$R" A GATE_BUSY="$W/gate-busy")"; RA3="$(rcof)"
git -C "$R" switch -q 984-x
assert "1 да" "$(diff "$SLOT" "$W/slot-mut-1176k2.sh" | grep -c '^<') $([ "$RA" = "$RA3" ] && echo да || echo нет)" "мутант «ключ без ветки»: из другой ветки возвращён чужой .rc — проба выше его ловит"
rm -f "$W/gate-busy"; await_rc "$RA" >/dev/null; GSLOT=""
# Билет умершего владельца снимается: старший ждущий убит SIGKILL — младший, которому места с ним нет
# (GATE_CAP_MIB на один), проходит быстро, а не 75 по сроку.
reapcase() {
    gnew; touch "$W/gate-busy"; GSLOT=""
    genq "$R" A GATE_BUSY="$W/gate-busy" >/dev/null; RA="$(rcof)"
    for _ in $(seq 1 150); do ls "$HEAVY_SLOT_DIR"/ext/* >/dev/null 2>&1 && break; sleep 0.2; done
    ap="$(sed -n 's/^pid=//p' "$HEAVY_SLOT_DIR"/ext/* | head -n 1)"
    kill -KILL "$ap" 2>/dev/null
    rm -f "$W/gate-busy"; GSLOT="${1:-}"
    genq "$R" B GATE_CAP_MIB=1000 HEAVY_SLOT_ENQ_S=12 >/dev/null; RBB="$(rcof)"
    echo "$(await_rc "$RBB") $(gorder)"; GSLOT=""
}
sed 's|why=владелец умер"; rm -f "\$f"; continue|why=владелец умер"; continue|' "$SLOT" > "$W/slot-mut-1176r.sh"
assert "0 B" "$(reapcase)" "старший ждущий убит SIGKILL: младший билет проходит (код 0, запуск B), а не ждёт срока"
assert "1 75" "$(diff "$SLOT" "$W/slot-mut-1176r.sh" | grep -c '^<') $(reapcase "$W/slot-mut-1176r.sh" | cut -d' ' -f1)" "мутант «билеты умерших не снимаются»: следующий получает 75 по истечении ожидания — проба выше его ловит"

echo "── --cancel <билет>: снимает СВОЮ заявку и её отсоединённое ожидание; чужую не снимает (ws#1156)"
# Билет очереди знал только --enqueue и --resume: поставленную заявку снять было нечем.
# Здесь заявки — настоящие: держатель слота, ждущий поставленный билет, отложенный 74, внешний вход.
export HEAVY_SLOT_LIMIT_MIB=1300
cdslot() { local d="$1"; shift; (cd "$d" && slot "$@"); }
tk_of() { local b="${1%.rc}" f; f="$(grep -l "^enq=$b\$" "$HEAVY_SLOT_DIR"/queue/* "$HEAVY_SLOT_DIR"/ext/* 2>/dev/null | head -n 1)"; [ -n "$f" ] && echo $((10#${f##*/})) || echo нет; }
mkdir -p "$W/own" "$W/alien"
HEAVY_SLOT_BUDGET_MIB=250 bash "$SLOT" docker -- sleep 9 2>/dev/null & HA=$!
for _ in $(seq 1 25); do [ "$(nslots)" -ge 1 ] && break; sleep 0.2; done
rm -f "$W/cn1" "$W/cn2"
cdslot "$W/own" -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_ENQ_S=60 HEAVY_SLOT_BUDGET_MIB=200 bash "$SLOT" --enqueue "$W/enq" docker -- touch "$W/cn1" >/dev/null; RB1="$(rcof)"
for _ in $(seq 1 25); do [ "$(tk_of "$RB1")" != нет ] && break; sleep 0.2; done
T1="$(tk_of "$RB1")"
cdslot "$W/own" -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_ENQ_S=60 HEAVY_SLOT_BUDGET_MIB=200 bash "$SLOT" --enqueue "$W/enq" docker -- touch "$W/cn2" >/dev/null; RB2="$(rcof)"
for _ in $(seq 1 25); do [ "$(tk_of "$RB2")" != нет ] && break; sleep 0.2; done
T2="$(tk_of "$RB2")"
assert "да да" "$([ "$T1" != нет ] && echo да || echo нет) $([ "$T2" != нет ] && echo да || echo нет)" "два поставленных билета ждут в очереди, у каждого есть номер"
rc="$(cdslot "$W/alien" env bash "$SLOT" --cancel "$T1")"
assert "64 да да" "$rc $(has "$W/err" 'чужой') $([ "$(tk_of "$RB1")" = "$T1" ] && echo да || echo нет)" "чужой билет (вызов из другого каталога) — отказ 64 с названным владельцем, билет остался"
rc="$(cdslot "$W/own" env bash "$SLOT" --cancel 987654)"
assert "69 да" "$rc $(has "$W/err" 'в очереди нет')" "неизвестный билет — 69 «не выполнилось», а не успех"
rc="$(cdslot "$W/own" env bash "$SLOT" --cancel x)"
assert "64" "$rc" "--cancel не числом — 64"
nc="$(grep -c ' cancel ticket=' "$JL")"
rc="$(cdslot "$W/own" env bash "$SLOT" --cancel "$T1")"; c1="$(await_rc "$RB1")"
assert "0 да 143 нет $((nc + 1))" "$rc $(has "$W/err" 'снято') $c1 $([ -e "$W/cn1" ] && echo да || echo нет) $(grep -c ' cancel ticket=' "$JL")" "свой билет: 0, «снято» сказано, ожидание снято (.rc 143), команда не запускалась, строка cancel в журнале"
assert "нет да" "$(tk_of "$RB1") $([ "$(tk_of "$RB2")" = "$T2" ] && echo да || echo нет)" "билет снят, соседний остался на месте"
cdslot "$W/own" env bash "$SLOT" --cancel "$T2" >/dev/null; await_rc "$RB2" >/dev/null
wait "$HA"
# Отложенный 74 билет.
HEAVY_SLOT_BUDGET_MIB=250 bash "$SLOT" docker -- sleep 4 2>/dev/null & HA=$!
for _ in $(seq 1 25); do [ "$(nslots)" -ge 1 ] && break; sleep 0.2; done
rc="$(cdslot "$W/own" -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_BUDGET_MIB=200 bash "$SLOT" docker -- true)"; TD="$(tkof)"
TF="$HEAVY_SLOT_DIR/queue/$(printf '%012d' "${TD:-0}")"
rc2="$(cdslot "$W/own" env bash "$SLOT" --cancel "${TD:-0}")"
assert "74 да 0 нет" "$rc $([ -n "$TD" ] && echo да || echo нет) $rc2 $([ -e "$TF" ] && echo да || echo нет)" "отложенный 74 билет снимается: 0, записи в очереди нет"
wait "$HA"
# Внешний вход: ждущий билет кластера.
rm -rf "$W/gate"; mkdir -p "$W/gate"; touch "$W/gate-busy"
r1="$(genq "$R" A GATE_BUSY="$W/gate-busy")"; RA="$(rcof)"
for _ in $(seq 1 150); do [ "$(tk_of "$RA")" != нет ] && break; sleep 0.2; done
TE="$(tk_of "$RA")"
rc="$(cd "$R" && slot bash "$SLOT" --cancel "$TE")"; ce="$(await_rc "$RA")"
assert "0 143 0" "$rc $ce $(ls "$HEAVY_SLOT_DIR"/ext/* 2>/dev/null | wc -l)" "ждущий билет внешнего входа: снят (0), ожидание снято (.rc 143), в ext пусто"
rm -f "$W/gate-busy"
# Мутант «владелец не сверяется».
sed 's/^\( *\)if \[ "$who" != "$me" \]; then/\1if false; then/' "$SLOT" > "$W/slot-mut-1156.sh"
HEAVY_SLOT_BUDGET_MIB=250 bash "$SLOT" docker -- sleep 5 2>/dev/null & HA=$!
for _ in $(seq 1 25); do [ "$(nslots)" -ge 1 ] && break; sleep 0.2; done
cdslot "$W/own" -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_ENQ_S=60 HEAVY_SLOT_BUDGET_MIB=200 bash "$SLOT" --enqueue "$W/enq" docker -- touch "$W/cn3" >/dev/null; RB3="$(rcof)"
for _ in $(seq 1 25); do [ "$(tk_of "$RB3")" != нет ] && break; sleep 0.2; done
T3="$(tk_of "$RB3")"
rc="$(cdslot "$W/alien" env bash "$W/slot-mut-1156.sh" --cancel "$T3")"; await_rc "$RB3" >/dev/null
assert "1 0" "$(diff "$SLOT" "$W/slot-mut-1156.sh" | grep -c '^<') $rc" "мутант «владелец не сверяется»: чужой билет снят — проба выше его ловит"
wait "$HA"

echo "── --cancel <журнал заявки>: снимается тем, что вызов держит в руках — строкой ENQUEUED (ws#1244 L1)"
# ENQUEUED называет журнал, .rc и pid, а номер билета выдаёт ребёнок позже: 2026-10-18 заявку ревьюера
# 123 мин снять было нечем, кроме переписи --status и ручного kill.
HEAVY_SLOT_BUDGET_MIB=250 bash "$SLOT" docker -- sleep 9 2>/dev/null & HA=$!
for _ in $(seq 1 25); do [ "$(nslots)" -ge 1 ] && break; sleep 0.2; done
rm -f "$W/cn4"
cdslot "$W/own" -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_ENQ_S=60 HEAVY_SLOT_BUDGET_MIB=200 bash "$SLOT" --enqueue "$W/enq" docker -- touch "$W/cn4" >/dev/null; RB4="$(rcof)"
hint="$(has "$W/err" "--cancel ${RB4%.rc}.pid")"
for _ in $(seq 1 25); do [ "$(tk_of "$RB4")" != нет ] && break; sleep 0.2; done
rc="$(cdslot "$W/alien" env bash "$SLOT" --cancel "${RB4%.rc}.pid")"
assert "64 да" "$rc $([ "$(tk_of "$RB4")" != нет ] && echo да || echo нет)" "близнец владельца: чужой вызов журналом заявки — 64, билет остался"
rc="$(cdslot "$W/own" env bash "$SLOT" --cancel "${RB4%.rc}.pid")"; c4="$(await_rc "$RB4")"
assert "да 0 143 нет нет" "$hint $rc $c4 $([ -e "$W/cn4" ] && echo да || echo нет) $(tk_of "$RB4")" "ENQUEUED называет отмену; свой журнал заявки (.pid): 0, ожидание снято (.rc 143), команда не запускалась, билета нет"
rc="$(cdslot "$W/own" env bash "$SLOT" --cancel "$W/enq/hs-docker-20990101T000000-1.log")"
assert "69 да да" "$rc $(has "$W/err" 'билета нет') $(has "$W/err" 'не выдавалась')" "журнал заявки без билета, без процесса и без .rc — 69 «не выдавалась», а не успех"
wait "$HA"
# Заявка ИДЁТ без билета (ws#1250 K5): вошла в слот — билета у неё нет, а процесс жив. Прежде отмена
# отвечала «снята, исполнилась либо не выдавалась» и о живой команде молчала.
rm -f "$W/cn5"
# shellcheck disable=SC2016  # тело `bash -c` раскрывает дочерняя оболочка
cdslot "$W/own" -u HEAVY_SLOT_WAIT_S HEAVY_SLOT_ENQ_S=60 HEAVY_SLOT_BUDGET_MIB=200 bash "$SLOT" --enqueue "$W/enq" docker -- bash -c 'sleep 4; touch "$0"' "$W/cn5" >/dev/null; RB5="$(rcof)"
for _ in $(seq 1 25); do [ "$(nslots)" -ge 1 ] && [ "$(tk_of "$RB5")" = нет ] && break; sleep 0.2; done
P5="$(cat "${RB5%.rc}.pid" 2>/dev/null)"
rc="$(cdslot "$W/own" env bash "$SLOT" --cancel "${RB5%.rc}.pid")"
assert "69 да да да" "$rc $(has "$W/err" 'ИДЁТ') $(has "$W/err" "pid ${P5:-нет}") $(kill -0 "${P5:-0}" 2>/dev/null && echo да || echo нет)" "идущая заявка без билета: 69, «ИДЁТ» и её pid названы, процесс не тронут"
c5="$(await_rc "$RB5")"
rc="$(cdslot "$W/own" env bash "$SLOT" --cancel "${RB5%.rc}.log")"
assert "0 да 69 да" "$c5 $([ -e "$W/cn5" ] && echo да || echo нет) $rc $(has "$W/err" 'завершилась кодом 0')" "близнец: та же заявка исполнилась — 69 с её кодом из .rc, а не «идёт»"

echo "── срок заявки ОДИН на все фазы: внешний вход, занятость кластера и очередь памяти (ws#1244 L1)"
# Очередь памяти считала срок от СВОЕГО начала: заявка, прождавшая занятый кластер, на его отказе
# уходила локально и ждала ещё столько же — до 2 × 120 мин. Здесь срок 7 с: кластер занят 4 с, затем
# не отвечает, слоты полны. Общий срок — 75 к ~7 с; сброшенный — к ~11 с.
HEAVY_SLOT_BUDGET_MIB=250 bash "$SLOT" docker -- sleep 15 2>/dev/null & HA=$!
for _ in $(seq 1 25); do [ "$(nslots)" -ge 1 ] && break; sleep 0.2; done
gnew; touch "$W/gate-busy"; rm -f "$W/gate-down"; t0="$(date +%s)"
genq "$R" D GATE_BUSY="$W/gate-busy" GATE_DOWN="$W/gate-down" HEAVY_SLOT_ENQ_S=7 >/dev/null; RD="$(rcof)"
sleep 4; touch "$W/gate-down"; rm -f "$W/gate-busy"
cdd="$(await_rc "$RD")"; el=$(( $(date +%s) - t0 ))
assert "75 да да" "$cdd $([ "$el" -le 10 ] && echo да || echo "нет(${el} с)") $(has "${RD%.rc}.log" 'кластер недоступен')" "занятость кластера, затем отказ и очередь памяти — 75 в пределах ОДНОГО срока заявки (7 с), а не срок на фазу"
wait "$HA"; rm -f "$W/gate-down"
export HEAVY_SLOT_LIMIT_MIB=100000

echo "── ci-local, git push из копии воркспейса: клоны для наборов хука выставляются сами (KACHO_HOME_<ИМЯ>)"
# Отправка из копии, где переменных клонов нет, проходила, но change-graph-gate («клон corelib не
# найден») и docs-gate («копия kaname рядом не найдена») уходили в [VOID]: имена переменных
# нигде не названы. Копия лежит в <корень>/tmp/…, а project/<имя> — только у основного клона.
mkdir -p "$W/wsr/project/kacho" "$W/wsr/project/kaname" "$W/wsr/project/corelib"
for _n in kacho kaname corelib; do git init -q "$W/wsr/project/$_n"; done
printf '#!/usr/bin/env bash\ncat >/dev/null\nenv | grep "^KACHO_HOME_" | sort > "$HOOK_ENV"\nexit 0\n' > "$W/wsr/.git/hooks/pre-push"; chmod +x "$W/wsr/.git/hooks/pre-push"
hslot() { local d="$1" cls="$2" ref="$3"; shift 3; rm -f "$W/henv"; (cd "$d" && slot "$@" HOOK_ENV="$W/henv" bash "$SLOT" "$cls" -- git push -q origin HEAD:refs/heads/"$ref"); }
henv() { tr '\n' ' ' < "$W/henv" 2>/dev/null | sed 's/ $//'; }
want="KACHO_HOME_CORELIB=$W/wsr/project/corelib KACHO_HOME_KACHO=$W/wsr/project/kacho KACHO_HOME_KANAME=$W/wsr/project/kaname"
rc="$(hslot "$W/wsr-lane" ci-local h1 -u KACHO_HOME_KACHO -u KACHO_HOME_KANAME -u KACHO_HOME_CORELIB)"
assert "0 $want да" "$rc $(henv) $(has "$W/err" 'KACHO_HOME_KANAME=')" "ci-local, git push из связанной копии без переменных: хук видит клоны основного клона (project/*), и слот назвал их"
rc="$(hslot "$W/wsr-lane" ci-local h2 -u KACHO_HOME_KACHO -u KACHO_HOME_CORELIB KACHO_HOME_KANAME=/свой/kaname)"
assert "0 KACHO_HOME_CORELIB=$W/wsr/project/corelib KACHO_HOME_KACHO=$W/wsr/project/kacho KACHO_HOME_KANAME=/свой/kaname" "$rc $(henv)" "близнец: заданная вызывающим переменная сильнее, остальные выставлены"
rc="$(hslot "$W/wsr-lane" docker h3 -u KACHO_HOME_KACHO -u KACHO_HOME_KANAME -u KACHO_HOME_CORELIB)"
assert "0 " "$rc $(henv)" "близнец: класс не ci-local — переменных слот не ставит"
rm -rf "$W/wsr/project/corelib"
rc="$(hslot "$W/wsr-lane" ci-local h4 -u KACHO_HOME_KACHO -u KACHO_HOME_KANAME -u KACHO_HOME_CORELIB)"
assert "0 да да" "$rc $(has "$W/err" 'KACHO_HOME_CORELIB') $(has "$W/err" 'клона нет')" "клона нет → не выставлено, и это названо по имени переменной: узнают до отправки, а не из [VOID]"
git init -q "$W/wsr/project/corelib"
printf '#!/usr/bin/env bash\ncat >/dev/null\nenv | grep "^KACHO_HOME_" | sort > "$HOOK_ENV"\nexit 0\n' > "$W/kcl/.git/hooks/pre-push"; chmod +x "$W/kcl/.git/hooks/pre-push"
rm -f "$W/henv"; (cd "$W/kcl" && slot -u KACHO_HOME_KACHO -u KACHO_HOME_KANAME -u KACHO_HOME_CORELIB HOOK_ENV="$W/henv" bash "$SLOT" ci-local -- git push -q bare HEAD:refs/heads/h5) >/dev/null
assert "" "$(henv)" "близнец: отправка из клона другого репозитория — переменных воркспейса нет"
sed 's/^\( *\)export "$var=$d"; set+=("$var=$d")/\1set+=("$var=$d")/' "$SLOT" > "$W/slot-mut-homes.sh"
rm -f "$W/henv"; (cd "$W/wsr-lane" && slot -u KACHO_HOME_KACHO -u KACHO_HOME_KANAME -u KACHO_HOME_CORELIB HOOK_ENV="$W/henv" bash "$W/slot-mut-homes.sh" ci-local -- git push -q origin HEAD:refs/heads/h6) >/dev/null
assert "1 " "$(diff "$SLOT" "$W/slot-mut-homes.sh" | grep -c '^<') $(henv)" "мутант «переменные не выставлены»: хук их не видит — проба выше его ловит"

echo "── ci-local: бронь по предмету отправки, а не единые 10 ГиБ; обгон малым ограничен (ws#1161 д)"
# Измерено по журналу слотов (строки leave класса ci-local, перемер 2026-10-18; предмет — origin
# каталога отправки): воркспейс — пик 394–790 МиБ (не считая отказов до хука), kaname —
# peak + container_peak + escaped_peak ≤ 4228 МиБ (36 строк), kacho — до 7595 МиБ (23 строки).
# Бронь = максимум пика × 1,5, вверх до 512 МиБ: воркспейс 1536, kaname 6656; kacho и всё
# неопознанное — прежние 10240. Число ставит предмет отправки (git push; -C), не имя класса.
git init -q -b main "$W/kn" && echo k > "$W/kn/f" && git -C "$W/kn" add f && sandbox_git -C "$W/kn" commit -q -m k
git -C "$W/kn" remote add origin "https://github.com/PRO-Robotech/kaname.git" && git -C "$W/kn" remote add bare "$W/wsr.git"
git init -q -b main "$W/kc" && echo k > "$W/kc/f" && git -C "$W/kc" add f && sandbox_git -C "$W/kc" commit -q -m k
git -C "$W/kc" remote add origin "https://github.com/PRO-Robotech/kacho.git"
# book <каталог> <класс> <команда…> — бронь слота, число на stdout, основание на stderr.
book() { local d="$1" c="$2"; shift 2; (cd "$d" && env "${REAL[@]}" bash "$SLOT" --book "$c" -- "$@" 2> "$W/err" || true); }
assert "1536 да" "$(book "$W/wsr-lane" ci-local git push origin HEAD:refs/heads/b1) $(has "$W/err" 'воркспейс')" "отправка воркспейса: бронь 1536 МиБ (пик 394–790 × 1,5, вверх до 512), основание названо"
assert "6656 да" "$(book "$W/kn" ci-local git push bare HEAD:refs/heads/b2) $(has "$W/err" 'kaname')" "отправка kaname: бронь 6656 МиБ (пик 4228 × 1,5, вверх до 512), основание названо"
assert "10240" "$(book "$W/kc" ci-local git push origin HEAD:refs/heads/b3)" "отправка kacho (пик до 7595): прежняя бронь 10240 МиБ — урезать нечем"
assert "6656" "$(book "$W/wsr" ci-local git -C "$W/kn" push bare HEAD:refs/heads/b4)" "из корня воркспейса отправка клона kaname через -C: предмет — клон, бронь 6656"
assert "10240" "$(book "$W/wsr-lane" ci-local go version)" "ci-local не отправка (прогон набора): предмета нет, прежняя бронь 10240"
assert "4096" "$(book "$W/wsr-lane" docker git push origin HEAD:refs/heads/b5)" "класс не ci-local — бронь класса, как была (docker 4096)"
assert "10240" "$(env "${REAL[@]}" bash "$SLOT" --budget ci-local 2>/dev/null)" "--budget ci-local — прежние 10240 (его читает session-memcap.sh)"
# Бронь РЕАЛЬНО ставится слотом (журнал enter, запись слота), а не только печатается: таблицу проб
# подменяет ручка HEAVY_SLOT_SUBJECTS (в режиме проб бюджет ≤ 512, настоящие числа не влезли бы).
SUBJ=$'workspace|96|проба\nkaname|160|проба'
bj() { local d="$1" ref="$2" rem="$3"; (cd "$d" && slot -u HEAVY_SLOT_BUDGET_MIB HEAVY_SLOT_SUBJECTS="$SUBJ" bash "$SLOT" ci-local -- git push -q "$rem" HEAD:refs/heads/"$ref") >/dev/null; grep " enter id=.*class=ci-local .*refs/heads/$ref" "$JL" | sed -n 's/.* budget=\([0-9]*\)MiB .*/\1/p' | tail -n 1; }
assert "96 160" "$(bj "$W/wsr-lane" b6 origin) $(bj "$W/kn" b7 bare)" "слот ставит бронь по предмету: воркспейс 96, kaname 160 (журнал enter) — брони разные"
bjc() { local d="$1" ref="$2" rem="$3" dir="$4"; (cd "$d" && slot -u HEAVY_SLOT_BUDGET_MIB HEAVY_SLOT_SUBJECTS="$SUBJ" bash "$SLOT" ci-local -- git -C "$dir" push -q "$rem" HEAD:refs/heads/"$ref") >/dev/null; grep " enter id=.*class=ci-local .*refs/heads/$ref" "$JL" | sed -n 's/.* budget=\([0-9]*\)MiB .*/\1/p' | tail -n 1; }
assert "160 96" "$(bjc "$W/wsr-lane" c1 bare "$W/kn") $(bjc "$W/kn" c2 origin "$W/wsr-lane")" "настоящий вход «git -C <клон> push»: бронь по клону из -C, а не по рабочему каталогу вызова (из копии воркспейса на kaname — 160, из kaname на воркспейс — 96)"
sed 's|_top="\$(git -C "\$GDIR" rev-parse --show-toplevel|_top="$(git -C "$PWD" rev-parse --show-toplevel|' "$SLOT" > "$W/slot-mut-bpc.sh"
bjm() { (cd "$W/wsr-lane" && slot -u HEAVY_SLOT_BUDGET_MIB HEAVY_SLOT_SUBJECTS="$SUBJ" bash "$W/slot-mut-bpc.sh" ci-local -- git -C "$W/kn" push -q bare HEAD:refs/heads/c3) >/dev/null; grep " enter id=.*class=ci-local .*refs/heads/c3" "$JL" | sed -n 's/.* budget=\([0-9]*\)MiB .*/\1/p' | tail -n 1; }
assert "1 96" "$(diff "$SLOT" "$W/slot-mut-bpc.sh" | grep -c '^<') $(bjm)" "мутант «бронь по рабочему каталогу, не по -C»: kaname получает бронь воркспейса — проба выше его ловит"
sed 's/^\( *\)sb_budget="${line%%|\*}"$/\1sb_budget="$(class_budget ci-local)"/' "$SLOT" > "$W/slot-mut-book.sh"
assert "1 10240" "$(diff "$SLOT" "$W/slot-mut-book.sh" | grep -c '^<') $(cd "$W/wsr-lane" && env "${REAL[@]}" bash "$W/slot-mut-book.sh" --book ci-local -- git push origin HEAD:refs/heads/b8 2>/dev/null)" "мутант «единая бронь»: воркспейс получает 10240 — проба выше его ловит"
# Обгон: большой (300) ждёт — ему места сейчас нет, а под свой потолок он влезает; малые (40)
# проходят не более BYPASS_MAX = 3 раз, четвёртый стоит за ним. Держатель — по событию (файл).
export HEAVY_SLOT_LIMIT_MIB=1300
fld() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n 1; }
bpnew() { rm -f "$W/hold-bp" "$W/bp-order"; bphold "$W/hold-bp"
          # shellcheck disable=SC2016
          HEAVY_SLOT_WAIT_S=60 HEAVY_SLOT_BUDGET_MIB=300 bash "$SLOT" docker -- sh -c 'echo G >> "$0"' "$W/bp-order" 2>/dev/null & GB=$!
          for _ in $(seq 1 50); do [ "$(qlen)" -ge 1 ] && break; sleep 0.2; done; }
bpsmall() { # shellcheck disable=SC2016
            slot HEAVY_SLOT_BUDGET_MIB=40 bash "${2:-$SLOT}" docker -- sh -c 'echo "$1" >> "$0"' "$W/bp-order" "$1"; }
bpend() { touch "$W/hold-bp"; wait "$BPH"; wait "$GB"; }
bpnew
r=""; for i in 1 2 3; do r="$r $(bpsmall "S$i")"; done
assert "0 0 0 S1 S2 S3" "$(echo $r) $(tr '\n' ' ' < "$W/bp-order" | sed 's/ $//')" "малые S1–S3 (40) проходят за ждущим большим (300), которому места нет"
gt="$(grep -l '^budget=300$' "$HEAVY_SLOT_DIR"/queue/* | head -n 1)"
assert "3" "$(fld "$gt" bypassed)" "у ждущего большого записано число обгонов — 3"
# shellcheck disable=SC2016
HEAVY_SLOT_WAIT_S=60 HEAVY_SLOT_BUDGET_MIB=40 bash "$SLOT" docker -- sh -c 'echo "$1" >> "$0"' "$W/bp-order" S4 2>"$W/errS4" & S4=$!
for _ in $(seq 1 50); do [ "$(qlen)" -ge 2 ] && break; sleep 0.2; done
bpend; wait "$S4"; r4=$?
assert "0 S1 S2 S3 G S4" "$r4 $(tr '\n' ' ' < "$W/bp-order" | sed 's/ $//')" "четвёртый малый обгонять уже не может: большой не голодает, входит РАНЬШЕ S4"
assert "да" "$(has "$W/errS4" 'в очереди впереди 1')" "...и причина ожидания S4 названа"
# Большому, которому места уже хватает, ждать нечего: он на пороге входа, его не обгоняют.
sleep 30 & SL=$!
tk="$(( $(cat "$HEAVY_SLOT_DIR/ticket") + 1 ))"; echo "$tk" > "$HEAVY_SLOT_DIR/ticket"
printf 'pid=%s\npid_start=%s\nclass=docker\nbudget=500\nlimit=100000\nmeminfo=%s\nwho=проба\n' "$SL" "$(awk '{ print $22 }' /proc/$SL/stat)" "$HEAVY_SLOT_MEMINFO" > "$HEAVY_SLOT_DIR/queue/$(printf '%012d' "$tk")"
assert "75 да" "$(slot HEAVY_SLOT_BUDGET_MIB=40 bash "$SLOT" docker -- true) $(has "$W/err" 'в очереди впереди 1')" "близнец: большой, которому места хватает (память свободна), на пороге входа — малый его не обгоняет"
sed 's/^BYPASS_MAX=3$/BYPASS_MAX=0/' "$SLOT" > "$W/slot-mut-bp0.sh"; sed 's/^BYPASS_MAX=3$/BYPASS_MAX=999/' "$SLOT" > "$W/slot-mut-bpinf.sh"
sed 's/^\( *\)fits_now "\$fb".*&& return 1$/\1true/' "$SLOT" > "$W/slot-mut-bpfit.sh"
assert "1 0" "$(diff "$SLOT" "$W/slot-mut-bpfit.sh" | grep -c '^<') $(slot HEAVY_SLOT_BUDGET_MIB=40 bash "$W/slot-mut-bpfit.sh" docker -- true)" "мутант «обгоняют и того, кому места хватает»: малый проходит за готовым к входу — проба выше его ловит"
kill "$SL" 2>/dev/null; rm -f "$HEAVY_SLOT_DIR/queue/$(printf '%012d' "$tk")"
bpnew
assert "1 75" "$(diff "$SLOT" "$W/slot-mut-bp0.sh" | grep -c '^<') $(bpsmall M0 "$W/slot-mut-bp0.sh")" "мутант «обгона нет»: малый стоит за большим — проба выше его ловит"
for i in 1 2 3; do bpsmall "S$i" >/dev/null; done
assert "1 0" "$(diff "$SLOT" "$W/slot-mut-bpinf.sh" | grep -c '^<') $(bpsmall M4 "$W/slot-mut-bpinf.sh")" "мутант «обгон без предела»: четвёртый малый тоже проходит — проба выше его ловит"
bpend
# Предел обгонов переживает 75 и --resume: число bypassed не теряется ни в defer_ticket, ни при перезаписи билета.
# Раунд 1: три обгона, G выходит 75; раунд 2: --resume <билет> — S4 всё равно не обгоняет, обгонов в журнале по-прежнему 3.
bpresume() {
    local sl="$1" tk f bpv rc4 cnt rg1
    rm -f "$W/hold-bp" "$W/bp-order"; bphold "$W/hold-bp"
    HEAVY_SLOT_BUDGET_MIB=300 env -u HEAVY_SLOT_WAIT_S bash "$sl" --wait 12 docker -- sh -c 'echo G >> "$0"' "$W/bp-order" 2> "$W/errG1" >/dev/null & G1=$!
    for _ in $(seq 1 50); do [ "$(qlen)" -ge 1 ] && break; sleep 0.2; done
    for i in 1 2 3; do bpsmall "S$i" >/dev/null; done
    wait "$G1"; rg1=$?
    tk="$(sed -n 's/.*--resume \([0-9][0-9]*\).*/\1/p' "$W/errG1" | head -n 1)"
    f="$HEAVY_SLOT_DIR/queue/$(printf '%012d' "${tk:-0}")"
    HEAVY_SLOT_BUDGET_MIB=300 env -u HEAVY_SLOT_WAIT_S bash "$sl" --resume "${tk:-0}" --wait 60 docker -- sh -c 'echo G >> "$0"' "$W/bp-order" 2>/dev/null >/dev/null & G2=$!
    for _ in $(seq 1 50); do [ -e "$f" ] && ! grep -q '^resume_until=' "$f" && break; sleep 0.2; done
    bpv="$(fld "$f" bypassed)"
    rc4="$(bpsmall S4)"
    cnt="$(grep -cF " bypass ticket=${tk:-0} " "$JL")"
    touch "$W/hold-bp"; wait "$BPH"; wait "$G2"
    echo "$rg1 ${bpv:-нет} $rc4 $cnt"
}
sed 's#^\( *\)\[ -z "\$BPK" \] || printf .bypassed=%s\\n. "\$BPK" >> "\$TICKET"$#\1:#' "$SLOT" > "$W/slot-mut-bpr.sh"
sed 's|^    BPK="\$(field "\$TICKET" bypassed)"$|    BPK=""|' "$SLOT" > "$W/slot-mut-bpd.sh"
assert "75 3 75 3" "$(bpresume "$SLOT")" "после 75 и --resume число обгонов (3) сохранено, четвёртый малый S4 не обгоняет (75), в журнале обгонов ровно 3"
assert "1 нет 0" "$(diff "$SLOT" "$W/slot-mut-bpr.sh" | grep -c '^<') $(bpresume "$W/slot-mut-bpr.sh" | cut -d' ' -f2,3)" "мутант «при перезаписи билета bypassed теряется»: S4 проходит — проба выше его ловит"
assert "1 нет 0" "$(diff "$SLOT" "$W/slot-mut-bpd.sh" | grep -c '^<') $(bpresume "$W/slot-mut-bpd.sh" | cut -d' ' -f2,3)" "мутант «defer_ticket теряет bypassed»: S4 проходит — проба выше его ловит"
export HEAVY_SLOT_LIMIT_MIB=100000

echo "── ci-local локально, правка консоли: зависимости — у ТОГО дерева, что судит хук отправки (ws#1190)"
# Хук отправки kacho отказывает «проверки консоли НЕ ВЫПОЛНЯЛИСЬ» в самом конце прогона (~6 мин
# слота), когда правка трогает ui-future/, а в судимом дереве нет node_modules. Судимое дерево —
# рабочая копия, если она чиста и стоит на отправляемой вершине, иначе ВРЕМЕННАЯ копия (git
# worktree add в subject_tree_for_push), где node_modules нет по построению. Слот судит вход git
# переходником pre-push: рабочая копия — ставит зависимости как ui.yml (шаг run.sh), временная —
# отказ 64 до проверок хука. Формы — настоящие, из ствола клона kacho: ui.yml, package.json и
# .gitignore консоли, ui-future/scripts/deps-ready.mjs (предикат самих проверок),
# scripts/hooks/prepush-range.sh и prepush-groups.sh (производители диапазона и набора групп хука). npm — двойник (журнал вызовов),
# node — настоящий. Хук — двойник: пишет, что судит и что видит в окружении.
KROOT="${HEAVY_SLOT_PROBE_KACHO:-$(dirname "$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)")/project/kacho}"
KFORMS=(.github/workflows/ui.yml ui-future/package.json ui-future/.gitignore ui-future/scripts/deps-ready.mjs scripts/hooks/prepush-range.sh scripts/hooks/prepush-groups.sh)
KOK=1
for f in "${KFORMS[@]}"; do git -C "$KROOT" cat-file -e "origin/main:$f" 2>/dev/null || KOK=""; done
if [ -z "$KOK" ] || ! command -v node >/dev/null; then
    skip "ws#1190: клона kacho с формами консоли ($KROOT, origin/main: ${KFORMS[*]}) либо node нет — часть не построена"
else
KS="$W/kcons"; KB="$W/kcons.git"
git init -q --bare -b main "$KB"; git init -q -b main "$KS"; git -C "$KS" remote add origin "$KB"
for f in "${KFORMS[@]}"; do mkdir -p "$KS/$(dirname "$f")"; git -C "$KROOT" show "origin/main:$f" > "$KS/$f"; done
# Пакеты консоли — по настоящим перечням: STANDALONE ui.yml и workspaces корневого package.json.
KSTD="$(python3 -c 'import sys,yaml; print(" ".join(yaml.safe_load(open(sys.argv[1]))["env"]["STANDALONE"].split()))' "$KS/.github/workflows/ui.yml")"
KMEM="$(python3 -c 'import sys,json; print(" ".join(json.load(open(sys.argv[1]))["workspaces"]))' "$KS/ui-future/package.json")"
for p in $KSTD $KMEM; do mkdir -p "$KS/ui-future/$p"; echo '{}' > "$KS/ui-future/$p/package.json"; done
echo base > "$KS/f.txt"; git -C "$KS" add -A; sandbox_git -C "$KS" commit -qm base; git -C "$KS" push -q origin main 2>/dev/null
git -C "$KS" fetch -q origin
git -C "$KS" checkout -q -b ui; echo 1 > "$KS/ui-future/host/a.ts"; git -C "$KS" add -A; sandbox_git -C "$KS" commit -qm ui
git -C "$KS" checkout -q -b noui main; mkdir -p "$KS/ui-futurex"; echo 1 > "$KS/ui-futurex/a.ts"; echo 1 > "$KS/x.go"; git -C "$KS" add -A; sandbox_git -C "$KS" commit -qm noui
git -C "$KS" checkout -q -b nodr ui; git -C "$KS" rm -q ui-future/scripts/deps-ready.mjs; sandbox_git -C "$KS" commit -qm nodr
git -C "$KS" checkout -q ui
KUI="$(git -C "$KS" rev-parse ui)"; KNO="$(git -C "$KS" rev-parse noui)"
# Двойник npm: журнал «каталог|аргументы»; ci ставит непустой node_modules (в --prefix либо в cwd).
KNB="$W/knpm"; mkdir -p "$KNB"
cat > "$KNB/npm" <<'NPM'
#!/usr/bin/env bash
printf '%s|%s\n' "$(basename "$PWD")" "$*" >> "$KNPM_LOG"
[ "${1:-}" = ci ] || exit 0
d="$PWD"; [ "${2:-}" = --prefix ] && d="$PWD/$3"
case "${FAKE_NPM_FAIL:-}" in root) [ "${2:-}" = --prefix ] || exit 1 ;; "") ;; *) [ "${3:-}" = "$FAKE_NPM_FAIL" ] && exit 1 ;; esac
[ "${FAKE_NPM_DIRTY:-}" = 1 ] && echo x > "$PWD/stray-from-npm.txt"
mkdir -p "$d/node_modules/.x"; touch "$d/node_modules/.x/ok"
NPM
chmod +x "$KNB/npm"
# Двойник хука: что судит (корень, есть ли node_modules в корне консоли) и окружение git.
# shellcheck disable=SC2016  # текст хука раскрывает он сам
printf '%s\n' '#!/usr/bin/env bash' 'cat > /dev/null' \
    'top="$(git rev-parse --show-toplevel)"; nm=нет; [ -n "$(ls -A "$top/ui-future/node_modules" 2>/dev/null)" ] && nm=да' \
    'printf "ran nm=%s gcp=%s hs=%s\n" "$nm" "${GIT_CONFIG_PARAMETERS:-}" "$(env | grep -c "^HS_")" > "$KHOOK"' 'exit 0' > "$KS/.git/hooks/pre-push"
chmod +x "$KS/.git/hooks/pre-push"
KPATH="$KNB:$PATH"
# kreset <ветка> <зависимости: все|нет|без-<пакет>> — копия на ветке, чистая, зависимости как велено.
kreset() {
    git -C "$KS" checkout -q -f "$1"; git -C "$KS" clean -qfdx
    case "$2" in
        все|без-*) mkdir -p "$KS/ui-future/node_modules/.x"; touch "$KS/ui-future/node_modules/.x/ok"
            for p in $KSTD; do [ "$2" = "без-$p" ] && continue; mkdir -p "$KS/ui-future/$p/node_modules/.x"; touch "$KS/ui-future/$p/node_modules/.x/ok"; done ;;
    esac
    rm -f "$W/knpm.log" "$W/khook"
}
# kpush [ENV=…] -- <слова git push после «push»> — ci-local слотом из копии; код слота.
kpush() {
    local e=()
    rm -f "$W/knpm.log" "$W/khook"
    while [ "$1" != -- ]; do e+=("$1"); shift; done; shift
    (cd "$KS" && slot PATH="$KPATH" KNPM_LOG="$W/knpm.log" KHOOK="$W/khook" "${e[@]+"${e[@]}"}" bash "${KSLOT:-$SLOT}" ci-local -- git push -q origin "$@")
}
knpm() { [ -s "$W/knpm.log" ] && tr '\n' ';' < "$W/knpm.log" || echo нет; }
khook() { [ -s "$W/khook" ] && cut -d' ' -f1,2 "$W/khook" || echo нет; }
KWANT="ui-future|ci;"; for p in $KSTD; do KWANT="${KWANT}ui-future|ci --prefix $p;"; done
kdec() { grep ' console-deps ' "$JL" 2>/dev/null | tail -n 1 | sed -n 's/.* decision=\([^ ]*\).*/\1/p'; }

kreset ui нет
assert "0 $KWANT ran nm=да install" "$(kpush -- HEAD:refs/heads/k1) $(knpm) $(khook) $(kdec)" "правка консоли, копия чиста и на вершине, зависимостей нет → npm ci как ui.yml ДО хука (корень и каждый STANDALONE по порядку), хук видит node_modules"
assert "да" "$(has "$W/err" 'хук судит рабочую копию')" "решение названо: хук судит рабочую копию, ставлю как ui.yml"
kreset ui все
assert "0 нет ran nm=да ready" "$(kpush -- HEAD:refs/heads/k2) $(knpm) $(khook) $(kdec)" "близнец: зависимости уже стоят у всех пакетов → повторной установки нет, хук идёт как прежде"
kreset ui без-e2e
assert "0 $KWANT ran" "$(kpush -- HEAD:refs/heads/k3) $(knpm) $(khook | cut -d' ' -f1)" "почти совпадение: не готов один STANDALONE (e2e) → ставится вся форма ui.yml"
kreset noui нет
assert "0 нет ran nm=нет untouched" "$(kpush -- HEAD:refs/heads/k4) $(knpm) $(khook) $(kdec)" "близнец: правка трогает ui-futurex/ и x.go, не ui-future/ → установки нет, хук идёт как прежде"
echo s > "$KS/stray.txt"
assert "0 ran untouched" "$(kpush -- HEAD:refs/heads/k4b) $(khook | cut -d' ' -f1) $(kdec)" "близнец: та же правка без консоли из ГРЯЗНОЙ копии → не отказ: временная копия хуку без консоли не мешает"
assert "0 ran untouched" "$(kpush KACHO_PREPUSH_GROUP='go ui-types' -- HEAD:refs/heads/k4c) $(khook | cut -d' ' -f1) $(kdec)" "близнец: группа консоли названа, но правка консоль не трогает (грязная копия) → не отказ: хук о пропуске консоли откажет лишь при ui-future/ в диапазоне"

# Временная копия: рабочая копия грязна либо не на отправляемой вершине — зависимости РАБОЧЕЙ копии хуку не помогут.
kreset ui все; echo s > "$KS/stray.txt"
assert "64 нет нет temp" "$(kpush -- HEAD:refs/heads/k5) $(knpm) $(khook) $(kdec)" "копия грязна неотслеживаемым файлом, зависимости в ней стоят → отказ 64 ДО хука, npm не звался"
assert "да да да да" "$(has "$W/err" 'ВРЕМЕННУЮ копию') $(has "$W/err" 'грязна: путей 1') $(has "$W/err" 'stray.txt') $(has "$W/err" 'node_modules нет по построению')" "текст отказа: временная копия, причина «грязна» с числом и путём, почему зависимостей нет"
kreset noui все
assert "64 нет нет" "$(kpush -- "$KUI:refs/heads/k6") $(knpm) $(khook)" "отправка вершины ui из копии на noui (чистой, с зависимостями) → отказ 64 до хука"
assert "да нет" "$(has "$W/err" "рабочая копия на ${KNO:0:8}, а отправляется ${KUI:0:8}") $(has "$W/err" 'грязна')" "текст отказа: причина «на другой ревизии» с обеими вершинами, «грязна» не названа"
kreset ui все; echo l > "$KS/ui-future/dev-x.log"
assert "0 нет ran nm=да" "$(kpush -- HEAD:refs/heads/k7) $(knpm) $(khook)" "почти совпадение: неотслеживаемый, но ИГНОРИРУЕМЫЙ файл (dev-x.log) копию грязной не делает → рабочая копия, хук идёт"
kreset ui все
assert "0 нет ran nm=да" "$(kpush -- "ui:refs/heads/k8") $(knpm) $(khook)" "почти совпадение: вершина названа по имени ветки, но это голова копии → рабочая копия, хук идёт"

# Хук не доходит до проверок консоли — переходник ему не мешает (ход как прежде).
kreset ui все; echo s > "$KS/stray.txt"
assert "0 ran pass" "$(kpush -- HEAD:refs/heads/wip/k9) $(khook | cut -d' ' -f1) $(kdec)" "черновик (все ссылки wip/): грязная копия не отказ — хук проверок не гонит"
assert "64 нет" "$(kpush -- HEAD:refs/heads/wip/k10 HEAD:refs/heads/k10) $(khook)" "близнец: смешанная (wip/ и обычная) — судится, отказ 64"
assert "0 ran" "$(kpush KACHO_SKIP_PREPUSH=1 -- HEAD:refs/heads/k11) $(khook | cut -d' ' -f1)" "KACHO_SKIP_PREPUSH=1: хук проверок дерева не гонит — отказа нет"
assert "0 ran" "$(kpush -- "$KUI:refs/heads/k12" "$KNO:refs/heads/k13") $(khook | cut -d' ' -f1)" "две разные вершины: хук откажет сам до проверок — переходник не судит"
assert "64" "$(kpush -- HEAD:refs/heads/k14 "ui:refs/heads/k15")" "близнец: две ссылки на ОДНУ вершину — судится, отказ 64"
git -C "$KS" push -q origin "$KUI:refs/heads/kdel" 2>/dev/null
assert "0 ran" "$(kpush -- :refs/heads/kdel) $(khook | cut -d' ' -f1)" "одно удаление ссылки: вершины нет — переходник не судит"
git -C "$KS" push -q origin "$KUI:refs/heads/kdel2" 2>/dev/null
assert "64" "$(kpush -- :refs/heads/kdel2 HEAD:refs/heads/k16)" "близнец: удаление и вершина — судится, отказ 64"
kom="$(git -C "$KS" rev-parse origin/main)"; git -C "$KS" update-ref -d refs/remotes/origin/main
assert "0 ran pass" "$(kpush -- HEAD:refs/heads/k17) $(khook | cut -d' ' -f1) $(kdec)" "производитель диапазона отказал (нет точки интеграции) — хук откажет тем же, переходник не судит"
git -C "$KS" update-ref refs/remotes/origin/main "$kom"

# Производители решения хука и переменные, заменяющие их вывод (по близнецу на каждую):
# KACHO_SKIP_PREPUSH — весь хук (k11 выше); KACHO_PREPUSH_GROUP — вывод prepush-groups.sh;
# KACHO_PUSH_RANGE — вход prepush-groups.sh, хук ставит его сам (вызывающего перекрывает);
# KACHO_TRUNK_REF — база prepush-range.sh. Дерево (subject_tree_for_push) переменной не заменяется.
kreset ui все; echo s > "$KS/stray.txt"
assert "0 ran nogroup" "$(kpush KACHO_PREPUSH_GROUP=go -- HEAD:refs/heads/g1) $(khook | cut -d' ' -f1) $(kdec)" "KACHO_PREPUSH_GROUP=go: правка консоли из ГРЯЗНОЙ копии — не отказ: проверок консоли хук не гонит"
assert "да" "$(has "$W/err" 'набор групп хука «go»')" "решение названо: набор групп хука и его источник"
kreset ui нет
assert "0 нет ran nm=нет nogroup" "$(kpush KACHO_PREPUSH_GROUP=go -- HEAD:refs/heads/g2) $(knpm) $(khook) $(kdec)" "KACHO_PREPUSH_GROUP=go: чистая копия без зависимостей — установки нет"
kreset ui все; echo s > "$KS/stray.txt"
assert "64 нет temp" "$(kpush KACHO_PREPUSH_GROUP='go ui' -- HEAD:refs/heads/g3) $(khook) $(kdec)" "почти совпадение: KACHO_PREPUSH_GROUP='go ui' — группа консоли названа, грязная копия → 64"
assert "64 temp" "$(kpush KACHO_PREPUSH_GROUP=all -- HEAD:refs/heads/g4) $(kdec)" "почти совпадение: KACHO_PREPUSH_GROUP=all — ci-local гонит и ui → 64"
assert "64 temp" "$(kpush KACHO_PREPUSH_GROUP=' ' -- HEAD:refs/heads/g5) $(kdec)" "почти совпадение: набор из одних пробелов — ci-local читает пустой как all → 64"
assert "0 ran nogroup" "$(kpush KACHO_PREPUSH_GROUP='go all' -- HEAD:refs/heads/g5b) $(khook | cut -d' ' -f1) $(kdec)" "близнец: «go all» — all не единственным словом, ci-local консоль не гонит (неизвестная группа) → суждения нет"
assert "64 temp" "$(kpush KACHO_PUSH_RANGE="$KNO..$KNO" -- HEAD:refs/heads/g6) $(kdec)" "KACHO_PUSH_RANGE вызывающего (диапазон без консоли) хук перекрывает своим — и суждение тоже: 64"
assert "0 ran untouched" "$(kpush KACHO_TRUNK_REF=ui -- HEAD:refs/heads/g7) $(khook | cut -d' ' -f1) $(kdec)" "KACHO_TRUNK_REF=ui: база — сама вершина, диапазон пуст → правка консоли не тронута, грязная копия не отказ"
assert "64 temp" "$(kpush KACHO_TRUNK_REF=main -- HEAD:refs/heads/g8) $(kdec)" "почти совпадение: KACHO_TRUNK_REF=main — диапазон несёт ui-future/ → 64"

# Отказы установки — до хука, кодом 69 («не выполнилось»), причина каждой — своим текстом.
kreset ui нет
assert "69 нет да" "$(kpush FAKE_NPM_FAIL=root -- HEAD:refs/heads/k18) $(khook) $(has "$W/err" 'npm ci в ui-future не исполнился')" "npm ci корня не исполнился → 69 до хука, причина названа"
kreset ui нет
assert "69 нет да" "$(kpush FAKE_NPM_DIRTY=1 -- HEAD:refs/heads/k19) $(khook) $(has "$W/err" 'после установки копия стала грязной')" "установка оставила неигнорируемый файл → 69 до хука: хук судил бы временную копию"
kreset nodr нет
assert "69 нет нет да" "$(kpush -- HEAD:refs/heads/k20) $(khook) $(knpm) $(has "$W/err" 'предиката готовности ui-future/scripts/deps-ready.mjs')" "предиката готовности в дереве нет → 69 до хука, npm не звался"
kreset ui нет
assert "69 нет да" "$(kpush PATH="$KNB:/usr/bin:/bin" -- HEAD:refs/heads/k21) $(khook) $(has "$W/err" 'node нет в PATH')" "node нет в PATH → 69 до хука, причина названа"

# Граница переходника: его core.hooksPath в проверки хука не уходит; заданное вызывающим — уходит.
kreset ui все
kpush -- HEAD:refs/heads/k22 >/dev/null
assert "0 0" "$(grep -c 'core.hooksPath' "$W/khook") $(sed -n 's/.* hs=\([0-9]*\).*/\1/p' "$W/khook")" "хук не видит ни core.hooksPath переходника, ни HS_* — фикстуры проверок не получают чужих хуков"
kreset ui все
(cd "$KS" && slot PATH="$KPATH" KNPM_LOG="$W/knpm.log" KHOOK="$W/khook" bash "$SLOT" ci-local -- git -c user.probe=1 push -q origin HEAD:refs/heads/k23) >/dev/null
assert "1 ran" "$(grep -c "'user.probe'='1'" "$W/khook") $(khook | cut -d' ' -f1)" "близнец: -c вызывающего до хука доходит"

# Где переходника нет: клон без консоли, класс не ci-local, --no-verify.
KN="$W/knocons"; git init -q -b main "$KN"; git -C "$KN" remote add origin "$W/knocons.git"; git init -q --bare -b main "$W/knocons.git"
echo a > "$KN/f"; git -C "$KN" add f; sandbox_git -C "$KN" commit -qm a; cp "$KS/.git/hooks/pre-push" "$KN/.git/hooks/pre-push"
mkdir -p "$KN/ui-futurex"; echo 1 > "$KN/ui-futurex/a"; echo s > "$KN/stray.txt"; git -C "$KN" add ui-futurex; sandbox_git -C "$KN" commit -qm b
rm -f "$W/khook"; jm="$(grep -c ' console-deps ' "$JL" 2>/dev/null)"
(cd "$KN" && slot PATH="$KPATH" KHOOK="$W/khook" bash "$SLOT" ci-local -- git push -q origin HEAD:refs/heads/n1) >/dev/null
assert "ran $jm" "$(khook | cut -d' ' -f1) $(grep -c ' console-deps ' "$JL" 2>/dev/null)" "клон без ui-future/ (есть ui-futurex/) — переходника нет, суждения нет, хук как прежде"
kreset ui все; echo s > "$KS/stray.txt"
assert "0 ran" "$(cd "$KS" && slot PATH="$KPATH" KHOOK="$W/khook" bash "$SLOT" docker -- git push -q origin HEAD:refs/heads/n2) $(khook | cut -d' ' -f1)" "класс не ci-local — переходника нет: грязная копия не отказ"
rm -f "$W/khook"
assert "0 нет" "$(cd "$KS" && slot PATH="$KPATH" KHOOK="$W/khook" bash "$SLOT" ci-local -- git push -q --no-verify origin HEAD:refs/heads/n3) $(khook)" "--no-verify — хука нет, переходника нет"

# Мутанты: каждое условие снято по одному — проба выше обязана краснеть.
KM="$W/kmut"; mkdir -p "$KM"; ln -s "$HERE/remote-heavy" "$KM/remote-heavy"
kmut() { python3 - "$SLOT" "$KM/$1.sh" "$2" "$3" <<'PYM'
import sys
src, dst, old, new = sys.argv[1:5]
t = open(src).read()
if t.count(old) != 1:
    sys.exit("мутант: образец найден %d раз" % t.count(old))
open(dst, "w").write(t.replace(old, new))
PYM
}
# shellcheck disable=SC2016  # образцы мутантов — текст слота, не раскрываются
kmut range '    case "$ch" in *ui-future/*) ;; *)' '    case "ui-future/" in *ui-future/*) ;; *)'
# shellcheck disable=SC2016
kmut wc '    if [ "$tips" != "$head" ] || [ -n "$dirty" ]; then' '    if false; then'
# shellcheck disable=SC2016
kmut wire '[ "$CLASS" = ci-local ] && console_adapter' 'false && console_adapter'
# shellcheck disable=SC2016
kmut ready '        [ -z "$miss" ] || continue' '        continue'
# shellcheck disable=SC2016
kmut never '        node ui-future/scripts/deps-ready.mjs "${m%/package.json}" >/dev/null 2>&1 && continue' '        false && continue'
# shellcheck disable=SC2016
kmut groups '    case " ${grp:-all} " in' '    case " ui " in'
# shellcheck disable=SC2016
kmut gall '    case " ${grp:-all} " in' '    case " ${grp} " in'
# shellcheck disable=SC2016
kmut gword '" all "|*" ui "*' '*" all "*|*" ui "*'
# shellcheck disable=SC2016
kmut gprange '    grp="$(KACHO_PUSH_RANGE="$rg" bash scripts/hooks/prepush-groups.sh 2>/dev/null)"' '    grp="$(bash scripts/hooks/prepush-groups.sh 2>/dev/null)"'
# shellcheck disable=SC2016
kmut trunk '    rg="$(printf '"'"'%s\n'"'"' "$lines" | bash scripts/hooks/prepush-range.sh 2>/dev/null)"; rgc=$?' '    rg="$(printf '"'"'%s\n'"'"' "$lines" | env -u KACHO_TRUNK_REF bash scripts/hooks/prepush-range.sh 2>/dev/null)"; rgc=$?'
for m in range wc wire ready never groups gall gword gprange trunk; do assert 1 "$(diff "$SLOT" "$KM/$m.sh" | grep -c '^<')" "мутант «$m» лёг ровно одной строкой"; done
kreset noui нет; echo s > "$KS/stray.txt"
assert "64 нет" "$(KSLOT="$KM/range.sh" kpush KACHO_PREPUSH_GROUP='go ui-types' -- HEAD:refs/heads/m1) $(khook)" "мутант «проверка диапазона снята»: правка без консоли из грязной копии при группе консоли получает отказ — проба k4c его ловит (без названной группы его маскирует набор групп: prepush-groups.sh сам судит ui-future/)"
kreset ui все; echo s > "$KS/stray.txt"
assert "0 ran" "$(KSLOT="$KM/wc.sh" kpush -- HEAD:refs/heads/m2) $(khook | cut -d' ' -f1)" "мутант «судит только рабочую копию»: грязная копия уходит в хук — проба «грязна → 64» его ловит"
kreset ui нет
assert "0 нет nm=нет" "$(KSLOT="$KM/wire.sh" kpush -- HEAD:refs/heads/m3) $(knpm) $(khook | cut -d' ' -f2)" "мутант «переходник не ставится»: хук судит копию без node_modules — проба установки его ловит"
kreset ui нет
assert "0 нет nm=нет" "$(KSLOT="$KM/ready.sh" kpush -- HEAD:refs/heads/m4) $(knpm) $(khook | cut -d' ' -f2)" "мутант «готовым признан всякий»: зависимостей нет, а установки нет — проба установки его ловит"
kreset ui все
assert "звался" "$(KSLOT="$KM/never.sh" kpush -- HEAD:refs/heads/m5 >/dev/null; [ "$(knpm)" = нет ] && echo нет || echo звался)" "мутант «готовность не судится»: стоящие зависимости ставятся заново — проба «уже стоят» его ловит"
kreset ui все; echo s > "$KS/stray.txt"
assert "64 нет" "$(KSLOT="$KM/groups.sh" kpush KACHO_PREPUSH_GROUP=go -- HEAD:refs/heads/m6) $(khook)" "мутант «набор групп не спрошен»: KACHO_PREPUSH_GROUP=go из грязной копии получает отказ — проба g1 его ловит"
assert "0 ran" "$(KSLOT="$KM/gall.sh" kpush KACHO_PREPUSH_GROUP=' ' -- HEAD:refs/heads/m7) $(khook | cut -d' ' -f1)" "мутант «пустой набор — не all»: набор из пробелов уходит в хук без суждения — проба g5 его ловит"
assert "64 нет" "$(KSLOT="$KM/gword.sh" kpush KACHO_PREPUSH_GROUP='go all' -- HEAD:refs/heads/m7b) $(khook)" "мутант «all — любым словом»: «go all» получает отказ, хотя ci-local консоль не гонит — проба g5b его ловит"
assert "0 ran" "$(KSLOT="$KM/gprange.sh" kpush KACHO_PUSH_RANGE="$KNO..$KNO" -- HEAD:refs/heads/m8) $(khook | cut -d' ' -f1)" "мутант «группы спрошены с диапазоном вызывающего»: суждение разошлось с хуком — проба g6 его ловит"
assert "64 нет" "$(KSLOT="$KM/trunk.sh" kpush KACHO_TRUNK_REF=ui -- HEAD:refs/heads/m9) $(khook)" "мутант «база диапазона без KACHO_TRUNK_REF»: пустой у хука диапазон судится как правка консоли — проба g7 его ловит"
fi

echo "[CENSUS] heavy-slot: утверждений $((pass + fail)), сошлось $pass, разошлось $fail; граница (не ловится, заявлено в шапке) $bound; не построено частей $void"
[ "$fail" -eq 0 ] || exit 1
[ "$void" -eq 0 ] || exit 2
exit 0
