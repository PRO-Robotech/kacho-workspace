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
> Прямой best-effort `WriteCreatorTuple` после commit (GitHub Issue N5: при сбое FGA tuple терялся навсегда → per-resource Check DENY). SEC-D заменил его транзакционным outbox: owner-tuple intent пишется в той же writer-tx, что и INSERT/DELETE ресурса, и применяется register-drainer'ом через `RegisterResource`/`UnregisterResource` по mTLS (intent durable, IAM-down → retry). `internal/fgawrite/` удалён; `InternalIAMService.WriteCreatorTuple` больше не вызывается из nlb. Ниже — историческое описание удалённого пути.

> [!quote] Историческое (до SEC-D)
> Описание ниже относится к удалённому direct-FGA пути и сохранено как trail.

# nlb → iam: D-11 sync creator-tuple write

**Caller**: `kacho-nlb` (`internal/fgawrite/` — Emit helpers; вызывается из Create UseCase worker'ов)
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
