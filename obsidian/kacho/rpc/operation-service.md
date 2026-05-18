---
title: OperationService
aliases:
  - OperationService
proto_file: kacho/cloud/operation/operation_service.proto
category: rpc
backend: per-domain
visibility: public
domain: operation
related_resource: "[[resources/operation]]"
methods_count: 2
async_methods: 0
tags:
  - rpc
  - operation
  - lro
---

# OperationService

**Proto**: `kacho-proto/proto/kacho/cloud/operation/operation_service.proto`
**Backend**: per-domain (каждый сервис ведёт свои operations; api-gateway проксирует к нужному backend по префиксу).

## Methods

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| Get | GetOperationRequest | Operation | sync | poll until `done=true` |
| Cancel | CancelOperationRequest | Operation | sync | best-effort — большинство операций нельзя отменить |

## REST mapping

| HTTP | Method |
|---|---|
| `GET /operations/{operation_id}` | Get |
| `POST /operations/{operation_id}:cancel` | Cancel |

(Префикс `/operations` — gw-level; за ним per-domain routing — см. [[apigw-opsproxy]].)

## Polling pattern

```python
op = client.create_network(req)
while not op.done:
    time.sleep(2)
    op = ops_client.get(op.id)
if op.HasField('error'): raise op.error
network = unmarshal_any(op.response, Network)
```

## See also

[[../packages/corelib-operations]] [[../packages/proto-operation]] [[../resources/operation]] [[apigw-opsproxy]]

#rpc #operation #lro
