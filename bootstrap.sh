#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_PARENT="$(cd "$SCRIPT_DIR/.." && pwd)"

REMOTE_BASE="${KACHO_REMOTE_BASE:-git@github.com:PRO-Robotech}"

REPOS=(
  kacho-api
  kacho-corelib
  kacho-api-gateway
  kacho-resource-manager
  kacho-vpc
  kacho-compute
  kacho-loadbalancer
  kacho-deploy
)

cd "$WS_PARENT"

clone_count=0
skip_count=0
fail_count=0

for r in "${REPOS[@]}"; do
  if [ -d "$WS_PARENT/$r/.git" ]; then
    echo "[skip] $r — already cloned"
    skip_count=$((skip_count + 1))
    continue
  fi

  url="$REMOTE_BASE/$r.git"
  case "$REMOTE_BASE" in
    file://*) url="${REMOTE_BASE#file://}/$r.git" ;;
  esac

  if git clone "$url" "$WS_PARENT/$r" 2>&1; then
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

echo
echo "Next step:"
echo "  cp $SCRIPT_DIR/go.work.example $WS_PARENT/go.work"
echo "  cd $WS_PARENT/kacho-deploy && make dev-up"
