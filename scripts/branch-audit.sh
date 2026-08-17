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
# ШЕСТЬ ПРИЗНАКОВ ВЛИВАНИЯ, и последние два строже первых четырёх вместе.
#
#   (1) `merge-base --is-ancestor` — ноль коммитов сверх ствола;
#   (2) статус PR по head-ветке;
#   (3) присутствие на origin — спрашивается У ORIGIN (`git ls-remote`), НИКОГДА
#       через `refs/remotes/*`: локальные копии ссылок отстают, и ответ по ним
#       бывает неверен в обе стороны;
#   (4) возраст последнего коммита — в ЕДИНОМ времени (эпоха, `%ct`);
#   (5) ДЕЛЬТА СЛИЯНИЯ: слить ветку в ствол во временной копии и посмотреть, что
#       изменилось. Пусто ⇒ содержимое уже в стволе;
#   (6) ПОГЛОЩЕНИЕ ПОФАЙЛОВО — объединение двух проверок, которые врут в РАЗНЫЕ
#       стороны, поэтому применяются вместе:
#         (6а) обратное применение патча файла во временный индекс ствола
#              (`git apply --cached -R --check`) — доказывает поглощение;
#              ЛОЖНО ОТРИЦАЕТ, когда ствол правил тот же файл ПОСЛЕ вливания;
#         (6б) блоб ветки встречался в истории ствола по этому пути
#              (`git log <ствол> --find-object=<blob> -- <путь>`) — доказывает,
#              что содержимое через ствол проходило; МОЛЧИТ, когда в PR были
#              правки по ревью и блоб ветки в ствол не попал дословно.
#       Файл считается непоглощённым, только если ОБЕ сказали «нет».
#
# Пятый и шестой не зависят от СПОСОБА вливания — слияние, схлопывание, перенос,
# черри-пик, — тогда как первые четыре зависят все.
#
# ЗАЧЕМ ШЕСТОЙ, если есть пятый. Пятый асимметричен: пустая дельта ДОКАЗЫВАЕТ
# поглощение, а конфликт не доказывает ничего — он одинаково означает и «ветка
# несёт своё», и «ствол правил тот же файл дальше». Замер 2026-08-16 на
# монорепо продукта (`origin/main@cd7bcc5c`): пятый признак назвал расщеплёнными
# 12 веток, шестой оставил 7 — пять находок были отставанием, а не работой.
# Инструмент, у которого 42 % находок ложные, перестают читать; перестав читать,
# возвращаются к `git branch --merged`, а он на схлопнутом вливании даёт НОЛЬ
# при 63 ветках, из которых 13 влиты. Предикат перепроверки — прогон этого
# скрипта: доли выводятся из его же разделов, а не из этого комментария.
#
# СТВОЛОВ БОЛЬШЕ ОДНОГО. Работа копится в накопительных ветках (`git-issues.md`
# §«Накопительная релизная ветка»), поэтому «нет в origin/main» и «нет нигде» —
# РАЗНЫЕ вердикты. Скрипт сверяет с origin/main И с каждой origin/release/*;
# ветка, поглощённая накопительной веткой, помечается источником поглощения, а
# не объявляется единственным экземпляром. В том же замере это сняло две ложные
# находки из пяти (`issue-489`, `issue-mutation-outcome-signal`).
#
# ЧЕГО ПРИЗНАКИ НЕ ДОКАЗЫВАЮТ ПООДИНОЧКЕ:
#
#   * `git branch --merged` — здесь вливают схлопыванием и через накопительную
#     ветку, поэтому HEAD ветки предком ствола не становится: `--merged
#     origin/main` дал НОЛЬ при 63 ветках, из которых 13 были влиты;
#   * сравнение содержимого — лжёт в обратную сторону: ствол уходит вперёд по тем
#     же файлам, и у заведомо влитой ветки насчитывается тысяча строк «различий»;
#   * статус PR — ветка может нести ДВЕ работы, а закрыть её могут по одной:
#     PR «поглощён», первая работа в стволе, вторая нет. Ловят это только (5)
#     и (6), причём (5) в одиночку даёт при этом ложные находки: конфликт от
#     ушедшего вперёд ствола он не отличает от второй работы.
#
# ВЕРДИКТ УСТАРЕВАЕТ. Он верен в момент замера и не позже: ветка, измеренная как
# единственный экземпляр, через 35 минут оказывалась влитой, а локальная ветка
# переезжала сама, потому что на ней работала живая сессия. Поэтому скрипт
# печатает время замера и метит ветки, двигавшиеся только что.
#
# Использование:
#   scripts/branch-audit.sh [путь-к-репозиторию]                  # перепись
#   scripts/branch-audit.sh --prune-merged [путь-к-репозиторию]   # + снять влитые
#
# Переменные: BRANCH_AUDIT_TRUNK (ствол, умолчание origin/main),
#             BRANCH_AUDIT_FRESH_MIN (окно «движется прямо сейчас», умолчание 45),
#             BRANCH_AUDIT_NO_ACCUM=1 (не искать накопительные ветки — для проб).
#
# БЕЗ `--prune-merged` скрипт НИЧЕГО НЕ УДАЛЯЕТ: он печатает списки и объём
# осмотренного, решение принимает человек — третий вид требует сдать работу, а
# не снять ветку.
#
# С `--prune-merged` снимаются ТОЛЬКО локальные ветки раздела «ВЛИТЫ», и по
# каждой печатается, снята она или оставлена и почему. Не снимаются никогда:
# занятые рабочей копией · двигавшиеся в окне FRESH_MIN · ветка ствола · текущая
# ветка HEAD · всё, что не попало в раздел «ВЛИТЫ». Причина ограничений — не
# осторожность, а замеренный класс: вердикт устаревает за минуты, а `git branch
# -D` необратим.
#
# ПОЧЕМУ СНЯТИЕ ЛОКАЛЬНОЙ ВЕТКИ ВООБЩЕ ЕСТЬ ПРЕДМЕТ. Висяк — это ССЫЛКА, а не
# коммит: при схлопывании исходный коммит не становится предком ствола НИКОГДА,
# и пока локальная ветка его держит, `git log --all --graph` рисует оборванную
# линию, неотличимую от брошенной работы. `delete_branch_on_merge` снимает
# head-ветку PR на origin — и только её; локальных копий он не видит by
# construction. Замер 2026-08-16 на монорепо продукта: 37 локальных веток при 4
# на origin, из них 20 влиты.
#
# Код возврата: 0 — работы в единственном экземпляре нет; 1 — найдена (находка,
# требующая действия); 2 — перепись беспредметна (нет ствола, нет веток).

set -euo pipefail

PRUNE=0
if [ "${1:-}" = "--prune-merged" ]; then PRUNE=1; shift; fi

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

# --- СТВОЛЫ: ствол плюс каждая накопительная ветка ----------------------------
# Работа копится в release/*, поэтому «нет в origin/main» и «нет нигде» — разные
# вердикты. Перечень ВЫВОДИТСЯ из ссылок, а не выписывается: рукописный список
# разошёлся бы с деревом молча, и новая накопительная ветка осталась бы вне
# сверки — невидимо, потому что отсутствие проверки не производит сигнала.
TRUNKS=("$TRUNK")
if [ "${BRANCH_AUDIT_NO_ACCUM:-0}" != "1" ]; then
  while read -r r; do
    [ -n "$r" ] && [ "$r" != "$TRUNK" ] && TRUNKS+=("$r")
  done < <(git for-each-ref --format='%(refname:short)' \
             'refs/remotes/origin/release/*' 'refs/remotes/origin/release/*/*' 2>/dev/null || true)
fi

# Временный индекс на КАЖДЫЙ ствол: обратное применение патча идёт в него, а не
# в индекс репозитория и не в рабочую копию. Это не стилистика — испорченный
# индекс заставляет проверки, читающие дерево, выдумывать красные вердикты
# (`multi-agent-flow.md` §НЕПРИКОСНОВЕННОСТЬ ЧУЖОГО СОСТОЯНИЯ).
declare -A TRUNK_IDX=()
BA_TMP=$(mktemp -d)
cleanup_tmp() { rm -rf "$BA_TMP"; }
trap cleanup_tmp EXIT
for tr in "${TRUNKS[@]}"; do
  idx="$BA_TMP/idx.$(printf '%s' "$tr" | tr '/' '_')"
  if GIT_INDEX_FILE="$idx" git read-tree "$tr" 2>/dev/null; then
    TRUNK_IDX["$tr"]="$idx"
  fi
done
PATCH_TMP="$BA_TMP/p.diff"

echo "branch-audit: репозиторий $(basename "$REPO"), ствол $TRUNK @ ${TRUNK_SHA:0:12}"
if [ "${#TRUNKS[@]}" -gt 1 ]; then
  echo "branch-audit: накопительных веток в сверке: $(( ${#TRUNKS[@]} - 1 )) — ${TRUNKS[*]:1}"
else
  echo "branch-audit: накопительных веток нет — сверка только со стволом"
fi
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

# --- ШЕСТОЙ ПРИЗНАК -----------------------------------------------------------
# Печатает пути, содержимое которых не найдено НИ В ОДНОМ стволе. Пустой вывод ⇒
# ветка поглощена (снимать безопасно). Непустой ⇒ отсутствие доказательства
# поглощения — НЕ доказательство потери: судит человек по именам.
#
# Асимметрия названа намеренно. Никакой из двух проверок по отдельности верить
# нельзя: (а) ложно отрицает на файле, который ствол правил после вливания;
# (б) молчит, когда PR правился по ревью. Вместе они закрывают обе дыры, и
# именно поэтому объединяются, а не выбираются.
#
# ИМЕНА ПЕЧАТАЮТСЯ, СПИСОК НЕ ФИЛЬТРУЕТСЯ. Перечень «снимать нельзя» без состава
# — стена из имён, и человек, которому нечем отличить сданную работу от
# сгенерированной строки указателя, перестаёт его читать. Замер 2026-08-16 на
# воркспейсе: из 24 веток с непустой дельтой у 14 она состояла ТОЛЬКО из
# машинно-собираемого obsidian/kacho/INDEX.md, то есть авторской работы в них не
# было вовсе. Подавлять «заведомо генерируемые» пути нельзя: это маска, которая
# однажды скроет настоящую работу. Судит человек — по именам.
unabsorbed_files() { # $1 = ref → печатает пути (по одному в строке)
  local ref=$1 base f bb tr found

  for tr in "${TRUNKS[@]}"; do
    [ -n "${TRUNK_IDX[$tr]+x}" ] || continue
    base=$(git merge-base "$tr" "$ref" 2>/dev/null) || continue
    # Дешёвая проверка целиком: кумулятивный патч ложится обратно ⇒ поглощено
    # всё сразу, пофайлово ходить незачем.
    if git diff "$base" "$ref" > "$PATCH_TMP" 2>/dev/null; then
      [ -s "$PATCH_TMP" ] || return 0
      if GIT_INDEX_FILE="${TRUNK_IDX[$tr]}" git apply --cached -R --check "$PATCH_TMP" 2>/dev/null; then
        return 0
      fi
    fi
  done

  base=$(git merge-base "$TRUNK" "$ref" 2>/dev/null) || return 0
  while read -r f; do
    [ -n "$f" ] || continue
    git diff "$base" "$ref" -- "$f" > "$PATCH_TMP" 2>/dev/null || continue
    [ -s "$PATCH_TMP" ] || continue
    bb=$(git rev-parse "$ref:$f" 2>/dev/null || true)
    found=0
    for tr in "${TRUNKS[@]}"; do
      [ -n "${TRUNK_IDX[$tr]+x}" ] || continue
      if GIT_INDEX_FILE="${TRUNK_IDX[$tr]}" git apply --cached -R --check "$PATCH_TMP" 2>/dev/null; then
        found=1; break
      fi
      if [ -n "$bb" ] &&
         [ -n "$(git log "$tr" --format=%H --find-object="$bb" -- "$f" 2>/dev/null | head -1)" ]; then
        found=1; break
      fi
    done
    [ "$found" = 0 ] && printf '%s\n' "$f"
  done < <(git diff --name-only "$base" "$ref" 2>/dev/null)
  return 0
}

absorbed_where() { # $1 = ref → печатает имя ствола, поглотившего ветку, либо пусто
  local ref=$1 tr out
  for tr in "${TRUNKS[@]}"; do
    out=$(git merge-tree --write-tree "$tr" "$ref" 2>/dev/null) || continue
    if [ "$(printf '%s\n' "$out" | head -1)" = "$(git rev-parse "$tr^{tree}")" ]; then
      printf '%s' "$tr"; return 0
    fi
  done
  return 0
}

fresh_mark() { # $1 = ref → метка, если ветка двигалась только что
  local ref=$1 ct age_min
  ct=$(git log -1 --format=%ct "$ref" 2>/dev/null || echo 0)
  age_min=$(( (NOW - ct) / 60 ))
  if [ "$ct" -gt 0 ] && [ "$age_min" -lt "$FRESH_MIN" ]; then
    printf ' [ДВИЖЕТСЯ: коммит %s мин назад]' "$age_min"
  fi
}

merged_local=(); orphan_remote=(); only_local=(); alive=(); split_work=(); prunable=()
examined_local=0; examined_remote=0; delta_checked=0
sixth_checked=0; sixth_rescued=0

# --- локальные ветки ----------------------------------------------------------
while read -r b; do
  [ "$b" = "${TRUNK#origin/}" ] && continue
  examined_local=$((examined_local + 1))

  on_origin=0
  [ -n "${ON_ORIGIN[$b]+x}" ] && on_origin=1

  ancestor=0
  git merge-base --is-ancestor "$b" "$TRUNK" 2>/dev/null && ancestor=1
  ahead=$(git rev-list --count "$TRUNK".."$b" 2>/dev/null || echo 0)

  empty=1; how=""; unabs=""
  delta_checked=$((delta_checked + 1))
  if [ "$ancestor" = 1 ]; then
    how="предок ствола"
  else
    src=$(absorbed_where "$b")
    if [ -n "$src" ]; then
      how="ДЕЛЬТА СЛИЯНИЯ ПУСТА относительно $src"
    else
      # Пятый признак сказал «конфликт» — а это не вердикт. Спрашиваем шестой.
      sixth_checked=$((sixth_checked + 1))
      unabs=$(unabsorbed_files "$b")
      if [ -z "$unabs" ]; then
        how="ПОГЛОЩЕНА ПОФАЙЛОВО (шестой признак; пятый дал конфликт)"
        sixth_rescued=$((sixth_rescued + 1))
      else
        empty=0
      fi
    fi
  fi

  occ=""; [ -n "${OCCUPIED[$b]+x}" ] && occ=" [ЗАНЯТА рабочей копией: ${OCCUPIED[$b]}]"
  pr=""; [ -n "${PRSTATE[$b]+x}" ] && pr=" ${PRSTATE[$b]}"
  fresh=$(fresh_mark "$b")

  if [ "$empty" = 1 ]; then
    if [ "$ancestor" = 1 ] && [ "$ahead" = 0 ]; then
      merged_local+=("$b — $how${pr}${occ}${fresh}")
    else
      merged_local+=("$b — +$ahead коммит(ов), но $how${pr}${occ}${fresh}")
    fi
    prunable+=("$b")
  elif [ "$on_origin" = 0 ]; then
    ucnt=$(printf '%s\n' "$unabs" | grep -c . || true)
    ulist=$(printf '%s\n' "$unabs" | head -3 | tr '\n' ' ')
    [ "$ucnt" -gt 3 ] && ulist="$ulist…"
    only_local+=("$b (+$ahead коммит(ов), НЕТ на origin) — не поглощено ни одним стволом: $ucnt файл(ов): $ulist${pr}${occ}${fresh}")
  else
    alive+=("$b (+$ahead)${pr}${occ}${fresh}")
  fi

  # Класс «одна ветка — две работы»: PR закрыт/влит, а содержимое поглощено не всё.
  if [ "$empty" = 0 ] && [ -n "${PRSTATE[$b]+x}" ]; then
    case "${PRSTATE[$b]}" in
      *MERGED*|*CLOSED*)
        ucnt=$(printf '%s\n' "$unabs" | grep -c . || true)
        split_work+=("$b — ${PRSTATE[$b]}, но не поглощено $ucnt файл(ов): $(printf '%s\n' "$unabs" | head -3 | tr '\n' ' ')") ;;
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
     "стволов в сверке ${#TRUNKS[@]}, дельта слияния посчитана ${delta_checked} раз," \
     "шестой признак спрошен ${sixth_checked} раз и снял ${sixth_rescued} ложных находок;" \
     "влитых ${#merged_local[@]}, без предмета на origin ${#orphan_remote[@]}," \
     "в единственном экземпляре ${#only_local[@]}, живых ${#alive[@]}," \
     "с расщеплённой работой ${#split_work[@]}, резервных ссылок ${#backup_refs[@]}"

# «Шестой признак спрошен 0 раз» — не успех: это значит, что пятый ни разу не дал
# конфликта, то есть проверять было нечего. Разные исходы для «проверено, находок
# ноль» и «проверять нечего» — требование `testing.md` §Гейт на класс.
if [ "$sixth_checked" -eq 0 ] && [ "${#only_local[@]}" -ne 0 ]; then
  echo "branch-audit: шестой признак не спрашивался ни разу при непустом разделе" >&2
  echo "              «единственный экземпляр» — это расхождение, а не чистота." >&2
fi

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

# --- СНЯТИЕ ВЛИТЫХ ЛОКАЛЬНЫХ ССЫЛОК ------------------------------------------
# Только раздел «ВЛИТЫ» и только локальные ссылки. Каждая пропущенная ветка
# называется вместе с причиной: молчаливый пропуск неотличим от «снято».
if [ "$PRUNE" = 1 ]; then
  echo
  echo "── СНЯТИЕ влитых локальных ссылок (--prune-merged)"
  head_branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)
  pruned=0; kept=0
  for b in ${prunable[@]+"${prunable[@]}"}; do
    if [ -n "${OCCUPIED[$b]+x}" ]; then
      echo "   оставлена $b — занята рабочей копией ${OCCUPIED[$b]}"; kept=$((kept+1)); continue
    fi
    if [ "$b" = "$head_branch" ]; then
      echo "   оставлена $b — это текущая ветка HEAD"; kept=$((kept+1)); continue
    fi
    ct=$(git log -1 --format=%ct "$b" 2>/dev/null || echo 0)
    if [ "$ct" -gt 0 ] && [ $(( (NOW - ct) / 60 )) -lt "$FRESH_MIN" ]; then
      echo "   оставлена $b — двигалась $(( (NOW - ct) / 60 )) мин назад (соседняя сессия может писать в неё)"
      kept=$((kept+1)); continue
    fi
    if git branch -D "$b" >/dev/null 2>&1; then
      echo "   СНЯТА $b"; pruned=$((pruned+1))
    else
      echo "   НЕ снята $b — git отказал"; kept=$((kept+1))
    fi
  done
  echo "branch-audit: снято ${pruned}, оставлено ${kept} из ${#prunable[@]} влитых;" \
       "разделы «единственный экземпляр» и «живые» не трогались by construction"
fi

# Работа в единственном экземпляре — находка, а не сводка: она требует действия
# (сдать в PR), и молчаливый успех здесь означал бы «всё в порядке» ровно там,
# где одна команда `git branch -D` уничтожает работу навсегда.
[ "${#only_local[@]}" -eq 0 ] || exit 1
