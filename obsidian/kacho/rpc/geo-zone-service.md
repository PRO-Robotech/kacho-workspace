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
methods_count: 9
async_methods: 0
status: in-progress
related_tickets:
  - "[[KAC/GEO-1]]"
  - "[[KAC/issue-3092]]"
tags:
  - rpc
  - kacho-geo
  - geo
  - geography
verified_against: "kacho 1266@0ca889983ee4 (git fetch 2026-10-10): перечень RPC и путей REST сверен с proto/kacho/cloud/geo/v1/zone_service.proto и internal_catalog_service.proto в обе стороны (git show); регистрация на крае — gateway/internal/restmux/mux.go (git show), allowlist — gateway/internal/allowlist/list.go; в main публичных мутаций нет; поля запросов и семантика построчно не пересматривались"
---

# ZoneService + InternalZoneService (geo)

**Proto**: `proto/kacho/cloud/geo/v1/zone_service.proto` (public) +
`internal_catalog_service.proto` (`InternalZoneService`, admin).
**Backend**: `kacho-geo:9090` (public read) · `kacho-geo:9091` (Internal admin).
**Domain**: geo. **Catalog-паттерн (GEO-1 two-projection)**: public read отдаёт **lean**
`Zone` (без status/infra); admin-мутации возвращают **синхронно-завершённый
`Operation{done:true}`** (config-INSERT, unwrap `.response` = public Zone); `GetInternal` отдаёт
**full** `InternalZone` (status + infra°).

## Public methods (ZoneService, :9090) — lean projection

| Method | Request | Response | Sync/Async | authz |
|---|---|---|---|---|
| Get | GetZoneRequest | Zone (lean) | sync | `geo.zones.get` (→ GEO-1: project-scope EXEMPT, follow-on) |
| List | ListZonesRequest | ListZonesResponse | sync | фильтры `region_id`, `open_for_placement` |
| Create | CreatePublicZoneRequest | Operation | — | `system_admin` на кластере, порог уверенности как у внутреннего близнеца (ADM-1, [[KAC/issue-3092]]) |
| Update | UpdatePublicZoneRequest | Operation | — | то же |
| Delete | DeleteZoneRequest | Operation | — | то же |

> [!note] Публичные мутации — в ветке эпика `1266`, в `main` их нет
> Внесены [[KAC/issue-3092]] (третья сборка волны-6, kacho#3104). Инфраструктурного блока публичный вход
> не несёт: полная плоскость с инфраструктурой и `GetInternal` остаются у внутреннего близнеца.

## Admin methods (InternalZoneService, :9091)

| Method | Request | Response | Sync/Async | authz |
|---|---|---|---|---|
| Create | CreateZoneRequest (status/infra/coupling) | Operation{done:true, response:Zone, metadata:warnings°} | sync-done | `system_admin`; absent `region_id` → FK 23503 FailedPrecondition [PHASE-0-GATED] |
| Update | UpdateZoneRequest (FieldMask; region_id immutable) | Operation{done:true} | sync-done | `system_admin`; numericInfraId immutable |
| Delete | DeleteZoneRequest | Operation{done:true, response:Empty} | sync-done | `system_admin` |
| GetInternal | GetInternalZoneRequest | InternalZone (status + infra°) | sync | `system_admin` |

## REST mapping (internal path self-describing)

| HTTP | Method | mux |
|---|---|---|
| `GET /geo/v1/zones/{zone_id}` | Get | public |
| `GET /geo/v1/zones` | List | public |
| `POST /geo/v1/zones` | Create | public (ADM-1, #3092) |
| `PATCH /geo/v1/zones/{zone_id}` | Update | public (ADM-1, #3092) |
| `DELETE /geo/v1/zones/{zone_id}` | Delete | public (ADM-1, #3092) |
| `POST /geo/v1/internal/zones` | Create | **internal-only** (:9091, ban #6) |
| `PATCH /geo/v1/internal/zones/{zone_id}` | Update | **internal-only** |
| `DELETE /geo/v1/internal/zones/{zone_id}` | Delete | **internal-only** |
| `GET /geo/v1/internal/zones/{zone_id}` | GetInternal | **internal-only** |

> Край регистрирует внутренних близнецов только на внутреннем REST-слушателе (`gateway/internal/restmux/mux.go`,
> сверено @`0ca889983ee4`); на внешнем эти пути не смонтированы.

## authz invariant

Per-RPC `InternalIAMService.Check` энфорсится на **обоих** листенерах (internal НЕ освобождён,
`security.md`). См. [[../edges/geo-to-iam-check]].

## History

- 2026-10-10 — публичные Create/Update/Delete (ZoneService) по ADM-1: [[KAC/issue-3092]], kacho#3104 → `1266` @`ad74c3ea01b5`; снято устаревшее «регистрация внутренних путей на крае — follow-on» (регистрация есть).

## See also

[[geo-region-service]] [[../resources/geo-zone]] [[../edges/vpc-to-geo-zone-validate]] [[../edges/compute-to-geo-zone-validate]] [[../edges/geo-to-iam-check]]

#rpc #kacho-geo #geo #geography
