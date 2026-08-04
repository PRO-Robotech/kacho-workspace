---
title: Operation
aliases:
  - Operation (LRO envelope)
  - LRO
category: resource
domain: operation
id_prefix: per-service
owner_table: per-service.operations
project_level: false
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
verified_against: "карта маршрутизации операций края сверена 2026-08-05 (gateway/internal/opsproxy)"
---

# Operation (LRO envelope)

**Domain**: per-service (каждый сервис ведёт свою `operations` таблицу)
**Owner table**: `<schema сервиса>.operations`
**Контракт**: `proto/kacho/cloud/operation/operation.proto` (пакет `kacho.cloud.operation`)

## ID-префикс операции — per-домен, и он ДЕКАПЛЕН от префикса ресурса

Край маршрутизирует `Operation.Get` по **первым трём символам** идентификатора, поэтому
op-префикс обязан быть стабилен для домена целиком, а не зависеть от того, какой ресурс
мутировали. Авторитетная таблица — карта маршрутизации края
`gateway/internal/opsproxy/proxy.go` (`prefixToBackend`), сверено 2026-08-05:

| Префикс | Домен | Заметка |
|---|---|---|
| `enp` | vpc | op-root домена: Network / RouteTable / SecurityGroup / Gateway |
| `e9b` | vpc | Subnet / Address — второй vpc-префикс, именная локальная константа края |
| `epd` | compute | все операции compute (Instance и MachineType делят op-префикс) |
| `iop` | iam | все операции iam (Account/Project/User/SA/Group/Role/AccessBinding) |
| `nlb` | loadbalancer | все операции nlb |
| `rop` | registry | все операции registry |
| `sop` | storage | все операции storage (декаплен от `vol`) |
| `geo` | geo | админский CRUD Region/Zone |

Состав карты удерживается пробой `gateway/internal/opsproxy/prefix_routing_test.go`: она
сверяет **количество и состав** ключей и падает, если префикс добавили или сняли, не
обновив стража. Рядом живёт `legacyPrefixToBackend` — старая форма `<сервис>_<uuid>`,
допустимая **только на чтение** (могла осесть в долгоживущих клиентах) и не используемая
при создании новых операций.

> [!warning] Здесь стояло `rm → b1g` — домена нет
> Домен resource-manager снят (`security.md`-независимо: проверка края
> `TestResolver_RemovedResourceManagerBlocked` требует, чтобы его методы не резолвились).
> Константа `PrefixCloud = "b1g"` в `pkg/ids/ids.go` **жива** как легаси-значение — и это
> ровно тот случай, когда резолв имени доказывает существование **имени**, а не домена.
> В карте маршрутизации края `b1g` отсутствует.

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
| (denorm) account_id | account_id | TEXT NULL — denormalization (sub-phase 1.2); partial index `(account_id,created_at,id) WHERE account_id IS NOT NULL`. Источник — извлечение из metadata по точному имени поля (corelib `extractAccountID`). |

**Principal-колонки** (KAC-105, миграция corelib `0002_operations_principal.sql`,
синхронизирована в legacy сервисах KAC-113) — кто инициировал операцию.
E0 stub: `('system', 'bootstrap', 'kacho-iam-bootstrap')`. E2+ заполняется
реальным subject из JWT через [[../packages/corelib-operations]]
`PrincipalFromContext(ctx)` + `Repo.CreateWithPrincipal`.

**`account_id`-колонка** (sub-phase 1.2, corelib `migrations/common/0003`) —
денормализация для account-scoped / cluster-wide operations-фидов IAM. Т.к.
каждый сервис **владеет своей копией** `operations`-DDL и НЕ применяет
corelib `migrations/common` автоматически, колонка добавляется per-service:
iam `0016` · vpc `0009` · compute `0012` · nlb `0003`. На текущей фазе
реально штампуется только iam (category-I ops); в остальных сервисах колонка
есть, но остаётся NULL. См. [[sub-phase-1.2-iam-operations]] и
[[../packages/corelib-operations]] (инцидент 42703).

**Backfill для pre-1.2 строк** (iam migration `0017_backfill_operations_account_id`,
iam#162) — `0016` добавил колонку nullable, но историческим ops (созданным до
`account_id`-стампа) она осталась NULL → account-scoped `/iam/operations` отдавал
пусто. `0017` бэкфилит, джойня заполненный `resource_id` к owning-ресурсу: account
ops → self; project/group/service_account/user ops → `resource.account_id`.
**Category-II** (`access_binding`/`role`) остаются NULL (нет однозначного
home-account). Verified live `fe3455` rev14: 50 ops, `account_id` 0→39.

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
