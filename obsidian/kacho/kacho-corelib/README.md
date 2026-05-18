---
title: kacho-corelib
aliases:
  - kacho-corelib
category: repo
repo: kacho-corelib
go_module: github.com/PRO-Robotech/kacho-corelib
service_type: shared-library
status: stable
tags:
  - kacho
  - kacho-corelib
  - shared
  - go
---

# kacho-corelib

Общая Go-библиотека Kachō — переиспользуемые **горизонтальные** компоненты (cross-cutting concerns).

- Repo: `github.com/PRO-Robotech/kacho-corelib`
- Import: `github.com/PRO-Robotech/kacho-corelib/<pkg>`

## Пакеты (15)

| Package | Назначение |
|---|---|
| **`backoff/`** | Exponential backoff helpers для retry-loops. |
| **`baggage/`** | `Extract(ctx)` через `context.WithoutCancel` — propagation trace/request-id/slog-attrs в operation worker (closes skill evgeniy I.3). |
| **`config/`** | Базовые config-helpers (DSN-парсеры, secret loading). |
| **`db/`** | pgxpool wrapper + `Transactor` для unit-of-work. |
| **`errors/`** | Sentinel errors + gRPC-status mapping helpers. |
| **`filter/`** | YC-syntax `name="value"` filter-parser с whitelist полей (`Parse`, `ToSQL`). |
| **`grpcsrv/`** | gRPC server bootstrap (interceptors, listener, shutdown). |
| **`ids/`** | `NewID(prefix)` — crockford-base32 + 3-char prefix. Источник истины для prefix-routing api-gateway. |
| **`observability/`** | structured logging (slog) + OTel boilerplate. |
| **`operations/`** | LRO support: `Operation` struct, `Run(ctx, repo, opID, fn)` worker с baggage propagation, repo для `operations` таблицы. |
| **`outbox/`** | Transactional outbox helpers (emit-в-той-же-TX + LISTEN/NOTIFY consumer). |
| **`retry/`** | gRPC retry-on-Unavailable helpers. |
| **`selector/`** | Label-selector parser (k8s-style). |
| **`shutdown/`** | Graceful-shutdown helpers (signal handling, drain). |
| **`validate/`** | YC-стилистические validators: `NameVPC`, `NameGateway`, `Description`, `Labels`, `ResourceID`, `UpdateMask`, `ZoneId`, `PageSize`, `IPAddress`, `DhcpDomainName`, `DdosProvider`, `SmtpCapability`. |
| **`migrations/common/`** | Общие goose-миграции (`operations`, `operations_sequence`). Sync через `make sync-migrations` в каждое сервисное репо. |

## Принцип переиспользования

> [!quote] workspace CLAUDE.md
> «Всё, что может быть вынесено в общий компонент для переиспользования в нескольких сервисах — выносится в `kacho-corelib/<package>/`.»

**Исключения** (НЕ в corelib):
- Бизнес-логика конкретного домена (VPC ref-validation, NLB target-deregister, Compute reconciler).
- Audit-log skeleton (`audit/`) — no-op в текущей фазе.

## Зависимости

- **Внутрь**: `kacho-proto` (импортирует `Operation`-message из `kacho.cloud.operation.v1`).
- **Из вне**: импортируется всеми сервисами:
  - [[../kacho-vpc/README|kacho-vpc]] — `ids`, `operations`, `db`, `validate`, `filter`, `outbox`, `baggage`, `grpcsrv`.
  - [[../kacho-resource-manager/README|kacho-resource-manager]] — `ids`, `operations`, `db`, `validate`, `grpcsrv`.
  - [[../kacho-api-gateway/README|kacho-api-gateway]] — `grpcsrv`, `observability`.
  - kacho-compute, kacho-loadbalancer — аналогично.

## Связь с corlib (H-BF)

Skill evgeniy ссылается на **внешнюю** библиотеку `github.com/H-BF/corlib` (newtypes, option, parallel, grpc client-builder, dict). Это **другой** пакет — не путать с `kacho-corelib`.

- `H-BF/corlib/pkg/dict.HDict[K,V]` — для `RcLabels` в domain.
- `H-BF/corlib/pkg/option.ValueOf[T]` — для optional newtypes.
- `H-BF/corlib/pkg/parallel.ExecAbstract` — для cmd/vpc serve+migrate-runner (KAC-94 K.4/K.5).
- `H-BF/corlib/client/grpc` — единый builder gRPC-клиентов с retries/LB/TLS (KAC-94 K.6).

#kacho #kacho-corelib #shared #go
