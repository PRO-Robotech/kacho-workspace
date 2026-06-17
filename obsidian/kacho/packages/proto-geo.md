---
title: proto-geo
category: package
repo: kacho-proto
layer: proto
status: in-progress
tags:
  - proto
  - kacho-geo
  - geo
  - geography
---

# proto/geo

**Path**: `kacho-proto/proto/kacho/cloud/geo/v1/`
**Package**: `kacho.cloud.geo.v1`
**Go import**: `github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/geo/v1` (`geov1`)
**Owner service**: `kacho-geo` (leaf-домен Geography, эпик #82).

## Resource protos

- `region.proto` — Region (id literal, name, created_at)
- `zone.proto` — Zone (id literal, region_id, status enum UP/DOWN/UNSPECIFIED, name, created_at)

## Service protos

- `region_service.proto` — `RegionService.Get/List` (public, **sync**)
- `zone_service.proto` — `ZoneService.Get/List` (public, **sync**)
- `internal_catalog_service.proto` — `InternalRegionService` / `InternalZoneService` admin-CRUD
  (Create/Update/Delete, возвращают ресурс **синхронно**, не `Operation` — catalog-паттерн).

## Происхождение (эпик #82)

Форма перенесена 1-в-1 из `compute.v1` (region/zone + 4 сервиса). На S1 добавление `geo.v1` —
additive (`buf breaking` зелёный); удаление geography из `compute.v1` отложено в S7 (намеренный
breaking, ПОСЛЕ перевода всех consumer'ов). Опечатки List-permission'ов `compute.{regionses,zoneses}.list`
исправлены на `geo.{regions,zones}.list`.

## Consumers (proto-stubs)

`kacho-compute` (Instance.zone_id), `kacho-vpc` (Subnet/AddressPool zone_id), `kacho-nlb`
(region_id), `kacho-api-gateway` (REST `/geo/v1/*`). См. [[../edges/compute-to-geo-zone-validate]]
[[../edges/vpc-to-geo-zone-validate]] [[../edges/nlb-to-geo-region-validate]].

## See also

[[geo-domain]] [[proto-compute]] [[../rpc/geo-region-service]] [[../rpc/geo-zone-service]]

#proto #kacho-geo #geo #geography
