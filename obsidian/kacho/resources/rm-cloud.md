---
title: Cloud
aliases:
  - Cloud (rm)
  - rm Cloud
category: resource
domain: resourcemanager
id_prefix: b1g
owner_table: kacho_rm.clouds
owner_db: kacho_rm
folder_level: false
hierarchy: mid
parent: Organization
status: stable
related_rpc:
  - "[[rpc/rm-cloud-service]]"
related_packages:
  - "[[packages/proto-rm]]"
tags:
  - resource
  - kacho-rm
  - cloud
---

# Cloud

**Domain**: resourcemanager (`kacho-resource-manager`)
**ID prefix**: `b1g`
**Owner table**: `kacho_rm.clouds`
**Parent**: Organization

## Fields

| Field | Type | Note |
|---|---|---|
| `id` | TEXT PK | `b1g<…>` |
| `organization_id` | TEXT | FK → organizations(id) RESTRICT |
| `name` | TEXT | UNIQUE per organization |
| `description`, `labels` | | |
| `created_at` | TIMESTAMP | |

## FK contract

- `clouds.organization_id → organizations(id)` RESTRICT (within `kacho_rm`).
- In-bound: `folders.cloud_id → clouds(id)` RESTRICT.

→ Delete Cloud → FailedPrecondition если есть Folder.

## See also

[[../packages/proto-rm]] [[../rpc/rm-cloud-service]] [[rm-folder]] [[rm-organization]]

#resource #kacho-rm #cloud
