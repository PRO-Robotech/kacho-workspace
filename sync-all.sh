#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/project"

# kacho-workspace — сам корень, синкаем отдельно первым.
if [ -d "$SCRIPT_DIR/.git" ]; then
  cd "$SCRIPT_DIR"
  before="$(git rev-parse HEAD 2>/dev/null)"
  if git fetch --quiet && git pull --ff-only --quiet 2>/dev/null; then
    after="$(git rev-parse HEAD)"
    if [ "$before" = "$after" ]; then
      echo "[kacho-workspace] up-to-date"
    else
      echo "[kacho-workspace] updated to $after"
    fi
  else
    echo "[kacho-workspace] skipped: fetch/pull failed"
  fi
fi

# Перечень выводится из дерева. Здесь стоял третий рукописный список тех же имён — и он
# уже разошёлся с двумя другими: в нём не хватало kacho-geo, то есть репозиторий, который
# bootstrap.sh клонировал, sync-all.sh молча не обновлял. Один механизм, три копии списка,
# расхождение никем не замечено — поэтому источник теперь один (repos.sh) и он же дерево.
# shellcheck source=repos.sh
. "$SCRIPT_DIR/repos.sh"

pulled=0
while IFS=$'\t' read -r repo identity; do
  [ -n "$repo" ] || continue
  pulled=$((pulled + 1))
  cd "$repo" || continue
  before="$(git rev-parse HEAD 2>/dev/null)"
  git fetch --quiet || { echo "[$identity] fetch failed"; continue; }
  if git pull --ff-only --quiet 2>/dev/null; then
    after="$(git rev-parse HEAD)"
    if [ "$before" = "$after" ]; then
      echo "[$identity] up-to-date"
    else
      echo "[$identity] updated to $after"
    fi
  else
    echo "[$identity] skipped: not fast-forward"
  fi
done < <(kacho_discover_worktrees "$PROJECT_DIR")

# Ноль целей — отсутствие предмета, а не «всё актуально». Различать обязательно: именно
# неразличение этих двух исходов держало модель распространения невыполненной.
if [ "$pulled" -eq 0 ]; then
  {
    echo "ОТКАЗ: в $PROJECT_DIR нет ни одной рабочей копии репозитория продукта — обновлять нечего."
    echo "       Осмотрено каталогов: $(ls -1d "$PROJECT_DIR"/*/ 2>/dev/null | wc -l | tr -d ' '). См. repos.sh."
  } >&2
  exit 1
fi
echo "обновлено рабочих копий: $pulled"

# Раскатки оснастки здесь больше нет (решение владельца 2026-08-02): оснастка берётся
# ТОЛЬКО из воркспейса, копий в рабочих копиях продукта не заводится. Этот скрипт теперь
# делает ровно одно — обновляет рабочие копии, — и его название это отражает.
