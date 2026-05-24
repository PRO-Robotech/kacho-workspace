---
title: kacho-nlb/internal/fgawrite
aliases:
  - nlb fgawrite
  - nlb hierarchy tuple writer
category: packages
repo: kacho-nlb
layer: composition
tags:
  - packages
  - kacho-nlb
  - fga
  - d11
  - composition-root
---

# kacho-nlb/internal/fgawrite

D-11 sync hierarchy tuple writer для kacho-nlb. Wraps `kacho-iam.InternalIAMService.WriteCreatorTuple` в типизированные helpers, которые вызываются из Create UseCase worker'ов.

**Layer**: composition (импортирует kacho-proto stubs + corelib/retry).

## Файлы

| File | Содержание |
|---|---|
| `doc.go` | overview + D-11 pattern reference (KAC-108) |
| `emitter.go` | `Emitter` interface + `iamEmitter` impl (gRPC adapter) |
| `noop.go` | `NoopEmitter` для dev/test без iam |
| `factory.go` | `New(Options)` с retry + LRU subject-cache |
| `emitter_test.go` | unit-tests (success/retry/noop/cache hit) |

## Interface

```go
type Emitter interface {
    EmitLoadBalancerCreated(ctx context.Context, lbID, projectID string) error
    EmitListenerCreated(ctx context.Context, listenerID, lbID, projectID string) error
    EmitTargetGroupCreated(ctx context.Context, tgID, projectID string) error
    EmitResourceDeleted(ctx context.Context, objectType, objectID string) error
}
```

## Usage в Create workers

```go
// internal/apps/kacho/api/loadbalancer/create.go (worker stage)
if err := uc.fga.EmitLoadBalancerCreated(ctx, lb.ID, lb.ProjectID); err != nil {
    uc.logger.Warn("fga emit failed; rely on D-13 lifecycle subscribe", "err", err)
    // non-fatal: D-13 stream (iam → nlb subscribe) catches up
}
```

## Non-fatal failure mode

iam недоступен → log WARN + continue. Worker НЕ возвращает error пользователю (нельзя блокировать success на FGA). Safety-net = [[../edges/iam-to-nlb-resource-lifecycle]] D-13 subscribe — iam catches up на reconnect.

## Imports

- `kacho-proto/gen/go/kacho/cloud/iam/v1` — `InternalIAMServiceClient.WriteCreatorTuple`.
- `kacho-corelib/authz` — port `CreatorTupleWriter`.
- `kacho-corelib/retry` — `OnUnavailable` wrapper.

## See also

[[../edges/nlb-to-iam-creator-tuple]] [[corelib-authz]] [[../KAC/KAC-108]] [[../KAC/KAC-141]]

#packages #kacho-nlb #fga #d11 #composition-root
