---
title: Region
aliases:
  - Region (geo)
  - geo Region
category: resource
domain: geo
id_prefix: none
owner_table: kacho_geo.regions
owner_db: kacho_geo
folder_level: false
status: in-progress
related_rpc:
  - "[[rpc/geo-region-service]]"
related_packages:
  - "[[packages/geo-domain]]"
related_tickets:
  - "[[KAC/EPIC-geo-extraction]]"
  - "[[KAC/GEO-1]]"
tags:
  - resource
  - kacho-geo
  - geo
  - geography
---

# Region

**Domain**: geo — placement-координата (REGIONAL/anycast), leaf-домен `kacho-geo`.
Cluster-scoped catalog, не привязан к Project/Account.
**ID**: admin-assigned **slug** (carve-out), напр. `ru-central1`. Immutable.
**Visibility**: public read (`RegionService.Get/List` — sync) + admin-CRUD/infra через
`InternalRegionService` (:9091).

## Two-projection (GEO-1)

Публичный `Region` (lean) и `InternalRegion` (full) — **РАЗНЫЕ proto-messages**. Сырой `status`
и `infra°` — только в internal-message.

| Проекция | Поля |
|---|---|
| **public `Region`** | `id`, `name`, `country_code°` (ISO-3166 alpha-2), `open_for_placement°`, `open_zone_count_hint°`, `created_at°` |
| **`InternalRegion`** (:9091) | `id`, `name`, `country_code`, `status` (GeoStatus), `infra°`{`numeric_infra_id`(immut), `capacity_hint`(rollup)}, `created_at°` |

- `open_for_placement° = status==UP` (Region: если false — причина ВСЕГДА REGION_DOWN by
  construction ⇒ нет `placement_blocked_reason°` на Region).
- `open_zone_count_hint°` — **advisory read-time COUNT** зон с `open_for_placement°=true` (НЕ
  persisted; authoritative = `ZoneService.List?openForPlacement=true`).
- `placementType°` НЕ эмитится.

## Constraints / invariants (DB-level, ban #10)

- `regions_pkey` PK (slug id).
- `regions_name_key` **UNIQUE(name)** глобально; `name` NOT NULL required (dup → 23505).
- `regions_status_check` CHECK(status IN ('UP','DOWN')); fresh-default **`status DEFAULT 'DOWN'`** (fail-safe).
- `numeric_infra_id` immutable после Create.
- Delete-инвариант: регион с зонами удалить нельзя (FK RESTRICT `zones.region_id`) →
  `FAILED_PRECONDITION "region <id> is not empty"`.

## Lifecycle (GEO-1)

Admin создаёт slug через `InternalRegionService.Create` → **`Operation{done:true, metadata:{regionId
+ warnings°}, response:public Region}`** (config-INSERT, sync). Fresh region **DOWN**; громкий
`warnings°` в `CreateRegionMetadata`. `countryCode` LIVE-mutable (валидируется на Create/Update).

## Cross-domain refs

- `kacho-nlb` `LoadBalancer.region_id` (валидируется `geo.v1.RegionService.Get`). См.
  [[../edges/nlb-to-geo-region-validate]] (consumer-side gate — отдельная под-фаза).

## See also

[[geo-zone]] [[../rpc/geo-region-service]] [[KAC/GEO-1]]

#resource #kacho-geo #geo #geography
