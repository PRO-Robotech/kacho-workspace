#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/project"
mkdir -p "$PROJECT_DIR"

REMOTE_BASE="${KACHO_REMOTE_BASE:-git@github.com:PRO-Robotech}"

# Здесь перечень остаётся объявленным, и это не оплошность: bootstrap работает ДО того, как
# что-либо склонировано, поэтому вывести его из дерева нечем — дерева ещё нет. Всё остальное
# (sync-all) работает уже ПО дереву и списка не держит.
#
# Что здесь было не так (замерено `gh repo view`, 2026-08-02):
#   • `kacho` — МОНОРЕПО, в котором ведётся разработка, — отсутствовал вовсе. То есть
#     bootstrap.sh не мог создать `project/kacho`: каталог, на который смотрит dev-стенд,
#     на который job `doc-commands` в CI делает checkout и в который раскатывается оснастка.
#     Свежий контрибьютор получал десять предшествующих репозиториев и ни одного рабочего.
#   • `kacho-vpc-operator` не резолвится на GitHub вовсе (404) — имя в списке ссылалось в
#     никуда, и каждый прогон bootstrap завершался ошибкой на нём.
#
# Порядок значим: монорепо первым, оно и есть рабочее дерево продукта.
REPOS=(
  kacho
)

# Предшествующие полирепо. Существуют и не заархивированы, но разработка в них не ведётся:
# на 2026-08-02 последний push в каждом — середина июля, тогда как в `kacho` — накануне.
# Клонируются только по явной просьбе: держать их в наборе по умолчанию значит выдавать
# устаревшее состояние за рабочее. См. `.claude/rules/polyrepo.md` §«Топология».
if [ "${KACHO_CLONE_LEGACY_POLYREPOS:-0}" = "1" ]; then
  REPOS+=(
    kacho-proto
    kacho-corelib
    kacho-api-gateway
    kacho-iam
    kacho-geo
    kacho-vpc
    kacho-compute
    kacho-nlb
    kacho-ui
    kacho-deploy
  )
fi

cd "$PROJECT_DIR"

clone_count=0
skip_count=0
fail_count=0

for r in "${REPOS[@]}"; do
  if [ -d "$PROJECT_DIR/$r/.git" ]; then
    echo "[skip] $r — already cloned"
    skip_count=$((skip_count + 1))
    continue
  fi

  url="$REMOTE_BASE/$r.git"
  case "$REMOTE_BASE" in
    file://*) url="${REMOTE_BASE#file://}/$r.git" ;;
  esac

  if git clone "$url" "$PROJECT_DIR/$r" 2>&1; then
    echo "[clone] $r"
    clone_count=$((clone_count + 1))
  else
    echo "[FAIL] $r — check SSH access to PRO-Robotech and that the repo exists" >&2
    fail_count=$((fail_count + 1))
  fi
done

echo
echo "Summary: cloned=$clone_count skipped=$skip_count failed=$fail_count"

if [ "$fail_count" -gt 0 ]; then
  echo "Some repos failed to clone. Already-cloned repos are preserved." >&2
  exit 1
fi

# Раскатки оснастки здесь больше нет (решение владельца 2026-08-02): оснастка живёт
# ТОЛЬКО в воркспейсе, копий в рабочих копиях продукта не заводится. Прежняя модель
# дублирования обосновывалась допущением, что хуки читаются лишь из текущего каталога
# и потому не достанут до воркспейса. Допущение опровергнуто собственным журналом хука:
# в нём срабатывания по деревьям, где нет ни своего settings.json, ни своих хуков, —
# хук следует за СЕССИЕЙ, а не за деревом файла. Значит копии не нужны, а раскатка,
# которая их создавала, снята вместе со своим обоснованием.

echo
echo "Next step:"
echo "  cp $SCRIPT_DIR/go.work.example $PROJECT_DIR/go.work"
echo "  cd $PROJECT_DIR/kacho/deploy && make dev-up"
