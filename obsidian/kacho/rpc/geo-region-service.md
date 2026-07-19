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
methods_count: 6
async_methods: 0
status: in-progress
related_tickets:
  - "[[KAC/GEO-1]]"
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
**Domain**: geo. **Catalog-паттерн (GEO-1 two-projection)**: public read отдаёт **lean**
`Region` (без status/infra; несёт `country_code°`/`open_for_placement°`/`open_zone_count_hint°`);
admin-мутации возвращают **синхронно-завершённый `Operation{done:true}`** (unwrap `.response`);
`GetInternal` отдаёт **full** `InternalRegion` (status + infra°). Byte-identical `InternalDiskTypeService`.

## Public methods (RegionService, :9090) — lean projection

| Method | Request | Response | Sync/Async | authz |
|---|---|---|---|---|
| Get | GetRegionRequest | Region (lean) | sync | `geo.regions.get` (→ GEO-1: project-scope EXEMPT, follow-on) |
| List | ListRegionsRequest | ListRegionsResponse | sync | фильтр `open_for_placement` |

## Admin methods (InternalRegionService, :9091)

| Method | Request | Response | Sync/Async | authz |
|---|---|---|---|---|
| Create | CreateRegionRequest (countryCode/status/infra) | Operation{done:true, response:Region, metadata:warnings°} | sync-done | `system_admin` |
| Update | UpdateRegionRequest (FieldMask) | Operation{done:true} | sync-done | `system_admin`; numericInfraId immutable |
| Delete | DeleteRegionRequest | Operation{done:true, response:Empty} | sync-done | `system_admin`; RESTRICT → `FAILED_PRECONDITION "region <id> is not empty"` |
| GetInternal | GetInternalRegionRequest | InternalRegion (status + infra°) | sync | `system_admin` |

## REST mapping (internal path self-describing)

| HTTP | Method | mux |
|---|---|---|
| `GET /geo/v1/regions/{region_id}` | Get | public |
| `GET /geo/v1/regions` | List | public |
| `POST /geo/v1/internal/regions` | Create | **internal-only** (:9091, ban #6) |
| `PATCH /geo/v1/internal/regions/{region_id}` | Update | **internal-only** |
| `DELETE /geo/v1/internal/regions/{region_id}` | Delete | **internal-only** |
| `GET /geo/v1/internal/regions/{region_id}` | GetInternal | **internal-only** |

> Gateway internal-mux регистрация + 4 read-RPC project-scope EXEMPT — follow-on (`api-gateway-registrar`).

## authz invariant

Per-RPC `InternalIAMService.Check` энфорсится в цепочке интерсепторов **обоих** листенеров
(internal НЕ освобождён, `security.md`). См. [[../edges/geo-to-iam-check]].

## See also

[[geo-zone-service]] [[../resources/geo-region]] [[../edges/nlb-to-geo-region-validate]] [[../edges/geo-to-iam-check]]

#rpc #kacho-geo #geo #geography
