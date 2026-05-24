---
title: nlb-apps-kacho-api-loadbalancer
category: packages
repo: kacho-nlb
layer: use-case
tags:
  - packages
  - kacho-nlb
  - handler
  - usecase
  - loadbalancer
---

# kacho-nlb/internal/apps/kacho/api/loadbalancer

**Path**: `kacho-nlb/internal/apps/kacho/api/loadbalancer/`
**Implements**: [[../rpc/nlb-network-load-balancer-service|NetworkLoadBalancerService]]
**Imports**: [[nlb-domain]], [[nlb-repo-kacho-pg]], [[corelib-operations]], [[corelib-outbox]], [[nlb-clients-iam]], [[nlb-clients-compute]], [[nlb-internal-fgawrite]]

Use-case slice per LoadBalancer — Clean Architecture: handler.go (gRPC adapter) + per-RPC use-case files (бизнес-логика).

## Files

| File | Содержание |
|---|---|
| `handler.go` | thin gRPC adapter; parse req → useCase.Run → dto.Transfer → format resp |
| `iface.go` | port-интерфейсы (Repo, RegionClient, IAMClient, Emitter) |
| `helpers.go` | shared validation + mapErr (SQLSTATE → gRPC) |
| `get.go` / `list.go` | sync reads |
| `create.go` | `CreateLoadBalancerUseCase` — Validate + Project/Region check + ops.Insert + spawn worker |
| `update.go` | UpdateMask discipline; immutable: type/region_id/project_id |
| `delete.go` | sync precheck: deletion_protection / has listeners / has attached TG |
| `start.go` / `stop.go` | status precondition + outbox.Emit UPDATED |
| `move.go` | cross-project, same-region; blocked if attached TG present |
| `attach_target_group.go` / `detach_target_group.go` | M:N pivot manage; same-region check; respects deregistration_delay (Detach) |
| `get_target_states.go` | sync; computed runtime ramp INITIAL→HEALTHY |
| `list_operations.go` | per-resource history |
| `*_test.go` | unit-tests against mock repo + mock clients |

## See also

[[../rpc/nlb-network-load-balancer-service]] [[../resources/nlb-load-balancer]] [[nlb-internal-fgawrite]] [[nlb-clients-vpc]]

#packages #kacho-nlb #handler #usecase #loadbalancer
