---
title: nlb-apps-kacho-api-targetgroup
category: packages
repo: kacho-nlb
layer: use-case
tags:
  - packages
  - kacho-nlb
  - handler
  - usecase
  - targetgroup
---

# kacho-nlb/internal/apps/kacho/api/targetgroup

**Path**: `kacho-nlb/internal/apps/kacho/api/targetgroup/`
**Implements**: [[../rpc/nlb-target-group-service|TargetGroupService]]
**Imports**: [[nlb-domain]], [[nlb-repo-kacho-pg]], [[corelib-operations]], [[corelib-outbox]], [[nlb-clients-vpc]], [[nlb-clients-compute]], [[nlb-internal-fgawrite]]

## Files

| File | Содержание |
|---|---|
| `handler.go` | thin gRPC adapter |
| `iface.go` | port-интерфейсы (Repo, RegionClient, InstanceClient, NicClient, SubnetClient, Emitter) |
| `helpers.go` | shared validation + per-target peer-resolve dispatcher |
| `get.go` / `list.go` | sync reads |
| `create.go` | inline `targets[]` + `health_check` allowed; Validate + Region check + ops.Insert → spawn worker (per-target peer-validate) |
| `update.go` | UpdateMask; immutable: project_id/region_id |
| `delete.go` | sync precheck: no attached LB + no targets remaining |
| `move.go` | cross-project; blocked if attached |
| `add_targets.go` | `AddTargetsUseCase` — per-target Validate + peer-resolve worker → `INSERT ... ON CONFLICT DO NOTHING` per identity-key (idempotent) |
| `remove_targets.go` | 2-phase: Phase A worker mark DRAINING → ops.MarkDone; Phase B drain-runner ([[nlb-apps-kacho-jobs]]) |
| `list_operations.go` | per-resource history |
| `*_test.go` | unit-tests (idempotent Add, 2-phase Remove, identity oneof validation, peer-resolve fail) |

## Peer-resolve dispatcher (per-target)

См. [[../edges/nlb-to-compute-instance-resolve]] / [[../edges/nlb-to-vpc-nic-resolve]] / [[../edges/nlb-to-vpc-subnet-validation]] (ip_ref).

## See also

[[../rpc/nlb-target-group-service]] [[../resources/nlb-target-group]] [[../resources/nlb-target]] [[nlb-apps-kacho-jobs]]

#packages #kacho-nlb #handler #usecase #targetgroup
