---
title: kacho-nlb/internal/check
aliases:
  - nlb check package
  - nlb authz interceptor
category: packages
repo: kacho-nlb
layer: composition
tags:
  - packages
  - kacho-nlb
  - authz
  - composition-root
  - e3
---

# kacho-nlb/internal/check

Composition-root пакет — превращает corelib `authz`-interceptor в готовую сборку для kacho-nlb: permission map + IAM client adapter + factory. Adopts pattern из kacho-vpc/check + kacho-compute/check.

**Layer**: composition (cmd/kacho-loadbalancer/main.go wiring; импортирует service + corelib + proto-stubs).

## Файлы

- `doc.go` — overview.
- `permission_map.go` — `PermissionMap()` возвращает `authz.RPCMap` со всеми публичными RPC kacho-nlb (~30 записей): NetworkLoadBalancerService (12) + ListenerService (6) + TargetGroupService (9) + OperationService (3).
- `check_client.go` — `IAMCheckClient` (gRPC adapter поверх `iamv1.InternalIAMServiceClient.Check`), реализует port `authz.CheckClient`.
- `factory.go` — `NewInterceptor(Options) (*authz.Interceptor, error)` + sentinel `ErrIAMConnNotConfigured`.
- `drift_test.go` — **обязательный drift-guard test**: enumerates все registered RPC через proto reflection, сверяет с `PermissionMap()`. Любой добавленный RPC без mapping → fail (anti-regression).
- `interceptor_test.go` — unit-tests (allow/deny/unavailable/no-principal/unmapped/internal-bypass/cache-hit/breakglass + factory + ErrNoPath passthrough).

## Семантика permission map

- `Create / List` → `editor / viewer` на `project:<project_id>`.
- `Update / Delete / Start / Stop / Move / Attach / Detach` → `editor` на `<resource_type>:<resource_id>`.
- `AddTargets / RemoveTargets` → `editor` на `nlb_target_group:<id>`.
- `GetTargetStates` → `viewer` на `nlb_load_balancer:<id>`.
- `OperationService.Get/Cancel` → `viewer/editor` на `nlb_operation:<id>`.
- `Internal*` (InternalResourceLifecycleService) — bypass (workspace #6).

## Wiring (cmd/kacho-loadbalancer/main.go)

```go
authzIntr, err := check.NewInterceptor(check.Options{
    ServiceName: "kacho-nlb",
    IAMConn:     authzConn,   // gRPC к kacho-iam:9091
    Breakglass:  cfg.AuthZ.Breakglass,
    Logger:      logger,
})
if authzIntr != nil {
    publicUnary = append(publicUnary, authzIntr.Unary())
    publicStream = append(publicStream, authzIntr.Stream())
}
```

Internal :9091 listener — БЕЗ authz-interceptor (admin-only).

## Cache invalidation

LISTEN-invalidate `kacho_iam_subjects` через `ListenInvalidator.Run` (corelib/authz) — wired в main.go. Worst-case revoke ≤10s (TTL 5s + push ≤1s + drain ≤2s).

## Imports

- `kacho-corelib/authz` — `Interceptor`, `RPCMap`, `Cache`, `StaticExtractor`, `CheckClient`, `ErrNoPath`.
- `kacho-proto/gen/go/kacho/cloud/iam/v1` — `InternalIAMServiceClient`, `CheckRequest`.
- `kacho-proto/gen/go/kacho/cloud/loadbalancer/v1` — request stubs для extractor'ов.
- `kacho-proto/gen/go/kacho/cloud/operation` — `OperationService` request stubs.

## See also

[[corelib-authz]] [[../edges/nlb-to-iam-check]] [[nlb-permissions-catalog]] [[../KAC/KAC-108]] [[../KAC/KAC-141]]

#packages #kacho-nlb #authz #composition-root #e3
