#!/usr/bin/env bash
# Freeze gate check #13 — vault & docs/specs synchronised.
#
# Heuristic: every APPROVED acceptance doc under docs/specs/ that mentions a
# KAC-N ticket should have a matching obsidian/kacho/KAC/KAC-N.md trail.
# Conversely, every KAC trail should have a status field set.
#
# Exit 0 = synced, 1 = drift, 2 = obsidian/kacho missing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

WS="$(freeze_gate_workspace_root)"
NAME="13-docs-synced"

if [ ! -d "$WS/obsidian/kacho/KAC" ]; then
    freeze_gate_skip "$NAME" "obsidian/kacho/KAC missing"
    exit 2
fi

drift=0

# 1) Each KAC trail must declare a Status:.
while IFS= read -r -d '' note; do
    # Skip the all-tickets index files and .base files.
    base=$(basename "$note")
    case "$base" in
        all-tickets.md|all-tickets.base) continue ;;
    esac
    if ! grep -qiE '^\*\*Status\*\*[[:space:]]*:[[:space:]]*[a-z]+' "$note"; then
        echo "[drift] $note: missing **Status**: field"
        drift=$((drift + 1))
    fi
done < <(find "$WS/obsidian/kacho/KAC" -maxdepth 1 -type f -name 'KAC-*.md' -print0)

# 2) Each acceptance doc must reference at least one KAC ticket, and any
#    KAC-N tickets referenced should have a trail file.
if [ -d "$WS/docs/specs" ]; then
    while IFS= read -r -d '' spec; do
        # Only check acceptance docs.
        case "$(basename "$spec")" in
            *acceptance*.md) ;;
            *) continue ;;
        esac
        kacs=$(grep -oE 'KAC-[0-9]+' "$spec" | sort -u || true)
        if [ -z "$kacs" ]; then
            echo "[drift] $spec: no KAC-N reference"
            drift=$((drift + 1))
            continue
        fi
        while IFS= read -r kac; do
            [ -z "$kac" ] && continue
            if [ ! -f "$WS/obsidian/kacho/KAC/$kac.md" ]; then
                echo "[drift] $spec references $kac but $WS/obsidian/kacho/KAC/$kac.md missing"
                drift=$((drift + 1))
            fi
        done <<< "$kacs"
    done < <(find "$WS/docs/specs" -maxdepth 1 -type f -name '*.md' -print0)
fi

if [ "$drift" -gt 0 ]; then
    freeze_gate_fail "$NAME" "$drift docs/vault drift item(s)"
    exit 1
fi

freeze_gate_pass "$NAME" "vault KAC trail synchronised with docs/specs"
exit 0
