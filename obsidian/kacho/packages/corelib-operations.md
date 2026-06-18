---
title: corelib-operations
category: package
repo: kacho-corelib
layer: shared
tags:
  - packages
  - kacho-corelib
  - async
  - operations
---

# corelib/operations

**Path**: `kacho-corelib/operations/`
**Imports**: `corelib/baggage`, `corelib/ids`, `pgx/v5`, `pgxpool`, `genproto/googleapis/rpc/status`, `grpc/codes`, `grpc/status`, `protobuf/proto`, `anypb`
**Imported by**: `kacho-vpc` (65 files), `kacho-resource-manager` (8)

Long-Running Operations (LRO) — Operation table (per-service) + Worker (queue + workers pool) + Repo. Каждая мутация в Kachō возвращает `Operation` и поллится клиентом.

## Exported types

- `Operation struct{ ID, Description string; CreatedAt time.Time; CreatedBy string; ModifiedAt time.Time; Done bool; Metadata *anypb.Any; Response *anypb.Any; Error *status.Status; Principal Principal }` — domain-уровень; параллельно proto-`Operation` (`kacho.cloud.operation.v1`). Поле `Principal` (KAC-105 / migration `0002_operations_principal.sql`) — кто инициировал операцию (kacho-iam-resolved); на E0/без auth заполняется `SystemPrincipal()`; на E2+ — из auth-ctx через `PrincipalFromContext`.
  - `func New(domainPrefix, description string, metadata proto.Message) (Operation, error)` — генерит `id = ids.NewID(domainPrefix+"oper")`, упаковывает metadata в Any.
- `Principal struct{ Type, ID, DisplayName string }` (KAC-105) — соответствует колонкам `operations.principal_type / principal_id / principal_display_name`. Helpers: `SystemPrincipal()`, `BootstrapPrincipal(displayName string)`. Context-baggage helpers: `PrincipalToContext(ctx, p)` / `PrincipalFromContext(ctx) Principal` (через `corelib/baggage`).
- `Repo interface { Create, CreateWithPrincipal, Get, List, Update, Heartbeat }` — порт; pg-реализация ниже. `CreateWithPrincipal(ctx, op, p)` (KAC-105) — пишет new operation с явным principal'ом; вызывается из use-case'ов после `PrincipalFromContext(ctx)`. Legacy `Create(ctx, op)` сохранён для backward-compat — внутри делает `CreateWithPrincipal` с default'ом (`SystemPrincipal()` либо `op.Principal` если уже заполнен).
  - `NewRepo(pool *pgxpool.Pool, schema string) Repo` — pgx-репозиторий поверх таблицы `<schema>.operations`.
- **`account_id` денормализация (sub-phase 1.2, corelib #24, migrations/common `0003`)** — `CreateWithPrincipal` теперь штампует `operations.account_id`, извлекая его из metadata-сообщения по **точному имени поля** (`extractAccountID`). `ListFilter.AccountID` (новое поле) фильтрует List по этой колонке; partial cursor-индекс `(account_id, created_at, id) WHERE account_id IS NOT NULL`. Питает account-scoped feed ([[../rpc/iam-account-service]] `ListAllOperations`) и cluster-wide ([[../rpc/iam-internal-operations-service]]).
- `Worker struct{ ... }` — pool горутин, обрабатывающих pending operations.
  - `NewWorker() *Worker`
  - `(*Worker).Wait(ctx) error`
- `ListFilter struct{ ... }` — pagination + filter для repo.List.

## Exported funcs / vars

- `Run(callerCtx, repo, opID, fn func(ctx) (proto.Message, error))` — вызывается в handler сразу после создания row: запускает фон-горутину с `baggage.Extract(callerCtx)`-context, на success/error → `repo.Update(done=true, response/error)`.
- `RunWithWorker(w, callerCtx, repo, opID, fn ...)` — то же, но через named-worker (для graceful shutdown).
- `MetadataFor[T proto.Message](op *Operation) (T, error)` — generic unmarshal Any → typed proto-msg.
- `Active() int64` — глобальный счётчик активных операций.
- `Wait(ctx)` — wait для всех глобальных Run-операций.
- `ErrAlreadyDone`, `ErrNotFound`, `ErrShutdownTimeout` — sentinels.

## Pattern

```go
op, _ := operations.New("enp", "Create network "+name, &vpc.CreateNetworkMetadata{NetworkId: id})
_ = repo.Create(ctx, op)
operations.Run(ctx, repo, op.ID, func(ctx context.Context) (proto.Message, error) {
    return &vpc.Network{...}, nil // или error → status.FromError
})
return convertToProto(op), nil // sync return — клиент поллит OperationService.Get
```

## ⚠️ Инцидент 42703 — per-service operations DDL (merge-order)

> [!warning] corelib `migrations/common/*` НЕ применяются сервисами автоматически
> Каждый сервис **владеет своей копией** `operations`-таблицы (iam/vpc/compute/nlb — у каждого своя DDL).
> corelib #24 включил **безусловный** INSERT `account_id` и был смержен **раньше**, чем consumer-сервисы
> добавили колонку → SQLSTATE `42703` undefined_column на **КАЖДОМ** operations-INSERT fleet-wide
> (замаскировалось под bootstrap-flake). Фикс: добавлены additive-миграции `account_id` —
> iam `0016` · vpc `0009` · compute `0012` · nlb `0003`.
> **Урок**: меняешь corelib-write-path по колонке → миграции consumer'ов landятся ПЕРВЫМИ (топосорт build-графа).

## See also

[[corelib-baggage]] [[corelib-outbox]] [[corelib-outbox-drainer]] [[../resources/operation]] [[../rpc/operation-service]] [[../rpc/iam-account-service]] [[sub-phase-1.2-iam-operations]]

#packages #kacho-corelib #async #operations
