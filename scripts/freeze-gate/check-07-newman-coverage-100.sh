#!/usr/bin/env bash
# Freeze gate check #07 — newman RPC coverage = 100% per service.
#
# Runs `tests/newman/scripts/coverage.py --min 100` for each repo that ships
# the coverage tool. A repo without coverage.py is treated as "not in scope".
#
# Exit 0 = all covered, 1 = gaps, 2 = no repo ships coverage tool.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

WS="$(freeze_gate_workspace_root)"
NAME="07-newman-coverage-100"

repos=(kacho-iam kacho-vpc kacho-compute kacho-api-gateway)
ran=0
gaps=0

for r in "${repos[@]}"; do
    repo="$WS/project/$r"
    [ -d "$repo/.git" ] || continue
    cov="$repo/tests/newman/scripts/coverage.py"
    [ -x "$cov" ] || [ -f "$cov" ] || continue
    ran=$((ran + 1))
    if ! ( cd "$repo" && python3 tests/newman/scripts/coverage.py --min 100 ); then
        echo "[gap] $r: newman coverage < 100%"
        gaps=$((gaps + 1))
    fi
done

if [ "$ran" -eq 0 ]; then
    freeze_gate_skip "$NAME" "no repo ships tests/newman/scripts/coverage.py"
    exit 2
fi

if [ "$gaps" -gt 0 ]; then
    freeze_gate_fail "$NAME" "$gaps repo(s) below 100% newman coverage"
    exit 1
fi

freeze_gate_pass "$NAME" "100% newman RPC coverage across $ran repo(s)"
exit 0
