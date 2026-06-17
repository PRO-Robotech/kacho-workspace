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
tags:
  - resource
  - kacho-geo
  - geo
  - geography
---

# Region

**Domain**: geo — platform-топология (leaf-домен `kacho-geo`, как iam). Глобальный
catalog-ресурс, не привязан к Project/Account (scope `cluster`).
**ID**: admin-assigned **литерал** (нет 3-char prefix), напр. `ru-central1`. Immutable после Create.
**Owner table**: `kacho_geo.regions`. Вынесен из `kacho_compute.regions` эпиком #82 (id сохранены 1-в-1).
**Visibility**: public read (`RegionService.Get/List` — sync) + admin-CRUD через `InternalRegionService` (:9091).

## Fields

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | admin-assigned литерал | immutable; напр. `ru-central1` |
| `name` | TEXT | human-readable | напр. `RU Central 1` |
| `created_at` | TIMESTAMPTZ | server-set | truncate-to-seconds |

## Constraints / invariants

- `regions_pkey` PRIMARY KEY (id).
- Регион с зонами **нельзя удалить** — FK RESTRICT со стороны `zones.region_id` (within-service
  инвариант на DB-уровне, ban #10). `InternalRegionService.Delete` при наличии зон → `FailedPrecondition`
  (SQLSTATE 23503).

## Cross-domain refs (consumer-side)

- `kacho-nlb` хранит `region_id` (TEXT, без cross-service FK), валидирует через `geo.v1.RegionService.Get`
  на request-path. См. [[../edges/nlb-to-geo-region-validate]].
- Удаление региона admin'ом не каскадит в consumer'ов — dangling-ref переживается грациозно на чтении.

## Lifecycle

Catalog-ресурс: admin создаёт/правит явным id через `Internal*` (синхронный ответ, не `Operation` —
catalog-паттерн, parity с `InternalDiskTypeService`). Tenant'ы только читают. Seed: `ru-central1`.

## See also

[[geo-zone]] [[../rpc/geo-region-service]] [[../edges/nlb-to-geo-region-validate]]

#resource #kacho-geo #geo #geography
