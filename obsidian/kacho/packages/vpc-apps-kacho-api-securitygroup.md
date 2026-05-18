---
title: vpc-apps-kacho-api-securitygroup
category: package
repo: kacho-vpc
layer: use-case
tags:
  - packages
  - kacho-vpc
  - handler
  - securitygroup
  - occ
---

# kacho-vpc/internal/apps/kacho/api/securitygroup

**Path**: `kacho-vpc/internal/apps/kacho/api/securitygroup/`
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
