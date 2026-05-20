---
title: "vpc → iam: AuthorizeService.ListObjects (List filtering)"
aliases:
  - vpc listobjects
  - vpc fga listobjects
category: edge
caller_repo: kacho-vpc
callee_repo: kacho-iam
sync_async: sync
protocol: gRPC
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - edge
  - kacho-vpc
  - cross-service
  - authz
  - fga
---

# vpc → iam: AuthorizeService.ListObjects

**Caller**: `kacho-vpc` List handlers (14 List* RPCs — networks, subnets, security_groups, route_tables, addresses, gateways, private_endpoints, network_interfaces, …).
**Callee**: `kacho-iam` AuthorizeService.ListObjects ([[../rpc/iam-authorize-service]]).
**Protocol**: gRPC.
**Sync/Async**: sync per-request.
**Status**: **Phase 4 planned**. SLO ListObjects p95 ≤100ms (Phase 4 DoD).

## Flow per-request (Phase 4)

```
Client → GET /vpc/v1/networks?folder_id=prj_yyy
  ↓ api-gateway DPoP/JWT verify + AuthorizeService.Check(user, "vpc.networks.list", project:prj_yyy)
  ↓ Forward к kacho-vpc Network.List(folder_id=prj_yyy)
  ↓
kacho-vpc Network.List:
  ↓ Call iam.AuthorizeService.ListObjects(
        user=user:usr_xxx,
        relation="vpc.network.read",
        object_type="network",
        ParentFilter=project:prj_yyy)
      ↓ Returns visible network IDs: ["net_aaa", "net_bbb", "net_ccc"]
  ↓ SQL: SELECT * FROM networks WHERE folder_id=$1 AND id = ANY($2)
  ↓ Return filtered list to api-gateway
```

## Pagination strategy

- ListObjects supports pagination cursor (opaque, signed).
- kacho-vpc passes opaque cursor to client unchanged.
- На каждый page request — new ListObjects call (no client-side cursor mutation).

## Cache strategy

- 5s TTL keyed on `(user, relation, project_id)` — shared with [[api-gateway-to-iam-authorize]] cache.
- Bigger page-set (≥1k items) → bypass cache (always fresh).
- LISTEN invalidation same as api-gateway.

## Fail-closed behavior

ListObjects unavailable → 503 (можно return empty list = false positive denial, дешевле fail-closed).

## SLO budget per List RPC

| Component | Budget |
|---|---|
| api-gateway DPoP/JWT | 5ms p95 |
| api-gateway authz.Check (top-level list permission) | 20ms p95 |
| kacho-vpc → iam.ListObjects | **100ms p95** |
| kacho-vpc SQL SELECT + filter | 30ms p95 |
| Total p95 end-to-end | ≤200ms |

## Cardinality consideration

ListObjects returns FULL set of visible IDs (no streaming). For user with access к 1M networks:
- Cap ListObjects response 10k items (server-enforced).
- For >10k → require explicit `parent` filter (project_id) — Phase 4 DoD test.
- > 10k AND no parent → 400 InvalidArgument "result set too large; specify project_id".

## Implementation pattern

```go
// kacho-vpc internal/apps/kacho/api/network/list.go (Phase 4)
visible, err := authzClient.ListObjects(ctx, authz.ListObjectsRequest{
    Subject:    callerSubject(ctx),
    Relation:   "vpc.network.read",
    ObjectType: "network",
    Parent:     &authz.ParentFilter{Type: "project", ID: folderID},
})
if err != nil { return nil, mapAuthzErr(err) }

rows, _ := repo.ListByFolderAndIDs(ctx, folderID, visible.IDs)
return rows, nil
```

## See also

[[compute-to-iam-listobjects]] [[api-gateway-to-iam-authorize]] [[iam-to-openfga-check]] [[../rpc/iam-authorize-service]] [[../packages/corelib-authz-listobjects]] [[../KAC/KAC-127]]

#edge #kacho-vpc #cross-service #authz #fga
