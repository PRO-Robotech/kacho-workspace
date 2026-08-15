---
title: "iam → api-gateway: subject_change push (authz-cache invalidation)"
aliases:
  - iam to apigw authz-cache push
  - subject_change drainer
category: edge
caller_repo: kacho-iam
callee_repo: kacho-api-gateway
sync_async: async
protocol: gRPC
status: active
related_tickets:
  - "[[KAC-223]]"
tags:
  - edge
  - kacho-iam
  - kacho-apigw
  - cross-service
  - authz
verified_against: "отметка сверки с деревом продукта стоит в тексте записки (96b2879a, 2026-08-05)"
---

> [!warning] Две записки об ОДНОМ предмете — эта каноническая, соседняя историческая
> `iam → api-gateway (инвалидация кэша решений)` описана здесь **и** в
> [[iam-to-apigw-cache-invalidation]]. Расходиться они уже начали: соседняя перечисляет
> четыре источника события, которых в контракте нет (сервисы срочного доступа и
> временных прав), эта — нет. Канон держим здесь, потому что она описывает провязку, которая
> в дереве есть: `services/iam/cmd/kacho-iam/subject_change_wiring.go`, и адрес шлюза
> **обязателен** — без него сервис не стартует (не «выключено по умолчанию»).
>
> Статус `planned` снят: ребро живое (сверено 2026-08-05, дерево `96b2879a`).

# iam → api-gateway: subject_change push (authz-cache invalidation)

**Caller**: `kacho-iam` — `subject_change` push-drainer
(`cmd/kacho-iam/subject_change_wiring.go`), corelib `Drainer[SubjectChangeEvent]`
over `kacho_iam.subject_change_outbox` (LISTEN `kacho_iam_subject_outbox_added`).
**Callee**: `kacho-api-gateway` `InternalAuthzCacheService.InvalidateSubject`
([[api-gateway-to-iam-authorize]]) on the **internal** gRPC listener.
**Protocol**: gRPC, **plaintext** (cluster-internal `:9091` mesh,
NetworkPolicy-protected — запрет #6). Dial addr `KACHO_IAM_GATEWAY_INTERNAL_ADDR`.
**Sync/Async**: async push (≤1s); the gateway's poll-loop
([[api-gateway-to-iam-subject-change]]) is the 30s safety-net fallback.

## Зачем

`AccessBinding` grant/revoke пишет `subject_change_outbox` в той же writer-TX.
Drainer пушит per-subject инвалидацию в gateway `decisionCache` (sub-second),
вместо 30s poll-fallback.

## KAC-223 — что изменилось

- Drainer теперь **всегда стартует** (раньше env-gated «addr empty → disabled»);
  `KACHO_IAM_GATEWAY_INTERNAL_ADDR` обязателен (fail-fast — static chart config).
- **Deploy gap закрыт**: gateway internal `:9091` listener существовал в коде, но
  k8s-Service'а не было → drainer не доходил, работал только 30s poll. KAC-223
  добавил Service `api-gateway-internal` (kacho-api-gateway#58).
- Transport — plaintext (внутренний mesh без TLS); mTLS по всему mesh — отдельный
  будущий epic (SPIRE). `KACHO_IAM_GATEWAY_INTERNAL_TLS_INSECURE` default true;
  поддержан опциональный mTLS (CA/cert/key env) на будущее.

## Поток

```
AccessBinding.Create/Delete (writer-TX) → INSERT subject_change_outbox
  → NOTIFY kacho_iam_subject_outbox_added
  → drainer claims rows (CAS + FOR UPDATE SKIP LOCKED)
  → InternalAuthzCacheService.InvalidateSubject(subject) на api-gateway-internal:9091
  → gateway decisionCache.InvalidateSubject(prefix)
```

## History

- KAC-223 (2026-05-29) — drainer made always-on + required; api-gateway-internal
  Service added; plaintext transport documented. До этого — env-gated, без
  Service → de-facto не работал (poll-fallback нёс нагрузку).

## See also

[[api-gateway-to-iam-subject-change]] [[api-gateway-to-iam-authorize]] [[../resources/iam-access-binding]] [[../KAC/KAC-223]]

#edge #kacho-iam #kacho-apigw #cross-service #authz
