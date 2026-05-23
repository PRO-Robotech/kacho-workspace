---
title: "api-gateway → iam: PollSubjectChanges (authz-cache invalidation)"
aliases:
  - apigw to iam subject-change
  - WS-2.3 cache invalidation
category: edge
caller_repo: kacho-api-gateway
callee_repo: kacho-iam
sync_async: sync
protocol: gRPC
status: planned
related_tickets:
  - "[[KAC-WS23]]"
tags:
  - edge
  - kacho-api-gateway
  - kacho-iam
  - cross-service
  - authz
---

# api-gateway → iam: PollSubjectChanges (authz-cache invalidation)

**Caller**: `kacho-api-gateway` — `SubjectChangeWatcher` poll-loop (`internal/watcher/`), via adapter `internal/clients/subject_change_client.go`.
**Callee**: `kacho-iam` `InternalIAMService.PollSubjectChanges` ([[../rpc/iam-internal-iam-service]]) — `kacho-iam:9091` (internal-only).
**Protocol**: gRPC, cluster-internal. Reuses the existing `iamInternal` backend conn — **no DB access on the gateway**.
**Sync/Async**: sync; background ticker (`KACHO_API_GATEWAY_SUBJECT_CHANGE_POLL_INTERVAL`, default 2s).
**Status**: WS-2.3 ([[KAC-WS23]]) — PRs open.

## Зачем

`AccessBinding` grant/revoke меняет authz-граф, но gateway держит `decisionCache`
(LRU 10k / 5s TTL). Без инвалидации отозванный грант авторизует до истечения TTL.

## Двухканальная инвалидация

1. **Synchronous self-flush** (request-path реплика): gateway проксирует
   `POST/DELETE /iam/v1/accessBindings*` → на 2xx зовёт `decisionCache.Invalidate()`
   (`AuthzMiddleware.MaybeFlushOnMutation`). Детерминированно — реплика, обработавшая
   мутацию, видит свежий граф сразу.
2. **Async cross-replica drain** (этот edge): `AccessBinding.Create/Delete` пишут
   `subject_change_outbox` в TX привязки → `SubjectChangeWatcher` дренит
   `PollSubjectChanges` по курсору → `InvalidateCache()`. Догоняет остальные
   реплики (HPA до 10) в пределах одного интервала; stale-окно ≤ TTL 5s.

## Поток

```
poll tick (2s):
  ids, headID ← iam.PollSubjectChanges(since=cursor, limit=1000)
  first tick  → primed: cursor=headID, БЕЗ flush (cache холодный на старте)
  ids непусты → cursor=max(ids,headID); InvalidateCache(); log
  ids пусты   → no-op
```

## Почему poll, а не LISTEN/NOTIFY

`subject_change_outbox` имеет NOTIFY-триггер (`kacho_iam_subject_outbox_added`,
migration 0002), но gateway не имеет доступа к Postgres, а давать edge-компоненту
DB-креды iam — расширение blast-radius. RPC-poll переиспользует доверенный
gRPC-канал. Детерминизм e2e обеспечивает self-flush (канал 1), не poll.

## History

- WS-2.3 ([[KAC-WS23]] / YT KAC-124, 2026-05-22) — edge создан. До него
  `decisionCache.Invalidate()`/`InvalidateSubject()` и `subject_change_outbox`
  существовали, но не были соединены (мёртвый scaffolding).

## See also

[[api-gateway-to-iam-authorize]] [[../rpc/iam-internal-iam-service]] [[../resources/iam-access-binding]] [[../KAC/KAC-WS23]]

#edge #kacho-api-gateway #kacho-iam #cross-service #authz
