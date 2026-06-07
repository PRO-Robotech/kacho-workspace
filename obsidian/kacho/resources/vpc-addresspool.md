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
| `v4_cidr_blocks`, `v6_cidr_blocks` | text[] | split по family (KAC-71). Меняются только через `:addCidrBlocks`/`:removeCidrBlocks` (KAC-269), НЕ через Update |
| `is_default` | BOOL | (zone, kind, is_default=true) UNIQUE |

## Constraints

- `address_pools_pkey` PRIMARY KEY (id)
- `address_pools_zone_kind_default_uniq` UNIQUE (COALESCE(zone_id, ''), kind) WHERE is_default — одного default-pool на (zone, kind).
- `address_pools_zone_id_fkey` → `zones(id)` ON DELETE RESTRICT (mirror table до KAC-15; будет removed).
- **CIDR overlap per kind ([[KAC-272]], миграция 0004)** — нормализованная child-таблица
  `address_pool_cidrs(pool_id FK ON DELETE CASCADE, kind smallint, block cidr, PK(pool_id,block))`
  + `EXCLUDE USING gist (kind WITH =, block inet_ops WITH &&)`. CIDR-блоки пулов одного `kind`
  не пересекаются — внутри пула И между пулами (cross-zone public CIDR глобально непересекающиеся
  → zone в exclusion-key НЕ входит). Иначе IPAM аллоцирует один external-IP дважды (per-pool UNIQUE
  `addresses_external_pool_ip_uniq` не ловит коллизию между разными pool_id). 23P01 →
  `FailedPrecondition` «address pool CIDRs can not overlap». Зеркалит `subnets_no_overlap_v4`.

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

### CIDR-управление (KAC-269)

`:addCidrBlocks` → `AddCidrToFreelist(pool, newV4)` — materialise free_ips только для новой
v4-дельты (idempotent ON CONFLICT). `:removeCidrBlocks` → `DeleteFreelistForCidrs` (row-lock)
+ `CountAllocatedInCidrs` use-guard в одной writer-TX (атомарность remove vs alloc). См.
`address_pool_cidr_blocks_integration_test.go`, [[../KAC/KAC-269]].

### CIDR overlap (KAC-272)

`Create` / `:addCidrBlocks` дополнительно нормализуют блоки в `address_pool_cidrs` (EXCLUDE gist)
в той же writer-TX — `InsertCidrBlocks(poolID, kind, v4, v6)`; пересечение per kind →
`FailedPrecondition` «address pool CIDRs can not overlap» (DB-level backstop, запрет #10). Sync
within-request precheck (`checkPoolCIDRsDisjoint`) → `InvalidArgument` тем же текстом.
`:removeCidrBlocks` → `DeleteCidrBlocks` освобождает диапазон. См.
`address_pool_overlap_integration_test.go`, [[KAC-272]].

## Gotchas

- Admin-only — все RPC на internal-listener.
- Split v4/v6 (0022) — нельзя mix family в одном pool.

## See also

[[../packages/vpc-apps-kacho-api-addresspool]] [[../rpc/vpc-internal-address-pool-service]]

#resource #vpc #addresspool #admin #kacho-only
