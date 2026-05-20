---
title: "iam ↔ cilium-mesh: mTLS via SPIFFE"
aliases:
  - cilium mesh
  - iam cilium
category: edge
caller_repo: cilium
callee_repo: kacho-iam
sync_async: continuous
protocol: data-plane (eBPF + mTLS)
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - edge
  - kacho-iam
  - cross-service
  - cilium
  - mtls
---

# iam ↔ cilium-mesh: mTLS via SPIFFE

**Provider**: Cilium Service Mesh (with WireGuard / IPSec / mTLS-via-SPIFFE).
**Identity source**: SPIRE-issued SVID ([[iam-to-spire]]).
**Status**: **Phase 10 planned**.

## Architecture (Phase 10)

Cilium agent (DaemonSet) per node:
- Reads SPIFFE SVID from SPIRE Agent socket.
- Configures eBPF mTLS termination on lo (transparent mTLS — pods don't need mTLS code).
- Enforces CiliumNetworkPolicy (CNP) based on SPIFFE identity.

```
┌─────────────┐  mTLS (transparent)  ┌─────────────┐
│  kacho-vpc  │ <──────────────────> │ kacho-iam   │
│  pod        │  (Cilium eBPF +      │ pod         │
│             │   SPIFFE SVID)       │             │
└─────────────┘                       └─────────────┘
```

## CiliumNetworkPolicy (CNP) examples

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: iam-admin-from-iam-only
  namespace: ory-hydra
spec:
  endpointSelector:
    matchLabels:
      app: hydra
      port: admin
  ingress:
  - fromEndpoints:
    - matchLabels:
        spiffe.io/identity: "spiffe://kacho.cloud/ns/kacho-iam/sa/kacho-iam"
```

## Used for (Phase 10)

- **Intra-cluster mTLS** — все вызовы kacho-vpc → kacho-iam / kacho-iam → Hydra-admin / Kratos-admin shielded mTLS.
- **Allow-list connectivity** — Hydra-admin port `4445` reachable ONLY от kacho-iam pod identity. Прочий traffic — deny.
- **Hubble observability** — flow logs include SPIFFE identities → audit-pipeline (Phase 9 + Phase 11 SIEM).
- **Pod-level identity propagation** — заменяет ServiceAccount tokens на SPIFFE SVID для intra-cluster auth (defense-in-depth).

## Notes

- Phase 10 — production-only. В dev cluster (kacho-deploy `make dev-up`) — Cilium opt-in.
- Allows replacing app-side mTLS code (pods don't need ssl certs / TLS config) — Cilium eBPF terminates транзитивно.
- Egress policies (Cilium CNP `egress[]`) — restricts kacho-iam talking external IdPs (только to verified domain set: Hydra-admin, Kratos-admin, OPA bundle server localhost, OpenFGA, Postgres).
- mTLS bound JWT (RFC 8705) — ortho-конкурент Cilium mTLS: api-gateway uses RFC 8705 (token-level cnf) AND Cilium mTLS (network-level) → defense-in-depth.

## See also

[[iam-to-spire]] [[../resources/iam-service-account]] [[../packages/api-gateway-middleware-dpop]] [[../packages/api-gateway-middleware-authz]] [[../KAC/KAC-127]]

#edge #kacho-iam #cross-service #cilium #mtls
