---
title: "nlb → iam: D-11 sync creator-tuple write (fgawrite)"
aliases:
  - nlb creator tuple
  - nlb to iam fgawrite
category: edge
caller_repo: kacho-nlb
callee_repo: kacho-iam
sync_async: sync
protocol: grpc-cluster-internal
status: deprecated
related_tickets:
  - "[[KAC-141]]"
  - "[[KAC-158]]"
  - "[[KAC-108]]"
  - "[[SEC-D-services-fga-via-iam-mtls]]"
tags:
  - edge
  - kacho-nlb
  - kacho-iam
  - cross-service
  - fga
  - d11
---

> [!warning] Deprecated by SEC-D (2026-06-11) → [[nlb-to-iam-fga-register]]
> Прямой best-effort `WriteCreatorTuple` после commit (GitHub Issue N5: при сбое FGA tuple терялся навсегда → per-resource Check DENY). SEC-D заменил его транзакционным outbox: owner-tuple intent пишется в той же writer-tx, что и INSERT/DELETE ресурса, и применяется register-drainer'ом через `RegisterResource`/`UnregisterResource` по mTLS (intent durable, IAM-down → retry). пакет прямой записи кортежей удалён из nlb; `InternalIAMService.WriteCreatorTuple` больше не вызывается ниоткуда (см. примечание ниже). Ниже — историческое описание удалённого пути.

> [!quote] Историческое (до SEC-D)
> Описание ниже относится к удалённому direct-FGA пути и сохранено как trail.

> [!note] RPC пережил своего единственного вызывающего (замер 2026-08-05)
> `InternalIAMService.WriteCreatorTuple` **по-прежнему объявлен** в
> `proto/kacho/cloud/iam/v1/internal_iam_service.proto`, но во всём дереве `96b2879a` его
> не зовёт **никто**: единственные вхождения — сгенерированные gateway-заглушки
> (`pkg/api/.../internal_iam_service.pb.gw.go`). Ровно то же верно для соседних
> `ForceLogout` и `GetRoleCompiled` — у них тоже ноль не-сгенерированных вызывающих.
>
> Это не находка этого ребра, а свойство поверхности: снятие вызывающего не снимает RPC, и
> объявленный метод продолжает выглядеть частью контракта. Прежде чем «переиспользовать»
> любой из трёх — установить, чем он гейтится и что материализует, а не выводить назначение
> из имени. Про то, чем сегодня решается та же задача, — [[nlb-to-iam-fga-register]] и
> [[iam-register-resource-callee-contract]].

> [!warning] Ссылка на подстраховку ниже ведёт в ребро без подписчика
> В разделе про отказ сказано: «D-13 lifecycle subscribe (iam side) catches up». Подписчика
> **нет** — сервер стрима у nlb есть, клиента в iam ноль ([[iam-to-nlb-resource-lifecycle]]).
> То есть подстраховки, на которую ссылалось это описание, не существовало и на момент
> написания; сегодня её роль исполняет durable-намерение + дренаж.

# nlb → iam: D-11 sync creator-tuple write

**Caller**: `kacho-nlb` (пакет прямой записи кортежей — Emit-хелперы; звался из Create-worker'ов; снят)
**Callee**: `kacho-iam.InternalIAMService.WriteCreatorTuple` (port 9091)
**Protocol**: gRPC cluster-internal
**Sync/Async**: **sync** в worker'е (после `ops.MarkDone`, до возврата success)

## When invoked

- `LoadBalancer.Create` worker → `fgawrite.Emit("nlb_load_balancer:<id>#project@project:<project_id>")` (parent tuple).
- `Listener.Create` worker → 2 tuples: `nlb_listener:<id>#project@project:<pid>` + `nlb_listener:<id>#load_balancer@nlb_load_balancer:<lb_id>`.
- `TargetGroup.Create` worker → `nlb_target_group:<id>#project@project:<pid>`.

## D-11 pattern (KAC-108)

Sync hierarchy tuple write **в worker'е**, после успешного DB-commit. Гарантирует, что parent-tuple существует прежде, чем client опрашивает `Operation.done=true` и пытается читать ресурс через FGA Check.

ErrNoPath race-window минимизируется до zero (sync), но не исключён (если fgawrite упал) — see passthrough в [[nlb-to-iam-check]].

## Helpers (`internal/fgawrite/`)

```go
type Emitter interface {
    EmitLoadBalancerCreated(ctx, lbID, projectID string) error
    EmitListenerCreated(ctx, listenerID, lbID, projectID string) error
    EmitTargetGroupCreated(ctx, tgID, projectID string) error
    EmitResourceDeleted(ctx, objectType, objectID string) error
}
```

Implements corelib `authz.CreatorTupleWriter` port. Gracefully retries via `corelib/retry.OnUnavailable`.

## Error handling

| Result | gRPC code in worker | Note |
|---|---|---|
| tuple written | (continue) | success |
| iam недоступен | log WARN + ops.MarkDone success | **non-fatal**; D-13 lifecycle subscribe (iam side) catches up |
| invalid object_type | log ERR + ops.MarkDone success | drift-guard, alert |

## Delete path

На Delete worker'ах — `EmitResourceDeleted(...)` (idempotent delete tuple), но primary safety-net = [[iam-to-nlb-resource-lifecycle]] D-13 subscribe (iam consumes outbox → cleanup tuples).

## See also

[[../packages/nlb-internal-fgawrite]] [[../packages/corelib-authz]] [[nlb-to-iam-check]] [[iam-to-nlb-resource-lifecycle]] [[../KAC/KAC-108]] [[../KAC/KAC-141]]

#edge #kacho-nlb #kacho-iam #cross-service #fga #d11
