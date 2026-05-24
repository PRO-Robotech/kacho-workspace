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
status: active
related_tickets:
  - "[[KAC-141]]"
  - "[[KAC-158]]"
  - "[[KAC-108]]"
tags:
  - edge
  - kacho-nlb
  - kacho-iam
  - cross-service
  - fga
  - d11
---

> [!success] Active since 2026-05-24 (KAC-141, kacho-nlb PR#11)
> Edge активен; на каждом Create-worker'е nlb sync-вызывает `kacho-iam.InternalIAMService.WriteCreatorTuple` для записи hierarchy tuple (D-11 pattern).

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
