#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# branches-clean.sh — влитая локальная ветка видна БЕЗ ЗАПУСКА КОМАНДЫ.
#
# # Предмет
#
# Висяк — это ССЫЛКА, а не коммит. Здесь вливают схлопыванием: squash-коммит не
# имеет родителя-ветки, поэтому исходный коммит не становится предком ствола
# НИКОГДА. Пока локальная ветка его держит, `git log --all --graph` рисует
# оборванную линию, неотличимую от брошенной работы, — и владелец, глядя на
# историю, видит куски разработки, повисшие в воздухе.
#
# `delete_branch_on_merge` включён в обоих репозиториях и снимает head-ветку PR
# НА ORIGIN — только её. Всё, что вливалось переносом, черри-пиком или через
# накопительную ветку, он не видит by construction; локальных копий — тем более.
# Замер 2026-08-16 на монорепо продукта: 37 локальных веток при 4 на origin, из
# них 20 влиты (сегодняшнее число даёт `scripts/branch-audit.sh`).
#
# Перепись, которая это чинит, существует и доказана инъекцией — и НЕ ВЫЗЫВАЕТСЯ
# ничем: узнать, что мусор накопился, мог лишь тот, кто и так о ней помнил. Этот
# хук закрывает именно заметность, а не саму уборку.
#
# # Форма
#
# Исполняется на КАЖДОМ обращении к сессии (`UserPromptSubmit`) и МОЛЧИТ, пока
# влитых локальных веток нет. Молчание выбрано намеренно: строка, печатающаяся
# всегда, перестаёт читаться на третий день.
#
# Отсюда обязанность, которую молчание накладывает: хук ОБЯЗАН заговорить, когда
# ему нечего осмотреть. «Ноль находок» и «ноль прочитанного» дают один и тот же
# пустой вывод, поэтому второе называется отдельной строкой.
#
# # Почему признак ЗДЕСЬ дешевле, чем в переписи, и это сказано вслух
#
# Хук считает только ветки, чей HEAD — ПРЕДОК ствола (первый признак): это одна
# дешёвая операция на ветку, и ложных срабатываний у неё нет by construction.
# Схлопнутые и поглощённые пофайлово он НЕ видит — их находит `branch-audit.sh`
# пятым и шестым признаками, и он же их снимает. Поэтому число хука — НИЖНЯЯ
# ГРАНИЦА, и он это печатает: иначе «две влитых» читалось бы как «всего две».
#
# Сессию не роняет НИКОГДА (выход 0 при любом исходе): это указатель, а не гейт.
set -uo pipefail

ws="${CLAUDE_PROJECT_DIR:-}"
[ -n "$ws" ] || ws="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

findings=()
examined_repos=0
examined_branches=0
unreadable=()

check_repo() { # $1 = путь, $2 = как называть в выводе
  local path=$1 label=$2 trunk="origin/main" n=0 occupied=() b

  [ -d "$path/.git" ] || [ -f "$path/.git" ] || { unreadable+=("$label: не репозиторий"); return; }
  git -C "$path" rev-parse --verify --quiet "$trunk^{commit}" >/dev/null 2>&1 || {
    unreadable+=("$label: ствол $trunk не разрешается — осмотр беспредметен"); return; }

  examined_repos=$((examined_repos + 1))

  # Ветку, занятую рабочей копией, снимать нельзя, и звать о ней бессмысленно.
  while read -r br; do
    [ -n "$br" ] && occupied+=("$br")
  done < <(git -C "$path" worktree list --porcelain 2>/dev/null |
           awk '/^branch /{b=$2; sub("refs/heads/","",b); print b}')

  while read -r b; do
    [ -n "$b" ] || continue
    [ "$b" = "main" ] && continue
    examined_branches=$((examined_branches + 1))
    local skip=0 o
    for o in ${occupied[@]+"${occupied[@]}"}; do [ "$o" = "$b" ] && skip=1; done
    [ "$skip" = 1 ] && continue
    git -C "$path" merge-base --is-ancestor "$b" "$trunk" 2>/dev/null && n=$((n + 1))
  done < <(git -C "$path" branch --format='%(refname:short)' 2>/dev/null)

  [ "$n" -gt 0 ] && findings+=("$label: не менее $n локальных веток уже в стволе")
  return 0
}

check_repo "$ws" "воркспейс"
[ -d "$ws/project/kacho" ] && check_repo "$ws/project/kacho" "продукт"

if [ "${#findings[@]}" -ne 0 ]; then
  echo "🌿 ВЛИТЫЕ ЛОКАЛЬНЫЕ ВЕТКИ — они и рисуют «повисшие куски» в git log --all --graph"
  printf '   %s\n' "${findings[@]}"
  echo "   Это НИЖНЯЯ ГРАНИЦА: считаны только предки ствола. Схлопнутые и поглощённые"
  echo "   пофайлово находит перепись — она же их снимает:"
  echo "     ./scripts/branch-audit.sh [project/kacho]                 # посмотреть"
  echo "     ./scripts/branch-audit.sh --prune-merged [project/kacho]  # снять влитые"
  echo "   Перепись НИКОГДА не трогает работу в единственном экземпляре и занятые"
  echo "   рабочей копией ветки; её вердикт устаревает за минуты — гони перед снятием."
fi

if [ "$examined_repos" -eq 0 ]; then
  echo "🌿 branches-clean: не осмотрено НИ ОДНОГО репозитория — молчание этого хука"
  echo "   означает «не проверяли», а не «чисто»."
  printf '   %s\n' ${unreadable[@]+"${unreadable[@]}"}
elif [ "${#unreadable[@]}" -ne 0 ]; then
  echo "🌿 branches-clean: осмотрено репозиториев $examined_repos, веток $examined_branches;"
  echo "   часть осмотреть не удалось — вердикт по ним НЕ вынесен:"
  printf '   %s\n' "${unreadable[@]}"
fi

exit 0
