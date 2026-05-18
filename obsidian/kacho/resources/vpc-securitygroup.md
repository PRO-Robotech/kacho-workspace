---
title: SecurityGroup
aliases:
  - SecurityGroup (vpc)
  - vpc SecurityGroup
  - SG
category: resource
domain: vpc
id_prefix: enp
owner_table: kacho_vpc.security_groups
owner_db: kacho_vpc
folder_level: true
status: stable
related_rpc:
  - "[[rpc/vpc-securitygroup-service]]"
related_packages:
  - "[[packages/vpc-apps-kacho-api-securitygroup]]"
tags:
  - resource
  - kacho-vpc
  - securitygroup
---

# SecurityGroup

**Domain**: vpc
**ID prefix**: `enp` (общий VPC prefix)
**Owner table**: `kacho_vpc.security_groups`
**Folder-level**: yes (через Network → Folder)

## Fields

| Field | Type | Note |
|---|---|---|
| `id` | TEXT PK | |
| `project_id` | TEXT | |
| `network_id` | TEXT | FK → networks(id) ON DELETE RESTRICT |
| `name`, `description`, `labels` | | |
| `rules` | JSONB | список `{direction, ports, protocol, cidr|sg_id, ...}` |
| `default_for_network` | BOOL | если true — авто-присвоен default-SG на Network |
| `xmin` (Postgres system) | | OCC version-counter |

CHECK (0029): name + rules format.

## Default-SG flow (0010 optional SG network)

При Network Create — inline создаётся default SG (если `KACHO_VPC_DEFAULT_SG_INLINE=true`, по дефолту true). См. `kacho-vpc/internal/apps/kacho/api/network/doCreate`.

## OCC (xmin)

`Update` берёт `Get`-snapshot, передаёт `xmin::text`, `UPDATE ... WHERE xmin::text = $expected RETURNING ...`. 0 rows → `Aborted "security group was modified concurrently"`. Тест: `security_group_occ_integration_test.go`.

## FK

- `security_groups.network_id → networks(id) ON DELETE RESTRICT` (нельзя удалить Network, пока есть SG).

## Gotchas

- Cross-SG references (`rule.sg_id` ссылается на другой SG в той же Network) — валидируется на Update в пределах same DB.
- NIC → SG[] (many-to-many) — массив `network_interfaces.security_group_ids` JSONB.

## See also

[[../packages/vpc-apps-kacho-api-securitygroup]] [[../rpc/vpc-securitygroup-service]] [[vpc-network]] [[vpc-networkinterface]]

#resource #vpc #securitygroup
