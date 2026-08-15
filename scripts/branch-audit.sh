#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# branch-audit.sh — перепись веток репозитория по ЖИВОСТИ, а не по имени.
#
# ПРЕДМЕТ. Ветки копятся тремя разными способами, и все три невидимы поодиночке:
#
#   1. ПЕРЕНОС. Работу переносят с отставшей ветки на свежую базу; PR-преемник
#      влит, `delete_branch_on_merge` снимает ЕГО ветку — а исходная остаётся
#      навсегда, потому что head-веткой ни одного PR она не была.
#   2. СНИМОК. Ветка вида `wip: снимок незакоммиченного состояния` заводится,
#      чтобы не потерять чужую грязную копию. Её предмет уезжает другим путём,
#      а снимок живёт вечно и выглядит как незаконченная работа.
#   3. ЕДИНСТВЕННЫЙ ЭКЗЕМПЛЯР. Локальная ветка, которой НЕТ на origin и которая
#      не влита. Её снятие уничтожает работу без следа — и именно она внешне
#      неотличима от мусора первых двух видов.
#
# Замер 2026-08-14, ради которого скрипт написан: в продукте 47 локальных веток,
# из них влитыми и снимаемыми оказались 34; на origin висело 8 брошенных, чья
# работа была влита восемью PR-преемниками (сверка: 214 файлов из 214 в стволе,
# два «отсутствующих» удалены своими же PR). В воркспейсе — 27 локальных, 17
# снимаемых, и ОДНА ветка третьего вида: 98-строчная записка, существовавшая в
# единственном экземпляре.
#
# ПОЧЕМУ НЕ `git branch --merged`. Здесь вливают схлопыванием и через
# накопительную ветку, поэтому HEAD ветки предком ствола не становится:
# `--merged origin/main` дал НОЛЬ при 63 ветках, из которых 13 были влиты.
# Сравнение содержимого лжёт в ОБЕ стороны: ствол уходит вперёд по тем же
# файлам, и у заведомо влитой ветки насчитывается тысяча строк «расхождений».
# Работают только два признака вместе — статус её PR и `merge-base --is-ancestor`.
#
# Использование:
#   scripts/branch-audit.sh [путь-к-репозиторию]   # перепись, ничего не меняет
#
# Скрипт НИЧЕГО НЕ УДАЛЯЕТ. Он печатает четыре списка и объём осмотренного;
# решение принимает человек, потому что третий вид требует сдать работу, а не
# снять ветку.

set -euo pipefail

REPO="${1:-$(pwd)}"
cd "$REPO" || { echo "branch-audit: каталог '$REPO' недоступен" >&2; exit 2; }

git rev-parse --git-dir >/dev/null 2>&1 || {
  echo "branch-audit: '$REPO' не репозиторий" >&2; exit 2; }

TRUNK="${BRANCH_AUDIT_TRUNK:-origin/main}"
git rev-parse --verify --quiet "$TRUNK^{commit}" >/dev/null || {
  echo "branch-audit: ствол '$TRUNK' не разрешается — перепись была бы беспредметна" >&2
  exit 2; }

echo "branch-audit: репозиторий $(basename "$REPO"), ствол $TRUNK"
echo

# --- какие ветки заняты рабочими копиями (снимать нельзя, не спросив) ---
declare -A OCCUPIED=()
while read -r br path; do
  [ -n "$br" ] && OCCUPIED["$br"]="$path"
done < <(git worktree list --porcelain 2>/dev/null |
         awk '/^worktree /{p=$2} /^branch /{b=$2; sub("refs/heads/","",b); print b" "p}')

# --- статус PR по head-ветке (если gh доступен и это GitHub-репозиторий) ---
declare -A PRSTATE=()
have_gh=0
if command -v gh >/dev/null 2>&1 && gh repo view >/dev/null 2>&1; then
  have_gh=1
  while IFS=$'\t' read -r head num state; do
    [ -n "$head" ] && PRSTATE["$head"]="#${num} ${state}"
  done < <(gh pr list --state all --limit 300 \
             --json number,state,headRefName \
             --jq '.[]|"\(.headRefName)\t\(.number)\t\(.state)"' 2>/dev/null || true)
fi

merged_local=(); orphan_remote=(); only_local=(); alive=()
examined_local=0; examined_remote=0

# --- локальные ветки ---
while read -r b; do
  [ "$b" = "${TRUNK#origin/}" ] && continue
  examined_local=$((examined_local + 1))
  on_origin=0
  git rev-parse --verify --quiet "origin/$b" >/dev/null && on_origin=1
  ancestor=0
  git merge-base --is-ancestor "$b" "$TRUNK" 2>/dev/null && ancestor=1
  ahead=$(git rev-list --count "$TRUNK".."$b" 2>/dev/null || echo 0)

  if [ "$ancestor" = 1 ] && [ "$ahead" = 0 ]; then
    merged_local+=("$b${OCCUPIED[$b]+ [занята: ${OCCUPIED[$b]:-}]}")
  elif [ "$on_origin" = 0 ]; then
    only_local+=("$b (+$ahead коммит(ов), НЕТ на origin)")
  else
    alive+=("$b (+$ahead)${PRSTATE[$b]+ ${PRSTATE[$b]}}")
  fi
done < <(git branch --format='%(refname:short)')

# --- ветки на origin, чья работа влита преемником ---
while read -r b; do
  [ "$b" = "${TRUNK#origin/}" ] && continue
  case "$b" in release/*) continue ;; esac
  examined_remote=$((examined_remote + 1))
  if git merge-base --is-ancestor "origin/$b" "$TRUNK" 2>/dev/null; then
    orphan_remote+=("$b — предок ствола, снимаемая")
    continue
  fi
  # PR нет вовсе, а ветка старше двух недель — кандидат в брошенные.
  if [ "$have_gh" = 1 ] && [ -z "${PRSTATE[$b]+x}" ]; then
    age_days=$(( ( $(date +%s) - $(git log -1 --format=%ct "origin/$b" 2>/dev/null || date +%s) ) / 86400 ))
    [ "$age_days" -gt 14 ] && orphan_remote+=("$b — PR не заводился, последний коммит ${age_days} дн. назад")
  fi
done < <(git ls-remote --heads origin 2>/dev/null | sed 's|.*refs/heads/||')

emit() {
  local title=$1; shift
  echo "── $title (${#@})"
  if [ "$#" -eq 0 ]; then echo "   —"; else printf '   %s\n' "$@"; fi
  echo
}

emit "ВЛИТЫ, снимаются локально" "${merged_local[@]+"${merged_local[@]}"}"
emit "НА ORIGIN без предмета — проверить PR-преемника перед снятием" "${orphan_remote[@]+"${orphan_remote[@]}"}"
emit "ТОЛЬКО ЛОКАЛЬНО и не влиты — РАБОТА В ЕДИНСТВЕННОМ ЭКЗЕМПЛЯРЕ, снимать НЕЛЬЗЯ" "${only_local[@]+"${only_local[@]}"}"
emit "ЖИВЫЕ — есть на origin, несут работу" "${alive[@]+"${alive[@]}"}"

echo "branch-audit: осмотрено локальных ${examined_local}, на origin ${examined_remote};" \
     "снимаемых локально ${#merged_local[@]}, без предмета на origin ${#orphan_remote[@]}," \
     "в единственном экземпляре ${#only_local[@]}, живых ${#alive[@]}"

if [ "$have_gh" = 0 ]; then
  echo "branch-audit: gh недоступен — статус PR НЕ прочитан, и это значит, что второй" >&2
  echo "              из двух признаков вливания отсутствует: перепись неполна." >&2
fi

if [ "$examined_local" -eq 0 ] && [ "$examined_remote" -eq 0 ]; then
  echo "branch-audit: не осмотрено ни одной ветки — вердикт беспредметен" >&2
  exit 2
fi

# Работа в единственном экземпляре — находка, а не сводка: она требует действия
# (сдать в PR), и молчаливый успех здесь означал бы «всё в порядке» ровно там,
# где одна команда `git branch -D` уничтожает работу навсегда.
[ "${#only_local[@]}" -eq 0 ] || exit 1
