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
tags:
  - resource
  - kacho-geo
  - geo
  - geography
---

# Zone

**Domain**: geo — availability-zone внутри Region (leaf-домен `kacho-geo`). Глобальный
catalog-ресурс, scope `cluster`, не привязан к Project/Account.
**ID**: admin-assigned **литерал** (нет 3-char prefix), напр. `ru-central1-a`. Immutable после Create.
**Owner table**: `kacho_geo.zones`. Вынесен из `kacho_compute.zones` эпиком #82 (id сохранены 1-в-1).
**Visibility**: public read (`ZoneService.Get/List` — sync) + admin-CRUD через `InternalZoneService` (:9091).

## Fields

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | admin-assigned литерал | immutable; напр. `ru-central1-a` |
| `region_id` | TEXT FK | → `regions(id)` ON DELETE RESTRICT | зона принадлежит региону |
| `status` | TEXT (enum) | `STATUS_UNSPECIFIED` / `UP` / `DOWN` | плоское enum-поле |
| `name` | TEXT | human-readable | |
| `created_at` | TIMESTAMPTZ | server-set | truncate-to-seconds |

## Constraints / invariants

- `zones_pkey` PRIMARY KEY (id).
- `zones.region_id` **FK → `regions(id)` ON DELETE RESTRICT** — несуществующий регион при Create →
  `FailedPrecondition` (23503); регион с зонами удалить нельзя. Within-service инвариант на DB-уровне (ban #10).

## Cross-domain refs (consumer-side, без cross-service FK)

- `kacho-compute`: `Instance.zone_id`, `disks.zone_id` — TEXT, валидируются через `geo.v1.ZoneService.Get`.
- `kacho-vpc`: `Subnet.zone_id`, `address_pools.zone_id` (empty = global) — валидируются через geo.
- Удаление зоны admin'ом не каскадит в consumer'ов; dangling-ref на чтении переживается грациозно
  (Get существующего ресурса → OK, новый Create в удалённой зоне → InvalidArgument).
- См. [[../edges/compute-to-geo-zone-validate]] · [[../edges/vpc-to-geo-zone-validate]].

## Lifecycle

Catalog-ресурс: admin создаёт явным id через `Internal*` (синхронный ответ, не `Operation`). Tenant'ы
только читают. Seed: `ru-central1-{a,b,d}` (status `UP`).

## See also

[[geo-region]] [[../rpc/geo-zone-service]] [[../edges/vpc-to-geo-zone-validate]] [[../edges/compute-to-geo-zone-validate]]

#resource #kacho-geo #geo #geography
