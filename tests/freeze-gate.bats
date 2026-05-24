#!/usr/bin/env bats
# Smoke tests for scripts/freeze-gate/.
#
# These verify per-script invariants without requiring sibling repos to be
# cloned: each check script must produce a deterministic SKIP (rc=2) or
# FAIL (rc=1) result against an empty fixture workspace, and never CRASH.

setup() {
    WORKSPACE_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export WORKSPACE_ROOT
}

@test "F1: all check scripts are executable" {
    for s in "$WORKSPACE_ROOT"/scripts/freeze-gate/check-*.sh; do
        [ -x "$s" ] || { echo "not executable: $s"; false; }
    done
}

@test "F2: every check script has a shebang and set -euo pipefail" {
    for s in "$WORKSPACE_ROOT"/scripts/freeze-gate/check-*.sh; do
        head -1 "$s" | grep -q '^#!/usr/bin/env bash' || { echo "missing bash shebang in $s"; false; }
        grep -q 'set -euo pipefail' "$s" || { echo "missing set -euo pipefail in $s"; false; }
    done
}

@test "F3: run-all.sh exits non-zero when all checks fail or skip, and prints a summary" {
    # In a fresh tmpdir with no project/ checkout, every check should be SKIP
    # or FAIL — never CRASH. run-all.sh must exit 1 or 2 (not 0).
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/scripts"
    cp -r "$WORKSPACE_ROOT/scripts/freeze-gate" "$tmp/scripts/"

    run "$tmp/scripts/freeze-gate/run-all.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Freeze gate summary"* ]]
    [[ "$output" == *"Totals:"* ]]

    rm -rf "$tmp"
}

@test "F4: run-all.sh writes JSON report when KACHO_FREEZE_OUTPUT_JSON set" {
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/scripts"
    cp -r "$WORKSPACE_ROOT/scripts/freeze-gate" "$tmp/scripts/"
    json="$tmp/report.json"

    KACHO_FREEZE_OUTPUT_JSON="$json" run "$tmp/scripts/freeze-gate/run-all.sh"
    [ -f "$json" ]
    # Minimal JSON sanity (no jq dependency).
    grep -q '"generated_at"' "$json"
    grep -q '"totals"' "$json"
    grep -q '"checks"' "$json"

    rm -rf "$tmp"
}

@test "F5: check-01-no-stubs reports PASS on a synthetic clean tree" {
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/scripts" "$tmp/project/kacho-fake/internal"
    cp -r "$WORKSPACE_ROOT/scripts/freeze-gate" "$tmp/scripts/"
    cat > "$tmp/project/kacho-fake/internal/clean.go" <<'GO'
package internal

func Clean() string { return "ok" }
GO
    mkdir -p "$tmp/project/kacho-fake/.git"

    run "$tmp/scripts/freeze-gate/check-01-no-stubs.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[PASS]"* ]]

    rm -rf "$tmp"
}

@test "F6: check-01-no-stubs reports FAIL when a TODO is present" {
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/scripts" "$tmp/project/kacho-fake/internal"
    cp -r "$WORKSPACE_ROOT/scripts/freeze-gate" "$tmp/scripts/"
    cat > "$tmp/project/kacho-fake/internal/dirty.go" <<'GO'
package internal

// TODO: implement
func Dirty() string { return "" }
GO
    mkdir -p "$tmp/project/kacho-fake/.git"

    run "$tmp/scripts/freeze-gate/check-01-no-stubs.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"[FAIL]"* ]] || [[ "$output" == *"TODO"* ]]

    rm -rf "$tmp"
}

@test "F7: check-13-docs-synced reports SKIP when obsidian/kacho/KAC missing" {
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/scripts"
    cp -r "$WORKSPACE_ROOT/scripts/freeze-gate" "$tmp/scripts/"

    run "$tmp/scripts/freeze-gate/check-13-docs-synced.sh"
    [ "$status" -eq 2 ]
    [[ "$output" == *"[SKIP]"* ]]

    rm -rf "$tmp"
}
