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
#   T5  неназванный продукт судится своим клоном (KACHO_HOME не переставлен).
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

echo "[CENSUS] trunk-future-inject: утверждений $((pass + fail)) — сошлось $pass, разошлось $fail"
[ "$fail" -eq 0 ] && [ "$pass" -gt 0 ]
