---
title: Listener
aliases:
  - Listener (nlb)
  - nlb Listener
category: resource
domain: nlb
id_prefix: lst
owner_table: kacho_nlb.listeners
owner_db: kacho_nlb
folder_level: true
status: stable
related_rpc:
  - "[[rpc/nlb-listener-service]]"
related_packages:
  - "[[packages/nlb-domain]]"
  - "[[packages/nlb-apps-kacho-api-listener]]"
tags:
  - resource
  - kacho-nlb
  - listener
---

# Listener (nlb)

**Domain**: nlb
**ID prefix**: `lst`
**Owner table**: `kacho_nlb.listeners`
**Folder-level**: yes (через LB → Project)

## Fields (domain)

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `ids.IsValid("lst")` | |
| `load_balancer_id` | TEXT NOT NULL | within-service FK → load_balancers(id) RESTRICT | **immutable** |
| `project_id` / `region_id` | TEXT | denorm from LB | для keyset + VIP UNIQUE |
| `name` | TEXT | DNS-1123 regex | partial UNIQUE per LB |
| `protocol` | TEXT | `TCP` \| `UDP` | **immutable** |
| `port`, `target_port` | INT | `1..65535` | port **immutable** |
| `ip_version` | TEXT | `IPV4` \| `IPV6` | **immutable** |
| `address_id` | TEXT | cross-service ref → vpc.Address (BYO) | **immutable**, опционально |
| `allocated_address` | TEXT | резолвленный VIP string | для UNIQUE region/vip/port/proto |
| `subnet_id` | TEXT | cross-service ref → vpc.Subnet (INTERNAL only) | required для INTERNAL LB |
| `proxy_protocol_v2` | BOOL | default `false` | mutable |
| `default_target_group_id` | TEXT | within-service soft-ref | mutable |
| `status` | TEXT | `CREATING/ACTIVE/UPDATING/DELETING` | enum CHECK |

## Constraints / indexes

- PK + FK `load_balancer_id` RESTRICT
- UNIQUE `(load_balancer_id, port, protocol)` (GWT-DB-006)
- Partial UNIQUE `(load_balancer_id, name) WHERE name <> ''`
- Partial UNIQUE `(region_id, allocated_address, port, protocol) WHERE status<>'DELETING' AND allocated_address<>''` (GWT-DB-007 — VIP uniqueness)
- Keyset `(project_id, created_at DESC, id)`
- GIN `labels_gin`
- Trigger `listeners_lb_status_recompute_trg` → пересчёт `LB.status` после INSERT/UPDATE/DELETE

## VIP allocation flow

См. [[../edges/nlb-to-vpc-vip-allocation]] и [[../edges/nlb-to-vpc-byo-address]]. Два режима:

- **Auto**: worker зовёт `vpc.InternalAddressService.AllocateExternalIP/AllocateInternalIP(owner=nlb_listener:<id>)`, получает IP-string → `allocated_address`.
- **BYO**: client передаёт `address_id` → worker: `AddressService.Get` (same project + used_by пустой OR ours) → `InternalAddressService.SetReference(used_by=nlb_listener:<id>)` atomic CAS.

Compensation: defer `vpc.FreeIP` если repo.Insert упал после allocate.

## Immutability rules

`load_balancer_id`, `protocol`, `port`, `ip_version`, `address_id` — InvalidArgument при попытке Update. Mutable: `name`, `description`, `labels`, `target_port`, `default_target_group_id`, `proxy_protocol_v2`.

## Lifecycle

`CREATING → ACTIVE → (UPDATING → ACTIVE)* → DELETING`. Delete освобождает VIP (free pool или clear BYO `used_by`).

## Gotchas

- VIP UNIQUE — region/vip/port/proto: два листенера на одном VIP допустимы только если порт/proto разные.
- INTERNAL LB обязан иметь `subnet_id` (InvalidArgument иначе).

## See also

[[../packages/nlb-apps-kacho-api-listener]] [[../rpc/nlb-listener-service]] [[nlb-load-balancer]] [[../edges/nlb-to-vpc-vip-allocation]] [[../edges/nlb-to-vpc-byo-address]]

#resource #kacho-nlb #listener
