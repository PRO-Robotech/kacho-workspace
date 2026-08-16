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
# ПЯТЬ ПРИЗНАКОВ ВЛИВАНИЯ, и пятый строже остальных четырёх вместе.
#
#   (1) `merge-base --is-ancestor` — ноль коммитов сверх ствола;
#   (2) статус PR по head-ветке;
#   (3) присутствие на origin — спрашивается У ORIGIN (`git ls-remote`), НИКОГДА
#       через `refs/remotes/*`: локальные копии ссылок отстают, и ответ по ним
#       бывает неверен в обе стороны;
#   (4) возраст последнего коммита — в ЕДИНОМ времени (эпоха, `%ct`);
#   (5) ДЕЛЬТА СЛИЯНИЯ: слить ветку в ствол во временной копии и посмотреть, что
#       изменилось. Пусто ⇒ содержимое уже в стволе.
#
# Пятый не зависит от СПОСОБА вливания — слияние, схлопывание, перенос,
# черри-пик, — тогда как первые четыре зависят все. Замер 2026-08-16 на этом
# репозитории: из семи веток, выглядевших невлитыми по всем прочим признакам
# (не предок ствола, нет на origin, +2…+9 коммитов), ДВЕ дали дельту ноль —
# `work-162` (+6) и `work-70` (+2). Без пятого признака их пришлось бы разбирать
# руками, а разбор одной такой ветки стоил полутора часов.
#
# ЧЕГО ПРИЗНАКИ НЕ ДОКАЗЫВАЮТ ПООДИНОЧКЕ:
#
#   * `git branch --merged` — здесь вливают схлопыванием и через накопительную
#     ветку, поэтому HEAD ветки предком ствола не становится: `--merged
#     origin/main` дал НОЛЬ при 63 ветках, из которых 13 были влиты;
#   * сравнение содержимого — лжёт в обратную сторону: ствол уходит вперёд по тем
#     же файлам, и у заведомо влитой ветки насчитывается тысяча строк «различий»;
#   * статус PR — ветка может нести ДВЕ работы, а закрыть её могут по одной:
#     PR «поглощён», первая работа в стволе, вторая нет. Ловит это только (5).
#
# ВЕРДИКТ УСТАРЕВАЕТ. Он верен в момент замера и не позже: ветка, измеренная как
# единственный экземпляр, через 35 минут оказывалась влитой, а локальная ветка
# переезжала сама, потому что на ней работала живая сессия. Поэтому скрипт
# печатает время замера и метит ветки, двигавшиеся только что.
#
# Использование:
#   scripts/branch-audit.sh [путь-к-репозиторию]   # перепись, ничего не меняет
#
# Переменные: BRANCH_AUDIT_TRUNK (ствол, умолчание origin/main),
#             BRANCH_AUDIT_FRESH_MIN (окно «движется прямо сейчас», умолчание 45).
#
# Скрипт НИЧЕГО НЕ УДАЛЯЕТ. Он печатает четыре списка и объём осмотренного;
# решение принимает человек, потому что третий вид требует сдать работу, а не
# снять ветку.
#
# Код возврата: 0 — работы в единственном экземпляре нет; 1 — найдена (находка,
# требующая действия); 2 — перепись беспредметна (нет ствола, нет веток).

set -euo pipefail

REPO="${1:-$(pwd)}"
cd "$REPO" || { echo "branch-audit: каталог '$REPO' недоступен" >&2; exit 2; }

git rev-parse --git-dir >/dev/null 2>&1 || {
  echo "branch-audit: '$REPO' не репозиторий" >&2; exit 2; }

TRUNK="${BRANCH_AUDIT_TRUNK:-origin/main}"
FRESH_MIN="${BRANCH_AUDIT_FRESH_MIN:-45}"

git rev-parse --verify --quiet "$TRUNK^{commit}" >/dev/null || {
  echo "branch-audit: ствол '$TRUNK' не разрешается — перепись была бы беспредметна" >&2
  exit 2; }

TRUNK_SHA=$(git rev-parse "$TRUNK")
TRUNK_TREE=$(git rev-parse "$TRUNK^{tree}")
NOW=$(date +%s)

echo "branch-audit: репозиторий $(basename "$REPO"), ствол $TRUNK @ ${TRUNK_SHA:0:12}"
echo "branch-audit: замер $(date -u +'%Y-%m-%dT%H:%M:%SZ') (UTC) — вердикт верен НА ЭТОТ МОМЕНТ"
echo

# --- какие ветки заняты рабочими копиями (снимать нельзя, не спросив) ---------
# `git worktree list` отвечает про ТОТ репозиторий, в котором выполнен, поэтому
# он выполняется после cd в целевой каталог, а не из текущего.
declare -A OCCUPIED=()
while read -r br path; do
  [ -n "$br" ] && OCCUPIED["$br"]="$path"
done < <(git worktree list --porcelain 2>/dev/null |
         awk '/^worktree /{p=$2} /^branch /{b=$2; sub("refs/heads/","",b); print b" "p}')

# --- что РЕАЛЬНО есть на origin: прямой запрос, не refs/remotes ---------------
declare -A ON_ORIGIN=()
remote_ok=0
if remote_out=$(git ls-remote --heads origin 2>/dev/null); then
  remote_ok=1
  while read -r _sha ref; do
    [ -n "${ref:-}" ] && ON_ORIGIN["${ref#refs/heads/}"]=1
  done <<<"$remote_out"
fi

# --- статус PR по head-ветке (если gh доступен и это GitHub-репозиторий) ------
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

# --- ПЯТЫЙ ПРИЗНАК: дельта слияния во временной копии -------------------------
# Сливает ветку в ствол БЕЗ рабочей копии и БЕЗ индекса (`merge-tree --write-tree`
# пишет только объекты) и сравнивает получившееся дерево с деревом ствола.
# Равны ⇒ ветка не добавляет стволу ничего ⇒ её содержимое уже там, каким бы
# способом оно туда ни попало.
# Конфликт (ненулевой код) означает, что ветка несёт изменения, которых в стволе
# нет, — то есть «не пусто», а не «неизвестно».
merge_delta_empty() { # $1 = ref → 0 если дельта пуста
  local ref=$1 out
  out=$(git merge-tree --write-tree "$TRUNK" "$ref" 2>/dev/null) || return 1
  [ "$(printf '%s\n' "$out" | head -1)" = "$TRUNK_TREE" ]
}

fresh_mark() { # $1 = ref → метка, если ветка двигалась только что
  local ref=$1 ct age_min
  ct=$(git log -1 --format=%ct "$ref" 2>/dev/null || echo 0)
  age_min=$(( (NOW - ct) / 60 ))
  if [ "$ct" -gt 0 ] && [ "$age_min" -lt "$FRESH_MIN" ]; then
    printf ' [ДВИЖЕТСЯ: коммит %s мин назад]' "$age_min"
  fi
}

merged_local=(); orphan_remote=(); only_local=(); alive=(); split_work=()
examined_local=0; examined_remote=0; delta_checked=0

# --- локальные ветки ----------------------------------------------------------
while read -r b; do
  [ "$b" = "${TRUNK#origin/}" ] && continue
  examined_local=$((examined_local + 1))

  on_origin=0
  [ -n "${ON_ORIGIN[$b]+x}" ] && on_origin=1

  ancestor=0
  git merge-base --is-ancestor "$b" "$TRUNK" 2>/dev/null && ancestor=1
  ahead=$(git rev-list --count "$TRUNK".."$b" 2>/dev/null || echo 0)

  empty=1
  if [ "$ancestor" = 1 ]; then
    delta_checked=$((delta_checked + 1))
  else
    delta_checked=$((delta_checked + 1))
    merge_delta_empty "$b" || empty=0
  fi

  occ=""; [ -n "${OCCUPIED[$b]+x}" ] && occ=" [ЗАНЯТА рабочей копией: ${OCCUPIED[$b]}]"
  pr=""; [ -n "${PRSTATE[$b]+x}" ] && pr=" ${PRSTATE[$b]}"
  fresh=$(fresh_mark "$b")

  if [ "$empty" = 1 ]; then
    if [ "$ancestor" = 1 ] && [ "$ahead" = 0 ]; then
      merged_local+=("$b — предок ствола${pr}${occ}${fresh}")
    else
      merged_local+=("$b — +$ahead коммит(ов), но ДЕЛЬТА СЛИЯНИЯ ПУСТА${pr}${occ}${fresh}")
    fi
  elif [ "$on_origin" = 0 ]; then
    only_local+=("$b (+$ahead коммит(ов), НЕТ на origin, дельта НЕ пуста)${pr}${occ}${fresh}")
  else
    alive+=("$b (+$ahead)${pr}${occ}${fresh}")
  fi

  # Класс «одна ветка — две работы»: PR закрыт/влит, а содержимое в стволе не всё.
  if [ "$empty" = 0 ] && [ -n "${PRSTATE[$b]+x}" ]; then
    case "${PRSTATE[$b]}" in
      *MERGED*|*CLOSED*)
        split_work+=("$b — ${PRSTATE[$b]}, но дельта слияния НЕ пуста: часть работы вне ствола") ;;
    esac
  fi
done < <(git branch --format='%(refname:short)')

# --- ветки на origin ----------------------------------------------------------
if [ "$remote_ok" = 1 ]; then
  for b in "${!ON_ORIGIN[@]}"; do
    [ "$b" = "${TRUNK#origin/}" ] && continue
    case "$b" in release/*) continue ;; esac
    examined_remote=$((examined_remote + 1))

    # Ветку origin читаем ПО ЕЁ SHA с origin, а не через возможно отставший
    # refs/remotes: если локальной копии ссылки нет, признак просто недоступен.
    rref="refs/remotes/origin/$b"
    git rev-parse --verify --quiet "$rref^{commit}" >/dev/null || {
      orphan_remote+=("$b — есть на origin, локальной копии ссылки нет: нужен git fetch")
      continue; }

    delta_checked=$((delta_checked + 1))
    if merge_delta_empty "$rref"; then
      orphan_remote+=("$b — ДЕЛЬТА СЛИЯНИЯ ПУСТА, содержимое в стволе${PRSTATE[$b]+ ${PRSTATE[$b]}}")
      continue
    fi

    if [ "$have_gh" = 1 ] && [ -z "${PRSTATE[$b]+x}" ]; then
      ct=$(git log -1 --format=%ct "$rref" 2>/dev/null || echo "$NOW")
      age_days=$(( (NOW - ct) / 86400 ))
      [ "$age_days" -gt 14 ] &&
        orphan_remote+=("$b — PR не заводился, последний коммит ${age_days} дн. назад, дельта НЕ пуста")
    fi
  done
fi

# --- резервные ссылки, которых обычное удаление не касается -------------------
backup_refs=()
while read -r r; do
  [ -n "$r" ] && backup_refs+=("$r")
done < <(git for-each-ref --format='%(refname)' 'refs/original/**' 2>/dev/null || true)

emit() {
  local title=$1; shift
  echo "── $title (${#@})"
  if [ "$#" -eq 0 ]; then echo "   —"; else printf '   %s\n' "$@"; fi
  echo
}

emit "ВЛИТЫ — содержимое в стволе, снимаются локально" "${merged_local[@]+"${merged_local[@]}"}"
emit "НА ORIGIN без предмета — проверить PR-преемника перед снятием" "${orphan_remote[@]+"${orphan_remote[@]}"}"
emit "ТОЛЬКО ЛОКАЛЬНО и дельта НЕ пуста — РАБОТА В ЕДИНСТВЕННОМ ЭКЗЕМПЛЯРЕ, снимать НЕЛЬЗЯ" \
     "${only_local[@]+"${only_local[@]}"}"
emit "ЖИВЫЕ — есть на origin, несут работу" "${alive[@]+"${alive[@]}"}"

if [ "${#split_work[@]}" -ne 0 ]; then
  emit "ВНИМАНИЕ: PR закрыт, а работа в стволе НЕ ВСЯ — ветка несла больше одного предмета" \
       "${split_work[@]}"
fi

if [ "${#backup_refs[@]}" -ne 0 ]; then
  emit "РЕЗЕРВНЫЕ ССЫЛКИ — обычное удаление веток их НЕ касается (git update-ref -d <ссылка>)" \
       "${backup_refs[@]}"
fi

echo "branch-audit: осмотрено локальных ${examined_local}, на origin ${examined_remote}," \
     "дельта слияния посчитана ${delta_checked} раз;" \
     "влитых ${#merged_local[@]}, без предмета на origin ${#orphan_remote[@]}," \
     "в единственном экземпляре ${#only_local[@]}, живых ${#alive[@]}," \
     "с расщеплённой работой ${#split_work[@]}, резервных ссылок ${#backup_refs[@]}"

if [ "$remote_ok" = 0 ]; then
  echo "branch-audit: origin не опрошен (git ls-remote не ответил) — признак «есть на origin»" >&2
  echo "              НЕ прочитан; всё локальное могло быть отнесено к единственным" >&2
  echo "              экземплярам ошибочно. Перепись неполна." >&2
fi

if [ "$have_gh" = 0 ]; then
  echo "branch-audit: gh недоступен — статус PR НЕ прочитан; из пяти признаков" >&2
  echo "              доступны четыре. Перепись неполна." >&2
fi

if [ "$examined_local" -eq 0 ] && [ "$examined_remote" -eq 0 ]; then
  echo "branch-audit: не осмотрено ни одной ветки — вердикт беспредметен" >&2
  exit 2
fi

echo "branch-audit: вердикт устаревает — ветка может быть влита или сдвинута соседней" \
     "сессией через минуты. Перед снятием прогони перепись заново."

# Работа в единственном экземпляре — находка, а не сводка: она требует действия
# (сдать в PR), и молчаливый успех здесь означал бы «всё в порядке» ровно там,
# где одна команда `git branch -D` уничтожает работу навсегда.
[ "${#only_local[@]}" -eq 0 ] || exit 1
