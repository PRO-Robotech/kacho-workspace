---
title: Address
aliases:
  - Address (vpc)
  - vpc Address
category: resource
domain: vpc
id_prefix: e9b
owner_table: kacho_vpc.addresses
owner_db: kacho_vpc
folder_level: true
status: stable
related_rpc:
  - "[[rpc/vpc-address-service]]"
  - "[[rpc/vpc-internal-address-service]]"
related_packages:
  - "[[packages/vpc-apps-kacho-api-address]]"
  - "[[packages/vpc-apps-kacho-services-addressref]]"
tags:
  - resource
  - kacho-vpc
  - address
  - ipam
---

# Address

**Domain**: vpc
**ID prefix**: `e9b` (общий с Subnet — см. CLAUDE.md)
**Owner table**: `kacho_vpc.addresses`
**Folder-level**: yes

## Fields (domain — упрощено)

| Field | Type | Note |
|---|---|---|
| `id` | TEXT PK | |
| `project_id` | TEXT | |
| `name`, `description`, `labels` | TEXT/JSONB | |
| `external_ipv4` | JSONB `{address, address_pool_id}` | nullable; v4 public |
| `internal_ipv4` | JSONB `{address, subnet_id}` | nullable |
| `internal_ipv6` | JSONB `{address, subnet_id}` | nullable (0009/0013) |
| `external_ipv6` | JSONB | nullable (0021 → inline в baseline 0001) |
| `internal_subnet_id` | TEXT | derived (FK target) |
| `used_by` | TEXT, kind+id | `SetAddressReference`/`ClearAddressReference` |
| `is_ephemeral` | BOOL | true = released after `used_by` clear |
| `reserved` | BOOL | tenant-controlled |

CHECK (0027 → inline в baseline 0001): хотя бы один из `external_ipv4`/`internal_ipv4`/`internal_ipv6` не пуст.

## Constraints (uniqueness, partial)

- `addresses_external_ip_uniq` — partial UNIQUE на (external_ipv4->>address) WHERE … <> '' — один IP может принадлежать одному Address.
- `addresses_external_pool_ip_uniq` — UNIQUE (pool_id, ip).
- `addresses_internal_subnet_ip_uniq` — UNIQUE (subnet_id, ip).
- `addresses_internal_subnet_fkey` — `internal_subnet_id → subnets(id) ON DELETE RESTRICT`.

## IPAM lifecycle

1. Tenant Create → `external_ipv4` from AddressPool (CAS-allocate из free-list, historical migration 0015 (свёрнуто в baseline 0001 — KAC-111)).
2. Compute NIC bind → `InternalAddressService.SetAddressReference(address_id, used_by={kind=instance, id=...})` — CAS на `used_by` пустой/наш.
3. Detach → `ClearAddressReference` → если `is_ephemeral=true` → row deleted.
4. Tenant Delete → FailedPrecondition если `used_by != ''`.

## Gotchas

- `used_by` — CAS, software-check **запрещён** (см. CLAUDE.md «Запреты» #10 и within-service refs).
- Address pool freelist (0015 → inline в baseline 0001) — `FOR UPDATE SKIP LOCKED LIMIT 1` для concurrent allocate.
- Split v4/v6 pools (0022, KAC-71).


> [!note] После KAC-111 (squash migrations)
> Specific migration numbers (0001–0034) свёрнуты в single baseline `0001_initial.sql`.
> Ссылки на исторические migration N сохраняются как archeology, но физически их нет —
> весь финальный state в `internal/migrations/0001_initial.sql` (kacho-vpc PR #97).

## See also

[[../packages/vpc-apps-kacho-api-address]] [[../packages/vpc-apps-kacho-services-addressref]] [[../rpc/vpc-address-service]] [[../rpc/vpc-internal-address-service]]

#resource #vpc #address #ipam
