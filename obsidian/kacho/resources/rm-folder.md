---
title: Folder
aliases:
  - Folder (rm)
  - rm Folder
category: resource
domain: resourcemanager
id_prefix: b1g
owner_table: kacho_rm.folders
owner_db: kacho_rm
folder_level: false
hierarchy: leaf-owner
parent: Cloud
status: stable
related_rpc:
  - "[[rpc/rm-folder-service]]"
related_packages:
  - "[[packages/proto-rm]]"
related_edges:
  - "[[edges/vpc-to-rm-folder-exists]]"
  - "[[edges/compute-to-rm-folder-check]]"
tags:
  - resource
  - kacho-rm
  - folder
  - leaf-owner
---

# Folder

**Domain**: resourcemanager (`kacho-resource-manager`)
**ID prefix**: `b1g` (shared с Cloud per `corelib/ids/ids.go`)
**Owner table**: `kacho_rm.folders`
**Parent**: Cloud
**Position**: **leaf-owner** в cross-service edge-графе — все доменные сервисы (vpc/compute/nlb) делают `Folder.Get` для validation, **Folder сам никуда не зовёт**.

## Fields

| Field | Type | Note |
|---|---|---|
| `id` | TEXT PK | |
| `cloud_id` | TEXT | FK → clouds(id) RESTRICT |
| `name` | TEXT | UNIQUE per cloud |
| `description`, `labels` | | |
| `created_at` | TIMESTAMP | |

## FK contract

- `folders.cloud_id → clouds(id)` RESTRICT (within `kacho_rm`).
- In-bound **cross-service** (нет FK — database-per-service): `vpc.networks.folder_id`, `vpc.addresses.folder_id`, `compute.instances.folder_id`, ... — все валидируются peer-API через `FolderService.Get` (см. [[../edges/vpc-to-rm-folder-exists]]).

## Dangling-ref policy

После `DeleteFolder` peer-сервисы могут продолжать ссылаться на удалённый `folder_id` — это by-design (database-per-service запрещает cross-DB cascade). Чтения деградируют graceful (Network → нет name folder'а на UI; не error). Cleanup — на оператора или future garbage-collector.

## See also

[[../packages/proto-rm]] [[../rpc/rm-folder-service]] [[../edges/vpc-to-rm-folder-exists]] [[../edges/compute-to-rm-folder-check]]

#resource #kacho-rm #folder #leaf-owner
