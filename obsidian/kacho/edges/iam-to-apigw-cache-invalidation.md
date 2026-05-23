---
title: "kacho-iam → kacho-api-gateway (authz-cache invalidation push)"
category: edges
caller_repo: kacho-iam
callee_repo: kacho-api-gateway
sync_async: async
protocol: grpc
status: experimental
related_tickets:
  - KAC-138
  - KAC-136
  - KAC-134
tags:
  - edge
  - kacho-iam
  - kacho-apigw
  - kacho-corelib
---

# kacho-iam → kacho-api-gateway (authz-cache invalidation)

Async push-drain канал: iam emit'ит row в `subject_change_outbox` после revoke → corelib `Drainer[T]` ([[../packages/corelib-outbox-drainer]]) LISTEN/NOTIFY + apply → gRPC `InternalAuthzCacheService.InvalidateSubject` на gateway internal-port (9091).

## Endpoint

- **Service**: `kacho.cloud.apigateway.v1.InternalAuthzCacheService` (proto KAC-138, [[../KAC/KAC-138]])
- **RPC**: `InvalidateSubject(InvalidateSubjectRequest) → InvalidateSubjectResponse`
- **Port**: internal gRPC `:9091` (CLAUDE.md §запрет #6 — НЕ на external TLS). Address конфигурируется через `KACHO_API_GATEWAY_INTERNAL_GRPC_ADDR`.
- **Auth**: mTLS via SPIRE SVID (production); insecure (dev). Bootstrap follow-up в отдельном KAC.

## Trigger paths (iam-side emit)

Каждый revoke path emit'ит `subject_change_outbox` row в той же writer-tx как и DB-delete (atomic per §запрет #10):

| Path | event_type | Wired commit |
|---|---|---|
| `AccessBindingService.Delete` | `binding_revoke` | KAC-138 (через legacy EmitSubjectChange shim) |
| `JitPendingService.DenyJITActivation` | `jit_revoke` | KAC-138 fix-up `be92aa6` |
| `BreakGlassService.DenyBreakGlass` | `bg_revoke` | KAC-138 fix-up `be92aa6` |
| `JitPendingExpirerWorker.Tick` (per-row before tx commit) | `jit_revoke` (auto-expired) | KAC-138 fix-up `be92aa6` |
| `BreakGlassExpirerWorker.Tick` (per-row before tx commit) | `bg_revoke` (auto-expired) | KAC-138 fix-up `be92aa6` |

## Latency promise (acceptance §0 после fix-up #7)

- **≥ 1 gateway replica converges < 1s** of revoke commit (push reaches the replica via LB sticky-session)
- **All HA replicas converge ≤ 30s** (WS-2.3 poll-loop безопасности — kept from KAC-127)

## Error semantics (drainer ↔ applier)

| Applier return | Drainer action |
|---|---|
| nil (gRPC OK) | markSuccess |
| `errors.Is(err, drainer.ErrAlreadyApplied)` (gRPC NotFound — entry already evicted) | markSuccess (idempotent) |
| `errors.Is(err, drainer.ErrPermanent)` (gRPC InvalidArgument/FailedPrecondition) | markPoisoned (force MaxAttempts) |
| Transient (gRPC Unavailable/DeadlineExceeded/Internal) | markFailure + exp-backoff retry |

## Safety net

WS-2.3 poll-loop ([[../KAC/KAC-127]]) запущен в gateway каждые 30s — на случай drainer crash / gateway replica miss. Push-drain — primary path; poll — fallback. Можно бахнуть `SubjectChangePollInterval` 2s → 30s после стабилизации push (R4 deferred follow-up).

## История

- 2026-05-23 (KAC-127 WS-2.3): poll-loop primary (2s interval), `decisionCache.InvalidateSubject` exists, `EmitSubjectChange` writer exists.
- 2026-05-23 (W1.2, [[../KAC/KAC-138]]): **push-drain через gRPC**. 4 новых emit-sites (JIT/BG/expirers). Latency 30s → <1s sticky / ≤30s convergence. Migration 0023 (payload jsonb).

#edge #kacho-iam #kacho-apigw #kacho-corelib
