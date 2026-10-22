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
# Путь запуска задан явно (ws#1326): случаи слота гонятся на обоих путях, мутанты — на watch.
# Коды: 0 — все утверждения сошлись; 1 — хотя бы одно нет; 2 — утверждений не исполнено ни одного.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SLOT="$HERE/heavy-slot.sh"
W="$(mktemp -d)"
# shellcheck disable=SC2154
trap '_rc=$?; rm -rf "$W" 2>/dev/null || rm -rf "$W" || echo "ПРЕДУПРЕЖДЕНИЕ: временный каталог $W не снят; код проверки $_rc сохранён" >&2; exit $_rc' EXIT

pass=0; fail=0; void=0
assert() {
    if [ "$1" = "$2" ]; then echo "  [OK]   $3"; pass=$((pass + 1))
    else
        echo "  [FAIL] $3 — ожидалось «$1», получено «$2»" >&2; fail=$((fail + 1))
        # Отказ называет причину, а не симптом: stderr последнего вызова слота (путь запуска, отказ).
        [ -s "$W/err" ] && sed -n '1,6s/^/         слот: /p' "$W/err" >&2
    fi
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
# Вызывающие: оба сигнала, только PIPE, только HUP — python, и каждый задаёт ОБА сигнала явно:
# python при старте сам заглушает SIGPIPE, и exec это наследует (замер Job ws#1326 @0c59eb69b:
# «только HUP» без SIG_DFL на PIPE дал без слота «1 4097»), а HUP вызывающий пробы мог заглушить.
IGN=(python3 -c 'import os, signal, sys; signal.signal(signal.SIGPIPE, signal.SIG_IGN); signal.signal(signal.SIGHUP, signal.SIG_IGN); os.execvp(sys.argv[1], sys.argv[1:])')
IGNP=(python3 -c 'import os, signal, sys; signal.signal(signal.SIGPIPE, signal.SIG_IGN); signal.signal(signal.SIGHUP, signal.SIG_DFL); os.execvp(sys.argv[1], sys.argv[1:])')
IGNH=(python3 -c 'import os, signal, sys; signal.signal(signal.SIGPIPE, signal.SIG_DFL); signal.signal(signal.SIGHUP, signal.SIG_IGN); os.execvp(sys.argv[1], sys.argv[1:])')
# sigrun <слот> [ENV=…] [вызывающий…] — вывод SIGP, исполненной командой слота.
sigrun() { local s="$1"; shift; slot "$@" bash "$s" docker -- bash -c "$SIGP" > /dev/null; cat "$W/out"; }

# ПУТЬ ЗАПУСКА (ws#1326). Команду слот ставит либо в `systemd-run --user --scope` (есть systemd
# --user: ранер конвейера), либо запасным путём watch (его нет: Job профиля ws). Конвейер run
# 39743660497 @00c4c8344: мутант маски 0x1000 под nohup дал «141 0», Job при d051a7237 — «141 1»;
# HUP команды на ранере сбросила не маска — systemd-run ли, nohup ли ранера, не замерено. Исход
# мутанта судил окружение, а не маску. Поэтому: случаи слота — на обоих путях (auto — путь
# окружения, watch — явный), мутанты — на watch, где диспозицию решает лишь перезапуск слота;
# «только HUP» — python, предпосылка каждого вызывающего проверена без слота; nohup — случай
# настоящего вызывающего, исполняется лишь при выполненной предпосылке, иначе [VOID] и счёт.
echo "── предпосылка: вызывающий отдаёт команде заявленное, без слота"
assert "1 4097" "$("${IGN[@]}" bash -c "$SIGP")" "вызывающий «PIPE и HUP» без слота — 1 и заглушённые PIPE|HUP"
assert "1 4096" "$("${IGNP[@]}" bash -c "$SIGP")" "вызывающий «только PIPE» без слота — 1 и заглушённый PIPE"
assert "141 1" "$("${IGNH[@]}" bash -c "$SIGP")" "вызывающий «только HUP» без слота — 141 и заглушённый HUP"
NOHUP="$(nohup bash -c "$SIGP" 2>/dev/null)"
if [ "$NOHUP" = "141 1" ]; then NOHUP_OK=да; echo "  [INFO] nohup без слота — «141 1»: случаи nohup исполняются"
else NOHUP_OK=нет; echo "  [VOID] nohup без слота — «$NOHUP», не «141 1»: HUP он здесь не заглушает, случаи nohup не исполнены; «только HUP» держит python"; fi

for LIM in auto watch; do
    L="HEAVY_SLOT_LIMITER=$LIM"
    echo "── команда слота, путь $L"
    assert "141 0" "$(sigrun "$SLOT" "$L")" "[$LIM] контроль: вызывающий без SIG_IGN — 141, ничего не заглушено"
    if [ "$LIM" = auto ]; then
        if grep -q 'запасной путь' "$W/err"; then echo "  [INFO] путь auto здесь — запасной watch"
        else echo "  [INFO] путь auto здесь — systemd-run --user --scope"; fi
    fi
    assert "141 0" "$(sigrun "$SLOT" "$L" "${IGN[@]}")" "[$LIM] вызывающий с SIG_IGN на PIPE и HUP — команда их не наследует"
    assert "141 0" "$(sigrun "$SLOT" "$L" "${IGN[@]}" timeout 60)" "[$LIM] то же под timeout над слотом — тот же исход"
    assert "141 0" "$(slot "$L" "${IGN[@]}" bash "$SLOT" docker -- timeout 60 bash -c "$SIGP" > /dev/null; cat "$W/out")" "[$LIM] то же под timeout внутри команды — тот же исход"
    assert "141 0" "$(sigrun "$SLOT" "$L" "${IGNP[@]}")" "[$LIM] вызывающий с SIG_IGN только на PIPE — команда его не наследует"
    assert "141 0" "$(sigrun "$SLOT" "$L" "${IGNP[@]}" timeout 60)" "[$LIM] то же под timeout над слотом — тот же исход"
    assert "141 0" "$(sigrun "$SLOT" "$L" "${IGNH[@]}")" "[$LIM] вызывающий с SIG_IGN только на HUP — команда его не наследует"
    if [ "$NOHUP_OK" = да ]; then
        assert "141 0" "$(sigrun "$SLOT" "$L" nohup)" "[$LIM] вызывающий nohup (SIG_IGN только на HUP) — команда его не наследует"
    else void=$((void + 1)); fi
done

# Мутанты — на явном watch (шапка раздела «путь запуска»).
MW="HEAVY_SLOT_LIMITER=watch"
echo "── мутанты, путь $MW"
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
assert "1 4097" "$(sigrun "$W/sigmut.sh" "$MW" "${IGN[@]}")" "мутант «диспозиция не восстановлена»: под SIG_IGN вызывающего — 1 и заглушённые PIPE|HUP, проба выше его ловит"
# Вызывающий с ОДНИМ заглушённым сигналом (возврат приёмки ws#1274): маска перезапуска судит биты
# PIPE (0x1000) и HUP (0x1) врозь. Вход «оба заглушены» её не держит: маска из одного бита на нём
# тоже перезапускает. «Только PIPE» и «только HUP» — python; timeout над слотом сбрасывает лишь HUP.
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
assert "1 4096" "$(sigrun "$W/sigmask-hup.sh" "$MW" "${IGNP[@]}")" "мутант маски 0x1: вызывающий «только PIPE» — 1 и заглушённый PIPE, случай «только PIPE» его ловит"
assert "1 4096" "$(sigrun "$W/sigmask-hup.sh" "$MW" "${IGNP[@]}" timeout 60)" "мутант маски 0x1 под timeout над слотом — тот же отказ, случай с timeout его ловит"
assert "141 1" "$(sigrun "$W/sigmask-pipe.sh" "$MW" "${IGNH[@]}")" "мутант маски 0x1000: вызывающий «только HUP» — заглушённый HUP дошёл до команды, случай «только HUP» на watch его ловит"
if [ "$NOHUP_OK" = да ]; then
    assert "141 1" "$(sigrun "$W/sigmask-pipe.sh" "$MW" nohup)" "мутант маски 0x1000: вызывающий nohup — заглушённый HUP дошёл до команды, случай nohup на watch его ловит"
else void=$((void + 1)); fi
assert "141 0 141 0" "$(sigrun "$W/sigmask-hup.sh" "$MW" "${IGN[@]}") $(sigrun "$W/sigmask-pipe.sh" "$MW" "${IGN[@]}")" "оба мутанта маски проходят вход «PIPE и HUP» — держат их лишь случаи с одним сигналом"

echo "[CENSUS] heavy-slot-signal: утверждений $((pass + fail)), сошлось $pass, разошлось $fail, не исполнено $void (nohup без предпосылки)"
[ "$fail" -eq 0 ] || exit 1
[ $((pass + fail)) -gt 0 ] || exit 2
exit 0
