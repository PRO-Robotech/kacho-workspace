#!/usr/bin/env bash
# Freeze gate check #11 — infra manifests ready (backups + TLS + fail-closed).
#
# Static check of kacho-deploy manifests for production-readiness markers:
#   - Postgres backup CronJob or chart
#   - TLS / cert-manager ingress configuration
#   - gateway authz: failOpen=false (also re-checked in #06)
#
# Exit 0 = present, 1 = gaps, 2 = kacho-deploy missing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

WS="$(freeze_gate_workspace_root)"
NAME="11-infra-ready"

if ! freeze_gate_repo_cloned "$WS" kacho-deploy; then
    freeze_gate_skip "$NAME" "kacho-deploy not cloned"
    exit 2
fi

DEPLOY="$WS/project/kacho-deploy"
gaps=0

# Backup CronJob / pgbackrest / wal-g / pg_dump
if ! grep -rqE 'pgbackrest|wal-g|pg_dump|postgres-backup|kind:[[:space:]]*CronJob' \
    "$DEPLOY/helm" "$DEPLOY/argo-apps" 2>/dev/null; then
    echo "[gap] no Postgres backup CronJob / pgbackrest / wal-g manifest in $DEPLOY"
    gaps=$((gaps + 1))
fi

# TLS / cert-manager
if ! grep -rqE 'cert-manager|tls:[[:space:]]*$|tls:[[:space:]]*\{|secretName:.*-tls' \
    "$DEPLOY/helm" "$DEPLOY/argo-apps" 2>/dev/null; then
    echo "[gap] no TLS / cert-manager ingress declaration in $DEPLOY"
    gaps=$((gaps + 1))
fi

# Gateway fail-closed (failOpen: false)
if ! grep -rqE 'failOpen:[[:space:]]*false|fail_open:[[:space:]]*false' \
    "$DEPLOY/helm" 2>/dev/null; then
    echo "[gap] no gateway authz failOpen:false in $DEPLOY/helm"
    gaps=$((gaps + 1))
fi

if [ "$gaps" -gt 0 ]; then
    freeze_gate_fail "$NAME" "$gaps infra readiness gap(s)"
    exit 1
fi

freeze_gate_pass "$NAME" "Postgres backup + TLS + gateway fail-closed declared"
exit 0
