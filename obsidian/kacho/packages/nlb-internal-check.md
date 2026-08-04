---
title: kacho-nlb/internal/check
aliases:
  - nlb check package
  - nlb authz interceptor
category: packages
path: services/nlb/internal/check
repo: kacho-nlb
layer: composition
tags:
  - packages
  - kacho-nlb
  - authz
  - composition-root
  - e3
status: stable
verified_against: "каталог пакета есть в дереве продукта b4edc5d5 (2026-08-05); текст записки построчно не пересматривался"
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
- `Internal*` (InternalResourceLifecycleService) — **тоже в карте**; пропуск Check
  выдаётся записью (`Public=false`/`ScopeFiltered`), а не выводится из имени метода.
  Незамапленный RPC отказывает (см. [[corelib-authz]] §Decision pipeline). `drift_test.go`
  это и держит: RPC без записи роняет сборку.

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

Internal-листенер собирается **той же** цепочкой, что публичный: `wiring.go` строит две
цепочки, и `authzIntr.Unary()`/`.Stream()` стоят в обеих.

> [!important] «Internal = trusted, mTLS достаточно» — запрещённое допущение
> mTLS доказывает ровно одно: пир предъявил сертификат нашего CA. Он не говорит, **кто**
> вызывающий и **на что** у него право, поэтому сам по себе не заменяет per-RPC Check.
> Ban #6 сужает **поверхность методов**, а не снимает проверку прав на внутреннем порту.
> См. `security.md` §«AuthN+AuthZ ВЕЗДЕ», п. 2 и 4, и [[corelib-authz]].

## Cache invalidation

LISTEN-invalidate `kacho_iam_subjects` через `ListenInvalidator.Run` (corelib/authz) — wired в main.go. Worst-case revoke ≤10s (TTL 5s + push ≤1s + drain ≤2s).

## Imports

- `kacho-corelib/authz` — `Interceptor`, `RPCMap`, `Cache`, `StaticExtractor`, `CheckClient`, `ErrNoPath`.
- `github.com/PRO-Robotech/kacho/pkg/api/kacho/cloud/iam/v1` — `InternalIAMServiceClient`, `CheckRequest`.
- `github.com/PRO-Robotech/kacho/pkg/api/kacho/cloud/loadbalancer/v1` — request stubs для extractor'ов.
- `github.com/PRO-Robotech/kacho/pkg/api/kacho/cloud/operation` — `OperationService` request stubs.

## See also

[[corelib-authz]] [[../edges/nlb-to-iam-check]] [[nlb-permissions-catalog]] [[../KAC/KAC-108]] [[../KAC/KAC-141]]

#packages #kacho-nlb #authz #composition-root #e3
