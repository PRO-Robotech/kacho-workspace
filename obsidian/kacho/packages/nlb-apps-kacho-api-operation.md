---
title: nlb-apps-kacho-api-operation
category: packages
repo: kacho-nlb
layer: use-case
tags:
  - packages
  - kacho-nlb
  - handler
  - operation
---

# kacho-nlb/internal/apps/kacho/api/operation

**Path**: `kacho-nlb/internal/apps/kacho/api/operation/`
**Implements**: `OperationService` (3 methods: `Get`, `List`, `Cancel`)
**Imports**: [[nlb-domain]], [[nlb-repo-kacho-pg]], [[corelib-operations]]

Thin wrapper над `kacho-corelib/operations.Worker` для NLB-specific operations table. Re-exports common LRO behavior — пользовательский API одинаков с vpc/compute.

## Files

| File | Содержание |
|---|---|
| `handler.go` | gRPC adapter |
| `iface.go` | port `OperationRepo` (расширение corelib `operations.Repo`) |
| `get.go` | sync `Operation.Get(id)` |
| `list.go` | filter + page_token (по `(project_id, created_at DESC, id)` keyset) |
| `cancel.go` | best-effort cancel: set `done=true` + error="cancelled" + outbox.Emit; **не аборт worker'а** mid-flight (workspace pattern) |
| `*_test.go` | unit-tests |

## Operation id prefix

`nlb` (same as LoadBalancer; corelib `ids.PrefixOperationNLB = ids.PrefixLoadBalancer`).

## Metadata types

Per-RPC `*Metadata` proto messages:
- `CreateNetworkLoadBalancerMetadata` (`{network_load_balancer_id}`)
- `CreateListenerMetadata` (`{listener_id}`)
- `CreateTargetGroupMetadata` (`{target_group_id}`)
- `AddTargetsMetadata` / `RemoveTargetsMetadata` (`{target_group_id, target_ids[]}`)
- ... (12 metadata types)

См. design §3.2.

## See also

[[../rpc/operation-service]] [[corelib-operations]] [[nlb-repo-kacho-pg]]

#packages #kacho-nlb #handler #operation
