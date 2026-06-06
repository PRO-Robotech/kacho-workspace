---
title: AddressPool
aliases:
  - AddressPool (vpc)
  - vpc AddressPool
category: resource
domain: vpc
id_prefix: apl
owner_table: kacho_vpc.address_pools
owner_db: kacho_vpc
folder_level: false
visibility: internal
status: stable
related_rpc:
  - "[[rpc/vpc-internal-address-pool-service]]"
related_packages:
  - "[[packages/vpc-apps-kacho-api-addresspool]]"
tags:
  - resource
  - kacho-vpc
  - addresspool
  - admin
  - kacho-only
---

# AddressPool

**Domain**: vpc (kacho-only — нет в YC)
**ID prefix**: `apl`
**Owner table**: `kacho_vpc.address_pools` (+ `address_pool_network_default`)
**Folder-level**: нет (cloud/zone-level admin ресурс)

## Fields

| Field | Type | Note |
|---|---|---|
| `id` | TEXT PK | |
| `name`, `description`, `labels` | | |
| `kind` | enum | `internal_v4`, `external_v4`, `external_v6`, … (split family 0022 KAC-71) |
| `zone_id` | TEXT | nullable; cross-zone pool — NULL |
| `cidr_blocks` | inet[] | список CIDR-ов в pool |
| `is_default` | BOOL | (zone, kind, is_default=true) UNIQUE |

## Constraints

- `address_pools_pkey` PRIMARY KEY (id)
- `address_pools_zone_kind_default_uniq` UNIQUE (COALESCE(zone_id, ''), kind) WHERE is_default — одного default-pool на (zone, kind).
- `address_pools_zone_id_fkey` → `zones(id)` ON DELETE RESTRICT (mirror table до KAC-15; будет removed).

## Bindings tables

- `address_pool_network_default(network_id PK, pool_id FK)` — override default-pool для Network.

> [!note] Упрощено в [[KAC-266]]
> Таблицы `address_pool_address_override` (per-Address override) и `cloud_pool_selector`
> (cloud-level selector) и соответствующие RPC удалены. IPAM-cascade сведён к трём шагам.

## Resolution chain (для tenant Address Create)

После [[KAC-266]] cascade упрощён до трёх шагов (override/selector сняты):

1. `network_default` — `address_pool_network_default` (per-Network).
2. `zone_default` — default pool в zone (UNIQUE по (zone, kind)).
3. `global_default` — default pool без zone (zone_id NULL).

## Allocate freelist (0015)

`FOR UPDATE SKIP LOCKED LIMIT 1` + `DELETE … RETURNING` — concurrent allocate без deadlock'ов. См. `address_pool_freelist_integration_test.go`.

## Gotchas

- Admin-only — все RPC на internal-listener.
- Split v4/v6 (0022) — нельзя mix family в одном pool.

## See also

[[../packages/vpc-apps-kacho-api-addresspool]] [[../rpc/vpc-internal-address-pool-service]]

#resource #vpc #addresspool #admin #kacho-only
