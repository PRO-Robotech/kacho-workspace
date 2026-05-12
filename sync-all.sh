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

REPOS=(kacho-proto kacho-corelib kacho-api-gateway kacho-resource-manager kacho-vpc kacho-vpc-implement kacho-compute kacho-loadbalancer kacho-deploy)

for r in "${REPOS[@]}"; do
  if [ ! -d "$PROJECT_DIR/$r/.git" ]; then
    echo "[$r] not cloned, skip"
    continue
  fi
  cd "$PROJECT_DIR/$r"
  before="$(git rev-parse HEAD 2>/dev/null)"
  git fetch --quiet || { echo "[$r] fetch failed"; continue; }
  if git pull --ff-only --quiet 2>/dev/null; then
    after="$(git rev-parse HEAD)"
    if [ "$before" = "$after" ]; then
      echo "[$r] up-to-date"
    else
      echo "[$r] updated to $after"
    fi
  else
    echo "[$r] skipped: not fast-forward"
  fi
done
