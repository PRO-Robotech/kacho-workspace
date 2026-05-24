#!/usr/bin/env bash
# Freeze gate check #01 — no stub / Unimplemented / disabled-by-config on surface.
#
# Scans every cloned sibling kacho-* repo for:
#   - `codes.Unimplemented` returned from production code (non _test.go)
#   - `// TODO`, `// FIXME`, `// XXX` markers on production code
#   - `disabled-by-config` / `feature_enabled: false` in deploy values.yaml
#
# Exit 0 = clean, 1 = findings, 2 = no repos cloned (skipped).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

WS="$(freeze_gate_workspace_root)"
NAME="01-no-stubs"

shopt -s nullglob
project_repos=("$WS"/project/kacho-*)
shopt -u nullglob

if [ ${#project_repos[@]} -eq 0 ]; then
    freeze_gate_skip "$NAME" "no project/kacho-* repos cloned"
    exit 2
fi

findings=0
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

for repo in "${project_repos[@]}"; do
    [ -d "$repo/.git" ] || continue
    rel="${repo#"$WS"/}"

    # Skip kacho-workspace itself (this lives there) and kacho-proto (generated stubs).
    case "$(basename "$repo")" in
        kacho-workspace|kacho-proto) continue ;;
    esac

    # codes.Unimplemented in production code (excluding generated and tests)
    if grep -rn --include='*.go' \
        --exclude='*_test.go' \
        --exclude='*.pb.go' \
        --exclude='*_grpc.pb.go' \
        'codes\.Unimplemented' "$repo/internal" "$repo/cmd" 2>/dev/null >> "$tmp"; then
        :
    fi

    # TODO / FIXME / XXX markers on production code
    grep -rEn --include='*.go' \
        --exclude='*_test.go' \
        --exclude='*.pb.go' \
        --exclude='*_grpc.pb.go' \
        '(^|[^a-zA-Z_])(TODO|FIXME|XXX)([^a-zA-Z_]|$)' \
        "$repo/internal" "$repo/cmd" 2>/dev/null >> "$tmp" || true

    # Disabled features in deploy values.yaml
    if [ -d "$repo/deploy" ]; then
        grep -rEn --include='values*.yaml' --include='*.yaml' \
            '(disabled-by-config|disabled:[[:space:]]*true|feature_enabled:[[:space:]]*false)' \
            "$repo/deploy" 2>/dev/null >> "$tmp" || true
    fi

    if [ -s "$tmp" ]; then
        findings=$(( findings + $(wc -l < "$tmp") ))
        echo "--- $rel ---"
        cat "$tmp"
        : > "$tmp"
    fi
done

if [ "$findings" -gt 0 ]; then
    freeze_gate_fail "$NAME" "$findings stub/TODO/disabled marker(s) found on production surface"
    exit 1
fi

freeze_gate_pass "$NAME" "0 stub/TODO/disabled markers on production surface"
exit 0
