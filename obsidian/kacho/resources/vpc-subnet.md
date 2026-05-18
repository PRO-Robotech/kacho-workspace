---
title: Subnet
aliases:
  - Subnet (vpc)
  - vpc Subnet
category: resource
domain: vpc
id_prefix: e9b
owner_table: kacho_vpc.subnets
owner_db: kacho_vpc
folder_level: true
status: stable
related_rpc:
  - "[[rpc/vpc-subnet-service]]"
related_packages:
  - "[[packages/vpc-domain]]"
  - "[[packages/vpc-repo-kacho-pg]]"
tags:
  - resource
  - kacho-vpc
  - subnet
  - cidr
---

# Subnet

**Domain**: vpc
**ID prefix**: `e9b`
**Owner table**: `kacho_vpc.subnets`
**Folder-level**: yes (через Network → Folder)

## Fields (domain)

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `ids.IsValid("e9b")` | |
| `project_id` | TEXT | cross-service ref → rm.Folder | |
| `network_id` | TEXT | within-service FK → networks(id) | |
| `zone_id` | TEXT | cross-service ref → compute.Zone (KAC-15) | |
| `name`, `description`, `labels` | TEXT/JSONB | `validate.Name*` | |
| `v4_cidr_primary` | inet | CHECK (0026 → inline в baseline 0001) | optional (можно v6-only) |
| `v4_cidr_blocks` | inet[] | extra CIDRs (KAC-71) | |
| `v6_cidr_primary` | inet | CHECK (0026 → inline в baseline 0001) | optional |
| `v6_cidr_blocks` | inet[] | | |
| `route_table_id` | TEXT | within-service ref → route_tables | nullable, auto-association (0019/0020) |

## Constraints

- `subnets_pkey` PRIMARY KEY (id)
- `subnets_no_overlap_v4` EXCLUDE USING gist (network_id WITH =, v4_cidr_primary inet_ops WITH &&) — никаких пересечений в одной Network.
- `subnets_no_overlap_v6` аналогично для v6.
- Subnet CHECK (0026 → inline в baseline 0001): name+CIDR-формат.
- `subnets_network_id_fkey` (default — без CASCADE).

## FK contract (in-bound)

- `addresses.internal_subnet_id → subnets(id) ON DELETE RESTRICT`
- `network_interfaces.subnet_id → subnets(id) ON DELETE RESTRICT` (0012 → inline в baseline 0001)

→ Delete Subnet → FailedPrecondition если есть Address или NIC.

## Lifecycle

Single ACTIVE state.

## Gotchas

- При Create — EXCLUDE-constraint ловит overlap'ы (SQLSTATE 23P01) → mapped to `AlreadyExists`/`FailedPrecondition` (см. `helpers.go` mapErr).
- Subnet может быть v6-only (KAC-71); validation в [[../packages/vpc-domain]].


> [!note] После KAC-111 (squash migrations)
> Specific migration numbers (0001–0034) свёрнуты в single baseline `0001_initial.sql`.
> Ссылки на исторические migration N сохраняются как archeology, но физически их нет —
> весь финальный state в `internal/migrations/0001_initial.sql` (kacho-vpc PR #97).

## See also

[[../packages/vpc-domain]] [[../rpc/vpc-subnet-service]] [[vpc-network]]

#resource #vpc #subnet #cidr
