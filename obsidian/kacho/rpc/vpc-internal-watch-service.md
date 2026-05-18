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
- impl-controller → upstream-read on-demand + ReportNiDataplane (KAC-2).

`kacho-corelib/watch/` package удалён в 1.0. Proto-файл остался для backward-compat, но его регистрация в api-gateway убрана (см. [[apigw-restmux]]).

## See also

[[../packages/corelib-operations]] [[../rpc/operation-service]]

#rpc #kacho-vpc #internal #deprecated
