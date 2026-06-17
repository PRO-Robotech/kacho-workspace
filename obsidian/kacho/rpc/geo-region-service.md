---
title: RegionService
aliases:
  - RegionService (geo)
  - InternalRegionService (geo)
proto_file: kacho/cloud/geo/v1/region_service.proto
category: rpc
backend: kacho-geo
backend_port: 9090
visibility: public
domain: geo
related_resource: "[[resources/geo-region]]"
methods_count: 5
async_methods: 0
status: in-progress
tags:
  - rpc
  - kacho-geo
  - geo
  - geography
---

# RegionService + InternalRegionService (geo)

**Proto**: `kacho-proto/proto/kacho/cloud/geo/v1/region_service.proto` (public) +
`internal_catalog_service.proto` (`InternalRegionService`, admin).
**Backend**: `kacho-geo:9090` (public read) · `kacho-geo:9091` (Internal admin).
**Domain**: geo (вынесен из `compute.v1` эпиком #82). **Catalog-паттерн**: read-only public + admin-CRUD,
все методы **sync** (admin-мутации возвращают ресурс синхронно, НЕ `Operation` — parity с `InternalDiskTypeService`).

## Public methods (RegionService, :9090)

| Method | Request | Response | Sync/Async | authz |
|---|---|---|---|---|
| Get | GetRegionRequest | Region | sync | `geo.regions.get` (viewer/`system_viewer`-floor) |
| List | ListRegionsRequest | ListRegionsResponse | sync | `geo.regions.list` (viewer-floor) |

## Admin methods (InternalRegionService, :9091)

| Method | Request | Response | Sync/Async | authz |
|---|---|---|---|---|
| Create | CreateRegionRequest | Region | sync | `geo.regions.create` (`system_admin`) |
| Update | UpdateRegionRequest | Region | sync | `geo.regions.update` (`system_admin`) |
| Delete | DeleteRegionRequest | (Delete resp) | sync | `geo.regions.delete` (`system_admin`); RESTRICT если есть зоны → FailedPrecondition |

## REST mapping

| HTTP | Method | mux |
|---|---|---|
| `GET /geo/v1/regions/{region_id}` | Get | public |
| `GET /geo/v1/regions` | List | public |
| `POST /geo/v1/regions` | Create | **internal-only** (:9091, ban #6) |
| `PATCH /geo/v1/regions/{region_id}` | Update | **internal-only** |
| `DELETE /geo/v1/regions/{region_id}` | Delete | **internal-only** |

> Прежние `/compute/v1/regions` удалены (путь врал бы про владельца). Опечатка `compute.regionses.list`
> исправлена на `geo.regions.list` при extract (эпик #82, scenario 6.0-01).

## authz invariant

Per-RPC `InternalIAMService.Check` энфорсится в цепочке интерсепторов **обоих** листенеров
(internal НЕ освобождён, `security.md`). См. [[../edges/geo-to-iam-check]].

## See also

[[geo-zone-service]] [[../resources/geo-region]] [[../edges/nlb-to-geo-region-validate]] [[../edges/geo-to-iam-check]]

#rpc #kacho-geo #geo #geography
