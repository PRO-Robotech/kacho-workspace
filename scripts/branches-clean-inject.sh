#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# branches-clean-inject.sh — доказательство того, что хук заметности СПОСОБЕН
# заговорить и способен смолчать. Инъекция в обе стороны на синтетическом
# репозитории, который скрипт создаёт сам и сносит за собой.
#
# ЗАЧЕМ. Хук молчит, пока чисто, — значит его молчание неотличимо от молчания
# сломанного хука. Единственный способ различить их — показать, что на настоящей
# находке он говорит И называет число, а на чистом дереве не печатает НИЧЕГО.
#
# Проверяется шесть утверждений:
#   A. влитая локальная ветка → хук говорит и называет её репозиторий;
#   B. чистое дерево → stdout ПУСТ (не «почти пуст», а пуст);
#   C/C2. ветка, занятая рабочей копией, в счёт не идёт — звать о ней бессмысленно,
#      но пропуск назван ЧИСЛОМ и указан ключ, которым брошенную копию освободить;
#      снять её нельзя;
#   D. невлитая ветка молчания не нарушает (нет ложного срабатывания);
#   E. каталог без репозитория → хук ГОВОРИТ, что не осмотрел ничего: молчание
#      здесь означало бы «чисто» на непрочитанном дереве;
#   F. ствол не разрешается → тот же исход, что и E, и с названной причиной.
#
# Использование: scripts/branches-clean-inject.sh [путь-к-branches-clean.sh]

set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HOOK="${1:-$HERE/../.claude/hooks/branches-clean.sh}"
[ -f "$HOOK" ] || { echo "inject: не найден $HOOK" >&2; exit 2; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail=0
asserts=0
say() { asserts=$((asserts + 1)); printf '%s %s\n' "$1" "$2"; }

# Синтетический «origin» + рабочая копия. Личность задаётся ЛОКАЛЬНО, только для
# этого одноразового репозитория, — настройки машины не трогаются.
mk_repo() { # $1 = каталог
  git init -q --bare "$1/origin.git"
  git init -q -b main "$1/ws"
  git -C "$1/ws" config user.email inject@example.invalid
  git -C "$1/ws" config user.name  inject
  git -C "$1/ws" config commit.gpgsign false
  git -C "$1/ws" remote add origin "$1/origin.git"
  echo ствол > "$1/ws/trunk.txt"
  git -C "$1/ws" add trunk.txt
  git -C "$1/ws" commit -qm "исходный ствол"
  git -C "$1/ws" push -qu origin main
}

# --- A/C/D: находка есть -------------------------------------------------------
mk_repo "$TMP/a"
cd "$TMP/a/ws" || exit 2
git checkout -qb landed
echo влитое > landed.txt && git add landed.txt && git commit -qm "работа, которая уедет в ствол"
git checkout -q main && git merge -q --no-ff -m "влить landed" landed && git push -q origin main
git checkout -qb not-landed main
echo своё > mine.txt && git add mine.txt && git commit -qm "работа, которой в стволе нет"
git checkout -q main
git branch occupied main
git worktree add -q "$TMP/a/wt" occupied
git fetch -q origin

OUT_A=$(CLAUDE_PROJECT_DIR="$TMP/a/ws" bash "$HOOK" 2>&1)
if grep -q 'ВЛИТЫЕ ЛОКАЛЬНЫЕ ВЕТКИ' <<<"$OUT_A"; then
  say "✅ A" "на влитой локальной ветке хук заговорил"
else
  say "❌ A" "хук промолчал при влитой локальной ветке"; echo "$OUT_A"; fail=1
fi

# C — занятая рабочей копией в счёт не идёт: влитых должна насчитаться ОДНА
# (`landed`), а не две (`landed` + `occupied`, которая тоже предок ствола).
if grep -qE 'не менее 1 локальных веток' <<<"$OUT_A"; then
  say "✅ C" "занятая рабочей копией ветка исключена из счёта"
else
  say "❌ C" "счёт включил занятую ветку либо разошёлся: $(grep 'не менее' <<<"$OUT_A")"; fail=1
fi

# C2 — пропуск НАЗВАН ЧИСЛОМ и указано, чем такую ветку освободить. Исключение
# без числа делает целый вид влитых веток невидимым: их держат брошенные копии,
# и молчание о них неотличимо от их отсутствия.
if grep -q 'локальных веток держат рабочие копии' <<<"$OUT_A" &&
   grep -q 'release-abandoned-worktrees' <<<"$OUT_A"; then
  say "✅ C2" "пропущенные по занятости названы числом и указан способ их освободить"
else
  say "❌ C2" "занятые ветки исключены молча — «ноль находок» неотличимо от «не считали»"; fail=1
fi

# D — невлитая ветка ложного срабатывания не даёт: её имени в выводе нет.
if grep -q 'not-landed' <<<"$OUT_A"; then
  say "❌ D" "хук назвал невлитую ветку — ложное срабатывание"; fail=1
else
  say "✅ D" "невлитая ветка молчания не нарушила"
fi

# --- B: чистое дерево — stdout ПУСТ -------------------------------------------
git -C "$TMP/a/ws" worktree remove --force "$TMP/a/wt"
git -C "$TMP/a/ws" branch -D landed >/dev/null 2>&1
git -C "$TMP/a/ws" branch -D occupied >/dev/null 2>&1
git -C "$TMP/a/ws" branch -D not-landed >/dev/null 2>&1
OUT_B=$(CLAUDE_PROJECT_DIR="$TMP/a/ws" bash "$HOOK" 2>&1)
if [ -z "$OUT_B" ]; then
  say "✅ B" "на чистом дереве хук не печатает НИЧЕГО — заметность не превращена в шум"
else
  say "❌ B" "чистое дерево дало вывод: $OUT_B"; fail=1
fi

# --- E: каталог без репозитория — обязан ЗАГОВОРИТЬ ----------------------------
mkdir -p "$TMP/empty"
OUT_E=$(CLAUDE_PROJECT_DIR="$TMP/empty" bash "$HOOK" 2>&1)
if grep -q 'не осмотрено НИ ОДНОГО репозитория' <<<"$OUT_E"; then
  say "✅ E" "«ноль прочитанного» названо отдельно от «ноль находок»"
else
  say "❌ E" "на каталоге без репозитория хук промолчал — молчание читается как чистота"; fail=1
fi

# --- F: репозиторий есть, ствола нет ------------------------------------------
git init -q -b main "$TMP/nostem"
git -C "$TMP/nostem" config user.email inject@example.invalid
git -C "$TMP/nostem" config user.name inject
git -C "$TMP/nostem" config commit.gpgsign false
echo x > "$TMP/nostem/x.txt"
git -C "$TMP/nostem" add x.txt
git -C "$TMP/nostem" commit -qm "без origin/main"
OUT_F=$(CLAUDE_PROJECT_DIR="$TMP/nostem" bash "$HOOK" 2>&1)
if grep -q 'ствол origin/main не разрешается' <<<"$OUT_F"; then
  say "✅ F" "неразрешимый ствол назван причиной, а не проглочен"
else
  say "❌ F" "ствол не разрешается, а хук промолчал"; echo "$OUT_F"; fail=1
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "branches-clean-inject: ${asserts} утверждений, все выполнены — хук способен заговорить И смолчать"
else
  echo "branches-clean-inject: есть невыполненные утверждения" >&2
fi
exit "$fail"
