---
title: InternalWatchService
aliases:
  - InternalWatchService (vpc)
proto_file: kacho/cloud/vpc/v1/internal_watch_service.proto
category: rpc
backend: kacho-vpc
backend_port: 9091
visibility: internal
domain: vpc
status: deprecated
methods_count: 1
async_methods: 0
tags:
  - rpc
  - kacho-vpc
  - internal
  - deprecated
---

# InternalWatchService (vpc) — DEPRECATED

**Proto**: `kacho-proto/proto/kacho/cloud/vpc/v1/internal_watch_service.proto`
**Backend**: `kacho-vpc:9091`
**Public/Internal**: **cluster-internal-only**
**Status**: **deprecated с 1.0** — Watch выкинут (см. workspace CLAUDE.md «API contract — flat resources + Operations»).

## Methods

| Method | Request | Response | Note |
|---|---|---|---|
| Watch | WatchRequest | stream Event | server-streaming; больше не используется |

## Migration

Клиенты, использовавшие `Watch`:
- UI → List-polling 2–5s.
- Async-workers → `OperationService.Get(id)` для in-flight.
- impl-controller (kube-ovn-эпоха) → NI dataplane writeback — удалён в KAC-36/79/80.

`kacho-corelib/watch/` package удалён в 1.0. Proto-файл остался для backward-compat, но его регистрация в api-gateway убрана (см. [[apigw-restmux]]).

> [!important] KAC-261 (2026-06-06) — impl удалён из kacho-vpc
> `InternalWatchHandler` (`internal/handler/internal_watch_handler.go`), его регистрация
> на :9091, `WatchConfig` (`watch.max-streams`) и deploy-ключи **удалены** — 0 потребителей
> (controllers упразднён). **Сохранены** (контракт): proto-файл (cross-repo, kacho-proto),
> таблица `vpc_outbox` + все outbox-WRITES (каждая мутация emit'ит). Сам сервис на :9091
> больше не поднимается. См. [[../KAC/KAC-261]].

## See also

[[../packages/corelib-operations]] [[../rpc/operation-service]]

#rpc #kacho-vpc #internal #deprecated
