#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# branch-audit-inject.sh — доказательство того, что перепись веток СПОСОБНА
# упасть и способна смолчать. Инъекция в обе стороны на синтетическом
# репозитории, который скрипт создаёт сам и сносит за собой.
#
# ЗАЧЕМ. Перепись, которая не падала ни разу, неотличима от переписи, которая
# падать не умеет. Проверка «ноль находок» имеет смысл, только если рядом
# показано, что на настоящей находке она краснеет И называет имя.
#
# Проверяется одиннадцать утверждений (A, A2, B, C, D, E, F, G, H, I, J):
#   A. ветка-работа без origin и с непустой дельтой → код 1 + её имя в выводе;
#   B. влитая ветка → код 0, её имени в списке «единственный экземпляр» нет;
#   C. ПЯТЫЙ ПРИЗНАК: ветка не предок ствола, нет на origin, но содержимое
#      уже в стволе (внесено схлопыванием) → код 0, НЕ находка;
#   D. ветка, занятая рабочей копией, помечена как занятая;
#   E. резервная ссылка refs/original/** названа отдельно;
#   H. ветка на origin с работой → «живая», не находка;
#   I. ветка на origin, поглощённая стволом → «без предмета», найдена дельтой;
#   J. origin действительно опрошен (объём осмотренного не нулевой).
#
# Использование: scripts/branch-audit-inject.sh [путь-к-branch-audit.sh]

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
AUDIT="${1:-$HERE/branch-audit.sh}"
[ -x "$AUDIT" ] || { echo "inject: не найден исполняемый $AUDIT" >&2; exit 2; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Синтетический «origin» + рабочая копия. Личность задаётся ЛОКАЛЬНО, только
# для этого одноразового репозитория, — настройки машины не трогаются.
git init -q --bare "$TMP/origin.git"
git init -q -b main "$TMP/work"
cd "$TMP/work"
git config user.email inject@example.invalid
git config user.name  inject
git config commit.gpgsign false
git remote add origin "$TMP/origin.git"

echo "ствол" > trunk.txt
git add trunk.txt && git commit -qm "исходный ствол"
git push -qu origin main

# --- A. работа в единственном экземпляре: нет на origin, дельта не пуста ------
git checkout -qb work-only-local
echo "правка, существующая в одном экземпляре" > only-local.txt
git add only-local.txt && git commit -qm "работа, которой нет нигде больше"

# --- B. влитая ветка: предок ствола -------------------------------------------
git checkout -q main
git checkout -qb work-merged
echo "влитое" > merged.txt
git add merged.txt && git commit -qm "работа, которая уедет в ствол"
git checkout -q main
git merge -q --no-ff -m "влить work-merged" work-merged
git push -q origin main

# --- C. пятый признак: содержимое в стволе, но ветка НЕ предок -----------------
# Схлопывание: тот же результат внесён другим коммитом, поэтому ни
# --is-ancestor, ни статус PR ветку влитой не считают, а дельта слияния пуста.
git checkout -q main
git checkout -qb work-squashed
echo "внесено схлопыванием" > squashed.txt
git add squashed.txt && git commit -qm "работа, которую внесут схлопыванием"
git checkout -q main
git merge -q --squash work-squashed
git commit -qm "схлопнуто из work-squashed"
git push -q origin main

# --- D. ветка, занятая рабочей копией -----------------------------------------
git branch occupied-branch main
git worktree add -q "$TMP/wt-occupied" occupied-branch

# --- H. ветка НА ORIGIN, несущая работу → «живая», не находка -------------------
git checkout -q main
git checkout -qb pushed-alive
echo "работа, сданная на origin" > pushed.txt
git add pushed.txt && git commit -qm "работа, лежащая и на origin"
git push -qu origin pushed-alive
git checkout -q main

# --- I. ветка НА ORIGIN, чьё содержимое уже в стволе → «без предмета» ----------
git checkout -qb pushed-absorbed
echo "поглощённое" > absorbed.txt
git add absorbed.txt && git commit -qm "работа, которую поглотит ствол"
git push -qu origin pushed-absorbed
git checkout -q main
git merge -q --squash pushed-absorbed
git commit -qm "схлопнуто из pushed-absorbed"
git push -q origin main

# --- E. резервная ссылка -------------------------------------------------------
git update-ref refs/original/refs/heads/main "$(git rev-parse main)"

git fetch -q origin

echo "=== прогон переписи на синтетическом репозитории ==="
set +e
OUT=$("$AUDIT" "$TMP/work" 2>&1); RC=$?
set -e
echo "$OUT"
echo "=== код возврата: $RC ==="
echo

fail=0
say() { printf '%s %s\n' "$1" "$2"; }

# A — обязана краснеть И назвать имя
if [ "$RC" -eq 1 ] && grep -q 'work-only-local' <<<"$OUT"; then
  say "✅ A" "работа в единственном экземпляре: код 1 и имя названо"
else
  say "❌ A" "ожидался код 1 с именем work-only-local, получен код $RC"; fail=1
fi

# Имя должно стоять именно в третьем списке, а не «где-то в выводе»
if awk '/ТОЛЬКО ЛОКАЛЬНО/,/^── ЖИВЫЕ/' <<<"$OUT" | grep -q 'work-only-local'; then
  say "✅ A2" "имя стоит в списке «единственный экземпляр», а не случайно в выводе"
else
  say "❌ A2" "work-only-local не попал в третий список"; fail=1
fi

# B — влитая не должна попадать в находки
if awk '/ТОЛЬКО ЛОКАЛЬНО/,/^── ЖИВЫЕ/' <<<"$OUT" | grep -q 'work-merged'; then
  say "❌ B" "влитая ветка ошибочно объявлена единственным экземпляром"; fail=1
else
  say "✅ B" "влитая ветка молчит — ложного срабатывания нет"
fi

# C — пятый признак: содержимое в стволе, ветка не предок
if awk '/ТОЛЬКО ЛОКАЛЬНО/,/^── ЖИВЫЕ/' <<<"$OUT" | grep -q 'work-squashed'; then
  say "❌ C" "схлопнутая ветка объявлена работой — пятый признак не сработал"; fail=1
elif grep -q 'work-squashed.*ДЕЛЬТА СЛИЯНИЯ ПУСТА' <<<"$OUT"; then
  say "✅ C" "пятый признак распознал схлопнутое вливание, которого не видят первые четыре"
else
  say "❌ C" "work-squashed не отнесён к влитым по дельте"; fail=1
fi

# D — занятость рабочей копией названа
if grep -q 'occupied-branch.*ЗАНЯТА рабочей копией' <<<"$OUT"; then
  say "✅ D" "ветка под чужой рабочей копией помечена"
else
  say "❌ D" "занятость рабочей копией не названа"; fail=1
fi

# E — резервная ссылка названа
if grep -q 'refs/original/refs/heads/main' <<<"$OUT"; then
  say "✅ E" "резервная ссылка названа отдельно"
else
  say "❌ E" "резервная ссылка не найдена в выводе"; fail=1
fi

# H — ветка на origin с работой: живая, но НЕ находка
if awk '/ЖИВЫЕ/,0' <<<"$OUT" | grep -q 'pushed-alive'; then
  say "✅ H" "ветка на origin с работой отнесена к живым"
else
  say "❌ H" "pushed-alive не попала в список живых"; fail=1
fi

# I — ветка на origin, поглощённая стволом: без предмета, найдена ПО ДЕЛЬТЕ
if awk '/НА ORIGIN без предмета/,/^── ТОЛЬКО ЛОКАЛЬНО/' <<<"$OUT" |
     grep -q 'pushed-absorbed.*ДЕЛЬТА СЛИЯНИЯ ПУСТА'; then
  say "✅ I" "поглощённая ветка origin найдена пятым признаком"
else
  say "❌ I" "pushed-absorbed не отнесена к «без предмета» по дельте"; fail=1
fi

# Контроль объёма: origin обязан быть ОПРОШЕН, а не пропущен
if grep -qE 'на origin [1-9]' <<<"$OUT"; then
  say "✅ J" "origin опрошен — ветки на нём осмотрены, а не пропущены"
else
  say "❌ J" "origin не опрошен: списки про origin беспредметны"; fail=1
fi

# Контроль объёма: «ноль находок» обязано быть отличимо от «ноль прочитанного»
if grep -q 'осмотрено локальных' <<<"$OUT" && grep -q 'дельта слияния посчитана' <<<"$OUT"; then
  say "✅ F" "объём осмотренного напечатан"
else
  say "❌ F" "переписи объёма нет — «ноль находок» неотличимо от «ноль прочитанного»"; fail=1
fi

# --- контроль в другую сторону: репозиторий БЕЗ находок -----------------------
git -C "$TMP/work" worktree remove --force "$TMP/wt-occupied"
git -C "$TMP/work" branch -D work-only-local >/dev/null
set +e
OUT2=$("$AUDIT" "$TMP/work" 2>&1); RC2=$?
set -e
if [ "$RC2" -eq 0 ]; then
  say "✅ G" "чистый репозиторий: код 0 — идеал не превращён в поломку"
else
  say "❌ G" "на репозитории без находок ожидался код 0, получен $RC2"
  echo "$OUT2"; fail=1
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "branch-audit-inject: 11 утверждений, все выполнены — перепись способна упасть И смолчать"
else
  echo "branch-audit-inject: есть невыполненные утверждения" >&2
fi
exit "$fail"
