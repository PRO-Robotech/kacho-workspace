#!/usr/bin/env bash
# Freeze gate check #10 — main CI green in every product repo.
#
# Uses gh CLI to query the latest CI run on main per repo. Looks at the
# repo's "ci" workflow (or any workflow if no "ci" exists). A red or
# missing run = freeze blocker.
#
# Exit 0 = all green, 1 = at least one red/missing, 2 = gh CLI unavailable.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

NAME="10-ci-green-all-repos"

if ! command -v gh >/dev/null 2>&1; then
    freeze_gate_skip "$NAME" "gh CLI not installed"
    exit 2
fi

red=0
total=0

while read -r r; do
    total=$((total + 1))
    # Prefer explicit "ci" workflow if it exists; otherwise latest of any.
    if gh workflow view --repo "PRO-Robotech/$r" ci >/dev/null 2>&1; then
        conclusion=$(gh run list --repo "PRO-Robotech/$r" --workflow ci \
            --branch main --limit 1 --json conclusion --jq '.[0].conclusion // empty' 2>/dev/null || true)
    else
        conclusion=$(gh run list --repo "PRO-Robotech/$r" \
            --branch main --limit 1 --json conclusion --jq '.[0].conclusion // empty' 2>/dev/null || true)
    fi

    case "$conclusion" in
        success)
            echo "[ok]   $r: success"
            ;;
        "")
            echo "[gap] $r: no CI run found on main"
            red=$((red + 1))
            ;;
        *)
            echo "[gap] $r: latest main CI = $conclusion"
            red=$((red + 1))
            ;;
    esac
done < <(freeze_gate_repos)

if [ "$red" -gt 0 ]; then
    freeze_gate_fail "$NAME" "$red of $total repo(s) with red/missing main CI"
    exit 1
fi

freeze_gate_pass "$NAME" "all $total repo(s) green on main"
exit 0
