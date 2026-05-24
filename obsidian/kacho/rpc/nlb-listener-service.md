---
title: ListenerService
aliases:
  - ListenerService (nlb)
proto_file: kacho/cloud/loadbalancer/v1/listener_service.proto
category: rpc
backend: kacho-nlb
backend_port: 9090
visibility: public
domain: nlb
related_resource: "[[resources/nlb-listener]]"
methods_count: 6
async_methods: 3
tags:
  - rpc
  - kacho-nlb
  - listener
---

# ListenerService (nlb)

**Proto**: `kacho-proto/proto/kacho/cloud/loadbalancer/v1/listener_service.proto`
**Backend**: `kacho-nlb:9090` (public gRPC)
**Public/Internal**: public

## Methods (6)

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| Get | GetListenerRequest | Listener | sync | |
| List | ListListenersRequest | ListListenersResponse | sync | filter, page_token |
| Create | CreateListenerRequest | operation.Operation | **async** | VIP alloc: BYO `address_id` OR auto |
| Update | UpdateListenerRequest | operation.Operation | **async** | mutable: name/desc/labels/target_port/default_tg_id/proxy_protocol_v2 |
| Delete | DeleteListenerRequest | operation.Operation | **async** | освобождает VIP (free pool или clear BYO `used_by`) |
| ListOperations | ListListenerOperationsRequest | ListListenerOperationsResponse | sync | per-resource history |

## VIP allocation flow (Create)

1. Sync: FGA `editor on nlb_load_balancer:<lb_id>` → domain.Validate → `LB.Get` (same project, status≠DELETING) → `ops.Insert`
2. Worker:
   - **BYO** (`address_id` given): [[../edges/nlb-to-vpc-byo-address]] → `vpc.AddressService.Get` (same project, used_by ours) → `InternalAddressService.SetReference(used_by=nlb_listener:<id>)` atomic CAS.
   - **Auto**: [[../edges/nlb-to-vpc-vip-allocation]] → `vpc.InternalAddressService.AllocateExternalIP/AllocateInternalIP(owner=nlb_listener:<id>)`.
3. `listeners.Insert(allocated_address, address_id)` + outbox.Emit (CREATED + LB UPDATED) + `ops.MarkDone`.
4. `fgawrite.Emit` 2 tuples (project + load_balancer hierarchy).

**Compensation**: defer `vpc.FreeIP` если repo.Insert упал после allocate.

## Immutability rules

`load_balancer_id`, `protocol`, `port`, `ip_version`, `address_id` — InvalidArgument при попытке Update.

## REST mapping

| HTTP | Method |
|---|---|
| `GET /nlb/v1/listeners/{listener_id}` | Get |
| `GET /nlb/v1/listeners` | List |
| `POST /nlb/v1/listeners` | Create |
| `PATCH /nlb/v1/listeners/{listener_id}` | Update |
| `DELETE /nlb/v1/listeners/{listener_id}` | Delete |
| `GET /nlb/v1/listeners/{listener_id}/operations` | ListOperations |

## FGA Permissions

- `Get` / `List` / `ListOperations` → `viewer` on `nlb_listener:<id>` (или viewer на parent LB)
- `Create` → `editor` on `nlb_load_balancer:<lb_id>`
- `Update` / `Delete` → `editor` on `nlb_listener:<id>`

## See also

[[../packages/nlb-apps-kacho-api-listener]] [[../resources/nlb-listener]] [[../edges/nlb-to-vpc-vip-allocation]] [[../edges/nlb-to-vpc-byo-address]]

#rpc #kacho-nlb #listener
