---
title: nlb-apps-kacho-api-internal-lifecycle
category: packages
repo: kacho-nlb
layer: use-case
tags:
  - packages
  - kacho-nlb
  - handler
  - internal
  - lifecycle
---

# kacho-nlb/internal/apps/kacho/api/internal_lifecycle

**Path**: `kacho-nlb/internal/apps/kacho/api/internal_lifecycle/`
**Implements**: [[../rpc/nlb-internal-resource-lifecycle-service|InternalResourceLifecycleService]]
**Imports**: [[nlb-repo-kacho-pg]] (outbox + watch_cursors), [[corelib-grpcsrv]]

Server-streaming D-13 lifecycle service. **Internal-only** (port 9091, workspace #6).

## Files

| File | Содержание |
|---|---|
| `handler.go` | `Subscribe(req, stream)` server-stream |
| `subscribe.go` | core loop: semaphore acquire → pgx.Connect (dedicated conn) → catchup batch (100) → LISTEN nlb_outbox → WaitForNotification (30s timeout) → stream LifecycleEvent |
| `iface.go` | port `OutboxReader` (catchup batch via cursor, NotifyConn factory) |
| `helpers.go` | event payload marshal (row jsonb → proto LifecycleEvent) |
| `*_test.go` | integration-tests (testcontainers + concurrent subscribers + reconnect cursor resume) |

## Semaphore guard

`KACHO_NLB_LIFECYCLE_MAX_STREAMS=32` (configurable). При превышении — `ResourceExhausted "max subscribers"`. Защищает pgx pool exhaustion (каждый stream — dedicated connection).

## Catchup vs realtime

1. **Catchup batch**: `SELECT FROM nlb_outbox WHERE sequence_no > $cursor ORDER BY sequence_no LIMIT 100` — sends to client as `LifecycleEvent`s.
2. **Realtime**: dedicated pgx-conn `LISTEN nlb_outbox` → `WaitForNotification` 30s; on notification → read row by `sequence_no` → send event.
3. **Cursor save**: `nlb_watch_cursors (subscriber_id, last_sequence_no)` — persisted resume position.

## Consumer

Primarily [[../edges/iam-to-nlb-resource-lifecycle|kacho-iam]] для D-13 FGA hierarchy tuple maintenance.

## See also

[[../rpc/nlb-internal-resource-lifecycle-service]] [[../edges/iam-to-nlb-resource-lifecycle]] [[nlb-repo-kacho-pg]] [[corelib-outbox]]

#packages #kacho-nlb #handler #internal #lifecycle
