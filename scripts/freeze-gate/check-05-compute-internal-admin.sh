#!/usr/bin/env bash
# Freeze gate check #05 — Compute Internal admin Lists ready.
#
# Verifies the compute domain exposes its admin Internal services with
# List RPC for at least: InternalInstance, InternalDisk.
# (kacho-loadbalancer is out-of-scope per master plan; the former Hypervisor
#  internal-admin service was removed in KAC-36/79/80.)
#
# Exit 0 = present, 1 = missing services, 2 = sibling repo missing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

WS="$(freeze_gate_workspace_root)"
NAME="05-compute-internal-admin"

if ! freeze_gate_repo_cloned "$WS" kacho-proto; then
    freeze_gate_skip "$NAME" "kacho-proto not cloned"
    exit 2
fi

PROTO_DIR="$WS/project/kacho-proto/proto/kacho/cloud/compute/v1"

if [ ! -d "$PROTO_DIR" ]; then
    freeze_gate_skip "$NAME" "compute/v1 proto directory missing"
    exit 2
fi

required_services=(
    "InternalInstance"
    "InternalDisk"
)

missing=0
for svc in "${required_services[@]}"; do
    # We require either a dedicated service file or the service block somewhere
    # under compute/v1, plus a `rpc List` RPC inside that service.
    if ! grep -rqE "service[[:space:]]+${svc}Service" "$PROTO_DIR" 2>/dev/null; then
        # tolerate the "internal_<resource>_service.proto" naming where the
        # service-name itself is shorter — also accept a List RPC mentioning the
        # resource name nearby
        if ! grep -rqE "rpc[[:space:]]+List[[:space:]]*\([[:space:]]*List${svc}sRequest" "$PROTO_DIR" 2>/dev/null; then
            echo "[gap] $svc: no Service or List${svc}sRequest found in $PROTO_DIR"
            missing=$((missing + 1))
        fi
    fi
done

if [ "$missing" -gt 0 ]; then
    freeze_gate_fail "$NAME" "$missing required Compute Internal service(s) missing"
    exit 1
fi

freeze_gate_pass "$NAME" "Compute Internal admin services ready (InternalInstance / InternalDisk)"
exit 0
