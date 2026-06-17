#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/project"
mkdir -p "$PROJECT_DIR"

REMOTE_BASE="${KACHO_REMOTE_BASE:-git@github.com:PRO-Robotech}"

REPOS=(
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
  kacho-vpc-operator
)

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

if [ -x "$SCRIPT_DIR/sync-tooling.sh" ]; then
  echo
  echo "Раскатываю AI-оснастку (rules/agents/skills/hooks/settings) в репо…"
  "$SCRIPT_DIR/sync-tooling.sh" || echo "[warn] sync-tooling завершился с ошибкой — запусти ./sync-tooling.sh вручную"
fi

echo
echo "Next step:"
echo "  cp $SCRIPT_DIR/go.work.example $PROJECT_DIR/go.work"
echo "  cd $PROJECT_DIR/kacho-deploy && make dev-up"
