---
title: nlb-apps-kacho-api-listener
category: packages
repo: kacho-nlb
layer: use-case
tags:
  - packages
  - kacho-nlb
  - handler
  - usecase
  - listener
---

# kacho-nlb/internal/apps/kacho/api/listener

**Path**: `kacho-nlb/internal/apps/kacho/api/listener/`
**Implements**: [[../rpc/nlb-listener-service|ListenerService]]
**Imports**: [[nlb-domain]], [[nlb-repo-kacho-pg]], [[corelib-operations]], [[corelib-outbox]], [[nlb-clients-vpc]], [[nlb-internal-fgawrite]]

## Files

| File | Содержание |
|---|---|
| `handler.go` | thin gRPC adapter |
| `iface.go` | port-интерфейсы (Repo, AddressClient, SubnetClient, Emitter) |
| `helpers.go` | shared validation + mapErr |
| `get.go` / `list.go` | sync reads |
| `create.go` | `CreateListenerUseCase` — Validate + LB.Get + spawn worker (VIP alloc) |
| `create_worker.go` | worker: BYO ([[nlb-clients-vpc]] SetReference CAS) OR auto-alloc (AllocateExternal/InternalIP) → listeners.Insert → outbox.Emit (CREATED + LB UPDATED) → ops.MarkDone → fga.Emit 2 tuples. Defer FreeIP compensation. |
| `update.go` | UpdateMask; immutable: lb_id/protocol/port/ip_version/address_id |
| `delete.go` | spawn worker: free VIP (auto → FreeIP, BYO → ClearReference) → listeners.Delete → outbox.Emit DELETED |
| `list_operations.go` | per-resource history |
| `*_test.go` | unit-tests (BYO/auto/compensation/immutable update reject) |

## VIP allocation worker flow

См. [[../edges/nlb-to-vpc-vip-allocation]] (auto) + [[../edges/nlb-to-vpc-byo-address]] (BYO).

## See also

[[../rpc/nlb-listener-service]] [[../resources/nlb-listener]] [[nlb-clients-vpc]] [[../edges/nlb-to-vpc-vip-allocation]]

#packages #kacho-nlb #handler #usecase #listener
