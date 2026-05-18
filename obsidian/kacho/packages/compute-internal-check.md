---
title: "kacho-compute/internal/check"
aliases:
  - compute check package
  - compute authz interceptor
category: packages
repo: kacho-compute
layer: composition
tags:
  - packages
  - kacho-compute
  - authz
  - composition-root
  - e3
---

# kacho-compute/internal/check

Composition-root пакет — обёртка corelib `authz`-interceptor под kacho-compute:
permission map + IAM client adapter + factory.

**Layer:** composition (импортирует corelib + proto-stubs).

## Файлы

- `doc.go` — overview.
- `permission_map.go` — `PermissionMap()` возвращает `authz.RPCMap` со всеми
  публичными RPC kacho-compute (40+ записей): Disk / Image / Snapshot /
  Instance (lifecycle-heavy: Start/Stop/Restart/Attach*/Detach*/AddOneToOneNat/…) /
  DiskType / Zone / Region + Operation.
- `check_client.go` — `IAMCheckClient` (gRPC adapter поверх
  `iamv1.InternalIAMServiceClient.Check`).
- `factory.go` — `NewInterceptor(Options) (*authz.Interceptor, error)`.
- `interceptor_test.go` — 11 unit-тестов (allow/deny/unavailable/no-principal/
  unmapped/internal-bypass/cache-hit/breakglass + system-catalog routing + factory).

## Семантика permission map

- `Create / List`               → `editor / viewer` на `project:<project_id>`.
- `Update / Delete / Start / Stop / Restart / Attach*/Detach*/<verb>`
                                → `editor` на `<resource_type>:<resource_id>`.
- `DiskType.Get/List`, `Zone.Get/List`, `Region.Get/List`
                                → `viewer` на `system:catalog`
  (well-known FGA object; E3 модель выдаёт всем authenticated principal'ам
  `viewer on system:catalog` неявно).
- `OperationService.Get/Cancel` → `viewer / editor` на `compute_operation:<id>`.
- `Internal*` RPC — bypass (heuristic в corelib/authz).

## Object types

`compute_disk`, `compute_image`, `compute_snapshot`, `compute_instance`,
`compute_operation`, `system`, `project`.

## Wiring

```go
// cmd/compute/main.go
authzIntr, err := check.NewInterceptor(check.Options{
    ServiceName: "kacho-compute",
    IAMConn:     authzConn,   // gRPC к kacho-iam:9091
    Breakglass:  cfg.AuthZBreakglass,
    Logger:      logger,
})
if authzIntr != nil {
    publicUnary = append(publicUnary, authzIntr.Unary())
    publicStream = append(publicStream, authzIntr.Stream())
}
```

Internal :9091 listener — БЕЗ authz-interceptor'а (admin-only, запрет workspace #6).

## Config

- `KACHO_COMPUTE_AUTHZ_IAM_GRPC_ADDR` (default `""` → graceful skip)
- `KACHO_COMPUTE_AUTHZ_IAM_TLS`
- `KACHO_COMPUTE_AUTHZ_BREAKGLASS` (dev/emergency)

## Scope-guard (KAC-108 MVP)

- LISTEN-invalidate `kacho_iam_subjects` НЕ wired; revoke ≤10s = TTL=5s + outbox-drain ≤2s.

## Imports

- `github.com/PRO-Robotech/kacho-corelib/authz`
- `github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/iam/v1` (InternalIAMServiceClient).
- `github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/compute/v1` (request stubs).
- `github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/operation`.

## See also

[[corelib-authz]] [[vpc-apps-kacho-check]] [[../edges/compute-to-iam-check]] [[../KAC/KAC-108]]

#packages #kacho-compute #authz #composition-root #e3
