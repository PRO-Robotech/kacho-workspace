---
title: vpc-apps-kacho-api-securitygroup
category: packages
repo: kacho-vpc
layer: use-case
tags:
  - packages
  - kacho-vpc
  - handler
  - securitygroup
  - occ
status: stable
verified_against: "каталог пакета есть в дереве продукта b4edc5d5 (2026-08-05); текст записки построчно не пересматривался"
---

# kacho-vpc/internal/apps/kacho/api/securitygroup

**Каталог**: `services/vpc/internal/apps/kacho/api/securitygroup/` — монорепо `PRO-Robotech/kacho` (прежде, в полирепо: `kacho-vpc/internal/apps/kacho/api/securitygroup/`)
**Implements**: [[../rpc/vpc-securitygroup-service|SecurityGroupService]]

## Files

| File | Содержание |
|---|---|
| `handler.go` | gRPC adapter |
| `iface.go` | ports |
| `helpers.go` | rule normalisation (sort, dedupe via [[vpc-repo-helpers]]) |
| `create.go` | network FK + initial rules validation |
| `update.go` | name/labels/desc/default_for_network — **OCC через xmin** |
| `update_rules.go` | bulk replace rules — OCC |
| `update_rule.go` | mutate single rule — OCC |
| `delete.go` | FailedPrecondition если SG в use на NIC |
| `get.go` | |
| `list.go` | |
| `move.go` | cross-folder |
| `usecase_test.go` | |

## OCC pattern

См. [[../rpc/vpc-securitygroup-service]] для деталей. Все Update'ы возвращают `Aborted` при concurrent-modify.

## See also

[[../rpc/vpc-securitygroup-service]] [[../resources/vpc-securitygroup]]

#packages #kacho-vpc #handler #securitygroup #occ
