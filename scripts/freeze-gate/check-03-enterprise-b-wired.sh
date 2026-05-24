#!/usr/bin/env bash
# Freeze gate check #03 — Enterprise block B.1–B.10 wired + newman cases exist.
#
# Verifies that each of the 10 Enterprise B services has both a proto
# definition under kacho-proto and a newman case file in kacho-iam tests.
#
# Exit 0 = all 10 wired, 1 = gaps, 2 = required sibling repos missing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

WS="$(freeze_gate_workspace_root)"
NAME="03-enterprise-b-wired"

if ! freeze_gate_repo_cloned "$WS" kacho-proto \
    || ! freeze_gate_repo_cloned "$WS" kacho-iam; then
    freeze_gate_skip "$NAME" "kacho-proto or kacho-iam not cloned"
    exit 2
fi

PROTO_DIR="$WS/project/kacho-proto/proto/kacho/cloud/iam/v1"
NEWMAN_DIR="$WS/project/kacho-iam/tests/newman/cases"

# Map each enterprise feature to (proto-marker, newman-case-marker).
# proto-marker = filename glob inside iam/v1 that must exist
# newman-marker = filename glob inside cases/ that must exist
declare -a features=(
    "B1-federation|federation*.proto|*federation*.py"
    "B2-access-review|access_review*.proto|*access*review*.py"
    "B3-jit|jit*.proto|*jit*.py"
    "B4-break-glass|break_glass*.proto|*break*glass*.py"
    "B5-caep|caep*.proto|*caep*.py"
    "B6-back-channel-logout|back_channel_logout*.proto|*back*channel*.py"
    "B7-compliance-report|compliance_report*.proto|*compliance*.py"
    "B8-cluster-admin|cluster_admin*.proto|*cluster*admin*.py"
    "B9-audit-signing|audit_signing*.proto|*audit*.py"
    "B10-quota|quota*.proto|*quota*.py"
)

missing=0
shopt -s nullglob
for entry in "${features[@]}"; do
    IFS='|' read -r tag proto_glob newman_glob <<< "$entry"

    # shellcheck disable=SC2206  # intentional glob expansion against PROTO_DIR
    proto_hits=("$PROTO_DIR"/$proto_glob)
    if [ ${#proto_hits[@]} -eq 0 ]; then
        echo "[gap] $tag: no proto matching $proto_glob in $PROTO_DIR"
        missing=$((missing + 1))
        continue
    fi

    # shellcheck disable=SC2206  # intentional glob expansion against NEWMAN_DIR
    newman_hits=("$NEWMAN_DIR"/$newman_glob)
    if [ ${#newman_hits[@]} -eq 0 ]; then
        echo "[gap] $tag: no newman case matching $newman_glob in $NEWMAN_DIR"
        missing=$((missing + 1))
    fi
done
shopt -u nullglob

if [ "$missing" -gt 0 ]; then
    freeze_gate_fail "$NAME" "$missing Enterprise B feature(s) missing proto or newman case"
    exit 1
fi

freeze_gate_pass "$NAME" "all 10 Enterprise B features wired with newman coverage"
exit 0
