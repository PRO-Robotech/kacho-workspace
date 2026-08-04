---
title: "kacho-iam → kacho-api-gateway (authz-cache invalidation push)"
category: edge
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
verified_against: "отметка сверки с деревом продукта стоит в тексте записки (96b2879a, 2026-08-05)"
---

> [!note] Канон этого ребра — [[iam-to-apigateway-authzcache]]
> Две записки об одном предмете; эта оставлена как история KAC-138 (как ребро заводилось и
> какие пути его эмитили). Действующее описание провязки и обязательности адреса шлюза — в
> канонической. Здесь правится только то, что стало ложью.

# kacho-iam → kacho-api-gateway (authz-cache invalidation)

Async push-drain канал: iam emit'ит row в `subject_change_outbox` после revoke → corelib `Drainer[T]` ([[../packages/corelib-outbox-drainer]]) LISTEN/NOTIFY + apply → gRPC `InternalAuthzCacheService.InvalidateSubject` на gateway internal-port (9091).

## Endpoint

- **Service**: `kacho.cloud.apigateway.v1.InternalAuthzCacheService` (proto KAC-138, [[../KAC/KAC-138]])
- **RPC**: `InvalidateSubject(InvalidateSubjectRequest) → InvalidateSubjectResponse`
- **Port**: internal gRPC `:9091` (CLAUDE.md §запрет #6 — НЕ на external TLS). Address конфигурируется через `KACHO_API_GATEWAY_INTERNAL_GRPC_ADDR`.
- **Auth**: клиентский сертификат внутреннего УЦ (SPIFFE-имя в SAN). SPIRE как компонент в дереве отсутствует — см. [[iam-to-spire]]: у нас SPIFFE-имена, а не агент SPIRE.

## Trigger paths (iam-side emit)

Каждый revoke path emit'ит `subject_change_outbox` row в той же writer-tx как и DB-delete (atomic per §запрет #10):

| Path | event_type | Замечание |
|---|---|---|
| `AccessBindingService.Delete` | `binding_revoke` | живой путь; применитель — `services/iam/internal/clients/cache_invalidation_applier.go` |

> [!warning] Четыре из пяти строк называли RPC, которых в контракте нет (сверено 2026-08-05)
> Оба названных сервиса — срочного доступа и временных прав — в proto
> отсутствуют (`ls proto/kacho/cloud/iam/v1/ | grep -i "break\|jit"` → пусто); имена
> встречаются только в табличной пробе анонимного доступа, то есть как **исторический
> перечень имён**, а не как поверхность. Соответствующих воркеров-истекателей в дереве тоже
> нет. Осталась одна работающая полоса — снятие привязки.
>
> Само ребро при этом **живое**: `subject_change_outbox` пишется, применитель зовёт
> `InternalAuthzCacheService.InvalidateSubject` на внутреннем порту шлюза, а у шлюза есть и
> обработчик, и подстраховочный опрос (`gateway/internal/watcher/subject_change_watcher.go`).

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
