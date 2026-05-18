---
title: Project
aliases:
  - Project (iam)
  - iam Project
category: resource
domain: iam
id_prefix: prj
owner_table: kacho_iam.projects
owner_db: kacho_iam
folder_level: false
status: done
related_rpc:
  - "[[rpc/iam-project-service]]"
related_packages:
  - "[[packages/iam-domain]]"
  - "[[packages/iam-repo-kacho-pg]]"
related_tickets:
  - "[[KAC-105]]"
  - "[[KAC-112]]"
tags:
  - resource
  - kacho-iam
  - iam
---

# Project

**Domain**: iam (новый аналог Folder из `kacho-resource-manager`, но без промежуточного Cloud)
**ID prefix**: `prj` (20 chars)
**Owner table**: `kacho_iam.projects`
**Folder-level**: no (Project сам играет роль folder в новой модели; E1 переключит `folder_id → project_id` в vpc/compute/loadbalancer)
**Status (E0)**: backend в [[KAC-112]] (по pattern'у Account; на момент E0 squash — только domain+migrations+iface).

## Fields

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `ids.IsValid("prj")` | |
| `account_id` | TEXT | FK → accounts(id) RESTRICT | NOT NULL |
| `name` | TEXT | `^[a-z][-a-z0-9]{2,62}$` | UNIQUE (account_id, name) |
| `description` | TEXT | `<=256` chars | |
| `labels` | JSONB | `kacho_labels_valid` | |
| `created_at` | TIMESTAMPTZ | server-set | |

## Constraints / indexes

- `projects_pkey` PRIMARY KEY (id)
- `projects_account_fk` FK → `accounts(id)` ON DELETE RESTRICT
- `projects_account_name_unique` UNIQUE (account_id, name)
- CHECK: `projects_name_check`, `projects_description_check`, `projects_labels_valid`

## FK contract (in-bound — внутри `kacho_iam`)

- (E0): нет — `access_bindings.resource_id` ссылается software (полиморфно, без FK; см. [[iam-access-binding]]).
- (E1, [[KAC-106]]): VPC/Compute/Loadbalancer сменят `folder_id → project_id` (cross-service software ref, peer-validation через `ProjectService.Get`).

## Lifecycle

- **Create / Update / Delete** — все async через `Operation`.
- **Move** — спец-операция: атомарный UPDATE `account_id` с CAS-условием на текущий account_id; защита от race и UNIQUE-конфликта по new (account_id, name).

## Gotchas

- Move через границу Account → новый `(account_id, name)` должен быть свободен, иначе `AlreadyExists`.
- `account_id` immutable через обычный Update (`UpdateMask` rejects); меняется только через `Move`.
- E1 ([[KAC-106]]) переключит cross-service `folder_id` ссылки в kacho-vpc/compute/loadbalancer; до этого dangling-coexistence с `kacho-resource-manager.Folder` (см. [[../edges/vpc-to-iam-project-exists]]).

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[../rpc/iam-project-service]] [[../edges/vpc-to-iam-project-exists]] [[../KAC/KAC-105]] [[../KAC/KAC-112]]

#resource #kacho-iam #iam
