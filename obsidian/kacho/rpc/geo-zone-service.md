---
title: ZoneService
aliases:
  - ZoneService (geo)
  - InternalZoneService (geo)
proto_file: kacho/cloud/geo/v1/zone_service.proto
category: rpc
backend: kacho-geo
backend_port: 9090
visibility: public
domain: geo
related_resource: "[[resources/geo-zone]]"
methods_count: 5
async_methods: 0
status: in-progress
tags:
  - rpc
  - kacho-geo
  - geo
  - geography
---

# ZoneService + InternalZoneService (geo)

**Proto**: `kacho-proto/proto/kacho/cloud/geo/v1/zone_service.proto` (public) +
`internal_catalog_service.proto` (`InternalZoneService`, admin).
**Backend**: `kacho-geo:9090` (public read) · `kacho-geo:9091` (Internal admin).
**Domain**: geo (вынесен из `compute.v1` эпиком #82). **Catalog-паттерн**: read-only public + admin-CRUD,
все методы **sync** (admin-мутации возвращают ресурс синхронно, НЕ `Operation`).

## Public methods (ZoneService, :9090)

| Method | Request | Response | Sync/Async | authz |
|---|---|---|---|---|
| Get | GetZoneRequest | Zone | sync | `geo.zones.get` (viewer/`system_viewer`-floor) |
| List | ListZonesRequest | ListZonesResponse | sync | `geo.zones.list` (viewer-floor); фильтр `region_id` |

## Admin methods (InternalZoneService, :9091)

| Method | Request | Response | Sync/Async | authz |
|---|---|---|---|---|
| Create | CreateZoneRequest | Zone | sync | `geo.zones.create` (`system_admin`); несуществующий `region_id` → FailedPrecondition (FK 23503) |
| Update | UpdateZoneRequest | Zone | sync | `geo.zones.update` (`system_admin`) |
| Delete | DeleteZoneRequest | (Delete resp) | sync | `geo.zones.delete` (`system_admin`) |

## REST mapping

| HTTP | Method | mux |
|---|---|---|
| `GET /geo/v1/zones/{zone_id}` | Get | public |
| `GET /geo/v1/zones` | List | public |
| `POST /geo/v1/zones` | Create | **internal-only** (:9091, ban #6) |
| `PATCH /geo/v1/zones/{zone_id}` | Update | **internal-only** |
| `DELETE /geo/v1/zones/{zone_id}` | Delete | **internal-only** |

> Прежние `/compute/v1/zones` удалены. Опечатка `compute.zoneses.list` исправлена на
> `geo.zones.list` при extract (эпик #82, scenario 6.0-01).

## authz invariant

Per-RPC `InternalIAMService.Check` энфорсится на **обоих** листенерах (internal НЕ освобождён,
`security.md`). См. [[../edges/geo-to-iam-check]].

## See also

[[geo-region-service]] [[../resources/geo-zone]] [[../edges/vpc-to-geo-zone-validate]] [[../edges/compute-to-geo-zone-validate]] [[../edges/geo-to-iam-check]]

#rpc #kacho-geo #geo #geography
