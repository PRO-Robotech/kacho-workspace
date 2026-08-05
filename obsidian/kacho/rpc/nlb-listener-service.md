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
verified_against: "перечень RPC сверен с proto ствола redesign/integration в ОБЕ стороны 2026-08-05 (методы контракта против методов записки); поля запросов и семантика построчно не пересматривались"
status: stable
---

# ListenerService (nlb)

**Proto**: `proto/kacho/cloud/loadbalancer/v1/listener_service.proto`
**Backend**: `kacho-nlb:9090` (public gRPC)
**Public/Internal**: public

## Methods (6)

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| Get | GetListenerRequest | Listener | sync | |
| List | ListListenersRequest | ListListenersResponse | sync | filter, page_token |
| Create | CreateListenerRequest | operation.Operation | **async** | чистый INSERT: адреса листенер не аллоцирует |
| Update | UpdateListenerRequest | operation.Operation | **async** | mutable: name/desc/labels/target_port/default_tg_id/proxy_protocol_v2 |
| Delete | DeleteListenerRequest | operation.Operation | **async** | VIP не трогает (принадлежит LB) |
| ListOperations | ListListenerOperationsRequest | ListListenerOperationsResponse | sync | per-resource history |

## Create flow — без внешних side-effect'ов

VIP — свойство LoadBalancer'а ([[../edges/nlb-to-vpc-vip-allocation]]), листенер открывает на нём порт.
Поэтому Create не зовёт vpc вовсе:

1. Sync: FGA `editor on nlb_load_balancer:<lb_id>` → `LB.Get` (тот же проект, status≠DELETING) →
   precheck `targetGroupId` (существует в проекте LB, авторизован, region-coherent) → domain.Validate → `ops.Insert`.
2. Worker — **одна** writer-TX: `listeners.Insert` (`status=ACTIVE` сразу) + outbox (`CREATED` +
   `nlb_load_balancer UPDATED`) + FGA-register-intent (creator + parent-link) → Commit.
   INSERT берёт `FOR NO KEY UPDATE` на строке LB → сериализуется с `Move`/`MarkDeleting`.
3. Компенсации нет — откатывать нечего (внешний ресурс не захватывался).

## Immutability rules

`load_balancer_id`, `protocol`, `port` — InvalidArgument при попытке Update
(`ip_version`/`address_id`/`subnet_id` у листенера больше нет — сняты с proto).

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
