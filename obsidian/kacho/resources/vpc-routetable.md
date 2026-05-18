---
title: RouteTable
aliases:
  - RouteTable (vpc)
  - vpc RouteTable
category: resource
domain: vpc
id_prefix: enp
owner_table: kacho_vpc.route_tables
owner_db: kacho_vpc
folder_level: true
status: stable
related_rpc:
  - "[[rpc/vpc-routetable-service]]"
related_packages:
  - "[[packages/vpc-apps-kacho-api-routetable]]"
tags:
  - resource
  - kacho-vpc
  - routetable
---

# RouteTable

**Domain**: vpc
**ID prefix**: `enp` (общий VPC prefix)
**Owner table**: `kacho_vpc.route_tables`
**Folder-level**: yes (через Network → Folder)

## Fields

| Field | Type | Note |
|---|---|---|
| `id` | TEXT PK | |
| `project_id` | TEXT | |
| `network_id` | TEXT | FK → networks(id) |
| `name`, `description`, `labels` | | |
| `static_routes` | JSONB | список `{destination_prefix, next_hop_address|gateway_id}` |

CHECK (0028 → inline в baseline 0001): name + static_routes format.

## Auto-association с Subnet

Миграция 0019/0020: при создании Subnet — auto-associate с default RT той Network (если есть); поле `subnets.route_table_id`. Tenant может override через Subnet Update.

## FK

- `route_tables.network_id → networks(id)` (default — без cascade override).
- `subnets.route_table_id → route_tables(id)` SET NULL (auto-deassoc при delete).

## Gotchas

- Delete → FailedPrecondition если ассоциирован с Subnet (не NULL).
- `static_routes.gateway_id` валидируется на Update (within-service: gateway exists в same DB).


> [!note] После KAC-111 (squash migrations)
> Specific migration numbers (0001–0034) свёрнуты в single baseline `0001_initial.sql`.
> Ссылки на исторические migration N сохраняются как archeology, но физически их нет —
> весь финальный state в `internal/migrations/0001_initial.sql` (kacho-vpc PR #97).

## See also

[[../packages/vpc-apps-kacho-api-routetable]] [[../rpc/vpc-routetable-service]] [[vpc-network]] [[vpc-gateway]]

#resource #vpc #routetable
