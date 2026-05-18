---
title: Operation
aliases:
  - Operation (LRO envelope)
  - LRO
category: resource
domain: operation
id_prefix: per-service
owner_table: per-service.operations
folder_level: false
status: stable
related_rpc:
  - "[[rpc/operation-service]]"
related_packages:
  - "[[packages/corelib-operations]]"
  - "[[packages/proto-operation]]"
tags:
  - resource
  - operation
  - lro
  - async
---

# Operation (LRO envelope)

**Domain**: per-service (каждый сервис ведёт свою `operations` таблицу)
**ID prefix**: domain-specific (vpc → `enp`, rm → `b1g`, compute → `epd`) + `oper`-суффикс не нужен — id берётся из domain ([[../packages/corelib-ids]]).
**Owner table**: `<service-schema>.operations`
**Proto**: `kacho.cloud.operation.v1.Operation`

## Fields (proto + DB)

| Proto | DB | Note |
|---|---|---|
| id | id | TEXT PK |
| description | description | |
| created_at | created_at | truncate-to-seconds |
| modified_at | modified_at | |
| done | done | BOOL |
| metadata | metadata | BYTEA (Any marshalled) |
| oneof result | response_bytes / error_bytes | один из двух |
| principal_type | principal_type | TEXT — `user` / `service_account` / `system` (KAC-105) |
| principal_id | principal_id | TEXT — usr.../sva.../`bootstrap` |
| principal_display_name | principal_display_name | TEXT — email / name / `kacho-iam-bootstrap` |

**Principal-колонки** (KAC-105, миграция corelib `0002_operations_principal.sql`,
синхронизирована в legacy сервисах KAC-113) — кто инициировал операцию.
E0 stub: `('system', 'bootstrap', 'kacho-iam-bootstrap')`. E2+ заполняется
реальным subject из JWT через [[../packages/corelib-operations]]
`PrincipalFromContext(ctx)` + `Repo.CreateWithPrincipal`.

## Lifecycle (in DB)

1. `Create(done=false, metadata={ResourceId})`.
2. Worker запускается ([[../packages/corelib-operations]] `Run`); `baggage.Extract(ctx)` для async-context.
3. На success: `Update(done=true, response=<Resource>)`.
4. На failure: `Update(done=true, error=google.rpc.Status)`.

## Polling

```python
op = client.create_network(...)
while not op.done:
    time.sleep(2)
    op = ops_client.get(op.id)
```

`OperationService.Get` ([[../rpc/operation-service]]) — единая точка; api-gateway routes per-domain (см. [[../edges/apigw-internal-vs-tls]]).

## Async-worker baggage

Что переносится из caller-context в worker-context (см. [[../packages/corelib-baggage]]):
- request-id, trace-context, auth-subject.
- **НЕ** переносятся: deadline, cancellation (worker должен пережить grpc-response).

## See also

[[../packages/corelib-operations]] [[../packages/corelib-baggage]] [[../packages/proto-operation]] [[../rpc/operation-service]]

#resource #operation #lro
