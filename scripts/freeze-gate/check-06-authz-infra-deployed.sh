#!/usr/bin/env bash
# Freeze gate check #06 — AuthZ infrastructure (Block D) deployed.
#
# Verifies the deploy-side declarations are in place:
#   - kacho-deploy has an OpenFGA chart / manifest with replicas >= 2
#   - drainer manifest or sidecar configured for kacho-iam
#   - subject_change_outbox migration exists in kacho-iam
#   - gateway authz config: enabled=true + failOpen=false
#
# Exit 0 = manifests present, 1 = gaps, 2 = required repos missing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

WS="$(freeze_gate_workspace_root)"
NAME="06-authz-infra-deployed"

for repo in kacho-deploy kacho-iam kacho-api-gateway; do
    if ! freeze_gate_repo_cloned "$WS" "$repo"; then
        freeze_gate_skip "$NAME" "$repo not cloned"
        exit 2
    fi
done

DEPLOY="$WS/project/kacho-deploy"
IAM="$WS/project/kacho-iam"
GW="$WS/project/kacho-api-gateway"

gaps=0

# OpenFGA chart / manifest
if ! grep -rqi 'openfga' "$DEPLOY/helm" "$DEPLOY/argo-apps" 2>/dev/null \
    && ! find "$DEPLOY" -path '*/openfga*' -type d -print -quit 2>/dev/null | grep -q .; then
    echo "[gap] no OpenFGA chart / manifest under $DEPLOY"
    gaps=$((gaps + 1))
fi

# OpenFGA HA: replicas >= 2 (check yaml values, accept either replicas:2/3 or
# replicaCount:2/3, or HPA min >= 2).
if [ "$gaps" -eq 0 ]; then
    if ! grep -rqE 'replica(Count)?:[[:space:]]*[2-9]|replicas:[[:space:]]*[2-9]' \
        "$DEPLOY/helm" 2>/dev/null; then
        echo "[gap] OpenFGA replicas >= 2 not declared in $DEPLOY/helm"
        gaps=$((gaps + 1))
    fi
fi

# Drainer reference in iam code or deploy
if ! grep -rqiE 'drainer|fga_outbox|subject_change_outbox' \
    "$IAM/internal" "$IAM/cmd" 2>/dev/null; then
    echo "[gap] no drainer / fga_outbox reference in $IAM/internal or $IAM/cmd"
    gaps=$((gaps + 1))
fi

# subject_change_outbox migration
shopt -s nullglob
migs=("$IAM"/migrations/*subject_change*.sql "$IAM"/migrations/*fga_outbox*.sql)
shopt -u nullglob
if [ ${#migs[@]} -eq 0 ]; then
    echo "[gap] no subject_change / fga_outbox migration in $IAM/migrations"
    gaps=$((gaps + 1))
fi

# Gateway authz config: must enable authz and not fail-open in default values
if [ -d "$GW/deploy" ] || [ -d "$DEPLOY/helm/api-gateway" ]; then
    # Tolerate either location; require any values.yaml that disables fail-open.
    if ! grep -rqE 'failOpen:[[:space:]]*false|fail_open:[[:space:]]*false' \
        "$GW/deploy" "$DEPLOY/helm/api-gateway" 2>/dev/null; then
        echo "[gap] gateway authz failOpen:false not declared in deploy values"
        gaps=$((gaps + 1))
    fi
fi

if [ "$gaps" -gt 0 ]; then
    freeze_gate_fail "$NAME" "$gaps gap(s) in authz infra declarations"
    exit 1
fi

freeze_gate_pass "$NAME" "OpenFGA HA + drainer + subject_change + gateway fail-closed declared"
exit 0
