#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_PARENT="$(cd "$SCRIPT_DIR/.." && pwd)"

REPOS=(kacho-workspace kacho-api kacho-corelib kacho-api-gateway kacho-resource-manager kacho-vpc kacho-compute kacho-loadbalancer kacho-deploy)

for r in "${REPOS[@]}"; do
  if [ ! -d "$WS_PARENT/$r/.git" ]; then
    echo "[$r] not cloned, skip"
    continue
  fi
  cd "$WS_PARENT/$r"
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
