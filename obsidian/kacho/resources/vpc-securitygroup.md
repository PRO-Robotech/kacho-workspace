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

## Default-SG flow

При Network Create — inline создаётся default SG (если `KACHO_VPC_DEFAULT_SG_INLINE=true`, по дефолту true). См. `kacho-vpc/internal/apps/kacho/api/network/doCreate`.

## network_id — обязателен + immutable (KAC-243)

`network_id` **обязателен** при Create (`INVALID_ARGUMENT "network_id required"`) и **неизменяем** после: его нет в Update known-mask {name,description,labels,rule_specs} (в маске → `INVALID_ARGUMENT`); `Move` network-bound SG между проектами → `FAILED_PRECONDITION`. Причина: SG→SG-правила валидны только в пределах одной Network (SG в разных сетях физически не видят друг друга). Откат «optional network_id» (kacho-proto#8). Миграция `0004` (Go goose, transactional) backfill'ит orphan-SG в сеть `default` проекта перед `ALTER ... SET NOT NULL`.

## OCC (xmin) — только UpdateRules/UpdateRule

Общий `Update` (name/description/labels/rule_specs) — **без OCC** (bare `UPDATE ... WHERE id=$1`). xmin-OCC есть ТОЛЬКО в `UpdateRules`/`UpdateRule`: `UPDATE ... WHERE xmin::text=$expected`, 0 rows → `FAILED_PRECONDITION` (НЕ `Aborted` — маппится через `helpers.ErrFailedPrecondition`). Тест: `security_group_occ_integration_test.go`.

## FK

- `security_groups.network_id → networks(id) ON DELETE RESTRICT` (нельзя удалить Network, пока есть SG).

## Gotchas

- SG→SG-правило (`rule.security_group_id` → другая SG) валидно ТОЛЬКО если target-SG в той же Network (KAC-243): cross-network/несуществующая target → `INVALID_ARGUMENT` + `BadRequest.field_violations`. Проверяется на Create(rule_specs)/UpdateRules (service-layer; network_id immutable → не TOCTOU). До KAC-243 НЕ валидировалось (был stale-claim в этой заметке).
- NIC → SG[] (many-to-many) — массив `network_interfaces.security_group_ids` JSONB.

## See also

[[../packages/vpc-apps-kacho-api-securitygroup]] [[../rpc/vpc-securitygroup-service]] [[vpc-network]] [[vpc-networkinterface]]

#resource #vpc #securitygroup
