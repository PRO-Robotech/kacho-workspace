---
title: "iam ↔ opa: sidecar policy evaluation"
aliases:
  - iam to opa
  - opa sidecar
category: edge
caller_repo: kacho-iam
callee_repo: open-policy-agent
sync_async: sync
protocol: REST/JSON (OPA Data API)
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - edge
  - kacho-iam
  - cross-service
  - opa
---

# iam ↔ opa: sidecar policy evaluation

**Caller(s)**: `kacho-iam` (AuthorizeService.Check), `kacho-vpc` / `kacho-compute` / `kacho-api-gateway` (per-RPC interceptor optional).
**Callee**: OPA sidecar `localhost:8181` (один per pod каждого сервиса — НЕ shared).
**Protocol**: REST/JSON, OPA Data API (`POST /v1/data/<policy-path>`).
**Sync/Async**: sync per-request. p95 ≤2ms (localhost, in-memory policy).
**Status**: **Phase 3 planned**. Bundle-distributed signed policies от [[../rpc/iam-opa-bundle-service]].

## Calls (Phase 3)

```http
POST http://localhost:8181/v1/data/kacho/cluster/deny
Content-Type: application/json

{
  "input": {
    "subject": "user:usr_xxx",
    "relation": "vpc.networks.create",
    "object": "project:prj_yyy",
    "context": { "ip": "1.2.3.4", "mfa_fresh": true, "acr": "aal2" }
  }
}
```

Response:
```json
{ "result": { "deny": false, "reason": null } }
```

Если `deny=true` → Check returns `allowed=false` без FGA lookup (cluster-deny override).

## Policies (Phase 3 catalog)

- `kacho/cluster/deny` — org-wide cluster-deny rules (override FGA allow).
- `kacho/stepup/required` — when MFA fresh + ACR required.
- `kacho/quota/allowed` — per-account spend / rate limits.
- `kacho/data/classification` — PII / financial export deny.
- `kacho/breakglass/active` — Phase 7 break-glass override (`deny=false` для cluster:system_admin during active grant).

## Bundle distribution

- OPA agent config polls `https://api.kacho.cloud/iam/v1/internal/opa/bundles/{name}.tar.gz` (см. [[../rpc/iam-opa-bundle-service]]).
- ETag-based caching; reload interval 30s configurable (`OPA_POLLING_MIN_DELAY_SECONDS`).
- cosign signature verified (fail-closed если invalid signature).

## Error handling

| OPA response | Caller action |
|---|---|
| 200 + `deny=true` | apply deny |
| 200 + `deny=false` | pass through к FGA |
| 5xx / timeout | **fail-closed** для мутаций (treat as deny); for reads — fail-open behind flag |
| 404 (policy missing) | log + fail-closed |

## Notes

- OPA sidecar runs as separate container в той же pod. **Не** общий cluster service — каждая реплика имеет свой OPA → нет network hop, cache thrash.
- Phase 3 bundles signed cosign в CI (Phase 11 supply-chain).
- OPA NOT replacement для OpenFGA — это **org-wide override layer**: FGA dictates allow, OPA can revoke (cluster-deny). FGA only — Phase 1-2; +OPA — Phase 3.

## See also

[[iam-to-openfga-check]] [[../rpc/iam-authorize-service]] [[../rpc/iam-internal-authorize-service]] [[../rpc/iam-opa-bundle-service]] [[../packages/iam-service-jit]] [[../packages/iam-service-breakglass]] [[../KAC/KAC-127]]

#edge #kacho-iam #cross-service #opa
