---
title: Zone
aliases:
  - Zone (geo)
  - geo Zone
category: resource
domain: geo
id_prefix: none
owner_table: kacho_geo.zones
owner_db: kacho_geo
folder_level: false
status: in-progress
related_rpc:
  - "[[rpc/geo-zone-service]]"
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

# Zone

**Domain**: geo — placement-координата (ZONAL) внутри Region (leaf-домен `kacho-geo`).
Cluster-scoped catalog, не привязан к Project/Account.
**ID**: admin-assigned **slug** (THE ONE carve-out из 3-char-prefix+crockford-base32), напр.
`ru-central1-a`. Immutable. **Coupling** `zone.id == regionId + "-" + <zoneSuffix>` (строго
`startsWith(regionId+"-")`; контрпример `ru-central10-a` под `ru-central1` → REJECT).
**Visibility**: public read (`ZoneService.Get/List` — sync) + admin-CRUD/infra через
`InternalZoneService` (:9091).

## Two-projection (GEO-1)

Публичный `Zone` (lean) и `InternalZone` (full) — **РАЗНЫЕ proto-messages**. Сырой `status`
и весь `infra°` физически существуют ТОЛЬКО в internal-message (security.md two-projection;
удаление public `status` — намеренный breaking).

| Проекция | Поля |
|---|---|
| **public `Zone`** | `id`, `region_id`, `name`, `open_for_placement°`, `placement_blocked_reason°`, `created_at°` |
| **`InternalZone`** (:9091) | `id`, `region_id`, `name`, `status` (GeoStatus UP/DOWN), `infra°`{`numeric_infra_id`(immut), `host_classes`, `failure_domain_count`, `underlay_anchor`, `capacity_hint`}, `created_at°` |

- `open_for_placement° = zone.status==UP && region.status==UP` (derived, JOIN на region).
- `placement_blocked_reason° ∈ {NONE,ZONE_DOWN,REGION_DOWN}` (только на Zone; precedence
  zone-down → ZONE_DOWN, иначе region-down → REGION_DOWN).
- `placementType°` НЕ эмитится (ось derived-by-service).

## Constraints / invariants (DB-level, ban #10)

- `zones_pkey` PK (slug id).
- `zones.region_id` **FK → `regions(id)` ON DELETE RESTRICT** (несуществующий регион при Create →
  FK 23503; регион с зонами удалить нельзя).
- `zones_name_key` **UNIQUE(name)** глобально; `name` NOT NULL required (dup → 23505 → AlreadyExists).
- `zones_status_check` CHECK(status IN ('UP','DOWN')); fresh-default **`status DEFAULT 'DOWN'`** (fail-safe).
- `numeric_infra_id` immutable после Create (update_mask reject).

## Lifecycle (GEO-1)

Admin создаёт явным slug через `InternalZoneService.Create` → **синхронно-завершённый
`Operation{done:true, metadata:{zoneId + warnings°}, response:public Zone}`** (config-INSERT,
без саги). Fresh zone поднимается **DOWN**; тихий no-op сделан громким через `warnings°` в
`CreateZoneMetadata` (geo-owned, НЕ в public response). Admin явно открывает `Update status=UP`.
`regionId` immutable (путь удалён). Tenant'ы только читают каталог.

## Cross-domain refs (consumer-side, без cross-service FK)

- `kacho-compute` `Instance.zone_id`/`disks.zone_id`, `kacho-vpc` `Subnet.zone_id` — TEXT,
  валидируются `geo.v1.ZoneService.Get` (existence). Consumer-side placement-gate на
  `open_for_placement°` — отдельные под-фазы (out-of-scope GEO-1).
- См. [[../edges/compute-to-geo-zone-validate]] · [[../edges/vpc-to-geo-zone-validate]].

## See also

[[geo-region]] [[../rpc/geo-zone-service]] [[KAC/GEO-1]]

#resource #kacho-geo #geo #geography
