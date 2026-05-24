#!/usr/bin/env bash
# Freeze gate check #09 — Go integration coverage >= 80% per service.
#
# Runs `go test -short -cover ./internal/...` per kacho-* service repo, parses
# total coverage and asserts >= threshold (default 80). Repos without Go code
# (kacho-proto, kacho-deploy, kacho-ui, kacho-workspace) are skipped.
#
# Honors KACHO_FREEZE_COVERAGE_MIN env var (default 80).
# Honors KACHO_FREEZE_COVERAGE_SKIP=1 to short-circuit (heavy in CI cron).
#
# Exit 0 = all pass threshold, 1 = below threshold, 2 = no go available
# or coverage-skip enabled.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

WS="$(freeze_gate_workspace_root)"
NAME="09-integration-coverage"
MIN="${KACHO_FREEZE_COVERAGE_MIN:-80}"

if [ "${KACHO_FREEZE_COVERAGE_SKIP:-0}" = "1" ]; then
    freeze_gate_skip "$NAME" "KACHO_FREEZE_COVERAGE_SKIP=1 set"
    exit 2
fi

if ! command -v go >/dev/null 2>&1; then
    freeze_gate_skip "$NAME" "go not installed"
    exit 2
fi

repos=(kacho-corelib kacho-api-gateway kacho-iam kacho-vpc kacho-compute)
ran=0
below=0

for r in "${repos[@]}"; do
    repo="$WS/project/$r"
    [ -f "$repo/go.mod" ] || continue
    ran=$((ran + 1))

    cov_file="$(mktemp)"
    if ( cd "$repo" && go test -short -coverprofile="$cov_file" ./internal/... >/dev/null 2>&1 ); then
        pct=$(go tool cover -func="$cov_file" 2>/dev/null | awk '/^total:/ {print $3}' | tr -d '%')
        pct_int=${pct%.*}
        if [ -z "$pct_int" ]; then pct_int=0; fi
        if [ "$pct_int" -lt "$MIN" ]; then
            echo "[gap] $r: ${pct}% < ${MIN}%"
            below=$((below + 1))
        else
            echo "[ok]   $r: ${pct}%"
        fi
    else
        echo "[gap] $r: go test failed"
        below=$((below + 1))
    fi
    rm -f "$cov_file"
done

if [ "$ran" -eq 0 ]; then
    freeze_gate_skip "$NAME" "no Go service repos cloned"
    exit 2
fi

if [ "$below" -gt 0 ]; then
    freeze_gate_fail "$NAME" "$below service(s) below ${MIN}% integration coverage"
    exit 1
fi

freeze_gate_pass "$NAME" "$ran service(s) at or above ${MIN}% integration coverage"
exit 0
