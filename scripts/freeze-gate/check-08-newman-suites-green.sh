#!/usr/bin/env bash
# Freeze gate check #08 — newman e2e CI green per repo.
#
# Uses gh CLI to look up the latest newman / e2e workflow run on main per
# product repo. A repo without a newman workflow is skipped (not failed).
#
# Exit 0 = latest green where workflow exists, 1 = at least one red,
# 2 = gh CLI unavailable or no workflow found anywhere.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

NAME="08-newman-suites-green"

if ! command -v gh >/dev/null 2>&1; then
    freeze_gate_skip "$NAME" "gh CLI not installed"
    exit 2
fi

# Candidate workflow names — first match wins per repo.
workflow_candidates=(
    "newman-e2e"
    "newman"
    "e2e"
    "newman-regression"
)

repos=(kacho-iam kacho-vpc kacho-compute kacho-api-gateway)
checked=0
red=0

for r in "${repos[@]}"; do
    wf_found=""
    for wf in "${workflow_candidates[@]}"; do
        if gh workflow view --repo "PRO-Robotech/$r" "$wf" >/dev/null 2>&1; then
            wf_found="$wf"
            break
        fi
    done
    [ -z "$wf_found" ] && continue

    checked=$((checked + 1))
    conclusion=$(gh run list --repo "PRO-Robotech/$r" --workflow "$wf_found" \
        --branch main --limit 1 --json conclusion --jq '.[0].conclusion // empty' 2>/dev/null || true)

    case "$conclusion" in
        success)
            echo "[ok]   $r/$wf_found: success"
            ;;
        "")
            echo "[gap] $r/$wf_found: no run found on main"
            red=$((red + 1))
            ;;
        *)
            echo "[gap] $r/$wf_found: latest main run = $conclusion"
            red=$((red + 1))
            ;;
    esac
done

if [ "$checked" -eq 0 ]; then
    freeze_gate_skip "$NAME" "no newman/e2e workflow found in any product repo"
    exit 2
fi

if [ "$red" -gt 0 ]; then
    freeze_gate_fail "$NAME" "$red repo(s) with red/missing newman runs on main"
    exit 1
fi

freeze_gate_pass "$NAME" "$checked repo(s) have green newman runs on main"
exit 0
