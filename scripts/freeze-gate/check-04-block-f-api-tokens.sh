#!/usr/bin/env bash
# Freeze gate check #04 — block F (API tokens) wired + newman case.
#
# Verifies:
#   - kacho-proto: api_token*.proto present in iam/v1
#   - kacho-iam: api_token migration + apps/.../api_token package
#   - kacho-api-gateway: Bearer kat_ prefix handling in middleware
#   - newman case for api-token exists
#
# Exit 0 = wired, 1 = gaps, 2 = required sibling repos missing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

WS="$(freeze_gate_workspace_root)"
NAME="04-block-f-api-tokens"

for repo in kacho-proto kacho-iam kacho-api-gateway; do
    if ! freeze_gate_repo_cloned "$WS" "$repo"; then
        freeze_gate_skip "$NAME" "$repo not cloned"
        exit 2
    fi
done

PROTO_DIR="$WS/project/kacho-proto/proto/kacho/cloud/iam/v1"
IAM_REPO="$WS/project/kacho-iam"
GW_REPO="$WS/project/kacho-api-gateway"
NEWMAN_DIR="$IAM_REPO/tests/newman/cases"

gaps=0
shopt -s nullglob

proto_hits=("$PROTO_DIR"/api_token*.proto)
if [ ${#proto_hits[@]} -eq 0 ]; then
    echo "[gap] no api_token*.proto in $PROTO_DIR"
    gaps=$((gaps + 1))
fi

migration_hits=("$IAM_REPO"/migrations/*api_token*.sql "$IAM_REPO"/migrations/*api_tokens*.sql)
if [ ${#migration_hits[@]} -eq 0 ]; then
    echo "[gap] no api_token migration in $IAM_REPO/migrations"
    gaps=$((gaps + 1))
fi

pkg_hits=("$IAM_REPO"/internal/apps/kacho/api/api_token* \
          "$IAM_REPO"/internal/apps/api_token*)
if [ ${#pkg_hits[@]} -eq 0 ]; then
    echo "[gap] no api_token package under $IAM_REPO/internal/apps"
    gaps=$((gaps + 1))
fi

# kat_ prefix Bearer handling — search gateway for the literal prefix.
if [ -d "$GW_REPO/internal" ] && ! grep -rqE 'kat_|ApiToken' "$GW_REPO/internal" 2>/dev/null; then
    echo "[gap] $GW_REPO/internal does not reference kat_ or ApiToken (Bearer prefix wiring)"
    gaps=$((gaps + 1))
fi

newman_hits=("$NEWMAN_DIR"/*api*token*.py "$NEWMAN_DIR"/*apitoken*.py)
if [ ${#newman_hits[@]} -eq 0 ]; then
    echo "[gap] no api-token newman case in $NEWMAN_DIR"
    gaps=$((gaps + 1))
fi

shopt -u nullglob

if [ "$gaps" -gt 0 ]; then
    freeze_gate_fail "$NAME" "$gaps gap(s) in API-token wiring"
    exit 1
fi

freeze_gate_pass "$NAME" "API-token resource + RPC + gateway + newman wired"
exit 0
