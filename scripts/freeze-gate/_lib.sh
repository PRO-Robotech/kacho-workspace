#!/usr/bin/env bash
# Shared helpers for freeze-gate check scripts.
# Source-only — not directly executable.

# Workspace root (one level above scripts/).
freeze_gate_workspace_root() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
    cd "$script_dir/../.." && pwd
}

# Print a status line in a consistent format used by run-all.sh.
# Usage: freeze_gate_pass "01-no-stubs" "details"
freeze_gate_pass() {
    echo "[PASS] $1${2:+ — $2}"
}

freeze_gate_fail() {
    echo "[FAIL] $1${2:+ — $2}" >&2
}

freeze_gate_skip() {
    echo "[SKIP] $1${2:+ — $2}" >&2
}

# Returns 0 if a sibling repo is cloned under project/<name>.
freeze_gate_repo_cloned() {
    local ws="$1"
    local repo="$2"
    [ -d "$ws/project/$repo/.git" ]
}

# Returns the list of all 9 sibling repos that participate in the freeze gate.
# (kacho-loadbalancer / kacho-nlb / kacho-vpc-implement are excluded — they are
# not part of the freeze contract per the W3.4 acceptance doc.)
freeze_gate_repos() {
    cat <<'EOF'
kacho-proto
kacho-corelib
kacho-api-gateway
kacho-iam
kacho-vpc
kacho-compute
kacho-deploy
kacho-ui
kacho-workspace
EOF
}
