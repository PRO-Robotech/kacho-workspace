---
title: "iam → nlb: D-13 lifecycle subscribe (outbox stream)"
aliases:
  - iam subscribes nlb
  - nlb lifecycle stream
category: edge
caller_repo: kacho-iam
callee_repo: kacho-nlb
sync_async: async
protocol: grpc-cluster-internal-stream
status: active
related_tickets:
  - "[[KAC-141]]"
  - "[[KAC-157]]"
  - "[[KAC-108]]"
tags:
  - edge
  - kacho-iam
  - kacho-nlb
  - cross-service
  - lifecycle
  - d13
---

> [!success] Active since 2026-05-24 (KAC-141, kacho-nlb PR#12)
> Edge активен; kacho-iam subscribes `nlb.InternalResourceLifecycleService.Subscribe` (server-stream) для maintenance FGA hierarchy tuples (cleanup на DELETED, ensure tuples на CREATED race-window).

# iam → nlb: D-13 lifecycle subscribe

**Caller**: `kacho-iam` (lifecycle subscriber pool; iam-side reads nlb outbox)
**Callee**: `kacho-nlb.InternalResourceLifecycleService.Subscribe` (port 9091, server-stream)
**Protocol**: gRPC cluster-internal (server-streaming)
**Sync/Async**: **async** (long-lived stream, semaphore-bounded)

## When invoked

- На старте kacho-iam — открывается long-lived `Subscribe` stream к каждому resource-owner backend'у (nlb, vpc, compute) для D-13 hierarchy tuple sync.
- Stream consumes `LifecycleEvent` (см. [[../rpc/nlb-internal-resource-lifecycle-service]]):
  - `CREATED` → ensure parent-tuple существует в OpenFGA (race-safe backstop для [[nlb-to-iam-creator-tuple]]).
  - `UPDATED` → no-op (relationship tuples не меняются; FGA не индексирует атрибуты).
  - `DELETED` → cleanup всех tuples для `<object_type>:<resource_id>` (idempotent).

## Implementation (iam side)

- Per-stream semaphore `KACHO_NLB_LIFECYCLE_MAX_STREAMS=32` (nlb-side).
- Dedicated pgx connection (nlb-side) → `LISTEN nlb_outbox` → `WaitForNotification` loop (30s timeout).
- Catchup batch при resume (`nlb_watch_cursors` отслеживает subscriber position).

## At-least-once semantics

Subscriber должен быть idempotent — duplicate `CREATED` после reconnect/catchup → no-op (FGA `Write` идемпотентен через `WriteIfNotExist` pattern).

## Why both D-11 + D-13

- **D-11** (sync creator-tuple в Create worker, см. [[nlb-to-iam-creator-tuple]]) — closes ErrNoPath race-window для immediate read after Create.
- **D-13** (async outbox subscribe, эта edge) — long-running cleanup + reconciliation guarantee. Если D-11 failed (iam temporarily down) → D-13 catches up на reconnect.

## Error handling

| Result | Behavior |
|---|---|
| Event consumed | advance cursor; FGA Write applied |
| FGA Write failed | log ERR + alert; retry next event loop tick |
| Stream broken | iam reconnects with cursor resume |
| nlb недоступен | iam log WARN, exponential backoff reconnect |

## See also

[[../rpc/nlb-internal-resource-lifecycle-service]] [[../packages/nlb-apps-kacho-api-internal-lifecycle]] [[nlb-to-iam-creator-tuple]] [[../KAC/KAC-108]] [[../KAC/KAC-141]]

#edge #kacho-iam #kacho-nlb #cross-service #lifecycle #d13
