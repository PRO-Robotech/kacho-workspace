---
title: Network
aliases:
  - Network (vpc)
  - vpc Network
category: resource
domain: vpc
id_prefix: enp
owner_table: kacho_vpc.networks
owner_db: kacho_vpc
folder_level: true
status: stable
related_rpc:
  - "[[rpc/vpc-network-service]]"
  - "[[rpc/vpc-internal-network-service]]"
related_packages:
  - "[[packages/vpc-domain]]"
  - "[[packages/vpc-repo-kacho-pg]]"
tags:
  - resource
  - kacho-vpc
  - network
---

# Network

**Domain**: vpc
**ID prefix**: `enp`
**Owner table**: `kacho_vpc.networks` (database `kacho_vpc`)
**Folder-level**: yes (per-folder unique name)

## Fields (domain)

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `ids.IsValid("enp")` | |
| `project_id` | TEXT | cross-service ref → rm.Folder | dangling-ref грациозен |
| `name` | TEXT | `validate.NameVPC` (regex) | UNIQUE (project_id, name) |
| `description` | TEXT | `<=256` chars | |
| `labels` | JSONB | `validate.Labels` (`<=64` pairs) | CHECK constraint (0025 → inline в baseline 0001) |
| `created_at` | TIMESTAMP | server-set | truncated to seconds (YC parity) |
| `default_security_group_id` | TEXT | nullable | `InternalNetworkService.SetDefaultSecurityGroupId` |

(Бывшее поле `vpn_id` — часть kube-ovn-эпохи data-plane-модели — **удалено** historical migration 0023 (свёрнуто в baseline 0001 — KAC-111), эпики KAC-36/79/80.)

## Constraints / indexes

- `networks_pkey` PRIMARY KEY (id)
- `networks_project_id_name_key` UNIQUE (project_id, name)
- Labels CHECK (0025 → inline в baseline 0001)
- Name CHECK (0025 → inline в baseline 0001)

## FK contract (in-bound: что ссылается на Network)

- `subnets.network_id → networks(id)` (default — без cascade override)
- `route_tables.network_id → networks(id)` (default)
- `security_groups.network_id → networks(id) ON DELETE RESTRICT`
- `address_pool_network_default.network_id → networks(id) ON DELETE CASCADE`

→ Delete Network → `FailedPrecondition "network is not empty"` если есть Subnet/RT/SG (FK без CASCADE).

## Lifecycle

Single state — нет `status` enum'а (после kube-ovn нет провизионинг-стадии). Сразу ACTIVE после `Create`.

## Gotchas

- `default_security_group_id` управляется через [[../rpc/vpc-internal-network-service]] (admin); tenant не может менять напрямую.
- При cross-folder Move — project_id меняется атомарно single-statement UPDATE; UNIQUE (project_id, name) ловит конфликт.


> [!note] После KAC-111 (squash migrations)
> Specific migration numbers (0001–0034) свёрнуты в single baseline `0001_initial.sql`.
> Ссылки на исторические migration N сохраняются как archeology, но физически их нет —
> весь финальный state в `internal/migrations/0001_initial.sql` (kacho-vpc PR #97).

## See also

[[../packages/vpc-domain]] [[../packages/vpc-repo-kacho-pg]] [[../rpc/vpc-network-service]] [[../rpc/vpc-internal-network-service]]

#resource #vpc #network
