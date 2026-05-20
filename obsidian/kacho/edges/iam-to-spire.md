---
title: "iam ↔ spire: SPIFFE Workload API"
aliases:
  - iam to spire
  - spire workload
  - spiffe
category: edge
caller_repo: kacho-iam
callee_repo: spire-server
sync_async: sync
protocol: gRPC (SPIFFE Workload API)
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - edge
  - kacho-iam
  - cross-service
  - spiffe
  - mtls
---

# iam ↔ spire: SPIFFE Workload API

**Caller(s)**:
- Every kacho service pod (vpc, compute, iam, api-gateway) — fetch own SVID (X.509 mTLS cert / JWT SVID).
- `kacho-iam` (admin-tool) — register new workload entries.

**Callee**: SPIRE Server cluster (`spire-server:8081`) + SPIRE Agent per node (`unix:///run/spire/sockets/api.sock`).
**Protocol**: gRPC (SPIFFE Workload API — fetch); gRPC (SPIRE Server Admin API — register).
**Sync/Async**: sync per-call.
**Status**: **Phase 10 planned** (production deployment SPIRE Server HA + Agent + Cilium mesh).

## Architecture (Phase 10)

```
                  ┌──────────────────────────┐
                  │ SPIRE Server (HA, 3 reps)│
                  │   (sqlite/postgres)      │
                  └──────────────────────────┘
                            ↑ Node Attest
                  ┌─────────┴────────┐
                  │ SPIRE Agent      │  per node
                  │ (unix socket)    │
                  └──────────────────┘
                       ↑ Workload API
              ┌────────┴────────┐
              │  kacho pod      │
              │  (workload)     │
              └─────────────────┘
```

## SVID issuance flow

1. SPIRE Agent boots → attest к Server (k8s_psat — pod service-account JWT).
2. Pod boots → mounts `/run/spire/sockets/api.sock`.
3. Pod calls `FetchX509SVID` (Workload API) → returns short-lived X.509 cert + private key + bundle (root CA).
4. Pod auto-rotate cert before TTL expiry (default 1h).
5. SPIFFE ID format: `spiffe://kacho.cloud/ns/{namespace}/sa/{service-account}`.

## Used for (Phase 10)

- **mTLS between kacho services** — каждый сервис authenticates peer SVID (см. [[iam-to-cilium-mesh]]).
- **JWT SVID for federation Class C** — workload получает JWT signed by SPIRE → exchanges на kacho federation Exchange endpoint ([[../rpc/iam-federation-exchange-service]]).
- **CAEP subscriber mTLS** — kacho-iam authenticates external subscribers via mTLS bundle.
- **Audit signing** — SPIRE-issued JWT-SVID для batch signing inputs (Phase 9 audit pipeline).

## Workload Registration

SPIRE Server entries registered via kacho-iam admin tool (Phase 10):

```bash
spire-server entry create \
  -spiffeID spiffe://kacho.cloud/ns/kacho-vpc/sa/kacho-vpc \
  -parentID spiffe://kacho.cloud/ns/spire/sa/spire-agent \
  -selector k8s:ns:kacho-vpc \
  -selector k8s:sa:kacho-vpc \
  -ttl 3600
```

## Error handling

| SPIRE response | Action |
|---|---|
| 200 + SVID | success; rotate before expiry |
| 401 / no SVID | pod restart (cert chain broken) |
| 5xx | retry exp-backoff |
| Bundle missing | mTLS reject downstream |

## Notes

- SPIRE Server HA — 3+ replicas, shared Postgres backend (DB schema separate from `kacho_iam`).
- Cosign attestor (Phase 10) — SVID issued only после image signature verify.
- Hubble Observability — Cilium-side flow logs include SPIFFE IDs (Phase 10).
- НЕ для tenant-facing workloads — это только intra-cluster mTLS bootstrap.

## See also

[[iam-to-cilium-mesh]] [[../rpc/iam-federation-exchange-service]] [[../resources/iam-service-account]] [[../KAC/KAC-127]]

#edge #kacho-iam #cross-service #spiffe #mtls
