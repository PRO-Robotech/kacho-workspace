#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# wave-errors-inject.sh — доказательство того, что `scripts/wave-errors.sh`
# СПОСОБЕН отвергнуть строку вне словаря, покраснеть на доле выше предела и не
# выдать «ошибок ноль» там, где счётчик не вёлся.
#
# Каталог волны — свой временный (`WAVE_ERRORS_DIR`): счётчики настоящих волн
# проба не видит и не трогает. Граница предела проверяется ровно на 5 %:
# законный близнец «доля 5,0 %» обязан пройти, «5,1 %» — покраснеть.
# Каталог без переопределения проверяется копией счётчика в клоне и в worktree
# под `tmp/` песочницы — их корень выводит `scripts/lib/ws-home.sh`.
# Коды: 0 — все утверждения сошлись; 1 — хотя бы одно нет; 2 — корневой подписи
# нет, посев worktree не построить.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
E="$HERE/wave-errors.sh"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
pass=0 fail=0
assert() {
    if [ "$1" = "$2" ]; then echo "  [OK]   $3"; pass=$((pass + 1))
    else echo "  [FAIL] $3 — ожидалось «$1», получено «$2»" >&2; sed 's/^/         /' "$W/out" >&2; fail=$((fail + 1)); fi
}
run() { bash "$E" "$@" > "$W/out" 2>&1; echo $?; }
has() { grep -q -- "$1" "$W/out" && echo да || echo нет; }
export WAVE_ERRORS_DIR="$W/wave-7"
F="$WAVE_ERRORS_DIR/errors.md"

echo "== счётчик не вёлся — не «ноль»"
assert "2 да" "$(run rate 7 10) $(has 'счётчик волны не вёлся')" "файла нет → код 2"

echo "== волна без ошибок — законный зелёный по заведённому счётчику"
Z="$W/wave-z"
assert "0" "$(WAVE_ERRORS_DIR="$Z" bash "$E" open z > "$W/out" 2>&1; echo $?)" "open заводит счётчик"
assert "0 да" "$(WAVE_ERRORS_DIR="$Z" bash "$E" rate z 10 > "$W/out" 2>&1; echo $?) $(has 'строк 0')" "заведённый счётчик без строк → код 0, «строк 0»"
: > "$Z/errors.md"
assert "2 да" "$(WAVE_ERRORS_DIR="$Z" bash "$E" rate z 10 > "$W/out" 2>&1; echo $?) $(has 'нет шапки')" "пустой файл без шапки — не «ошибок ноль»: код 2"
WAVE_ERRORS_DIR="$Z" bash "$E" open z > /dev/null 2>&1
WAVE_ERRORS_DIR="$Z" bash "$E" add z truncation 1 A x y > /dev/null 2>&1
WAVE_ERRORS_DIR="$Z" bash "$E" open z > /dev/null 2>&1
assert "3" "$(grep -c '^|' "$Z/errors.md")" "повторный open строк не стирает"

echo "== запись"
assert "0" "$(run add 7 false-fail 0.25 A ci-watcher повтор на той же голове)" "законная строка записана"
assert "3" "$(grep -c '^|' "$F")" "шапка, разделитель и строка в таблице"
assert "1 да" "$(run add 7 review 1 A go-style возврат по существу) $(has 'не ошибка оркестровки')" "возврат ревью по существу отвергнут"
assert "1 да" "$(run add 7 misc 1 A x y) $(has 'вне словаря')" "класс вне словаря отвергнут"
assert "1" "$(run add 7 false-fail час A x y)" "часы не числом отвергнуты"
assert "1" "$(run add 7 new:Bad_Name 1 A x y)" "имя нового класса вне формы отвергнуто"
assert "3" "$(grep -c '^|' "$F")" "отвергнутые строки в файл не попали"
assert "0" "$(run add 7 new:stale-base 0.25 B git-operator 'база | старая')" "новый класс записан, разделитель в заметке обезврежен"

echo "== доля и предел"
assert "0 да" "$(run rate 7 10) $(has 'доля 5.0 %')" "0,5 ч из 10 — ровно 5 % — проходит (граница)"
assert "да" "$(has 'NEW-CLASS new:stale-base')" "новый класс назван отдельной строкой"
assert "1 да" "$(run rate 7 9.8) $(has 'КРАСНОЕ — доля 5.1 %')" "0,5 ч из 9,8 — 5,1 % — красное"
assert "2" "$(run rate 7 0)" "часы волны 0 → вердикта нет"

echo "== строка, правленная руками"
echo '| 2026-10-06T00:00Z | C | x | misc | 1 | y |' >> "$F"
assert "1 да" "$(run rate 7 100) $(has 'вне формы 1')" "строка вне словаря в файле → отказ, а не тихий пропуск"

echo "== каталог волны без переопределения: счётчик в клоне под tmp/ пишет в общую волну"
# Счётчик лежит в КЛОНЕ под <ws>/tmp/ (у клона свой .git): волна обязана выйти
# <ws>/tmp/wave-N, а не <клон>/tmp/wave-N (check-verifier ws#933, п. 6).
WS2="$W/ws2"
git init -q -b main "$WS2" && mkdir -p "$WS2/tmp"
C="$WS2/tmp/tools-clone"
git init -q -b main "$C" && mkdir -p "$C/scripts/lib"
cp "$E" "$C/scripts/" && cp "$HERE/lib/ws-home.sh" "$C/scripts/lib/"
env -u WAVE_ERRORS_DIR bash "$C/scripts/wave-errors.sh" add 8 truncation 0.1 A x y > "$W/out" 2>&1
assert "да нет" "$([ -s "$WS2/tmp/wave-8/errors.md" ] && echo да || echo нет) $([ -e "$C/tmp/wave-8" ] && echo да || echo нет)" "строка — в <ws>/tmp/wave-8, а не в клоне"
WT="$WS2/tmp/wt"
# Подпись посева — корневая учётная запись через HOME песочницы (check-16).
# shellcheck source=lib/sandbox-git-home.sh
. "$HERE/lib/sandbox-git-home.sh"
sandbox_git_home "$W/home" || exit 2
sandbox_git -C "$WS2" commit -q --allow-empty -m base
git -C "$WS2" worktree add -q "$WT" 2> /dev/null && mkdir -p "$WT/scripts/lib" && cp "$E" "$WT/scripts/" && cp "$HERE/lib/ws-home.sh" "$WT/scripts/lib/"
env -u WAVE_ERRORS_DIR bash "$WT/scripts/wave-errors.sh" add 8 truncation 0.1 B x y > "$W/out" 2>&1
assert "2" "$(grep -c '| truncation |' "$WS2/tmp/wave-8/errors.md")" "близнец: из worktree под tmp/ — та же волна"

echo
echo "wave-errors-inject: утверждений $((pass + fail)); сошлось $pass, разошлось $fail"
[ "$fail" -eq 0 ]
