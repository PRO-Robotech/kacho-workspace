---
title: "registry → geo: Namespace/Registry.region_id validation (REG-1 F4)"
aliases:
  - registry to geo region validate
category: edge
caller_repo: kacho-registry
callee_repo: kacho-geo
sync_async: sync
protocol: grpc-cluster-internal
status: active
related_tickets:
  - "[[KAC/redesign-2026]]"
tags:
  - edge
  - cross-service
  - kacho-registry
  - kacho-geo
  - geography
---

> [!note] Landed (сверено 2026-08-05): клиент — `services/registry/internal/clients/geo/region_client.go`,
> провязан в `cmd/kacho-registry/serve.go`. Статус `in-progress` снят.

> [!note] New edge (REG-1 F4, redesign-2026)
> Registry-редизайн сделал реестр **region-pinned**: `regionId` — required на Create, `placementType`
> всегда `REGIONAL` (OCI-контент region-scoped by construction, anycast — `zoneId` нет). Существование
> `regionId` валидируется peer-вызовом в geo (как vpc/compute/nlb). geo — leaf-owner Geography.

# registry → geo: Registry.region_id validation (REG-1 F4)

**Caller**: `kacho-registry` (`internal/clients/geo/region_client.go`; wired в `serve.go`/`config.go`,
`KACHO_REGISTRY_GEO_GRPC_ADDR` + `GEO_MTLS`).
**Callee**: `kacho-geo` (`geo.v1.RegionService.Get`).
**Protocol**: gRPC cluster-internal (direct dial :9090; **mTLS** — registry-client leaf, ServerName
`kacho-geo` ∈ geo server-cert SAN; per-edge `enable`).
**Sync/Async**: **sync** на request-path (per-call 5s deadline + `retry.OnUnavailable`).

## When invoked

- `Registry.Create` — валидировать `regionId` (required; omit → `INVALID_ARGUMENT "regionId is required"`).
- `regionId`/`placementType` immutable после Create (в update_mask → INVALID_ARGUMENT; peer-вызов не повторяется).

## Error handling (by-lane, peer-validate)

| Result | gRPC code | reason (по мере landing reason-token) |
|---|---|---|
| region существует | OK | — |
| region не найден | `FAILED_PRECONDITION` | `PEER_RESOURCE_MISSING` |
| geo недоступен | `UNAVAILABLE` (fail-closed мутации) | `PEER_UNAVAILABLE` |

## Ацикличность

geo — **leaf** (никогда не зовёт registry обратно). Уже существующие рёбра `registry → geo` нет
(это первое); прочие registry→iam (`InternalIAMService.Check`/fgaproxy :9091 + `ProjectService.Get` :9090 +
jwks-fetch :9097). Цикла нет.

## Deploy

registry chart: `authz.geoGrpcAddr` (default `kacho-geo…:9090`) + `mtls.edges.geo` + `mtls.serverName.geo`
(reuse `registry-client-tls` leaf). fe3455-prod: `registry.mtls.edges.geo: true` (geo hardened →
verified transport). Зашито в `services/registry/deploy/`.

## History

- **2026-07-20** (redesign-2026, REG-1 F4): ребро введено. Registry region-pinned + anycast. Зафиксировано
  в `polyrepo.md` runtime-edges + этот edge-файл. Backend commit `33d1637`, deploy `41c94e2`.
