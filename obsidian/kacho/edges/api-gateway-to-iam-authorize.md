---
title: "api-gateway → iam: AuthorizeService.Check (per-RPC)"
aliases:
  - apigw to iam authorize
  - apigw fga check
category: edge
caller_repo: kacho-api-gateway
callee_repo: kacho-iam
sync_async: sync
protocol: gRPC
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - edge
  - kacho-api-gateway
  - cross-service
  - authz
  - fga
---

# api-gateway → iam: AuthorizeService.Check (per-RPC)

**Caller**: `kacho-api-gateway` authz middleware ([[../packages/api-gateway-middleware-authz]]).
**Callee**: `kacho-iam` AuthorizeService.Check ([[../rpc/iam-authorize-service]]) — `kacho-iam:9090`.
**Protocol**: gRPC. Cluster-internal — НЕ via api.kacho.cloud (avoids token-loop).
**Sync/Async**: sync per-request.
**Status**: **Phase 3 planned**.

## Flow per-request (Phase 3)

```
1. Client → POST /vpc/v1/networks (api.kacho.cloud)
2. api-gateway TLS-listener:
   - DPoP / JWT verify ([[../packages/api-gateway-middleware-dpop]])
   - Extract subject (user:usr_xxx or service_account:sva_xxx)
   - Extract verb (proto descriptor → "vpc.networks.create")
3. authz middleware ([[../packages/api-gateway-middleware-authz]]):
   - Resolve target object — for Create, project_id from request body
   - Build (subject, relation=verb, object=project:prj_yyy)
4. gRPC call → iam.AuthorizeService.Check
   - Per-RPC: ≤20ms p95 SLO (Phase 3 DoD)
   - Cached 5s (verify-then-cache; LISTEN-invalidate on FGA tuple change)
5. allowed=true → forward request to backend (vpc/compute/lb)
   allowed=false → respond 403 PermissionDenied + audit log
```

## Cache key

`hash(subject || relation || object || condition_params_hash || jwt_aal)` → 5s TTL.

## Cache invalidation

- LISTEN на `kacho_iam_fga_outbox` (PostgreSQL pubsub) → on any tuple change, gateway clears cache subset.
- Tag-based: scan cache keys with prefix `subject=user:usr_xxx` → invalidate (selective; не nuclear).
- TTL fallback: 5s ceiling.

## Fail-closed / fail-open policy

| Operation | iam.Check unavailable | Action |
|---|---|---|
| Mutation (POST/PUT/PATCH/DELETE) | fail-closed | 503 Unavailable + retry-after |
| Read (GET/List) | fail-open behind flag `KACHO_API_GATEWAY_AUTHZ_FAIL_OPEN_READS=true` (default false) | proceed without check (audit-logged) |
| List with FGA filtering | fail-closed (can't filter without lookup) | 503 |

## Error handling

| Check result | Gateway action |
|---|---|
| `allowed=true` | forward |
| `allowed=false` | 403 + audit `iam.authz.denied` |
| `Unavailable` | fail-closed for mutations (see above) |
| `Internal` | log + propagate 500 + alert |

## Notes

- Phase 1-2: NO per-RPC Check (auth-interceptor only verifies DPoP/JWT). Phase 3 adds Check.
- Phase 4 — ListObjects integration ([[vpc-to-iam-listobjects]] / [[compute-to-iam-listobjects]]) — backend itself queries ListObjects для List handlers; api-gateway не пред-фильтрует.
- API-gateway side cache shared across requests on same node (sync.Map). Cold cache p95 +5ms.

## See also

[[iam-to-openfga-check]] [[iam-to-opa]] [[vpc-to-iam-listobjects]] [[compute-to-iam-listobjects]] [[../rpc/iam-authorize-service]] [[../packages/api-gateway-middleware-authz]] [[../packages/api-gateway-middleware-dpop]] [[../packages/corelib-authz-listobjects]] [[../KAC/KAC-127]]

#edge #kacho-api-gateway #cross-service #authz #fga
