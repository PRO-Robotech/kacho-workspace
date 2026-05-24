#!/usr/bin/env bash
# Freeze gate check #02 — all known findings closed (or wontfix).
#
# Scans findings/ directories across product repos and the workspace for
# open finding-issue markdown files. A finding is "closed" if either:
#   - its status field reads `done` / `closed` / `wontfix`, or
#   - it has been moved to findings/closed/ subdirectory.
#
# Exit 0 = all closed, 1 = open findings remain, 2 = no findings directories.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

WS="$(freeze_gate_workspace_root)"
NAME="02-findings-closed"

# Candidate finding locations.
search_paths=(
    "$WS/findings"
    "$WS/docs/findings"
    "$WS/project/kacho-iam/findings"
    "$WS/project/kacho-vpc/findings"
    "$WS/project/kacho-compute/findings"
)

existing=()
for p in "${search_paths[@]}"; do
    [ -d "$p" ] && existing+=("$p")
done

if [ ${#existing[@]} -eq 0 ]; then
    freeze_gate_skip "$NAME" "no findings/ directories present (no findings to check)"
    exit 2
fi

open=0
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

for dir in "${existing[@]}"; do
    while IFS= read -r -d '' file; do
        # Skip files already in a closed/ or wontfix/ subdirectory.
        case "$file" in
            */closed/*|*/wontfix/*|*/done/*) continue ;;
        esac

        # Look at a frontmatter / first-N-lines status hint.
        if head -40 "$file" | grep -qiE '^(status|state)[[:space:]]*:[[:space:]]*(done|closed|wontfix|resolved)\b'; then
            continue
        fi

        echo "$file" >> "$tmp"
    done < <(find "$dir" -type f -name '*.md' -print0)
done

if [ -s "$tmp" ]; then
    open=$(wc -l < "$tmp")
    echo "open findings:"
    cat "$tmp"
    freeze_gate_fail "$NAME" "$open open finding(s) remain"
    exit 1
fi

freeze_gate_pass "$NAME" "all findings closed or wontfix"
exit 0
