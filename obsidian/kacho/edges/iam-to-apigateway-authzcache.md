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
status: superseded
related_tickets:
  - "[[KAC-223]]"
tags:
  - edge
  - kacho-iam
  - kacho-apigw
  - cross-service
  - authz
verified_against: "перемерено 2026-08-29 на линии `release/watch-2` (f205e60c2) против ствола `origin/main`: прод-файлов iam, знающих контракт края, — на стволе 3, на линии 0; контракта `proto/kacho/cloud/apigateway/v1/internal_authz_cache_service.proto` на линии нет; принимающего обработчика края и его опросчика на линии нет. Историческая часть записки (KAC-223 и ниже) верна как прошлое и не переписывалась"
---

> [!warning] МЕХАНИЗМ СНЯТ линией `release/watch-2` — записка верна как ПРОШЛОЕ
> Толчок из iam в край был **обратным ребром**: владелец звонил потребителю. Это
> единственное место, где лист iam переставал быть листом, и эпик
> [[KAC/issue-1016]] снял его вместе с введением единой подписки — задача
> [[KAC/issue-1024]] («край сам открывает поток — снять обратный вызов к нему»).
>
> **Что именно снято** (перемерено 2026-08-29, линия `f205e60c2` против `origin/main`):
>
> | предмет | ствол | линия |
> |---|---:|---:|
> | прод-файлы iam, знающие контракт края | 3 | **0** |
> | контракт `internal_authz_cache_service.proto` | есть | **нет** |
> | принимающий обработчик края | есть | **нет** |
> | опросчик края `gateway/internal/watcher/` | есть | **нет** |
>
> Метод стоит в надгробии снятой поверхности
> (`internal/repohygiene/retiredrpcsurface_test.go`), то есть его отсутствие
> **удержано гейтом**, а не памятью.
>
> **Чем заменено — направлением, а не другим толчком.** Сброс кэша решений край
> получает, **сам** спрашивая владельца (`InternalIAMService.PollSubjectChanges`,
> общий механизм `pkg/subjectchange`); поток изменений ресурсов край **сам**
> открывает у владельца журнала — [[edges/apigw-to-owner-subscription-stream]].
> Оба направления «потребитель → владелец», и ацикличность цела.
>
> **В стволе механизм ещё живёт**: MR PRO-Robotech/kacho#1457 открыт и не влит.
> Пока он не влит, всё ниже описывает действующее состояние `origin/main`.

> [!note] Две записки об ОДНОМ предмете — эта каноническая, соседняя историческая
> Соседняя — [[edges/iam-to-apigw-cache-invalidation]]. Обе теперь описывают снятый
> механизм; канон остаётся здесь.

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

## См. также — куда ушёл предмет

[[edges/apigw-to-owner-subscription-stream]] (заменившее направление) · [[KAC/issue-1024]] · [[KAC/issue-1016]] · [[KAC/watch-unified-change-stream-2026-08]]

## See also

[[api-gateway-to-iam-subject-change]] [[api-gateway-to-iam-authorize]] [[../resources/iam-access-binding]] [[../KAC/KAC-223]]

#edge #kacho-iam #kacho-apigw #cross-service #authz
