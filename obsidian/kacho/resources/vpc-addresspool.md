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
  - "[[rpc/vpc-internal-cloud-service]]"
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
**Owner table**: `kacho_vpc.address_pools` (+ `address_pool_network_default`, `address_pool_address_override`, `cloud_pool_selector`)
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
- `address_pool_address_override(address_id PK, pool_id FK)` — explicit pool для конкретного Address.
- `cloud_pool_selector(cloud_id PK, selector-json)` — cloud-level rule selector.

## Resolution chain (для tenant Address Create)

1. `address_pool_address_override` (per-Address) → если есть, use.
2. `address_pool_network_default` (per-Network).
3. `cloud_pool_selector` (per-Cloud, JSON predicate).
4. Default pool в zone (UNIQUE).

См. `InternalAddressPoolService.ExplainResolution` ([[../rpc/vpc-internal-address-pool-service]]).

## Allocate freelist (0015)

`FOR UPDATE SKIP LOCKED LIMIT 1` + `DELETE … RETURNING` — concurrent allocate без deadlock'ов. См. `address_pool_freelist_integration_test.go`.

## Gotchas

- Admin-only — все RPC на internal-listener.
- Split v4/v6 (0022) — нельзя mix family в одном pool.

## See also

[[../packages/vpc-apps-kacho-api-addresspool]] [[../rpc/vpc-internal-address-pool-service]] [[../rpc/vpc-internal-cloud-service]]

#resource #vpc #addresspool #admin #kacho-only
