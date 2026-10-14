#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# trunk-future-inject.sh — доказательство scripts/trunk-future.sh исполнением
# (ws#1078). Вход — настоящий клон продукта той же формы: репозиторий с
# `origin/main` = A и боковой головой B, несущей файл FUTURE. Команда пробы
# читает ствол так же, как наборы `product-trunk-gates`: `origin/main` клона из
# `KACHO_HOME_<ПРОДУКТ>`.
#
#   T1  голова B названа — команда видит FUTURE в стволе; клон разработчика не
#       тронут (его origin/main — по-прежнему A);
#   T1′ близнец — та же голова именем ветки, а не sha: тот же исход;
#   T2  мутант: строка перестановки origin/main снята — FUTURE не виден, проба
#       краснеет;
#   T3  код команды проходит как есть (команда с кодом 1 — код 1);
#   T4  без пар, с чужим именем продукта, с ревизией, которой в клоне нет, —
#       код 2, а не 0;
#   T5  неназванный продукт судится своим клоном (KACHO_HOME не переставлен);
#   T6  вызов БЕЗ «--» (так зовут wave.js и git-operator) исполняет именно
#       `scripts/lib/run-suites.sh --void-is-failure --job product-trunk-gates`
#       (дублёр под WS пишет argv и судит ствол): красный набор на будущем
#       стволе — код 1, близнец на нынешнем — 0; мутанты «команда true» и
#       «другое задание» краснеют;
#   T7  чужое имя продукта при живом клоне (KACHO_HOME_OTHER) — код 2: перечень
#       kacho, kaname, corelib держит сам скрипт, а не отсутствие клона.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$here/trunk-future.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/trunk-future-inject.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
pass=0 fail=0
ok() { if [ "$1" = 0 ]; then pass=$((pass + 1)); echo "  [OK]   $2"; else fail=$((fail + 1)); echo "  [FAIL] $2"; fi; }

# shellcheck source=lib/sandbox-git-home.sh
. "$here/lib/sandbox-git-home.sh"
sandbox_git_home "$tmp/home" || { echo "trunk-future-inject: корневой подписи нет — предмета нет" >&2; exit 2; }
g() { sandbox_git "$@"; }
mk() {
    local r="$1"; mkdir -p "$r"; g -C "$r" init -q -b main
    echo a > "$r/BASE"; g -C "$r" add BASE; g -C "$r" commit -qm A
    g -C "$r" update-ref refs/remotes/origin/main HEAD
    g -C "$r" switch -qc pr; echo b > "$r/FUTURE"; g -C "$r" add FUTURE; g -C "$r" commit -qm B
    g -C "$r" switch -q main
}
mk "$tmp/kacho"; mk "$tmp/kaname"
B="$(git -C "$tmp/kacho" rev-parse pr)"
A="$(git -C "$tmp/kacho" rev-parse origin/main)"
export KACHO_HOME_KACHO="$tmp/kacho" KACHO_HOME_KANAME="$tmp/kaname" WS="$tmp"
# shellcheck disable=SC2016  # раскрывается в подставленном окружении команды, а не здесь
SEES='git -C "$KACHO_HOME_KACHO" cat-file -e origin/main:FUTURE'

# expect <код> <что> <команда…> — код команды равен ожидаемому («!0» — любой ненулевой).
expect() {
    local want="$1" what="$2" got; shift 2
    "$@" > "$tmp/o" 2>&1; got=$?
    if [ "$want" = '!0' ]; then [ "$got" -ne 0 ]; else [ "$got" -eq "$want" ]; fi
    ok "$?" "$what (код $got)"
}
same() { [ "$1" = "$2" ]; }

echo "== T1: голова названа — ствол будущий, клон разработчика не тронут"
expect 0 "FUTURE виден в origin/main подставленного клона" bash "$SUT" "kacho=$B" -- bash -c "$SEES"
expect 0 "origin/main клона разработчика — по-прежнему A" same "$(git -C "$tmp/kacho" rev-parse origin/main)" "$A"
echo "== T1′: близнец — голова именем ветки"
expect 0 "имя ветки вместо sha — тот же исход" bash "$SUT" "kacho=pr" -- bash -c "$SEES"

echo "== T2: мутант — перестановки origin/main нет"
sed '/update-ref refs\/remotes\/origin\/main/d' "$SUT" > "$tmp/mut.sh"
expect '!0' "образец мутанта найден в скрипте" cmp -s "$SUT" "$tmp/mut.sh"
expect '!0' "без перестановки FUTURE не виден — проба краснеет" bash "$tmp/mut.sh" "kacho=$B" -- bash -c "$SEES"

echo "== T3: код команды проходит как есть"
expect 1 "команда с кодом 1 — код 1" bash "$SUT" "kacho=$B" -- bash -c 'exit 1'

echo "== T4: будущего состояния нет — код 2, не 0"
expect 2 "без пар" bash "$SUT"
expect 2 "чужое имя продукта" bash "$SUT" "other=$B" -- true
expect 2 "ревизии нет в клоне" bash "$SUT" "kacho=$(printf 'f%.0s' {1..40})" -- true
cp "$tmp/o" "$tmp/o.void"
expect 0 "  ...и в тексте отказа — команда fetch" grep -q 'fetch origin' "$tmp/o.void"

echo "== T5: неназванный продукт — своим клоном"
expect 0 "KACHO_HOME_KANAME не переставлен" bash "$SUT" "kacho=$B" -- bash -c "[ \"\$KACHO_HOME_KANAME\" = '$tmp/kaname' ]"

echo "== T6: вызов без «--» — задание конвейера product-trunk-gates"
mkdir -p "$tmp/scripts/lib"
# Дублёр набора: argv — в файл; на стволе с FUTURE набор красный (код 1), без него — 0.
cat > "$tmp/scripts/lib/run-suites.sh" <<'STUB'
printf '%s\n' "$*" > "$WS/argv"
git -C "$KACHO_HOME_KACHO" cat-file -e origin/main:FUTURE 2>/dev/null && exit 1
exit 0
STUB
expect 1 "красный набор на будущем стволе — код 1" bash "$SUT" "kacho=$B"
expect 0 "  ...исполнено именно задание конвейера" grep -qx -- '--void-is-failure --job product-trunk-gates' "$tmp/argv"
rm -f "$tmp/argv"
expect 0 "близнец: нынешний ствол (A) — набор зелёный, код 0" bash "$SUT" "kacho=$A"
expect 0 "  ...и задание то же" grep -qx -- '--void-is-failure --job product-trunk-gates' "$tmp/argv"
# mutate <что> <образец sed> — мутант умолчания обязан покраснеть.
mutate() {
    rm -f "$tmp/argv"; sed "$2" "$SUT" > "$tmp/mut6.sh"
    expect '!0' "образец мутанта «$1» найден в скрипте" cmp -s "$SUT" "$tmp/mut6.sh"
    bash "$tmp/mut6.sh" "kacho=$B" > "$tmp/o" 2>&1
    local rc=$?
    [ "$rc" -eq 1 ] && grep -qx -- '--void-is-failure --job product-trunk-gates' "$tmp/argv" 2>/dev/null
    ok "$(( $? == 0 ))" "мутант «$1» — проба краснеет (код $rc)"
}
# shellcheck disable=SC2016  # образец sed: $WS — литерал скрипта, а не раскрытие здесь
mutate "команда по умолчанию true" 's/|| cmd=(bash "$WS\/scripts\/lib\/run-suites.sh".*/|| cmd=(true)/'
mutate "другое задание" 's/--job product-trunk-gates)$/--job tooling-gate)/'

echo "== T7: чужое имя продукта при живом клоне — код 2"
mk "$tmp/other"
KACHO_HOME_OTHER="$tmp/other" expect 2 "other= при живом клоне — отказ" bash "$SUT" "other=$(git -C "$tmp/other" rev-parse pr)" -- true
cp "$tmp/o" "$tmp/o.t7"
expect 0 "  ...причина — перечень продуктов" grep -q 'не из kacho, kaname, corelib' "$tmp/o.t7"
sed '/kacho|kaname|corelib) ;;/d' "$SUT" > "$tmp/mut7.sh"
expect '!0' "образец мутанта перечня найден в скрипте" cmp -s "$SUT" "$tmp/mut7.sh"
KACHO_HOME_OTHER="$tmp/other" expect 0 "мутант без перечня принимает other — проба его видит" bash "$tmp/mut7.sh" "other=$(git -C "$tmp/other" rev-parse pr)" -- true

echo "[CENSUS] trunk-future-inject: утверждений $((pass + fail)) — сошлось $pass, разошлось $fail"
[ "$fail" -eq 0 ] && [ "$pass" -gt 0 ]
