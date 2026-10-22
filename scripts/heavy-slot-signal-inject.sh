#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# heavy-slot-signal-inject.sh — доказательство того, что команда слота получает SIGPIPE и SIGHUP
# по умолчанию, как в конвейере, при любом вызывающем (ws#1274), и что маску перезапуска 0x1001
# держат пробы, а не шапка.
#
# ЗАЧЕМ ОТДЕЛЬНО от heavy-slot-inject.sh. Та проба судит МАШИНУ (systemd --user, cgroup памяти,
# docker, настоящая память) и внешнего маршрута не имеет (запись MACHINE heavy-slot.sh, ws#1303):
# при доступном кластере её исход — «не выполнилось». Эта часть машину не судит: память —
# синтетический meminfo, каталог слотов — свой временный, предел ядра не нужен, — и потому
# переносима: Job профиля ws (scripts/*-inject.sh ведомости PORTABLE) и шаг конвейера.
# Возврат приёмки ws#1274: вход «PIPE и HUP заглушены» маску не держал — мутанты 0x1 и 0x1000
# перезапускают и на нём; держат её вызывающие с ОДНИМ заглушённым сигналом.
# Коды: 0 — все утверждения сошлись; 1 — хотя бы одно нет; 2 — утверждений не исполнено ни одного.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SLOT="$HERE/heavy-slot.sh"
W="$(mktemp -d)"
# shellcheck disable=SC2154
trap '_rc=$?; rm -rf "$W" 2>/dev/null || rm -rf "$W" || echo "ПРЕДУПРЕЖДЕНИЕ: временный каталог $W не снят; код проверки $_rc сохранён" >&2; exit $_rc' EXIT

pass=0; fail=0
assert() {
    if [ "$1" = "$2" ]; then echo "  [OK]   $3"; pass=$((pass + 1))
    else echo "  [FAIL] $3 — ожидалось «$1», получено «$2»" >&2; fail=$((fail + 1)); fi
}
# Синтетическая память машины (MemTotal 96 ГиБ, занято 1000 МиБ) и свой каталог слотов — как у
# heavy-slot-inject.sh: исход не зависит от соседних полос и настоящей памяти.
printf 'MemTotal: %d kB\nMemAvailable: %d kB\n' $((98304 * 1024)) $(( (98304 - 1000) * 1024 )) > "$W/meminfo"
export HEAVY_SLOT_DIR="$W/slots" HEAVY_SLOT_MEMINFO="$W/meminfo" HEAVY_SLOT_LIMIT_MIB=100000 \
       HEAVY_SLOT_POLL_S=1 HEAVY_SLOT_WAIT_S=2 HEAVY_SLOT_GUARD_S=1 HEAVY_SLOT_GUARD_GRACE_S=10 \
       HEAVY_SLOT_BUDGET_MIB=64
# slot [ENV=…] <класс> -- … — код слота; stderr в $W/err, stdout в $W/out.
slot() { env "$@" 2> "$W/err" > "$W/out"; echo $?; }

echo "── диспозиция сигналов: команда слота — SIGPIPE и SIGHUP по умолчанию, как в конвейере (ws#1274)"
# Замер 2026-10-21 (GNU timeout 9.7, uutils timeout 0.8.0): timeout СБРАСЫВАЕТ унаследованный
# SIG_IGN на SIGHUP и СОХРАНЯЕТ его на SIGPIPE; bash снять SIG_IGN, полученный при входе, не
# может. Под вызывающим с SIG_IGN (nohup, python) `yes | head -n 1` давал 1 вместо 141, а
# пробы сигналов краснели либо зеленели в зависимости от обёртки, а не от кода.
# Вывод команды: «<код yes | head> <биты SIG_IGN на PIPE|HUP>»; конвейер — «141 0».
# shellcheck disable=SC2016  # строка дочерней оболочки, раскрывает она
SIGP='set -o pipefail; yes | head -n 1 > /dev/null; p=$?; i=$(sed -n "s/^SigIgn:[[:space:]]*//p" /proc/$$/status); printf "%s %s" "$p" $(( 16#$i & 0x1001 ))'
IGN=(python3 -c 'import os, signal, sys; signal.signal(signal.SIGPIPE, signal.SIG_IGN); signal.signal(signal.SIGHUP, signal.SIG_IGN); os.execvp(sys.argv[1], sys.argv[1:])')
sigrun() { local s="$1"; shift; slot "$@" bash "$s" docker -- bash -c "$SIGP" > /dev/null; cat "$W/out"; }
assert "141 0" "$(sigrun "$SLOT")" "контроль: вызывающий без SIG_IGN — 141, ничего не заглушено"
assert "141 0" "$(sigrun "$SLOT" "${IGN[@]}")" "вызывающий с SIG_IGN на PIPE и HUP — команда их не наследует"
assert "141 0" "$(sigrun "$SLOT" "${IGN[@]}" timeout 60)" "то же под timeout над слотом — тот же исход"
assert "141 0" "$(slot "${IGN[@]}" bash "$SLOT" docker -- timeout 60 bash -c "$SIGP" > /dev/null; cat "$W/out")" "то же под timeout внутри команды — тот же исход"
python3 - "$SLOT" "$W/sigmut.sh" <<'PYM' && SIGMUT=да || SIGMUT=нет
import sys, re
s, d = sys.argv[1:3]
t = open(s, encoding="utf-8").read()
a = "    exec env --default-signal=PIPE,HUP KACHO_SIGDISP=1 bash \"$0\" \"$@\"\n"
if t.count(a) != 1:
    sys.exit(1)
open(d, "w", encoding="utf-8").write(t.replace(a, "    :\n"))
PYM
assert "да" "$SIGMUT" "мутант «диспозиция не восстановлена» лёг ровно одной строкой"
assert "1 4097" "$(sigrun "$W/sigmut.sh" "${IGN[@]}")" "мутант «диспозиция не восстановлена»: под SIG_IGN вызывающего — 1 и заглушённые PIPE|HUP, проба выше его ловит"
# Вызывающий с ОДНИМ заглушённым сигналом (возврат приёмки ws#1274): маска перезапуска судит биты
# PIPE (0x1000) и HUP (0x1) врозь. Вход «оба заглушены» её не держит: маска из одного бита на нём
# тоже перезапускает. «Только PIPE» — python, а timeout над слотом сбрасывает лишь HUP; «только HUP» — nohup.
IGNP=(python3 -c 'import os, signal, sys; signal.signal(signal.SIGPIPE, signal.SIG_IGN); os.execvp(sys.argv[1], sys.argv[1:])')
assert "141 0" "$(sigrun "$SLOT" "${IGNP[@]}")" "вызывающий с SIG_IGN только на PIPE — команда его не наследует"
assert "141 0" "$(sigrun "$SLOT" "${IGNP[@]}" timeout 60)" "то же под timeout над слотом — тот же исход"
assert "141 0" "$(sigrun "$SLOT" nohup)" "вызывающий nohup (SIG_IGN только на HUP) — команда его не наследует"
# sigmask <файл> <маска> — копия слота с маской перезапуска <маска> вместо 0x1001 (ровно одно вхождение).
sigmask() {
    python3 - "$SLOT" "$1" "$2" <<'PYM'
import sys
s, d, m = sys.argv[1:4]
t = open(s, encoding="utf-8").read()
a = "& 0x1001 )); then\n"
if t.count(a) != 1:
    sys.exit(1)
open(d, "w", encoding="utf-8").write(t.replace(a, "& " + m + " )); then\n"))
PYM
}
sigmask "$W/sigmask-hup.sh" 0x1 && SIGM1=да || SIGM1=нет
sigmask "$W/sigmask-pipe.sh" 0x1000 && SIGM2=да || SIGM2=нет
assert "да да" "$SIGM1 $SIGM2" "мутанты маски «только HUP» (0x1) и «только PIPE» (0x1000) легли ровно одной строкой"
assert "1 4096" "$(sigrun "$W/sigmask-hup.sh" "${IGNP[@]}")" "мутант маски 0x1: вызывающий «только PIPE» — 1 и заглушённый PIPE, случай «только PIPE» его ловит"
assert "1 4096" "$(sigrun "$W/sigmask-hup.sh" "${IGNP[@]}" timeout 60)" "мутант маски 0x1 под timeout над слотом — тот же отказ, случай с timeout его ловит"
assert "141 1" "$(sigrun "$W/sigmask-pipe.sh" nohup)" "мутант маски 0x1000: вызывающий nohup — заглушённый HUP дошёл до команды, случай nohup его ловит"
assert "141 0 141 0" "$(sigrun "$W/sigmask-hup.sh" "${IGN[@]}") $(sigrun "$W/sigmask-pipe.sh" "${IGN[@]}")" "оба мутанта маски проходят вход «PIPE и HUP» — держат их лишь случаи с одним сигналом"

echo "[CENSUS] heavy-slot-signal: утверждений $((pass + fail)), сошлось $pass, разошлось $fail"
[ "$fail" -eq 0 ] || exit 1
[ $((pass + fail)) -gt 0 ] || exit 2
exit 0
