#!/usr/bin/env bash
# vault-sync — агрегирует per-repo docs/arch/ всех сервисов в Obsidian-vault.
# Источник истины — <repo>/docs/arch/ в сервисном репо; сюда стягивается
# read-only для единого browsable-обзора. Регенерация — archgraph в каждом репо.
set -euo pipefail
WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT="$WS/obsidian/kacho"
synced=0
for archdir in "$WS"/project/*/docs/arch; do
  [ -d "$archdir" ] || continue
  repo="$(basename "$(dirname "$(dirname "$archdir")")")"
  # build-worktree archgraph — не сервис, пропускаем
  case "$repo" in *-archgraph) continue;; esac
  # worktree-суффикс -archdocs нормализуем к имени сервиса
  repo="${repo%-archdocs}"
  dst="$VAULT/$repo/arch"
  rm -rf "$dst"; mkdir -p "$dst"
  cp -r "$archdir/." "$dst/"
  echo "synced: $repo ($(find "$dst" -type f | wc -l) files)"
  synced=$((synced + 1))
done
echo "vault-sync: aggregated $synced repo(s)"
