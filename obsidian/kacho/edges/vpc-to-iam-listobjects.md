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
status: active
related_tickets:
  - "[[KAC-127]]"
  - "[[rbac-rules-model-2026-subphase-D-consumer-vpc]]"
tags:
  - edge
  - kacho-vpc
  - cross-service
  - authz
  - fga
---

# vpc → iam: AuthorizeService.ListObjects

> [!important] Текущая реализация — sub-phase D-consumer (§11), не KAC-127 Phase 4
> Раздел «Flow / Implementation pattern» ниже — исторический KAC-127-черновик. Актуальная
> механика — в callout «Sub-phase D-consumer (active)». Главное расхождение: relation =
> **`viewer`** (не `vpc.network.read`/`v_list`), object_type = FGA snake-case **`vpc_subnet`**
> (не `network`), scope — НЕ отдельное поле request'а (containment внутри FGA-модели).

> [!note] Sub-phase D-consumer (active) — kacho-vpc per-object filtered List
> - **Каждый из 7 public `List<Resource>`** (network/subnet/securityGroup/routeTable/address/
>   gateway/networkInterface) зовёт `AuthorizeService.ListObjects(subject, resource_type, action)`.
>   - `subject` = `pbconv.SubjectFromContext` (`user:usr_…`/`service_account:sva_…`); system/empty → passthrough (enforce делает per-RPC interceptor).
>   - `resource_type` = FGA snake-case (`vpc_subnet`, `vpc_network`, `vpc_security_group`, `vpc_route_table`, `vpc_address`, `vpc_gateway`, `vpc_network_interface`).
>   - `action` = `vpc.<resource>.list` → iam server-side `resolveActionToRelation` мапит verb `list`→relation **`viewer`** (та же tier-relation, что Check для read → **read==enforce**, D-45).
> - Ответ → `Decision`: `wildcard_grant` → bypass (все project-scoped строки, D-42 LST-3 global);
>   иначе `resource_ids` (bare) → `repo.ListByIDs(WHERE id = ANY)`; **pagination ПОСЛЕ фильтра** (D-46 LST-6).
> - **Get no-leak** (D-44 LST-5): `Get<Resource>` тоже прогоняет id через тот же `ListObjects` grant-set;
>   id ∉ set → `NotFound` (тот же текст, что и несуществующий ресурс) — **НЕ** `PermissionDenied`.
> - **fail-closed** (D-47): iam недоступен/ошибка → `Unavailable` (НЕ unfiltered, НЕ silently empty).
> - **Реализация**: `internal/authzfilter/` (`FGAFilter` поверх `AuthorizeService.ListObjects`, TTL-cache 5s,
>   fail-closed default) + `internal/clients/iam_listobjects_client.go` (gRPC adapter, `auth.PropagateOutgoing`).
>   Конфиг `authz.list-filter.{enabled(default true),authorize-endpoint,authorize-tls,timeout-ms,max-results,fail-open}`.
>   CI-гейт `make audit-list-filter` ужесточён до per-object (`ListAllowedIDs` обязателен в каждом List).
> - **Эталон**: kacho-compute `internal/authzfilter/` ([[compute-to-iam-listobjects]]) — тот же контракт.

**Caller**: `kacho-vpc` List handlers (7 public List* RPCs — networks, subnets, security_groups, route_tables, addresses, gateways, network_interfaces) + per-object no-leak Get* (D-44).
**Callee**: `kacho-iam` AuthorizeService.ListObjects ([[../rpc/iam-authorize-service]]) — public projection; verb `list`→relation `viewer`.
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
